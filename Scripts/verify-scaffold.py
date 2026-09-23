#!/usr/bin/env python3
"""Infrastructure validation; deliberately makes no source-readiness claim."""

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REQUIRED = (
    '.github/workflows/ci.yml', '.github/workflows/docs.yml', '.gitignore', '.swift-format',
    'CHANGELOG.md', 'CONTRIBUTING.md', 'IMPLEMENTATION_READINESS.md', 'LICENSE',
    'Package.swift', 'README.md', 'Scripts/build-docs.sh', 'Scripts/linux-test.sh',
    'Scripts/verify-scaffold.py', 'Scripts/verify-source.sh', 'Scripts/verify.sh',
)
ROOT = pathlib.Path(__file__).resolve().parent.parent


def append(path, value):
    path.write_text(path.read_text() + value)


def check(root):
    errors = []
    for name in REQUIRED:
        if not (root / name).is_file() or not (root / name).stat().st_size:
            errors.append('Missing required infrastructure: ' + name)
    if errors:
        return errors
    expected_format = {'version': 1, 'indentConditionalCompilationBlocks': False, 'rules': {
        'AllPublicDeclarationsHaveDocumentation': True, 'NeverForceUnwrap': True, 'NeverUseForceTry': True}}
    try:
        if json.loads((root / '.swift-format').read_text()) != expected_format:
            errors.append('Formatting policy differs from the family template')
    except ValueError:
        errors.append('Invalid formatting policy JSON')
    manifest = (root / 'Package.swift').read_text()
    for text in ('// swift-tools-version:6.2', 'products: []', 'dependencies: []',
                 'targets: []', '.default(enabledTraits: [])', 'swiftLanguageModes: [.v6]',
                 '.defaultIsolation(nil)', '.enableUpcomingFeature("NonisolatedNonsendingByDefault")',
                 '.strictMemorySafety()', '.iOS(.v26)', '.macOS(.v26)', '.tvOS(.v26)',
                 '.visionOS(.v26)', '.watchOS(.v26)'):
        if text not in manifest:
            errors.append('Manifest invariant missing: ' + text)
    if 'HTTPPortable' in manifest:
        errors.append('Scaffold must not declare transport traits')
    for name in ('Sources', 'Tests', 'Examples', 'Package.resolved', '.spi.yml'):
        if (root / name).exists():
            errors.append('Scaffold contains implementation artifact: ' + name)
    for workflow in sorted((root / '.github/workflows').glob('*.yml')):
        content = workflow.read_text()
        jobs = re.findall(r'^  ([a-z][a-z_-]*):\n(.*?)(?=^  [a-z][a-z_-]*:|\Z)',
                          content.split('jobs:\n', 1)[-1], re.M | re.S)
        if not jobs:
            errors.append('Workflow has no jobs: ' + workflow.name)
        for name, body in jobs:
            if not re.search(r'^    timeout-minutes: [1-9][0-9]*$', body, re.M):
                errors.append('Unbounded job: ' + name)
            if name != 'scaffold' and '    if: ${{ false }}' not in body:
                errors.append('Implementation job is active: ' + name)
        if workflow.name == 'ci.yml' and not any(name == 'scaffold' for name, _ in jobs):
            errors.append('Missing active scaffold job')
    for shell in sorted((root / 'Scripts').glob('*.sh')):
        if subprocess.run(['bash', '-n', str(shell)], capture_output=True).returncode:
            errors.append('Invalid shell syntax: ' + shell.name)
    tracked = subprocess.run(['git', '-C', str(root), 'ls-files'], capture_output=True, text=True)
    if tracked.returncode:
        errors.append('Git index unavailable')
    for name in tracked.stdout.splitlines():
        if name in ('AGENTS.md', 'CLAUDE.md', 'GEMINI.md') or name.startswith(
                ('.agents/', '.claude/', '.codex/', '.gemini/', '.grok/', 'plans/', '.swiftpm/')):
            errors.append('Local-only file tracked: ' + name)
    return errors


