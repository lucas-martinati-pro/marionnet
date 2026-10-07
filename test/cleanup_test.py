"""Recovery and startup counts use the same protected directory selection."""
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/scripts/marionnet-cleanup'


class CleanupTests(unittest.TestCase):
    def test_count_and_recovery_preserve_recent_and_spared_projects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run = root / 'run'
            run.mkdir()
            archive = root / 'archives'
            archive.mkdir()
            old = run / 'marionnet-100.dir'
            recent = run / 'marionnet-101.dir'
            spared = run / 'marionnet-102.dir'
            empty = run / 'marionnet-103.dir'
            for directory in (old, recent, spared):
                (directory / 'project').mkdir(parents=True)
                (directory / 'project' / 'version').write_text('unsaved work')
            empty.mkdir()
            stamp = time.time() - 7200
            for directory in (old, spared, empty):
                os.utime(directory, (stamp, stamp))
            env = dict(os.environ, TMPDIR=str(run), UML_DIR=str(root / 'uml'))

            def launch(*args):
                result = subprocess.run(['bash', str(SCRIPT), '--spare-dir', str(spared), *args],
                                        env=env, text=True, capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.stdout

            self.assertEqual(launch('--count-dirs'), '2\n')
            self.assertTrue(old.exists(), 'checking must not remove unsaved work')
            launch('--archive-dirs', str(archive), '--purge-dirs')
            self.assertFalse(old.exists())
            self.assertFalse(empty.exists())
            self.assertTrue(recent.exists())
            self.assertTrue(spared.exists())
            projects = list(archive.glob('*.mar'))
            self.assertEqual(len(projects), 1)
            with tarfile.open(projects[0]) as recovered:
                self.assertEqual(recovered.extractfile('project/version').read(), b'unsaved work')
            self.assertEqual(launch('--count-dirs'), '0\n')

    def test_count_rejects_mutations(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(['bash', str(SCRIPT), '--count-dirs', '--purge-dirs'],
                                    env=dict(os.environ, TMPDIR=temporary), text=True,
                                    capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 2)
            self.assertIn('cannot be combined', result.stderr)


if __name__ == '__main__':
    unittest.main()
