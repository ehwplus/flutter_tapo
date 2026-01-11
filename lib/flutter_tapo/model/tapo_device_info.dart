class TapoDeviceInfo {
  const TapoDeviceInfo({
    required this.deviceId,
    required this.firmwareVersion,
    required this.hardwareVersion,
    required this.type,
    required this.model,
    required this.mac,
    required this.nickname,
    required this.ip,
    required this.deviceOn,
    required this.onTime,
  });

  factory TapoDeviceInfo.fromJson(Map<String, dynamic> json) {
    return TapoDeviceInfo(
      deviceId: json['device_id']?.toString() ?? '',
      firmwareVersion: json['fw_ver']?.toString() ?? '',
      hardwareVersion: json['hw_ver']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      deviceOn: json['device_on'] == true,
      onTime: json['on_time'] is num ? (json['on_time'] as num).toInt() : 0,
    );
  }

  final String deviceId;
  final String firmwareVersion;
  final String hardwareVersion;
  final String type;
  final String model;
  final String mac;
  final String nickname;
  final String ip;
  final bool deviceOn;
  final int onTime;
}
