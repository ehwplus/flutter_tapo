enum TapoEnergyDataIntervalType { hourly, daily, monthly, activity }

class TapoEnergyDataInterval {
  const TapoEnergyDataInterval._({
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.interval,
  });

  factory TapoEnergyDataInterval.hourly({required DateTime startDate, required DateTime endDate, int interval = 60}) {
    return _hourlyLike(
      type: TapoEnergyDataIntervalType.hourly,
      startDate: startDate,
      endDate: endDate,
      interval: interval,
    );
  }

  factory TapoEnergyDataInterval.activity({required DateTime startDate, required DateTime endDate, int interval = 60}) {
    return _hourlyLike(
      type: TapoEnergyDataIntervalType.activity,
      startDate: startDate,
      endDate: endDate,
      interval: interval,
    );
  }

  static TapoEnergyDataInterval _hourlyLike({
    required TapoEnergyDataIntervalType type,
    required DateTime startDate,
    required DateTime endDate,
    required int interval,
  }) {
    if (type != TapoEnergyDataIntervalType.hourly && type != TapoEnergyDataIntervalType.activity) {
      throw ArgumentError('Hourly-like intervals must be hourly or activity.');
    }
    final normalizedStart = _startOfDay(startDate);
    final normalizedEnd = _startOfDay(endDate);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError('endDate must be on or after startDate.');
    }
    if (normalizedEnd.difference(normalizedStart).inDays > 8) {
      throw ArgumentError('Hourly interval must not exceed 8 days.');
    }
    return TapoEnergyDataInterval._(
      type: type,
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

  static const int _activityMinPowerW = 2;

  bool get _isHourlyLike =>
      intervalType == TapoEnergyDataIntervalType.hourly || intervalType == TapoEnergyDataIntervalType.activity;

  TapoEnergyDataIntervalType get _normalizedIntervalType =>
      _isHourlyLike ? TapoEnergyDataIntervalType.hourly : intervalType;

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

  TapoEnergyData trimToValidWindow({DateTime? now}) {
    final effectiveNow = now ?? localDateTime ?? DateTime.now();
    final trimmed = trimToNow(now: effectiveNow);
    if (trimmed.values.isEmpty) {
      return trimmed;
    }

    final windowStart = trimmed._windowStart(effectiveNow);
    final drop = trimmed._pointsBefore(windowStart);
    if (drop <= 0) {
      return trimmed;
    }

    final newStart = drop >= trimmed.values.length
        ? trimmed._alignToInterval(windowStart)
        : trimmed._pointStartForIndex(drop);
    final newValues = drop >= trimmed.values.length ? const <int>[] : trimmed.values.sublist(drop);
    final newEnd = newValues.isEmpty ? null : trimmed._pointStartForIndex(drop + newValues.length - 1);

    return TapoEnergyData(
      intervalType: trimmed.intervalType,
      startDate: newStart,
      values: newValues,
      interval: trimmed.interval,
      startTimestamp: trimmed.startTimestamp == null ? null : _toUnixSeconds(newStart),
      endTimestamp: trimmed.endTimestamp == null || newEnd == null ? null : _toUnixSeconds(newEnd),
      localTime: trimmed.localTime,
    );
  }

  List<TapoEnergyDataPoint> get points {
    return List<TapoEnergyDataPoint>.generate(values.length, (index) {
      return TapoEnergyDataPoint(start: _pointStartForIndex(index), energyWh: values[index]);
    });
  }

  List<TapoEnergyActivity> activities({Duration? maxDuration, Duration? minGap}) {
    if (!_isHourlyLike || values.isEmpty) {
      return const [];
    }

    final activities = <TapoEnergyActivity>[];
    int? currentStartIndex;
    final minEnergyWh = _activityMinEnergyWh();
    final effectiveMaxDuration = _resolveMaxDuration(maxDuration);
    final maxPoints = effectiveMaxDuration == null ? null : _maxPoints(effectiveMaxDuration);
    final minGapPoints = _resolveMinGapPoints(minGap);
    var gapCount = minGapPoints;
    var sawGap = false;

    for (var index = 0; index < values.length; index += 1) {
      final hasEnergy = values[index].toDouble() >= minEnergyWh;
      if (currentStartIndex != null) {
        if (!hasEnergy) {
          activities.add(_buildActivity(currentStartIndex, index));
          currentStartIndex = null;
          gapCount = 1;
          if (gapCount >= minGapPoints) {
            sawGap = true;
          }
          continue;
        }

        if (maxPoints != null) {
          final length = index - currentStartIndex + 1;
          if (length >= maxPoints) {
            activities.add(_buildActivity(currentStartIndex, index + 1));
            currentStartIndex = null;
            gapCount = 0;
            continue;
          }
        }
        continue;
      }

      if (hasEnergy) {
        if (gapCount >= minGapPoints) {
          currentStartIndex = index;
        }
        continue;
      }

      if (gapCount < minGapPoints) {
        gapCount += 1;
        if (gapCount >= minGapPoints) {
          sawGap = true;
        }
      } else {
        sawGap = true;
      }
    }

    if (currentStartIndex != null) {
      activities.add(_buildActivity(currentStartIndex, values.length));
    }

    if (intervalType == TapoEnergyDataIntervalType.activity && !sawGap) {
      return const [];
    }

    return activities;
  }

  TapoEnergyActivity _buildActivity(int startIndex, int endExclusiveIndex) {
    final start = _pointStartForIndex(startIndex);
    final durationHours = endExclusiveIndex - startIndex;
    final end = start.add(Duration(hours: durationHours));
    final energyWh = _sumEnergy(startIndex, endExclusiveIndex);
    return TapoEnergyActivity(start: start, end: end, energyWh: energyWh);
  }

  double _activityMinEnergyWh() {
    final intervalMinutes = interval ?? 60;
    return _activityMinPowerW * (intervalMinutes / 60);
  }

  Duration? _resolveMaxDuration(Duration? maxDuration) {
    if (!_isHourlyLike) {
      return null;
    }
    final resolved =
        maxDuration ?? (intervalType == TapoEnergyDataIntervalType.activity ? const Duration(hours: 12) : null);
    if (resolved != null && resolved > const Duration(hours: 24)) {
      throw ArgumentError('maxDuration must not exceed 24 hours.');
    }
    return resolved;
  }

  int _maxPoints(Duration maxDuration) {
    final intervalMinutes = interval ?? 60;
    final points = maxDuration.inMinutes ~/ intervalMinutes;
    if (points < 1) {
      throw ArgumentError('maxDuration must be at least one interval.');
    }
    return points;
  }

  int _resolveMinGapPoints(Duration? minGap) {
    if (!_isHourlyLike) {
      return 0;
    }
    final resolved = minGap ?? (intervalType == TapoEnergyDataIntervalType.activity ? _intervalDuration() : null);
    if (resolved == null) {
      return 0;
    }
    final intervalMinutes = interval ?? 60;
    final points = (resolved.inMinutes / intervalMinutes).ceil();
    if (points < 1) {
      throw ArgumentError('minGap must be at least one interval.');
    }
    return points;
  }

  Duration _intervalDuration() {
    return Duration(minutes: interval ?? 60);
  }

  int _sumEnergy(int startIndex, int endExclusiveIndex) {
    var sum = 0;
    for (var index = startIndex; index < endExclusiveIndex; index += 1) {
      sum += values[index];
    }
    return sum;
  }

  int _pointsThrough(DateTime now) {
    final start = startDate;
    final diff = switch (_normalizedIntervalType) {
      TapoEnergyDataIntervalType.activity => DateTime(now.year, now.month, now.day, now.hour).difference(start).inHours,
      TapoEnergyDataIntervalType.hourly => DateTime(now.year, now.month, now.day, now.hour).difference(start).inHours,
      TapoEnergyDataIntervalType.daily => DateTime(now.year, now.month, now.day).difference(start).inDays,
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

  static int _toUnixSeconds(DateTime date) {
    return date.millisecondsSinceEpoch ~/ 1000;
  }

  DateTime _pointStartForIndex(int index) {
    return switch (_normalizedIntervalType) {
      TapoEnergyDataIntervalType.activity => startDate.add(Duration(hours: index)),
      TapoEnergyDataIntervalType.hourly => startDate.add(Duration(hours: index)),
      TapoEnergyDataIntervalType.daily => DateTime(startDate.year, startDate.month, startDate.day + index),
      TapoEnergyDataIntervalType.monthly => DateTime(startDate.year, startDate.month + index, 1),
    };
  }

  DateTime _windowStart(DateTime now) {
    return switch (_normalizedIntervalType) {
      TapoEnergyDataIntervalType.activity => now.subtract(const Duration(days: 7)),
      TapoEnergyDataIntervalType.hourly => now.subtract(const Duration(days: 7)),
      TapoEnergyDataIntervalType.daily => _addMonths(DateTime(now.year, now.month, now.day), -3),
      TapoEnergyDataIntervalType.monthly => _addMonths(DateTime(now.year, now.month, now.day), -12),
    };
  }

  DateTime _alignToInterval(DateTime date) {
    return switch (_normalizedIntervalType) {
      TapoEnergyDataIntervalType.activity => DateTime(date.year, date.month, date.day, date.hour),
      TapoEnergyDataIntervalType.hourly => DateTime(date.year, date.month, date.day, date.hour),
      TapoEnergyDataIntervalType.daily => DateTime(date.year, date.month, date.day),
      TapoEnergyDataIntervalType.monthly => DateTime(date.year, date.month, 1),
    };
  }

  int _pointsBefore(DateTime boundary) {
    for (var index = 0; index < values.length; index += 1) {
      if (!_pointStartForIndex(index).isBefore(boundary)) {
        return index;
      }
    }
    return values.length;
  }

  static DateTime _addMonths(DateTime date, int months) {
    return DateTime(date.year, date.month + months, date.day);
  }
}

class TapoEnergyDataPoint {
  const TapoEnergyDataPoint({required this.start, required this.energyWh});

  final DateTime start;
  final int energyWh;
}

class TapoEnergyActivity {
  const TapoEnergyActivity({required this.start, required this.end, required this.energyWh});

  final DateTime start;
  final DateTime end;
  final int energyWh;
}
