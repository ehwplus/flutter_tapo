import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

sealed class TapoSubnetScanEvent {
  const TapoSubnetScanEvent();
}

class TapoSubnetDeviceCountEvent extends TapoSubnetScanEvent {
  const TapoSubnetDeviceCountEvent({
    required this.devicesFound,
    required this.scanned,
    required this.total,
  });

  final int devicesFound;
  final int scanned;
  final int total;
}

class TapoSubnetTapoCandidatesEvent extends TapoSubnetScanEvent {
  const TapoSubnetTapoCandidatesEvent(this.candidates);

  final List<String> candidates;
}

class TapoSubnetScanCompleteEvent extends TapoSubnetScanEvent {
  const TapoSubnetScanCompleteEvent(this.devices);

  final List<String> devices;
}

class TapoDeviceDiscovery {
  const TapoDeviceDiscovery._();

  /// Streams discovery events for the given subnet.
  static Stream<TapoSubnetScanEvent> scanSubnet({
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
  }) {
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
    final controller = StreamController<TapoSubnetScanEvent>();
    var canceled = false;

    void emit(TapoSubnetScanEvent event) {
      if (canceled || controller.isClosed) {
        return;
      }
      controller.add(event);
    }

    controller.onCancel = () {
      canceled = true;
    };

    controller.onListen = () {
      () async {
        final queue = ListQueue<String>.from(ips);
        final found = <String>{};
        var scanned = 0;
        var devicesFound = 0;

        Future<void> worker() async {
          while (!canceled) {
            if (queue.isEmpty) {
              break;
            }
            final ip = queue.removeFirst();
            final hasDevice = await _hasOpenPort(ip, ports: ports, timeout: timeout);
            if (hasDevice) {
              devicesFound += 1;
            }
            scanned += 1;
            emit(TapoSubnetDeviceCountEvent(
              devicesFound: devicesFound,
              scanned: scanned,
              total: ips.length,
            ));
            if (hasDevice) {
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
                final snapshot = found.toList()..sort();
                emit(TapoSubnetTapoCandidatesEvent(snapshot));
              }
            }
          }
        }

        await Future.wait(List.generate(concurrency, (_) => worker()));
        if (!canceled) {
          final results = found.toList()..sort();
          emit(TapoSubnetScanCompleteEvent(results));
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      }().catchError((Object error, StackTrace stackTrace) async {
        canceled = true;
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      });
    };

    return controller.stream;
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

  static Future<bool> _hasOpenPort(
    String ip, {
    required List<int> ports,
    required Duration timeout,
  }) async {
    for (final port in ports) {
      try {
        final socket = await Socket.connect(ip, port, timeout: timeout);
        socket.destroy();
        return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<void> _warmup(String ip, int port, Duration timeout, int attempts, Duration delay) async {
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
