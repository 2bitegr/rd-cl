"""Offline S2 codec compilation, separate from every existing vcpkg installation.

Preflight validates local inputs; Compile repeats it and publishes codec evidence
only after fresh native objects, installed ABIs and the unchanged verifier pass.
This does not compile/package/run rd-cl or import any S1 compiled-cache receipt.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time


SCRIPT = Path(__file__).resolve()
spec = importlib.util.spec_from_file_location('native_build', SCRIPT.with_name('windows-native-build.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
PINS = json.loads(SCRIPT.with_name('windows-codec-bootstrap-inputs.json').read_text(encoding='utf-8'))
TRIPLET = ('set(VCPKG_TARGET_ARCHITECTURE x64)\r\n'
           'set(VCPKG_CRT_LINKAGE static)\r\nset(VCPKG_LIBRARY_LINKAGE static)\r\n'
           'set(VCPKG_BUILD_TYPE release)\r\n').encode('ascii')


def regular_tree(root, recursive=True):
    """Never follow a junction/symlink into another cache, checkout or delivery."""
    root = Path(root)
    paths = [root, *root.parents]
    for path in paths:
        info = path.lstat()
        if path.is_symlink() or getattr(info, 'st_file_attributes', 0) & 0x400:
            raise RuntimeError('Link/reparse point is not an owned bootstrap input: ' + str(path))
    for path in root.rglob('*') if recursive else []:
        info = path.lstat()
        if path.is_symlink() or getattr(info, 'st_file_attributes', 0) & 0x400:
            raise RuntimeError('Link/reparse point in bootstrap input: ' + str(path))
        if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
            raise RuntimeError('Non-regular bootstrap input: ' + str(path))


def inventory(root):
    regular_tree(root)
    return {p.relative_to(root).as_posix(): native.digest(p)
            for p in sorted(Path(root).rglob('*')) if p.is_file()}


def check_archives(downloads):
    checked = {}
    missing = []
    for record in PINS['archives']:
        path = downloads / record['filename']
        if not path.is_file():
            missing.append(str(path))
            continue
        with path.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha512').hexdigest()
        if actual != record['sha512']:
            raise RuntimeError('Pinned source/patch SHA512 mismatch; bytes preserved: ' + str(path))
        checked[record['filename']] = native.digest(path)
    for port, commit in PINS['git_archives'].items():
        path = downloads / (port + '-' + commit + '.tar.gz')
        if not path.is_file():
            missing.append(str(path))
    if missing:
        raise RuntimeError('Missing LOCAL codec inputs; no compilation/download: ' + ', '.join(missing))
    return checked


def tar_members(path):
    result = {}
    with tarfile.open(path, 'r:*') as archive:
        for member in archive:
            if member.name in result:
                raise RuntimeError('Duplicate archive member: ' + member.name)
            if member.isfile():
                with archive.extractfile(member) as stream:
                    value = hashlib.file_digest(stream, 'sha256').hexdigest()
            elif member.isdir() or member.issym():
                value = member.linkname
            else:
                raise RuntimeError('Unsupported Git archive member: ' + member.name)
            result[member.name] = [member.type.decode('ascii'), member.mode, value]
    return result


def require_compile_evidence(root, started_ns):
    """A successful process or an existing .lib alone is insufficient."""
    installed = root / 'installed/x64-windows-static'
    evidence = {}
    for port in PINS['compiled_ports']:
        abi = installed / 'share' / port / 'vcpkg_abi_info.txt'
        if not abi.is_file() or not abi.stat().st_size:
            raise RuntimeError('Missing freshly compiled codec ABI: ' + port)
        objects = [p for p in (root / 'buildtrees' / port).rglob('*')
                   if p.suffix.lower() in ('.obj', '.o') and p.is_file()
                   and p.stat().st_mtime_ns >= started_ns - 2_000_000_000]
        if not objects:
            raise RuntimeError('No fresh compiler objects; receipt refused: ' + port)
        package = root / 'packages' / (port + '_x64-windows-static')
        libraries = sorted((package / 'lib').glob('*.lib'))
        if not libraries:
            raise RuntimeError('No compiled static libraries: ' + port)
        for library in libraries:
            destination = installed / 'lib' / library.name
            if not destination.is_file() or native.digest(destination) != native.digest(library):
                raise RuntimeError('Compiled library was not installed intact: ' + port + '/' + library.name)
        evidence[port] = {'abi_sha256': native.digest(abi),
                          'objects_sha256': {p.relative_to(root).as_posix(): native.digest(p) for p in objects},
                          'libraries_sha256': {p.name: native.digest(p) for p in libraries}}
    return evidence


def require_empty_plan(text):
    headings = re.findall(r'^The following packages[^\r\n]*', text, re.MULTILINE)
    if headings != ['The following packages will be built and installed:']:
        raise RuntimeError('Expected a fresh, build-only pinned codec plan; no installed-cache imports/removals')
    entries = re.findall(r'^\s*(?:\*\s+)?([a-z0-9-]+)(?:\[[^\]]+\])?:([a-z0-9-]+)@([^\s]+)',
                         text, re.MULTILINE)
    packages = {name: version for name, triplet, version in entries}
    expected = {name: version['baseline'] + ('#' + str(version['port-version']) if version['port-version'] else '')
                for name, version in PINS['ports'].items()}
    if (packages != expected or len(entries) != len(expected) or
            any(triplet != 'x64-windows-static' for name, triplet, version in entries)):
        raise RuntimeError('Unknown/missing codec dependency or version in plan: ' + repr(packages))


def require_uncompiled_outputs(root):
    """Keep the known compiler probe without accepting previous codec outputs."""
    for name in ['packages', 'installed', 'buildtrees']:
        directory = root / name
        if not directory.exists() and not directory.is_symlink():
            continue
        regular_tree(directory)
        if not directory.is_dir():
            raise RuntimeError('Expected native output directory; preserved: ' + str(directory))
        if name == 'packages':
            for entry in directory.iterdir():
                if (entry.name != 'detect_compiler_x64-windows-static' or
                        not entry.is_dir() or any(entry.iterdir())):
                    raise RuntimeError('Existing or unknown package output; preserve it, do not replay: ' + str(entry))
        else:
            for path in directory.rglob('*'):
                if path.is_file() and path.suffix.lower() in ['.obj', '.o', '.lib', '.a', '.dll', '.exe']:
                    # Native vcpkg compiler detection may itself produce objects
                    # here. This exact buildtree is not a codec package/build.
                    if name == 'buildtrees' and path.relative_to(directory).parts[0] == 'detect_compiler':
                        continue
                    raise RuntimeError('Existing native codec output; preserve it, do not replay: ' + str(path))


class Bootstrap(native.Build):
    def close(self):
        try:
            # The lock may use the short drive. Release it before native.close()
            # removes the invocation-owned mapping, including constructor errors.
            if getattr(self, 'lock_token', None):
                if self.lock_path.read_text() != self.lock_token:
                    raise RuntimeError('Bootstrap lock changed; preserve it for inspection')
                self.lock_path.unlink()
                self.lock_token = None
        finally:
            super().close()

    def check_script_source(self):
        for name in ['windows-codec-bootstrap.py', 'windows-codec-bootstrap.ps1',
                     'windows-codec-bootstrap.cmake', 'windows-codec-bootstrap-inputs.json',
                     'windows-native-build.py']:
            _, text = self.git('published-' + name.replace('.', '-'), 'show',
                               self.args.source_commit + ':scripts/' + name)
            if (self.source / 'scripts' / name).read_text(encoding='utf-8') != text:
                raise RuntimeError('Bootstrap script differs from published source: ' + name)
            if SCRIPT.with_name(name).read_text(encoding='utf-8') != text:
                raise RuntimeError('Invoke bootstrap scripts from the selected published snapshot')
        self.git('source-base', 'merge-base', '--is-ancestor', PINS['base_source_commit'], self.args.source_commit)
        if self.profile['version'] != PINS['product_version']:
            raise RuntimeError('Bootstrap is reviewed for 1.4.13+71 only')

    def tool_hashes(self):
        version = (self.vs / 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt').read_text().strip()
        compiler = self.vs / 'VC/Tools/MSVC' / version / 'bin/Hostx64/x64'
        tools = [compiler / name for name in ['cl.exe', 'link.exe', 'lib.exe']]
        tools += [self.tools['vcpkg_cmake'], self.tools['vcpkg'] / 'vcpkg.exe']
        native.require_files(tools)
        return {str(p.resolve()): native.digest(p) for p in tools}

    def verify_git_archives(self, downloads):
        # vcpkg_from_git has no SHA512 pin. Compare cached tar CONTENT to the
        # exact Git commit's local objects, never just its commit-shaped filename.
        result = {}
        for port, commit in PINS['git_archives'].items():
            cached = downloads / (port + '-' + commit + '.tar.gz')
            repo = downloads / 'git-tmp'
            self.git('cached-' + port + '-object', 'cat-file', '-e', commit + '^{commit}', cwd=repo)
            descriptor, temporary = tempfile.mkstemp(suffix='.tar', dir=self.logs)
            os.close(descriptor)
            temporary = Path(temporary)
            try:
                self.git('cached-' + port + '-archive', '-c', 'core.autocrlf=false',
                         'archive', '--format=tar', '--output=' + str(temporary), commit, cwd=repo)
                if tar_members(cached) != tar_members(temporary):
                    raise RuntimeError('Cached Git archive does not match pinned objects: ' + port)
                result[cached.name] = native.digest(cached)
            finally:
                # Only this invocation's exact disposable comparison file.
                temporary.unlink()
        return result

    def prepare_root(self):
        physical = Path(self.args.codec_root).resolve()
        artifact_root = Path(self.cfg['artifact_root']).resolve()
        if not physical.is_relative_to(artifact_root / 'Tools/codec-bootstrap'):
            raise RuntimeError('CodecRoot must be under artifact_root/Tools/codec-bootstrap')
        # Resolve ownership physically, then use only the already reviewed alias
        # for compiler paths. Never create or change a mapping here.
        root = physical
        alias = self.cfg.get('drive_alias')
        if alias:
            root = Path(alias['drive'] + '\\') / physical.relative_to(artifact_root)
        if ' ' in str(root):
            raise RuntimeError('Use the reviewed short drive alias for CodecRoot; ffmpeg rejects spaces')
        for retained in [self.source.resolve(), self.tools['vcpkg'].resolve(), self.output]:
            if physical == retained or physical.is_relative_to(retained) or retained.is_relative_to(physical):
                raise RuntimeError('CodecRoot overlaps preserved source, vcpkg or delivery')
        root.parent.mkdir(parents=True, exist_ok=True)
        regular_tree(root.parent, recursive=False)
        self.lock_path = root.parent / (root.name + '.bootstrap.lock')
        token = json.dumps({'pid': os.getpid(), 'source_commit': self.args.source_commit})
        with self.lock_path.open('x') as lock:
            lock.write(token)
        self.lock_token = token
        if root.exists():
            regular_tree(root)
            marker = json.loads((root / '.rd-cl-codec-bootstrap.json').read_text(encoding='utf-8'))
            if marker != {'source_commit': self.args.source_commit, 'machine': 'S2', 'schema': 1, 'phase': 'PREPARED'}:
                raise RuntimeError('CodecRoot ownership/source mismatch; preserve it')
            require_uncompiled_outputs(root)
            return root
        # Local-only source/object copy, not a remote clone or a binary-cache import.
        self.git('local-vcpkg-copy', 'clone', '--no-hardlinks', '--no-checkout',
                 str(self.tools['vcpkg']), str(root), cwd=root.parent)
        self.git('local-vcpkg-checkout', 'checkout', '--detach', self.profile['vcpkg_commit'], cwd=root)
        shutil.copy2(self.tools['vcpkg'] / 'vcpkg.exe', root / 'vcpkg.exe')
        native.save(root / '.rd-cl-codec-bootstrap.json',
                    {'source_commit': self.args.source_commit, 'machine': 'S2', 'schema': 1, 'phase': 'PREPARED'})
        shutil.copytree(Path(self.env['VCPKG_DOWNLOADS']), root / 'downloads')
        return root

    def command(self, root, triplets):
        return [root / 'vcpkg.exe', 'install', '--triplet=x64-windows-static',
                '--host-triplet=x64-windows-static', '--overlay-triplets=' + str(triplets),
                '--x-install-root=' + str(root / 'installed'), '--no-downloads', '--no-binarycaching']

    def codec_preflight(self):
        for name in ['compiled-cache-receipt.json', 'toolchain-codecs-local.json', 'BUILD-INFO.json', 'EXE-INFO.json']:
            if (self.output / name).exists():
                raise RuntimeError('Preserve existing receipt/delivery; use the owned codec-bootstrap output: ' + name)
        self.preflight()  # Existing source/version/toolchain guards, unchanged.
        self.check_script_source()
        if 'vcpkg_cmake' not in self.tools:
            raise RuntimeError('Explicit existing paths.vcpkg_cmake is required')
        previous = Path(self.args.existing_triplet)
        if native.digest(previous) not in [PINS['previous_triplet_sha256'], PINS['triplet_sha256']]:
            raise RuntimeError('Unexpected existing triplet; preserved without edits')
        if hashlib.sha256(TRIPLET).hexdigest() != PINS['triplet_sha256']:
            raise RuntimeError('Canonical CRLF release-only triplet bytes differ')
        self.developer_environment()
        # Refuse inherited feature/tool/overlay changes before invoking vcpkg.
        for key in ['USE_AOM_391', 'VCPKG_OVERLAY_PORTS', 'VCPKG_OVERLAY_TRIPLETS',
                    'VCPKG_CHAINLOAD_TOOLCHAIN_FILE', 'VCPKG_VISUAL_STUDIO_PATH']:
            if self.env.get(key):
                raise RuntimeError('Unreviewed codec environment override: ' + key)
        self.env.update({'VCPKG_MAX_CONCURRENCY': '1', 'VCPKG_DISABLE_METRICS': '1',
                         'VCPKG_BINARY_SOURCES': 'clear', 'VCPKG_DEFAULT_TRIPLET': 'x64-windows-static',
                         'VCPKG_DEFAULT_HOST_TRIPLET': 'x64-windows-static', 'VSLANG': '1033'})
        self.env['PATH'] = str(self.tools['vcpkg_cmake'].parent) + ';' + self.env['PATH']
        # Importing VS must not re-enable user proxy/online policy.
        self.env = native.offline_environment(self.env)
        self.input_tools = self.tool_hashes()
        downloads = Path(self.env['VCPKG_DOWNLOADS'])
        self.preserved_download_root = downloads
        regular_tree(downloads)
        archives = check_archives(downloads)
        archives.update(self.verify_git_archives(downloads))
        self.original_downloads = inventory(downloads)
        self.original_installed = inventory(self.tools['vcpkg'] / 'installed')
        self.overlays = {p.relative_to(self.source).as_posix(): native.digest(p)
                         for p in sorted((self.source / 'res/vcpkg').rglob('*')) if p.is_file()}
        # Validate every original tracked script/recipe and local Git object,
        # including override trees, without fetching missing objects.
        self.git('vcpkg-unchanged', 'diff', '--exit-code', 'HEAD', '--', 'scripts', 'ports', 'versions',
                 cwd=self.tools['vcpkg'])
        for name, tree in self.profile['vcpkg_override_trees'].items():
            _, entries = self.git('override-' + name, 'ls-tree', '-r', tree, cwd=self.tools['vcpkg'])
            if not entries.strip():
                raise RuntimeError('Missing pinned override tree: ' + name)
            for index, entry in enumerate(entries.splitlines()):
                self.git('override-' + name + '-' + str(index), 'cat-file', '-e', entry.split()[2],
                         cwd=self.tools['vcpkg'])
        copied_bytes = (0 if Path(self.args.codec_root).exists() else
                        sum(p.stat().st_size for p in downloads.rglob('*') if p.is_file()))
        if shutil.disk_usage(self.output).free < copied_bytes + 5 * 1024 ** 3:
            raise RuntimeError('Need cache-copy bytes plus 5 GiB free before codec compilation; no cleanup')
        root = self.prepare_root()
        self.root = root
        self.env.update({'VCPKG_ROOT': str(root), 'VCPKG_DOWNLOADS': str(root / 'downloads')})
        # Pinned source bytes must remain identical. Helpers may legitimately
        # prepare MSYS metadata in this PRIVATE copy on a repeated preflight.
        for name, sha in archives.items():
            if native.digest(root / 'downloads' / name) != sha:
                raise RuntimeError('Copied local source input differs: ' + name)
        triplets = self.output / 'Triplets'
        triplets.mkdir(exist_ok=True)
        triplet = triplets / 'x64-windows-static.cmake'
        if triplet.exists() and triplet.read_bytes() != TRIPLET:
            raise RuntimeError('Existing output triplet differs; preserve it')
        triplet.write_bytes(TRIPLET)
        _, tool_version = self.run('vcpkg-version', [root / 'vcpkg.exe', 'version'])
        date = re.search(r'\b(20\d\d-\d\d-\d\d)\b', tool_version)
        if not date:
            raise RuntimeError('Cannot identify installed vcpkg tool date')
        # Tool acquisition is cache-only: asset origins are blocked. No bootstrap
        # executable, rustup, pip, remote Git or vcpkg --only-downloads is used.
        for tool in ['cmake', 'ninja', '7zip', 'git']:
            _, fetched = self.run('local-tool-' + tool, [root / 'vcpkg.exe', 'fetch', tool, '--x-stderr-status'])
            resolved = Path(fetched.strip())
            native.require_files([resolved])
            if tool == 'cmake':
                if native.digest(resolved) != native.digest(self.tools['vcpkg_cmake']):
                    raise RuntimeError('vcpkg selected different CMake bytes; supply its existing exact path as paths.vcpkg_cmake')
                self.tools['vcpkg_cmake'] = resolved
        self.initial_tools = self.tool_hashes()
        self.env['PATH'] = str(self.tools['vcpkg_cmake'].parent) + ';' + self.env['PATH']
        _, self.cmake_version = self.run('codec-cmake-version', [self.tools['vcpkg_cmake'], '--version'])
        audit = self.logs / 'input-audit'
        audit.mkdir()
        self.run('codec-helper-audit', [self.tools['vcpkg_cmake'],
                 '-DBOOTSTRAP_ROOT=' + str(root), '-DBOOTSTRAP_AUDIT=' + str(audit),
                 '-DDOWNLOADS=' + self.env['VCPKG_DOWNLOADS'], '-DBOOTSTRAP_TOOL_DATE=' + date[1],
                 '-P', SCRIPT.with_suffix('.cmake')])
        if (audit / 'helpers-complete.txt').read_text().strip() != 'LOCAL_INPUTS_CHECKED':
            raise RuntimeError('Incomplete helper input audit')
        _, plan = self.run('codec-empty-plan', [*self.command(root, triplets), '--dry-run'])
        require_empty_plan(plan)
        self.prepared = {'status': 'PREFLIGHT_PASS_NOT_COMPILED', 'machine': 'S2',
                         'source_commit': self.args.source_commit, 'base_source_commit': PINS['base_source_commit'],
                         'archives_sha256': archives, 'triplet_sha256': native.digest(triplet),
                         'previous_triplet_sha256': native.digest(previous), 'tools_sha256': self.initial_tools,
                         'original_downloads_sha256': self.original_downloads,
                         'original_installed_sha256': self.original_installed, 'codec_root': str(root)}
        native.save(self.output / 'codec-preflight.json', self.prepared)
        return root, triplets

    def compile_codecs(self):
        root, triplets = self.codec_preflight()  # Never trust an earlier audit.
        require_uncompiled_outputs(root)
        marker = root / '.rd-cl-codec-bootstrap.json'
        native.save(marker, {'source_commit': self.args.source_commit, 'machine': 'S2', 'schema': 1, 'phase': 'COMPILING'})
        started_ns = time.time_ns()
        _, compile_text = self.run('codec-compile', self.command(root, triplets))
        compilers = re.findall(r'^Compiler found:\s*(.+?)\s*$', compile_text, re.MULTILINE)
        checked_paths = {os.path.normcase(p) for p in self.initial_tools}
        if not compilers or any(os.path.normcase(str(Path(p).resolve())) not in checked_paths for p in compilers):
            raise RuntimeError('Actual vcpkg compiler path is missing or differs from the checked compiler')
        evidence = require_compile_evidence(root, started_ns)
        # Prove preserved source installation/cache bytes before publishing proof.
        if inventory(self.tools['vcpkg'] / 'installed') != self.original_installed:
            raise RuntimeError('Original codec installation changed; receipt withheld')
        if inventory(self.preserved_download_root) != self.original_downloads:
            raise RuntimeError('Original download cache changed; receipt withheld')
        if self.tool_hashes() != self.initial_tools:
            raise RuntimeError('Compiler/CMake/tool bytes changed during compilation')
        for path, sha in self.input_tools.items():
            if native.digest(path) != sha:
                raise RuntimeError('Preserved input tool changed: ' + path)
        for relative, sha in {**self.overlays, **self.profile['input_sha256']}.items():
            if native.digest(self.source / relative) != sha:
                raise RuntimeError('Source/overlay changed during compilation: ' + relative)
        if native.digest(triplets / 'x64-windows-static.cmake') != PINS['triplet_sha256']:
            raise RuntimeError('Release-only triplet changed during compilation')
        installed = root / 'installed/x64-windows-static'
        hashes = inventory(installed)
        self.tools['vcpkg'] = root
        # CMake and compiler hashes use actual local executable paths, not S1 data.
        tool_hashes = self.tool_hashes()
        candidate = self.logs / 'codec-receipt.candidate.json'
        receipt = {'status': 'PASS', 'scope': 'codecs-only; NOT an application warm-cache receipt',
                   'machine': platform.node(), 'compiled_at': datetime.now(timezone.utc).isoformat(),
                   'source_commit': self.args.source_commit, 'base_source_commit': PINS['base_source_commit'],
                   'inputs': self.profile['input_sha256'], 'source_sha256': self.overlays,
                   'tool_sha256': tool_hashes, 'codec_abi_sha256': hashes,
                   'triplet_sha256': PINS['triplet_sha256'], 'compile_evidence': evidence,
                   'compiler_paths': compilers, 'cmake_version': self.cmake_version.strip(),
                   'preflight_sha256': native.digest(self.output / 'codec-preflight.json'),
                   'steps_sha256': native.digest(self.logs / 'steps.json'),
                   'dependency_policy': 'local inputs only; source compilation; binary/asset origins disabled'}
        native.save(candidate, receipt)
        self.cfg['compiled_cache_receipt'] = str(candidate)
        self.require_verified_codecs()  # Exact existing verifier, no exceptions.
        # Use the same installed-only guard and command as the release build.
        verify_command = [arg for arg in self.command(root, triplets) if arg != '--no-binarycaching']
        _, plan = self.run('codec-installed-plan', [*verify_command, '--dry-run', '--only-binarycaching'])
        native.require_installed_vcpkg_plan(plan)
        receipt_path = self.output / 'compiled-cache-receipt.json'
        toolchain_path = self.output / 'toolchain-codecs-local.json'
        if receipt_path.exists() or toolchain_path.exists():
            raise RuntimeError('Previous receipt/toolchain preserved; choose new owned output')
        native.save(receipt_path, receipt)
        cfg = json.loads(Path(self.args.toolchain).read_text(encoding='utf-8-sig'))
        cfg['paths']['vcpkg'] = str(root)
        cfg['paths']['vcpkg_cmake'] = str(self.tools['vcpkg_cmake'])
        cfg['environment']['VCPKG_ROOT'] = str(root)
        cfg['environment']['VCPKG_DOWNLOADS'] = str(root / 'downloads')
        cfg['compiled_cache_receipt'] = str(receipt_path)
        native.save(toolchain_path, cfg)
        native.save(marker, {'source_commit': self.args.source_commit, 'machine': 'S2', 'schema': 1, 'phase': 'COMPILED'})
        print('VERIFIED_CODEC_RECEIPT=' + str(receipt_path))
        print('TOOLCHAIN_FOR_EXISTING_BUILD=' + str(toolchain_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['Preflight', 'Compile'], required=True)
    parser.add_argument('--toolchain', required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--output-root', required=True)
    parser.add_argument('--codec-root', required=True)
    parser.add_argument('--existing-triplet', required=True)
    args = parser.parse_args()
    if os.name != 'nt' or platform.node().upper() != 'S2':
        parser.error('Execute only on native Windows S2, not S1, Wine or the Linux coordinator')
    runner = Bootstrap(args)
    try:
        if args.mode == 'Compile':
            runner.compile_codecs()
        else:
            runner.codec_preflight()
        native.save(runner.logs / 'result.json', {'status': 'PASS', 'mode': args.mode,
                    'native_codec_compilation': args.mode == 'Compile'})
        return 0
    except Exception as error:
        return native.report_failure(runner, error)
    finally:
        runner.close()


if __name__ == '__main__':
    sys.exit(main())
