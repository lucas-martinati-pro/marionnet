"""Exercise updater output with fake downloads and privileged commands."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/scripts/marionnet-update'
STUB = r'''
import hashlib, json, os
from pathlib import Path
import sys
name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'curl':
    if '-o' in args:
        target = Path(args[args.index('-o') + 1])
        if any(arg.endswith('/SHA256SUMS') for arg in args):
            failure = os.environ.get('TEST_FAILURE')
            if failure == 'manifest-download':
                print('curl: manifest download failed', file=sys.stderr)
                sys.exit(22)
            digest = hashlib.sha256(b'x' * 1100000).hexdigest()
            filename = 'marionnet-all-in-one_1.0.461_amd64.deb'
            if failure == 'checksum': digest = '0' * 64
            if failure == 'malformed': digest = 'invalid-digest'
            if failure == 'missing-entry': filename = 'another-package.deb'
            manifest = digest + '  ' + filename + '\n'
            if failure == 'duplicate': manifest *= 2
            if failure == 'binary-marker': manifest = digest.upper() + ' *' + filename + '\n'
            target.write_text(manifest)
        else:
            target.write_bytes(b'x' * 1100000)
    else:
        print(json.dumps({'tag_name': 'v1.0.461', 'html_url': 'https://example.test/release',
            'assets': [{'name': 'marionnet-all-in-one_1.0.461_amd64.deb',
                        'browser_download_url': 'https://example.test/marionnet-all-in-one_1.0.461_amd64.deb'}]}))
elif name == 'sudo':
    with open(os.environ['TEST_CALLS'], 'a') as f:
        f.write(json.dumps(args) + '\n')
    print('package-manager-detail')
    if args[:2] == ['apt', 'install']:
        print('Confirmer ? [O/n]')
    operation = 'network' if args[0] == 'marionnet-sudoers.sh' else args[1]
    if os.environ.get('TEST_FAILURE') == operation:
        print('E: simulated failure', file=sys.stderr)
        sys.exit(17)
'''


class UpdatePresentationTests(unittest.TestCase):
    def run_update(self, *args, failure='', current='1.0.460'):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('curl', 'sudo', 'marionnet-sudoers.sh'):
                stub = root / name
                stub.write_text('#!' + sys.executable + '\n' + STUB)
                stub.chmod(0o755)
            calls = root / 'calls'
            env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
                       TMPDIR=tmp, TEST_CALLS=str(calls), TEST_FAILURE=failure,
                       NO_COLOR='1')
            result = subprocess.run(['bash', str(SCRIPT), '--current', current, *args],
                                    env=env, capture_output=True, text=True, timeout=15)
            log_files = list(root.glob('marionnet-update.*.log'))
            logs = ''.join(p.read_text() for p in log_files)
            for log in log_files:
                self.assertEqual(log.stat().st_mode & 0o777, 0o600)
            commands = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            for command in commands:
                if command[:2] == ['apt', 'install']:
                    self.assertFalse(Path(command[-1]).exists(), 'temporary package must be removed')
            return result, logs, commands

    def test_compact_success_retains_prompts_and_full_private_log(self):
        result, log, commands = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        for step in ('[1/3] Téléchargement', '[2/3] Installation', '[3/3] Configuration réseau'):
            self.assertIn(step, result.stdout)
        self.assertIn('Confirmer ? [O/n]', result.stdout)
        self.assertIn('Marionnet 1.0.461 installé', result.stdout)
        self.assertNotIn('package-manager-detail', result.stdout)
        self.assertIn('package-manager-detail', log)
        self.assertNotIn('\x1b', result.stdout)
        self.assertEqual(commands[0], ['apt', 'update'])
        self.assertEqual(commands[1][:-1], ['apt', 'install', '-o',
            'Dpkg::Options::=--force-overwrite', '--reinstall', '-y'])
        self.assertEqual(commands[2][0:2], ['marionnet-sudoers.sh', 'install'])

    def test_verbose_shows_command_details(self):
        result, _, _ = self.run_update('--verbose')
        self.assertEqual(result.returncode, 0)
        self.assertIn('package-manager-detail', result.stdout)

    def test_unverified_packages_never_reach_privileged_commands(self):
        for failure in ('checksum', 'malformed', 'missing-entry', 'duplicate', 'manifest-download'):
            with self.subTest(failure=failure):
                result, _, commands = self.run_update(failure=failure)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(commands, [])
                self.assertNotIn('Marionnet 1.0.461 installé', result.stdout)
                if failure == 'checksum':
                    self.assertIn('SHA256 incorrect', result.stderr)
                elif failure != 'manifest-download':
                    self.assertIn('Empreinte absente, invalide ou multiple', result.stderr)
                self.assertIn('Journal :', result.stderr)

    def test_binary_manifest_marker_and_uppercase_digest(self):
        result, _, commands = self.run_update(failure='binary-marker')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('SHA256 validé', result.stdout)
        self.assertEqual(len(commands), 3)

    def test_install_failure_is_visible_and_never_reports_success(self):
        result, _, commands = self.run_update(failure='install')
        self.assertEqual(result.returncode, 1)
        self.assertIn('simulated failure', result.stdout + result.stderr)
        self.assertIn('Journal :', result.stderr)
        self.assertNotIn('Marionnet 1.0.461 installé', result.stdout)
        self.assertEqual(len(commands), 2)

    def test_repository_failure_preserves_existing_fallback(self):
        result, log, commands = self.run_update(failure='update')
        self.assertEqual(result.returncode, 0)
        self.assertIn('Dépôts non actualisés', result.stdout)
        self.assertIn('simulated failure', log)
        self.assertEqual(len(commands), 3)

    def test_network_failure_is_nonblocking_but_reported(self):
        result, log, _ = self.run_update(failure='network')
        self.assertEqual(result.returncode, 0)
        self.assertIn('Droits réseau non actualisés', result.stdout)
        self.assertIn('simulated failure', log)

    def test_check_mode_protocol_is_unchanged(self):
        result, log, commands = self.run_update('--check')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, 'UPDATE_AVAILABLE 1.0.461 1.0.460 https://example.test/release\n')
        self.assertEqual(log, '')
        self.assertEqual(commands, [])

    def test_up_to_date_and_force(self):
        result, _, commands = self.run_update(current='1.0.461')
        self.assertEqual(result.returncode, 0)
        self.assertIn('déjà à jour', result.stdout)
        self.assertEqual(commands, [])
        result, _, commands = self.run_update('--force', current='1.0.461')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(commands), 3)


if __name__ == '__main__':
    unittest.main()
