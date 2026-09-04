import '../models/vehicle_record.dart';

class VehicleAnalytics {
  const VehicleAnalytics({
    required this.total,
    required this.distance,
    required this.costPerKm,
    required this.consumption,
  });

  final double total;
  final double distance;
  final double costPerKm;
  final double consumption;
}

class FuelPrediction {
  const FuelPrediction({
    required this.odometer,
    required this.remainingKm,
    required this.averageIntervalKm,
    required this.sampleSize,
  });

  final double odometer;
  final double remainingKm;
  final double averageIntervalKm;
  final int sampleSize;
}

class AnalyticsService {
  const AnalyticsService();

  VehicleAnalytics calculate(List<VehicleRecord> records) {
    if (records.isEmpty) {
      return const VehicleAnalytics(total: 0, distance: 0, costPerKm: 0, consumption: 0);
    }
    final sorted = [...records]..sort((a, b) => a.odometer.compareTo(b.odometer));
    final total = records.fold<double>(0, (sum, item) => sum + item.total);
    final distance = sorted.last.odometer - sorted.first.odometer;
    final fullTanks = sorted.where((item) => item.type == VehicleRecordType.fuel && item.fullTank && (item.liters ?? 0) > 0).toList();
    var consumptionDistance = 0.0;
    var consumptionLiters = 0.0;
    for (var index = 1; index < fullTanks.length; index += 1) {
      final interval = fullTanks[index].odometer - fullTanks[index - 1].odometer;
      if (interval > 0) {
        consumptionDistance += interval;
        consumptionLiters += fullTanks[index].liters ?? 0;
      }
    }
    return VehicleAnalytics(
      total: total,
      distance: distance,
      costPerKm: distance > 0 ? total / distance : 0,
      consumption: consumptionLiters > 0 ? consumptionDistance / consumptionLiters : 0,
    );
  }

  FuelPrediction? predict(VehicleData vehicle) {
    final fuel = vehicle.records.where((item) => item.type == VehicleRecordType.fuel && item.fullTank).toList()
      ..sort((a, b) => a.odometer.compareTo(b.odometer));
    if (fuel.length < 2) return null;
    final recent = fuel.length > 6 ? fuel.sublist(fuel.length - 6) : fuel;
    final intervals = <double>[];
    for (var index = 1; index < recent.length; index += 1) {
      final interval = recent[index].odometer - recent[index - 1].odometer;
      if (interval > 0) intervals.add(interval);
    }
    if (intervals.isEmpty) return null;
    final average = intervals.reduce((a, b) => a + b) / intervals.length;
    final target = recent.last.odometer + average;
    return FuelPrediction(
      odometer: target,
      remainingKm: target - vehicle.odometer,
      averageIntervalKm: average,
      sampleSize: intervals.length,
    );
  }
}
