#!/usr/bin/env python3
"""Local, deterministic release validation. No network calls or third-party modules."""
import argparse
import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?')


def validate_version(value):
    match = VERSION.fullmatch(value)
    if not match or (match[4] and any(x.isdigit() and len(x) > 1 and x[0] == '0' for x in match[4].split('.'))):
        raise ValueError('Expected SemVer without a v prefix or build metadata')
    return value


def version_is_newer(candidate, current):
    a, b = VERSION.fullmatch(validate_version(candidate)), VERSION.fullmatch(validate_version(current))
    major_a, major_b = tuple(map(int, a.group(1, 2, 3))), tuple(map(int, b.group(1, 2, 3)))
    if major_a != major_b:
        return major_a > major_b
    if a[4] is None or b[4] is None:
        return a[4] is None and b[4] is not None
    left, right = a[4].split('.'), b[4].split('.')
    for x, y in zip(left, right):
        if x == y:
            continue
        if x.isdigit() and y.isdigit():
            return int(x) > int(y)
        if x.isdigit() != y.isdigit():
            return not x.isdigit()
        return x > y
    return len(left) > len(right)


def _field(text, key):
    values = re.findall(r'^\s*' + re.escape(key) + r':\s*"([^"\n]+)"\s*$', text, re.M)
    if len(values) != 1:
        raise ValueError(f'Expected exactly one quoted {key} in project.yml')
    return values[0]


def project_version(path):
    text = Path(path).read_text()
    version = validate_version(_field(text, 'MARKETING_VERSION'))
    build = _field(text, 'CURRENT_PROJECT_VERSION')
    if not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Build number must be a positive integer')
    for field, setting in [('CFBundleVersion', 'CURRENT_PROJECT_VERSION'), ('CFBundleShortVersionString', 'MARKETING_VERSION')]:
        if _field(text, field) != f'$({setting})':
            raise ValueError(f'{field} must reference $({setting})')
    return version, int(build)


def _items(appcast):
    channel = ET.fromstring(appcast).find('channel')
    if channel is None:
        raise ValueError('Appcast is missing its channel')
    return channel.findall('item')


def _text(item, name):
    return item.findtext(f'{{{SPARKLE}}}{name}', default='')


def release_plan(path, version, appcast):
    current, build = project_version(path)
    if not version_is_newer(version, current):
        raise ValueError('Release version must be newer than the current source version')
    published = []
    for item in _items(appcast):
        old_version = _text(item, 'shortVersionString')
        if old_version and not version_is_newer(version, old_version):
            raise ValueError('Release version must be newer than the published appcast')
        old_build = _text(item, 'version')
        if old_build.isdigit():
            published.append(int(old_build))
    return max([build] + published) + 1


def bump_project(path, version, appcast):
    next_build = release_plan(path, version, appcast)
    text = Path(path).read_text()
    for key, value in [('MARKETING_VERSION', version), ('CURRENT_PROJECT_VERSION', str(next_build))]:
        text, count = re.subn(r'(^\s*' + key + r':\s*)"[^"\n]+"', lambda m: m[1] + '"' + value + '"', text, flags=re.M)
        if count != 1:
            raise ValueError(f'Ambiguous {key}')
    Path(path).write_text(text)
    return next_build


def validate_bundle(path, version, build):
    info = plistlib.loads(Path(path).read_bytes())
    expected = {'CFBundleIdentifier': 'com.mqdir.app', 'CFBundleShortVersionString': validate_version(version), 'CFBundleVersion': str(build)}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'Built bundle {key} differs from release metadata')


