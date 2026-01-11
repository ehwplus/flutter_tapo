import 'package:crypto/crypto.dart';

class TapoEncoding {
  static String encodeUsername(String email) {
    final digest = sha1.convert(email.codeUnits);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String encodePassword(String password) {
    final digest = sha1.convert(password.codeUnits);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
