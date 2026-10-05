#!/usr/bin/env python3
"""Exercise install.sh in an isolated tree; never execute sudo, apt or downloads.

Run from the checkout with:
    python3 test/install_presentation_test.py
For an additional comparison against the previous installer:
    git show 40f4997:dist/install.sh > /tmp/marionnet-install-before.sh
    python3 test/install_presentation_test.py --baseline /tmp/marionnet-install-before.sh

Only absolute paths used for reading the installed GUI/kernel are redirected to
fixtures. Privileged commands are intercepted and their arguments recorded.
"""

import argparse
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import subprocess
import tempfile
import time


REPO = Path(__file__).resolve().parents[1]
PAYLOAD = b"fixture package\n"
AIO = "marionnet-all-in-one_1.0.459_amd64.deb"

# Python stand-ins also prevent an accidental privileged command in the test.
STUB = r'''#!/usr/bin/python3
import hashlib, json, os, pathlib, sys, time
root = pathlib.Path(os.environ['INSTALL_FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ['INSTALL_SCENARIO']
with (root / 'trace.jsonl').open('a') as f:
    f.write(json.dumps([name, args]) + '\n')
payload = b'fixture package\n'
image = b'fixture wheezy\n'
aio = 'marionnet-all-in-one_1.0.459_amd64.deb'
wheezy = 'marionnet-fs-debian-wheezy_08367_all.deb'
def sums():
    return hashlib.sha256(payload).hexdigest() + '  ' + aio + '\n' + hashlib.sha256(image).hexdigest() + '  ' + wheezy + '\n'
if name == 'sudo':
    if args[0] == 'tee':
        rule = sys.stdin.read()
        if scenario == 'fallback-write-failure':
            print('Fixture compatibility rule could not be written', file=sys.stderr)
            sys.exit(73)
        (root / 'rule.txt').write_text(rule)
        print(rule, end='')
    elif args[0] == 'marionnet-sudoers.sh':
        if scenario in ('sudoers-fallback', 'fallback-write-failure', 'fallback-chmod-failure'):
            for line in range(10, 16):
                print('/tmp/marionnet-sudoers.fixture:%d:32: syntax error: wildcards are not allowed in command arguments' % line, file=sys.stderr)
            sys.exit(1)
    elif args[0] == 'chmod' and scenario == 'fallback-chmod-failure':
        print('Fixture compatibility rule permissions failed', file=sys.stderr)
        sys.exit(74)
    elif args[:3] == ['dpkg', '--configure', '-a']:
        if scenario in ('prompt', 'prompt-newline'):
            print('Fixture confirmation [yes/no]: ', end='\n' if scenario == 'prompt-newline' else '', flush=True)
            answer = sys.stdin.readline().strip()
            if answer != 'yes': sys.exit(43)
        if scenario == 'dpkg-ignored': sys.exit(37)
    elif args[0] == 'apt':
        if scenario == 'interrupt' and args[1] == 'update':
            (root / 'interrupt-ready').touch()
            time.sleep(30)
        print('APT ordinary output: dependencies and package progress')
        print('WARNING: apt does not have a stable CLI interface. Use with caution in scripts.', file=sys.stderr)
        print('W: Fixture repository warning', file=sys.stderr)
        if scenario == 'apt-update-failure' and args[1] == 'update':
            print('Fixture repository unavailable', file=sys.stderr)
            sys.exit(100)
        if scenario == 'runtime-failure' and args[1:] == ['install', '-y', 'libc6:i386']:
            print('Fixture runtime dependency unavailable', file=sys.stderr)
            sys.exit(100)
        if scenario == 'package-failure' and '--reinstall' in args:
            print('Fixture package configuration failed', file=sys.stderr)
            sys.exit(51)
elif name in ('curl', 'wget'):
    url = next(x for x in args if x.startswith('https:'))
    if '-w' in args:
        print('https://github.com/example/marionnet/releases/tag/v1.0.459', end='')
    else:
        target = pathlib.Path(args[args.index('-o' if name == 'curl' else '-O') + 1])
        if scenario == 'latest-fallback' and 'latest/download' in url:
            print('Fixture latest endpoint unavailable', file=sys.stderr)
            sys.exit(22)
        if scenario == 'wheezy-unavailable' and url.endswith(wheezy): sys.exit(22)
        data = sums().encode() if url.endswith('SHA256SUMS') else image if url.endswith(wheezy) else payload
        if scenario == 'checksum-failure' and url.endswith(aio): data = b'corrupt package'
        target.write_bytes(data)
        print('Transfer complete')
elif name == 'dpkg-deb':
    if '-f' in args: print('libc6, libc6:i386, graphviz')
    # --fsys-tarfile is followed by an intercepted tar, which emits no GLIBC marker.
elif name == 'dpkg':
    sys.exit(0 if scenario == 'wheezy-installed' else 1)
elif name == 'tar':
    print('fixture binary with compatible GLIBC', end='')
elif name == 'uname':
    print('aarch64' if scenario == 'unsupported-arch' else 'x86_64')
elif name == 'ldd':
    print('fixture library => not found' if scenario == 'ldd-failure' else 'fixture libraries resolved')
elif name in ('marionnet', 'marionnet.native', 'marionnet.exe'):
    if '--paths' in args:
        print('gui : ' + str(root / 'gui'))
        print('kernels : ' + str(root / 'kernels'))
    else: print('marionnet version 1.0.459')
elif name == 'build-all-in-one.sh':
    print('Builder ordinary output: extraction, Dune resources, dependencies')
    (root / 'dist' / aio).write_bytes(payload)
    (root / 'dist' / 'SHA256SUMS').write_text(sums())
    if scenario == 'build-failure':
        print('Fixture Dune build failed', file=sys.stderr)
        sys.exit(17)
elif name == 'marionnet-install.sh':
    print(json.dumps(args))
elif name == 'opam':
    print('Dune compilation complete')
'''


