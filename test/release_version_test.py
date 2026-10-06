"""Check release version persistence without contacting GitHub or publishing."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'dist/sync-release-version.py'
spec = importlib.util.spec_from_file_location('release_version', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class VersionTests(unittest.TestCase):
    def response(self, text):
        return subprocess.CompletedProcess([], 0, json.dumps(dict(
            sha='current-meta-sha', content=base64.b64encode(text.encode()).decode())))

    def test_update_only_version_on_latest_branch_file(self):
        original = '# Latest branch comment\nversion="1.0.459"\nrequires="unchanged"\n'
        with patch.object(module.subprocess, 'run') as run:
            run.side_effect = [self.response(original), subprocess.CompletedProcess([], 0, '{}')]
            module.synchronize('owner/repo', 'release/main', '1.0.460')
            self.assertEqual(run.call_args_list[0].args[0][-1],
                             'repos/owner/repo/contents/META?ref=release%2Fmain')
            payload = json.loads(run.call_args.kwargs['input'])
            self.assertEqual(payload['branch'], 'release/main')
            self.assertEqual(payload['sha'], 'current-meta-sha')
            self.assertEqual(base64.b64decode(payload['content']).decode(),
                             original.replace('1.0.459', '1.0.460'))
            self.assertEqual(payload['message'], 'chore(release): synchronize version 1.0.460')

    def test_api_output_stays_plain_in_colored_ci_environment(self):
        with patch.dict(os.environ, CLICOLOR_FORCE='1', GH_FORCE_TTY='100%', GH_TOKEN='test-token'), \
                patch.object(module.subprocess, 'run') as run:
            run.side_effect = [self.response('version="1.0.460"\n'),
                               subprocess.CompletedProcess([], 0, '{}')]
            module.synchronize('owner/repo', 'main', '1.0.461')
            for call in run.call_args_list:
                env = call.kwargs['env']
                self.assertEqual(env['NO_COLOR'], '1')
                self.assertEqual(env['CLICOLOR_FORCE'], '0')
                self.assertNotIn('GH_FORCE_TTY', env)
                self.assertEqual(env['GH_TOKEN'], 'test-token')
            self.assertEqual(os.environ['CLICOLOR_FORCE'], '1')

    def test_equal_and_newer_versions_create_no_commit(self):
        for version in ('1.0.460', '1.0.461', '1.0.1000'):
            with self.subTest(version=version), patch.object(module.subprocess, 'run') as run:
                run.return_value = self.response('version="' + version + '"\n')
                module.synchronize('owner/repo', 'main', '1.0.460')
                self.assertEqual(run.call_count, 1)

    def test_unfrozen_series_can_be_frozen(self):
        with patch.object(module.subprocess, 'run') as run:
            run.side_effect = [self.response('version="1.0.x"\n'),
                               subprocess.CompletedProcess([], 0, '{}')]
            module.synchronize('owner/repo', 'main', '1.0.460')
            self.assertEqual(run.call_count, 2)

    def test_invalid_input_makes_no_request(self):
        with patch.object(module.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                module.synchronize('owner/repo', 'main', '$(anything)')
            run.assert_not_called()

    def test_ambiguous_metadata_makes_no_write(self):
        with patch.object(module.subprocess, 'run') as run:
            run.return_value = self.response('version="1.0.459"\nversion="1.0.458"\n')
            with self.assertRaises(ValueError):
                module.synchronize('owner/repo', 'main', '1.0.460')
            self.assertEqual(run.call_count, 1)

    def test_write_conflict_is_reported(self):
        with patch.object(module.subprocess, 'run') as run:
            run.side_effect = [self.response('version="1.0.459"\n'),
                               subprocess.CalledProcessError(1, ['gh'], stderr='HTTP 409')]
            with self.assertRaises(subprocess.CalledProcessError):
                module.synchronize('owner/repo', 'main', '1.0.460')
            self.assertEqual(run.call_count, 2)


if __name__ == '__main__':
    unittest.main()
