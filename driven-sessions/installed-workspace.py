#!/usr/bin/env python3
"""GPL-2.0-or-later. Exercise the actual Debian package outside the source tree.

Run: python3 driven-sessions/installed-workspace.py dist/marionnet-all-in-one_VERSION_amd64.deb
No system installation, guest startup or privileged operation is performed.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("package", type=Path)
args = parser.parse_args()
if not all(shutil.which(tool) for tool in ("dpkg-deb", "xvfb-run", "dot", "xdotool")):
    print("SKIP: dpkg-deb, xvfb-run, dot and xdotool required")
    sys.exit(77)

with tempfile.TemporaryDirectory(prefix="marionnet-installed-workspace-") as directory:
    fixture = Path(directory)
    subprocess.run(["dpkg-deb", "-x", str(args.package.resolve()), str(fixture)], check=True)
    prefix = fixture / "usr"
    data = prefix / "share/marionnet"
    # These files were formerly inherited from the old base package. Check the
    # actual archive, then run its GTK interface rather than merely its --version.
    for folder, pattern in (("gui", "*.xml"), ("locales", "*.json"),
                            ("images", "*"), ("share", "*")):
        for source in (ROOT / "bin" / folder).rglob(pattern):
            if source.is_file():
                installed = data / folder / source.relative_to(ROOT / "bin" / folder)
                assert installed.is_file(), f"Missing installed resource: {installed}"
                assert installed.read_bytes() == source.read_bytes(), f"Outdated installed resource: {installed}"
    print("PASS: the Debian archive contains the current interface, translations and images", flush=True)
    binary = prefix / "bin/marionnet"
    assert binary.is_symlink() and os.readlink(binary) == "marionnet.native", binary
    assert (data / "kernels").is_dir() and (data / "filesystems").is_dir(), "Missing guest layers"
    result = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1280x900x24", sys.executable,
                             str(ROOT / "driven-sessions/workspace.py"), str(binary),
                             "--installed-prefix", str(prefix)], cwd=fixture)
    sys.exit(result.returncode)
