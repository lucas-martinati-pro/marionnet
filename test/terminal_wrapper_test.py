"""Check console configuration and command forwarding without a display."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/scripts/marionnet-xterm.sh'


class TerminalWrapperTests(unittest.TestCase):
    def launch(self, size=None, args=()):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'terminal with spaces'
            binary.write_text('#!' + sys.executable + '\n'
                              'import json, sys\nprint(json.dumps(sys.argv[1:]))\n')
            binary.chmod(0o755)
            env = dict(os.environ, MARIONNET_XTERM_BINARY=str(binary))
            env.pop('MARIONNET_TERMINAL_FONT_SIZE', None)
            if size is not None:
                env['MARIONNET_TERMINAL_FONT_SIZE'] = size
            result = subprocess.run(['bash', str(SCRIPT), *args], env=env,
                                    capture_output=True, text=True, check=True)
            return json.loads(result.stdout), result.stderr

    def test_command_arguments_are_preserved(self):
        command = ['-T', 'Machine m1', '-e', '/a path/program', 'one argument', '']
        arguments, errors = self.launch(args=command)
        self.assertEqual(arguments[-len(command):], command)
        self.assertIn('*faceSize: 8', arguments)
        self.assertEqual(errors, '')

    def test_configured_size(self):
        for size in ('6', '08', '14', '32'):
            with self.subTest(size=size):
                arguments, errors = self.launch(size)
                self.assertIn(f'*faceSize: {int(size)}', arguments)
                self.assertEqual(errors, '')

    def test_invalid_size_cannot_inject_resources(self):
        for size in ('5', '33', '-1', '12.5', 'abc', '12\n*renderFont: false'):
            with self.subTest(size=size):
                arguments, errors = self.launch(size)
                self.assertIn('*faceSize: 8', arguments)
                self.assertNotIn('*renderFont: false', arguments)
                self.assertIn('invalid font size', errors)

    def test_missing_terminal_reports_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, MARIONNET_XTERM_BINARY=str(Path(directory) / 'missing'))
            result = subprocess.run(['bash', str(SCRIPT)], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 127)
            self.assertIn('not found', result.stderr)


if __name__ == '__main__':
    unittest.main()
