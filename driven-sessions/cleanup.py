#!/usr/bin/env python3
"""Real recovery button, shutdown ordering, and no repeated startup warning.

Run: xvfb-run -a python3 driven-sessions/cleanup.py
Needs xdotool; no guests, privileged commands or changes to real project files.
"""
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def xdo(*args):
    return subprocess.check_output(['xdotool', *map(str, args)], text=True).strip()


def wait(check):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError('timed out waiting for GUI')


with tempfile.TemporaryDirectory(prefix='marionnet-recovery-') as temporary:
    fixture = Path(temporary)
    run = fixture / 'run'
    run.mkdir()
    abandoned = run / 'marionnet-100.dir'
    (abandoned / 'project').mkdir(parents=True)
    (abandoned / 'project/version').write_text('recoverable work')
    old = time.time() - 7200
    os.utime(abandoned, (old, old))
    env = dict(os.environ, MARIONNET_TMPDIR=str(run), TMPDIR=str(run),
               MARIONNET_NO_AUTO_UPDATE='true', MARIONNET_LANG='en',
               MARIONNET_CLEANUP_SCRIPT=str(ROOT / 'bin/scripts/marionnet-cleanup'),
               MARIONNET_PREFIX=str(ROOT / '_build/install/default/share/marionnet'))

    def launch(log):
        return subprocess.Popen([str(ROOT / '_build/default/bin/marionnet.exe'),
                                 '--debug', '--no-welcome'], cwd=fixture, env=env,
                                start_new_session=True, stdout=log, stderr=log)

    def windows(app):
        result = subprocess.run(['xdotool', 'search', '--onlyvisible', '--pid', str(app.pid)],
                                capture_output=True, text=True)
        return {xdo('getwindowname', window): window for window in result.stdout.splitlines()}

    with (fixture / 'first.log').open('w') as log:
        app = launch(log)
        try:
            warning = wait(lambda: windows(app).get('Warning'))
            main = windows(app)['Marionnet']
            geometry = dict(line.split('=', 1) for line in
                            xdo('getwindowgeometry', '--shell', warning).splitlines())
            xdo('mousemove', '--window', warning, 125, int(geometry['HEIGHT']) - 20, 'click', '1')
            # Immediately quit while the subprocess is still scanning /proc.
            xdo('windowfocus', main, 'key', 'ctrl+q')
            app.wait(timeout=45)
            assert app.returncode == 0
            assert not abandoned.exists(), 'normal exit interrupted cleanup'
            archives = list(fixture.glob('recovered-project.*.mar'))
            assert len(archives) == 1
            with tarfile.open(archives[0]) as archive:
                assert archive.extractfile('project/version').read() == b'recoverable work'
            print('PASS: recovery finishes before normal shutdown; unsaved work preserved', flush=True)
        finally:
            if app.poll() is None:
                app.kill()
                app.wait()

    # A recent working copy must also be spared without causing a false warning.
    recent = run / 'marionnet-101.dir'
    recent.mkdir()
    with (fixture / 'second.log').open('w') as log:
        app = launch(log)
        try:
            main = wait(lambda: windows(app).get('Marionnet'))
            wait(lambda: 'The task "cleanup" succeeded' in (fixture / 'second.log').read_text())
            assert 'Warning' not in windows(app)
            assert recent.exists()
            xdo('windowfocus', main, 'key', 'ctrl+q')
            app.wait(timeout=45)
            print('PASS: restart has no warning; recent directory remains intact', flush=True)
        finally:
            if app.poll() is None:
                app.kill()
                app.wait()
