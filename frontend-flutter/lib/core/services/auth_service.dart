import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../peran.dart';
import 'api_service.dart';
import 'fcm_service.dart';

class AuthService extends ChangeNotifier {
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get errorMessage => _errorMessage;
  String get userRole => _user?['role'] ?? '';
  String get userName => _user?['nama'] ?? '';
  String get userId => _user?['id']?.toString() ?? '';

  /// True bila user berhak mengakses endpoint khusus pengurus. Dipakai untuk
  /// tidak menembakkan request yang sudah pasti ditolak 403.
  ///
  /// Daftarnya ada di `Peran.pengurus`, bukan di sini. Salinan lokalnya dulu
  /// melewatkan `ketua_rw`, dan akibatnya halus: layar yang memakai penjaga
  /// ini membiarkan dirinya kosong tanpa pernah bertanya ke server, padahal
  /// Ketua RW memegang izin lihat pada hampir seluruh modul.
  bool get isPengurus => Peran.pengurus.contains(userRole);

  String get userRoleLabel {
    switch (userRole) {
      case 'admin':
        return 'Administrator';
      case 'pengurus_rt':
        return 'Pengurus RT';
      case 'ketua_rw':
        return 'Ketua RW';
      case 'ketua_rt':
        return 'Ketua RT';
      case 'sekretaris':
        return 'Sekretaris';
      case 'bendahara':
        return 'Bendahara';
      case 'warga':
        return 'Warga';
      default:
        return userRole;
    }
  }

  /// Memulihkan sesi yang tersimpan saat aplikasi dibuka.
  ///
  /// Pengguna HANYA dikeluarkan bila server benar-benar menolak tokennya
  /// (401/403). Sebelumnya jawaban apa pun yang bukan `success` dianggap
  /// penolakan — padahal `ApiService` tidak pernah melempar galat dan
  /// mengembalikan `success: false` juga ketika server tidak terjangkau.
  ///
  /// Akibatnya: cukup backend belum hidup, ngrok belum tersambung, atau
  /// ponsel belum dapat Wi-Fi pada detik aplikasi dibuka — token pengguna
  /// terhapus, dan tiap kali membuka aplikasi ia disodori layar masuk lagi.
  ///
  /// Bila server tidak terjangkau, sesi dari cache tetap dipakai. Permintaan
  /// berikutnya yang benar-benar butuh server akan gagal dengan pesannya
  /// sendiri — itu jauh lebih jelas daripada dipaksa masuk ulang tanpa
  /// keterangan apa pun.
  Future<bool> tryAutoLogin() async {
    await ApiService.loadToken();
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData == null) return false;

    try {
      _user = jsonDecode(userData) as Map<String, dynamic>;
    } catch (_) {
      // Data tersimpan rusak — perlakukan seperti belum pernah masuk.
      return false;
    }
    notifyListeners();

