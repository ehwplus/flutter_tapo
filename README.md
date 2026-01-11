# flutter_tapo

Local Flutter client for TP-Link Tapo devices (tested with P115). P100 should
work as well but is not yet tested. The package implements the device handshake,
encrypted requests, and a minimal device API.

## Known limitations

* Only tested inside the local network.
* Device discovery is not implemented; you need the device IP.
* This is a first iteration focused on smart plugs (P115).

## Features

* Handshake and login for the local Tapo API.
* Fetch device info (model, state, nickname).
* Toggle power state.
* Fetch energy usage for P110/P115 devices.

## Getting started

You need the device IP address and your Tapo account email/password. The API
communicates directly with the device over HTTP.

## Usage

```dart
import 'package:flutter_tapo/flutter_tapo.dart';
import 'custom_tapo_api_client.dart';

final client = CustomTapoApiClient(host: '192.168.1.50');

await client.authenticate(
  email: 'tapo@example.com',
  password: 'secret-password',
);

final info = await client.getDeviceInfo();
await client.setPowerState(true);
final energy = await client.getEnergyUsage();
```

Check the `example` app for a full working flow.

## Additional information

If you find missing features or device types, feel free to open an issue or PR.
