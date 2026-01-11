import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tapo/flutter_tapo.dart';
import 'package:http/http.dart' as http;

import 'http_client_factory.dart';
import 'raw_socket_client.dart';

class CustomTapoApiClient extends TapoApiClient {
  CustomTapoApiClient({
    required super.host,
    super.port = 80,
    super.useHttps = false,
    bool allowInsecureHttps = false,
    String userAgent = 'reqwest/0.11.22',
    String acceptEncoding = 'gzip, deflate',
    bool useRawSocketForHandshake = false,
    bool useRawSocketForKlapRequests = false,
    http.Client? client,
  }) : _client = client ??
            createHttpClient(
              allowInsecure: allowInsecureHttps,
            ),
       _userAgent = userAgent,
       _acceptEncoding = acceptEncoding,
       _useRawSocketForHandshake = useRawSocketForHandshake,
       _useRawSocketForKlapRequests = useRawSocketForKlapRequests;

  final http.Client _client;
  final String _userAgent;
  final String _acceptEncoding;
  final bool _useRawSocketForHandshake;
  final bool _useRawSocketForKlapRequests;

  @override
  Future<TapoApiResponse> post(
    Uri url, {
    Map<String, String>? headers,
    required String body,
  }) async {
    final response = await _send(url, headers: headers, body: utf8.encode(body));
    final responseBody = utf8.decode(response.bodyBytes);

    return TapoApiResponse(
      statusCode: response.statusCode,
      body: responseBody,
      headers: response.headers,
    );
  }

  @override
  Future<TapoApiBytesResponse> postBytes(
    Uri url, {
    Map<String, String>? headers,
    required Uint8List body,
  }) async {
    final response = await _send(url, headers: headers, body: body);

    return TapoApiBytesResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      headers: response.headers,
    );
  }

  Future<_RawResponse> _send(
    Uri url, {
    Map<String, String>? headers,
    required List<int> body,
  }) async {
    final resolvedHeaders = <String, String>{
      if (!kIsWeb) 'User-Agent': _userAgent,
      if (!kIsWeb) 'Accept-Encoding': _acceptEncoding,
      'Accept': '*/*',
      ...?headers,
    };

    if (kDebugMode && url.path.contains('handshake')) {
      debugPrint(
        'HTTP request url=$url contentLength=${body.length} headers=$resolvedHeaders',
      );
    }

    if (_useRawSocketForHandshake &&
        !kIsWeb &&
        url.scheme == 'http' &&
        _isHandshakePath(url.path)) {
      debugPrint('Using raw socket for $url');
      final rawResponse = await sendRawSocketRequest(
        host: url.host,
        port: url.port,
        method: 'POST',
        pathWithQuery: url.hasQuery ? '${url.path}?${url.query}' : url.path,
        headers: resolvedHeaders,
        body: Uint8List.fromList(body),
      );
      return _RawResponse(
        statusCode: rawResponse.statusCode,
        bodyBytes: rawResponse.bodyBytes,
        headers: rawResponse.headers,
      );
    }

    if (_useRawSocketForKlapRequests &&
        !kIsWeb &&
        url.scheme == 'http' &&
        _isKlapRequestPath(url.path)) {
      debugPrint('Using raw socket for $url');
      final rawResponse = await sendRawSocketRequest(
        host: url.host,
        port: url.port,
        method: 'POST',
        pathWithQuery: url.hasQuery ? '${url.path}?${url.query}' : url.path,
        headers: resolvedHeaders,
        body: Uint8List.fromList(body),
      );
      return _RawResponse(
        statusCode: rawResponse.statusCode,
        bodyBytes: rawResponse.bodyBytes,
        headers: rawResponse.headers,
      );
    }

    final request = http.Request('POST', url)
      ..headers.addAll(resolvedHeaders)
      ..bodyBytes = Uint8List.fromList(body)
      ..followRedirects = false
      ..maxRedirects = 0;

    final streamed = await _client.send(request);
    final responseBytes = await streamed.stream.toBytes();
    return _RawResponse(
      statusCode: streamed.statusCode,
      bodyBytes: Uint8List.fromList(responseBytes),
      headers: streamed.headers,
    );
  }

  void close() {
    _client.close();
  }

  @override
  void log(String message) {
    debugPrint(message);
  }
}

class _RawResponse {
  const _RawResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.headers,
  });

  final int statusCode;
  final Uint8List bodyBytes;
  final Map<String, String> headers;
}

bool _isHandshakePath(String path) {
  return path.endsWith('/handshake1') || path.endsWith('/handshake2');
}

bool _isKlapRequestPath(String path) {
  return path.endsWith('/request');
}
