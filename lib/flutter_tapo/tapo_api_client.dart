import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'tapo_cipher.dart';
import 'tapo_device_info.dart';
import 'tapo_encoding.dart';
import 'tapo_energy_usage.dart';
import 'tapo_exception.dart';
import 'tapo_klap.dart';

abstract class TapoApiClient {
  TapoApiClient({
    required this.host,
    this.port = 80,
    this.useHttps = false,
    Uuid? uuid,
  }) : terminalUuid = (uuid ?? const Uuid()).v4();

  final String host;
  final int port;
  final bool useHttps;
  final String terminalUuid;

  TapoCipher? _cipher;
  String? _cookie;
  String? _token;
  TapoProtocolType? _protocolType;
  TapoKlapSession? _klapSession;
  String _klapBasePath = '/app';

  String? get token => _token;
  bool get isAuthenticated {
    if (_protocolType == TapoProtocolType.klap) {
      return _klapSession != null;
    }
    return _token != null;
  }

  Future<void> authenticate({
    required String email,
    required String password,
  }) async {
    _protocolType ??= await _discoverProtocol();
    if (_protocolType == TapoProtocolType.klap) {
      log('Starting KLAP handshake...');
      try {
        await _klapHandshake(email: email, password: password);
        log('KLAP handshake OK.');
        return;
      } on TapoApiException catch (error) {
        log('KLAP handshake failed: $error');
        if (error.code != 400) {
          rethrow;
        }
      }
    }

    _protocolType = TapoProtocolType.passthrough;
    log('Starting passthrough handshake...');
    await handshake();
    log('Handshake OK. Logging in...');
    await login(email: email, password: password);
    log('Login OK. Token received.');
  }

  Future<void> handshake() async {
    _protocolType ??= TapoProtocolType.passthrough;
    final keyPair = TapoKeyPair.generate();
    final keyPem = keyPair.toPublicKeyPem();
    final keyPemCrlf = keyPem.replaceAll('\n', '\r\n');
    final keyBase64 = keyPem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '');
    final keyVariants = <String>[keyPem, keyPemCrlf, keyBase64];
    final attempts = <Map<String, dynamic>>[
      for (final key in keyVariants) ...[
        {
          'method': 'handshake',
          'params': {
            'key': key,
          },
        },
        {
          'method': 'handshake',
          'params': {
            'key': key,
          },
          'requestTimeMils': 0,
        },
        {
          'method': 'handshake',
          'params': {
            'key': key,
            'requestTimeMils': 0,
          },
        },
      ],
    ];

    TapoApiException? lastError;
    for (var i = 0; i < attempts.length; i++) {
      final payload = attempts[i];
      log('Handshake attempt ${i + 1}: ${jsonEncode(payload)}');
      try {
        final response = await _postJson(
          _baseUri(),
          payload,
          includeCookie: false,
        );

        log('Handshake response: ${response.body}');
        _updateCookie(response.headers);
        final data = _decodeJson(response.body);
        _ensureSuccess(data);

        final result = _extractResult(data);
        final key = result['key']?.toString();
        if (key == null || key.isEmpty) {
          throw const TapoProtocolException('Handshake did not return a key.');
        }

        _cipher = TapoCipher.fromHandshakeKey(
          handshakeKey: key,
          keyPair: keyPair,
        );
        _token = null;
        return;
      } on TapoApiException catch (error) {
        lastError = error;
        if (error.code != 1002 &&
            error.code != 1003 &&
            error.code != -1003) {
          rethrow;
        }
        log('Handshake attempt ${i + 1} failed: $error');
      }
    }

    if (lastError != null) {
      throw lastError;
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    _protocolType ??= TapoProtocolType.passthrough;
    final encodedUsername = TapoEncoding.encodeUsername(email);
    final encodedPassword = TapoEncoding.encodePassword(password);

    final payload = _buildPayload(
      'login_device',
      params: {
        'username': encodedUsername,
        'password': encodedPassword,
      },
      includeRequestTimeMils: true,
    );

    final safePayload = Map<String, dynamic>.from(payload);
    final safeParams = Map<String, dynamic>.from(
      safePayload['params'] as Map<String, dynamic>,
    );
    if (safeParams.containsKey('password')) {
      safeParams['password'] = '***';
    }
    safePayload['params'] = safeParams;
    log('Login request: ${jsonEncode(safePayload)}');
    final response = await _sendSecure(payload, withToken: false);
    final result = _extractResult(response);
    final token = result['token']?.toString();

    if (token == null || token.isEmpty) {
      throw const TapoProtocolException('Login did not return a token.');
    }
    _token = token;
  }

