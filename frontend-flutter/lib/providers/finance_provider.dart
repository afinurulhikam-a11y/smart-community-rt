import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/finance_model.dart';

class FinanceProvider extends ChangeNotifier {
  List<FinanceModel> _transactions = [];
  FinanceSummary? _summary;
  bool _isLoading = false;
  String? _errorMessage;

  List<FinanceModel> get transactions => _transactions;
  FinanceSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Filter yang sedang aktif, dipakai bersama oleh daftar, ringkasan, dan
  /// export supaya angka di ketiganya tidak pernah berbeda.
  Map<String, String> _filterAktif = {};
  Map<String, String> get filterAktif => Map.unmodifiable(_filterAktif);

  Future<void> fetchTransactions({
    String? tipe,
    String? bulan,
    String? tahun,
    int? kategoriId,
    String? search,
  }) async {
    _isLoading = true;
    notifyListeners();

    _filterAktif = {
      if (tipe != null && tipe.isNotEmpty) 'tipe': tipe,
      if (bulan != null && bulan.isNotEmpty) 'bulan': bulan,
      if (tahun != null && tahun.isNotEmpty) 'tahun': tahun,
      if (kategoriId != null) 'kategori_id': kategoriId.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final response = await ApiService.get(
      ApiConstants.finances,
      queryParams: _filterAktif.isNotEmpty ? _filterAktif : null,
    );

    if (response['success'] == true) {
      _transactions = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FinanceModel.fromJson)
          .toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }

    await fetchSummary(bulan: _filterAktif['bulan']);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchSummary({String? bulan}) async {
    final response = await ApiService.get(
      ApiConstants.financeSummary,
      queryParams: bulan != null && bulan.isNotEmpty ? {'bulan': bulan} : null,
    );
    if (response['success'] == true && response['data'] != null) {
      _summary = FinanceSummary.fromJson(response['data'] as Map<String, dynamic>);
      notifyListeners();
    }
  }

  /// Muat ulang dengan filter yang sedang aktif.
  Future<void> refresh() => fetchTransactions(
    tipe: _filterAktif['tipe'],
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

  Future<Map<String, dynamic>> deleteTransaction(String id) async {
    final response = await ApiService.delete(ApiConstants.finance(id));
    if (response['success'] == true) await refresh();
    return response;
  }

  /// Unduh laporan dengan filter aktif. Token lewat query param karena browser
  /// tidak menyertakan header pada navigasi unduhan.
  Future<void> downloadExport({required String format}) async {
    final token = ApiService.token;
    if (token == null) return;

    final params = <String, String>{..._filterAktif, 'format': format, 'token': token};
    final uri = Uri.parse(ApiConstants.financeExport).replace(queryParameters: params);
    await launchUrl(uri, webOnlyWindowName: '_self');
  }
}
