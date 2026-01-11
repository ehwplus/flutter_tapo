class TapoEnergyUsage {
  const TapoEnergyUsage({
    required this.todayRuntime,
    required this.todayEnergy,
    required this.monthRuntime,
    required this.monthEnergy,
    required this.localTime,
  });

  factory TapoEnergyUsage.fromJson(Map<String, dynamic> json) {
    return TapoEnergyUsage(
      todayRuntime: json['today_runtime'] is num
          ? (json['today_runtime'] as num).toInt()
          : 0,
      todayEnergy: json['today_energy'] is num
          ? (json['today_energy'] as num).toInt()
          : 0,
      monthRuntime: json['month_runtime'] is num
          ? (json['month_runtime'] as num).toInt()
          : 0,
      monthEnergy: json['month_energy'] is num
          ? (json['month_energy'] as num).toInt()
          : 0,
      localTime: json['local_time']?.toString(),
    );
  }

  final int todayRuntime;
  final int todayEnergy;
  final int monthRuntime;
  final int monthEnergy;
  final String? localTime;
}
