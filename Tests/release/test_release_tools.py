import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_tools', ROOT / 'Scripts/release_tools.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

PROJECT = '''settings:
  base:
    MARKETING_VERSION: "0.2.0"
    CURRENT_PROJECT_VERSION: "7"
info:
  CFBundleShortVersionString: "$(MARKETING_VERSION)"
  CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
'''
FEED = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<!-- APPCAST-PREPEND-MARKER -->
<item><sparkle:version>7</sparkle:version><sparkle:shortVersionString>0.2.0</sparkle:shortVersionString></item>
</channel></rss>'''
CASK = 'cask "mq-dir" do\n  version "0.2.0"\n  sha256 "' + 'a' * 64 + '"\nend\n'


class ReleaseToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'project.yml'
        self.project.write_text(PROJECT)

    def manifest(self, version='0.3.0', build=8):
        (self.root / f'mq-dir-v{version}.dmg').write_bytes(b'dmg fixture')
        (self.root / f'mq-dir-v{version}.zip').write_bytes(b'zip fixture')
        return r.make_manifest(self.root, version, build, 'a' * 40,
                               'sparkle:edSignature="' + 'A' * 86 + '==" length="11"')

    def test_version_validation_rejects_shell_input_and_invalid_semver(self):
        for value in ['', '1.2', 'v1.2.3', '01.2.3', '1.2.3\n', '1.2.3-01', '1.2.3-..', '1.2.3;touch /tmp/no', '$(id)', '1.2.3+meta']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                r.validate_version(value)
        for value in ['0.2.1', '1.0.0-beta.2', '1.0.0-rc-test.1']:
            self.assertEqual(r.validate_version(value), value)

    def test_bump_uses_one_version_source_and_increments_build(self):
        self.assertEqual(r.bump_project(self.project, '0.3.0', FEED), 8)
        self.assertEqual(r.project_version(self.project), ('0.3.0', 8))
        self.assertIn('CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"', self.project.read_text())

    def test_bump_rejects_same_or_older_version_without_mutation(self):
        for version in ['0.2.0', '0.1.9', '0.2.0-beta.2']:
            with self.assertRaises(ValueError):
                r.bump_project(self.project, version, FEED)
            self.assertEqual(self.project.read_text(), PROJECT)

    def test_plan_rejects_a_version_behind_published_feed(self):
        feed = FEED.replace('>0.2.0<', '>0.4.0<').replace('>7<', '>9<')
        with self.assertRaises(ValueError):
            r.release_plan(self.project, '0.3.0', feed)
        self.assertEqual(self.project.read_text(), PROJECT)

    def test_build_number_advances_past_published_maximum(self):
        self.assertEqual(r.release_plan(self.project, '0.3.0', FEED.replace('>7<', '>12<')), 13)

    def test_prerelease_order_uses_numeric_identifiers(self):
        self.assertTrue(r.version_is_newer('1.0.0-beta.10', '1.0.0-beta.2'))
        self.assertTrue(r.version_is_newer('1.0.0', '1.0.0-rc.9'))
        self.assertFalse(r.version_is_newer('1.0.0-beta.2', '1.0.0-beta.10'))

    def test_duplicated_or_literal_bundle_versions_are_rejected(self):
        for text in [PROJECT + 'MARKETING_VERSION: "0.2.0"\n', PROJECT.replace('$(CURRENT_PROJECT_VERSION)', '8')]:
            self.project.write_text(text)
            with self.assertRaises(ValueError):
                r.project_version(self.project)

    def test_bundle_must_match_version_build_and_identity(self):
        info = self.root / 'Info.plist'
        def write(version, build, identity='com.mqdir.app'):
            info.write_bytes(plistlib.dumps(dict(CFBundleShortVersionString=version, CFBundleVersion=build, CFBundleIdentifier=identity)))
        write('0.3.0', '8')
        r.validate_bundle(info, '0.3.0', 8)
        for values in [('0.2.0', '8'), ('0.3.0', '7'), ('0.3.0', '8', 'other.app')]:
            write(*values)
            with self.assertRaises(ValueError):
                r.validate_bundle(info, '0.3.0', 8)

    def test_manifest_verifies_bytes_and_tag_commit(self):
        manifest = self.manifest()
        r.verify_artifacts(self.root, manifest, '0.3.0', 8, 'a' * 40)
        with self.assertRaises(ValueError):
            r.verify_artifacts(self.root, manifest, '0.3.0', 8, 'b' * 40)
        (self.root / 'mq-dir-v0.3.0.dmg').write_bytes(b'changed bytes')
        with self.assertRaises(ValueError):
            r.verify_artifacts(self.root, manifest, '0.3.0', 8, 'a' * 40)

    def test_manifest_cannot_select_arbitrary_local_paths(self):
        manifest = self.manifest()
        manifest['dmg']['name'] = '../private-file'
        with self.assertRaises(ValueError):
            r.verify_artifacts(self.root, manifest, '0.3.0', 8, 'a' * 40)

    def test_signature_length_must_match_actual_dmg(self):
        self.manifest()
        with self.assertRaises(ValueError):
            r.make_manifest(self.root, '0.3.0', 8, 'a' * 40, 'sparkle:edSignature="bad" length="12"')

    def test_checksums_include_manifest_and_detect_changed_metadata(self):
        manifest = self.manifest()
        (self.root / 'release.json').write_text(json.dumps(manifest))
        r.write_checksums(self.root, '0.3.0')
        r.verify_checksums(self.root, '0.3.0')
        (self.root / 'release.json').write_text(json.dumps(manifest) + ' ')
        with self.assertRaises(ValueError):
            r.verify_checksums(self.root, '0.3.0')

    def test_checksum_list_cannot_read_unexpected_paths(self):
        (self.root / 'SHA256SUMS').write_text('a' * 64 + '  ../unexpected\n')
        with self.assertRaises(ValueError):
            r.verify_checksums(self.root, '0.3.0')

    def test_appcast_rerun_is_byte_identical(self):
        manifest = self.manifest()
        feed, cask = r.metadata_content(FEED, CASK, manifest, 'h5nam/mq-dir')
        self.assertEqual(r.metadata_content(feed, cask, manifest, 'h5nam/mq-dir'), (feed, cask))
        self.assertEqual(feed.count('<sparkle:version>8</sparkle:version>'), 1)
        self.assertIn('version "0.3.0"', cask)

    def test_same_release_with_different_bytes_is_rejected(self):
        manifest = self.manifest()
        feed, cask = r.metadata_content(FEED, CASK, manifest, 'h5nam/mq-dir')
        manifest['dmg']['signature'] = 'B' * 86 + '=='
        with self.assertRaises(ValueError):
            r.metadata_content(feed, cask, manifest, 'h5nam/mq-dir')

    def test_late_new_release_cannot_roll_back_channel(self):
        manifest = self.manifest()
        feed = FEED.replace('>7<', '>9<').replace('>0.2.0<', '>0.4.0<')
        with self.assertRaises(ValueError):
            r.metadata_content(feed, CASK, manifest, 'h5nam/mq-dir')

    def test_recovery_of_existing_older_release_keeps_newest_cask(self):
        old = self.manifest()
        feed, cask = r.metadata_content(FEED, CASK, old, 'h5nam/mq-dir')
        newer = self.manifest('0.4.0', 9)
        feed, cask = r.metadata_content(feed, cask, newer, 'h5nam/mq-dir')
        self.assertEqual(r.metadata_content(feed, cask, old, 'h5nam/mq-dir'), (feed, cask))

    def test_bad_marker_or_cask_is_rejected_before_output(self):
        manifest = self.manifest()
        for feed, cask in [(FEED.replace('APPCAST-PREPEND-MARKER', 'missing'), CASK), (FEED, 'broken cask')]:
            with self.assertRaises(ValueError):
                r.metadata_content(feed, cask, manifest, 'h5nam/mq-dir')


if __name__ == '__main__':
    unittest.main()
