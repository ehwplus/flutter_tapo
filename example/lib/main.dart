import 'package:flutter/material.dart';
import 'package:flutter_tapo/flutter_tapo.dart';

import 'custom_tapo_api_client.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
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

  CustomTapoApiClient? _client;
  TapoDeviceInfo? _deviceInfo;
  TapoEnergyUsage? _energyUsage;
  bool _isLoading = false;
  String? _error;

  bool get _isConnected => _client?.isAuthenticated == true;

  @override
  void dispose() {
    _ipController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
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
    });

    Uri? deviceUri;
    try {
      deviceUri = rawInput.contains('://')
          ? Uri.parse(rawInput)
          : Uri.parse('http://$rawInput');
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

    final client = CustomTapoApiClient(
      host: deviceUri.host,
      port: deviceUri.hasPort
          ? deviceUri.port
          : (deviceUri.scheme == 'https' ? 443 : 80),
      useHttps: deviceUri.scheme == 'https',
      allowInsecureHttps: deviceUri.scheme == 'https',
    );

    try {
      await client.authenticate(email: email, password: password);
      final info = await client.getDeviceInfo();
      setState(() {
        _client = client;
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

  @override
  Widget build(BuildContext context) {
    final deviceInfo = _deviceInfo;
    final energyUsage = _energyUsage;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Connection',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Device IP or URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Tapo account email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Tapo account password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isLoading ? null : _connect,
            child: const Text('Connect'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Device',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (!_isConnected)
            Text(
              'Not connected yet.',
              style: Theme.of(context).textTheme.bodySmall,
            )
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
            Row(
              children: [
                FilledButton(
                  onPressed: _isLoading ? null : _refreshDeviceInfo,
                  child: const Text('Refresh device info'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _isLoading ? null : _loadEnergyUsage,
                  child: const Text('Load energy usage'),
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
          ],
        ],
      ),
    );
  }
}