def _digest(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _identity(version, build, sha):
    validate_version(version)
    if type(build) is not int or build <= 0 or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', sha):
        raise ValueError('Invalid release build number or commit SHA')


def _signature(value):
    try:
        if len(base64.b64decode(value, validate=True)) != 64:
            raise ValueError('Expected a 64-byte EdDSA signature')
    except (TypeError, ValueError) as error:
        raise ValueError('Invalid EdDSA signature encoding') from error


def make_manifest(directory, version, build, sha, signature_line):
    _identity(version, build, sha)
    enclosure = ET.fromstring(f'<enclosure xmlns:sparkle="{SPARKLE}" {signature_line}/>')
    signature = enclosure.get(f'{{{SPARKLE}}}edSignature', '')
    _signature(signature)
    result = dict(format=1, version=version, build=build, tag_sha=sha,
                  pub_date=format_datetime(datetime.now(timezone.utc)))
    for kind in ['dmg', 'zip']:
        name = f'mq-dir-v{version}.{kind}'
        path = Path(directory) / name
        result[kind] = dict(name=name, sha256=_digest(path), length=path.stat().st_size)
    if int(enclosure.get('length', '-1')) != result['dmg']['length']:
        raise ValueError('Sparkle signature length differs from DMG size')
    result['dmg']['signature'] = signature
    return result


def verify_artifacts(directory, manifest, version, build, sha):
    _identity(version, build, sha)
    if (manifest.get('format'), manifest.get('version'), manifest.get('build'), manifest.get('tag_sha')) != (1, version, build, sha):
        raise ValueError('Published manifest does not match the requested version/build/tag commit')
    _signature(manifest['dmg']['signature'])
    for kind in ['dmg', 'zip']:
        record = manifest[kind]
        expected_name = f'mq-dir-v{version}.{kind}'
        if record['name'] != expected_name:
            raise ValueError('Manifest contains an unexpected artifact filename')
        path = Path(directory) / expected_name
        if path.is_symlink() or path.stat().st_size != record['length'] or _digest(path) != record['sha256']:
            raise ValueError(f'Published {kind} bytes do not match the manifest')


def write_checksums(directory, version):
    names = [f'mq-dir-v{validate_version(version)}.dmg', f'mq-dir-v{version}.zip', 'release.json']
    (Path(directory) / 'SHA256SUMS').write_text(''.join(f'{_digest(Path(directory) / name)}  {name}\n' for name in names))


def verify_checksums(directory, version):
    expected = {f'mq-dir-v{validate_version(version)}.dmg', f'mq-dir-v{version}.zip', 'release.json'}
    records = {}
    for line in (Path(directory) / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match or match[2] not in expected or match[2] in records:
            raise ValueError('Unexpected or duplicate filename in SHA256SUMS')
        records[match[2]] = match[1]
    if set(records) != expected:
        raise ValueError('SHA256SUMS must cover exactly the release artifacts and manifest')
    for name, digest in records.items():
        path = Path(directory) / name
        if path.is_symlink() or _digest(path) != digest:
            raise ValueError(f'Checksum mismatch for {name}')


def metadata_content(appcast, cask, manifest, repository):
    version, build = manifest['version'], manifest['build']
    _identity(version, build, manifest['tag_sha'])
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid repository name')
    dmg = manifest['dmg']
    _signature(dmg['signature'])
    if dmg['name'] != f'mq-dir-v{version}.dmg' or not re.fullmatch(r'[0-9a-f]{64}', dmg['sha256']) or type(dmg['length']) is not int or dmg['length'] <= 0:
        raise ValueError('Invalid DMG metadata')
    url = f'https://github.com/{repository}/releases/download/v{version}/{dmg["name"]}'
    items = _items(appcast)
    matches = [item for item in items if _text(item, 'shortVersionString') == version or _text(item, 'version') == str(build)]
    if matches:
        if len(matches) != 1:
            raise ValueError('Duplicate appcast version/build')
        item = matches[0]
        enclosure = item.find('enclosure')
        if (_text(item, 'shortVersionString'), _text(item, 'version')) != (version, str(build)) or enclosure is None:
            raise ValueError('Appcast version/build collision')
        expected = {'url': url, 'length': str(dmg['length']), f'{{{SPARKLE}}}edSignature': dmg['signature']}
        if any(enclosure.get(key) != value for key, value in expected.items()):
            raise ValueError('Existing appcast item differs from published artifact; refusing replacement')
        newer = any(_text(other, 'version').isdigit() and int(_text(other, 'version')) > build for other in items)
        if newer:
            return appcast, cask  # Recovery of an old release must not roll back the cask.
    else:
        for item in items:
            old_build = _text(item, 'version')
            old_version = _text(item, 'shortVersionString')
            if old_build.isdigit() and int(old_build) >= build:
                raise ValueError('Release build is older than the current appcast')
            if old_version and not version_is_newer(version, old_version):
                raise ValueError('Release version is older than the current appcast')
        if appcast.count('APPCAST-PREPEND-MARKER') != 1:
            raise ValueError('Expected exactly one appcast insertion marker')
        marker = re.search(r'<!--(?:(?!-->).)*APPCAST-PREPEND-MARKER(?:(?!-->).)*-->', appcast, re.S)
        if not marker:
            raise ValueError('Appcast marker must be an XML comment')
        item = f'''
    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{escape(manifest['pub_date'])}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url={quoteattr(url)} sparkle:edSignature={quoteattr(dmg['signature'])} length="{dmg['length']}" type="application/octet-stream" />
    </item>'''
        appcast = appcast[:marker.end()] + item + appcast[marker.end():]
        ET.fromstring(appcast)
    for key, value in [('version', version), ('sha256', dmg['sha256'])]:
        cask, count = re.subn(r'(^\s*' + key + r'\s+)"[^"\n]*"', lambda m: m[1] + '"' + value + '"', cask, flags=re.M)
        if count != 1:
            raise ValueError(f'Expected exactly one cask {key}')
    return appcast, cask


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['version', 'source', 'plan', 'bump', 'bundle', 'manifest', 'verify', 'metadata'])
    parser.add_argument('--version')
    parser.add_argument('--build', type=int)
    parser.add_argument('--sha')
    parser.add_argument('--project', type=Path, default=Path('project.yml'))
    parser.add_argument('--appcast', type=Path, default=Path('docs/appcast.xml'))
    parser.add_argument('--cask', type=Path, default=Path('Casks/mq-dir.rb'))
    parser.add_argument('--plist', type=Path)
    parser.add_argument('--directory', type=Path, default=Path('dist'))
    parser.add_argument('--manifest', type=Path, default=Path('dist/release.json'))
    parser.add_argument('--signature')
    parser.add_argument('--repository')
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    if args.command == 'version':
        print(validate_version(args.version))
    elif args.command == 'source':
        version, build = project_version(args.project)
        if args.version is not None and args.version != version:
            raise ValueError('Tag version differs from source version')
        print(f'version={version}\nbuild={build}')
    elif args.command == 'plan':
        build = release_plan(args.project, args.version, args.appcast.read_text())
        print(f'version={args.version}\nbuild={build}')
    elif args.command == 'bump':
        print(bump_project(args.project, args.version, args.appcast.read_text()))
    elif args.command == 'bundle':
        validate_bundle(args.plist, args.version, args.build)
    elif args.command == 'manifest':
        manifest = make_manifest(args.directory, args.version, args.build, args.sha, args.signature)
        args.manifest.write_text(json.dumps(manifest, indent=2) + '\n')
        write_checksums(args.directory, args.version)
    elif args.command == 'verify':
        verify_checksums(args.directory, args.version)
        verify_artifacts(args.directory, json.loads(args.manifest.read_text()), args.version, args.build, args.sha)
    elif args.command == 'metadata':
        appcast, cask = metadata_content(args.appcast.read_text(), args.cask.read_text(), json.loads(args.manifest.read_text()), args.repository)
        if not args.check_only:
            if appcast != args.appcast.read_text():
                args.appcast.write_text(appcast)
            if cask != args.cask.read_text():
                args.cask.write_text(cask)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, TypeError, KeyError, OSError, ET.ParseError) as error:
        sys.exit(f'release validation failed: {error}')
