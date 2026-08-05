import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class PatrolProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _attendances = [];
  Map<String, dynamic>? _posQrData;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get schedules => _schedules;
  List<Map<String, dynamic>> get attendances => _attendances;
  Map<String, dynamic>? get posQrData => _posQrData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchSchedules() async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.get(ApiConstants.patrolSchedules);
    _isLoading = false;
    if (response['success'] == true) {
      _schedules = List<Map<String, dynamic>>.from(response['data'] ?? []);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> createSchedule({
    required String hari,
    String? tanggal,
    required String shift,
    required String petugasWarga,
    String? keterangan,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.patrolSchedules,
      body: {
        'hari': hari,
        if (tanggal != null) 'tanggal': tanggal,
        'shift': shift,
        'petugas_warga': petugasWarga,
        if (keterangan != null) 'keterangan': keterangan,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchSchedules();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateSchedule({
    required int id,
    required String hari,
    String? tanggal,
    required String shift,
    required String petugasWarga,
    String? keterangan,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.put(
      '${ApiConstants.patrolSchedules}/$id',
      body: {
        'hari': hari,
        if (tanggal != null) 'tanggal': tanggal,
        'shift': shift,
        'petugas_warga': petugasWarga,
        if (keterangan != null) 'keterangan': keterangan,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchSchedules();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSchedule(int id) async {
    final response = await ApiService.delete('${ApiConstants.patrolSchedules}/$id');
    if (response['success'] == true) {
      await fetchSchedules();
      return true;
    }
    return false;
  }

  Future<bool> deleteAttendance(int id) async {
    final response = await ApiService.delete('${ApiConstants.patrolAttendances}/$id');
    if (response['success'] == true) {
      await fetchAttendances();
      return true;
    }
    return false;
  }

  Future<void> fetchAttendances({String? tanggal}) async {
    final queryParams = <String, String>{};
    if (tanggal != null) queryParams['tanggal'] = tanggal;

    final response = await ApiService.get(
      ApiConstants.patrolAttendances,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    if (response['success'] == true) {
      _attendances = List<Map<String, dynamic>>.from(response['data'] ?? []);
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> submitAttendance({
    int? scheduleId,
    String? kodeQr,
    String? tipeAbsen,
    String? catatan,
    String? fotoUrl,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.patrolAttendances,
      body: {
        if (scheduleId != null) 'schedule_id': scheduleId,
        if (kodeQr != null) 'kode_qr': kodeQr,
        if (tipeAbsen != null) 'tipe_absen': tipeAbsen,
        if (catatan != null) 'catatan': catatan,
        if (fotoUrl != null) 'foto_url': fotoUrl,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchAttendances();
      return {'success': true, 'message': response['message'] ?? 'Absensi berhasil.'};
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return {'success': false, 'message': _errorMessage ?? 'Gagal melakukan absensi.'};
    }
  }

  Future<void> fetchPosQr() async {
    final response = await ApiService.get(ApiConstants.patrolQr);
    if (response['success'] == true) {
      _posQrData = Map<String, dynamic>.from(response['data']);
      notifyListeners();
    }
  }

  Future<bool> regenerateQr() async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(ApiConstants.patrolQrRegenerate, body: {});
    _isLoading = false;
    if (response['success'] == true) {
      _posQrData = Map<String, dynamic>.from(response['data']);
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }
}
