import 'dart:collection';
import 'dart:convert';
import 'dart:io';

class TapoDeviceDiscovery {
  const TapoDeviceDiscovery._();

  static Future<List<String>> scanSubnet({
    String base = '192.168.178',
    int start = 1,
    int end = 254,
    int concurrency = 32,
    Duration timeout = const Duration(milliseconds: 800),
    int warmupAttempts = 2,
    Duration warmupDelay = const Duration(milliseconds: 150),
    int probeAttempts = 2,
    Duration probeDelay = const Duration(milliseconds: 250),
    List<int> ports = const [80, 443],
    void Function(int scanned, int total)? onProgress,
  }) async {
    _validateBase(base);
    if (start < 1 || end > 254 || end < start) {
      throw ArgumentError('start/end must be within 1..254 and start <= end.');
    }
    if (concurrency < 1) {
      throw ArgumentError('concurrency must be >= 1.');
    }
    if (warmupAttempts < 0) {
      throw ArgumentError('warmupAttempts must be >= 0.');
    }
    if (probeAttempts < 1) {
      throw ArgumentError('probeAttempts must be >= 1.');
    }

    final ips = List<String>.generate(end - start + 1, (index) => '$base.${start + index}');
    final queue = ListQueue<String>.from(ips);
    final found = <String>{};
    var scanned = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final ip = queue.removeFirst();
        final isTapo = await _probeTapo(
          ip,
          ports: ports,
          timeout: timeout,
          warmupAttempts: warmupAttempts,
          warmupDelay: warmupDelay,
          probeAttempts: probeAttempts,
          probeDelay: probeDelay,
        );
        if (isTapo) {
          found.add(ip);
        }
        scanned += 1;
        onProgress?.call(scanned, ips.length);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    final results = found.toList()..sort();
    return results;
  }

  static Future<bool> _probeTapo(
    String ip, {
    required List<int> ports,
    required Duration timeout,
    required int warmupAttempts,
    required Duration warmupDelay,
    required int probeAttempts,
    required Duration probeDelay,
  }) async {
    for (final port in ports) {
      if (warmupAttempts > 0) {
        await _warmup(ip, port, timeout, warmupAttempts, warmupDelay);
      }
      try {
        final scheme = port == 443 ? 'https' : 'http';
        final client = HttpClient()..connectionTimeout = timeout;
        if (scheme == 'https') {
          client.badCertificateCallback = (_, __, ___) => true;
        }
        try {
          for (var attempt = 0; attempt < probeAttempts; attempt += 1) {
            for (final payload in _componentNegoPayloads) {
              final request = await client.postUrl(Uri(scheme: scheme, host: ip, port: port, path: '/app'));
              request.headers.contentType = ContentType.json;
              request.headers.set('accept', 'application/json');
              request.write(jsonEncode(payload));
              final response = await request.close().timeout(timeout);
              final body = await response.transform(utf8.decoder).join().timeout(timeout);
              if (_looksLikeTapo(body)) {
                return true;
              }
            }
            if (attempt + 1 < probeAttempts) {
              await Future.delayed(probeDelay);
            }
          }
        } finally {
          client.close(force: true);
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  static Future<void> _warmup(
    String ip,
    int port,
    Duration timeout,
    int attempts,
    Duration delay,
  ) async {
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        final socket = await Socket.connect(ip, port, timeout: timeout);
        socket.destroy();
      } catch (_) {}
      if (attempt + 1 < attempts) {
        await Future.delayed(delay);
      }
    }
  }

  static bool _looksLikeTapo(String body) {
    if (body.isEmpty) {
      return false;
    }
    if (body.contains('error_code')) {
      return true;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('error_code')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  static const List<Map<String, dynamic>> _componentNegoPayloads = [
    {'method': 'component_nego'},
    {'method': 'component_nego', 'params': <String, dynamic>{}},
    {'method': 'component_nego', 'params': <String, dynamic>{}, 'requestTimeMils': 0},
  ];

  static void _validateBase(String base) {
    final parts = base.split('.');
    if (parts.length != 3) {
      throw ArgumentError('base must be in form "192.168.178".');
    }
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        throw ArgumentError('base must contain valid IPv4 octets.');
      }
    }
  }
}
