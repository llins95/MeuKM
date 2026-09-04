import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vehicle_record.dart';
import 'analytics_service.dart';

class ReportExporter {
  const ReportExporter();

  Future<Uint8List> buildPdf(VehicleData vehicle, VehicleAnalytics analytics) async {
    final document = pw.Document();
    final categoryTotals = VehicleRecordType.values.map((type) {
      return vehicle.records.where((item) => item.type == type).fold<double>(0, (sum, item) => sum + item.total);
    }).toList();
    final maxCategory = categoryTotals.fold<double>(1, (maximum, value) => value > maximum ? value : maximum);
    final labels = ['Combustível', 'Manutenção', 'Outras despesas'];
    final colors = [PdfColors.orange700, PdfColors.green700, PdfColors.red700];

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.all(18),
        color: PdfColor.fromHex('#081F3A'),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('MeuKM', style: pw.TextStyle(color: PdfColors.white, fontSize: 26, fontWeight: pw.FontWeight.bold)),
          pw.Text('${vehicle.name} • ${vehicle.plate}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
        ]),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ),
      build: (_) => [
        pw.SizedBox(height: 22),
        pw.Text('Relatório do veículo', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Wrap(spacing: 10, runSpacing: 10, children: [
          _metric('Total gasto', money(analytics.total)),
          _metric('Distância', '${analytics.distance.round()} km'),
          _metric('Custo por km', money(analytics.costPerKm)),
          _metric('Consumo médio', '${decimal(analytics.consumption)} km/L'),
        ]),
        pw.SizedBox(height: 26),
        pw.Text('Gastos por categoria', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 14),
        ...List.generate(categoryTotals.length, (index) {
          final value = categoryTotals[index];
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(labels[index]),
                pw.Text(money(value), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ]),
              pw.SizedBox(height: 5),
              pw.Container(
                height: 13,
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                alignment: pw.Alignment.centerLeft,
                child: pw.Container(
                  width: 480 * (value <= 0 ? 0.01 : value / maxCategory),
                  color: colors[index],
                ),
              ),
            ]),
          );
        }),
        pw.SizedBox(height: 20),
        pw.Text('Últimos registros', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: const ['Data', 'Tipo', 'Odômetro', 'Valor'],
          data: ([...vehicle.records]..sort((a, b) => b.date.compareTo(a.date))).take(12).map((record) => [
            dateText(record.date),
            record.label,
            '${record.odometer.round()} km',
            money(record.total),
          ]).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#0759D6')),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(7),
        ),
      ],
    ));
    return document.save();
  }

  Future<void> exportPdf(VehicleData vehicle, VehicleAnalytics analytics) async {
    final bytes = await buildPdf(vehicle, analytics);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
      fileNameOverrides: ['meukm-relatorio.pdf'],
      title: 'Relatório MeuKM',
    ));
  }

  Future<void> exportPng(VehicleData vehicle, VehicleAnalytics analytics) async {
    final pdf = await buildPdf(vehicle, analytics);
    Uint8List? png;
    await for (final page in Printing.raster(pdf, pages: const [0], dpi: 144)) {
      png = await page.toPng();
      break;
    }
    if (png == null) throw StateError('Não foi possível gerar a imagem.');
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: ['meukm-relatorio.png'],
      title: 'Relatório MeuKM',
    ));
  }

  pw.Widget _metric(String label, String value) => pw.Container(
    width: 238,
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(8)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 6),
      pw.Text(value, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
    ]),
  );
}

String money(double value) => 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
String decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
String dateText(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
