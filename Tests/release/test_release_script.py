import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_release_tools import PROJECT, FEED, ROOT


class ReleaseScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q', '-b', 'main')
        for key, value in [('user.name', 'Release Test'), ('user.email', 'fixture@example.test'),
                           ('commit.gpgsign', 'false'), ('tag.gpgsign', 'false'),
                           ('core.hooksPath', str(self.root / 'no-hooks'))]:
            self.git('config', key, value)
        for directory in ['Scripts', 'docs', 'Config', 'Sources/mq-dir']:
            (self.repo / directory).mkdir(parents=True, exist_ok=True)
        for name in ['release.sh', 'release_tools.py', 'generate-project.sh']:
            shutil.copy2(ROOT / 'Scripts' / name, self.repo / 'Scripts' / name)
        (self.repo / 'project.yml').write_text(PROJECT)
        (self.repo / 'docs/appcast.xml').write_text(FEED)
        (self.repo / 'Config/Package.resolved').write_text('{"pins": []}')
        (self.repo / 'Sources/mq-dir/Info.plist').write_text('generated fixture')
        (self.repo / '.gitignore').write_text('*.xcodeproj/\n__pycache__/\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.remote = self.root / 'origin.git'
        subprocess.run(['git', 'init', '--bare', '-q', str(self.remote)], check=True)
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', '-q', 'origin', 'main')
        self.env = dict(os.environ)
        fake_bin = self.root / 'bin'
        fake_bin.mkdir()
        generator = fake_bin / 'xcodegen'
        generator.write_text('#!/bin/sh\nexit 0\n')
        generator.chmod(0o755)
        self.env['PATH'] = str(fake_bin) + os.pathsep + self.env['PATH']

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, text=True, stderr=subprocess.STDOUT).strip()

    def release(self, *args):
        return subprocess.run(['bash', 'Scripts/release.sh', *args], cwd=self.repo, env=self.env,
                              capture_output=True, text=True, timeout=20)

    def test_dry_run_does_not_change_files_refs_or_remote(self):
        head = self.git('rev-parse', 'HEAD')
        result = self.release('--dry-run', '0.3.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD'), head)
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.assertEqual(self.git('tag'), '')
        self.assertEqual((self.repo / 'project.yml').read_text(), PROJECT)

    def test_other_branch_and_untracked_files_are_rejected(self):
        self.git('checkout', '-qb', 'feature')
        result = self.release('--dry-run', '0.3.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('main', result.stderr)
        self.git('checkout', '-q', 'main')
        (self.repo / 'unfinished.swift').write_text('unfinished')
        result = self.release('--dry-run', '0.3.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('untracked', result.stderr)

    def test_local_main_must_match_remote_tracking_commit(self):
        self.git('commit', '--allow-empty', '-qm', 'local only')
        result = self.release('--dry-run', '0.3.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('match origin/main', result.stderr)

    def test_existing_tag_and_shell_input_do_not_mutate_source(self):
        self.git('tag', 'v0.3.0')
        for version in ['0.3.0', '0.3.1; touch escaped']:
            self.assertNotEqual(self.release('--dry-run', version).returncode, 0)
        self.assertEqual((self.repo / 'project.yml').read_text(), PROJECT)
        self.assertFalse((self.repo / 'escaped').exists())

    def test_rejected_tag_cannot_push_main_without_it(self):
        before = self.git('rev-parse', 'origin/main')
        hooks = self.remote / 'hooks'
        subprocess.run(['git', '--git-dir', str(self.remote), 'config', 'core.hooksPath', str(hooks)], check=True)
        hook = hooks / 'update'
        hook.write_text('#!/bin/sh\ncase "$1" in refs/tags/*) exit 1;; esac\nexit 0\n')
        hook.chmod(0o755)
        result = self.release('0.3.0')
        self.assertNotEqual(result.returncode, 0)
        main = subprocess.check_output(['git', '--git-dir', str(self.remote), 'rev-parse', 'refs/heads/main'], text=True).strip()
        self.assertEqual(main, before)
        tag = subprocess.run(['git', '--git-dir', str(self.remote), 'show-ref', '--verify', '--quiet', 'refs/tags/v0.3.0'])
        self.assertNotEqual(tag.returncode, 0)

    def test_real_script_pushes_main_and_tag_to_same_local_commit(self):
        result = self.release('0.3.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        refs = subprocess.check_output(['git', '--git-dir', str(self.remote), 'rev-parse',
                                        'refs/heads/main', 'refs/tags/v0.3.0^{commit}'], text=True).splitlines()
        self.assertEqual(refs[0], refs[1])
        self.assertEqual(refs[0], self.git('rev-parse', 'HEAD'))
        self.assertIn('CURRENT_PROJECT_VERSION: "8"', (self.repo / 'project.yml').read_text())
        self.assertIn('Signed-off-by:', self.git('log', '-1', '--format=%B'))


if __name__ == '__main__':
    unittest.main()
