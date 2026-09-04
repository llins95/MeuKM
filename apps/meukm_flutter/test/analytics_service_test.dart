import 'package:flutter_test/flutter_test.dart';
import 'package:meukm/models/vehicle_record.dart';
import 'package:meukm/services/analytics_service.dart';

void main() {
  test('calcula consumo com abastecimentos completos', () {
    const service = AnalyticsService();
    final result = service.calculate(AppData.sample.currentVehicle.records);
    expect(result.consumption, greaterThan(20));
    expect(result.distance, greaterThan(0));
  });

  test('prevê o próximo odômetro de abastecimento', () {
    const service = AnalyticsService();
    final prediction = service.predict(AppData.sample.currentVehicle);
    expect(prediction, isNotNull);
    expect(prediction!.odometer, greaterThan(6845));
  });
}