def prepare(root, source, scenario):
    for sub in ('dist', 'mock-bin', 'gui', 'kernels', 'logs'):
        (root / sub).mkdir(parents=True)
    mock_bin = root / 'mock-bin'
    for name in ('sudo', 'curl', 'wget', 'dpkg', 'dpkg-deb', 'tar', 'uname', 'ldd',
                 'marionnet', 'marionnet.native', 'opam', 'marionnet-install.sh'):
        path = mock_bin / name
        path.write_text(STUB)
        path.chmod(0o755)
    builder = root / 'dist' / 'build-all-in-one.sh'
    builder.write_text(STUB)
    builder.chmod(0o755)
    (root / 'META').write_text('version="1.0.459"\n')
    (root / 'dune-project').touch()
    (root / 'gui' / 'gui_glade3.xml').write_text('fixture GUI\n')
    (root / 'bin' / 'gui').mkdir(parents=True)
    (root / 'bin' / 'gui' / 'gui_glade3.xml').write_text('different GUI\n' if scenario == 'gui-mismatch' else 'fixture GUI\n')
    local_bin = root / '_build' / 'default' / 'bin' / 'marionnet.exe'
    local_bin.parent.mkdir(parents=True)
    if scenario != 'missing-local-binary':
        local_bin.write_text(STUB)
        local_bin.chmod(0o755)
    kernel = root / 'kernels' / 'linux-6.12.95-i386'
    if scenario != 'missing-kernel':
        kernel.touch()
        kernel.chmod(0o755)
    loader = root / 'loader'
    if scenario != 'missing-loader': loader.touch()
    source = source.replace('/usr/bin/marionnet --paths', f'"{mock_bin}/marionnet" --paths')
    source = source.replace('/lib/ld-linux.so.2', str(loader))
    source = source.replace('/usr/share/marionnet/filesystems/machine-debian-wheezy-08367', str(root / 'installed-wheezy'))
    source = source.replace('/usr/local/bin/marionnet', str(root / 'old-bin' / 'marionnet'))
    (root / 'dist' / 'install.sh').write_text(source)
    (root / 'install.sh').write_text((REPO / 'install.sh').read_text())
    for path in (root / 'dist' / 'install.sh', root / 'install.sh'):
        path.chmod(0o755)
    if scenario == 'release-cache': (root / 'dist' / AIO).write_bytes(PAYLOAD)
    env = dict(os.environ, PATH=str(mock_bin) + os.pathsep + os.environ['PATH'],
               INSTALL_FIXTURE=str(root), INSTALL_SCENARIO=scenario,
               TMPDIR=str(root / 'logs'), USER='fixture-user', TERM='xterm-256color')
    for key in ('SUDO_USER', 'MARIONNET_VERSION', 'MARIONNET_REPO', 'NO_COLOR'):
        env.pop(key, None)
    return env


