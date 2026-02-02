import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tapo/flutter_tapo.dart';

void main() {
  test('builds daily energy points from start date', () {
    final interval = TapoEnergyDataInterval.daily(quarterStart: DateTime(2025, 1, 1));
    final data = TapoEnergyData.fromJson(
      {'data': [10, 20, 30]},
      interval: interval,
    );

    expect(data.points.length, 3);
    expect(data.points[0].start, DateTime(2025, 1, 1));
    expect(data.points[1].start, DateTime(2025, 1, 2));
    expect(data.points[2].energyWh, 30);
  });

  test('rejects invalid daily start date', () {
    expect(
      () => TapoEnergyDataInterval.daily(quarterStart: DateTime(2025, 2, 1)),
      throwsArgumentError,
    );
  });

  test('rejects hourly intervals longer than 8 days', () {
    expect(
      () => TapoEnergyDataInterval.hourly(
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 10),
      ),
      throwsArgumentError,
    );
  });

  test('trims future daily points', () {
    final interval = TapoEnergyDataInterval.daily(quarterStart: DateTime(2025, 1, 1));
    final data = TapoEnergyData.fromJson(
      {'data': [1, 2, 3, 4, 5]},
      interval: interval,
    );

    final trimmed = data.trimToNow(now: DateTime(2025, 1, 3, 12));
    expect(trimmed.values.length, 3);
    expect(trimmed.values.last, 3);
  });

  test('trims old daily points outside the valid window', () {
    final interval = TapoEnergyDataInterval.daily(quarterStart: DateTime(2025, 1, 1));
    final data = TapoEnergyData.fromJson(
      {'data': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]},
      interval: interval,
    );

    final trimmed = data.trimToValidWindow(now: DateTime(2025, 4, 5, 10));
    expect(trimmed.values.length, 6);
    expect(trimmed.startDate, DateTime(2025, 1, 5));
    expect(trimmed.values.first, 5);
  });

  test('builds activities from hourly data', () {
    final interval = TapoEnergyDataInterval.hourly(
      startDate: DateTime(2025, 1, 1),
      endDate: DateTime(2025, 1, 1, 6),
    );
    final data = TapoEnergyData.fromJson(
      {'data': [0, 3, 2, 0, 4, 4, 0]},
      interval: interval,
    );

    final activities = data.activities;
    expect(activities.length, 2);
    expect(activities[0].start, DateTime(2025, 1, 1, 1));
    expect(activities[0].end, DateTime(2025, 1, 1, 3));
    expect(activities[1].start, DateTime(2025, 1, 1, 4));
    expect(activities[1].end, DateTime(2025, 1, 1, 6));
  });

  test('activity interval is hourly-like', () {
    final interval = TapoEnergyDataInterval.activity(
      startDate: DateTime(2025, 1, 1),
      endDate: DateTime(2025, 1, 1, 2),
    );
    final data = TapoEnergyData.fromJson(
      {'data': [5, 0, 5]},
      interval: interval,
    );

    expect(data.activities.length, 2);
    expect(data.activities.first.start, DateTime(2025, 1, 1, 0));
  });

  test('ignores activity below 2W threshold', () {
    final interval = TapoEnergyDataInterval.activity(
      startDate: DateTime(2025, 1, 1),
      endDate: DateTime(2025, 1, 1, 2),
    );
    final data = TapoEnergyData.fromJson(
      {'data': [1, 2, 0]},
      interval: interval,
    );

    final activities = data.activities;
    expect(activities.length, 1);
    expect(activities.first.start, DateTime(2025, 1, 1, 1));
    expect(activities.first.end, DateTime(2025, 1, 1, 2));
  });
}
