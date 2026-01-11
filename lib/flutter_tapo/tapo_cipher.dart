import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

import 'tapo_exception.dart';

class TapoKeyPair {
  TapoKeyPair(this.privateKey, this.publicKey);

  final RSAPrivateKey privateKey;
  final RSAPublicKey publicKey;

  static TapoKeyPair generate() {
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    final random = Random.secure();
    for (var i = 0; i < seed.length; i++) {
      seed[i] = random.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 64),
          secureRandom,
        ),
      );

    final keyPair = keyGen.generateKeyPair();
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;

    return TapoKeyPair(privateKey, publicKey);
  }

  String toPublicKeyPem() {
    final algorithmSeq = ASN1Sequence();
    final algorithmAsn1Obj = ASN1ObjectIdentifier.fromComponentString(
      '1.2.840.113549.1.1.1',
    );
    final paramsAsn1Obj = ASN1Null();
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    final modulus = publicKey.modulus;
    final exponent = publicKey.exponent;
    if (modulus == null || exponent == null) {
      throw const TapoProtocolException('Invalid RSA public key.');
    }

    final publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(modulus));
    publicKeySeq.add(ASN1Integer(exponent));

    final publicKeySeqBitString =
        ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

    final topLevelSeq = ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);

    final base64Key = base64Encode(topLevelSeq.encodedBytes);
    final chunked = _chunk(base64Key, 64);
    return '-----BEGIN PUBLIC KEY-----\n$chunked\n-----END PUBLIC KEY-----';
  }

  static String _chunk(String value, int chunkSize) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i += chunkSize) {
      final end = (i + chunkSize < value.length) ? i + chunkSize : value.length;
      buffer.writeln(value.substring(i, end));
    }
    return buffer.toString().trimRight();
  }
}

class TapoCipher {
  TapoCipher({
    required this.key,
    required this.iv,
  }) {
    if (key.length != 16 || iv.length != 16) {
      throw const TapoProtocolException('AES key and IV must be 16 bytes long.');
    }
  }

  final Uint8List key;
  final Uint8List iv;

  factory TapoCipher.fromHandshakeKey({
    required String handshakeKey,
    required TapoKeyPair keyPair,
  }) {
    final encryptedBytes = base64Decode(handshakeKey);
    final rsa = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(keyPair.privateKey));

    final decrypted = rsa.process(encryptedBytes);
    if (decrypted.length != 32) {
      throw TapoProtocolException(
        'Expected 32 bytes from handshake key, got ${decrypted.length}.',
      );
    }

    final aesKey = Uint8List.fromList(decrypted.sublist(0, 16));
    final aesIv = Uint8List.fromList(decrypted.sublist(16, 32));
    return TapoCipher(key: aesKey, iv: aesIv);
  }

  String encrypt(String data) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      true,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ),
    );

    final input = Uint8List.fromList(utf8.encode(data));
    final encrypted = cipher.process(input);
    return base64Encode(encrypted);
  }

  String decrypt(String data) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ),
    );

    final decoded = base64Decode(data);
    final decrypted = cipher.process(decoded);
    return utf8.decode(decrypted);
  }
}
