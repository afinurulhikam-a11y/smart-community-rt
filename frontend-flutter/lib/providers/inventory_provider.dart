import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/inventory_model.dart';
import '../models/borrowing_model.dart';

class InventoryProvider extends ChangeNotifier {
  List<InventoryModel> _items = [];
  List<BorrowingModel> _borrowings = [];
  InventoryStats _statsBarang = const InventoryStats();
  BorrowingStats _statsPinjam = const BorrowingStats();
  bool _isLoading = false;
  String? _errorMessage;

  List<InventoryModel> get items => _items;
  List<BorrowingModel> get borrowings => _borrowings;
  InventoryStats get statsBarang => _statsBarang;
  BorrowingStats get statsPinjam => _statsPinjam;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Diisi lewat endpoint peminjaman, bukan endpoint inventaris.
  List<InventoryModel> _barangPinjam = [];

  /// Hanya barang yang masih bisa dipinjam — dipakai dropdown dialog peminjaman
  /// supaya barang yang habis tidak muncul sebagai pilihan.
  ///
  /// Warga tidak punya izin `inventaris.barang`, jadi `_items` selalu kosong
  /// baginya. Untuk itu ada [fetchBarangTersedia] yang memakai endpoint di
  /// bawah modul peminjaman; hasilnya diutamakan bila sudah termuat.
  List<InventoryModel> get barangTersedia =>
      _barangPinjam.isNotEmpty ? _barangPinjam : _items.where((i) => i.bisaDipinjam).toList();

  /// Daftar ringkas barang yang masih tersedia, tanpa menyentuh endpoint
  /// inventaris — satu-satunya jalan bagi warga mengisi form ajukan pinjam.
  Future<void> fetchBarangTersedia() async {
    final response = await ApiService.get(ApiConstants.barangTersedia);
    if (response['success'] == true) {
      _barangPinjam = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(InventoryModel.fromJson)
          .toList();
      notifyListeners();
    }
  }

  Map<String, String> _filterBarang = {};
  Map<String, String> _filterPinjam = {};
  Map<String, String> get filterBarang => Map.unmodifiable(_filterBarang);
  Map<String, String> get filterPinjam => Map.unmodifiable(_filterPinjam);

  // ------------------------------------------------------------- inventaris

