import 'dart:convert';

import 'package:crypto/crypto.dart';

class TapoEncoding {
  static String encodeUsername(String username) {
    final digest = sha1.convert(utf8.encode(username)).toString();
    return base64Encode(utf8.encode(digest));
  }

  static String encodePassword(String password) {
    return base64Encode(utf8.encode(password));
  }

  static String? decodeBase64String(String? value) {
    if (value == null || value.isEmpty) {
      return value;
    }
    try {
      final decoded = base64Decode(value);
      return utf8.decode(decoded);
    } catch (_) {
      return value;
    }
  }
}
