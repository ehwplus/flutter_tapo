import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createPlatformHttpClient({bool allowInsecure = false}) {
  if (!allowInsecure) {
    return IOClient();
  }
  final ioClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;
  return IOClient(ioClient);
}
