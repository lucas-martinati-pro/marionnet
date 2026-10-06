#!/usr/bin/env python3
"""GPL-2.0-or-later. Real canvas gestures and shared component dialogs.
Run: xvfb-run -a python3 driven-sessions/canvas.py [--screenshots DIR]
Requires xdotool, ImageMagick import, Pillow and NumPy; no guest boots or root.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--screenshots', type=Path)
args = parser.parse_args()
locales = json.loads((ROOT / 'bin/locales/fr.json').read_text())


def wait(predicate, message):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            print('PASS:', message, flush=True)
            return result
        time.sleep(.05)
    raise AssertionError(message)


def xdo(*args):
    return subprocess.check_output(['xdotool', *map(str, args)], text=True).strip()


with tempfile.TemporaryDirectory(prefix='marionnet-canvas-') as tmp:
    fixture = Path(tmp)
    run = fixture / 'run'
    run.mkdir()
    sock = fixture / 'control.sock'
    log_path = fixture / 'application.log'
    env = dict(os.environ, MARIONNET_PREFIX=str(ROOT / '_build/install/default/share/marionnet'),
               MARIONNET_TMPDIR=str(run), MARIONNET_LANG='fr', MARIONNET_SHOW_SPLASH='false')
    with log_path.open('w') as log:
        app = subprocess.Popen([str(ROOT / '_build/default/bin/marionnet.exe'), '--debug',
                                '--no-welcome', '--control-socket', str(sock)], cwd=ROOT, env=env,
                               start_new_session=True, stdout=log, stderr=log)

    def ask(command):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(40)
            connection.connect(str(sock))
            connection.sendall((command + '\n').encode())
            data = b''
            while b'\n' not in data:
                part = connection.recv(65536)
                assert part, 'control channel closed'
                data += part
        result = json.loads(data.split(b'\n')[0])
        assert result.get('ok'), (command, result)
        return result

    def field(name, prop):
        return ask('get ' + name + ' ' + prop)['fields'][prop]

    def keys(value):
        xdo('key', '--clearmodifiers', value)
        time.sleep(.2)

    def windows(title):
        result = subprocess.run(['xdotool', 'search', '--all', '--onlyvisible', '--pid', str(app.pid),
                                 '--name', '^' + re.escape(title) + '$'], text=True, capture_output=True)
        return result.stdout.splitlines()

    def dialog(title):
        return wait(lambda: windows(title), 'dialog opens: ' + title)[0]

    def close_dialog(title):
        keys('Escape')
        wait(lambda: not windows(title), 'dialog closes: ' + title)
        xdo('windowfocus', '--sync', window)

    def capture(window, name):
        path = fixture / (name + '.png')
        bounds = geometry(window)
        crop = f"{bounds['WIDTH']}x{bounds['HEIGHT']}+{bounds['X']}+{bounds['Y']}"
        subprocess.run(['import', '-window', 'root', '-crop', crop, str(path)], check=True)
        if args.screenshots:
            args.screenshots.mkdir(parents=True, exist_ok=True)
            (args.screenshots / path.name).write_bytes(path.read_bytes())
        return np.asarray(Image.open(path).convert('RGB'))

    def geometry(window):
        return dict(line.split('=', 1) for line in xdo('getwindowgeometry', '--shell', window).splitlines())

    def fits(window):
        bounds = geometry(window)
        width, height = map(int, xdo('getdisplaygeometry').split())
        return int(bounds['WIDTH']) <= width and int(bounds['HEIGHT']) <= height

    def check_popup_parent():
        ids = xdo('search', '--all', '--onlyvisible', '--pid', app.pid).splitlines()
        menus = [identity for identity in ids if 'POPUP_MENU' in subprocess.check_output(
            ['xprop', '-id', identity, '_NET_WM_WINDOW_TYPE'], text=True)]
        assert menus, 'the real GTK popup must be mapped'
        for identity in menus:
            prop = subprocess.check_output(['xprop', '-id', identity, 'WM_TRANSIENT_FOR'], text=True)
            parent = re.search(r'0x[0-9a-fA-F]+', prop)
            assert parent and int(parent.group(0), 16) == int(window), prop
        print('PASS: the context popup has the drawing window as its transient parent', flush=True)

    def drawing():
        return next(run.glob('**/sketch.png'), None)

    def map_ready():
        png = drawing()
        if not png or not png.with_suffix('.cmapx').exists():
            return False
        try:
            return len(ET.fromstring(png.with_suffix('.cmapx').read_text()).findall('area')) >= 1
        except ET.ParseError:
            return False

    def point(name):
        # Locate the actual PNG in the allocated GTK viewport, without assuming
        # a panel size or desktop theme. Use opaque dark pixels as template anchors.
        xdo('mousemove', '--window', window, 0, 0)
        keys('Escape')
        time.sleep(.15)
        wait(map_ready, 'current PNG and hit map are available')
        png = drawing()
        image = np.asarray(Image.open(png).convert('RGBA'))
        screen = capture(window, 'network')
        ys, xs = np.where((image[:, :, :3].min(axis=2) < 200) & (image[:, :, 3] == 255))
        indices = np.linspace(0, len(xs) - 1, min(60, len(xs)), dtype=int)
        anchors = list(zip(xs[indices], ys[indices]))
        ax, ay = anchors[0]
        sy, sx = np.where(np.all(screen == image[ay, ax, :3], axis=2))
        ox, oy = sx - ax, sy - ay
        ok = (ox >= 0) & (oy >= 0) & (ox + image.shape[1] <= screen.shape[1]) & (oy + image.shape[0] <= screen.shape[0])
        ox, oy = ox[ok], oy[ok]
        for ax, ay in anchors[1:]:
            ok = np.all(screen[oy + ay, ox + ax] == image[ay, ax, :3], axis=1)
            ox, oy = ox[ok], oy[ok]
        assert len(ox) == 1, ('cannot locate the drawing', ox, oy)
        source = png.with_suffix('.dot').read_text()
        if name == 'c1':
            href = re.search(r'marionnet:cable:(\d+)', source).group(0)
        else:
            href = re.search(re.escape(name) + r' \[URL="(marionnet:node:\d+)"', source).group(1)
        area = next(a for a in ET.fromstring(png.with_suffix('.cmapx').read_text()).findall('area')
                    if a.attrib['href'] == href)
        coordinates = [int(c) for c in area.attrib['coords'].split(',')]
        if area.attrib['shape'] == 'rect':
            x, y = (coordinates[0] + coordinates[2]) / 2, (coordinates[1] + coordinates[3]) / 2
        elif area.attrib['shape'] == 'circle':
            x, y = coordinates[:2]
        else:
            x, y = np.array(coordinates).reshape(-1, 2).mean(axis=0)
        return (int(ox[0] + x), int(oy[0] + y)), (int(ox[0]), int(oy[0])), (x, y), image.shape[1::-1]

    def click(position, button=1, double=False):
        xdo('windowfocus', '--sync', window)
        xdo('mousemove', '--window', window, *position)
        xdo('click', '--repeat', 2 if double else 1, '--delay', 100, button)
        time.sleep(.25)

    def selected(name, action):
        offset = log_path.stat().st_size
        action()
        wait(lambda: 'Drawing selection: ' + name in log_path.read_text(errors="replace")[offset:], 'canvas selects ' + name)

    try:
        wait(lambda: sock.exists() or app.poll() is not None, 'application starts')
        assert app.poll() is None, log_path.read_text(errors="replace")
        window = windows('Marionnet')[0]
        time.sleep(6.5)  # Wait for the existing startup palette recentering.
        ask('new --timeout=30 ' + str(fixture / 'canvas.mar'))
        ask('add hub h1 --ports=8')
        ask('add hub h2 --ports=8')
        ask('connect c1 h1:port1 h2:port1')
        ask('save --timeout=30')
        p, _, _, _ = point('h1')
        selected('h1', lambda: click(p))
        assert ask('status')['saved'], 'selection must not modify the project'
        capture(window, 'selection')
        click(p, double=True)
        hub_title = locales['action.modify_hub'] + ' h1'
        hub_window = dialog(hub_title)
        assert fits(hub_window)
        capture(hub_window, 'hub-properties')
        # Invalid and duplicate names leave the form open, without an error modal.
        keys('ctrl+a'); xdo('type', 'bad name'); keys('Return')
        assert windows(hub_title) and ask('status')['saved']
        keys('ctrl+a'); xdo('type', 'h2'); keys('Return')
        assert windows(hub_title) and ask('status')['nodes'] == 2
        capture(hub_window, 'name-conflict')
        print('PASS: invalid and duplicate names are rejected inline', flush=True)
        keys('ctrl+a'); xdo('type', 'h1'); keys('Tab')
        xdo('type', 'Nouvelle etiquette'); keys('Return')
        wait(lambda: not windows(hub_title) and field('h1', 'label') == 'Nouvelle etiquette', 'Enter validates the properties once')
        xdo('windowfocus', '--sync', window)
        keys('ctrl+z')
        wait(lambda: not ask('status')['editing'] and field('h1', 'label') == '' and ask('status')['saved'], 'canvas edits are undoable')
        p, _, _, _ = point('c1')
        selected('c1', lambda: click(p, 3))
        check_popup_parent()
        capture(window, 'cable-menu')
        keys('Home'); keys('Return')
        cable_title = locales['action.modify_straight_cable'] + ' c1'
        cable_window = dialog(cable_title)
        assert fits(cable_window)
        capture(cable_window, 'cable-properties')
        close_dialog(cable_title)
        # Properties remain available via Enter. Delete retains the existing confirmation.
        p, _, _, _ = point('h1')
        click(p); keys('shift+F10')
        check_popup_parent(); keys('Escape')
        xdo('windowfocus', '--sync', window)
        keys('Return'); dialog(hub_title); close_dialog(hub_title)
        p, _, _, _ = point('c1')
        click(p); keys('Delete')
        remove_title = locales['label.remove']
        dialog(remove_title); close_dialog(remove_title)
        assert field('c1', 'leftnodename') == 'h1', 'cancelled removal must retain the cable'
        print('PASS: Delete preserves the existing removal confirmation', flush=True)
        p, _, _, _ = point('h1')
        # The node menu exposes real lifecycle actions and rechecks availability.
        click(p, 3); keys('Home'); keys('Down'); keys('Down'); keys('Return')
        wait(lambda: ask('can h1')['state'] == 'on', 'Start from the node context menu')
        p, _, _, _ = point('h1')
        click(p, double=True)
        assert not windows(hub_title), 'running hub properties must stay disabled'
        click(p, 3); keys('Home'); keys('Return')
        wait(lambda: ask('can h1')['state'] == 'off', 'Stop from the node context menu')
        ask('set h1 label Identique')
        ask('save --timeout=30')
        wait(lambda: 'Identique' in drawing().with_suffix('.dot').read_text(), 'changed drawing is published')
        identical_stamp = drawing().with_suffix('.dot').stat().st_mtime_ns
        ask('set h1 label Identique')
        ask('save --timeout=30')
        time.sleep(.2)
        assert drawing().with_suffix('.dot').stat().st_mtime_ns == identical_stamp
        assert 'reused unchanged drawing and hit map' in log_path.read_text(errors='replace')
        print('PASS: unchanged drawing reuses its image and geometry', flush=True)
        p, origin, map_point, size = point('h1')
        before = hashlib.sha256(drawing().read_bytes()).hexdigest()
        stamp = drawing().with_suffix('.dot').stat().st_mtime_ns
        click(p)
        xdo('keydown', 'ctrl'); xdo('click', 4); xdo('keyup', 'ctrl')
        time.sleep(.3)
        zoomed = tuple(round(origin[i] - size[i] * .15 / 2 + map_point[i] * 1.15) for i in (0, 1))
        selected('h1', lambda: click(zoomed))
        assert hashlib.sha256(drawing().read_bytes()).hexdigest() == before
        assert drawing().with_suffix('.dot').stat().st_mtime_ns == stamp and ask('status')['saved']
        print('PASS: Ctrl+wheel zoom keeps hit testing accurate without rendering or dirtying the project', flush=True)
        capture(window, 'zoom')
        xdo('keydown', 'ctrl'); xdo('click', 5); xdo('keyup', 'ctrl')
        wait(lambda: not ask('status')['operations'], 'individual operation reservations are released')
        ask('start-all')
        wait(lambda: ask('can h1')['state'] == 'on' and ask('can h2')['state'] == 'on'
             and not ask('status')['operations'], 'collective startup completes and releases reservations')
        ask('shutdown-all')
        wait(lambda: ask('can h1')['state'] == 'off' and ask('can h2')['state'] == 'off'
             and not ask('status')['operations'], 'parallel shutdown completes and releases reservations')
        # Exercise the longest shared form on the available screen as well.
        xdo('windowfocus', '--sync', window)
        keys('ctrl+m')
        add_title = locales['action.add_machine']
        add_window = dialog(add_title)
        assert fits(add_window)
        keys('Tab')
        xdo('type', '--clearmodifiers', 'Etiquette clavier')
        keys('shift+Tab')
        keys('Return')
        wait(lambda: not windows(add_title) and ask('status')['nodes'] == 3, 'add a machine through its real configuration dialog')
        assert field('m1', 'label') == 'Etiquette clavier', 'Tab must reach the label field'
        wait(lambda: ask('status')['can_undo'], 'machine addition enters undo history')
        xdo('windowfocus', '--sync', window)
        keys('ctrl+z')
        wait(lambda: not ask('status')['editing'] and ask('status')['nodes'] == 2, 'Ctrl+Z removes a machine added through the dialog')
        keys('ctrl+y')
        wait(lambda: not ask('status')['editing'] and ask('status')['nodes'] == 3, 'Ctrl+Y restores that machine')
        p, _, _, _ = point('m1')
        click(p, double=True)
        machine_title = locales['action.modify_machine'] + ' m1'
        machine_window = dialog(machine_title)
        assert fits(machine_window), geometry(machine_window)
        capture(machine_window, 'machine-properties')
        keys('Tab'); xdo('type', 'Proprietes modifiees'); keys('Return')
        wait(lambda: not windows(machine_title) and field('m1', 'label') == 'Proprietes modifiees', 'change machine properties through the dialog')
        xdo('windowfocus', '--sync', window)
        keys('ctrl+z')
        wait(lambda: not ask('status')['editing'] and field('m1', 'label') == 'Etiquette clavier', 'Ctrl+Z restores machine properties')
        p, _, _, _ = point('m1')
        click(p, double=True)
        machine_window = dialog(machine_title)
        bounds = geometry(machine_window)
        xdo('windowfocus', '--sync', machine_window)
        xdo('mousemove', '--window', machine_window, int(bounds['WIDTH']) - 130, int(bounds['HEIGHT']) - 20)
        xdo('mousedown', 1)
        xdo('mousemove', '--window', machine_window, 0, 0)
        xdo('mouseup', 1)
        keys('Return')
        wait(lambda: not windows(machine_title), 'Enter activates focused Cancel below the long form')
        xdo('windowfocus', '--sync', window)
        tab_y = int(geometry(window)['HEIGHT']) - 118
        for tab_x, name in [(258, 'interfaces'), (382, 'defects'), (502, 'disks')]:
            xdo('mousemove', '--window', window, tab_x, tab_y)
            xdo('click', 1)
            time.sleep(.2)
            capture(window, name)
        xdo('mousemove', '--window', window, 134, tab_y)
        xdo('click', 1)
        for kind, title_key in [('switch', 'action.modify_switch'), ('router', 'action.modify_router'),
                                ('cloud', 'action.modify_cloud'), ('world_bridge', 'action.modify_lan_bridge'),
                                ('nat_bridge', 'action.modify_nat_bridge'), ('world_gateway', 'action.modify_world_gateway')]:
            ask('close --no-save --timeout=30')
            ask('new --timeout=30 ' + str(fixture / (kind + '.mar')))
            ask('add ' + kind + ' n1')
            p, _, _, _ = point('n1')
            click(p, double=True)
            title = locales[title_key] + ' n1'
            component_window = dialog(title)
            assert fits(component_window), geometry(component_window)
            capture(component_window, kind + '-properties')
            close_dialog(title)
        assert 'uncaught exception' not in log_path.read_text(errors="replace"), 'unexpected GTK callback failure'
        assert 'temporary window without parent' not in log_path.read_text(errors="replace")
        assert 'Gdk-CRITICAL' not in log_path.read_text(errors="replace"), 'unexpected GDK popup failure'
        print('PASS: shared short and long configuration dialogs fit the screen', flush=True)
    except Exception:
        print(log_path.read_text(errors="replace")[-14000:], file=sys.stderr)
        raise
    finally:
        if app.poll() is None:
            os.killpg(app.pid, signal.SIGKILL)
        app.wait()