  Future<TapoDeviceInfo> getDeviceInfo() async {
    final payload = _buildPayload(
      'get_device_info',
      includeRequestTimeMils: true,
    );
    log('Device info request: ${jsonEncode(payload)}');
    final response = await _sendRequest(payload, requiresToken: true);
    log('Device info response: ${jsonEncode(response)}');
    return TapoDeviceInfo.fromJson(_extractResult(response));
  }

  Future<void> setPowerState(bool isOn) async {
    final payload = _buildPayload(
      'set_device_info',
      params: {
        'device_on': isOn,
      },
      includeRequestTimeMils: true,
      includeTerminalUuid: true,
    );

    log('Set power request: ${jsonEncode(payload)}');
    await _sendRequest(payload, requiresToken: true);
  }

  Future<TapoEnergyUsage> getEnergyUsage() async {
    final payload = _buildPayload(
      'get_energy_usage',
      includeRequestTimeMils: true,
    );
    log('Energy usage request: ${jsonEncode(payload)}');
    final response = await _sendRequest(payload, requiresToken: true);
    log('Energy usage response: ${jsonEncode(response)}');
    return TapoEnergyUsage.fromJson(_extractResult(response));
  }

  Future<Map<String, dynamic>> _sendRequest(
    Map<String, dynamic> payload, {
    required bool requiresToken,
  }) async {
    if (_protocolType == TapoProtocolType.klap) {
      return _sendKlap(payload);
    }
    return _sendSecure(payload, withToken: requiresToken);
  }

  Future<Map<String, dynamic>> _sendSecure(
    Map<String, dynamic> payload, {
    required bool withToken,
  }) async {
    final cipher = _cipher;
    if (cipher == null) {
      throw const TapoProtocolException('Handshake must be completed first.');
    }

    if (withToken && _token == null) {
      throw const TapoProtocolException('Login must be completed first.');
    }

    final encryptedPayload = cipher.encrypt(jsonEncode(payload));
    final securePayload = <String, dynamic>{
      'method': 'securePassthrough',
      'params': {
        'request': encryptedPayload,
      },
    };

    log('Secure passthrough request: ${jsonEncode(securePayload)}');
    final response = await _postJson(_baseUri(withToken: withToken), securePayload);
    log('Secure passthrough response: ${response.body}');
    final outer = _decodeJson(response.body);
    _ensureSuccess(outer);

    final outerResult = _extractResult(outer);
    final encryptedResponse = outerResult['response']?.toString();
    if (encryptedResponse == null || encryptedResponse.isEmpty) {
      throw const TapoProtocolException('Secure response is missing.');
    }

    final decrypted = cipher.decrypt(encryptedResponse);
    log('Secure response decrypted: $decrypted');
    final inner = _decodeJson(decrypted);
    _ensureSuccess(inner);

    return inner;
  }

  Future<Map<String, dynamic>> _sendKlap(
    Map<String, dynamic> payload,
  ) async {
    final session = _klapSession;
    if (session == null) {
      throw const TapoProtocolException('KLAP handshake must be completed first.');
    }

    final requestString = jsonEncode(payload);
    final encrypted = session.cipher.encrypt(requestString);
    final uri = _klapRequestUri(encrypted.seq);

    log('KLAP request seq=${encrypted.seq}: ${jsonEncode(payload)}');
    final response = await _postBytes(
      uri,
      encrypted.payload,
      cookie: session.cookie,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const TapoApiException(9999, 'Session timeout');
      }
      throw TapoApiException(
        response.statusCode,
        'Invalid response',
      );
    }

