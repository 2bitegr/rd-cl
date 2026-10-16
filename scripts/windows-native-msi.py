"""Package an already verified native rd-cl bundle without executing the product."""
import argparse
import ctypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
from datetime import datetime, timezone
import xml.etree.ElementTree as ET
import zipfile

PREPROCESS_SHA256 = 'f48cb7be2fb9f317a56972869eaa696ef25ac321dd11724cdd9100ccc410797a'


def local_nuget_config(cache):
    root = ET.Element('configuration')
    sources = ET.SubElement(root, 'packageSources')
    ET.SubElement(sources, 'clear')
    ET.SubElement(sources, 'add', key='existing-local-cache', value=str(cache / 'packages'))
    config = ET.SubElement(root, 'config')
    ET.SubElement(config, 'add', key='repositoryPath', value='packages')
    return ET.tostring(root, encoding='unicode')


def read_msi_metadata(path):
    """Use the Windows Installer database API in read-only mode, never install."""
    api = ctypes.WinDLL(str(Path(os.environ['SYSTEMROOT']) / 'System32/msi.dll'))
    u = ctypes.c_uint
    up = ctypes.POINTER(u)
    signatures = {
        'MsiOpenDatabaseW': [ctypes.c_wchar_p, ctypes.c_wchar_p, up],
        'MsiDatabaseOpenViewW': [u, ctypes.c_wchar_p, up],
        'MsiViewExecute': [u, u], 'MsiViewFetch': [u, up],
        'MsiRecordGetStringW': [u, u, ctypes.c_wchar_p, up],
        'MsiGetSummaryInformationW': [u, ctypes.c_wchar_p, u, up],
        'MsiSummaryInfoGetPropertyW': [u, u, up, ctypes.POINTER(ctypes.c_int),
                                     ctypes.c_void_p, ctypes.c_wchar_p, up],
        'MsiCloseHandle': [u], 'MsiViewClose': [u],
    }
    for name, types in signatures.items():
        fn = getattr(api, name); fn.argtypes = types; fn.restype = u

    def check(code):
        if code:
            raise RuntimeError('Windows Installer database API returned ' + str(code))

    def string(record, field):
        buf = ctypes.create_unicode_buffer(8192); size = u(len(buf))
        check(api.MsiRecordGetStringW(record, field, buf, ctypes.byref(size)))
        return buf.value

    db, view, summary = u(), u(), u()
    try:
        check(api.MsiOpenDatabaseW(str(path), None, ctypes.byref(db)))
        check(api.MsiDatabaseOpenViewW(db, 'SELECT `Property`, `Value` FROM `Property`', ctypes.byref(view)))
        check(api.MsiViewExecute(view, 0)); properties = {}
        while True:
            record = u(); code = api.MsiViewFetch(view, ctypes.byref(record))
            if code == 259:
                break
            check(code)
            try:
                key = string(record, 1)
                if key in {'ProductName', 'ProductVersion', 'Manufacturer', 'UpgradeCode'}:
                    properties[key] = string(record, 2)
            finally:
                api.MsiCloseHandle(record)
        check(api.MsiGetSummaryInformationW(db, None, 0, ctypes.byref(summary)))
        buf = ctypes.create_unicode_buffer(8192); size, kind = u(len(buf)), u()
        check(api.MsiSummaryInfoGetPropertyW(summary, 7, ctypes.byref(kind), None, None,
                                            buf, ctypes.byref(size)))
        return {'properties': properties, 'summary_template': buf.value,
                'summary_type': kind.value, 'database_mode': 'read-only'}
    finally:
        if summary.value: api.MsiCloseHandle(summary)
        if view.value:
            api.MsiViewClose(view); api.MsiCloseHandle(view)
        if db.value: api.MsiCloseHandle(db)


