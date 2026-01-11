import 'package:http/http.dart' as http;

import 'http_client_factory_stub.dart'
    if (dart.library.io) 'http_client_factory_io.dart';

http.Client createHttpClient({bool allowInsecure = false}) {
  return createPlatformHttpClient(allowInsecure: allowInsecure);
}
