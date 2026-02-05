# flutter_tapo

Local Flutter client for TP-Link Tapo devices (tested with P115). P100 should
work as well but is not yet tested. The package implements the device handshake,
encrypted requests, and a minimal device API.

## Known limitations

* Only tested inside the local network.
* Device discovery is limited to local subnet probing; it may miss devices if they do not respond to component negotiation.
* This is a first iteration focused on smart plugs (P115).

## Features

* Handshake and login for the local Tapo API.
* Fetch device info (model, state, nickname).
* Toggle power state.
* Fetch energy usage for P110/P115 devices.
* Fetch energy data series (hourly/daily/monthly) with client-side trimming.
* Discover local Tapo devices on a subnet.
* Derive device activity windows from hourly energy data.

## Getting started

You need the device IP address and your Tapo account email/password. The API
communicates directly with the device over HTTP.

## Platform setup (iOS)

Because the library talks to local devices over HTTP, the platform needs
explicit permissions:

### iOS

- Allow local networking in `Info.plist`:
  - `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`
- If you use device discovery or access local IPs, add:
  - `NSLocalNetworkUsageDescription` (user-visible reason string)

### macOS (not working right now)

- Enable outbound network access in entitlements:
    - `com.apple.security.network.client = true` (Debug & Release)
    - Flutter uses `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`
- Allow local networking in `Info.plist`:
    - `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`
- If you use device discovery or access local IPs, also add:
    - `NSLocalNetworkUsageDescription` (user-visible reason string)

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

### Energy data series

```dart
final interval = TapoEnergyDataInterval.daily(
  quarterStart: DateTime(2025, 1, 1),
);
final data = await client.getEnergyData(interval);
for (final point in data.points) {
  print('${point.start}: ${point.energyWh} Wh');
}
```

### Activity intervals (washer/dryer detection)

When you request hourly energy data, you can derive activity windows by grouping
consecutive hours with meaningful usage. Hours below 2W are ignored so standby
power does not create false activities. By default, activities are capped at 12h
and can be configured up to a maximum of 24h.

```dart
final interval = TapoEnergyDataInterval.activity(
  startDate: DateTime(2025, 1, 1),
  endDate: DateTime(2025, 1, 2),
);
final data = await client.getEnergyData(interval);

for (final activity in data.activities()) {
  print('${activity.start} → ${activity.end}');
}
```

### Device discovery

```dart
await for (final event in TapoDeviceDiscovery.scanSubnet(base: '192.168.178')) {
  if (event is TapoSubnetDeviceCountEvent) {
    print('Found ${event.devicesFound} devices (${event.scanned}/${event.total})');
  } else if (event is TapoSubnetTapoCandidatesEvent) {
    print('Tapo candidates so far: ${event.candidates}');
  } else if (event is TapoSubnetScanCompleteEvent) {
    print('Final Tapo devices: ${event.devices}');
  }
}
```

Check the `example` app for a full working flow.

## Additional information

If you find missing features or device types, feel free to open an issue or PR.
