import 'package:http/http.dart' as http;

http.Client createPlatformHttpClient({bool allowInsecure = false}) {
  return http.Client();
}
