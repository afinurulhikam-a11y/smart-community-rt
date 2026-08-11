import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';

class ComplaintProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = false;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;

  Map<String, int> _stats = {
    'pending': 0,
    'diproses': 0,
    'selesai': 0,
    'ditolak': 0,
    'total': 0,
  };

  List<Map<String, dynamic>> get complaints => _complaints;
  Map<String, int> get stats => _stats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;

  Future<void> fetchStats() async {
    final response = await ApiService.get(ApiConstants.complaintStats);
    if (response['success'] == true && response['data'] != null) {
      final data = Map<String, dynamic>.from(response['data']);
      _stats = {
        'pending': (data['pending'] ?? 0) as int,
        'diproses': (data['diproses'] ?? 0) as int,
        'selesai': (data['selesai'] ?? 0) as int,
        'ditolak': (data['ditolak'] ?? 0) as int,
        'total': (data['total'] ?? 0) as int,
      };
      notifyListeners();
    }
  }

  Future<void> fetchComplaints({String? status, String? search, int page = 1}) async {
    _isLoading = true;
    _currentPage = page;
    notifyListeners();
    fetchStats();
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    if (search != null) queryParams['search'] = search;
    queryParams['page'] = page.toString();
    queryParams['limit'] = '25';
    final response = await ApiService.get(
      ApiConstants.complaints,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _complaints = List<Map<String, dynamic>>.from(response['data'] ?? []);
      if (response['pagination'] != null) {
        _totalPages = response['pagination']['total_pages'] ?? 1;
        _totalData = response['pagination']['total_data'] ?? 0;
      }
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  Future<bool> createComplaint({required String judul, String? deskripsi, String? kategori}) async {
    _isLoading = true;
    notifyListeners();
    // `judulAntrean` menandai permintaan ini AMAN ditunda. Pengaduan menunggu
    // ditinjau manusia dan tidak mengubah apa pun seketika, jadi terkirim
    // beberapa menit kemudian tidak mengubah artinya. Uang dan alarm tidak
    // pernah diantre — lihat AntreanOffline.
    final response = await ApiService.post(
      ApiConstants.complaints,
      body: {
        'judul': judul,
        if (deskripsi != null) 'deskripsi': deskripsi,
        if (kategori != null) 'kategori': kategori,
      },
      judulAntrean: 'Pengaduan: $judul',
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchComplaints();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  /// Ubah status pengaduan, sekaligus menyimpan teks tanggapan pengurus.
  ///
  /// `_errorMessage` WAJIB diisi di sini. Dialog Tanggapi menampilkan
  /// `prov.errorMessage` ketika penyimpanan gagal — dan sebelumnya metode ini
  /// tidak pernah menyentuhnya. Akibatnya bukan sekadar pesan yang kurang
  /// informatif: nilai lamanya tetap tersimpan, sehingga kegagalan hari ini
  /// bisa dijelaskan dengan alasan dari kegagalan yang sama sekali lain — dan
  /// pengurus menyimpulkan sebab yang salah. Dikosongkan lagi saat berhasil,
  /// supaya tidak ada pesan basi yang menunggu untuk salah dipakai.
  Future<bool> updateComplaintStatus(int id, {required String status, String? response}) async {
    final resp = await ApiService.put(
      ApiConstants.complaintStatus(id),
      body: {'status': status, if (response != null) 'response': response},
    );
    if (resp['success'] == true) {
      _errorMessage = null;
      await fetchComplaints();
      return true;
    }
    _errorMessage = resp['message'] as String?;
    notifyListeners();
    return false;
  }

  Future<bool> deleteComplaint(int id) async {
    final response = await ApiService.delete('${ApiConstants.complaints}/$id');
    if (response['success'] == true) {
      await fetchComplaints();
      return true;
    }
    return false;
  }

  /// Pasang daftar langsung, tanpa jaringan — **hanya untuk pengujian.**
  ///
  /// Layar Pengaduan hanya menggambar tombol aksinya bila ada baris data, dan
  /// dialog Tanggapi hanya bisa dibuka lewat tombol itu. Tanpa jalur ini, uji
  /// widget selamanya melihat tabel kosong — yaitu satu-satunya keadaan yang
  /// tidak punya dialog untuk diuji.
  ///
  /// Bukan sumber kebenaran kedua: tidak ada kode produksi yang memanggilnya,
  /// dan pengambilan data berikutnya menimpanya.
  @visibleForTesting
  void pasangUji(List<Map<String, dynamic>> daftar, {String? galat}) {
    _complaints = daftar;
    _totalData = daftar.length;
    _totalPages = 1;
    _currentPage = 1;
    _isLoading = false;
    _errorMessage = galat;
    notifyListeners();
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  void bersihkan() {
    _complaints = [];
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    notifyListeners();
  }

}
