import 'package:flutter/material.dart';
import 'package:flutter_tapo/flutter_tapo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const title = 'Tapo P115 Demo';
    return MaterialApp(
      title: title,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), useMaterial3: true),
      home: const MyHomePage(title: title),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _ipController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _scrollController = ScrollController();

  HttpTapoApiClient? _client;
  TapoDeviceInfo? _deviceInfo;
  TapoEnergyUsage? _energyUsage;
  TapoEnergyData? _energyData;
  bool _isLoading = false;
  String? _error;
  bool _isScanning = false;
  int _scanProgress = 0;
  int _scanTotal = 0;
  List<String> _discoveredIps = const [];
  TapoEnergyDataIntervalType _energyIntervalType = TapoEnergyDataIntervalType.daily;
  DateTime _energyStartDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _energyEndDate = DateTime.now();

  bool get _isConnected => _client?.isAuthenticated == true;

  @override
  void dispose() {
    _client?.close();
    _scrollController.dispose();
    _ipController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('tapo_ip');
    final email = prefs.getString('tapo_email');
    final password = prefs.getString('tapo_password');
    if (!mounted) return;
    setState(() {
      if (ip != null) _ipController.text = ip;
      if (email != null) _emailController.text = email;
      if (password != null) _passwordController.text = password;
    });
  }

  Future<void> _savePrefs({required String ip, required String email, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tapo_ip', ip);
    await prefs.setString('tapo_email', email);
    await prefs.setString('tapo_password', password);
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final rawInput = _ipController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (rawInput.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Please provide IP, email and password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _energyUsage = null;
      _energyData = null;
    });

    Uri? deviceUri;
    try {
      deviceUri = rawInput.contains('://') ? Uri.parse(rawInput) : Uri.parse('http://$rawInput');
    } catch (_) {
      setState(() {
        _error = 'Invalid device address. Use IP or full URL.';
        _isLoading = false;
      });
      return;
    }

    if (deviceUri.host.isEmpty) {
      setState(() {
        _error = 'Invalid device address. Use IP or full URL.';
        _isLoading = false;
      });
      return;
    }

    final client = HttpTapoApiClient(
      host: deviceUri.host,
      port: deviceUri.hasPort ? deviceUri.port : (deviceUri.scheme == 'https' ? 443 : 80),
      useHttps: deviceUri.scheme == 'https',
      allowInsecureHttps: deviceUri.scheme == 'https',
    );

    try {
      await _savePrefs(ip: rawInput, email: email, password: password);
      await client.authenticate(email: email, password: password);
      final info = await client.getDeviceInfo();
      setState(() {
        _client = client;
        _deviceInfo = info;
      });
    } on TapoInvalidCredentialsException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshDeviceInfo() async {
    final client = _client;
    if (client == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final info = await client.getDeviceInfo();
      setState(() {
        _deviceInfo = info;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePower(bool value) async {
    final client = _client;
    if (client == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await client.setPowerState(value);
      final info = await client.getDeviceInfo();
      setState(() {
        _deviceInfo = info;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadEnergyUsage() async {
    final client = _client;
    if (client == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final usage = await client.getEnergyUsage();
      setState(() {
        _energyUsage = usage;
      });
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _scanForDevices() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
      _scanProgress = 0;
      _scanTotal = 254;
      _discoveredIps = const [];
      _error = null;
    });

    try {
      final results = await TapoDeviceDiscovery.scanSubnet(
        base: '192.168.178',
        onProgress: (scanned, total) {
          if (!mounted) {
            return;
          }
          setState(() {
            _scanProgress = scanned;
            _scanTotal = total;
          });
        },
      );
      if (mounted) {
        setState(() {
          _discoveredIps = results;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _loadEnergyData() async {
    final client = _client;
    if (client == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final clamped = _clampEnergyRange(_energyStartDate, _energyEndDate, now);
      final start = _startOfDay(clamped.start);
      final end = _startOfDay(clamped.end);
      if (end.isBefore(start)) {
        throw ArgumentError('End date must be on or after start date.');
      }
      if (_energyIntervalType == TapoEnergyDataIntervalType.daily && !_isSameQuarter(start, end)) {
        throw ArgumentError('Daily energy data must stay within a single quarter.');
      }
      if (_energyIntervalType == TapoEnergyDataIntervalType.monthly && start.year != end.year) {
        throw ArgumentError('Monthly energy data must stay within a single year.');
      }

      final interval = switch (_energyIntervalType) {
        TapoEnergyDataIntervalType.hourly => TapoEnergyDataInterval.hourly(startDate: start, endDate: end),
        TapoEnergyDataIntervalType.daily => TapoEnergyDataInterval.daily(quarterStart: _quarterStart(start)),
        TapoEnergyDataIntervalType.monthly => TapoEnergyDataInterval.monthly(yearStart: DateTime(start.year, 1, 1)),
      };

      if (start != _energyStartDate || end != _energyEndDate) {
        setState(() {
          _energyStartDate = start;
          _energyEndDate = end;
        });
      }

      final data = await client.getEnergyData(interval);
      setState(() {
        _energyData = data;
      });
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  DateTime _quarterStart(DateTime date) {
    final quarterMonth = ((date.month - 1) ~/ 3) * 3 + 1;
    return DateTime(date.year, quarterMonth, 1);
  }

  bool _isSameQuarter(DateTime first, DateTime second) {
    final startA = _quarterStart(first);
    final startB = _quarterStart(second);
    return startA.year == startB.year && startA.month == startB.month;
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _energyWindowStart(DateTime now) {
    return switch (_energyIntervalType) {
      TapoEnergyDataIntervalType.hourly => now.subtract(const Duration(days: 7)),
      TapoEnergyDataIntervalType.daily => _addMonths(now, -3),
      TapoEnergyDataIntervalType.monthly => _addMonths(now, -12),
    };
  }

  ({DateTime start, DateTime end}) _clampEnergyRange(DateTime start, DateTime end, DateTime now) {
    final windowStart = _startOfDay(_energyWindowStart(now));
    final windowEnd = _startOfDay(now);
    var clampedStart = start;
    var clampedEnd = end;

    if (clampedStart.isBefore(windowStart)) {
      clampedStart = windowStart;
    }
    if (clampedEnd.isBefore(windowStart)) {
      clampedEnd = windowStart;
    }
    if (clampedStart.isAfter(windowEnd)) {
      clampedStart = windowEnd;
    }
    if (clampedEnd.isAfter(windowEnd)) {
      clampedEnd = windowEnd;
    }
    if (clampedEnd.isBefore(clampedStart)) {
      clampedEnd = clampedStart;
    }

    return (start: clampedStart, end: clampedEnd);
  }

  DateTime _addMonths(DateTime date, int months) {
    return DateTime(date.year, date.month + months, date.day);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final windowStart = _startOfDay(_energyWindowStart(now));
    final windowEnd = _startOfDay(now);
    final initialDate = _energyStartDate.isBefore(windowStart) ? windowStart : _energyStartDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(windowEnd) ? windowEnd : initialDate,
      firstDate: windowStart,
      lastDate: windowEnd,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _energyStartDate = picked;
      if (_energyEndDate.isBefore(picked)) {
        _energyEndDate = picked;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final windowStart = _startOfDay(_energyWindowStart(now));
    final windowEnd = _startOfDay(now);
    final initialDate = _energyEndDate.isBefore(windowStart) ? windowStart : _energyEndDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(windowEnd) ? windowEnd : initialDate,
      firstDate: windowStart,
      lastDate: windowEnd,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _energyEndDate = picked;
      if (_energyStartDate.isAfter(picked)) {
        _energyStartDate = picked;
      }
    });
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatEnergy(int wh) {
    if (wh >= 1000) {
      final kwh = (wh / 1000).toStringAsFixed(2);
      return '$kwh kWh';
    }
    return '$wh Wh';
  }

  String _formatPointLabel(TapoEnergyDataPoint point) {
    return switch (_energyIntervalType) {
      TapoEnergyDataIntervalType.hourly =>
        '${_formatDate(point.start)} ${point.start.hour.toString().padLeft(2, '0')}:00',
      TapoEnergyDataIntervalType.daily => _formatDate(point.start),
      TapoEnergyDataIntervalType.monthly => '${point.start.year}-${point.start.month.toString().padLeft(2, '0')}',
    };
  }

  String _intervalLabel(TapoEnergyDataIntervalType type) {
    return switch (type) {
      TapoEnergyDataIntervalType.hourly => 'Hourly',
      TapoEnergyDataIntervalType.daily => 'Daily',
      TapoEnergyDataIntervalType.monthly => 'Monthly',
    };
  }

  List<TapoEnergyDataPoint> _filteredEnergyPoints(TapoEnergyData data) {
    final start = _startOfDay(_energyStartDate);
    final end = _startOfDay(_energyEndDate);
    final now = data.localDateTime ?? DateTime.now();
    final normalizedEnd = end.isAfter(now) ? _startOfDay(now) : end;
    final windowStart = _energyWindowStart(now);

    return data.points.where((point) {
      final withinWindow = switch (_energyIntervalType) {
        TapoEnergyDataIntervalType.hourly => !point.start.isBefore(windowStart),
        TapoEnergyDataIntervalType.daily => !point.start.isBefore(_startOfDay(windowStart)),
        TapoEnergyDataIntervalType.monthly => !point.start.isBefore(DateTime(windowStart.year, windowStart.month, 1)),
      };

      final withinRange = switch (_energyIntervalType) {
        TapoEnergyDataIntervalType.hourly =>
          !point.start.isBefore(DateTime(start.year, start.month, start.day, 0)) &&
              !point.start.isAfter(DateTime(normalizedEnd.year, normalizedEnd.month, normalizedEnd.day, 23)),
        TapoEnergyDataIntervalType.daily => !point.start.isBefore(start) && !point.start.isAfter(normalizedEnd),
        TapoEnergyDataIntervalType.monthly =>
          !point.start.isBefore(DateTime(start.year, start.month, 1)) &&
              !point.start.isAfter(DateTime(normalizedEnd.year, normalizedEnd.month, 1)),
      };

      return withinWindow && withinRange;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final deviceInfo = _deviceInfo;
    final energyUsage = _energyUsage;
    final energyData = _energyData;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Discovery', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _isScanning ? null : _scanForDevices,
                child: Text(_isScanning ? 'Scanning...' : 'Scan devices'),
              ),
              if (_isScanning) Text('$_scanProgress/$_scanTotal'),
            ],
          ),
          if (!_isScanning && _scanTotal > 0 && _discoveredIps.isEmpty) ...[
            const SizedBox(height: 8),
            Text('No devices found in 192.168.178.0/24.', style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_discoveredIps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final ip in _discoveredIps)
                    ListTile(
                      title: Text(ip),
                      trailing: TextButton(
                        onPressed: () {
                          setState(() {
                            _ipController.text = ip;
                          });
                        },
                        child: const Text('Use'),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(labelText: 'Device IP or URL', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Tapo account email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Tapo account password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _isLoading ? null : _connect, child: const Text('Connect')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Device Info', style: Theme.of(context).textTheme.titleLarge)),
              IconButton(onPressed: _isLoading ? null : _refreshDeviceInfo, icon: Icon(Icons.refresh)),
            ],
          ),
          if (!_isConnected)
            Text('Not connected yet.', style: Theme.of(context).textTheme.bodySmall)
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Model: ${deviceInfo?.model ?? '-'}'),
                    Text('Device ID: ${deviceInfo?.deviceId ?? '-'}'),
                    Text('IP: ${deviceInfo?.ip ?? '-'}'),
                    Text('MAC: ${deviceInfo?.mac ?? '-'}'),
                    Text('Nickname: ${deviceInfo?.nickname ?? '-'}'),
                    Text('On time: ${deviceInfo?.onTime ?? 0}s'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Energy Usage', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: _isLoading ? null : _loadEnergyUsage, icon: Icon(Icons.refresh)),
              ],
            ),
            if (energyUsage != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local time: ${energyUsage.localTime ?? '-'}'),
                      Text('Today runtime: ${energyUsage.todayRuntime} min'),
                      Text('Today energy: ${energyUsage.todayEnergy} Wh'),
                      Text('Month runtime: ${energyUsage.monthRuntime} min'),
                      Text('Month energy: ${energyUsage.monthEnergy ?? 0} Wh'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text('Turn on/off', style: Theme.of(context).textTheme.titleLarge),
            SwitchListTile(
              title: const Text('Power'),
              value: deviceInfo?.deviceOn ?? false,
              onChanged: _isLoading ? null : _togglePower,
            ),
            const SizedBox(height: 12),
            Text('Energy data', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            DropdownButton<TapoEnergyDataIntervalType>(
              value: _energyIntervalType,
              items: TapoEnergyDataIntervalType.values
                  .map((type) => DropdownMenuItem(value: type, child: Text(_intervalLabel(type))))
                  .toList(),
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _energyIntervalType = value;
                        final now = DateTime.now();
                        final clamped = _clampEnergyRange(_energyStartDate, _energyEndDate, now);
                        _energyStartDate = clamped.start;
                        _energyEndDate = clamped.end;
                      });
                    },
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _isLoading ? null : _pickStartDate,
                  child: Text('Start: ${_formatDate(_energyStartDate)}'),
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : _pickEndDate,
                  child: Text('End: ${_formatDate(_energyEndDate)}'),
                ),
                OutlinedButton(onPressed: _isLoading ? null : _loadEnergyData, child: const Text('Load energy data')),
              ],
            ),
            const SizedBox(height: 12),
            if (energyData != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_intervalLabel(_energyIntervalType)} energy '
                        '(${_formatDate(_energyStartDate)} → ${_formatDate(_energyEndDate)})',
                      ),
                      const SizedBox(height: 8),
                      for (final point in _filteredEnergyPoints(energyData))
                        Text('${_formatPointLabel(point)}: ${_formatEnergy(point.energyWh)}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
