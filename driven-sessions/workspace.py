#!/usr/bin/env python3
"""GPL-2.0-or-later. Real GTK session, no guest or privileged operation.

Run: xvfb-run -a python3 driven-sessions/workspace.py [binary] [--screenshots DIR]
Graphviz alone is wrapped to measure starts and inject delay/partial failure.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", nargs="?", default=str(ROOT / "_build/default/bin/marionnet.exe"))
parser.add_argument("--screenshots", type=Path)
args = parser.parse_args()
if not os.environ.get("DISPLAY") or not all(shutil.which(t) for t in ("dot", "xdotool")):
    print("SKIP: DISPLAY, dot and xdotool required (use xvfb-run -a)")
    sys.exit(77)


def wait_for(predicate, description, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("Timed out: " + description)


def check(condition, description):
    assert condition, description
    print("PASS: " + description, flush=True)


with tempfile.TemporaryDirectory(prefix="marionnet-workspace-") as directory:
    fixture = Path(directory)
    tools = fixture / "tools"
    tools.mkdir()
    run = fixture / "run"
    run.mkdir()
    real_dot = shutil.which("dot")
    wrapper = tools / "dot"
    wrapper.write_text(f"#!{sys.executable}\n" + r'''
import json, os, pathlib, subprocess, sys, time
fixture = pathlib.Path(os.environ["MARIONNET_WORKSPACE_BENCH"])
arguments = sys.argv[1:]
if "-Tpng" not in arguments:
    os.execv(os.environ["MARIONNET_WORKSPACE_REAL_DOT"], ["dot"] + arguments)
source = pathlib.Path(arguments[-1]).read_text()
with (fixture / "renders.jsonl").open("a") as log:
    log.write(json.dumps({"source": source, "output": arguments[arguments.index("-o") + 1]}) + "\n")
if (fixture / "block").exists():
    (fixture / "blocked").touch()
    deadline = time.monotonic() + 20
    while (fixture / "block").exists() and time.monotonic() < deadline:
        time.sleep(0.05)
if (fixture / "fail").exists():
    pathlib.Path(arguments[arguments.index("-o") + 1]).write_bytes(b"partial PNG")
    print("simulated Graphviz failure after partial output", file=sys.stderr)
    sys.exit(2)
sys.exit(subprocess.call([os.environ["MARIONNET_WORKSPACE_REAL_DOT"]] + arguments))
''')
    wrapper.chmod(0o700)
    sock = fixture / "control.sock"
    env = dict(os.environ, PATH=str(tools) + ":" + os.environ["PATH"],
               MARIONNET_WORKSPACE_BENCH=str(fixture), MARIONNET_WORKSPACE_REAL_DOT=real_dot,
               MARIONNET_TMPDIR=str(run), MARIONNET_LANG="fr", LC_ALL="C", LANGUAGE="C")
    log_path = fixture / "application.log"
    with log_path.open("w") as log:
        app = subprocess.Popen([str(Path(args.binary).resolve()), "--debug", "--no-welcome",
                                "--control-socket", str(sock)], cwd=ROOT, env=env,
                               stdout=log, stderr=log)

    def ask(command):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(35)
            connection.connect(str(sock))
            connection.sendall((command + "\n").encode())
            data = b""
            while b"\n" not in data:
                part = connection.recv(65536)
                if not part:
                    break
                data += part
        reply = json.loads(data.split(b"\n")[0])
        assert reply.get("ok"), (command, reply)
        return reply

    def renders():
        path = fixture / "renders.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def drawing():
        files = list(run.glob("**/sketch.png"))
        return files[0] if files else None

    def xdo(*words):
        return subprocess.check_output(["xdotool", *map(str, words)], text=True).strip()

    def window():
        # The title always ends with the application's title, including the dirty marker.
        return xdo("search", "--onlyvisible", "--pid", app.pid, "--name", "[Mm]arionnet").splitlines()[0]

    def title():
        return xdo("getwindowname", window())

    def screenshot(name):
        if args.screenshots:
            args.screenshots.mkdir(parents=True, exist_ok=True)
            xdo("mousemove", "0", "0")
            time.sleep(0.5)  # Dismiss hover tooltips before capturing the workspace.
            subprocess.run(["import", "-window", window(), str(args.screenshots / (name + ".png"))], check=True)

    def chooser(expected, gesture):
        xdo("windowfocus", "--sync", window())
        gesture()
        def find_dialog():
            result = subprocess.run(["xdotool", "search", "--onlyvisible", "--pid", str(app.pid),
                                     "--name", "^" + re.escape(expected) + "$"], capture_output=True, text=True)
            return result.stdout.strip() if result.returncode == 0 else None
        dialog = wait_for(find_dialog, expected)
        xdo("windowfocus", "--sync", dialog.splitlines()[0])
        xdo("key", "--clearmodifiers", "Escape")
        time.sleep(0.2)

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def geometry_fits():
        geometry = dict(line.split("=", 1) for line in xdo("getwindowgeometry", "--shell", window()).splitlines())
        width, height = map(int, xdo("getdisplaygeometry").split())
        return int(geometry["WIDTH"]) <= width and int(geometry["HEIGHT"]) <= height

    try:
        wait_for(lambda: sock.exists() or app.poll() is not None, "control socket", timeout=30)
        assert app.poll() is None, log_path.read_text()
        ask("status")
        time.sleep(0.5)
        check(geometry_fits(), "the workspace fits the available screen")
        screenshot("welcome")
        locales = json.loads((ROOT / "bin/locales/fr.json").read_text())
        new_title = locales["Name of the new project"]
        open_title = locales["Open a project"]
        xdo("windowfocus", "--sync", window())
        chooser(new_title, lambda: xdo("key", "--clearmodifiers", "ctrl+n"))
        check(True, "Ctrl+N opens New project rather than Add NAT bridge")
        chooser(open_title, lambda: xdo("key", "--clearmodifiers", "ctrl+o"))
        check(True, "Ctrl+O opens the project chooser")
        chooser(new_title, lambda: (xdo("mousemove", "--window", window(), "40", "55"), xdo("click", "1")))
        chooser(open_title, lambda: (xdo("mousemove", "--window", window(), "130", "55"), xdo("click", "1")))
        check(True, "the New and Open toolbar buttons use the project dialogs")
        target = fixture / "TP d'aujourd'hui (réseau).mar"
        ask("new --timeout=30 " + str(target))
        ask("add hub h1 --ports=8")
        wait_for(drawing, "first drawing with a quoted project path")
        wait_for(lambda: "•" in title(), "dirty title")
        check(True, "special project paths render and unsaved changes are visible")

        # The same persistent label still triggers a refresh, but needs no new PNG.
        ask("set h1 label Stable")
        wait_for(lambda: "Stable" in drawing().with_suffix(".dot").read_text(), "updated label")
        count = len(renders())
        for _ in range(5):
            ask("set h1 label Stable")
            time.sleep(0.2)
        check(len(renders()) == count, "unchanged drawings launch no new Graphviz process")

        # A keyboard save uses the exact same flow as the existing Project menu.
        xdo("windowfocus", "--sync", window())
        xdo("key", "--clearmodifiers", "ctrl+s")
        wait_for(lambda: target.exists() and ask("status")["saved"], "Ctrl+S save")
        wait_for(lambda: "•" not in title(), "clean title after save")
        check(True, "Ctrl+S saves and clears the unsaved marker")

        # The visible Save button must also work, with a real click (not a direct callback).
        ask("set h1 label Clicked")
        wait_for(lambda: "•" in title(), "dirty title before button save")
        xdo("mousemove", "--window", window(), "205", "55")
        xdo("click", "1")
        wait_for(lambda: ask("status")["saved"], "Save button")
        check(True, "the toolbar Save button writes the project")

        ask("add hub h2 --ports=8")
        ask("connect c1 h1:port1 h2:port1")
        wait_for(lambda: 'h2' in drawing().with_suffix(".dot").read_text(), "second hub")
        time.sleep(0.5)
        check(geometry_fits(), "a rendered network keeps the window within the screen")
        screenshot("network")
        if args.screenshots:
            # Exercise the right sidebar and retain the view of its lower controls.
            # Wheels hit its scrollbar edge, away from editable scale widgets.
            geometry = dict(line.split("=", 1) for line in xdo("getwindowgeometry", "--shell", window()).splitlines())
            original_drawing = digest(drawing())
            xdo("mousemove", "--window", window(), int(geometry["WIDTH"]) - 4, "300")
            xdo("click", "--repeat", "8", "--delay", "50", "5")
            screenshot("graph-controls")
            check(digest(drawing()) == original_drawing, "scrolling the graph controls does not modify the network drawing")
            xdo("mousemove", "--window", window(), int(geometry["WIDTH"]) - 4, "300")
            xdo("click", "--repeat", "20", "--delay", "50", "4")

        # A deliberately slow render leaves GTK responsive. Several updates collapse
        # into one final job after it: the intermediate snapshots must never publish.
        (fixture / "block").touch()
        start = len(renders())
        ask("set h1 label Blocked")
        wait_for(lambda: (fixture / "blocked").exists(), "blocked render")
        t0 = time.monotonic()
        check(ask("status")["active"] and time.monotonic() - t0 < 2,
              "GTK responds while Graphviz is blocked")
        for index in range(12):
            ask(f"set h1 label Burst{index}")
        time.sleep(0.3)
        (fixture / "block").unlink()
        wait_for(lambda: 'Burst11' in drawing().with_suffix(".dot").read_text(), "latest snapshot")
        check(len(renders()) - start == 2, "12 rapid edits require only the blocked job and latest drawing")

        before = digest(drawing())
        (fixture / "fail").touch()
        ask("set h1 label Failed")
        wait_for(lambda: "simulated Graphviz failure" in log_path.read_text(), "render error")
        check(digest(drawing()) == before, "partial Graphviz failure preserves the last valid drawing")
        (fixture / "fail").unlink()
        # Dismiss the genuine error dialog if it remains open.
        xdo("key", "--clearmodifiers", "Escape")
        ask("set h1 label Recovered")
        wait_for(lambda: 'Recovered' in drawing().with_suffix(".dot").read_text(), "render retry")
        check(True, "drawing recovers after a render failure")

        # Close and reopen while the old worker is still busy. A completed old job
        # cannot replace the new project's drawing or resurrect a closed project.
        (fixture / "blocked").unlink()
        (fixture / "block").touch()
        ask("set h1 label Obsolete")
        wait_for(lambda: (fixture / "blocked").exists(), "old project render")
        ask("close --no-save --timeout=30")
        second = fixture / "second.mar"
        ask("new --timeout=30 " + str(second))
        ask("add hub final --ports=8")
        time.sleep(0.3)
        (fixture / "block").unlink()
        wait_for(lambda: drawing() and 'final' in drawing().with_suffix(".dot").read_text(), "new project drawing")
        check('Obsolete' not in drawing().with_suffix(".dot").read_text(), "old project renders never overwrite the new project")
        ask("close --no-save --timeout=30")
        check(not ask("status")["active"], "closing restores the empty workspace")
        wait_for(lambda: not list(run.glob("**/.marionnet-sketch-*")), "temporary drawing cleanup")
    except Exception:
        print(log_path.read_text()[-8000:], file=sys.stderr)
        raise
    finally:
        # Marionnet creates an isolated session and can fork an X11 relay. Stop
        # this child's group only after verifying that isolation, to leave no relay
        # pointing at the Xvfb display which is about to disappear.
        if app.poll() is None:
            if os.getsid(app.pid) == app.pid:
                os.killpg(app.pid, signal.SIGKILL)
            else:
                app.kill()
        app.wait(timeout=10)
