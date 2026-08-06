import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class AnnouncementProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get announcements => _announcements;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchAnnouncements({String? kategori, String? status, String? search}) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (kategori != null) queryParams['kategori'] = kategori;
    if (status != null) queryParams['status'] = status;
    if (search != null) queryParams['search'] = search;
    final response = await ApiService.get(
      ApiConstants.announcements,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _announcements = List<Map<String, dynamic>>.from(response['data'] ?? []);
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> createAnnouncement({
    required String judul,
    required String isi,
    String? kategori,
    String? status,
  }) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.announcements,
      body: {
        'judul': judul,
        'isi': isi,
        if (kategori != null) 'kategori': kategori,
        if (status != null) 'status': status,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchAnnouncements();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAnnouncement(
    int id, {
    String? judul,
    String? isi,
    String? kategori,
    String? status,
  }) async {
    final response = await ApiService.put(
      '${ApiConstants.announcements}/$id',
      body: {
        if (judul != null) 'judul': judul,
        if (isi != null) 'isi': isi,
        if (kategori != null) 'kategori': kategori,
        if (status != null) 'status': status,
      },
    );
    if (response['success'] == true) {
      await fetchAnnouncements();
      return true;
    }
    return false;
  }

  Future<bool> deleteAnnouncement(int id) async {
    final response = await ApiService.delete('${ApiConstants.announcements}/$id');
    if (response['success'] == true) {
      await fetchAnnouncements();
      return true;
    }
    return false;
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _announcements = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

}
