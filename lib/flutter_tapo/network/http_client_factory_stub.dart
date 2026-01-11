import 'package:http/http.dart' as http;

http.Client createPlatformHttpClient({bool allowInsecure = false}) =>
    throw UnsupportedError('Platform not supported');
