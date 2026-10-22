"""Synthetic Windows SDK identity for guard tests; never a compiled-cache receipt."""

def sdk_fixture(runner, root):
    version = '10.0.22621.0'
    sdk = root / 'WindowsSDK'
    runner.env = getattr(runner, 'env', {})
    runner.env.update({'WINDOWSSDKVERSION': version + '\\', 'WINDOWSSDKDIR': str(sdk)})
    for name in ['Include/{version}/um/Windows.h', 'Include/{version}/shared/sdkddkver.h',
                 'Include/{version}/ucrt/corecrt.h', 'Lib/{version}/um/x64/kernel32.lib',
                 'Lib/{version}/ucrt/x64/ucrt.lib', 'Lib/{version}/ucrt/x64/libucrt.lib']:
        path = sdk / name.format(version=version)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'synthetic SDK input')
    return runner.selected_sdk_identity()