    final decrypted = session.cipher.decrypt(encrypted.seq, response.bodyBytes);
    log('KLAP response decrypted: $decrypted');
    final inner = _decodeJson(decrypted);
    _ensureSuccess(inner);
    return inner;
  }

  Map<String, dynamic> _buildPayload(
    String method, {
    Map<String, dynamic>? params,
    bool includeRequestTimeMils = false,
    bool includeTerminalUuid = false,
  }) {
    final payload = <String, dynamic>{
      'method': method,
      'params': params ?? <String, dynamic>{},
    };

    if (includeRequestTimeMils) {
      payload['requestTimeMils'] = DateTime.now().millisecondsSinceEpoch;
    }

    if (includeTerminalUuid) {
      payload['terminalUUID'] = terminalUuid;
    }

    return payload;
  }

  Uri _baseUri({bool withToken = false}) {
    final scheme = useHttps ? 'https' : 'http';
    final query = withToken ? 'token=$_token' : null;

    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: '/app',
      query: query,
    );
  }

  Uri _klapHandshakeUri(String path, {String? basePath}) {
    final scheme = useHttps ? 'https' : 'http';
    final resolvedPath = _joinKlapPath(basePath ?? _klapBasePath, path);
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: resolvedPath,
    );
  }

  Uri _klapRequestUri(int seq) {
    final scheme = useHttps ? 'https' : 'http';
    final resolvedPath = _joinKlapPath(_klapBasePath, 'request');
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: resolvedPath,
      queryParameters: {
        'seq': seq.toString(),
      },
    );
  }

  String _joinKlapPath(String basePath, String segment) {
    if (basePath.isEmpty || basePath == '/') {
      return '/$segment';
    }
    final normalized = basePath.startsWith('/') ? basePath : '/$basePath';
    final trimmed =
        normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
    return '$trimmed/$segment';
  }

  Future<TapoApiResponse> _postJson(
    Uri url,
    Map<String, dynamic> payload, {
    bool includeCookie = true,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (includeCookie && _cookie != null) {
      headers['Cookie'] = _cookie!;
    }

    final body = jsonEncode(payload);
    return post(url, headers: headers, body: body);
  }

  Future<TapoApiBytesResponse> _postBytes(
    Uri url,
    Uint8List payload, {
    String? cookie,
    String? contentType,
    Map<String, String>? headers,
  }) async {
    final resolvedHeaders = <String, String>{};
    if (headers != null) {
      resolvedHeaders.addAll(headers);
    }
    if (contentType != null && contentType.isNotEmpty) {
      resolvedHeaders['Content-Type'] = contentType;
    }
    if (cookie != null) {
      resolvedHeaders['Cookie'] = cookie;
    }
    return postBytes(url, headers: resolvedHeaders, body: payload);
  }

  void _updateCookie(Map<String, String> headers) {
    String? setCookie;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        setCookie = entry.value;
        break;
      }
    }

    if (setCookie == null || setCookie.isEmpty) {
      return;
    }

    final match = RegExp(
      r'(TP_SESSIONID)=([^;]+)',
      caseSensitive: false,
    ).firstMatch(setCookie);
    if (match != null) {
      final name = match.group(1)!;
      final value = match.group(2)!;
      _cookie = '$name=$value';
      return;
    }

    final parts = setCookie.split(';');
    if (parts.isNotEmpty) {
      _cookie = parts.first.trim();
    }
  }

  Map<String, dynamic> _decodeJson(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const TapoProtocolException('Unexpected response format.');
  }

  Map<String, dynamic> _extractResult(Map<String, dynamic> response) {
    final result = response['result'];
    if (result is Map<String, dynamic>) {
      return result;
    }
    return <String, dynamic>{};
  }

  void _ensureSuccess(Map<String, dynamic> response) {
    final rawCode = response['error_code'];
    if (rawCode == null) {
      return;
    }
    final code = rawCode is int ? rawCode : int.tryParse(rawCode.toString()) ?? 0;
    if (code == 0) {
      return;
    }

    final message = _errorMessages[code] ?? 'Unknown error';
    log('Tapo error $code: $message');
    throw TapoApiException(code, message, payload: response);
  }

  void log(String message) {}

  Future<TapoProtocolType> _discoverProtocol() async {
    final attempts = <Map<String, dynamic>>[
      {
        'method': 'component_nego',
      },
      {
        'method': 'component_nego',
        'params': <String, dynamic>{},
      },
      {
        'method': 'component_nego',
        'params': <String, dynamic>{},
        'requestTimeMils': 0,
      },
    ];

    for (var i = 0; i < attempts.length; i++) {
      final payload = attempts[i];
      log('Component negotiation attempt ${i + 1}: ${jsonEncode(payload)}');
      final response = await _postJson(_baseUri(), payload, includeCookie: false);
      log('Component negotiation response: ${response.body}');
      _updateCookie(response.headers);
      if (_cookie != null) {
        log('Component negotiation cookie: $_cookie');
      }

      final data = _decodeJson(response.body);
      final rawCode = data['error_code'];
      final code =
          rawCode is int ? rawCode : int.tryParse(rawCode.toString()) ?? 0;

      if (code == 0) {
        return TapoProtocolType.passthrough;
      }
      if (code == 1003 || code == -1003) {
        continue;
      }

      _ensureSuccess(data);
    }

    return TapoProtocolType.klap;
  }

  Future<void> _klapHandshake({
    required String email,
    required String password,
  }) async {
    final basePaths = <String>['/app', ''];
    final revisions = <TapoKlapRevision>[
      TapoKlapRevision.v2,
      TapoKlapRevision.v1,
    ];

    TapoApiException? lastApiError;
    TapoProtocolException? lastProtocolError;

    for (final basePath in basePaths) {
      for (final revision in revisions) {
        log('KLAP handshake attempt (${revision.label}) using base "${basePath.isEmpty ? "/" : basePath}"');
        try {
          final result = await _klapHandshakeAttempt(
            email: email,
            password: password,
            revision: revision,
            basePath: basePath,
          );

          _klapBasePath = basePath.isEmpty ? '' : basePath;
          _klapSession = TapoKlapSession(
            cookie: _cookie ?? '',
            cipher: TapoKlapCipher.create(
              localSeed: result.localSeed,
              remoteSeed: result.remoteSeed,
              authHash: result.authHash,
            ),
          );
          return;
        } on TapoApiException catch (error) {
          lastApiError = error;
          log('KLAP ${revision.label} handshake failed: $error');
        } on TapoProtocolException catch (error) {
          lastProtocolError = error;
          log('KLAP ${revision.label} handshake failed: $error');
        }
      }
    }

    if (lastApiError != null) {
      throw lastApiError;
    }
    if (lastProtocolError != null) {
      throw lastProtocolError;
    }
    throw const TapoProtocolException('KLAP handshake failed.');
  }

  Future<_KlapHandshakeResult> _klapHandshakeAttempt({
    required String email,
    required String password,
    required TapoKlapRevision revision,
    required String basePath,
  }) async {
    final authHash = tapoKlapAuthHash(
      username: email,
      password: password,
      revision: revision,
    );
    final localSeed = tapoRandomBytes(16);
    final handshake1Uri = _klapHandshakeUri(
      'handshake1',
      basePath: basePath,
    );

    log('Handshake1 request (${revision.label}) uri=$handshake1Uri length=${localSeed.length}');
    final handshake1Response = await _postBytes(
      handshake1Uri,
      localSeed,
      cookie: _cookie,
      contentType: 'application/octet-stream',
      headers: const {
        'Accept': '*/*',
      },
    );
    _updateCookie(handshake1Response.headers);
    log('Handshake1 status: ${handshake1Response.statusCode}');
    log('Handshake1 headers: ${handshake1Response.headers}');
    log('Handshake1 cookie: ${_cookie ?? "(none)"}');
    log('Handshake1 body length: ${handshake1Response.bodyBytes.length}');
    if (handshake1Response.bodyBytes.isNotEmpty) {
      log('Handshake1 body hex: ${_bytesToHex(handshake1Response.bodyBytes)}');
    }

    if (handshake1Response.statusCode < 200 ||
        handshake1Response.statusCode >= 300) {
      throw TapoApiException(
        handshake1Response.statusCode,
        'Handshake1 failed',
      );
    }

    if (handshake1Response.bodyBytes.length < 48) {
      throw const TapoProtocolException('Handshake1 response too short.');
    }

    final candidates = <_KlapAuthCandidate>[
      _KlapAuthCandidate(label: 'credentials', authHash: authHash),
      _KlapAuthCandidate(
        label: 'blank',
        authHash: tapoKlapAuthHash(
          username: '',
          password: '',
          revision: revision,
        ),
      ),
      _KlapAuthCandidate(
        label: 'test',
        authHash: tapoKlapAuthHash(
          username: 'test@tp-link.net',
          password: 'test',
          revision: revision,
        ),
      ),
    ];

    _KlapHandshakeMatch? match;
    final maxOffset = handshake1Response.bodyBytes.length - 48;
    for (final candidate in candidates) {
      for (var offset = 0; offset <= maxOffset; offset++) {
        final remoteSeed = handshake1Response.bodyBytes.sublist(offset, offset + 16);
        final serverHash =
            handshake1Response.bodyBytes.sublist(offset + 16, offset + 48);
        final localHash = tapoKlapHandshake1Hash(
          localSeed: localSeed,
          remoteSeed: remoteSeed,
          authHash: candidate.authHash,
          revision: revision,
        );
        if (_bytesEqual(serverHash, localHash)) {
          match = _KlapHandshakeMatch(
            candidate: candidate,
            remoteSeed: remoteSeed,
            offset: offset,
          );
          break;
        }
      }
      if (match != null) {
        break;
      }
    }

    if (match == null) {
      throw const TapoProtocolException('Handshake1 hash mismatch.');
    }

    if (match.offset != 0) {
      log('Handshake1 matched at offset ${match.offset}.');
    }
    if (match.candidate.label != 'credentials') {
      log('Handshake1 matched using ${match.candidate.label} auth hash.');
    }
    final handshake2Uri = _klapHandshakeUri(
      'handshake2',
      basePath: basePath,
    );
    final handshake2Payload = tapoKlapHandshake2Hash(
      localSeed: localSeed,
      remoteSeed: match.remoteSeed,
      authHash: match.candidate.authHash,
      revision: revision,
    );
    final handshake2Response = await _postBytes(
      handshake2Uri,
      handshake2Payload,
      cookie: _cookie,
      contentType: 'application/octet-stream',
      headers: const {
        'Accept': '*/*',
      },
    );
    log('Handshake2 status: ${handshake2Response.statusCode}');
    if (handshake2Response.bodyBytes.isNotEmpty) {
      log('Handshake2 body length: ${handshake2Response.bodyBytes.length}');
    }

    if (handshake2Response.statusCode < 200 ||
        handshake2Response.statusCode >= 300) {
      throw TapoApiException(
        handshake2Response.statusCode,
        'Handshake2 failed',
      );
    }

    return _KlapHandshakeResult(
      localSeed: localSeed,
      remoteSeed: match.remoteSeed,
      authHash: match.candidate.authHash,
    );
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  String _bytesToHex(List<int> data, {int maxBytes = 64}) {
    final limited = data.length > maxBytes ? data.sublist(0, maxBytes) : data;
    final buffer = StringBuffer();
    for (final value in limited) {
      buffer.write(value.toRadixString(16).padLeft(2, '0'));
    }
    if (data.length > maxBytes) {
      buffer.write('...');
    }
    return buffer.toString();
  }

  Future<TapoApiResponse> post(
    Uri url, {
    Map<String, String>? headers,
    required String body,
  });

  Future<TapoApiBytesResponse> postBytes(
    Uri url, {
    Map<String, String>? headers,
    required Uint8List body,
  });
}

