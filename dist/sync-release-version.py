"""Persist a successfully published version in META on the default branch.

Only META is updated, using its current blob SHA to reject concurrent changes.
No commit is created if the branch already has this version or a newer one.
"""
import base64
import json
import os
import re
import subprocess
import sys
from urllib.parse import quote


def synchronize(repository, branch, version):
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', version):
        raise ValueError('Invalid release version: ' + version)
    endpoint = 'repos/' + repository + '/contents/META'
    result = subprocess.run(['gh', 'api', endpoint + '?ref=' + quote(branch, safe='')],
                            check=True, text=True, capture_output=True)
    metadata = json.loads(result.stdout)
    original = base64.b64decode(metadata['content']).decode('utf-8')
    pattern = r'^version="([^"]+)"$'
    matches = list(re.finditer(pattern, original, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError('META must contain exactly one version declaration')
    current = matches[0].group(1)
    if current == version or (re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', current) and
                             tuple(map(int, current.split('.'))) > tuple(map(int, version.split('.')))):
        print('META already contains version ' + current + '; no commit needed.')
        return
    updated = re.sub(pattern, 'version="' + version + '"', original, flags=re.MULTILINE)
    payload = dict(message='chore(release): synchronize version ' + version,
                   content=base64.b64encode(updated.encode('utf-8')).decode('ascii'),
                   sha=metadata['sha'], branch=branch)
    # Updating by blob SHA preserves other files and rejects a conflicting META edit.
    subprocess.run(['gh', 'api', '--method', 'PUT', endpoint, '--input', '-'],
                   input=json.dumps(payload), text=True, check=True, capture_output=True)
    print('Published version ' + version + ' committed to ' + branch + '.')


if __name__ == '__main__':
    try:
        synchronize(os.environ['GITHUB_REPOSITORY'], os.environ['RELEASE_BRANCH'], os.environ['VERSION'])
    except subprocess.CalledProcessError as error:
        print(error.stderr or str(error), file=sys.stderr)
        sys.exit(error.returncode)