def check_manifest(root, manifest):
    expected_name = (root / 'README.md').read_text().splitlines()[0].removeprefix('# ')
    assert manifest['name'] == expected_name, 'Wrong package name'
    assert manifest['toolsVersion']['_version'] == '6.2.0', 'Wrong tools version'
    assert manifest['swiftLanguageVersions'] == ['6'], 'Wrong language version'
    assert {p['platformName']: p['version'] for p in manifest['platforms']} == {
        name: '26.0' for name in ('ios', 'macos', 'tvos', 'visionos', 'watchos')}, 'Wrong platform floors'
    assert all(manifest[key] == [] for key in ('dependencies', 'products', 'targets')), 'Nonempty graph'
    assert [(t['name'], t.get('enabledTraits', [])) for t in manifest['traits']] == [('default', [])], 'Wrong traits'


def dump_manifest(root):
    result = subprocess.run(['swift', 'package', 'dump-package'], cwd=root,
                            check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def replace(path, old, new):
    path.write_text(path.read_text().replace(old, new))


def self_test():
    mutations = (
        ('required file', lambda p: (p / 'LICENSE').unlink()),
        ('manifest', lambda p: (p / 'Package.swift').write_text('// empty\n')),
        ('format policy', lambda p: (p / '.swift-format').write_text('{}\n')),
        ('source artifact', lambda p: (p / 'Sources').mkdir()),
        ('transport trait', lambda p: append(p / 'Package.swift', '// HTTPPortable\n')),
        ('timeout', lambda p: replace(p / '.github/workflows/ci.yml', 'timeout-minutes:', 'unbounded:')),
        ('active source lane', lambda p: replace(p / '.github/workflows/ci.yml', 'if: ${{ false }}', 'if: ${{ true }}')),
        ('missing scaffold lane', lambda p: replace(p / '.github/workflows/ci.yml', '  scaffold:', '  disabled:')),
        ('shell syntax', lambda p: append(p / 'Scripts/verify.sh', '\nif\n')),
        ('local file tracking', lambda p: track_local(p)),
    )
    with tempfile.TemporaryDirectory(prefix='scaffold-self-test-') as temporary:
        clean = pathlib.Path(temporary) / 'clean'
        shutil.copytree(ROOT, clean, ignore=shutil.ignore_patterns('.git', '.build', '.build-default'))
        subprocess.run(['git', 'init', '-q', str(clean)], check=True)
        assert not check(clean), check(clean)
        for label, mutate in mutations:
            planted = pathlib.Path(temporary) / label.replace(' ', '-')
            shutil.copytree(clean, planted)
            mutate(planted)
            assert check(planted), 'Missed planted violation: ' + label
            print('PASS planted violation: ' + label)
        manifest = dump_manifest(clean)
        check_manifest(clean, manifest)
        for key, value in (('name', 'wrong'), ('toolsVersion', {'_version': '6.1.0'}),
                           ('swiftLanguageVersions', ['5']), ('platforms', []),
                           ('dependencies', [{}]), ('products', [{}]), ('targets', [{}]), ('traits', [])):
            planted_manifest = dict(manifest, **{key: value})
            try:
                check_manifest(clean, planted_manifest)
            except AssertionError:
                print('PASS planted manifest violation: ' + key)
            else:
                raise AssertionError('Missed manifest violation: ' + key)
    print('Infrastructure self-test passed; no implementation checks ran.')


def track_local(root):
    (root / 'CLAUDE.md').write_text('local\n')
    subprocess.run(['git', '-C', str(root), 'add', '-f', 'CLAUDE.md'], check=True)


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        self_test()
    else:
        errors = check(ROOT)
        for error in errors:
            print('FAIL ' + error, file=sys.stderr)
        if errors:
            sys.exit(1)
        subprocess.run(['swift', 'format', 'lint', '--strict', 'Package.swift'], cwd=ROOT, check=True)
        check_manifest(ROOT, dump_manifest(ROOT))
        print('PASS infrastructure only; source, tests, platforms, and documentation remain unverified.')
