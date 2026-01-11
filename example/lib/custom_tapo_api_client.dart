import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tapo/flutter_tapo.dart';
import 'package:http/http.dart' as http;

import 'http_client_factory.dart';

class CustomTapoApiClient extends TapoApiClient {
  CustomTapoApiClient({
    required super.host,
    super.port = 80,
    super.useHttps = false,
    bool allowInsecureHttps = false,
    http.Client? client,
  }) : _client = client ??
            createHttpClient(
              allowInsecure: allowInsecureHttps,
            );

  final http.Client _client;

  @override
  Future<TapoApiResponse> post(
    Uri url, {
    Map<String, String>? headers,
    required String body,
  }) async {
    final response = await _client.post(url, headers: headers, body: body);
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
    final response = await _client.post(url, headers: headers, body: body);

    return TapoApiBytesResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      headers: response.headers,
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
