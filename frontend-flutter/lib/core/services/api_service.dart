import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String? _token;
  static const int _timeoutSeconds = 10;
  static const int _maxRetries = 2;

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
  }

  static String? get token => _token;

  static Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    // ngrok paket gratis menyisipkan halaman peringatan HTML untuk
    // permintaan yang dianggap berasal dari browser. Tanpa header ini,
    // aplikasi menerima HTML itu alih-alih JSON dan setiap panggilan
    // gagal dengan pesan yang membingungkan. Header ini diabaikan begitu
    // saja oleh server lain, jadi aman dikirim selalu.
    'ngrok-skip-browser-warning': 'true',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Helper: jalankan request dengan retry otomatis
  static Future<http.Response> _withRetry(Future<http.Response> Function() requestFn) async {
    http.Response? lastResponse;
    Object? lastError;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        lastResponse = await requestFn().timeout(const Duration(seconds: _timeoutSeconds));
        // Jika berhasil mendapat response (bukan network error), langsung return
        return lastResponse;
      } catch (e) {
        lastError = e;
        if (attempt < _maxRetries) {
          // Tunggu sebentar sebelum retry (exponential backoff)
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
    // Jika semua retry gagal, throw error terakhir
    throw lastError!;
  }

  static Future<Map<String, dynamic>> get(String url, {Map<String, String>? queryParams}) async {
    try {
      Uri uri = Uri.parse(url);
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _withRetry(() => http.get(uri, headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, penandaOffline: true, 'message': 'Gagal terhubung ke server: $e'};
    }
  }

  static Future<Map<String, dynamic>> post(String url, {Map<String, dynamic>? body}) async {
    try {
      final response = await _withRetry(
        () => http.post(
          Uri.parse(url),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        ),
      );
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, penandaOffline: true, 'message': 'Gagal terhubung ke server: $e'};
    }
  }

  static Future<Map<String, dynamic>> put(String url, {Map<String, dynamic>? body}) async {
    try {
      final response = await _withRetry(
        () => http.put(
          Uri.parse(url),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        ),
      );
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, penandaOffline: true, 'message': 'Gagal terhubung ke server: $e'};
    }
  }

  static Future<Map<String, dynamic>> delete(String url) async {
    try {
      final response = await _withRetry(() => http.delete(Uri.parse(url), headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, penandaOffline: true, 'message': 'Gagal terhubung ke server: $e'};
    }
  }

  /// Ditambahkan pada jawaban ketika server sama sekali tidak terjangkau.
  ///
  /// Membedakan "tidak bisa menghubungi server" dari "server menolak" itu
  /// penting: keduanya sama-sama `success: false`, dan tanpa penanda ini
  /// pemanggil tidak bisa tahu bedanya. [AuthService.tryAutoLogin] dulu
  /// menganggap keduanya sama lalu menghapus token pengguna hanya karena
  /// backend kebetulan belum hidup saat aplikasi dibuka.
  static const String penandaOffline = 'offline';

  static Map<String, dynamic> _handleResponse(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // Kode status disertakan supaya pemanggil bisa membedakan 401 (token
      // memang tidak berlaku) dari 500 atau 502 (server bermasalah, tetapi
      // sesi penggunanya masih sah).
      body['statusCode'] ??= response.statusCode;
      return body;
    } catch (e) {
      // Jawaban bukan JSON. Penyebab paling sering saat memakai tunnel adalah
      // halaman peringatan ngrok, dan pesan "response tidak valid" saja
      // membuat penyebabnya sulit ditebak — jadi disebutkan langsung.
      final isi = response.body.trimLeft().toLowerCase();
      if (isi.startsWith('<!doctype html') || isi.startsWith('<html')) {
        return {
          'success': false,
          'message':
              'Server membalas halaman HTML, bukan data. '
              'Bila memakai ngrok, pastikan alamatnya masih aktif dan benar '
              '(status: ${response.statusCode}).',
        };
      }
      return {'success': false, 'message': 'Response tidak valid (status: ${response.statusCode})'};
    }
  }
}
