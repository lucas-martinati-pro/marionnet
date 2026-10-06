#!/usr/bin/env python3
"""GPL-2.0-or-later. Exercise useful errors in real GTK, without guests or root.
Run: xvfb-run -a python3 driven-sessions/errors.py
Requires Xvfb, xdotool and xclip; ImageMagick import for screenshots.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--screenshots', type=Path)
parser.add_argument('--binary', type=Path, default=Path(__file__).resolve().parent.parent / '_build/default/bin/marionnet.exe')
args = parser.parse_args()
required = ['Xvfb', 'xvfb-run', 'xdotool', 'xclip', 'dot', 'tar'] + (['import'] if args.screenshots else [])
missing = [command for command in required if not shutil.which(command)]
if missing:
    print('SKIP: missing ' + ', '.join(missing))
    sys.exit(77)
if os.environ.get('MARIONNET_ERRORS_TEST_XVFB') != '1':
    env = dict(os.environ, MARIONNET_ERRORS_TEST_XVFB='1', GDK_BACKEND='x11')
    sys.exit(subprocess.call(['xvfb-run', '-a', '-s', '-screen 0 1024x768x24',
                             sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]], env=env))
if args.screenshots:
    args.screenshots.mkdir(parents=True, exist_ok=True)

ROOT = Path(__file__).resolve().parent.parent
locale = json.loads((ROOT / 'bin/locales/fr.json').read_text())


def wait(predicate, message):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            print('PASS:', message, flush=True)
            return value
        time.sleep(.05)
    raise AssertionError(message)


with tempfile.TemporaryDirectory(prefix='marionnet-errors-') as tmp:
    fixture = Path(tmp)
    run = fixture / 'run'
    run.mkdir()
    commands = fixture / 'commands'
    commands.mkdir()
    diagnostic = 'Test diagnostic <réseau> & disque\n' + 'long detail ' * 700
    for command in ('dot', 'tar'):
        executable = shutil.which(command)
        assert executable, command
        wrapper = commands / command
        marker = fixture / (command + '.fail')
        wrapper.write_text('#!/usr/bin/python3\nimport os,sys\nfrom pathlib import Path\n'
                           + f'if Path({str(marker)!r}).exists():\n'
                           + f'    sys.stderr.write({diagnostic!r}); sys.exit(1)\n'
                           + f'os.execv({executable!r}, [{command!r}] + sys.argv[1:])\n')
        wrapper.chmod(0o700)
    sock = fixture / 'control.sock'
    log_path = fixture / 'application.log'
    env = dict(os.environ, MARIONNET_LANG='fr', MARIONNET_SHOW_SPLASH='false',
               MARIONNET_TMPDIR=str(run),
               MARIONNET_PREFIX=str(ROOT / '_build/install/default/share/marionnet'),
               PATH=str(commands) + ':' + os.environ['PATH'])
    with log_path.open('w') as log:
        app = subprocess.Popen([str(args.binary.resolve()), '--debug',
                                '--no-welcome', '--control-socket', str(sock), '--dialog-timeout=60000'],
                               env=env, cwd=ROOT, stdout=log, stderr=log, start_new_session=True)

    def ask(command, successful=True):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(40)
            connection.connect(str(sock))
            connection.sendall((command + '\n').encode())
            data = b''
            while b'\n' not in data:
                part = connection.recv(65536)
                assert part
                data += part
        reply = json.loads(data.split(b'\n')[0])
        if successful:
            assert reply.get('ok'), (command, reply)
        return reply

    def xdo(*words):
        return subprocess.check_output(['xdotool', *map(str, words)], text=True).strip()

    def error_window():
        result = subprocess.run(['xdotool', 'search', '--all', '--onlyvisible', '--pid', str(app.pid),
                                 '--name', '^' + locale['label.error'] + '$'], capture_output=True, text=True)
        return result.stdout.splitlines()

    def bounds(window):
        return dict(line.split('=', 1) for line in xdo('getwindowgeometry', '--shell', window).splitlines())

    def notification(fragment):
        return next((n for n in ask('notifications')['notifications'] if fragment in n['body']), None)

    try:
        wait(lambda: sock.exists() or app.poll() is not None, 'application starts')
        assert app.poll() is None
        project = fixture / 'projet <réseau> & test.mar'
        ask('new --timeout=30 ' + str(project))
        ask('add hub h1 --ports=8')
        wait(lambda: list(run.glob('**/sketch.png')), 'initial drawing is published')
        png = next(run.glob('**/sketch.png'))
        old_drawing = png.read_bytes()
        ask('save --timeout=30')
        old_archive = hashlib.sha256(project.read_bytes()).hexdigest()
        (fixture / 'dot.fail').touch()
        ask('add hub h2 --ports=8')
        report = wait(lambda: notification('Test diagnostic'), 'render failure keeps its technical diagnostic')
        assert locale['workspace.render_failed'] in report['body']
        assert locale['error.advice.report'] in report['body']
        assert png.read_bytes() == old_drawing
        window = wait(error_window, 'error dialog is visible')[0]
        collapsed = bounds(window)
        assert int(collapsed['WIDTH']) <= 1024 and int(collapsed['HEIGHT']) <= 768
        xdo('windowfocus', '--sync', window)
        xdo('key', '--clearmodifiers', 'shift+Tab', 'space')
        clipboard = subprocess.check_output(['xclip', '-o', '-selection', 'clipboard'], text=True)
        assert 'Test diagnostic <réseau> & disque' in clipboard and '&lt;réseau&gt;' not in clipboard
        assert locale['error.advice.report'] in clipboard
        assert error_window(), 'copying must keep the dialog open'
        print('PASS: copied report is plain text and copying keeps the dialog open', flush=True)
        if args.screenshots:
            subprocess.run(['import', '-window', window, str(args.screenshots / 'error-collapsed.png')], check=True)
        # The details expander is directly above the fixed action row.
        xdo('mousemove', '--window', window, 60, int(collapsed['HEIGHT']) - 46)
        xdo('click', 1)
        time.sleep(.2)
        expanded = bounds(window)
        assert int(expanded['HEIGHT']) > int(collapsed['HEIGHT']), (collapsed, expanded)
        assert int(expanded['WIDTH']) <= 1024 and int(expanded['HEIGHT']) <= 768
        assert 0 <= int(expanded['X']) <= 1024 - int(expanded['WIDTH']), expanded
        assert 0 <= int(expanded['Y']) <= 768 - int(expanded['HEIGHT']), expanded
        if args.screenshots:
            subprocess.run(['import', '-window', window, str(args.screenshots / 'error-expanded.png')], check=True)
        print('PASS: long technical details expand within the screen', flush=True)
        xdo('key', '--clearmodifiers', 'Return')
        wait(lambda: not error_window(), 'Close remains accessible')
        (fixture / 'dot.fail').unlink()
        ask('set h1 label Reprise')
        wait(lambda: png.read_bytes() != old_drawing, 'drawing recovers after the failure')
        ask('notifications --clear')
        (fixture / 'tar.fail').touch()
        result = ask('save --timeout=30', successful=False)
        assert not result['ok'], result
        report = wait(lambda: notification(locale['error.advice.save']), 'save failure offers a concrete remedy')
        assert 'projet &lt;réseau&gt; &amp; test.mar' in report['body'], report
        assert hashlib.sha256(project.read_bytes()).hexdigest() == old_archive
        assert not ask('status')['saved']
        print('PASS: a failed save preserves the previous archive and unsaved marker', flush=True)
        window = wait(error_window, 'save error remains readable')[0]
        xdo('windowfocus', '--sync', window); xdo('key', '--clearmodifiers', 'Return')
        wait(lambda: not error_window(), 'save error closes')
        (fixture / 'tar.fail').unlink()
        ask('close --no-save --timeout=30')
        ask('notifications --clear')
        broken = fixture / 'archive <invalide> & test.mar'
        broken.write_text('not a project archive')
        result = ask('open --timeout=30 ' + str(broken), successful=False)
        assert not result['ok'], result
        report = wait(lambda: notification(locale['error.advice.open']), 'invalid archive gets opening advice and details')
        assert 'archive &lt;invalide&gt; &amp; test.mar' in report['body'], report
        assert 'Failure(' in report['body'] and 'exited with 2' in report['body'], report
        assert 'Failed to set text' not in log_path.read_text(errors='replace')
        assert 'uncaught exception' not in log_path.read_text(errors='replace')
    except Exception:
        print(log_path.read_text(errors='replace')[-12000:])
        raise
    finally:
        if app.poll() is None:
            os.killpg(app.pid, signal.SIGKILL)
        app.wait()
