import 'dart:typed_data';

import 'raw_socket_client_stub.dart'
    if (dart.library.io) 'raw_socket_client_io.dart';
import 'raw_socket_client_types.dart';

Future<RawSocketResponse> sendRawSocketRequest({
  required String host,
  required int port,
  required String method,
  required String pathWithQuery,
  Map<String, String>? headers,
  required Uint8List body,
}) {
  return sendPlatformRawSocketRequest(
    host: host,
    port: port,
    method: method,
    pathWithQuery: pathWithQuery,
    headers: headers,
    body: body,
  );
}
