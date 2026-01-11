class TapoEnergyUsage {
  TapoEnergyUsage({
    required this.localTime,
    required this.todayRuntime,
    required this.todayEnergy,
    required this.monthRuntime,
    required this.monthEnergy,
    required this.raw,
  });

  final DateTime? localTime;
  final int? todayRuntime;
  final int? todayEnergy;
  final int? monthRuntime;
  final int? monthEnergy;
  final Map<String, dynamic> raw;

  factory TapoEnergyUsage.fromJson(Map<String, dynamic> json) {
    final localTimeRaw = json['local_time']?.toString();
    DateTime? localTime;
    if (localTimeRaw != null && localTimeRaw.isNotEmpty) {
      final normalized = localTimeRaw.contains('T')
          ? localTimeRaw
          : localTimeRaw.replaceFirst(' ', 'T');
      localTime = DateTime.tryParse(normalized);
    }

    return TapoEnergyUsage(
      localTime: localTime,
      todayRuntime: _asInt(json['today_runtime']),
      todayEnergy: _asInt(json['today_energy']),
      monthRuntime: _asInt(json['month_runtime']),
      monthEnergy: _asInt(json['month_energy']),
      raw: json,
    );
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
