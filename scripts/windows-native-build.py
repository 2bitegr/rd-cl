"""Pinned native Windows build; writes only to explicitly owned tool/build roots.

Run through windows-native-build.ps1 using a reviewed machine-local toolchain JSON.
Uses existing caches only; missing dependencies stop the build.
No downloads, dependency upgrades, product execution, signing, Git commits or deployment.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import tomllib
import subprocess
import tempfile
import secrets
import stat
import sys
from datetime import datetime
import zipfile
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save(path, value):
    # Preserve the previous receipt even if a full volume rejects the new write.
    path = Path(path)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + '.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            stream.write(json.dumps(value, indent=2))
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def offline_environment(environment):
    """Process-only policy, including children that invoke Cargo/Git/HTTP tools."""
    result = environment.copy()
    result.update({
        'CARGO_NET_OFFLINE': 'true', 'GIT_NO_LAZY_FETCH': '1',
        'GIT_ALLOW_PROTOCOL': 'file', 'GIT_TERMINAL_PROMPT': '0',
        'GIT_NO_REPLACE_OBJECTS': '1',
        'X_VCPKG_ASSET_SOURCES': 'clear;x-block-origin',
        'VCPKG_BINARY_SOURCES': 'clear',
        'FLUTTER_STORAGE_BASE_URL': 'http://127.0.0.1:9',
        'RUSTUP_DIST_SERVER': 'http://127.0.0.1:9',
        'RUSTUP_UPDATE_ROOT': 'http://127.0.0.1:9',
        'PIP_NO_INDEX': '1', 'PIP_DISABLE_PIP_VERSION_CHECK': '1',
    })
    # Defense in depth for SDK/plugin helpers; no global proxy/firewall changes.
    for key in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY',
                'http_proxy', 'https_proxy', 'all_proxy']:
        result[key] = 'http://127.0.0.1:9'
    result['NO_PROXY'] = result['no_proxy'] = 'localhost,127.0.0.1,::1'
    return result


WINDOWS_SDK_VERSION = '10.0.22621.0'
SDK_INPUTS = ['Include/{version}/um/Windows.h', 'Include/{version}/shared/sdkddkver.h',
              'Include/{version}/ucrt/corecrt.h', 'Lib/{version}/um/x64/kernel32.lib',
              'Lib/{version}/ucrt/x64/ucrt.lib', 'Lib/{version}/ucrt/x64/libucrt.lib']


def native_triplet(profile):
    version = profile.get('windows_sdk_version', WINDOWS_SDK_VERSION)
    if not re.fullmatch(r'10\.0\.\d+\.0', version):
        raise RuntimeError('Invalid pinned Windows SDK version')
    return ('set(VCPKG_TARGET_ARCHITECTURE x64)\r\n'
            'set(VCPKG_CRT_LINKAGE static)\r\nset(VCPKG_LIBRARY_LINKAGE static)\r\n'
            'set(VCPKG_BUILD_TYPE release)\r\n'
            'set(VCPKG_CMAKE_SYSTEM_VERSION ' + version + ')\r\n').encode('ascii')


def runtime_inventory(root):
    root = Path(root)
    files = {}
    pending = [root]
    while pending:
        directory = pending.pop()
        info = directory.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
            raise RuntimeError('Runtime link/reparse point is not a verified payload: ' + str(directory))
        with os.scandir(directory) as entries:
            for entry in sorted(entries, key=lambda item: item.name):
                path = Path(entry.path)
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
                    raise RuntimeError('Runtime link/reparse point is not a verified payload: ' + str(path))
                if stat.S_ISDIR(info.st_mode):
                    pending.append(path)
                elif stat.S_ISREG(info.st_mode):
                    files[path.relative_to(root).as_posix()] = digest(path)
                else:
                    raise RuntimeError('Unexpected runtime entry: ' + str(path))
    return files


class BuildLocks:
    """Non-blocking per-user resource locks. Never guess or erase a stale owner."""
    def __init__(self, directory, resources):
        self.directory = Path(directory)
        self.owned = []
        self.resources = sorted(set(resources))

    def acquire(self):
        self.directory.mkdir(parents=True, exist_ok=True)
        try:
            for resource in self.resources:
                name = hashlib.sha256(resource.encode()).hexdigest() + '.lock'
                path = self.directory / name
                token = json.dumps({'pid': os.getpid(), 'resource': resource, 'token': secrets.token_hex(24)})
                try:
                    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                except FileExistsError as error:
                    raise RuntimeError('Build resource locked; preserve owner/stale lock for inspection: ' + str(path)) from error
                identity = os.fstat(descriptor)
                try:
                    with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
                        stream.write(token)
                except BaseException:
                    current = path.lstat()
                    if (current.st_dev, current.st_ino) == (identity.st_dev, identity.st_ino) and not path.is_symlink():
                        path.unlink()
                    raise
                self.owned.append((path, token))
        except BaseException:
            self.close()
            raise

    def close(self):
        for path, token in reversed(self.owned[:]):
            if path.is_symlink() or path.read_text(encoding='utf-8') != token:
                raise RuntimeError('Build lock ownership changed; preserve for inspection: ' + str(path))
            path.unlink()
            self.owned.remove((path, token))


def require_submodule_tree(git, root, commit, patch, environment, scratch, allow_unpatched=True):
    """Compare worktree with a temporary index for pinned tree + exact public patch.

    Real index/worktree are never reset or cleaned. Only the owned temporary
    index is patched; Git handles CRLF normalization during comparisons.
    """
    with tempfile.TemporaryDirectory(prefix='submodule-audit-', dir=scratch) as directory:
        env = environment.copy()
        env['GIT_INDEX_FILE'] = str(Path(directory) / 'index')
        git('hbb-audit-read-tree', '-c', 'core.autocrlf=input', 'read-tree', commit, cwd=root, env=env)

        def matches(label):
            code, _ = git(label, '-c', 'core.autocrlf=input', 'diff', '--exit-code', '--no-ext-diff', '--', cwd=root, env=env, check=False)
            if code not in (0, 1):
                raise RuntimeError('Cannot inspect pinned submodule worktree')
            _, others = git(label + '-untracked', '-c', 'core.autocrlf=input', 'ls-files', '--others', '--exclude-standard', '-z', cwd=root, env=env)
            return code == 0 and not others

        if allow_unpatched and matches('hbb-audit-base'):
            return 'PINNED'
        git('hbb-audit-patch', '-c', 'core.autocrlf=input', 'apply', '--cached', '--ignore-whitespace', '--ignore-space-change',
            '--unidiff-zero', str(patch), cwd=root, env=env)
        if not matches('hbb-audit-patched'):
            raise RuntimeError('hbb_common differs from pinned source plus the exact reviewed patch; preserve dirty work')
        return 'PATCHED'


def require_files(paths):
    missing = [str(path) for path in paths if not Path(path).is_file()]
    if missing:
        raise RuntimeError('Missing cached dependency; downloads are disabled: ' + ', '.join(missing))


def require_source_pin(profile, requested, head, working_profile, committed_profile):
    # A tracked profile cannot embed its own future commit hash. The reviewed
    # handoff supplies that immutable SHA; never accept a branch/moving alias.
    if not re.fullmatch(r'[0-9a-f]{40}', requested) or head != requested:
        raise RuntimeError('SourceCommit must be the exact full snapshot HEAD')
    if profile.get('source_commit_policy') != 'exact-published-invocation':
        raise RuntimeError('Unknown source commit policy')
    if working_profile != committed_profile:
        raise RuntimeError('Build profile differs from the requested source commit')


def report_failure(build, error):
    # A full log volume must not hide the error that stopped the build.
    print(str(error), file=sys.stderr)
    try:
        save(build.logs / 'result.json', {'mode': build.args.mode, 'status': 'BLOCKED', 'error': str(error)})
    except OSError as diagnostic:
        print('Could not write result.json: ' + str(diagnostic), file=sys.stderr)
    return 1


def require_installed_vcpkg_plan(text, ports=None):
    # This pinned manifest is nonempty. Accept only the known no-action plan;
    # an unfamiliar plan or any install/rebuild/removal requires investigation.
    headings = re.findall(r'^The following packages[^\r\n]*', text, re.MULTILINE)
    if headings != ['The following packages are already installed:']:
        raise RuntimeError('vcpkg requires missing/changed libraries or returned an unknown plan; '
                           'existing installations are preserved and downloads are disabled. See vcpkg-plan logs.')
    if ports is not None:
        entries = re.findall(r'^\s*(?:\*\s+)?([a-z0-9-]+)(?:\[[^\]]+\])?:([a-z0-9-]+)@([^\s]+)',
                             text, re.MULTILINE)
        expected = {name: pin['baseline'] + ('#' + str(pin['port-version']) if pin['port-version'] else '')
                    for name, pin in ports.items()}
        if ({name: version for name, triplet, version in entries} != expected or
                len(entries) != len(expected) or
                any(triplet != 'x64-windows-static' for name, triplet, version in entries)):
            raise RuntimeError('Installed vcpkg plan differs from the reviewed codec dependency closure')


def require_vcpkg_objects(git, profile, ports, overlays=None):
    """Audit the builtin registry's selected snapshots, never commit ancestry.

    git is the offline, logged runner bound to the vcpkg root. Git show resolves
    the baseline commit/path; version databases select trees; ls-tree/read-tree
    need those trees and every descendant blob, not their introducing commits.
    """
    baseline = profile['vcpkg_commit']
    if not re.fullmatch(r'[0-9a-f]{40}', baseline) or not ports:
        raise RuntimeError('Invalid pinned vcpkg object audit inputs')
    _, head = git('vcpkg-object-head', 'rev-parse', 'HEAD')
    if head.strip() != baseline:
        raise RuntimeError('Vcpkg checkout mismatch during object audit')
    _, kind = git('vcpkg-baseline-commit', 'cat-file', '-t', baseline)
    if kind.strip() != 'commit':
        raise RuntimeError('Pinned vcpkg baseline is not a commit')
    _, raw = git('vcpkg-baseline', 'show', baseline + ':versions/baseline.json')
    versions = json.loads(raw)['default']
    # vcpkg reads versions files from disk. Do not audit committed metadata while
    # allowing different working recipes/metadata/scripts/triplets to be used.
    git('vcpkg-object-worktree', 'diff', '--exit-code', 'HEAD', '--',
        'versions', 'ports', 'scripts', 'triplets')
    overlays = overlays or {}
    if not set(overlays).issubset(ports) or set(overlays).intersection(profile.get('vcpkg_override_trees', {})):
        raise RuntimeError('Unexpected overlay in the pinned dependency closure')
    trees = {}
    for name, pin in sorted(ports.items()):
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', name):
            raise RuntimeError('Invalid pinned port name')
        if name in overlays:
            overlay = overlays[name]
            if (overlay.get('name') != name or overlay.get('port-version', 0) != pin['port-version'] or
                    not any(overlay.get(key) == pin['baseline'] for key in
                            ['version', 'version-semver', 'version-date', 'version-string'])):
                raise RuntimeError('Pinned overlay version differs: ' + name)
            # vcpkg overlays bypass builtin registry recipe/version selection.
            # Their bytes were checked by the unchanged codec receipt verifier.
            continue
        if name not in profile.get('vcpkg_override_trees', {}) and versions.get(name) != pin:
            raise RuntimeError('Pinned baseline version differs: ' + name)
        _, raw = git('port-' + name + '-versions', 'show',
                     baseline + ':versions/' + name[0] + '-/' + name + '.json')
        matches = [entry for entry in json.loads(raw)['versions']
                   if entry.get('port-version', 0) == pin['port-version'] and
                   any(entry.get(key) == pin['baseline'] for key in
                       ['version', 'version-semver', 'version-date', 'version-string'])]
        if len(matches) != 1:
            raise RuntimeError('Missing/ambiguous pinned port version: ' + name)
        tree = matches[0]['git-tree']
        if (not re.fullmatch(r'[0-9a-f]{40}', tree) or
                (name in profile.get('vcpkg_override_trees', {}) and
                 tree != profile['vcpkg_override_trees'][name])):
            raise RuntimeError('Pinned override tree mismatch: ' + name)
        _, kind = git('port-' + name + '-root', 'cat-file', '-t', tree)
        if kind.strip() != 'tree':
            raise RuntimeError('Pinned port root is not a tree: ' + name)
        _, listing = git('port-' + name + '-tree', 'ls-tree', '-r', '-t', tree)
        if not listing.strip():
            raise RuntimeError('Empty pinned port tree: ' + name)
        for index, entry in enumerate(listing.splitlines()):
            mode, kind, oid = entry.split('\t', 1)[0].split()
            if kind not in ['tree', 'blob'] or not re.fullmatch(r'[0-9a-f]{40}', oid):
                raise RuntimeError('Invalid pinned port object: ' + name)
            _, actual = git('port-' + name + '-object-' + str(index), 'cat-file', '-t', oid)
            if actual.strip() != kind:
                raise RuntimeError('Pinned port object type mismatch: ' + name)
        trees[name] = tree
    if not set(profile.get('vcpkg_override_trees', {})).issubset(trees):
        raise RuntimeError('Unaudited pinned override')
    return trees


class Build:
    def __init__(self, args):
        self.drive_created = False
        self.session_locks = None
        try:
            self._initialize(args)
        except BaseException as error:
            try:
                self.close()
            except Exception as cleanup:
                error.add_note('Build cleanup also failed; preserve locks/state: ' + str(cleanup))
            raise

    def _initialize(self, args):
        if os.name != 'nt':
            raise RuntimeError('This workflow requires native Windows Python/MSVC.')
        self.args = args
        self.cfg = json.loads(Path(args.toolchain).read_text(encoding='utf-8-sig'))
        self.profile = json.loads(Path(__file__).with_name('windows-native-profile.json').read_text(encoding='utf-8'))
        artifact_root = Path(self.cfg['artifact_root']).resolve()
        physical_source = Path(self.cfg['source']).resolve()
        if not physical_source.is_relative_to(artifact_root / 'Scratch'):
            raise RuntimeError('Source must be an explicitly owned native Desktop Scratch snapshot')
        marker = json.loads((physical_source / '.rd-cl-native-snapshot.json').read_text(encoding='utf-8'))
        if marker.get('source_commit') != args.source_commit:
            raise RuntimeError('Snapshot ownership/revision marker mismatch')
        if not Path(args.output_root).resolve().is_relative_to(artifact_root / 'Builds/rd-cl'):
            raise RuntimeError('OutputRoot must remain within this artifact root Builds/rd-cl')
        if self.cfg.get('drive_alias') and os.path.normcase(self.cfg['drive_alias']['target']) != os.path.normcase(str(artifact_root)):
            raise RuntimeError('Drive alias must point only at this reviewed artifact root')
        # Acquire before SUBST, generated files, logs or native build mutation.
        normalize = lambda path: os.path.normcase(str(Path(path).resolve()))
        resources = ['source:' + normalize(physical_source),
                     'output:' + normalize(args.output_root),
                     'cargo:' + normalize(self.cfg['environment'].get('CARGO_TARGET_DIR', os.environ.get('CARGO_TARGET_DIR', physical_source / 'target'))),
                     'flutter:' + normalize(self.cfg['paths']['flutter']),
                     'vcpkg:' + normalize(self.cfg['paths']['vcpkg'])]
        if self.cfg.get('drive_alias'):
            resources.append('alias:' + self.cfg['drive_alias']['drive'].upper())
        if getattr(args, 'codec_root', None):
            resources.append('codec:' + normalize(args.codec_root))
        lock_home = Path(os.environ.get('LOCALAPPDATA', tempfile.gettempdir()))
        self.session_locks = BuildLocks(lock_home / 'ExantasBuildLocks/rd-cl', resources)
        self.session_locks.acquire()
        self.drive_created = False
        alias = self.cfg.get('drive_alias')
        if alias:
            drive, target = alias['drive'].upper(), alias['target']
            if not re.fullmatch(r'[D-Z]:', drive) or not Path(target).is_absolute():
                raise RuntimeError('Invalid optional short drive alias')
            subst = Path(os.environ.get('SYSTEMROOT', r'C:\Windows')) / 'System32/subst.exe'
            current = subprocess.run([subst], capture_output=True, text=True,
                                     creationflags=subprocess.CREATE_NO_WINDOW, check=True).stdout
            mapping = next((line.split(' => ', 1)[1] for line in current.splitlines()
                            if line.upper().startswith(drive + '\\: => ')), None)
            if mapping and os.path.normcase(mapping) != os.path.normcase(target):
                raise RuntimeError('Short drive is already mapped elsewhere')
            if not mapping:
                if Path(drive + '\\').exists():
                    raise RuntimeError('Short drive is occupied; refusing to replace it')
                subprocess.run([subst, drive, target], check=True,
                               creationflags=subprocess.CREATE_NO_WINDOW)
                self.drive_created = True
            # Aliases preserve physical Desktop storage while avoiding Cargo/libgit2 MAX_PATH.
            def shorten(value):
                return drive + value[len(target):] if value.lower().startswith(target.lower() + '\\') else value
            self.cfg['source'] = shorten(self.cfg['source'])
            self.cfg['paths'] = {key: shorten(value) for key, value in self.cfg['paths'].items()}
            self.cfg['environment'] = {key: shorten(value) for key, value in self.cfg['environment'].items()}
        self.source = Path(self.cfg['source'])
        self.tools = {key: Path(value) for key, value in self.cfg['paths'].items()}
        self.output = Path(args.output_root).resolve()
        self.logs = self.output / 'Logs' / (datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '-' + args.mode)
        self.logs.mkdir(parents=True, exist_ok=False)
        self.steps = []
        self.env = os.environ.copy()
        # Process-scoped; never change user/global PATH or the default Rust toolchain.
        self.env.update(self.cfg['environment'])
        bins = [self.tools['git'].parent, self.tools['flutter'] / 'bin',
                self.tools['flutter'] / 'bin/cache/dart-sdk/bin', self.tools['cargo'].parent,
                self.tools['python'].parent, self.tools['codegen'].parent,
                Path(os.environ.get('SYSTEMROOT', r'C:\Windows')) / 'System32',
                Path(os.environ.get('SYSTEMROOT', r'C:\Windows')) / 'System32/WindowsPowerShell/v1.0']
        self.env['PATH'] = ';'.join(map(str, bins)) + ';' + self.env.get('PATH', '')
        self.env['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'
        self.env['RUST_LOG'] = 'info'
        self.env['CI'] = 'true'
        self.env['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
        self.env['DART_SUPPRESS_ANALYTICS'] = 'true'
        self.env = offline_environment(self.env)
        self.env['FLUTTER_ROOT'] = str(self.tools['flutter'])
        self.env.setdefault('CARGO_TARGET_DIR', str(self.source / 'target'))
        self.env['VCPKG_DOWNLOADS'] = self.cfg['environment'].get(
            'VCPKG_DOWNLOADS', str(self.tools['vcpkg'] / 'downloads'))

    def flutter_command(self, *args):
        # Invoke the existing tool snapshot directly: flutter.bat may bootstrap
        # Dart or run pub upgrade before the Flutter command even starts.
        sdk = self.tools['flutter']
        dart = sdk / 'bin/cache/dart-sdk/bin/dart.exe'
        snapshot = sdk / 'bin/cache/flutter_tools.snapshot'
        packages = sdk / 'packages/flutter_tools/.dart_tool/package_config.json'
        require_files([dart, snapshot, packages])
        return [dart, '--disable-dart-dev', '--packages=' + str(packages),
                snapshot, '--no-version-check', *args]

    def require_cached_tools(self):
        sdk = self.tools['flutter']
        rust = Path(self.env['RUSTUP_HOME']) / 'toolchains' / self.env['RUSTUP_TOOLCHAIN'] / 'bin'
        require_files([rust / name for name in ['cargo.exe', 'rustc.exe', 'rustfmt.exe']])
        # Bypass rustup proxies, which may otherwise auto-install a missing toolchain.
        self.tools['cargo'], self.tools['rustc'] = rust / 'cargo.exe', rust / 'rustc.exe'
        self.env['RUSTC'] = str(self.tools['rustc'])
        self.env['PATH'] = str(rust) + ';' + self.env['PATH']
        for key in ['CARGO_HOME', 'PUB_CACHE', 'CARGO_TARGET_DIR']:
            if not Path(self.env[key]).is_dir():
                raise RuntimeError('Missing existing ' + key + ' cache; downloads are disabled: ' + self.env[key])
        require_files([self.tools[name] for name in ['git', 'python', 'codegen', 'vswhere', 'engine_archive']])
        require_files([self.tools['vcpkg'] / 'vcpkg.exe',
                       sdk / 'bin/cache/artifacts/engine/windows-x64/flutter_tester.exe',
                       sdk / 'bin/cache/artifacts/engine/windows-x64-release/flutter_windows.dll',
                       sdk / 'bin/cache/artifacts/engine/windows-x64-release/gen_snapshot.exe'])
        self.flutter_command('--version')
        require_files([sdk / 'bin/cache/flutter_tools.stamp', sdk / 'bin/cache/engine-dart-sdk.stamp'])
        if ((sdk / 'bin/cache/engine-dart-sdk.stamp').read_text().strip() !=
                (sdk / 'bin/internal/engine.version').read_text().strip()):
            raise RuntimeError('Cached Dart SDK does not match this Flutter engine; downloads are disabled')
        stamp = (sdk / 'bin/cache/flutter_tools.stamp').read_text().strip().strip('"')
        if stamp != self.profile['flutter_commit'] + ':':
            raise RuntimeError('Cached Flutter tool snapshot revision differs; downloads are disabled')
        save(self.logs / 'offline-policy.json', {'downloads': 'disabled',
             'cargo': 'frozen', 'pub': 'offline/enforce-lockfile',
             'vcpkg': 'installed-only/no-downloads', 'git_network_protocols': 'disabled',
             'flutter_bootstrap': 'bypassed; existing Dart/tool snapshot',
             'http_helpers': 'process-only loopback proxy; not OS network isolation',
             'cache_paths': {key: self.env[key] for key in
                 ['CARGO_HOME', 'PUB_CACHE', 'CARGO_TARGET_DIR', 'VCPKG_DOWNLOADS']}})

    def run_dart_package(self, package, arguments):
        # dart run / codegen's automatic build_runner may implicitly invoke pub.
        # Execute the cached entrypoint with the existing package configuration.
        config = self.source / 'flutter/.dart_tool/package_config.json'
        packages = json.loads(config.read_text(encoding='utf-8'))['packages']
        record = next((p for p in packages if p['name'] == package), None)
        if record is None:
            raise RuntimeError('Missing cached Dart package; downloads are disabled: ' + package)
        uri = urlparse(urljoin(config.as_uri(), record['rootUri']))
        if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
            raise RuntimeError('Dart package must resolve to the local cache: ' + package)
        root = Path(url2pathname(uri.path)).resolve()
        if not root.is_relative_to(Path(self.env['PUB_CACHE']).resolve()):
            raise RuntimeError('Dart package is outside the reviewed cache: ' + package)
        entry = root / 'bin' / (package + '.dart')
        require_files([entry])
        self.run('dart-' + package, [self.tools['flutter'] / 'bin/cache/dart-sdk/bin/dart.exe',
                 '--packages=' + str(config), entry, *arguments], cwd=self.source / 'flutter')

    def run(self, label, argv, cwd=None, check=True, env=None):
        argv = list(map(str, argv))
        if argv[0].lower().endswith(('.bat', '.cmd')):
            if any(re.search(r'[\r\n%&|<>]', item) for item in argv):
                raise RuntimeError('Unsafe batch argument')
            batch = self.logs / (label + '.cmd')
            batch.write_text('@echo off\ncall ' + subprocess.list2cmdline(argv) +
                             '\nexit /b %errorlevel%\n', encoding='utf-8')
            argv = [self.env.get('COMSPEC', r'C:\Windows\System32\cmd.exe'), '/d', '/c', str(batch)]
        print(label, flush=True)
        stdout = self.logs / (label + '.out.log')
        stderr = self.logs / (label + '.err.log')
        with stdout.open('wb') as out, stderr.open('wb') as err:
            result = subprocess.run(argv, cwd=cwd or self.source, env=env or self.env,
                                    stdout=out, stderr=err, creationflags=subprocess.CREATE_NO_WINDOW)
        self.steps.append({'step': label, 'argv': argv, 'exit_code': result.returncode,
                           'stdout': str(stdout), 'stderr': str(stderr)})
        save(self.logs / 'steps.json', self.steps)
        text = stdout.read_text(encoding='utf-8', errors='replace')
        if check and result.returncode:
            raise RuntimeError(f'{label}: exit {result.returncode}; see {stderr}')
        return result.returncode, text

    def git(self, label, *args, cwd=None, check=True, env=None):
        return self.run(label, [self.tools['git'], '-c', 'core.autocrlf=false', *args], cwd, check, env=env)

    def patch(self, label, root, patch, extra=()):
        code, _ = self.git(label + '-check', 'apply', *extra, '--check', patch, cwd=root, check=False)
        if code == 0:
            self.git(label + '-apply', 'apply', *extra, patch, cwd=root)
        else:
            self.git(label + '-already-applied', 'apply', *extra, '--reverse', '--check', patch, cwd=root)

    def preflight(self):
        if self.args.mode == 'Build':
            # The detailed cold/warm check follows compiler verification. This
            # floor prevents generators/tests filling an already crowded volume.
            free = shutil.disk_usage(self.source).free
            minimum = int(1.5 * 1024 ** 3)
            save(self.logs / 'space-floor.json', {'free_bytes': free, 'minimum_bytes': minimum})
            if free < minimum:
                raise RuntimeError(f'Insufficient free space before build: {free} bytes available; '
                                   f'at least {minimum} bytes required. No dependency acquisition or build started.')
        self.require_cached_tools()
        _, head = self.git('source-head', 'rev-parse', 'HEAD')
        _, committed_profile = self.git('source-profile', 'show',
            self.args.source_commit + ':scripts/windows-native-profile.json')
        require_source_pin(self.profile, self.args.source_commit, head.strip(),
            json.dumps(self.profile, sort_keys=True),
            json.dumps(json.loads(committed_profile), sort_keys=True))
        _, changed = self.git('source-delta', 'diff', '--name-only', '--ignore-submodules=all', 'HEAD')
        generated = {'src/bridge_generated.rs', 'src/bridge_generated.io.rs',
                     'flutter/lib/generated_bridge.dart', 'flutter/lib/generated_bridge.freezed.dart'}
        if set(changed.splitlines()) - generated:
            raise RuntimeError('Snapshot contains authored changes outside its published commit')
        _, submodule = self.git('submodule-head', 'rev-parse', 'HEAD', cwd=self.source / 'libs/hbb_common')
        if head.strip() != self.args.source_commit or submodule.strip() != self.profile['submodule_commit']:
            raise RuntimeError('Source or submodule revision mismatch')
        for relative, expected in self.profile['input_sha256'].items():
            if digest(self.source / relative) != expected:
                raise RuntimeError(f'Unreviewed source input: {relative}')
        self.require_hbb_source()
        cargo_manifest = tomllib.loads((self.source / 'Cargo.toml').read_text(encoding='utf-8'))
        pubspec = (self.source / 'flutter/pubspec.yaml').read_text(encoding='utf-8')
        app_version = re.search(r'^version:\s*[\"\']?([^\s\"\']+)', pubspec, re.MULTILINE).group(1)
        if app_version != self.profile['version'] or cargo_manifest['package']['version'] != app_version.split('+')[0]:
            raise RuntimeError('Manifest product version mismatch')
        manifest = json.loads((self.source / 'vcpkg.json').read_text(encoding='utf-8'))
        if manifest['vcpkg-configuration']['default-registry']['baseline'] != self.profile['vcpkg_commit']:
            raise RuntimeError('Vcpkg manifest baseline mismatch')
        _, vs = self.run('vs-discovery', [self.tools['vswhere'], '-products', '*', '-requires',
                            'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
                            'Microsoft.VisualStudio.Component.Windows11SDK.22621', '-format', 'json'])
        installs = json.loads(vs)
        if not installs or not installs[0]['isComplete']:
            raise RuntimeError('VS C++/SDK installation incomplete')
        self.vs = Path(installs[0]['installationPath'])
        version_file = self.vs / 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
        msvc = version_file.read_text(encoding='utf-8').strip()
        self.cmake = self.vs / 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
        self.env['PATH'] = str(self.cmake.parent) + ';' + self.env['PATH']
        _, flutter = self.run('flutter-version', self.flutter_command('--version', '--machine'))
        sdk = json.loads(flutter)
        if sdk['frameworkRevision'] != self.profile['flutter_commit']:
            raise RuntimeError('Flutter SDK revision mismatch')
        _, rust = self.run('rust-version', [self.tools['rustc'], '--version', '--verbose'])
        if self.profile['rust_version'] not in rust or 'host: x86_64-pc-windows-msvc' not in rust:
            raise RuntimeError('Unexpected Rust compiler/host')
        _, frb = self.run('frb-version', [self.tools['codegen'], '--version'])
        if self.profile['frb_version'] not in frb:
            raise RuntimeError('FRB codegen/runtime mismatch')
        self.run('cmake-version', [self.cmake, '--version'])
        self.run('python-version', [self.tools['python'], '--version'])
        _, vp = self.git('vcpkg-head', 'rev-parse', 'HEAD', cwd=self.tools['vcpkg'])
        if vp.strip() != self.profile['vcpkg_commit']:
            raise RuntimeError('Vcpkg checkout mismatch')
        _, status = self.git('source-state', 'status', '--short')
        info = {'source_commit': head.strip(), 'source_state': status, 'profile': self.profile,
                'toolchain': self.cfg, 'flutter': sdk, 'rust': rust.strip(), 'frb': frb.strip(),
                'visual_studio': installs[0], 'msvc': msvc,
                'free_bytes': shutil.disk_usage(self.source).free}
        save(self.logs / 'toolchain-manifest.json', info)
        if self.args.mode == 'Build':
            self.check_build_space('space-budget-preflight.json')
        return info

    def require_hbb_source(self, allow_unpatched=True):
        state = require_submodule_tree(self.git, self.source / 'libs/hbb_common',
            self.profile['submodule_commit'], self.source / 'patches/hbb_common-exantas-config.patch',
            self.env, self.logs, allow_unpatched)
        save(self.logs / 'submodule-source.json', {'status': 'PASS', 'state': state,
             'commit': self.profile['submodule_commit']})

    def selected_sdk_identity(self):
        required = self.profile.get('windows_sdk_version', WINDOWS_SDK_VERSION)
        version = self.env.get('WINDOWSSDKVERSION', '').rstrip('\\/')
        root = Path(self.env.get('WINDOWSSDKDIR', ''))
        if version != required or not root.is_absolute():
            raise RuntimeError('Selected Windows SDK differs from pinned ' + required)
        paths = {name.format(version=version): root / name.format(version=version) for name in SDK_INPUTS}
        require_files(paths.values())
        return {'version': version, 'files_sha256': {name: digest(path) for name, path in paths.items()}}

    def developer_environment(self):
        # Import in memory only. Never log a full environment or its values.
        sdk = self.profile.get('windows_sdk_version', WINDOWS_SDK_VERSION)
        if not re.fullmatch(r'10\.0\.\d+\.0', sdk):
            raise RuntimeError('Invalid pinned Windows SDK version')
        batch = self.logs / 'vs-env.cmd'
        batch.write_text('@echo off\ncall "' + str(self.vs / 'Common7/Tools/VsDevCmd.bat') +
                         '" -arch=x64 -host_arch=x64 -winsdk=' + sdk + ' >nul\nif errorlevel 1 exit /b %errorlevel%\nset\n')
        result = subprocess.run([self.env.get('COMSPEC', r'C:\Windows\System32\cmd.exe'),
                                 '/d', '/c', str(batch)], env=self.env, capture_output=True,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode:
            raise RuntimeError('VsDevCmd failed')
        for line in result.stdout.decode(errors='replace').splitlines():
            if '=' in line and not line.startswith('='):
                key, value = line.split('=', 1)
                self.env[key.upper()] = value
        # VsDevCmd can select Visual Studio's unrelated bundled vcpkg. Rust
        # build scripts (including pinned hwcodec) read VCPKG_ROOT directly;
        # they must use the same root as our receipt/ABI and installed-plan checks.
        # Remove case aliases too: Windows environment keys are case-insensitive.
        for key in list(self.env):
            if key.upper() == 'VCPKG_ROOT':
                del self.env[key]
        self.env['VCPKG_ROOT'] = str(self.tools['vcpkg'])
        self.env['RDCL_WINDOWS_SDK_VERSION'] = sdk
        save(self.logs / 'selected-windows-sdk.json', self.selected_sdk_identity())
        save(self.logs / 'native-vcpkg-root.json', {
            'vcpkg_root': self.env['VCPKG_ROOT'], 'selected_from': 'toolchain.paths.vcpkg'})

    def provision(self):
        self.developer_environment()
        # A shallow boundary alone says nothing about the selected objects.
        # Retain the same compiler/ABI proof before any provisioning side effect.
        self.env = offline_environment(self.env)
        self.require_verified_codecs()
        _, pins = self.git('codec-closure-pins', 'show', self.args.source_commit +
                           ':scripts/windows-codec-bootstrap-inputs.json')
        self.codec_ports = json.loads(pins)['ports']
        overlays = {p.parent.name: json.loads(p.read_text(encoding='utf-8'))
                    for p in (self.source / 'res/vcpkg').glob('*/vcpkg.json')}
        trees = require_vcpkg_objects(
            lambda label, *args: self.git(label, *args, cwd=self.tools['vcpkg']),
            self.profile, self.codec_ports, overlays)
        save(self.logs / 'vcpkg-objects.json', {'status': 'PASS',
             'baseline': self.profile['vcpkg_commit'], 'port_trees': trees,
             'receipt_verified_overlays': sorted(overlays),
             'policy': 'local objects only; no ancestry walk, fetch or codec rebuild'})
        archive = self.tools['engine_archive']
        if digest(archive) != self.profile['engine_sha256']:
            raise RuntimeError('Custom engine archive checksum mismatch')
        target = self.tools['flutter'] / 'bin/cache/artifacts/engine/windows-x64-release'
        with zipfile.ZipFile(archive) as payload:
            if payload.testzip():
                raise RuntimeError('Engine ZIP CRC failure')
            for member in payload.infolist():
                if Path(member.filename).name != member.filename or member.is_dir():
                    raise RuntimeError('Unexpected engine payload path')
                destination = target / member.filename
                with payload.open(member) as incoming:
                    data = incoming.read()
                if not destination.is_file() or digest(destination) != hashlib.sha256(data).hexdigest():
                    destination.write_bytes(data)
        self.patch('sdk-filter', self.tools['flutter'], self.source /
                   '.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff')
        self.patch('exantas-submodule', self.source / 'libs/hbb_common', self.source /
                   'patches/hbb_common-exantas-config.patch',
                   ('--ignore-whitespace', '--ignore-space-change', '--unidiff-zero'))
        self.require_hbb_source(allow_unpatched=False)
        self.run('pub-locked', self.flutter_command('pub', 'get', '--offline', '--enforce-lockfile'),
                 cwd=self.source / 'flutter')
        if digest(self.source / 'flutter/pubspec.lock') != self.profile['input_sha256']['flutter/pubspec.lock']:
            raise RuntimeError('Locked resolve modified the reviewed lockfile')
        self.ensure_desktop_plugin_links()

    def ensure_desktop_plugin_links(self):
        # Flutter3.24.5 buildWindows calls createPluginSymlinks for both enabled
        # desktop platforms. Linux links are bookkeeping only, not a Linux build.
        metadata = json.loads((self.source / 'flutter/.flutter-plugins-dependencies').read_text(encoding='utf-8'))
        cache = Path(self.env['PUB_CACHE']).resolve()
        records = []
        for platform in ['windows', 'linux']:
            if not (self.source / ('flutter/' + platform + '/CMakeLists.txt')).is_file():
                continue
            root = self.source / ('flutter/' + platform + '/flutter/ephemeral/.plugin_symlinks')
            root.mkdir(parents=True, exist_ok=True)
            for plugin in metadata['plugins'].get(platform, []):
                name = plugin['name']
                if not re.fullmatch(r'[a-z0-9_]+', name):
                    raise RuntimeError('Unexpected desktop plugin name')
                target = Path(plugin['path'])
                if not target.is_dir() or not target.resolve().is_relative_to(cache):
                    raise RuntimeError('Desktop plugin target is outside the owned cache: ' + name)
                link = root / name
                if link.is_symlink():
                    if link.resolve() != target.resolve():
                        raise RuntimeError('Existing desktop plugin link differs; preserved: ' + name)
                elif link.exists():
                    raise RuntimeError('Unexpected desktop plugin directory; preserved: ' + name)
                else:
                    try:
                        os.symlink(str(target), str(link), target_is_directory=True)
                    except OSError as error:
                        raise RuntimeError('Desktop plugin symlink privilege required; run the same profile Provision with real UAC: ' + platform + '/' + name) from error
                records.append({'platform': platform, 'name': name, 'target': str(target),
                                'valid': link.is_symlink() and link.exists()})
        save(self.logs / 'desktop-plugin-links.json', records)

    def verified_warm_cache(self):
        # This changes only the space reserve. Every compile/test/package check
        # still runs. A cold or changed source/toolchain keeps the5GiB guard.
        path = self.cfg.get('compiled_cache_receipt')
        if not path:
            return False
        try:
            cached = json.loads(Path(path).read_text(encoding='utf-8'))
            if cached.get('status') != 'PASS':
                return False
            if cached['source_commit'] != self.args.source_commit or cached['inputs'] != self.profile['input_sha256']:
                return False
            if cached['rust_version'] != (self.logs / 'rust-version.out.log').read_text(encoding='utf-8').strip():
                return False
            target = Path(self.env['CARGO_TARGET_DIR'])
            for name, expected in cached['source_sha256'].items():
                if digest(self.source / name) != expected:
                    return False
            for name, expected in cached['target_sha256'].items():
                if digest(target / name) != expected:
                    return False
            for name, expected in cached['codec_abi_sha256'].items():
                if digest(self.tools['vcpkg'] / 'installed/x64-windows-static' / name) != expected:
                    return False
            for name, expected in cached['tool_sha256'].items():
                if digest(name) != expected:
                    return False
            return True
        except (OSError, ValueError, KeyError):
            return False

    def require_verified_codecs(self):
        # A no-action version plan alone does not prove compiler/ABI compatibility.
        # Reuse the existing successful receipt's codec/tool/overlay evidence,
        # independently of application-source or Cargo-target cache changes.
        receipt = self.cfg.get('compiled_cache_receipt')
        if not receipt:
            raise RuntimeError('Missing verified codec cache receipt; installed libraries are preserved')
        cached = json.loads(Path(receipt).read_text(encoding='utf-8'))
        if (cached.get('status') != 'PASS' or
                cached.get('inputs', {}).get('vcpkg.json') != self.profile['input_sha256']['vcpkg.json'] or
                not cached.get('codec_abi_sha256')):
            raise RuntimeError('Codec cache receipt does not match the pinned dependency inputs')
        version = (self.vs / 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt').read_text().strip()
        compiler = self.vs / 'VC/Tools/MSVC' / version / 'bin/Hostx64/x64'
        actual_tools = [compiler / 'cl.exe', compiler / 'link.exe', compiler / 'lib.exe',
                        self.tools.get('vcpkg_cmake', self.cmake), self.tools['vcpkg'] / 'vcpkg.exe']
        key = lambda path: os.path.normcase(str(Path(path).resolve()))
        expected_tools = {key(path): sha for path, sha in cached.get('tool_sha256', {}).items()}
        for tool in actual_tools:
            if key(tool) not in expected_tools or digest(tool) != expected_tools[key(tool)]:
                raise RuntimeError('Codec compiler/tool differs from the verified cache: ' + str(tool))
        if not cached.get('sdk_identity'):
            raise RuntimeError('Codec receipt lacks Windows SDK identity; preserve it and compile a new isolated codec root with current tooling')
        if cached['sdk_identity'] != self.selected_sdk_identity():
            raise RuntimeError('Windows SDK identity differs from the verified codec receipt')
        if cached.get('triplet_sha256') != hashlib.sha256(native_triplet(self.profile)).hexdigest():
            raise RuntimeError('Codec receipt triplet differs from the SDK-pinned release-only triplet')
        installed = self.tools['vcpkg'] / 'installed/x64-windows-static'
        for relative, expected in cached['codec_abi_sha256'].items():
            if digest(installed / relative) != expected:
                raise RuntimeError('Installed codec/ABI differs from the verified cache: ' + relative)
        for relative, expected in cached.get('source_sha256', {}).items():
            if relative.startswith('res/vcpkg/') and digest(self.source / relative) != expected:
                raise RuntimeError('Codec overlay differs from the verified cache: ' + relative)
        save(self.logs / 'verified-codecs.json', {'status': 'PASS', 'receipt': str(receipt),
             'compiler_tools': list(map(str, actual_tools)),
             'codec_abi_library_files': len(cached['codec_abi_sha256'])})

    def check_build_space(self, filename='space-budget.json'):
        warm = self.verified_warm_cache()
        required = int((1.5 if warm else 5) * 1024 ** 3)
        free = shutil.disk_usage(self.source).free
        save(self.logs / filename, {'verified_warm_cache': warm,
             'minimum_bytes': required, 'free_bytes': free})
        if free < required:
            raise RuntimeError('Insufficient free space for the verified cold/warm build budget; '
                               'no unrelated cleanup is performed')

    def build(self):
        self.provision()
        generated = ['src/bridge_generated.rs', 'src/bridge_generated.io.rs',
                     'flutter/lib/generated_bridge.dart', 'flutter/lib/generated_bridge.freezed.dart']
        previous = {name: (digest(self.source / name), (self.source / name).stat())
                    for name in generated if (self.source / name).is_file()}
        self.run('frb-generate', [self.tools['codegen'], '--rust-input', 'src/flutter_ffi.rs',
                                  '--dart-output', 'flutter/lib/generated_bridge.dart',
                                  '--llvm-path', self.env['LLVM_PATH'], '--skip-deps-check', '--no-build-runner'])
        self.run_dart_package('build_runner', ['build', '--delete-conflicting-outputs',
                                               '--enable-experiment=class-modifiers'])
        # Preserve timestamps only when regenerated bytes are exactly identical.
        # This lets Cargo reuse its verified native cache on a second build.
        for name, (expected, old_stat) in previous.items():
            path = self.source / name
            if path.is_file() and digest(path) == expected:
                os.utime(path, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))
        save(self.logs / 'generated-bindings.json', {name: digest(self.source / name) for name in generated})
        self.run('dart-regressions', [*self.flutter_command('test', '--no-pub', '--concurrency=1'), 'test/exantas_session_report_test.dart',
                 'test/input_modifier_utils_test.dart', 'test/autocomplete_peer_merge_test.dart',
                 'test/server_settings_dialog_test.dart', 'test/exantas_identity_settings_test.dart',
                 'test/exantas_native_auth_test.dart', 'test/exantas_account_settings_test.dart',
                 'test/exantas_office_response_test.dart', 'test/exantas_lifecycle_queue_test.dart'],
                 cwd=self.source / 'flutter')
        self.run('cargo-metadata', [self.tools['cargo'], 'metadata', '--frozen', '--features', 'flutter,hwcodec,vram',
                                              '--format-version', '1', '--filter-platform', 'x86_64-pc-windows-msvc'])
        metadata = json.loads((self.logs / 'cargo-metadata.out.log').read_text(encoding='utf-8'))
        save(self.logs / 'locked-msrv.json', [{'name': p['name'], 'version': p['version'],
                                             'rust_version': p.get('rust_version')} for p in metadata['packages']])
        triplets = self.output / 'Triplets'
        triplets.mkdir(exist_ok=True)
        (triplets / 'x64-windows-static.cmake').write_bytes(native_triplet(self.profile))
        self.check_build_space()
        # Pin the codec CMake separately from Flutter/VS CMake so an unrelated
        # newer tool on PATH does not invalidate every installed codec ABI.
        codec_env = self.env.copy()
        if 'vcpkg_cmake' in self.tools:
            self.run('codec-cmake-version', [self.tools['vcpkg_cmake'], '--version'])
            codec_env['PATH'] = str(self.tools['vcpkg_cmake'].parent) + ';' + codec_env['PATH']
        self.require_verified_codecs()
        _, plan = self.run('vcpkg-plan', [self.tools['vcpkg'] / 'vcpkg.exe', 'install', '--dry-run', '--triplet',
                 'x64-windows-static', '--host-triplet', 'x64-windows-static',
                 '--overlay-triplets=' + str(triplets),
                 '--x-install-root=' + str(self.tools['vcpkg'] / 'installed'),
                 '--no-downloads', '--only-binarycaching'], env=codec_env)
        require_installed_vcpkg_plan(plan, self.codec_ports)
        self.require_hbb_source(allow_unpatched=False)
        self.run('cargo-virtual-display', [self.tools['cargo'], 'build', '--frozen',
                                          '--release', '-p', 'dylib_virtual_display', '-j', '1'])
        self.run('cargo-release', [self.tools['cargo'], 'build', '--frozen', '--features',
                                  'flutter,hwcodec,vram', '--lib', '--release', '-j', '1'])
        # CMake expects these exact runtime payloads under the source target/
        # directory. Keep the large Cargo cache in the reviewed target root and
        # copy only the required DLLs when a separate CARGO_TARGET_DIR is used.
        cargo_target = Path(self.env.get('CARGO_TARGET_DIR', str(self.source / 'target')))
        rust_payload = self.source / 'target/release'
        (rust_payload / 'deps').mkdir(parents=True, exist_ok=True)
        if cargo_target != self.source / 'target':
            shutil.copy2(cargo_target / 'release/librustdesk.dll', rust_payload / 'librustdesk.dll')
            shutil.copy2(cargo_target / 'release/deps/dylib_virtual_display.dll',
                         rust_payload / 'deps/dylib_virtual_display.dll')
        self.run('flutter-release', self.flutter_command('build', 'windows', '--release', '--no-pub'), cwd=self.source / 'flutter')
        self.require_flutter_sdk()
        self.require_verified_codecs()
        bundle = self.source / 'flutter/build/windows/x64/runner/Release'
        shutil.copy2(self.source / 'target/release/deps/dylib_virtual_display.dll', bundle)
        self.require_native_core(bundle, cargo_target)
        receipt = {'source_commit': self.args.source_commit,
                   'lock_sha256': digest(self.source / 'flutter/pubspec.lock'),
                   'payload_sha256': runtime_inventory(bundle)}
        save(self.output / 'native-compile-receipt.json', receipt)
        self.package()

    def require_native_core(self, bundle, cargo_target):
        generated = (self.source / 'src/version.rs').read_text(encoding='utf-8')
        match = re.search(r'pub const VERSION:\s*&str\s*=\s*"([^"]+)"', generated)
        if not match or match.group(1) != self.profile['version'].split('+')[0]:
            raise RuntimeError('Generated native core version differs from the release profile')
        compiled = cargo_target / 'release/librustdesk.dll'
        if digest(bundle / 'librustdesk.dll') != digest(compiled):
            raise RuntimeError('Flutter payload contains a different native DLL from this Cargo build')
        save(self.logs / 'native-core-identity.json', {
            'version': match.group(1), 'compiled_dll_sha256': digest(compiled),
            'generated_version_sha256': digest(self.source / 'src/version.rs')})

    def require_flutter_sdk(self):
        project = self.source / 'flutter/build/windows/x64/runner/rustdesk.vcxproj'
        root = ET.parse(project).getroot()
        versions = {node.text.strip() for node in root.iter()
                    if node.tag.rsplit('}', 1)[-1] == 'WindowsTargetPlatformVersion' and node.text}
        expected = self.profile.get('windows_sdk_version', WINDOWS_SDK_VERSION)
        if versions != {expected}:
            raise RuntimeError('Flutter project selected a different or unknown Windows SDK: ' + repr(versions))
        save(self.logs / 'flutter-sdk-selection.json', {'status': 'PASS', 'version': expected})

    def close(self):
        if self.drive_created:
            alias = self.cfg['drive_alias']
            # Recheck ownership in case another process replaced the mapping.
            subst = Path(os.environ.get('SYSTEMROOT', r'C:\Windows')) / 'System32/subst.exe'
            current = subprocess.run([subst], capture_output=True, text=True, check=True,
                                     creationflags=subprocess.CREATE_NO_WINDOW).stdout
            expected = alias['drive'].upper() + '\\: => ' + alias['target']
            if expected.lower() not in current.lower().splitlines():
                raise RuntimeError('Drive alias changed externally; refusing to remove it')
            subprocess.run([subst, alias['drive'], '/d'], check=True,
                           creationflags=subprocess.CREATE_NO_WINDOW)
            self.drive_created = False
        if getattr(self, 'session_locks', None):
            self.session_locks.close()

    def package_exe(self):
        # Reuse the existing upstream self-extracting installer. Never execute
        # the packaged application, install it, or invoke MSI during packaging.
        bundle = self.source / 'flutter/build/windows/x64/runner/Release'
        info = json.loads((self.output / 'BUILD-INFO.json').read_text(encoding='utf-8'))
        if (info.get('status') != 'PASS' or info['source_commit'] != self.args.source_commit
                or info['version'] != self.profile['version']):
            raise RuntimeError('EXE requires a verified matching native build')
        current = runtime_inventory(bundle)
        if current != info['files']:
            raise RuntimeError('Runtime payload differs from the verified native build')
        destination = self.output / ('rd-cl-' + self.profile['version'] + '-windows-x64-install.exe')
        if destination.exists():
            raise RuntimeError('Refusing to overwrite an existing installer')
        self.run('packer-python-dependency', [self.tools['python'], '-c',
            "import brotli; import importlib.metadata; print(importlib.metadata.version('Brotli'))"])
        self.run('packer-generate', [self.tools['python'], self.source / 'libs/portable/generate.py',
            '--folder', bundle, '--output', self.source / 'libs/portable', '--executable',
            bundle / 'rustdesk.exe', '--skip-build'])
        self.run('packer-frozen', [self.tools['cargo'], 'build', '--frozen', '--release',
                                  '-p', 'rustdesk-portable-packer', '-j', '1'])
        target = Path(self.env['CARGO_TARGET_DIR']) / 'release/rustdesk-portable-packer.exe'
        with target.open('rb') as stream:
            if stream.read(2) != b'MZ':
                raise RuntimeError('Installer is not a Windows PE executable')
            stream.seek(0x3c); stream.seek(struct.unpack('<I', stream.read(4))[0])
            if stream.read(4) != b'PE\0\0' or struct.unpack('<H', stream.read(2))[0] != 0x8664:
                raise RuntimeError('Installer architecture is not x64')
        if runtime_inventory(bundle) != current:
            raise RuntimeError('Runtime payload changed during EXE packaging')
        shutil.copy2(target, destination)
        receipt = {'status': 'PACKAGED_NATIVE_ACCEPTANCE_PENDING',
            'source_commit': self.args.source_commit, 'version': self.profile['version'],
            'source_repository': self.profile['source_repository'], 'architecture': 'windows-x64',
            'installer': str(destination), 'sha256': digest(destination),
            'payload_sha256': current, 'toolchain_manifest': str(self.logs / 'toolchain-manifest.json'),
            'format': 'existing self-extracting RustDesk installer; interactive --install',
            'acceptance': 'NOT_RUN: installation, upgrade, DPAPI, services and real session',
            'signing': 'UNSIGNED'}
        save(self.output / 'EXE-INFO.json', receipt)
        with (self.output / 'SHA256SUMS').open('a', encoding='utf-8') as sums:
            sums.write(receipt['sha256'] + '  ' + destination.name + '\n')

    def package(self):
        bundle = self.source / 'flutter/build/windows/x64/runner/Release'
        required = ['rustdesk.exe', 'flutter_windows.dll', 'librustdesk.dll',
                    'dylib_virtual_display.dll', 'data/icudtl.dat', 'data/app.so']
        for name in required:
            path = bundle / name
            if not path.is_file() or not path.stat().st_size:
                raise RuntimeError('Missing release payload: ' + name)
        with (bundle / 'rustdesk.exe').open('rb') as exe:
            if exe.read(2) != b'MZ':
                raise RuntimeError('Release app is not a PE executable')
            exe.seek(0x3c); offset = struct.unpack('<I', exe.read(4))[0]
            exe.seek(offset)
            if exe.read(4) != b'PE\0\0' or struct.unpack('<H', exe.read(2))[0] != 0x8664:
                raise RuntimeError('Release PE architecture is not x64')
        if not (self.logs / 'toolchain-manifest.json').exists():
            raise RuntimeError('Package requires verified preflight inputs')
        receipt = json.loads((self.output / 'native-compile-receipt.json').read_text(encoding='utf-8'))
        if receipt['source_commit'] != self.args.source_commit or receipt['lock_sha256'] != digest(self.source / 'flutter/pubspec.lock'):
            raise RuntimeError('Native compile provenance differs from the current inputs')
        expected_files = {name.replace('\\', '/'): sha for name, sha in receipt['payload_sha256'].items()}
        files = runtime_inventory(bundle)
        if len(expected_files) != len(receipt['payload_sha256']) or files != expected_files:
            raise RuntimeError('Release payload inventory differs from native compilation: extra/missing/changed file')
        name = 'rd-cl-' + self.profile['version'] + '-windows-x64-portable'
        archive = self.output / (name + '.zip')
        if archive.exists():
            raise RuntimeError('Refusing to overwrite an existing package')
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as output:
            for relative in sorted(files):
                output.write(bundle / relative, name + '/' + relative)
        with zipfile.ZipFile(archive) as verify:
            if verify.testzip():
                raise RuntimeError('Portable ZIP integrity failure')
            if set(verify.namelist()) != {name + '/' + relative for relative in files}:
                raise RuntimeError('Portable ZIP inventory mismatch')
            for relative, expected in files.items():
                with verify.open(name + '/' + relative) as stream:
                    if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
                        raise RuntimeError('Portable ZIP payload differs: ' + relative)
        if runtime_inventory(bundle) != files:
            raise RuntimeError('Runtime payload changed during ZIP packaging')
        info = {'status': 'PASS', 'source_commit': self.args.source_commit,
                'source_repository': self.profile['source_repository'],
                'build_automation_sha256': {name: digest(Path(__file__).with_name(name)) for name in
                    ['windows-native-build.py', 'windows-native-build.ps1', 'windows-native-profile.json']},
                'approved_dirty_lock_sha256': self.profile['input_sha256']['flutter/pubspec.lock'],
                'version': self.profile['version'], 'architecture': 'windows-x64',
                'dependency_policy': 'existing local caches only; downloads disabled',
                'package': str(archive), 'package_sha256': digest(archive), 'files': files,
                'toolchain_manifest': str(self.logs / 'toolchain-manifest.json'),
                'runtime_acceptance': 'NOT RUN - no product launch/production connection'}
        save(self.output / 'BUILD-INFO.json', info)
        (self.output / 'SHA256SUMS').write_text(digest(archive) + '  ' + archive.name + '\n' +
            ''.join(f'{sha}  {name}/{relative}\n' for relative, sha in sorted(files.items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['Preflight', 'Provision', 'Build', 'Package', 'PackageExe', 'PackageMsi'], required=True)
    parser.add_argument('--toolchain', required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--output-root', required=True)
    parser.add_argument('--with-exe', action='store_true')
    parser.add_argument('--with-msi', action='store_true')
    args = parser.parse_args()
    if ((args.with_exe or args.with_msi) and args.mode not in ['Build', 'Package']) or (args.with_exe and args.with_msi):
        parser.error('Choose one installer, only after Build/Package')
    build = Build(args)
    failure = None
    try:
        build.preflight()
        if args.mode == 'Provision':
            build.provision()
        elif args.mode == 'Build':
            build.build()
        elif args.mode == 'Package':
            build.package()
        elif args.mode == 'PackageExe':
            build.developer_environment()
            build.package_exe()
        if args.with_exe:
            if args.mode == 'Package':
                build.developer_environment()
            build.package_exe()
        if args.with_msi or args.mode == 'PackageMsi':
            build.developer_environment()
            spec = importlib.util.spec_from_file_location('native_msi', Path(__file__).with_name('windows-native-msi.py'))
            msi = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(msi)
            msi.package(build, sys.modules[__name__])
    except Exception as error:
        failure = error
    finally:
        try:
            build.close()
        except Exception as cleanup:
            if failure is None:
                failure = cleanup
            else:
                failure.add_note('Build cleanup also failed; preserve locks/state: ' + str(cleanup))
                print('Cleanup also failed: ' + str(cleanup), file=sys.stderr)
    if failure is not None:
        return report_failure(build, failure)
    try:
        save(build.logs / 'result.json', {'mode': args.mode, 'status': 'PASS'})
    except Exception as error:
        return report_failure(build, error)
    return 0


if __name__ == '__main__':
    sys.exit(main())
