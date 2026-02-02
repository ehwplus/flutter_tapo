enum TapoEnergyDataIntervalType { hourly, daily, monthly }

class TapoEnergyDataInterval {
  const TapoEnergyDataInterval._({
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.interval,
  });

  factory TapoEnergyDataInterval.hourly({required DateTime startDate, required DateTime endDate, int interval = 60}) {
    final normalizedStart = _startOfDay(startDate);
    final normalizedEnd = _startOfDay(endDate);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError('endDate must be on or after startDate.');
    }
    if (normalizedEnd.difference(normalizedStart).inDays > 8) {
      throw ArgumentError('Hourly interval must not exceed 8 days.');
    }
    return TapoEnergyDataInterval._(
      type: TapoEnergyDataIntervalType.hourly,
      startDate: normalizedStart,
      endDate: _endOfDay(endDate),
      interval: interval,
    );
  }

  factory TapoEnergyDataInterval.daily({required DateTime quarterStart, int interval = 1440}) {
    final normalizedStart = _startOfDay(quarterStart);
    final isQuarterStart =
        normalizedStart.day == 1 &&
        (normalizedStart.month == 1 ||
            normalizedStart.month == 4 ||
            normalizedStart.month == 7 ||
            normalizedStart.month == 10);
    if (!isQuarterStart) {
      throw ArgumentError('quarterStart must be the first day of a quarter.');
    }
    return TapoEnergyDataInterval._(
      type: TapoEnergyDataIntervalType.daily,
      startDate: normalizedStart,
      endDate: _endOfDay(_addMonths(normalizedStart, 3).subtract(const Duration(days: 1))),
      interval: interval,
    );
  }

  factory TapoEnergyDataInterval.monthly({required DateTime yearStart, int interval = 43200}) {
    final normalizedStart = _startOfDay(yearStart);
    if (normalizedStart.month != 1 || normalizedStart.day != 1) {
      throw ArgumentError('yearStart must be January 1st.');
    }
    return TapoEnergyDataInterval._(
      type: TapoEnergyDataIntervalType.monthly,
      startDate: normalizedStart,
      endDate: _endOfDay(DateTime(normalizedStart.year, 12, 31)),
      interval: interval,
    );
  }

  final TapoEnergyDataIntervalType type;
  final DateTime startDate;
  final DateTime endDate;
  final int interval;

  Map<String, dynamic> toParams() {
    return {
      'start_timestamp': _toUnixSeconds(startDate),
      'end_timestamp': _toUnixSeconds(endDate),
      'interval': interval,
    };
  }

  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  static int _toUnixSeconds(DateTime date) {
    return date.millisecondsSinceEpoch ~/ 1000;
  }

  static DateTime _addMonths(DateTime date, int months) {
    return DateTime(date.year, date.month + months, date.day);
  }
}

class TapoEnergyData {
  const TapoEnergyData({
    required this.intervalType,
    required this.startDate,
    required this.values,
    this.interval,
    this.startTimestamp,
    this.endTimestamp,
    this.localTime,
  });

  factory TapoEnergyData.fromJson(Map<String, dynamic> json, {required TapoEnergyDataInterval interval}) {
    final rawValues = json['data'] ?? json['energy_data'] ?? json['data_list'];
    return TapoEnergyData(
      intervalType: interval.type,
      startDate: interval.startDate,
      values: _parseValues(rawValues),
      interval: _parseInt(json['interval']),
      startTimestamp: _parseInt(json['start_timestamp']),
      endTimestamp: _parseInt(json['end_timestamp']),
      localTime: json['local_time']?.toString(),
    );
  }

  final TapoEnergyDataIntervalType intervalType;
  final DateTime startDate;
  final List<int> values;
  final int? interval;
  final int? startTimestamp;
  final int? endTimestamp;
  final String? localTime;

  DateTime? get localDateTime {
    final value = localTime;
    if (value == null) {
      return null;
    }
    final normalized = value.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }

  TapoEnergyData trimToNow({DateTime? now}) {
    final effectiveNow = now ?? localDateTime ?? DateTime.now();
    final count = _pointsThrough(effectiveNow);
    if (count >= values.length) {
      return this;
    }
    return TapoEnergyData(
      intervalType: intervalType,
      startDate: startDate,
      values: values.take(count).toList(),
      interval: interval,
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
      localTime: localTime,
    );
  }

  List<TapoEnergyDataPoint> get points {
    return List<TapoEnergyDataPoint>.generate(values.length, (index) {
      final pointStart = switch (intervalType) {
        TapoEnergyDataIntervalType.hourly => startDate.add(Duration(hours: index)),
        TapoEnergyDataIntervalType.daily => DateTime(startDate.year, startDate.month, startDate.day + index),
        TapoEnergyDataIntervalType.monthly => DateTime(startDate.year, startDate.month + index, 1),
      };
      return TapoEnergyDataPoint(start: pointStart, energyWh: values[index]);
    });
  }

  int _pointsThrough(DateTime now) {
    final start = startDate;
    final diff = switch (intervalType) {
      TapoEnergyDataIntervalType.hourly => DateTime(now.year, now.month, now.day, now.hour)
          .difference(start)
          .inHours,
      TapoEnergyDataIntervalType.daily =>
        DateTime(now.year, now.month, now.day).difference(start).inDays,
      TapoEnergyDataIntervalType.monthly =>
        (DateTime(now.year, now.month, 1).year - start.year) * 12 +
            (DateTime(now.year, now.month, 1).month - start.month),
    };

    if (diff < 0) {
      return 0;
    }
    final count = diff + 1;
    return count > values.length ? values.length : count;
  }

  static List<int> _parseValues(dynamic rawValues) {
    if (rawValues is! List) {
      return const [];
    }
    return rawValues.map((value) => value is num ? value.toInt() : int.tryParse(value.toString()) ?? 0).toList();
  }

  static int? _parseInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class TapoEnergyDataPoint {
  const TapoEnergyDataPoint({required this.start, required this.energyWh});

  final DateTime start;
  final int energyWh;
}
