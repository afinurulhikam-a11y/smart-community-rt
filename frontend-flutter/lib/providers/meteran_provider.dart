import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/meteran_model.dart';

/// Bacaan meteran air — dua sisi, satu provider.
///
/// [saya] adalah keadaan periode berjalan milik warga yang sedang masuk;
/// [list] adalah daftar seluruh rumah yang dilihat pengurus. Keduanya di sini
/// karena keduanya membaca tabel yang sama dan harus segar bersamaan: pengurus
/// yang mengoreksi bacaan warga harus melihat perubahannya di kedua tempat.
///
/// Backend yang menyempitkan `GET /meteran` untuk warga, bukan layar. Jadi
/// [muatDaftar] aman dipanggil peran apa pun — warga hanya menerima barisnya
/// sendiri.
class MeteranProvider extends ChangeNotifier {
  MeteranSaya? _saya;
  List<MeteranModel> _list = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _offline = false;

  MeteranSaya? get saya => _saya;
  List<MeteranModel> get list => _list;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Benar bila kegagalan terakhir karena server tak terjangkau, bukan ditolak.
  bool get offline => _offline;

  /// Rumah yang bacaannya perlu diperiksa pengurus.
  List<MeteranModel> get anomali => _list.where((e) => e.anomali).toList();

  /// GET /meteran/saya — keadaan periode berjalan warga.
  ///
  /// Akun tanpa kartu keluarga menerima 404, dan itu bukan galat sistem:
  /// pesannya disimpan apa adanya supaya layar bisa menjelaskan keadaannya
  /// alih-alih menampilkan daftar kosong yang terlihat seperti "belum ada
  /// tagihan".
  Future<void> muatSaya({String? periode}) async {
    _isLoading = true;
    notifyListeners();

    final url = periode == null
        ? ApiConstants.meteranSaya
        : '${ApiConstants.meteranSaya}?periode=$periode';
    final response = await ApiService.get(url);

    _isLoading = false;
    if (response['success'] == true) {
      final data = response['data'] as Map<String, dynamic>?;
      _saya = data == null ? null : MeteranSaya.fromJson(data);
      _errorMessage = null;
      _offline = false;
    } else {
      _offline = response[ApiService.penandaOffline] == true;
      _errorMessage = response['message'] as String?;
      // Server yang MENJAWAB dan menolak (404 "belum tertaut ke kartu
      // keluarga") memang harus mengosongkan kartunya — itu jawaban, bukan
      // kegagalan. Server yang TIDAK TERJANGKAU tidak menjawab apa pun, jadi
      // angka meteran yang sudah ada di layar dipertahankan; menghapusnya
      // berarti sinyal yang putus sesaat menghilangkan data yang benar dan
      // menggantinya dengan kalimat yang menyatakan data itu tidak ada.
      //
      // `penandaOffline` adalah satu-satunya yang membedakan keduanya:
      // `ApiService` tidak pernah melempar, jadi backend mati dan token
      // ditolak sama-sama datang sebagai `success: false`.
      if (!_offline) _saya = null;
    }
    notifyListeners();
  }

