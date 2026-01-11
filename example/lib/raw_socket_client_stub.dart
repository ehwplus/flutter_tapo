import 'dart:typed_data';

import 'raw_socket_client_types.dart';

Future<RawSocketResponse> sendPlatformRawSocketRequest({
  required String host,
  required int port,
  required String method,
  required String pathWithQuery,
  Map<String, String>? headers,
  required Uint8List body,
}) {
  throw UnsupportedError('Raw socket requests are not supported on this platform.');
}
