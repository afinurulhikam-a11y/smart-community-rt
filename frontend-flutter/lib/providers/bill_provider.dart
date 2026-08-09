import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/bill_model.dart';

class BillProvider extends ChangeNotifier {
  List<BillModel> _bills = [];
  BillStats _stats = BillStats.kosong();
  // Statistik khusus bulan berjalan, dipakai card "Progress Iuran Bulan Ini"
  // di dashboard. Sengaja TERPISAH dari `_stats` yang mengikuti filter daftar
  // layar — card itu harus selalu menampilkan bulan berjalan, apa pun filter
  // yang dipilih pengurus di layar Iuran Warga.
  BillStats _statsBulanIni = BillStats.kosong();
  bool _isLoading = false;
  String? _errorMessage;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;

  List<BillModel> get bills => _bills;
  BillStats get stats => _stats;
  BillStats get statsBulanIni => _statsBulanIni;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  List<BillModel> get unpaidBills => _bills.where((b) => !b.isLunas).toList();
  List<BillModel> get paidBills => _bills.where((b) => b.isLunas).toList();

  /// Filter yang sedang aktif. Disimpan supaya daftar, statistik, dan export
  /// selalu memakai penyaringan yang sama — kalau tidak, angka di kartu
  /// ringkasan bisa berbeda dari isi tabel.
  Map<String, String> _filterAktif = {};
  Map<String, String> get filterAktif => Map.unmodifiable(_filterAktif);

  Map<String, String> _susunFilter({
    String? status,
    String? bulan,
    String? tahun,
    int? jenisIuranId,
    String? search,
  }) {
    final q = <String, String>{};
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (bulan != null && bulan.isNotEmpty) q['bulan'] = bulan;
    if (tahun != null && tahun.isNotEmpty) q['tahun'] = tahun;
    if (jenisIuranId != null) q['jenis_iuran_id'] = jenisIuranId.toString();
    if (search != null && search.isNotEmpty) q['search'] = search;
    return q;
  }

