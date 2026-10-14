#!/usr/bin/env python3
"""Repackage published releases with a tested kernel; preserve application ELFs.

Inputs must be downloaded release packages. --app-depends is measured with
dpkg-shlibdeps on the oldest supported host, for the latest application's ELF.
No upload, tag creation, or Git operation is performed by this script.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def digest(path, algorithm="sha256"):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def field(control, name, value):
    pattern = rf"^{re.escape(name)}:.*(?:\n[ \t].*)*"
    replacement = f"{name}: {value}"
    if re.search(pattern, control, re.M):
        return re.sub(pattern, replacement, control, flags=re.M)
    return control.rstrip() + "\n" + replacement + "\n"


def build(root, output):
    sums = []
    for path in sorted((root / "usr").rglob("*")):
        if path.is_file() and not path.is_symlink():
            sums.append(f"{digest(path, 'md5')}  {path.relative_to(root)}\n")
    (root / "DEBIAN/md5sums").write_text("".join(sums))
    size = run("du", "-sk", root, capture_output=True, text=True).stdout.split()[0]
    control = root / "DEBIAN/control"
    control.write_text(field(control.read_text(), "Installed-Size", size))
    run("dpkg-deb", "--root-owner-group", "--build", "-Zxz", "-z6", root, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-dir", type=Path, required=True)
    parser.add_argument("--kernel-package", type=Path, required=True)
    parser.add_argument("--base-aio", type=Path, required=True)
    parser.add_argument("--latest-aio", type=Path, required=True)
    parser.add_argument("--app-depends", type=Path, required=True)
    parser.add_argument("--base-release-json", type=Path,
                        help="gh release view --json assets: retain checksums of unchanged assets")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    components = Path(__file__).with_name("release-components.sh")
    settings = run("bash", "-c",
                   'source "$1"; printf "%s\\n" "$KERNEL_I386_NAME" "${KERNEL_VER}-${KERNEL_I386_REVISION}" "$BASE_RELEASE_TAG" "$KERNELS_I386_LEGACY_DEB"',
                   "release-components", components, capture_output=True, text=True).stdout.splitlines()
    name, kernel_version, base_tag, legacy_name = settings
    required = [line for line in (Path(__file__).resolve().parents[1] / "uml/kernel/CONFIG-i386-netfilter").read_text().splitlines() if line.startswith("CONFIG_")]
    actual = (args.kernel_dir / (name + ".config")).read_text().splitlines()
    assert all(line in actual for line in required), "kernel firewall config incomplete"
    abi = run("readelf", "-V", args.kernel_dir / name, capture_output=True, text=True).stdout
    versions = [tuple(map(int, v.split("."))) for v in re.findall(r"Name: GLIBC_([0-9.]+)", abi)]
    assert versions and max(versions) <= (2, 35), "kernel host libc too new"
    base_out = args.output / base_tag
    base_out.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="marionnet-assets-") as work:
        work = Path(work)
        root = work / "kernel"
        run("dpkg-deb", "-R", args.kernel_package, root)
        dest = root / "usr/share/marionnet/kernels"
        for filename in [name, name + ".config"]:
            shutil.copy2(args.kernel_dir / filename, dest / filename)
        control = root / "DEBIAN/control"
        text = field(control.read_text(), "Version", kernel_version)
        text = field(text, "Depends", "marionnet, libc6:i386 (>= 2.34)")
        text = field(text, "Replaces", "marionnet-all-in-one")
        control.write_text(text)
        revised = base_out / f"marionnet-kernels-i386_{kernel_version}_amd64.deb"
        build(root, revised)
        # Existing CI builders fetch this pinned name. Its control metadata has
        # the incremented Debian revision; new split-package installs use it too.
        shutil.copy2(revised, base_out / legacy_name)
        run("tar", "--sort=name", "--owner=0", "--group=0", "--numeric-owner", "-cJf",
            base_out / f"kernels_{name}.tar.xz", "-C", root / "usr/share/marionnet", "kernels")
        for package in [args.base_aio, args.latest_aio]:
            version = run("dpkg-deb", "-f", package, "Version", capture_output=True, text=True).stdout.strip()
            output = args.output / ("v" + version)
            output.mkdir(exist_ok=True)
            aio = work / ("aio-" + version)
            run("dpkg-deb", "-R", package, aio)
            dest = aio / "usr/share/marionnet/kernels"
            for filename in [name, name + ".config"]:
                shutil.copy2(args.kernel_dir / filename, dest / filename)
            # A repeated release number must still be detected by the updater.
            identity = hashlib.sha256((digest(package) + digest(args.kernel_dir / name) + digest(args.app_depends)).encode()).hexdigest()
            for updater in (aio / "usr").rglob("marionnet-update"):
                if updater.is_file() and not updater.is_symlink():
                    source = updater.read_text()
                    source = re.sub(r'^INSTALLED_BUILD_ID="[^"]*"', f'INSTALLED_BUILD_ID="{identity}"', source, flags=re.M)
                    updater.write_text(source)
            control = aio / "DEBIAN/control"
            text = re.sub(r"marionnet-kernels-i386 \(= [^)]+\)", f"marionnet-kernels-i386 (= {kernel_version})", control.read_text())
            if package == args.latest_aio:
                depends = args.app_depends.read_text().strip()
                assert "shlibs:Depends=" not in depends and "libc6" in depends
                text = field(text, "Depends", depends + ", libc6:i386 (>= 2.34)")
            elif "libc6:i386" not in text:
                existing = re.search(r"^Depends: (.*)$", text, re.M).group(1)
                text = field(text, "Depends", existing + ", libc6:i386 (>= 2.34)")
            control.write_text(text)
            build(aio, output / package.name)
            (output / "BUILD_ID").write_text(identity + "\n")
    for directory in args.output.iterdir():
        if directory.is_dir():
            packages = sorted(path for path in directory.iterdir() if path.suffix in [".deb", ".xz"])
            # The AIO must come first: old installers select the first matching AIO.
            checksums = {path.name: digest(path) for path in packages}
            if directory == base_out and args.base_release_json:
                for asset in json.loads(args.base_release_json.read_text())["assets"]:
                    name = asset["name"]
                    if name not in checksums and name not in ["SHA256SUMS", "BUILD_ID"]:
                        sha = asset["digest"].removeprefix("sha256:")
                        assert re.fullmatch(r"[0-9a-f]{64}", sha), f"Missing digest for {name}"
                        checksums[name] = sha
            (directory / "SHA256SUMS").write_text("".join(f"{sha}  {name}\n" for name, sha in sorted(checksums.items())))


if __name__ == "__main__":
    main()
