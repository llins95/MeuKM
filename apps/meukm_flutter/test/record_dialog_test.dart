import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meukm/features/shell/meukm_shell.dart';
import 'package:meukm/models/vehicle_record.dart';

void main() {
  testWidgets('calcula litros e aceita o odômetro informado', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    VehicleRecord? savedRecord;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => ElevatedButton(
        onPressed: () async {
          savedRecord = await showDialog<VehicleRecord>(
            context: context,
            builder: (_) => RecordDialog(
              type: VehicleRecordType.fuel,
              vehicle: AppData.sample.currentVehicle,
            ),
          );
        },
        child: const Text('Abrir'),
      )),
    ));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

    await tester.enterText(field('Odômetro (km)'), '5458');
    await tester.enterText(field('Preço por litro'), '6,25');
    await tester.enterText(field('Valor total'), '50');
    await tester.pump();

    final liters = tester.widget<TextField>(field('Litros')).controller!;
    expect(liters.text, '8,000');

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(savedRecord, isNotNull);
    expect(savedRecord!.odometer, 5458);
    expect(savedRecord!.liters, 8);
  });
}
