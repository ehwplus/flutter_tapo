import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

http.Client createPlatformHttpClient({bool allowInsecure = false}) {
  final client = BrowserClient()..withCredentials = true;
  return client;
}