    // Pemeriksaan ke server dijalankan DI LATAR, tidak ditunggu.
    //
    // Ditunggu, layar splash tertahan selama pemeriksaan itu berlangsung — dan
    // ApiService mencoba tiga kali dengan batas 10 detik ditambah jeda mundur,
    // jadi hingga 31 detik bila server tidak terjangkau. Ditambah `izin.muat()`
    // sesudahnya, aplikasi bisa diam hampir satu menit tanpa satu pun tanda
    // bahwa ia masih hidup.
    //
    // Sesi dari cache sudah cukup untuk membuka aplikasi; hasil pemeriksaannya
    // baru berpengaruh bila server benar-benar MENOLAK token.
    unawaited(_periksaSesiDiLatar(prefs));
    unawaited(FCMService.instance.sinkronkanTokenKeBackend());
    return true;
  }

  /// Memastikan token masih diterima server, tanpa menahan tampilan.
  ///
  /// Hanya penolakan tegas (401/403) yang mengeluarkan pengguna. Server mati,
  /// 500, atau tidak terjangkau dibiarkan — token pengguna tidak ada
  /// hubungannya dengan itu.
  Future<void> _periksaSesiDiLatar(SharedPreferences prefs) async {
    try {
      final response = await ApiService.get(ApiConstants.me);
      if (response['success'] == true) {
        _user = response['data'] as Map<String, dynamic>;
        await _simpanProfil(prefs);
        notifyListeners();
        return;
      }
      final status = response['statusCode'];
      if (status == 401 || status == 403) {
        // `panggilServer: false` — sesinya memang sudah ditolak server, jadi
        // memanggil /auth/logout hanya akan ditolak lagi. Yang dibutuhkan di
        // sini hanya membersihkan sisa sesi di perangkat ini.
        await logout(panggilServer: false);
      }
    } catch (_) {
      // Diabaikan dengan sengaja: sesi dari cache tetap berlaku.
    }
  }

  /// Satu-satunya field identitas yang boleh mendarat di penyimpanan perangkat.
  ///
  /// Di Web, `SharedPreferences` **adalah** `localStorage` — terbaca skrip mana
  /// pun di origin itu. Yang dulu tersimpan di sana adalah baris `users` hampir
  /// utuh: `nik`, `no_kk`, `no_hp`, `alamat`, `email`. NIK dan nomor KK dijaga
  /// ketat di sisi backend proyek ini, lalu tergeletak terbuka di sisi klien.
  static const _fieldProfilRingkas = {
    'id', 'nama', 'role', 'username', 'must_change_password',
  };

  /// Tulis identitas ke penyimpanan — SATU-SATUNYA jalan menuju `user_data`.
  ///
  /// Penyaringnya ada di sini, di perbatasan penyimpanan, bukan di setiap
  /// pemanggil. `updateProfile` mengembalikan baris lengkap dan dulu digabungkan
  /// apa adanya ke `_user`, sehingga PII masuk kembali lewat pintu belakang
  /// walau `/auth/me` sudah dirampingkan. Dengan penyaring di titik ini,
  /// endpoint baru yang kelak mengembalikan lebih banyak field tidak bisa
  /// membocorkannya tanpa seseorang mengubah baris ini lebih dulu.
  Future<void> _simpanProfil(SharedPreferences prefs) async {
    final ringkas = <String, dynamic>{
      for (final e in (_user ?? {}).entries)
        if (_fieldProfilRingkas.contains(e.key)) e.key: e.value,
    };
    _user = ringkas;
    await prefs.setString('user_data', jsonEncode(ringkas));
  }

  /// Profil lengkap — di MEMORI saja, tidak pernah disimpan.
  ///
  /// Hidup selama layar Profil Saya terbuka, lalu ikut hilang saat proses
  /// berakhir. Sengaja tidak punya jalur persistensi sama sekali.
  Map<String, dynamic>? _profilLengkap;
  Map<String, dynamic>? get profilLengkap => _profilLengkap;

  /// Ambil profil lengkap dari `/auth/profil` untuk layar Profil Saya.
  Future<Map<String, dynamic>?> muatProfilLengkap() async {
    final response = await ApiService.get(ApiConstants.authProfil);
    if (response['success'] == true && response['data'] != null) {
      _profilLengkap = Map<String, dynamic>.from(response['data'] as Map);
      notifyListeners();
      return _profilLengkap;
    }
    _errorMessage = response['message'] as String?;
    return null;
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.login,
      body: {'email': email, 'password': password},
    );
    _isLoading = false;
    if (response['success'] == true) {
      final data = response['data'] as Map<String, dynamic>;
      _user = data['user'] as Map<String, dynamic>;
      await ApiService.saveToken(data['token'] as String);
      final prefs = await SharedPreferences.getInstance();
      await _simpanProfil(prefs);
      _errorMessage = null;
      notifyListeners();
      unawaited(FCMService.instance.sinkronkanTokenKeBackend());
      return true;
    } else {
      _errorMessage = response['message'] as String? ?? 'Login gagal';
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String nama,
    required String email,
    required String password,
    String? noHp,
    String? alamat,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.register,
      body: {
        'nama': nama,
        'email': email,
        'password': password,
        if (noHp != null) 'no_hp': noHp,
        if (alamat != null) 'alamat': alamat,
      },
    );
    _isLoading = false;
    if (response['success'] == true) {
      final data = response['data'] as Map<String, dynamic>;
      _user = data['user'] as Map<String, dynamic>;
      await ApiService.saveToken(data['token'] as String);
      final prefs = await SharedPreferences.getInstance();
      await _simpanProfil(prefs);
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String? ?? 'Registrasi gagal';
      notifyListeners();
      return false;
    }
  }



  Future<bool> updateProfile({
    required String nama,
    String? email,
    String? noHp,
    String? username,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final body = <String, dynamic>{
      'nama': nama,
      if (email != null && email.isNotEmpty) 'email': email,
      if (noHp != null && noHp.isNotEmpty) 'no_hp': noHp,
      if (username != null && username.isNotEmpty) 'username': username,
    };

    final response = await ApiService.put(ApiConstants.updateProfile, body: body);
    _isLoading = false;

    if (response['success'] == true) {
      await terapkanProfilTerbaru(response['data'] as Map<String, dynamic>);
      _errorMessage = null;
      return true;
    } else {
      _errorMessage = response['message'] as String? ?? 'Gagal memperbarui profil';
      notifyListeners();
      return false;
    }
  }

  /// Selaraskan KEDUA salinan identitas setelah profil berhasil disimpan.
  ///
  /// Dipisahkan menjadi metode sendiri karena inilah bagian yang pernah salah,
  /// dan `updateProfile` di atas memanggil `ApiService` statis yang tidak punya
  /// seam — tanpa pemisahan ini, sinkronisasinya tidak bisa diuji tanpa
  /// jaringan.
  ///
  /// Cacat yang diperbaiki: sebelumnya hanya `_user` yang disegarkan, sementara
  /// `_profilLengkap` dibiarkan memegang nilai sebelum penyuntingan. Layar
  /// Profil Saya membaca email dan nomor HP dari `_profilLengkap`, sehingga
  /// pengguna melihat pesan "Profil berhasil diperbarui!" sambil kartunya masih
  /// menampilkan data lama — pesan sukses yang tampak berbohong. Namanya lebih
  /// buruk lagi: layar membacanya sebagai `lengkap['nama'] ?? ringkas['nama']`,
  /// dan karena nilai basi itu bukan null, operator `??` justru memenangkannya.
  ///
  /// Barisnya diambil dari respons PUT, bukan dengan memanggil `/auth/profil`
  /// lagi. Respons itu adalah keadaan sesudah tulis yang otoritatif, jadi
  /// permintaan kedua hanya menambah perjalanan jaringan untuk jawaban yang
  /// sudah ada di tangan. `/auth/profil` tetap satu-satunya sumber BACA — ia
  /// yang dipanggil saat layar dibuka.
  ///
  /// `_profilLengkap` hanya disegarkan bila memang sudah pernah dimuat. Bila
  /// belum, ia tetap null supaya pembukaan layar berikutnya mengambilnya utuh
  /// dari server, bukan menyusunnya dari potongan respons tulis.
  @visibleForTesting
  Future<void> terapkanProfilTerbaru(Map<String, dynamic> baris) async {
    _user = {...?_user, ...baris};
    // Menyaring `_user` kembali menjadi profil ringkas DAN menyimpannya.
    // Respons PUT membawa email, no_hp, no_kk, dan alamat; tanpa penyaring ini
    // semuanya akan mendarat di penyimpanan perangkat.
    await _simpanProfil(await SharedPreferences.getInstance());

    if (_profilLengkap != null) {
      _profilLengkap = {..._profilLengkap!, ...baris};
    }
    notifyListeners();
  }

  /// Pasang keadaan langsung, tanpa jaringan — **hanya untuk pengujian.**
  ///
  /// Layar Profil Saya hanya menampilkan email dan nomor HP setelah
  /// `/auth/profil` menjawab. Tanpa jalur ini, uji widget selamanya melihat
  /// keadaan "Memuat…" — satu-satunya tampilan yang tidak memuat data apa pun.
  @visibleForTesting
  void pasangUji({Map<String, dynamic>? user, Map<String, dynamic>? profilLengkap}) {
    if (user != null) _user = user;
    if (profilLengkap != null) _profilLengkap = profilLengkap;
    notifyListeners();
  }

  Future<bool> changePassword({required String oldPassword, required String newPassword}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final response = await ApiService.put(
      ApiConstants.changePassword,
      body: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
    _isLoading = false;

    if (response['success'] == true) {
      // Wajib ganti sandi sudah dipenuhi — lepas tandanya di memori lokal
      // agar AuthGate tidak menampilkan dialog itu lagi pada sesi ini.
      if (_user != null) {
        _user!['must_change_password'] = false;
        final prefs = await SharedPreferences.getInstance();
        await _simpanProfil(prefs);
      }
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String? ?? 'Gagal mengubah password';
      notifyListeners();
      return false;
    }
  }

  /// Keluar — DARI SEMUA PERANGKAT, bukan hanya perangkat ini.
  ///
  /// Server menaikkan `users.token_versi`, dan setiap token yang masih membawa
  /// versi lama langsung ditolak. Itu konsekuensi langsung dari rancangannya:
  /// versinya melekat pada PENGGUNA, bukan pada sesi. Layar Keluar wajib
  /// menyebutkannya — perilaku yang mengejutkan tanpa peringatan adalah cacat
  /// tersendiri, walau amannya benar.
  ///
  /// **Bila server tidak terjangkau, ini menjadi keluar LOKAL saja.** Token dan
  /// `user_data` tetap dihapus dari perangkat ini, tetapi `token_versi` tidak
  /// naik dan sesi di perangkat lain tetap hidup sampai kedaluwarsa alaminya.
  /// Penyimpanan lokal dibersihkan apa pun yang terjadi: seseorang yang menekan
  /// Keluar tidak boleh terjebak masih berada di dalam aplikasi.
  ///
  /// Sengaja TIDAK diantrekan lewat `AntreanOffline`, walau mekanismenya ada.
  /// Alasannya makna, bukan mekanis: seseorang bisa menekan Keluar pukul 10.00
  /// saat offline, masuk lagi pukul 10.05, lalu antreannya terkirim pukul
  /// 10.10 — dan pencabutan yang tertunda itu akan membunuh sesi baru yang sah.
  ///
  /// [panggilServer] hanya disetel `false` pada jalur di mana server sudah
  /// menolak sesinya (401/403); memanggilnya di sana hanya akan ditolak lagi.
  Future<void> logout({bool panggilServer = true}) async {
    if (panggilServer) {
      // Cabut token FCM perangkat ini dari backend sebelum sesi dibersihkan
      unawaited(FCMService.instance.cabutTokenDariBackend());
      // Hasilnya sengaja tidak diperiksa. Berhasil atau gagal, langkah
      // berikutnya sama: bersihkan perangkat ini.
      await ApiService.post(ApiConstants.logout, body: {});
    } else {
      FCMService.instance.resetTokenLokal();
    }
    _user = null;
    // Profil lengkap ikut dibuang. Ia hanya di memori, tetapi provider ini hidup
    // selama proses berjalan di MultiProvider akar — dan perangkat di sini
    // dipakai pengurus bergantian. Menyisakannya berarti NIK dan alamat orang
    // sebelumnya masih ada di memori saat orang lain masuk.
    _profilLengkap = null;
    _errorMessage = null;
    await ApiService.clearToken();
    notifyListeners();
  }
}
