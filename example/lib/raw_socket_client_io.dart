import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'raw_socket_client_types.dart';

Future<RawSocketResponse> sendPlatformRawSocketRequest({
  required String host,
  required int port,
  required String method,
  required String pathWithQuery,
  Map<String, String>? headers,
  required Uint8List body,
}) async {
  final socket = await Socket.connect(host, port);

  final normalizedHeaders = <String, String>{};
  headers?.forEach((key, value) {
    normalizedHeaders[key.toLowerCase()] = value;
  });

  final headerLines = <String>[
    '$method $pathWithQuery HTTP/1.1',
    if (!normalizedHeaders.containsKey('host'))
      'Host: ${port == 80 ? host : '$host:$port'}',
    if (!normalizedHeaders.containsKey('content-length'))
      'Content-Length: ${body.length}',
    if (!normalizedHeaders.containsKey('connection')) 'Connection: close',
  ];

  if (headers != null) {
    headers.forEach((key, value) {
      headerLines.add('$key: $value');
    });
  }

  final requestString = '${headerLines.join('\r\n')}\r\n\r\n';
  socket.add(latin1.encode(requestString));
  if (body.isNotEmpty) {
    socket.add(body);
  }
  await socket.flush();

  final responseBytes = await _readHttpResponse(socket);
  await socket.close();

  return responseBytes;
}

Future<RawSocketResponse> _readHttpResponse(Socket socket) {
  final completer = Completer<RawSocketResponse>();
  final buffer = <int>[];
  Timer? timer;

  int? headerEnd;
  int? contentLength;
  Map<String, String>? headers;
  int? statusCode;
  bool isChunked = false;

  void finish() {
    if (completer.isCompleted) {
      return;
    }
    timer?.cancel();

    if (headerEnd == null || headers == null || statusCode == null) {
      completer.completeError(
        const FormatException('Missing HTTP response headers.'),
      );
      return;
    }

    final bodyStart = headerEnd! + 4;
    final bodyBytes = buffer.length >= bodyStart
        ? Uint8List.fromList(buffer.sublist(bodyStart))
        : Uint8List(0);

    Uint8List decodedBody = bodyBytes;
    if (isChunked) {
      decodedBody = _decodeChunked(decodedBody);
    }

    final contentEncoding = headers!['content-encoding']?.toLowerCase();
    if (contentEncoding == 'gzip') {
      decodedBody = Uint8List.fromList(gzip.decode(decodedBody));
    } else if (contentEncoding == 'deflate') {
      decodedBody = Uint8List.fromList(ZLibCodec().decode(decodedBody));
    }

    completer.complete(
      RawSocketResponse(
        statusCode: statusCode!,
        headers: headers!,
        bodyBytes: decodedBody,
      ),
    );
  }

  void parseHeadersIfReady() {
    if (headerEnd != null) {
      return;
    }
    final end = _indexOf(buffer, const [13, 10, 13, 10]);
    if (end == -1) {
      return;
    }
    headerEnd = end;

    final headerBytes = buffer.sublist(0, end);
    final headerText = latin1.decode(headerBytes);
    final lines = headerText.split('\r\n');
    if (lines.isEmpty) {
      throw const FormatException('Empty HTTP response.');
    }

    final statusLine = lines.first.trim();
    final statusParts = statusLine.split(' ');
    if (statusParts.length < 2) {
      throw FormatException('Invalid status line: $statusLine');
    }
    statusCode = int.tryParse(statusParts[1]) ?? 0;

    headers = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) {
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final name = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      headers![name] = value;
    }

    final transferEncoding = headers!['transfer-encoding']?.toLowerCase();
    isChunked = transferEncoding != null && transferEncoding.contains('chunked');
    final contentLengthHeader = headers!['content-length'];
    if (contentLengthHeader != null) {
      contentLength = int.tryParse(contentLengthHeader);
    }
  }

  bool isBodyComplete() {
    if (headerEnd == null) {
      return false;
    }
    final bodyStart = headerEnd! + 4;
    if (contentLength != null) {
      return buffer.length >= bodyStart + contentLength!;
    }
    if (isChunked) {
      final bodyBytes = buffer.length >= bodyStart
          ? Uint8List.fromList(buffer.sublist(bodyStart))
          : Uint8List(0);
      return _hasChunkedTerminator(bodyBytes);
    }
    return false;
  }

  timer = Timer(const Duration(seconds: 5), () {
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException('No HTTP response', const Duration(seconds: 5)),
      );
    }
  });

  socket.listen(
    (data) {
      buffer.addAll(data);
      parseHeadersIfReady();
      if (isBodyComplete()) {
        finish();
      }
    },
    onDone: () {
      finish();
    },
    onError: (error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    },
  );

  return completer.future;
}

int _indexOf(List<int> data, List<int> pattern) {
  if (pattern.isEmpty || data.length < pattern.length) {
    return -1;
  }
  for (var i = 0; i <= data.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

Uint8List _decodeChunked(Uint8List data) {
  var offset = 0;
  final output = <int>[];

  while (offset < data.length) {
    final lineEnd = _indexOf(data.sublist(offset), const [13, 10]);
    if (lineEnd == -1) {
      break;
    }
    final sizeLine =
        ascii.decode(data.sublist(offset, offset + lineEnd)).trim();
    final sizeToken = sizeLine.split(';').first;
    final size = int.tryParse(sizeToken, radix: 16) ?? 0;
    offset += lineEnd + 2;
    if (size == 0) {
      break;
    }
    final end = offset + size;
    if (end > data.length) {
      break;
    }
    output.addAll(data.sublist(offset, end));
    offset = end + 2;
  }

  return Uint8List.fromList(output);
}

bool _hasChunkedTerminator(Uint8List data) {
  if (data.length < 5) {
    return false;
  }
  final marker = ascii.encode('0\r\n\r\n');
  return _indexOf(data, marker) != -1;
}
