#!/usr/bin/env python3
"""GPL-2.0-or-later. Real Ctrl+Z/Ctrl+Y gestures, no guest or privileged operation.
Run: xvfb-run -a python3 driven-sessions/undo.py [binary]
"""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
binary = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / '_build/default/bin/marionnet.exe').resolve()

def wait(predicate, message):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if predicate():
            print('PASS:', message, flush=True)
            return
        time.sleep(.05)
    raise AssertionError(message)

with tempfile.TemporaryDirectory(prefix='marionnet-undo-test-') as tmp:
    fixture = Path(tmp)
    run = fixture / 'run'
    run.mkdir()
    sock = fixture / 'control.sock'
    log_path = fixture / 'application.log'
    env = dict(os.environ, MARIONNET_PREFIX=str(ROOT / '_build/install/default/share/marionnet'),
               MARIONNET_TMPDIR=str(run), MARIONNET_LANG='fr', MARIONNET_SHOW_SPLASH='false')
    with log_path.open('w') as log:
        app = subprocess.Popen([str(binary), '--debug', '--no-welcome', '--control-socket', str(sock)],
                               cwd=ROOT, env=env, start_new_session=True, stdout=log, stderr=log)
    def ask(command):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(40)
            connection.connect(str(sock))
            connection.sendall((command + '\n').encode())
            data = b''
            while b'\n' not in data:
                data += connection.recv(65536)
        reply = json.loads(data.split(b'\n')[0])
        assert reply.get('ok'), (command, reply)
        return reply
    def key(value):
        subprocess.run(['xdotool', 'windowfocus', '--sync', window], check=True)
        subprocess.run(['xdotool', 'key', '--clearmodifiers', value], check=True)
        time.sleep(.15)
        wait(lambda: not ask('status')['editing'], value + ' completes')
    def field(name, prop):
        return ask('get ' + name + ' ' + prop)['fields'][prop]
    try:
        wait(lambda: sock.exists() or app.poll() is not None, 'application starts')
        assert app.poll() is None, log_path.read_text()
        window = subprocess.check_output(['xdotool', 'search', '--onlyvisible', '--pid', str(app.pid), '--name', '^Marionnet$'], text=True).splitlines()[0]
        ask('new --timeout=30 ' + str(fixture / 'undo.mar'))
        ask('add hub h1 --ports=8')
        ask('add hub h2 --ports=8')
        ask('connect c1 h1:port1 h2:port1')
        ask('save --timeout=30')
        ask('set h1 label Avant')
        key('ctrl+z')
        wait(lambda: field('h1', 'label') == '' and ask('status')['saved'], 'undo restores the saved topology and clean marker')
        key('ctrl+y')
        wait(lambda: field('h1', 'label') == 'Avant' and not ask('status')['saved'], 'redo restores the edit and dirty marker')
        ask('set h1 name renamed')
        key('ctrl+z')
        wait(lambda: field('c1', 'leftnodename') == 'h1', 'undo restores names and cable endpoints together')
        key('ctrl+shift+z')
        wait(lambda: field('c1', 'leftnodename') == 'renamed', 'Ctrl+Shift+Z also restores a rename')
        ask('del renamed')
        key('ctrl+z')
        wait(lambda: field('c1', 'leftnodename') == 'renamed' and ask('status')['nodes'] == 2, 'undo deletion restores the hub and its cable')
        key('ctrl+y')
        wait(lambda: ask('status')['nodes'] == 1, 'redo deletion removes the hub and its cable')
        key('ctrl+z')
        ask('set h2 label Nouvelle')
        assert not ask('status')['can_redo'], 'new edits must discard redo history'
        print('PASS: a new edit discards the redo branch', flush=True)
        # Create a VM without booting it. A sparse state and host file stand in
        # for owned data: deletion really unlinks them in the production model.
        ask('add machine m1')
        root = next(run.glob('**/hostfs')).parent
        owned = root / 'hostfs/m1/student-file'
        owned.write_text('preserve my data\n')
        ask('set m1 label Persistant')
        ask('del m1')
        assert not owned.exists(), 'the real deletion path must remove hostfs'
        key('ctrl+z')
        wait(lambda: owned.exists() and owned.read_text() == 'preserve my data\n', 'undo a VM deletion preserves host files')
        ask('set h2 label Arrêté')
        ask('start h2')
        wait(lambda: ask('can h2')['state'] == 'on', 'the hub starts without a guest')
        assert not ask('status')['can_undo']
        print('PASS: undo is unavailable while a component runs', flush=True)
        ask('stop h2')
        wait(lambda: ask('can h2')['state'] == 'off', 'the hub stops')
        ask('save --timeout=30')
        archive = fixture / 'undo.mar'
        entries = subprocess.check_output(['tar', '-tzf', str(archive)], text=True)
        assert '.undo-' not in entries, 'history backups must stay outside project archives'
        print('PASS: editing backups do not enter saved project archives', flush=True)
        ask('close --discard --timeout=30')
        ask('new --timeout=30 ' + str(fixture / 'next.mar'))
        assert not ask('status')['can_undo'] and not ask('status')['can_redo']
        print('PASS: history is cleared when the project changes', flush=True)
    except Exception:
        print(log_path.read_text()[-20000:], file=sys.stderr)
        raise
    finally:
        if app.poll() is None:
            os.killpg(app.pid, signal.SIGKILL)
        app.wait()
