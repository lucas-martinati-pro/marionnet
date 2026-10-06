#!/usr/bin/env python3
"""GPL-2.0-or-later. Run lifecycle regressions against production OCaml modules.
Run: xvfb-run -a python3 driven-sessions/lifecycle.py
Builds the app, then links the fixtures to its actual objects. No root or UML boot.
"""
from pathlib import Path
import os
import json
import signal
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
subprocess.run(['opam', 'exec', '--', 'dune', 'build', '@install', '@check'],
               cwd=ROOT, check=True)
objects = ROOT / '_build/default/bin/.marionnet.eobjs/native'
available = {p.stem[0].upper() + p.stem[1:]: p for p in objects.glob('*.cmx')}
ordered, visited = [], set()


def visit(name):
    if name in visited or name not in available:
        return
    visited.add(name)
    info = subprocess.check_output(['opam', 'exec', '--', 'ocamlobjinfo',
                                    str(available[name])], text=True, cwd=ROOT)
    imports = info.split('Implementations imported:\n', 1)[1].split('Clambda', 1)[0]
    for line in imports.splitlines():
        parts = line.split()
        if len(parts) == 2:
            visit(parts[1])
    ordered.append(str(available[name]))


visit('Dune__exe__Simulation_level')
visit('Dune__exe__Task_runner')
with tempfile.TemporaryDirectory(prefix='marionnet-lifecycle-') as tmp:
    fixture = Path(tmp)
    source = fixture / 'lifecycle.ml'
    source.write_text(Path(__file__).with_suffix('.ml').read_text())
    command = ['opam', 'exec', '--', 'ocamlfind', 'ocamlopt', '-thread', '-linkpkg',
               '-package', 'str,unix,threads,inotify,lablgtk3,lablgtk3-sourceview3,yojson,base64']
    for folder in ['lib', 'lib/.ocamlbricks.objs/byte', 'lib/.ocamlbricks.objs/native',
                   'bin/.marionnet_base.objs/byte', 'bin/.marionnet_base.objs/native',
                   'bin/.marionnet_tap.objs/byte', 'bin/.marionnet_tap.objs/native',
                   'bin/.marionnet.eobjs/byte', 'bin/.marionnet.eobjs/native']:
        command += ['-I', str(ROOT / '_build/default' / folder)]
    command += [str(ROOT / '_build/default' / lib) for lib in
                ['lib/ocamlbricks.cmxa', 'bin/marionnet_base.cmxa', 'bin/marionnet_tap.cmxa']]
    command += ordered + [str(source), '-o', str(fixture / 'lifecycle')]
    subprocess.run(command, cwd=ROOT, check=True)
    env = dict(os.environ, MARIONNET_LIFECYCLE_FIXTURE=tmp,
               MARIONNET_PREFIX=str(ROOT / '_build/install/default/share/marionnet'))
    subprocess.run([str(fixture / 'lifecycle')], cwd=ROOT, env=env, check=True, timeout=35)
    # A separate real GTK session keeps lifecycle timing independent of canvas gestures.
    control = fixture / 'control.sock'
    log_path = fixture / 'application.log'
    run = fixture / 'run'
    run.mkdir()
    env.update(MARIONNET_TMPDIR=str(run), MARIONNET_LANG='fr', MARIONNET_SHOW_SPLASH='false')
    with log_path.open('w') as log:
        app = subprocess.Popen([str(ROOT / '_build/default/bin/marionnet.exe'), '--debug',
                                '--no-welcome', '--control-socket', str(control)],
                               cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True)

    def wait(predicate, message):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if predicate():
                print('PASS:', message, flush=True)
                return
            time.sleep(.05)
        raise AssertionError(message)

    def ask(command):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(20)
            connection.connect(str(control))
            connection.sendall((command + '\n').encode())
            data = b''
            while b'\n' not in data:
                chunk = connection.recv(65536)
                if not chunk:
                    raise AssertionError('control socket closed')
                data += chunk
        reply = json.loads(data.split(b'\n')[0])
        assert reply.get('ok'), (command, reply)
        return reply

    try:
        wait(lambda: control.exists() or app.poll() is not None, 'GTK application starts')
        assert app.poll() is None, log_path.read_text()
        ask('new --timeout=15 ' + str(fixture / 'restart.mar'))
        ask('add hub h1 --ports=8')
        ask('start h1')
        wait(lambda: ask('can h1')['state'] == 'on', 'hub starts')
        locales = json.loads((ROOT / 'bin/locales/fr.json').read_text())
        finished = ('task_runner: The task "Destroy the progress bar for "' +
                    locales['label.restarting'] + ' h1"" succeeded.')
        for _ in range(3):
            offset = log_path.stat().st_size
            started = time.monotonic()
            ask('restart h1')
            wait(lambda: finished in log_path.read_text()[offset:]
                 and ask('can h1')['state'] == 'on', 'restart and progress cleanup complete')
            assert time.monotonic() - started < 5, 'restart added an artificial delay'
        ask('stop h1')
        wait(lambda: ask('can h1')['state'] == 'off', 'hub stops after repeated restarts')
        assert 'uncaught exception' not in log_path.read_text()
        ask('quit --no-save')
        app.wait(timeout=15)
    except Exception:
        print(log_path.read_text()[-6000:])
        raise
    finally:
        if app.poll() is None:
            os.killpg(app.pid, signal.SIGTERM)
            try:
                app.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(app.pid, signal.SIGKILL)
                app.wait()
