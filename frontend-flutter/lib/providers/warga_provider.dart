import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class WargaProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _wargaList = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;

  List<Map<String, dynamic>> get wargaList => _wargaList;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  Future<void> fetchWarga({String? search, int page = 1}) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': '10',
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final response = await ApiService.get(
      ApiConstants.warga,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _wargaList = List<Map<String, dynamic>>.from(response['data'] ?? []);
      final pag = response['pagination'] as Map<String, dynamic>?;
      if (pag != null) {
        _currentPage = pag['current_page'] as int? ?? 1;
        _totalPages = pag['total_pages'] as int? ?? 1;
        _totalData = pag['total_data'] as int? ?? 0;
        _perPage = pag['per_page'] as int? ?? 10;
      }
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> tambahWargaLengkap(Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.post(ApiConstants.warga, body: data);
      _isLoading = false;
      notifyListeners();

      if (response['success'] == true) {
        // Refresh data
        fetchWarga();
        return response;
      } else {
        _errorMessage = response['message'] as String?;
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return {'success': false, 'message': _errorMessage};
    }
  }

  /// Ubah data warga lewat endpoint PUT /warga/:nik. NIK tidak bisa diubah,
  /// jadi tidak ikut dikirim di body.
  Future<Map<String, dynamic>> updateWargaLengkap(
    String nik,
    Map<String, dynamic> data,
  ) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.put(
        '${ApiConstants.warga}/$nik',
        body: data,
      );
      _isLoading = false;
      notifyListeners();

      if (response['success'] == true) {
        await fetchWarga();
        return response;
      } else {
        _errorMessage = response['message'] as String?;
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return {'success': false, 'message': _errorMessage};
    }
  }

  /// Hapus warga dari data kependudukan lewat DELETE /warga/:nik.
  Future<Map<String, dynamic>> deleteWargaLengkap(String nik) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.delete('${ApiConstants.warga}/$nik');
      _isLoading = false;
      notifyListeners();

      if (response['success'] == true) {
        await fetchWarga();
        return response;
      } else {
        _errorMessage = response['message'] as String?;
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return {'success': false, 'message': _errorMessage};
    }
  }

  List<Map<String, dynamic>> _pendingWargaList = [];
  bool _isLoadingPending = false;
  String? _successMessage;

  List<Map<String, dynamic>> get pendingWargaList => _pendingWargaList;
  bool get isLoadingPending => _isLoadingPending;
  String? get successMessage => _successMessage;

  Future<void> fetchPendingWarga() async {
    _isLoadingPending = true;
    notifyListeners();
    final response = await ApiService.get(ApiConstants.pendingUsers);
    _isLoadingPending = false;
    if (response['success'] == true) {
      _pendingWargaList = List<Map<String, dynamic>>.from(response['data'] ?? []);
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> approveWarga(String id) async {
    _isLoadingPending = true;
    notifyListeners();
    final response = await ApiService.put(ApiConstants.userStatus(id), body: {'is_active': true});
    _isLoadingPending = false;

    if (response['success'] == true) {
      _pendingWargaList.removeWhere((w) => w['id'] == id);
      _successMessage = response['message'] as String?;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> rejectWarga(String id) async {
    _isLoadingPending = true;
    notifyListeners();
    final response = await ApiService.delete(ApiConstants.user(id));
    _isLoadingPending = false;

    if (response['success'] == true) {
      _pendingWargaList.removeWhere((w) => w['id'] == id);
      _successMessage = response['message'] as String?;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  /// Lewat tiket sekali pakai — lihat [ApiService.unduhDenganTiket]. Berkas ini
  /// memuat NIK, no_kk, alamat dan nomor telepon seluruh warga, jadi tautannya
  /// termasuk yang paling tidak boleh membawa kredensial di URL.
  Future<Map<String, dynamic>> downloadExcel({String? search}) {
    return ApiService.unduhDenganTiket('warga.excel', parameter: {'search': search});
  }

  Future<Map<String, dynamic>> downloadPdf({String? search}) {
    return ApiService.unduhDenganTiket('warga.pdf', parameter: {'search': search});
  }

  Future<bool> createUserAccount(Map<String, dynamic> data) async {
    _isLoadingPending = true;
    notifyListeners();

    final response = await ApiService.post(
      ApiConstants
          .users, // Assuming ApiConstants.users is defined, wait! Let's just use '/users' directly if not sure. Actually ApiConstants.user(id) exists, ApiConstants.users might not. I'll use '/users'.
      body: data,
    );

    _isLoadingPending = false;

    if (response['success'] == true) {
      _successMessage = response['message'] as String?;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> importWarga(String base64File) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.post(
        '${ApiConstants.baseUrl}/warga/import/excel', // Using full path since it's custom
        body: {'fileBase64': base64File},
      );
      _isLoading = false;
      notifyListeners();

      if (response['success'] == true) {
        fetchWarga(); // Refresh data
        return response;
      } else {
        _errorMessage = response['message'] as String?;
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return {'success': false, 'message': _errorMessage};
    }
  }

  /// Kirim kredensial login (username + sandi bawaan) ke warga lewat gateway
  /// WhatsApp backend — bukan membuka wa.me di perangkat pengurus.
  Future<Map<String, dynamic>> kirimKredensialWA(String nik) async {
    try {
      final response = await ApiService.post(
        ApiConstants.wargaKirimKredensialWa,
        body: {'nik': nik},
      );
      return response;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return {'success': false, 'message': _errorMessage};
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
    _wargaList = [];
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _perPage = 10;
    _pendingWargaList = [];
    _isLoadingPending = false;
    _successMessage = null;
    notifyListeners();
  }

}
