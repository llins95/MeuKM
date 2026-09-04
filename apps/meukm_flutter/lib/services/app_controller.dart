import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle_record.dart';

class AppController extends ChangeNotifier {
  AppController(this._client);

  static const _localKey = 'meukm_native_data_v1';
  static const _table = 'meukm_user_data';

  final SupabaseClient _client;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  StreamSubscription<AuthState>? _authSubscription;

  AppData data = AppData.sample;
  bool loading = true;
  bool syncing = false;
  String syncStatus = 'Entre para sincronizar entre aparelhos.';

  User? get user => _client.auth.currentUser;
  bool get signedIn => user != null;

  Future<void> initialize() async {
    final saved = await _preferences.getString(_localKey);
    if (saved != null) {
      try {
        data = AppData.fromJson(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      } catch (_) {
        data = AppData.sample;
      }
    }
    loading = false;
    notifyListeners();
    _authSubscription = _client.auth.onAuthStateChange.listen((event) {
      notifyListeners();
      if (event.session != null) unawaited(sync());
    });
    if (signedIn) await sync();
  }

  Future<bool> signUp({required String name, required String email, required String password}) async {
    final response = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'name': name.trim()},
    );
    notifyListeners();
    if (response.session != null) await sync();
    return response.session != null;
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
    await sync();
    notifyListeners();
  }

  Future<void> signOut() async {
    await sync();
    await _client.auth.signOut();
    syncStatus = 'Entre para sincronizar entre aparelhos.';
    notifyListeners();
  }

  Future<void> sync() async {
    final currentUser = user;
    if (currentUser == null || syncing) return;
    syncing = true;
    syncStatus = 'Sincronizando…';
    notifyListeners();
    try {
      final rows = await _client
          .from(_table)
          .select('data, updated_at')
          .eq('user_id', currentUser.id)
          .limit(1);

      if (rows.isEmpty) {
        await _push(currentUser.id);
      } else {
        final row = Map<String, dynamic>.from(rows.first);
        final remoteUpdatedAt = DateTime.tryParse('${row['updated_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final localUpdatedAt = DateTime.tryParse('${data.sync['modifiedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final localIsNewer = data.sync['dirty'] == true && !localUpdatedAt.isBefore(remoteUpdatedAt);
        if (localIsNewer) {
          await _push(currentUser.id);
        } else {
          data = AppData.fromJson(Map<String, dynamic>.from(row['data'] as Map));
          await _markSynced(currentUser.id, remoteUpdatedAt);
        }
      }
      syncStatus = 'Sincronizado agora.';
    } catch (_) {
      syncStatus = 'Sem conexão. Os dados continuam salvos neste aparelho.';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> addRecord(VehicleRecord record) async {
    final updatedRecords = [...data.records, record];
    final updatedVehicles = data.vehicles.map((vehicle) {
      if (vehicle.id != record.vehicleId) return vehicle;
      return vehicle.copyWith(
        odometer: record.odometer > vehicle.odometer ? record.odometer : vehicle.odometer,
        records: updatedRecords.where((item) => item.vehicleId == vehicle.id).toList(),
        updatedAt: record.updatedAt,
      );
    }).toList();
    data = data.copyWith(records: updatedRecords, vehicles: updatedVehicles);
    await _markDirty();
    unawaited(sync());
  }

  Future<void> deleteAllData() async {
    final vehicle = emptyVehicle();
    final now = DateTime.now().toUtc();
    data = AppData(
      currentVehicleId: vehicle.id,
      vehicles: [vehicle],
      records: const [],
      settings: {'darkMode': false, 'maintenanceNotifications': true, 'fuelNotifications': true, '_updatedAt': now.toIso8601String()},
      deletedRecords: const [],
      sync: {'dirty': true, 'modifiedAt': now.toIso8601String(), 'resetAt': now.toIso8601String(), 'ownerId': user?.id},
    );
    await _saveLocal();
    await sync();
  }

  Future<void> _push(String userId) async {
    final rows = await _client
        .from(_table)
        .upsert({'user_id': userId, 'data': data.toJson(cloud: true)}, onConflict: 'user_id')
        .select('updated_at');
    final updatedAt = rows.isNotEmpty
        ? DateTime.tryParse('${rows.first['updated_at']}') ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    await _markSynced(userId, updatedAt);
  }

  Future<void> _markDirty() async {
    final sync = Map<String, dynamic>.from(data.sync)
      ..['dirty'] = true
      ..['modifiedAt'] = DateTime.now().toUtc().toIso8601String()
      ..['ownerId'] = user?.id;
    data = data.copyWith(sync: sync);
    await _saveLocal();
    notifyListeners();
  }

  Future<void> _markSynced(String userId, DateTime updatedAt) async {
    final sync = Map<String, dynamic>.from(data.sync)
      ..['dirty'] = false
      ..['ownerId'] = userId
      ..['lastSyncedAt'] = updatedAt.toUtc().toIso8601String();
    data = data.copyWith(sync: sync);
    await _saveLocal();
  }

  Future<void> _saveLocal() => _preferences.setString(_localKey, jsonEncode(data.toJson()));

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