  Future<void> fetchInventory({String? kategori, String? kondisi, String? search}) async {
    _isLoading = true;
    notifyListeners();

    _filterBarang = {
      if (kategori != null && kategori.isNotEmpty) 'kategori': kategori,
      if (kondisi != null && kondisi.isNotEmpty) 'kondisi': kondisi,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final response = await ApiService.get(
      ApiConstants.inventory,
      queryParams: _filterBarang.isNotEmpty ? _filterBarang : null,
    );

    if (response['success'] == true) {
      _items = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(InventoryModel.fromJson)
          .toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }

    await _fetchStatsBarang();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchStatsBarang() async {
    final r = await ApiService.get(
      ApiConstants.inventoryStats,
      queryParams: _filterBarang.isNotEmpty ? _filterBarang : null,
    );
    if (r['success'] == true && r['data'] != null) {
      _statsBarang = InventoryStats.fromJson(r['data'] as Map<String, dynamic>);
    }
  }

  /// Muat ulang ketersediaan barang lewat jalur yang sesuai role.
  ///
  /// Peminjaman mengubah jumlah tersedia, jadi daftarnya harus disegarkan.
  /// Tetapi warga tidak boleh menyentuh endpoint inventaris — baginya jalur
  /// yang benar adalah endpoint ringkas di bawah modul peminjaman.
  Future<void> _muatUlangKetersediaan() =>
      _barangPinjam.isNotEmpty ? fetchBarangTersedia() : refreshInventory();

  Future<void> refreshInventory() => fetchInventory(
    kategori: _filterBarang['kategori'],
    kondisi: _filterBarang['kondisi'],
    search: _filterBarang['search'],
  );

  /// Detail satu barang beserta riwayat peminjamannya.
  Future<Map<String, dynamic>?> fetchInventoryDetail(int id) async {
    final r = await ApiService.get(ApiConstants.inventoryById(id));
    if (r['success'] == true) return r['data'] as Map<String, dynamic>?;
    _errorMessage = r['message'] as String?;
    return null;
  }

  Future<Map<String, dynamic>> createInventory({
    required String namaBarang,
    String? kategori,
    int? jumlah,
    String? kondisi,
    String? lokasi,
    double? nilaiBarang,
    String? tanggalPerolehan,
    String? keterangan,
  }) async {
    final r = await ApiService.post(
      ApiConstants.inventory,
      body: {
        'nama_barang': namaBarang,
        if (kategori != null && kategori.isNotEmpty) 'kategori': kategori,
        if (jumlah != null) 'jumlah': jumlah,
        if (kondisi != null) 'kondisi': kondisi,
        if (lokasi != null && lokasi.isNotEmpty) 'lokasi': lokasi,
        if (nilaiBarang != null) 'nilai_barang': nilaiBarang,
        if (tanggalPerolehan != null && tanggalPerolehan.isNotEmpty)
          'tanggal_perolehan': tanggalPerolehan,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
      },
    );
    if (r['success'] == true) await refreshInventory();
    return r;
  }

  Future<Map<String, dynamic>> updateInventory(int id, Map<String, dynamic> data) async {
    final r = await ApiService.put(ApiConstants.inventoryById(id), body: data);
    if (r['success'] == true) await refreshInventory();
    return r;
  }

  Future<Map<String, dynamic>> deleteInventory(int id) async {
    final r = await ApiService.delete(ApiConstants.inventoryById(id));
    if (r['success'] == true) await refreshInventory();
    return r;
  }

  // ------------------------------------------------------------ peminjaman

  Future<void> fetchBorrowings({String? status, int? inventoryId, String? search}) async {
    _isLoading = true;
    notifyListeners();

    _filterPinjam = {
      if (status != null && status.isNotEmpty) 'status': status,
      if (inventoryId != null) 'inventory_id': inventoryId.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final response = await ApiService.get(
      ApiConstants.borrowings,
      queryParams: _filterPinjam.isNotEmpty ? _filterPinjam : null,
    );

    if (response['success'] == true) {
      _borrowings = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(BorrowingModel.fromJson)
          .toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }

    await _fetchStatsPinjam();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchStatsPinjam() async {
    final r = await ApiService.get(ApiConstants.borrowingStats);
    if (r['success'] == true && r['data'] != null) {
      _statsPinjam = BorrowingStats.fromJson(r['data'] as Map<String, dynamic>);
    }
  }

  Future<void> refreshBorrowings() => fetchBorrowings(
    status: _filterPinjam['status'],
    inventoryId: _filterPinjam['inventory_id'] == null
        ? null
        : int.tryParse(_filterPinjam['inventory_id']!),
    search: _filterPinjam['search'],
  );

  Future<Map<String, dynamic>> createBorrowing({
    required int inventoryId,

    /// Dikosongkan bila warga meminjam untuk dirinya sendiri. Backend memakai
    /// akun pemanggil dan memang MENGABAIKAN nilai ini untuk role warga, jadi
    /// mengirimnya pun tidak akan mengubah siapa peminjamnya.
    String? userId,
    int? jumlah,
    String? tanggalPinjam,
    String? tanggalRencanaKembali,
    String? keterangan,
  }) async {
    final r = await ApiService.post(
      ApiConstants.borrowings,
      body: {
        'inventory_id': inventoryId,
        if (userId != null) 'user_id': userId,
        if (jumlah != null) 'jumlah': jumlah,
        if (tanggalPinjam != null && tanggalPinjam.isNotEmpty) 'tanggal_pinjam': tanggalPinjam,
        if (tanggalRencanaKembali != null && tanggalRencanaKembali.isNotEmpty)
          'tanggal_rencana_kembali': tanggalRencanaKembali,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
      },
    );
    if (r['success'] == true) {
      await refreshBorrowings();
      // Ketersediaan barang ikut berubah, jadi daftar barang dimuat ulang.
      await _muatUlangKetersediaan();
    }
    return r;
  }

  Future<Map<String, dynamic>> updateBorrowing(int id, Map<String, dynamic> data) async {
    final r = await ApiService.put(ApiConstants.borrowingById(id), body: data);
    if (r['success'] == true) {
      await refreshBorrowings();
      await _muatUlangKetersediaan();
    }
    return r;
  }

  Future<Map<String, dynamic>> approveBorrowing(int id) async {
    final r = await ApiService.put('${ApiConstants.borrowingById(id)}/approve');
    if (r['success'] == true) {
      await refreshBorrowings();
      await _muatUlangKetersediaan();
    }
    return r;
  }

  Future<Map<String, dynamic>> rejectBorrowing(int id) async {
    final r = await ApiService.put('${ApiConstants.borrowingById(id)}/reject');
    if (r['success'] == true) {
      await refreshBorrowings();
      await _muatUlangKetersediaan();
    }
    return r;
  }

  Future<Map<String, dynamic>> returnBorrowing(int id, {String? tanggalKembali}) async {
    final r = await ApiService.put(
      ApiConstants.returnBorrowing(id),
      body: {
        if (tanggalKembali != null && tanggalKembali.isNotEmpty) 'tanggal_kembali': tanggalKembali,
      },
    );
    if (r['success'] == true) {
      await refreshBorrowings();
      await _muatUlangKetersediaan();
    }
    return r;
  }

  Future<Map<String, dynamic>> deleteBorrowing(int id) async {
    final r = await ApiService.delete(ApiConstants.borrowingById(id));
    if (r['success'] == true) {
      await refreshBorrowings();
      await _muatUlangKetersediaan();
    }
    return r;
  }

  // ---------------------------------------------------------------- export

  /// Token lewat query param karena browser tidak menyertakan header pada
  /// navigasi unduhan.
  Future<void> downloadExport({required String format, required bool peminjaman}) async {
    final token = ApiService.token;
    if (token == null) return;

    final params = <String, String>{
      ...(peminjaman ? _filterPinjam : _filterBarang),
      'format': format,
      'token': token,
    };
    final uri = Uri.parse(
      peminjaman ? ApiConstants.borrowingExport : ApiConstants.inventoryExport,
    ).replace(queryParameters: params);
    await launchUrl(uri, webOnlyWindowName: '_self');
  }
}
