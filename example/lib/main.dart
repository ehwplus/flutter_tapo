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
  TapoEnergyData? _dailyEnergyData;
  bool _isLoading = false;
  String? _error;

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
      _dailyEnergyData = null;
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

  Future<void> _loadDailyEnergyData() async {
    final client = _client;
    if (client == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final quarterStart = _quarterStart(DateTime.now());
      final interval = TapoEnergyDataInterval.daily(quarterStart: quarterStart);
      final data = await client.getEnergyData(interval);
      setState(() {
        _dailyEnergyData = data;
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

  @override
  Widget build(BuildContext context) {
    final deviceInfo = _deviceInfo;
    final energyUsage = _energyUsage;
    final dailyEnergyData = _dailyEnergyData;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
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
          Text('Device', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
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
            SwitchListTile(
              title: const Text('Power'),
              value: deviceInfo?.deviceOn ?? false,
              onChanged: _isLoading ? null : _togglePower,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _isLoading ? null : _refreshDeviceInfo,
                  child: const Text('Refresh device info'),
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : _loadEnergyUsage,
                  child: const Text('Load energy usage'),
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : _loadDailyEnergyData,
                  child: const Text('Load daily energy data'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (energyUsage != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local time: ${energyUsage.localTime ?? '-'}'),
                      Text('Today runtime: ${energyUsage.todayRuntime ?? 0} min'),
                      Text('Today energy: ${energyUsage.todayEnergy ?? 0} Wh'),
                      Text('Month runtime: ${energyUsage.monthRuntime ?? 0} min'),
                      Text('Month energy: ${energyUsage.monthEnergy ?? 0} Wh'),
                    ],
                  ),
                ),
              ),
            if (dailyEnergyData != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Daily energy (from ${_formatDate(dailyEnergyData.startDate)})'),
                      const SizedBox(height: 8),
                      for (final point in dailyEnergyData.points)
                        Text('${_formatDate(point.start)}: ${_formatEnergy(point.energyWh)}'),
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
