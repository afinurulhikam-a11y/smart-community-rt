import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'api_service.dart';

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
  int get userId => _user?['id'] ?? 0;

  /// Role yang diterima endpoint berpenjaga `roleGuard('admin', 'pengurus_rt')`.
  ///
  /// Cermin dari `auth.middleware.js`: middleware di backend memperluas
  /// 'pengurus_rt' menjadi ketua_rt, sekretaris, dan bendahara. Efektifnya
  /// semua role kecuali 'warga'. Bila daftar di backend berubah, ubah di sini.
  static const Set<String> _rolePengurus = {
    'admin',
    'pengurus_rt',
    'ketua_rt',
    'sekretaris',
    'bendahara',
  };

  /// True bila user berhak mengakses endpoint khusus pengurus. Dipakai untuk
  /// tidak menembakkan request yang sudah pasti ditolak 403.
  bool get isPengurus => _rolePengurus.contains(userRole);

  String get userRoleLabel {
    switch (userRole) {
      case 'admin':
        return 'Administrator';
      case 'pengurus_rt':
        return 'Pengurus RT';
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
        await prefs.setString('user_data', jsonEncode(_user));
        notifyListeners();
        return;
      }
      final status = response['statusCode'];
      if (status == 401 || status == 403) {
        await logout();
      }
    } catch (_) {
      // Diabaikan dengan sengaja: sesi dari cache tetap berlaku.
    }
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
      await prefs.setString('user_data', jsonEncode(_user));
      _errorMessage = null;
      notifyListeners();
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
      await prefs.setString('user_data', jsonEncode(_user));
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
      final updatedUser = response['data'] as Map<String, dynamic>;
      _user = {...?_user, ...updatedUser};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(_user));
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String? ?? 'Gagal memperbarui profil';
      notifyListeners();
      return false;
    }
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
        await prefs.setString('user_data', jsonEncode(_user));
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

  Future<void> logout() async {
    _user = null;
    _errorMessage = null;
    await ApiService.clearToken();
    notifyListeners();
  }
}
