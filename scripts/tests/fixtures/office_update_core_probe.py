"""Inert native GUI-child fixture, launched with existing Windows pythonw.exe.

No product, service, IPC or network operations. PID markers stay in fixture TEMP.
Write to inherited Win32 handles directly: pythonw may leave sys.stdout unset.
"""
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import sys
import time


def emit(handle_id, value):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetStdHandle.argtypes = [wintypes.DWORD]
    kernel.GetStdHandle.restype = wintypes.HANDLE
    kernel.WriteFile.argtypes = [wintypes.HANDLE, wintypes.LPCVOID,
                                wintypes.DWORD, ctypes.POINTER(wintypes.DWORD),
                                wintypes.LPVOID]
    kernel.WriteFile.restype = wintypes.BOOL
    handle = kernel.GetStdHandle(handle_id & 0xffffffff)
    data = value.encode('utf-8')
    offset = 0
    while offset < len(data):
        chunk = ctypes.create_string_buffer(data[offset:offset + 4096])
        count = wintypes.DWORD()
        if not kernel.WriteFile(handle, chunk, len(chunk.raw) - 1,
                                ctypes.byref(count), None) or not count.value:
            raise OSError('fixture_pipe_closed')
        offset += count.value


def main():
    if os.name != 'nt':
        return 91
    mode = sys.argv[1]
    if mode == 'sleep':
        Path(sys.argv[2]).write_text(str(os.getpid()), encoding='ascii')
        time.sleep(60)
        return 0
    if mode == 'empty':
        return 0
    if mode == 'malformed':
        emit(-11, '{not-json}\n')
        return 0
    if mode == 'multiple':
        emit(-11, '{}\n{}\n')
        return 0
    if mode == 'overflow':
        emit(-11, 'x' * 1100000)
        return 0
    payload = json.dumps({'ok': True, 'argv': sys.argv[2:],
                          'pid': os.getpid()}, ensure_ascii=False) + '\n'
    if mode == 'nonzero':
        emit(-11, payload)
        emit(-12, 'SYNTHETIC_PRIVATE_TEXT\n')
        return 7
    if mode == 'stderr':
        emit(-11, payload)
        emit(-12, 'SYNTHETIC_PRIVATE_TEXT\n')
        return 0
    if mode == 'both':
        emit(-11, json.dumps({'data': 'a' * 131072}) + '\n')
        emit(-12, 'b' * 131072)
        return 0
    if mode == 'delayed':
        time.sleep(0.6)
    emit(-11, payload)
    return 0


if __name__ == '__main__':
    try:
        os._exit(main())
    except Exception:
        os._exit(92)
