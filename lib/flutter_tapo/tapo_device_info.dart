import 'tapo_encoding.dart';

class TapoDeviceInfo {
  TapoDeviceInfo({
    required this.deviceId,
    required this.model,
    required this.deviceOn,
    required this.nickname,
    required this.ip,
    required this.mac,
    required this.onTime,
    required this.raw,
  });

  final String? deviceId;
  final String? model;
  final bool? deviceOn;
  final String? nickname;
  final String? ip;
  final String? mac;
  final int? onTime;
  final Map<String, dynamic> raw;

  factory TapoDeviceInfo.fromJson(Map<String, dynamic> json) {
    final decodedNickname = TapoEncoding.decodeBase64String(
      json['nickname']?.toString(),
    );

    return TapoDeviceInfo(
      deviceId: json['device_id']?.toString(),
      model: json['model']?.toString(),
      deviceOn: _asBool(json['device_on']),
      nickname: decodedNickname,
      ip: json['ip']?.toString(),
      mac: json['mac']?.toString(),
      onTime: _asInt(json['on_time']),
      raw: json,
    );
  }

  static bool? _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      if (value.toLowerCase() == 'true') {
        return true;
      }
      if (value.toLowerCase() == 'false') {
        return false;
      }
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed != 0;
      }
    }
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
