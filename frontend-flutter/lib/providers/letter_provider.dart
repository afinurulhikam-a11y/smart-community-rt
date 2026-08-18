import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/letter_model.dart';

class LetterProvider extends ChangeNotifier {
  List<LetterModel> _letters = [];
  bool _isLoading = false;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  String? _lastStatus;

  List<LetterModel> get letters => _letters;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;

  int get pendingCount => _letters.where((l) => l.isPending).length;
  List<LetterModel> get pendingLetters => _letters.where((l) => l.isPending).toList();

  Future<void> fetchLetters({String? status, int page = 1, bool silent = false}) async {
    _lastStatus = status;
    _currentPage = page;

    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    final queryParams = <String, String>{};
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    queryParams['page'] = page.toString();
    queryParams['limit'] = '25';
    final response = await ApiService.get(
      ApiConstants.letters,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    if (response['success'] == true) {
      final dataList = response['data'] as List<dynamic>;
      _letters = dataList.map((j) => LetterModel.fromJson(j as Map<String, dynamic>)).toList();
      if (response['pagination'] != null) {
        _totalPages = response['pagination']['total_pages'] ?? 1;
        _totalData = response['pagination']['total_data'] ?? 0;
      }
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createLetter({required String jenisSurat, required String keperluan}) async {
    _isLoading = true;
    notifyListeners();
    // Permohonan surat menunggu persetujuan pengurus, jadi aman ditunda —
    // sama seperti pengaduan. Lihat AntreanOffline untuk yang tidak boleh.
    final response = await ApiService.post(
      ApiConstants.letters,
      body: {'jenis_surat': jenisSurat, 'keperluan': keperluan},
      judulAntrean: 'Permohonan surat: $jenisSurat',
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchLetters(status: _lastStatus, page: 1);
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateLetterStatus(String id, String status, {String? responseNote}) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.put(
      ApiConstants.approveLetter(id),
      body: {'status': status, if (responseNote != null) 'response_note': responseNote},
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchLetters(status: _lastStatus, page: _currentPage);
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteLetter(String id) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.delete('${ApiConstants.letters}/$id');
    _isLoading = false;
    if (response['success'] == true) {
      await fetchLetters(status: _lastStatus, page: _currentPage);
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _letters = [];
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _lastStatus = null;
    notifyListeners();
  }

}
