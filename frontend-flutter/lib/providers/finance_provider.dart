import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/finance_model.dart';

class FinanceProvider extends ChangeNotifier {
  List<FinanceModel> _transactions = [];
  FinanceSummary? _summary;
  // Agregat bulanan untuk grafik dashboard. Dihitung di backend lewat
  // GET /finances/bulanan, bukan dari daftar transaksi yang ter-paginate —
  // daftar itu hanya berisi satu halaman, sehingga chart yang dibangun dari
  // situ salah melaporkan bulan-bulan di luar halaman pertama.
  List<Map<String, dynamic>> _bulanan = [];
  bool _isLoading = false;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;

  List<FinanceModel> get transactions => _transactions;
  FinanceSummary? get summary => _summary;
  List<Map<String, dynamic>> get bulanan => _bulanan;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  /// Filter yang sedang aktif, dipakai bersama oleh daftar, ringkasan, dan
  /// export supaya angka di ketiganya tidak pernah berbeda.
  Map<String, String> _filterAktif = {};
  Map<String, String> get filterAktif => Map.unmodifiable(_filterAktif);

  Future<void> fetchTransactions({
    String? tipe,
    String? sumber,
    String? bulan,
    String? tahun,
    int? kategoriId,
    String? search,
    int page = 1,
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    _currentPage = page;

    _filterAktif = {
      if (tipe != null && tipe.isNotEmpty) 'tipe': tipe,
      if (sumber != null && sumber.isNotEmpty) 'sumber': sumber,
      if (bulan != null && bulan.isNotEmpty) 'bulan': bulan,
      if (tahun != null && tahun.isNotEmpty) 'tahun': tahun,
      if (kategoriId != null) 'kategori_id': kategoriId.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final params = Map<String, String>.from(_filterAktif);
    params['page'] = page.toString();
    params['limit'] = '10';

    final response = await ApiService.get(
      ApiConstants.finances,
      queryParams: params,
      // cache: true — daftar ini yang pertama dibuka orang, dan yang paling
      // merugikan bila kosong saat sinyal hilang. Jawaban terakhir disimpan
      // dan dipakai HANYA ketika server tidak terjangkau; penolakan dari
      // server tetap diteruskan apa adanya.
      cache: true,
    );

    if (response['success'] == true) {
      _transactions = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FinanceModel.fromJson)
          .toList();
      if (response['pagination'] != null) {
        _totalPages = response['pagination']['total_pages'] ?? 1;
        _totalData = response['pagination']['total_data'] ?? 0;
        _perPage = response['pagination']['per_page'] as int? ?? 10;
      }
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }

    await fetchSummary(bulan: _filterAktif['bulan'], sumber: _filterAktif['sumber']);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchSummary({String? bulan, String? sumber}) async {
    final q = <String, String>{
      if (bulan != null && bulan.isNotEmpty) 'bulan': bulan,
      if (sumber != null && sumber.isNotEmpty) 'sumber': sumber,
    };
    final response = await ApiService.get(
      ApiConstants.financeSummary,
      queryParams: q.isNotEmpty ? q : null,
    );
    if (response['success'] == true && response['data'] != null) {
      _summary = FinanceSummary.fromJson(response['data'] as Map<String, dynamic>);
      notifyListeners();
    }
  }

  /// Agregat pemasukan/pengeluaran per bulan untuk grafik dashboard.
  Future<void> fetchBulanan({int rentang = 12, int? tahun}) async {
    final query = <String, String>{
      if (tahun != null)
        'tahun': tahun.toString()
      else
        'rentang': rentang.toString(),
    };
    final response = await ApiService.get(
      ApiConstants.financeBulanan,
      queryParams: query,
    );
    if (response['success'] == true) {
      _bulanan = List<Map<String, dynamic>>.from(response['data'] ?? []);
      notifyListeners();
    }
  }

  /// Muat ulang dengan filter yang sedang aktif.
  Future<void> refresh() => fetchTransactions(
    tipe: _filterAktif['tipe'],
    sumber: _filterAktif['sumber'],
    bulan: _filterAktif['bulan'],
    tahun: _filterAktif['tahun'],
    kategoriId: _filterAktif['kategori_id'] == null
        ? null
        : int.tryParse(_filterAktif['kategori_id']!),
    search: _filterAktif['search'],
  );

  Future<Map<String, dynamic>> createTransaction({
    required String tipe,
    required double jumlah,
    required String deskripsi,
    int? kategoriId,
    String? tanggal,
  }) async {
    final response = await ApiService.post(
      ApiConstants.finances,
      body: {
        'tipe': tipe,
        'jumlah': jumlah,
        'deskripsi': deskripsi,
        if (kategoriId != null) 'kategori_id': kategoriId,
        if (tanggal != null && tanggal.isNotEmpty) 'tanggal': tanggal,
      },
    );
    if (response['success'] == true) await refresh();
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
      ApiConstants.finance(id),
      body: {
        if (tipe != null) 'tipe': tipe,
        if (jumlah != null) 'jumlah': jumlah,
        if (deskripsi != null) 'deskripsi': deskripsi,
        if (kategoriId != null) 'kategori_id': kategoriId,
        if (tanggal != null && tanggal.isNotEmpty) 'tanggal': tanggal,
      },
    );
    if (response['success'] == true) await refresh();
    return response;
  }

  /// Hapus satu transaksi kas manual. Baris dari iuran ditolak backend.
  Future<Map<String, dynamic>> deleteTransaction(String id) async {
    final response = await ApiService.delete(ApiConstants.finance(id));
    if (response['success'] == true) await refresh();
    return response;
  }


  /// Unduh laporan dengan filter aktif, lewat tiket sekali pakai —
  /// lihat [ApiService.unduhDenganTiket].
  Future<Map<String, dynamic>> downloadExport({required String format}) {
    return ApiService.unduhDenganTiket(
      'kas.export',
      parameter: {..._filterAktif, 'format': format},
    );
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
    _summary = null;
    _bulanan = [];
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _perPage = 10;
    _filterAktif = {};
    notifyListeners();
  }

}