class TapoApiResponse {
  const TapoApiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

class TapoApiBytesResponse {
  const TapoApiBytesResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.headers,
  });

  final int statusCode;
  final Uint8List bodyBytes;
  final Map<String, String> headers;
}

enum TapoProtocolType {
  passthrough,
  klap,
}

const Map<int, String> _errorMessages = {
  1002: 'Incorrect request',
  1003: 'Incorrect request',
  -1002: 'Invalid request',
  -1003: 'Malformed request',
  -1008: 'Invalid parameters',
  -1010: 'Invalid public key length',
  -1012: 'Invalid terminal UUID',
  -1501: 'Invalid request or credentials',
  9999: 'Session timeout',
};

class _KlapHandshakeResult {
  const _KlapHandshakeResult({
    required this.localSeed,
    required this.remoteSeed,
    required this.authHash,
  });

  final Uint8List localSeed;
  final Uint8List remoteSeed;
  final Uint8List authHash;
}

class _KlapAuthCandidate {
  const _KlapAuthCandidate({
    required this.label,
    required this.authHash,
  });

  final String label;
  final Uint8List authHash;
}

class _KlapHandshakeMatch {
  const _KlapHandshakeMatch({
    required this.candidate,
    required this.remoteSeed,
    required this.offset,
  });

  final _KlapAuthCandidate candidate;
  final Uint8List remoteSeed;
  final int offset;
}
