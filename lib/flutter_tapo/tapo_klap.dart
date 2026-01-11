import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

enum TapoKlapRevision {
  v1,
  v2,
}

extension TapoKlapRevisionLabel on TapoKlapRevision {
  String get label {
    switch (this) {
      case TapoKlapRevision.v1:
        return 'KLAP v1';
      case TapoKlapRevision.v2:
        return 'KLAP v2';
    }
  }
}

class TapoKlapCipher {
  TapoKlapCipher._({
    required this.key,
    required this.ivPrefix,
    required this.sigKey,
    required int seq,
  }) : _seq = seq;

  final Uint8List key;
  final Uint8List ivPrefix;
  final Uint8List sigKey;
  int _seq;

  static TapoKlapCipher create({
    required Uint8List localSeed,
    required Uint8List remoteSeed,
    required Uint8List authHash,
  }) {
    final localHash = Uint8List.fromList([
      ...localSeed,
      ...remoteSeed,
      ...authHash,
    ]);

    final ivHash = _sha256Bytes(utf8.encode('iv') + localHash);
    final ivPrefix = Uint8List.fromList(ivHash.sublist(0, 12));
    final seqBytes = Uint8List.fromList(ivHash.sublist(ivHash.length - 4));
    final seq = ByteData.sublistView(seqBytes).getInt32(0, Endian.big);

    final keyHash = _sha256Bytes(utf8.encode('lsk') + localHash);
    final sigHash = _sha256Bytes(utf8.encode('ldk') + localHash);

    return TapoKlapCipher._(
      key: Uint8List.fromList(keyHash.sublist(0, 16)),
      ivPrefix: ivPrefix,
      sigKey: Uint8List.fromList(sigHash.sublist(0, 28)),
      seq: seq,
    );
  }

  TapoKlapEncrypted encrypt(String data) {
    _seq = _incrementSeq(_seq);
    final seq = _seq;
    final ivSeq = _buildIvSeq(seq);

    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      true,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV(KeyParameter(key), ivSeq),
        null,
      ),
    );

    final encrypted = cipher.process(Uint8List.fromList(utf8.encode(data)));
    final signature = _sha256Bytes(
      Uint8List.fromList([
        ...sigKey,
        ..._int32ToBytes(seq),
        ...encrypted,
      ]),
    );

    final payload = Uint8List.fromList([
      ...signature,
      ...encrypted,
    ]);

    return TapoKlapEncrypted(payload: payload, seq: seq);
  }

  String decrypt(int seq, Uint8List payload) {
    final ivSeq = _buildIvSeq(seq);
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV(KeyParameter(key), ivSeq),
        null,
      ),
    );

    if (payload.length <= 32) {
      return '';
    }
    final decrypted = cipher.process(payload.sublist(32));
    return utf8.decode(decrypted);
  }

  Uint8List _buildIvSeq(int seq) {
    return Uint8List.fromList([
      ...ivPrefix,
      ..._int32ToBytes(seq),
    ]);
  }

  static Uint8List _sha256Bytes(List<int> data) {
    return Uint8List.fromList(sha256.convert(data).bytes);
  }

  static int _incrementSeq(int value) {
    final next = (value + 1) & 0xffffffff;
    if (next & 0x80000000 != 0) {
      return next - 0x100000000;
    }
    return next;
  }

  static List<int> _int32ToBytes(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}

class TapoKlapEncrypted {
  const TapoKlapEncrypted({
    required this.payload,
    required this.seq,
  });

  final Uint8List payload;
  final int seq;
}

class TapoKlapSession {
  const TapoKlapSession({
    required this.cookie,
    required this.cipher,
  });

  final String cookie;
  final TapoKlapCipher cipher;
}

Uint8List tapoKlapAuthHash({
  required String username,
  required String password,
  TapoKlapRevision revision = TapoKlapRevision.v2,
}) {
  switch (revision) {
    case TapoKlapRevision.v1:
      final usernameHash = md5.convert(utf8.encode(username)).bytes;
      final passwordHash = md5.convert(utf8.encode(password)).bytes;
      return Uint8List.fromList(
        md5.convert([...usernameHash, ...passwordHash]).bytes,
      );
    case TapoKlapRevision.v2:
      final usernameDigest = sha1.convert(utf8.encode(username)).bytes;
      final passwordDigest = sha1.convert(utf8.encode(password)).bytes;
      return Uint8List.fromList(
        sha256.convert([...usernameDigest, ...passwordDigest]).bytes,
      );
  }
}

Uint8List tapoKlapHandshake1Hash({
  required Uint8List localSeed,
  required Uint8List remoteSeed,
  required Uint8List authHash,
  TapoKlapRevision revision = TapoKlapRevision.v2,
}) {
  switch (revision) {
    case TapoKlapRevision.v1:
      return Uint8List.fromList(
        sha256.convert([...localSeed, ...authHash]).bytes,
      );
    case TapoKlapRevision.v2:
      return Uint8List.fromList(
        sha256.convert([...localSeed, ...remoteSeed, ...authHash]).bytes,
      );
  }
}

Uint8List tapoKlapHandshake2Hash({
  required Uint8List localSeed,
  required Uint8List remoteSeed,
  required Uint8List authHash,
  TapoKlapRevision revision = TapoKlapRevision.v2,
}) {
  switch (revision) {
    case TapoKlapRevision.v1:
      return Uint8List.fromList(
        sha256.convert([...remoteSeed, ...authHash]).bytes,
      );
    case TapoKlapRevision.v2:
      return Uint8List.fromList(
        sha256.convert([...remoteSeed, ...localSeed, ...authHash]).bytes,
      );
  }
}

Uint8List tapoRandomBytes(int length) {
  final random = Random.secure();
  final data = Uint8List(length);
  for (var i = 0; i < length; i++) {
    data[i] = random.nextInt(256);
  }
  return data;
}
