import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
// FinanceModel dipakai ulang karena baris transaksi BOP bentuknya sama
// (tipe, jumlah, deskripsi, tanggal, kategori). Ringkasannya TIDAK dipakai
// ulang: BOP punya pagu yang tidak ada padanannya di Kas RT, jadi memakai
// BopSummary tersendiri.
import '../models/finance_model.dart';
import '../models/bop_model.dart';

class BopProvider extends ChangeNotifier {
  List<FinanceModel> _transactions = [];
  BopSummary? _summary;
  // Agregat bulanan untuk grafik dashboard — dihitung backend dari SEMUA
  // baris, bukan dari daftar ter-paginate.
  List<Map<String, dynamic>> _bulanan = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Pagination di SISI SERVER, menyamai FinanceProvider.
  //
  // Sebelumnya layar BOP mengambil seluruh tabel lalu memotongnya sendiri
  // dengan `sublist`. Artinya setiap pemuatan menghitung window function saldo
  // berjalan atas setiap baris yang pernah ada, hanya untuk menampilkan
  // sepuluh. Kas RT sudah dipindah ke sisi server; BOP tertinggal, padahal
  // keduanya memang dimaksudkan berperilaku sama.
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;

  List<FinanceModel> get transactions => _transactions;
  BopSummary? get summary => _summary;
  List<Map<String, dynamic>> get bulanan => _bulanan;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;

  /// Filter aktif, dipakai bersama daftar, ringkasan, dan export supaya
  /// angkanya tidak pernah berbeda.
  Map<String, String> _filterAktif = {};
  Map<String, String> get filterAktif => Map.unmodifiable(_filterAktif);

  Future<void> fetchTransactions({
    String? tipe,
    String? bulan,
    String? tahun,
    int? kategoriId,
    String? search,
    int page = 1,
    int limit = 25,
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    _currentPage = page;

    // `page` dan `limit` sengaja TIDAK masuk `_filterAktif`. Peta itu dipakai
    // ulang oleh ringkasan dan export, dan keduanya harus mencakup seluruh
    // data yang cocok — bukan sepotong halaman yang kebetulan sedang dibuka.
    _filterAktif = {
      if (tipe != null && tipe.isNotEmpty) 'tipe': tipe,
      if (bulan != null && bulan.isNotEmpty) 'bulan': bulan,
      if (tahun != null && tahun.isNotEmpty) 'tahun': tahun,
      if (kategoriId != null) 'kategori_id': kategoriId.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final params = Map<String, String>.from(_filterAktif);
    params['page'] = page.toString();
    params['limit'] = limit.toString();

    final response = await ApiService.get(ApiConstants.bop, queryParams: params);

    if (response['success'] == true) {
      _transactions = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FinanceModel.fromJson)
          .toList();
      if (response['pagination'] != null) {
        _totalPages = response['pagination']['total_pages'] ?? 1;
        _totalData = response['pagination']['total_data'] ?? 0;
      }
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }

    await fetchSummary(bulan: _filterAktif['bulan'], tahun: _filterAktif['tahun']);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchSummary({String? bulan, String? tahun}) async {
    final q = <String, String>{
      if (bulan != null && bulan.isNotEmpty) 'bulan': bulan,
      if (tahun != null && tahun.isNotEmpty) 'tahun': tahun,
    };
    final response = await ApiService.get(
      ApiConstants.bopSummary,
      queryParams: q.isNotEmpty ? q : null,
    );
    if (response['success'] == true && response['data'] != null) {
      _summary = BopSummary.fromJson(response['data'] as Map<String, dynamic>);
      notifyListeners();
    }
  }

  /// Agregat pemasukan/pengeluaran per bulan untuk grafik dashboard BOP.
  Future<void> fetchBulanan({int rentang = 12, int? tahun}) async {
    final query = <String, String>{
      if (tahun != null)
        'tahun': tahun.toString()
      else
        'rentang': rentang.toString(),
    };
    final response = await ApiService.get(
      ApiConstants.bopBulanan,
      queryParams: query,
    );
    if (response['success'] == true) {
      _bulanan = List<Map<String, dynamic>>.from(response['data'] ?? []);
      notifyListeners();
    }
  }

  /// Muat ulang dengan filter DAN halaman yang sedang aktif.
  Future<void> refresh({int? page}) => fetchTransactions(
    tipe: _filterAktif['tipe'],
    bulan: _filterAktif['bulan'],
    tahun: _filterAktif['tahun'],
    kategoriId: _filterAktif['kategori_id'] == null
        ? null
        : int.tryParse(_filterAktif['kategori_id']!),
    search: _filterAktif['search'],
    page: page ?? _currentPage,
  );

  Future<Map<String, dynamic>> createTransaction({
    required String tipe,
    required double jumlah,
    required String deskripsi,
    int? kategoriId,
    String? tanggal,
  }) async {
    final response = await ApiService.post(
      ApiConstants.bop,
      body: {
        'tipe': tipe,
        'jumlah': jumlah,
        'deskripsi': deskripsi,
        if (kategoriId != null) 'kategori_id': kategoriId,
        if (tanggal != null && tanggal.isNotEmpty) 'tanggal': tanggal,
      },
    );
    if (response['success'] == true) await refresh(page: 1);
    return response;
  }

  Future<Map<String, dynamic>> updateTransaction(
    String id, {
    String? tipe,
    double? jumlah,
    String? deskripsi,
    int? kategoriId,
    String? tanggal,
  }) async {
    final response = await ApiService.put(
      ApiConstants.bopById(id),
      body: {
        if (tipe != null) 'tipe': tipe,
        if (jumlah != null) 'jumlah': jumlah,
        if (deskripsi != null) 'deskripsi': deskripsi,
        if (kategoriId != null) 'kategori_id': kategoriId,
        if (tanggal != null && tanggal.isNotEmpty) 'tanggal': tanggal,
      },
    );
    if (response['success'] == true) await refresh(page: _currentPage);
    return response;
  }

  Future<Map<String, dynamic>> deleteTransaction(String id) async {
    final response = await ApiService.delete(ApiConstants.bopById(id));
    if (response['success'] == true) {
      final targetPage = (_transactions.length == 1 && _currentPage > 1)
          ? _currentPage - 1
          : _currentPage;
      await refresh(page: targetPage);
    }
    return response;
  }

  /// Unduh laporan dengan filter aktif, lewat tiket sekali pakai —
  /// lihat [ApiService.unduhDenganTiket].
  Future<Map<String, dynamic>> downloadExport({required String format}) {
    final params = <String, dynamic>{..._filterAktif, 'format': format};
    params.remove('limit');
    return ApiService.unduhDenganTiket('bop.export', parameter: params);
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _transactions = [];
    _bulanan = [];
    _summary = null;
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _filterAktif = {};
    notifyListeners();
  }

}