def package(b, module):
    digest, save = module.digest, module.save
    info = json.loads((b.output / 'BUILD-INFO.json').read_text(encoding='utf-8'))
    receipt = json.loads((b.output / 'native-compile-receipt.json').read_text(encoding='utf-8'))
    if (info['status'] != 'PASS' or info['architecture'] != 'windows-x64' or
            info['source_commit'] != b.args.source_commit or receipt['source_commit'] != b.args.source_commit):
        raise RuntimeError('MSI requires a verified matching native portable build')
    if digest(info['package']) != info['package_sha256']:
        raise RuntimeError('Portable package changed after its verified build')
    bundle = b.source / 'flutter/build/windows/x64/runner/Release'
    for name, expected in receipt['payload_sha256'].items():
        if digest(bundle / name) != expected:
            raise RuntimeError('Native runtime changed: ' + name)
    if digest(b.source / 'flutter/pubspec.lock') != receipt['lock_sha256']:
        raise RuntimeError('Native lock inputs changed')
    preprocess = b.source / 'res/msi/preprocess.py'
    if digest(preprocess) != PREPROCESS_SHA256:
        raise RuntimeError('MSI metadata-only preprocessor differs from reviewed bytes')
    version_text = (b.source / 'src/version.rs').read_text(encoding='utf-8')
    version = re.search(r'pub const VERSION:\s*&str\s*=\s*"([^"]+)"', version_text).group(1)
    date = re.search(r'pub const BUILD_DATE:\s*&str\s*=\s*"([^"]+)"', version_text).group(1)
    base, revision = b.profile['version'].split('+')
    if version != base or not re.fullmatch(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}', date):
        raise RuntimeError('Generated Rust version/date does not match the native profile')
    rc = (b.source / 'flutter/windows/runner/Runner.rc').read_text(encoding='utf-8')
    product = re.search(r'VALUE\s+"ProductName",\s*"([^"]+)"', rc).group(1)
    if re.search(r'[<>:"/\\|?*\r\n]', product):
        raise RuntimeError('Unsafe source-defined product filename')
    delivery = b.output / ('ExantasInstaller-' + b.profile['version'] + '-windows-x64.msi')
    if delivery.exists():
        raise RuntimeError('Refusing to overwrite an existing MSI delivery')

    # Restore only task-owned installer templates, preserving ignored tool caches.
    archive = b.logs / 'source-msi-templates.zip'
    b.git('msi-source-archive', '-c', 'core.eol=lf', 'archive', '--format=zip', '--output=' + str(archive),
          b.args.source_commit, 'res/msi', 'res/icon.ico')
    generated = b.source / '.rd-cl-msi-generated.json'
    previous = json.loads(generated.read_text(encoding='utf-8')) if generated.exists() else None
    if previous and previous['source_commit'] != b.args.source_commit:
        raise RuntimeError('Installer template ownership mismatch')
    with zipfile.ZipFile(archive) as templates:
        if templates.testzip(): raise RuntimeError('Installer source archive CRC failure')
        files = {}
        for member in templates.infolist():
            path = PurePosixPath(member.filename)
            if path.is_absolute() or '..' in path.parts:
                raise RuntimeError('Unexpected installer source path')
            if member.is_dir(): continue
            if not (member.filename.startswith('res/msi/') or member.filename == 'res/icon.ico'):
                raise RuntimeError('Unexpected installer source path')
            if not member.is_dir(): files[member.filename] = templates.read(member)
        for name, data in files.items():
            target = b.source / name
            if name == 'res/msi/preprocess.py': continue
            if target.exists():
                expected = previous['files'].get(name) if previous else hashlib.sha256(data).hexdigest()
                if digest(target) != expected:
                    raise RuntimeError('Unrecognized installer source change; preserved: ' + name)
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or target.read_bytes() != data: target.write_bytes(data)

    payload = b.output / ('MsiPayload-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
    shutil.copytree(bundle, payload)
    (payload / 'rustdesk.exe').rename(payload / (product + '.exe'))
    project = b.source / 'res/msi'
    try:
        b.run('msi-preprocess', [b.tools['python'], preprocess, '--arp', '--dist-dir', payload,
                               '--app-name', product, '--version', base, '--revision-version', revision,
                               '--build-date', date], cwd=project)
    finally:
        # Even a partial generator failure remains identifiable/recoverable as
        # this invocation's own derived state, with no reset of unknown edits.
        save(generated, {'source_commit': b.args.source_commit,
                         'files': {name: digest(b.source / name) for name in files}})
    artifact = Path(b.cfg['artifact_root'])
    if b.cfg.get('drive_alias'): artifact = Path(b.cfg['drive_alias']['drive'] + '\\')
    cache = artifact / 'Tools/nuget-wix4'
    for part in ['packages', 'http', 'scratch']: (cache / part).mkdir(parents=True, exist_ok=True)
    b.env.update({'NUGET_PACKAGES': str(cache / 'packages'), 'NUGET_HTTP_CACHE_PATH': str(cache / 'http'),
                  'NUGET_SCRATCH': str(cache / 'scratch'), 'DOTNET_CLI_TELEMETRY_OPTOUT': '1'})
    config = project / 'NuGet.Config'
    config.write_text(local_nuget_config(cache), encoding='utf-8')
    wix = ET.parse(project / 'Package/Package.wixproj').getroot()
    if wix.attrib['Sdk'] != 'WixToolset.Sdk/4.0.5': raise RuntimeError('Unexpected installer SDK')
    msbuild = b.vs / 'MSBuild/Current/Bin/amd64/MSBuild.exe'
    # Restrict both package restore and the SDK resolver to existing local packages.
    # An absent WiX/extension package is a build failure, never an online fallback.
    options = ['/p:RestoreSources=' + str(cache / 'packages'), '/p:NuGetAudit=false',
               '/p:Configuration=Release', '/p:Platform=x64', '/p:WindowsTargetPlatformVersion=10.0.22621.0',
               '/m:1', '/nr:false', '/verbosity:minimal']
    b.run('msi-restore', [msbuild, 'msi.sln', '/t:Restore', '/p:RestorePackagesConfig=true',
                         '/p:RestoreConfigFile=' + str(config), *options], cwd=project)
    b.run('msi-build', [msbuild, 'msi.sln', '/t:Build', *options], cwd=project)
    output_name = wix.findtext('.//OutputName')
    if output_name != 'ExantasInstaller': raise RuntimeError('Unexpected installer output identity')
    built = project / 'Package/bin/x64/Release/en-us/ExantasInstaller.msi'
    if not built.is_file(): raise RuntimeError('Expected x64 installer output missing: ' + str(built))
    metadata = read_msi_metadata(built)
    if (metadata['summary_template'].split(';')[0].lower() != 'x64' or
            metadata['properties'].get('ProductName') != product or
            metadata['properties'].get('ProductVersion') != base + '.' + revision):
        raise RuntimeError('Installer architecture/product/version mismatch')
    shutil.copy2(built, delivery)
    if digest(built) != digest(delivery): raise RuntimeError('Installer delivery copy checksum mismatch')
    result = {'status': 'PASS', 'built_at_utc': datetime.now(timezone.utc).isoformat(),
              'source_commit': b.args.source_commit, 'version': b.profile['version'],
              'approved_flutter_lock_sha256': receipt['lock_sha256'], 'wix_sdk': '4.0.5',
              'installer': str(delivery), 'installer_sha256': digest(delivery), 'metadata': metadata,
              'product_build_date': date, 'generated_rust_version_sha256': digest(b.source / 'src/version.rs'),
              'preprocess_sha256': PREPROCESS_SHA256, 'msi_helper_sha256': digest(__file__),
              'product_execution': 'NOT RUN', 'product_installation': 'NOT RUN', 'signing': 'NOT RUN',
              'toolchain_manifest': str(b.logs / 'toolchain-manifest.json')}
    save(b.output / 'MSI-INFO.json', result)
    with (b.output / 'SHA256SUMS').open('a', encoding='utf-8') as sums:
        sums.write(digest(delivery) + '  ' + delivery.name + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain', required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--output-root', required=True)
    args = parser.parse_args(); args.mode = 'PackageMsi'
    spec = importlib.util.spec_from_file_location('native_build', Path(__file__).with_name('windows-native-build.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    b = module.Build(args)
    try:
        b.preflight(); b.developer_environment(); package(b, module); b.close()
        module.save(b.logs / 'result.json', {'mode': args.mode, 'status': 'PASS'})
        return 0
    except Exception as error:
        return module.report_failure(b, error)
    finally:
        b.close()


if __name__ == '__main__':
    sys.exit(main())
