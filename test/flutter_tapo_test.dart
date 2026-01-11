import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tapo/flutter_tapo.dart';

void main() {
  test('encodes username with sha1 hex and base64', () {
    const username = 'user@example.com';
    final encoded = TapoEncoding.encodeUsername(username);

    expect(
      encoded,
      'NjNhNzEwNTY5MjYxYTI0YjM3NjYyNzViNzAwMGNlOGQ3YjMyZTJmNw==',
    );
  });

  test('encodes password as base64', () {
    final encoded = TapoEncoding.encodePassword('secret');
    expect(encoded, 'c2VjcmV0');
  });

  test('parses energy usage local time', () {
    final usage = TapoEnergyUsage.fromJson({
      'local_time': '2024-01-02 10:11:12',
      'today_runtime': 42,
      'today_energy': 123,
      'month_runtime': 200,
      'month_energy': 450,
    });

    expect(usage.localTime, DateTime(2024, 1, 2, 10, 11, 12));
    expect(usage.todayEnergy, 123);
  });
}
