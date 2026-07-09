import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const String _dpapiPrefix = 'dpapi:v1:';

class ExantasSecureStore {
  const ExantasSecureStore();

  bool isProtected(String value) => value.startsWith(_dpapiPrefix);

  String protect(String value) {
    if (value.isEmpty) {
      return '';
    }
    if (!Platform.isWindows) {
      return value;
    }
    return '$_dpapiPrefix${base64Encode(_protectWithDpapi(value))}';
  }

  String unprotect(String storedValue) {
    if (storedValue.isEmpty) {
      return '';
    }
    if (!storedValue.startsWith(_dpapiPrefix)) {
      return storedValue;
    }
    if (!Platform.isWindows) {
      return '';
    }
    final encrypted = base64Decode(storedValue.substring(_dpapiPrefix.length));
    return utf8.decode(_unprotectWithDpapi(encrypted));
  }

  List<int> _protectWithDpapi(String value) {
    final plainText = utf8.encode(value);
    return using((alloc) {
      final pPlainText = alloc<Uint8>(plainText.length);
      pPlainText.asTypedList(plainText.length).setAll(0, plainText);

      final plainTextBlob = alloc<CRYPT_INTEGER_BLOB>();
      plainTextBlob.ref.cbData = plainText.length;
      plainTextBlob.ref.pbData = pPlainText;

      final encryptedTextBlob = alloc<CRYPT_INTEGER_BLOB>();
      if (CryptProtectData(
            plainTextBlob,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0,
            encryptedTextBlob,
          ) ==
          0) {
        throw WindowsException(
          GetLastError(),
          message: 'Could not protect Exantas Office token.',
        );
      }

      if (encryptedTextBlob.ref.pbData.address == NULL) {
        throw WindowsException(
          WIN32_ERROR.ERROR_OUTOFMEMORY,
          message: 'Could not protect Exantas Office token.',
        );
      }

      try {
        return List<int>.from(
          encryptedTextBlob.ref.pbData.asTypedList(
            encryptedTextBlob.ref.cbData,
          ),
        );
      } finally {
        LocalFree(encryptedTextBlob.ref.pbData);
      }
    });
  }

  List<int> _unprotectWithDpapi(List<int> encrypted) {
    return using((alloc) {
      final pEncryptedText = alloc<Uint8>(encrypted.length);
      pEncryptedText.asTypedList(encrypted.length).setAll(0, encrypted);

      final encryptedTextBlob = alloc<CRYPT_INTEGER_BLOB>();
      encryptedTextBlob.ref.cbData = encrypted.length;
      encryptedTextBlob.ref.pbData = pEncryptedText;

      final plainTextBlob = alloc<CRYPT_INTEGER_BLOB>();
      if (CryptUnprotectData(
            encryptedTextBlob,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0,
            plainTextBlob,
          ) ==
          0) {
        throw WindowsException(
          GetLastError(),
          message: 'Could not unprotect Exantas Office token.',
        );
      }

      if (plainTextBlob.ref.pbData.address == NULL) {
        throw WindowsException(
          WIN32_ERROR.ERROR_OUTOFMEMORY,
          message: 'Could not unprotect Exantas Office token.',
        );
      }

      try {
        return List<int>.from(
          plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
        );
      } finally {
        LocalFree(plainTextBlob.ref.pbData);
      }
    });
  }
}
