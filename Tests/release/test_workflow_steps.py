"""Execute real workflow shell steps against fake gh and temporary files only."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_release_tools import ROOT, r

WORKFLOW = json.loads(subprocess.check_output([
    'ruby', '-rjson', '-ryaml', '-e', 'puts JSON.generate(YAML.load_file(ARGV[0]))',
    str(ROOT / '.github/workflows/release.yml')
], text=True))


class WorkflowStepTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['Scripts', 'runner', 'bin', 'published']:
            (self.root / folder).mkdir()
        shutil.copy2(ROOT / 'Scripts/release_tools.py', self.root / 'Scripts/release_tools.py')
        for kind in ['dmg', 'zip']:
            (self.root / 'published' / f'mq-dir-v0.3.0.{kind}').write_bytes(b'dmg fixture')
        manifest = r.make_manifest(self.root / 'published', '0.3.0', 8, 'a' * 40,
                                   'sparkle:edSignature="' + 'A' * 86 + '==" length="11"')
        (self.root / 'published/release.json').write_text(json.dumps(manifest))
        r.write_checksums(self.root / 'published', '0.3.0')
        gh = self.root / 'bin/gh'
        gh.write_text('''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
root = pathlib.Path(os.environ['FIXTURE_ROOT'])
with (root / 'calls.jsonl').open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\\n')
mode = os.environ['FIXTURE_MODE']
if sys.argv[1] == 'api':
    if mode == 'api-error': sys.exit(1)
    if mode != 'new': print(json.dumps({'draft': mode == 'draft'}))
elif sys.argv[1:3] == ['release', 'download']:
    for path in (root / 'published').iterdir(): shutil.copy2(path, root / 'dist' / path.name)
elif sys.argv[1:3] == ['release', 'create']:
    if mode == 'create-error': sys.exit(1)
elif sys.argv[1:3] == ['release', 'upload']:
    if mode == 'upload-error': sys.exit(1)
elif sys.argv[1:3] == ['release', 'edit']:
    pass
else:
    sys.exit('Unexpected external command in fixture')
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                        FIXTURE_ROOT=str(self.root), RUNNER_TEMP=str(self.root / 'runner'),
                        GITHUB_ENV=str(self.root / 'github-env'), GITHUB_REPOSITORY='h5nam/mq-dir',
                        APP_NAME='mq-dir', VERSION='0.3.0', BUILD_NUMBER='8', RELEASE_SHA='a' * 40)
        self.step = WORKFLOW['jobs']['release']['steps'][1]['run']

    def execute(self, mode):
        return subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', self.step], cwd=self.root,
                              env=dict(self.env, FIXTURE_MODE=mode), text=True, capture_output=True, timeout=15)

    def test_api_failure_stops_before_build_or_download(self):
        result = self.execute('api-error')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('BUILD_RELEASE', (self.root / 'github-env').read_text())
        self.assertEqual(len((self.root / 'calls.jsonl').read_text().splitlines()), 1)

    def test_new_release_enters_build_branch(self):
        result = self.execute('new')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('BUILD_RELEASE=true', (self.root / 'github-env').read_text())

    def test_published_release_reuses_verified_bytes(self):
        result = self.execute('published')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('BUILD_RELEASE=false', (self.root / 'github-env').read_text())
        self.assertEqual((self.root / 'dist/mq-dir-v0.3.0.dmg').read_bytes(), b'dmg fixture')

    def test_changed_published_bytes_stop_recovery(self):
        (self.root / 'published/mq-dir-v0.3.0.dmg').write_bytes(b'changed')
        result = self.execute('published')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('BUILD_RELEASE', (self.root / 'github-env').read_text())

    def test_incomplete_draft_is_not_overwritten(self):
        result = self.execute('draft')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('incomplete draft', result.stderr)
        self.assertEqual(len((self.root / 'calls.jsonl').read_text().splitlines()), 1)

    def execute_publish(self, mode):
        git = self.root / 'bin/git'
        git.write_text('#!/bin/sh\nif [ "$1" = describe ]; then echo v0.2.0; else echo "fixture change"; fi\n')
        git.chmod(0o755)
        (self.root / 'dist').mkdir()
        (self.root / 'dist/fixture').write_text('asset')
        step = next(s['run'] for s in WORKFLOW['jobs']['release']['steps']
                    if s.get('name') == 'Publish new release without replacing existing assets')
        result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', step], cwd=self.root,
                                env=dict(self.env, FIXTURE_MODE=mode, TAG='v0.3.0'),
                                text=True, capture_output=True, timeout=15)
        calls = [json.loads(line) for line in (self.root / 'calls.jsonl').read_text().splitlines()]
        return result, calls

    def test_upload_failure_leaves_draft_unpublished(self):
        result, calls = self.execute_publish('upload-error')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[:2] for call in calls], [['release', 'create'], ['release', 'upload']])
        self.assertIn('--draft', calls[0])

    def test_create_collision_never_uploads_to_existing_release(self):
        result, calls = self.execute_publish('create-error')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)

    def test_publish_occurs_only_after_upload(self):
        result, calls = self.execute_publish('publish')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[:2] for call in calls], [['release', 'create'], ['release', 'upload'], ['release', 'edit']])
        self.assertIn('--verify-tag', calls[0])
        self.assertNotIn('--clobber', calls[1])
        self.assertIn('--draft=false', calls[2])

    def test_all_workflow_shell_blocks_parse(self):
        for job in WORKFLOW['jobs'].values():
            for step in job['steps']:
                if 'run' in step:
                    result = subprocess.run(['bash', '-n'], input=step['run'], text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, (step.get('name'), result.stderr))


if __name__ == '__main__':
    unittest.main()
