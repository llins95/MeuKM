enum VehicleRecordType { fuel, maintenance, expense }

double _number(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

DateTime _date(Object? value) => DateTime.tryParse('$value') ?? DateTime.now();

class VehicleRecord {
  const VehicleRecord({
    required this.id,
    required this.vehicleId,
    required this.type,
    required this.date,
    required this.odometer,
    required this.total,
    required this.label,
    required this.updatedAt,
    this.liters,
    this.pricePerLiter,
    this.fullTank = false,
    this.place = '',
    this.notes = '',
    this.nextOdometer,
    this.nextDate,
    this.paymentMethod,
  });

  final String id;
  final String vehicleId;
  final VehicleRecordType type;
  final DateTime date;
  final double odometer;
  final double total;
  final String label;
  final DateTime updatedAt;
  final double? liters;
  final double? pricePerLiter;
  final bool fullTank;
  final String place;
  final String notes;
  final double? nextOdometer;
  final DateTime? nextDate;
  final String? paymentMethod;

  factory VehicleRecord.fromJson(Map<String, dynamic> json) {
    final typeName = '${json['type']}';
    return VehicleRecord(
      id: '${json['id']}',
      vehicleId: '${json['vehicleId']}',
      type: VehicleRecordType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => VehicleRecordType.expense,
      ),
      date: _date(json['date']),
      odometer: _number(json['odometer']),
      total: _number(json['total']),
      label: '${json['category'] ?? json['label'] ?? 'Registro'}',
      updatedAt: _date(json['_updatedAt']),
      liters: json['liters'] == null ? null : _number(json['liters']),
      pricePerLiter: json['pricePerLiter'] == null ? null : _number(json['pricePerLiter']),
      fullTank: json['fullTank'] == true,
      place: '${json['place'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      nextOdometer: json['nextOdometer'] == null ? null : _number(json['nextOdometer']),
      nextDate: json['nextDate'] == null ? null : _date(json['nextDate']),
      paymentMethod: json['paymentMethod']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'type': type.name,
    'date': date.toIso8601String().substring(0, 10),
    'odometer': odometer,
    'total': total,
    'category': label,
    'place': place,
    'notes': notes,
    'fullTank': fullTank,
    '_updatedAt': updatedAt.toUtc().toIso8601String(),
    if (liters != null) 'liters': liters,
    if (pricePerLiter != null) 'pricePerLiter': pricePerLiter,
    if (nextOdometer != null) 'nextOdometer': nextOdometer,
    if (nextDate != null) 'nextDate': nextDate!.toIso8601String().substring(0, 10),
    if (paymentMethod != null) 'paymentMethod': paymentMethod,
  };
}

class VehicleData {
  const VehicleData({
    required this.id,
    required this.name,
    required this.plate,
    required this.odometer,
    required this.updatedAt,
    this.records = const [],
  });

  final String id;
  final String name;
  final String plate;
  final double odometer;
  final DateTime updatedAt;
  final List<VehicleRecord> records;

  factory VehicleData.fromJson(Map<String, dynamic> json, List<VehicleRecord> records) => VehicleData(
    id: '${json['id']}',
    name: '${json['name'] ?? 'Meu veículo'}',
    plate: '${json['plate'] ?? 'SEM PLACA'}',
    odometer: _number(json['odometer']),
    updatedAt: _date(json['_updatedAt']),
    records: records.where((record) => record.vehicleId == '${json['id']}').toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'plate': plate,
    'odometer': odometer,
    '_updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  VehicleData copyWith({double? odometer, List<VehicleRecord>? records, DateTime? updatedAt}) => VehicleData(
    id: id,
    name: name,
    plate: plate,
    odometer: odometer ?? this.odometer,
    records: records ?? this.records,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class AppData {
  const AppData({
    required this.currentVehicleId,
    required this.vehicles,
    required this.records,
    required this.settings,
    required this.deletedRecords,
    required this.sync,
  });

  final String currentVehicleId;
  final List<VehicleData> vehicles;
  final List<VehicleRecord> records;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> deletedRecords;
  final Map<String, dynamic> sync;

  VehicleData get currentVehicle {
    final selected = vehicles.where((vehicle) => vehicle.id == currentVehicleId);
    return selected.isNotEmpty ? selected.first : vehicles.first;
  }

  factory AppData.fromJson(Map<String, dynamic> json) {
    final records = (json['records'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => VehicleRecord.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    var vehicles = (json['vehicles'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => VehicleData.fromJson(Map<String, dynamic>.from(item), records))
        .toList();
    if (vehicles.isEmpty) vehicles = [emptyVehicle()];
    final currentId = '${json['currentVehicleId'] ?? vehicles.first.id}';
    return AppData(
      currentVehicleId: vehicles.any((vehicle) => vehicle.id == currentId) ? currentId : vehicles.first.id,
      vehicles: vehicles,
      records: records,
      settings: Map<String, dynamic>.from(json['settings'] as Map? ?? const {}),
      deletedRecords: (json['deletedRecords'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      sync: Map<String, dynamic>.from(json['sync'] as Map? ?? const {}),
    );
  }

  Map<String, dynamic> toJson({bool cloud = false}) {
    final syncData = Map<String, dynamic>.from(sync);
    if (cloud) {
      syncData.remove('dirty');
      syncData.remove('lastSyncedAt');
    }
    return {
      'currentVehicleId': currentVehicleId,
      'vehicles': vehicles.map((item) => item.toJson()).toList(),
      'records': records.map((item) => item.toJson()).toList(),
      'settings': settings,
      'deletedRecords': deletedRecords,
      'sync': syncData,
    };
  }

  AppData copyWith({
    String? currentVehicleId,
    List<VehicleData>? vehicles,
    List<VehicleRecord>? records,
    Map<String, dynamic>? settings,
    List<Map<String, dynamic>>? deletedRecords,
    Map<String, dynamic>? sync,
  }) => AppData(
    currentVehicleId: currentVehicleId ?? this.currentVehicleId,
    vehicles: vehicles ?? this.vehicles,
    records: records ?? this.records,
    settings: settings ?? this.settings,
    deletedRecords: deletedRecords ?? this.deletedRecords,
    sync: sync ?? this.sync,
  );

  static AppData get sample => AppData.fromJson({
    'currentVehicleId': 'vehicle-1',
    'vehicles': [
      {'id': 'vehicle-1', 'name': 'Shineray JEF 150', 'plate': 'SEM PLACA', 'odometer': 7044, '_updatedAt': '2026-08-31T12:00:00.000Z'},
    ],
    'records': [
      {'id': 'r1', 'vehicleId': 'vehicle-1', 'type': 'fuel', 'date': '2026-08-14', 'odometer': 6307, 'total': 50, 'liters': 8.2, 'pricePerLiter': 6.098, 'category': 'Gasolina comum', 'place': 'Posto Central', 'fullTank': true, '_updatedAt': '2026-08-14T12:00:00.000Z'},
      {'id': 'r2', 'vehicleId': 'vehicle-1', 'type': 'fuel', 'date': '2026-08-21', 'odometer': 6454, 'total': 50, 'liters': 8.08, 'category': 'Gasolina comum', 'fullTank': true, '_updatedAt': '2026-08-21T12:00:00.000Z'},
      {'id': 'r3', 'vehicleId': 'vehicle-1', 'type': 'maintenance', 'date': '2026-08-21', 'odometer': 6454, 'total': 0, 'category': 'Calibragem', '_updatedAt': '2026-08-21T12:00:00.000Z'},
      {'id': 'r4', 'vehicleId': 'vehicle-1', 'type': 'fuel', 'date': '2026-08-26', 'odometer': 6626, 'total': 50, 'liters': 8.01, 'category': 'Gasolina comum', 'fullTank': true, '_updatedAt': '2026-08-26T12:00:00.000Z'},
      {'id': 'r5', 'vehicleId': 'vehicle-1', 'type': 'fuel', 'date': '2026-08-31', 'odometer': 6845, 'total': 50, 'liters': 8.03, 'category': 'Gasolina comum', 'fullTank': true, '_updatedAt': '2026-08-31T12:00:00.000Z'},
      {'id': 'r6', 'vehicleId': 'vehicle-1', 'type': 'expense', 'date': '2026-08-08', 'odometer': 6210, 'total': 145.8, 'category': 'Licenciamento', '_updatedAt': '2026-08-08T12:00:00.000Z'},
    ],
    'settings': {'darkMode': false, 'maintenanceNotifications': true, 'fuelNotifications': true, '_updatedAt': '2026-08-31T12:00:00.000Z'},
    'deletedRecords': <Map<String, dynamic>>[],
    'sync': {'dirty': false, 'modifiedAt': '2026-08-31T12:00:00.000Z'},
  });
}

VehicleData emptyVehicle() {
  final now = DateTime.now().toUtc();
  return VehicleData(
    id: 'vehicle-${now.microsecondsSinceEpoch}',
    name: 'Meu veículo',
    plate: 'SEM PLACA',
    odometer: 0,
    updatedAt: now,
  );
}