  /// GET /meteran — daftar bacaan. Pengurus: semua rumah; warga: miliknya.
  Future<void> muatDaftar({String? periode, String? status}) async {
    _isLoading = true;
    notifyListeners();

    final params = <String>[
      if (periode != null && periode.isNotEmpty) 'periode=$periode',
      if (status != null && status.isNotEmpty) 'status=$status',
    ];
    final url = params.isEmpty
        ? ApiConstants.meteran
        : '${ApiConstants.meteran}?${params.join('&')}';
    final response = await ApiService.get(url);

    _isLoading = false;
    if (response['success'] == true) {
      _list = (response['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MeteranModel.fromJson)
          .toList();
      _errorMessage = null;
      _offline = false;
    } else {
      _offline = response[ApiService.penandaOffline] == true;
      _errorMessage = response['message'] as String?;
    }
    notifyListeners();
  }

  /// POST /meteran — warga mengisi meteran periode berjalan.
  ///
  /// [meteranLalu] hanya dipakai server pada periode pertama. Sejak periode
  /// kedua server mengambilnya sendiri dari bacaan sebelumnya dan mengabaikan
  /// kiriman ini — jadi layar boleh mengirimnya tanpa risiko, dan warga tidak
  /// bisa menurunkan tagihannya dengan mengarang angka pembanding.
  ///
  /// Mengembalikan respons mentah supaya layar bisa membedakan tersimpan biasa
  /// dari tersimpan-tetapi-anomali; keduanya `success: true` dengan pesan yang
  /// berbeda.
  Future<Map<String, dynamic>> isi({
    required int meteranSekarang,
    int? meteranLalu,
  }) async {
    final response = await ApiService.post(
      ApiConstants.meteran,
      body: {
        'meteran_sekarang': meteranSekarang,
        if (meteranLalu != null) 'meteran_lalu': meteranLalu,
      },
    );
    if (response['success'] == true) await muatSaya();
    return response;
  }

  /// PUT /meteran/:id/koreksi — pengurus mengoreksi, dengan alasan.
  ///
  /// [alasan] wajib dan tidak diberi nilai bawaan di sini. Koreksi mengubah
  /// berapa yang harus dibayar warga, dan alasan bawaan seperti "koreksi" akan
  /// membuat jejak audit terlihat lengkap sambil tidak mengatakan apa pun.
  Future<Map<String, dynamic>> koreksi(
    String id, {
    required String alasan,
    int? meteranLalu,
    int? meteranSekarang,
    int? keluargaId,
    String? periode,
  }) async {
    final response = await ApiService.put(
      ApiConstants.meteranKoreksi(id),
      body: {
        'alasan': alasan,
        if (meteranLalu != null) 'meteran_lalu': meteranLalu,
        if (meteranSekarang != null) 'meteran_sekarang': meteranSekarang,
        if (keluargaId != null && keluargaId > 0) 'keluarga_id': keluargaId,
        if (periode != null && periode.isNotEmpty) 'periode': periode,
      },
    );
    if (response['success'] == true) await muatDaftar();
    return response;
  }

  /// PUT /bills/langganan-sampah — warga menyalakan/mematikan layanan sampah.
  ///
  /// Batas tanggalnya sama dengan input meteran, dan itu disengaja: satu
  /// tanggal untuk diingat, bukan dua. Tanpa batas, warga bisa mematikannya
  /// tanggal 24 lalu menyalakannya lagi tanggal 26 dan melewati biayanya.
  Future<Map<String, dynamic>> ubahLanggananSampah(bool berlangganan) async {
    final response = await ApiService.put(
      ApiConstants.langgananSampah,
      body: {'langganan_sampah': berlangganan},
    );
    if (response['success'] == true) await muatSaya();
    return response;
  }

  /// Pasang keadaan langsung, tanpa jaringan — **hanya untuk pengujian.**
  ///
  /// Kartu meteran punya enam tampilan yang berbeda dan lima di antaranya
  /// hanya muncul pada kombinasi tanggal dan isi tabel tertentu. Tanpa jalur
  /// ini, uji widget hanya pernah melihat keadaan "belum ada data" — persis
  /// tampilan yang paling tidak menarik untuk diuji, dan cacat tata letak di
  /// lima keadaan lainnya lolos begitu saja.
  ///
  /// Ini bukan sumber kebenaran kedua: tidak ada kode produksi yang
  /// memanggilnya, dan panggilan jaringan berikutnya menimpanya.
  @visibleForTesting
  void pasangUji({MeteranSaya? saya, List<MeteranModel>? daftar, String? galat}) {
    if (saya != null) _saya = saya;
    if (daftar != null) _list = daftar;
    if (galat != null) _errorMessage = galat;
    _isLoading = false;
    notifyListeners();
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider ini hidup selama proses berjalan di MultiProvider akar. Tanpa
  /// ini, bacaan meteran pengguna sebelumnya masih ada di memori saat orang
  /// lain masuk — dan angka meteran rumah adalah data rumah tangga orang.
  void bersihkan() {
    _saya = null;
    _list = [];
    _isLoading = false;
    _errorMessage = null;
    _offline = false;
    notifyListeners();
  }
}