  /// Ambil daftar tagihan sekaligus statistiknya dalam satu langkah.
  Future<void> fetchBills({
    String? status,
    String? bulan,
    String? tahun,
    int? jenisIuranId,
    String? search,
    int page = 1,
  }) async {
    _isLoading = true;
    notifyListeners();

    _filterAktif = _susunFilter(
      status: status,
      bulan: bulan,
      tahun: tahun,
      jenisIuranId: jenisIuranId,
      search: search,
    );

    final query = Map<String, String>.from(_filterAktif);
    query['page'] = page.toString();
    query['limit'] = '10';

    final response = await ApiService.get(
      ApiConstants.bills,
      queryParams: query,
      // cache: true — daftar ini yang pertama dibuka orang, dan yang paling
      // merugikan bila kosong saat sinyal hilang. Jawaban terakhir disimpan
      // dan dipakai HANYA ketika server tidak terjangkau; penolakan dari
      // server tetap diteruskan apa adanya.
      cache: true,
    );

    if (response['success'] == true) {
      _bills = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(BillModel.fromJson)
          .toList();
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

    await _fetchStats();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchStats() async {
    final response = await ApiService.get(
      ApiConstants.billStats,
      queryParams: _filterAktif.isNotEmpty ? _filterAktif : null,
    );
    if (response['success'] == true && response['data'] != null) {
      _stats = BillStats.fromJson(response['data'] as Map<String, dynamic>);
    }
  }

  /// Statistik untuk bulan berjalan, dipakai card Progress Iuran dashboard.
  Future<void> fetchStatsBulanIni() async {
    final sekarang = DateTime.now();
    final bulanIni = DateFormat('yyyy-MM').format(sekarang);
    final response = await ApiService.get(
      ApiConstants.billStats,
      queryParams: {'bulan': bulanIni, 'tahun': sekarang.year.toString()},
    );
    if (response['success'] == true && response['data'] != null) {
      _statsBulanIni = BillStats.fromJson(response['data'] as Map<String, dynamic>);
      notifyListeners();
    }
  }

  Future<void> refresh() => fetchBills(
    status: _filterAktif['status'],
    bulan: _filterAktif['bulan'],
    tahun: _filterAktif['tahun'],
    jenisIuranId: _filterAktif['jenis_iuran_id'] == null
        ? null
        : int.tryParse(_filterAktif['jenis_iuran_id']!),
    search: _filterAktif['search'],
    page: _currentPage,
  );

  Future<Map<String, dynamic>> createBill({
    required int keluargaId,
    required int jenisIuranId,
    required String bulan,
    double? nominal,
    String? keterangan,
    String? jatuhTempo,
    int? meteranLalu,
    int? meteranSekarang,
  }) async {
    final response = await ApiService.post(
      ApiConstants.bills,
      body: {
        'keluarga_id': keluargaId,
        'jenis_iuran_id': jenisIuranId,
        'bulan': bulan,
        // Untuk iuran bermeteran, `nominal` diabaikan backend dan totalnya
        // dihitung dari kedua angka ini — supaya rincian yang tampil selalu
        // menjumlah ke totalnya sendiri.
        if (nominal != null) 'nominal': nominal,
        if (meteranLalu != null) 'meteran_lalu': meteranLalu,
        if (meteranSekarang != null) 'meteran_sekarang': meteranSekarang,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
        if (jatuhTempo != null && jatuhTempo.isNotEmpty) 'jatuh_tempo': jatuhTempo,
      },
    );
    if (response['success'] == true) await refresh();
    return response;
  }

  /// Ubah tagihan yang belum lunas: nominal, keterangan, jatuh tempo.
  Future<Map<String, dynamic>> updateBill(
    String id, {
    double? nominal,
    String? keterangan,
    String? jatuhTempo,
    int? meteranLalu,
    int? meteranSekarang,
  }) async {
    final response = await ApiService.put(
      ApiConstants.bill(id),
      body: {
        if (nominal != null) 'nominal': nominal,
        if (meteranLalu != null) 'meteran_lalu': meteranLalu,
        if (meteranSekarang != null) 'meteran_sekarang': meteranSekarang,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
        if (jatuhTempo != null && jatuhTempo.isNotEmpty) 'jatuh_tempo': jatuhTempo,
      },
    );
    if (response['success'] == true) await refresh();
    return response;
  }

  /// Buat tagihan untuk seluruh kartu keluarga sekaligus pada satu periode.
  Future<Map<String, dynamic>> generateBills({
    required int jenisIuranId,
    required String bulan,
    double? nominal,
    String? keterangan,
    String? jatuhTempo,
  }) async {    _isLoading = true;
    notifyListeners();

    final response = await ApiService.post(
      ApiConstants.billsGenerate,
      body: {
        'jenis_iuran_id': jenisIuranId,
        'bulan': bulan,
        if (nominal != null) 'nominal': nominal,
        if (keterangan != null && keterangan.isNotEmpty) 'keterangan': keterangan,
        if (jatuhTempo != null && jatuhTempo.isNotEmpty) 'jatuh_tempo': jatuhTempo,
      },
    );

    if (response['success'] == true) {
      await refresh();
    } else {
      _isLoading = false;
      _errorMessage = response['message'] as String?;
      notifyListeners();
    }
    return response;
  }

  Future<bool> payBill(String billId, {String metodeBayar = 'tunai'}) async {
    final response = await ApiService.post(
      ApiConstants.payBill(billId),
      body: {'metode_bayar': metodeBayar},
    );
    if (response['success'] == true) {
      await refresh();
      return true;
    }
    _errorMessage = response['message'] as String?;
    notifyListeners();
    return false;
  }

  Future<Map<String, dynamic>> payBillsBulk(
    List<String> billIds, {
    String metodeBayar = 'tunai',
  }) async {
    _isLoading = true;
    notifyListeners();

    final response = await ApiService.post(
      ApiConstants.billsPayBulk,
      body: {'bill_ids': billIds, 'metode_bayar': metodeBayar},
    );

    if (response['success'] == true) {
      await refresh();
    } else {
      _isLoading = false;
      _errorMessage = response['message'] as String?;
      notifyListeners();
    }
    return response;
  }

  Future<Map<String, dynamic>> deleteBill(String billId) async {
    final response = await ApiService.delete(ApiConstants.bill(billId));
    if (response['success'] == true) await refresh();
    return response;
  }

  /// Unduh export dengan filter yang sedang aktif. Token dikirim lewat query
  /// param karena browser tidak menyertakan header pada navigasi unduhan —
  /// pola yang sama dipakai WargaProvider.downloadExcel.
  Future<void> downloadExport({required String format}) async {
    final token = ApiService.token;
    if (token == null) return;

    final params = <String, String>{..._filterAktif, 'format': format, 'token': token};
    final uri = Uri.parse(ApiConstants.billExport).replace(queryParameters: params);
    await launchUrl(uri, webOnlyWindowName: '_self');
  }

  /// Kirim penagihan WhatsApp lewat gateway backend (Fonnte). Dipakai untuk
  /// pengiriman massal (`billIds` kosong → seluruh tunggakan sesuai filter)
  /// maupun per keluarga / per tagihan (berikan daftar `bill_ids`).
  ///
  /// Dulu pengiriman manual membuka `wa.me` per keluarga di sisi klien — yang
  /// terblokir browser bila banyak tab, dan memakai WhatsApp operator, bukan
  /// gateway sistem. Sekarang semua jalur lewat endpoint ini.
  ///
  /// Kalau FONNTE_TOKEN di backend kosong, endpoint tetap sukses tetapi hanya
  /// simulasi (log server); warga tidak benar-benar menerima WA.
  Future<Map<String, dynamic>> tagihSemuaWA({List<String>? billIds}) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.billsTagihWa,
      body: billIds == null || billIds.isEmpty ? const {} : {'bill_ids': billIds},
    );
    _isLoading = false;
    // notifyListeners() harus dipanggil di DUA arah. Awalnya hanya dipanggil
    // saat gagal, sehingga pada keberhasilan UI tidak pernah diberi tahu bahwa
    // loading selesai — spinner berputar tanpa henti.
    notifyListeners();
    if (response['success'] != true) {
      _errorMessage = response['message'] as String?;
    }
    return response;
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _bills = [];
    _stats = BillStats.kosong();
    _statsBulanIni = BillStats.kosong();
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