def read_result(root, completed):
    trace = [json.loads(line) for line in (root / 'trace.jsonl').read_text().splitlines()]
    # Metadata filenames are mktemp outputs. Normalize only temporary paths.
    def normalize(value):
        value = value.replace(str(root), '<ROOT>')
        return re.sub(r'/tmp/marionnet-sums\.[A-Za-z0-9]+', '<SUMS>', value)
    trace = [[name, [normalize(x) for x in args]] for name, args in trace]
    # The two sides of the existing archive-inspection pipeline start in any order.
    for i in range(len(trace) - 1):
        if trace[i][0] == 'tar' and trace[i + 1][0] == 'dpkg-deb':
            trace[i], trace[i + 1] = trace[i + 1], trace[i]
    logs = list((root / 'logs').glob('marionnet-install.*.log'))
    log = logs[0].read_text() if logs else ''
    return completed.returncode, completed.stdout, trace, log


def run_case(root, source, scenario, args, verbose=False, tty=False, no_color=False, log_available=True):
    env = prepare(root, source, scenario)
    if no_color: env['NO_COLOR'] = '1'
    if not log_available: env['TMPDIR'] = str(root / 'nonexistent')
    cmd = [str(root / 'install.sh'), *args, *(['--verbose'] if verbose else [])]
    if tty:
        master, slave = pty.openpty()
        try:
            child = subprocess.Popen(cmd, env=env, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave)
            os.close(slave)
            output = bytearray()
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try: data = os.read(master, 65536)
                    except OSError: break
                    if not data: break
                    output.extend(data)
                if child.poll() is not None and not select.select([master], [], [], 0)[0]: break
            child.wait(timeout=1)
            completed = subprocess.CompletedProcess(cmd, child.returncode, output.decode())
        finally:
            os.close(master)
    elif scenario in ('prompt', 'prompt-newline'):
        child = subprocess.Popen(cmd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            output = bytearray()
            deadline = time.monotonic() + 5
            while b'Fixture confirmation [yes/no]: ' not in output:
                if time.monotonic() > deadline: raise AssertionError('interactive prompt was hidden')
                if select.select([child.stdout], [], [], 0.1)[0]: output.extend(os.read(child.stdout.fileno(), 4096))
            # Supply the answer only AFTER the prompt was displayed.
            remaining, _ = child.communicate(b'yes\n', timeout=10)
            completed = subprocess.CompletedProcess(cmd, child.returncode, (output + remaining).decode())
        finally:
            if child.poll() is None: child.kill(); child.wait()
    else:
        completed = subprocess.run(cmd, env=env, input='', text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, timeout=20)
    return read_result(root, completed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--preview', type=Path, help='save the simulated successful installation display')
    options = parser.parse_args()
    source = (REPO / 'dist' / 'install.sh').read_text()
    baseline = options.baseline.read_text() if options.baseline else None
    local = ['--local', '--no-wheezy']
    release = ['--release', '--no-wheezy', '1.0.459']
    cases = [
        ('local', local, 0), ('auto-local', ['--no-wheezy'], 0),
        ('missing-local-binary', local, 0), ('build-failure', local, 17),
        ('release', release, 0), ('release-cache', release, 0),
        ('release-clean', release + ['--force-download'], 0),
        ('latest-fallback', ['--release', '--no-wheezy'], 0),
        ('checksum-failure', release, 1), ('wheezy', ['--release', '1.0.459'], 0),
        ('wheezy-unavailable', ['--release', '1.0.459'], 0),
        ('wheezy-installed', ['--local'], 0), ('sudoers-fallback', local, 0),
        ('fallback-write-failure', local, 73), ('fallback-chmod-failure', local, 74),
        ('dpkg-ignored', local, 0), ('apt-update-failure', local, 100),
        ('runtime-failure', local, 1), ('package-failure', local, 51),
        ('gui-mismatch', local, 1), ('missing-kernel', local, 1),
        ('missing-loader', local, 1), ('ldd-failure', local, 1),
        ('unsupported-arch', release, 1), ('prompt', local, 0), ('prompt-newline', local, 0),
    ]
    with tempfile.TemporaryDirectory(prefix='marionnet-install-test-') as folder:
        root = Path(folder)
        for scenario, args, expected in cases:
            result = run_case(root / scenario / 'modern', source, scenario, args)
            code, output, trace, log = result
            assert code == expected, (scenario, code, expected, output)
            assert '\x1b' not in output, (scenario, 'ANSI in redirected output')
            assert log and '\x1b' not in log, (scenario, 'missing/plain journal')
            if baseline:
                before = run_case(root / scenario / 'before', baseline, scenario, args)
                assert before[0] == code, (scenario, 'exit status changed', before[0], code)
                assert before[2] == trace, (scenario, 'command arguments/order changed', before[2], trace)
                old_rule = root / scenario / 'before' / 'rule.txt'
                if old_rule.exists():
                    assert old_rule.read_text() == (root / scenario / 'modern' / 'rule.txt').read_text()
            if expected == 0:
                assert '[9/9]' in output and 'est prêt' in output, (scenario, output)
            else:
                assert 'Installation interrompue' in output and 'est prêt' not in output, (scenario, output)
            if scenario in ('apt-update-failure', 'package-failure'):
                assert 'Dernières lignes' in output and 'Fixture' in output
            if scenario in ('sudoers-fallback', 'fallback-write-failure', 'fallback-chmod-failure'):
                assert 'syntax error: wildcards' not in output and 'syntax error: wildcards' in log
                assert 'Application de la règle sudoers compatible' in output
            if scenario == 'sudoers-fallback':
                assert 'Règle réseau compatible appliquée' in output
            elif scenario.startswith('fallback-'):
                assert 'Règle réseau compatible appliquée' not in output and 'Fixture compatibility rule' in output
            if scenario == 'local':
                assert 'APT ordinary output' not in output and 'APT ordinary output' in log
                assert 'Builder ordinary output' not in output and 'Builder ordinary output' in log
                assert 'W: Fixture repository warning' in output
                assert 'stable CLI interface' not in output and 'stable CLI interface' in log
                assert re.findall(r'\[(\d)/9\]', output) == list('123456789')
                apt = [args for name, args in trace if name == 'sudo' and args[0] == 'apt']
                assert apt == [['apt', 'update'], ['apt', 'install', '-y', 'libc6:i386'],
                               ['apt', 'install', '-o', 'Dpkg::Options::=--force-overwrite',
                                '--reinstall', '-y', './' + AIO]], apt
                if options.preview: options.preview.write_text(output)
            print('PASS', scenario, '(same commands and status)' if baseline else '')
        code, output, _, log = run_case(root / 'fallback-verbose', source, 'sudoers-fallback', local, verbose=True)
        assert code == 0 and 'syntax error: wildcards' in output and 'syntax error: wildcards' in log
        assert 'Règle réseau compatible appliquée' in output
        print('PASS fallback-verbose')
        for mode in ('verbose', 'tty-color', 'tty-no-color'):
            code, output, _, log = run_case(root / mode, source, 'local', local,
                                           verbose=mode == 'verbose', tty=mode != 'verbose',
                                           no_color=mode == 'tty-no-color')
            assert code == 0
            assert ('\x1b[' in output) == (mode == 'tty-color')
            assert '\x1b' not in log
            if mode == 'verbose': assert 'APT ordinary output' in output and 'Builder ordinary output' in output
            print('PASS', mode)
        code, output, _, log = run_case(root / 'no-log', source, 'local', local, log_available=False)
        assert code == 0 and not log and 'Journal indisponible' in output
        assert 'APT ordinary output' in output and 'Builder ordinary output' in output
        print('PASS journal-unavailable')
        args = ['--tarball', '--fetch-only', '--prefix', '/a path with spaces']
        code, output, trace, log = run_case(root / 'tarball', source, 'tarball', args)
        assert code == 0 and not log and trace == [['marionnet-install.sh', args[1:]]]
        if baseline:
            before = run_case(root / 'tarball-before', baseline, 'tarball', args)
            assert before[0] == code and before[2] == trace
        print('PASS tarball-dispatch')
        for args, expected in ((['--help'], 0), (['--unknown'], 1), (['--tarball', '--local'], 2)):
            env = prepare(root / ('cli-' + args[0][2:] + str(expected)), source, 'local')
            entry = Path(env['INSTALL_FIXTURE']) / 'install.sh'
            completed = subprocess.run([str(entry), *args], env=env, text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=5)
            assert completed.returncode == expected and 'MARIONNET  /' not in completed.stdout
            assert not list((entry.parent / 'logs').glob('*.log'))
        print('PASS help-and-invalid-options')
        env = prepare(root / 'interrupt', source, 'interrupt')
        child = subprocess.Popen([str(root / 'interrupt' / 'install.sh'), *local], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 10
            while not (root / 'interrupt' / 'interrupt-ready').exists():
                assert time.monotonic() < deadline, 'interrupt test did not reach APT'
                time.sleep(0.05)
            os.killpg(child.pid, signal.SIGINT)
            output = child.communicate(timeout=5)[0].decode()
            assert child.returncode != 0 and 'est prêt' not in output
            assert 'Installation interrompue' in output
        finally:
            if child.poll() is None: os.killpg(child.pid, signal.SIGKILL); child.wait()
        print('PASS interrupt')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
