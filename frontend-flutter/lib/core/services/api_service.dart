import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';
import 'cache_lokal.dart';
import 'antrean_offline.dart';

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

  /// Penanda bahwa jawaban ini berasal dari penyimpanan lokal, bukan server.
  ///
  /// Layar WAJIB menampilkannya bersama [penandaWaktuCache]. Data lama yang
  /// disajikan seolah baru lebih berbahaya daripada layar kosong: seorang
  /// pengurus bisa menyimpulkan iuran belum dibayar padahal pembayarannya
  /// sudah masuk sejam lalu.
  static const String penandaCache = 'dariCache';
  static const String penandaWaktuCache = 'waktuCache';

  /// GET dengan cache baca-tembus opsional.
  ///
  /// Dengan `cache: true`:
  ///   - jawaban server yang berhasil ikut disimpan ke penyimpanan lokal;
  ///   - bila server tidak terjangkau, jawaban tersimpan terakhir dikembalikan
  ///     dengan [penandaCache] dan [penandaWaktuCache] terpasang.
  ///
  /// Cache TIDAK dipakai ketika server menjawab tetapi menolak (401/403/404).
  /// Penolakan adalah jawaban yang sah dan harus diteruskan apa adanya —
  /// menutupinya dengan data lama akan menyembunyikan pencabutan akses, dan
  /// membuat seseorang yang baru saja dinonaktifkan tetap melihat isinya.
  static Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? queryParams,
    bool cache = false,
  }) async {
    Uri uri = Uri.parse(url);
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }

    try {
      final response = await _withRetry(() => http.get(uri, headers: _headers));
      final hasil = _handleResponse(response);

      if (cache && hasil['success'] == true) {
        // Tidak ditunggu: menyimpan cache tidak boleh menambah waktu tunggu
        // pengguna atas data yang sudah ada di tangan.
        unawaited(CacheLokal.simpan(uri.toString(), hasil));
      }
      return hasil;
    } catch (e) {
      if (cache) {
        final tersimpan = await CacheLokal.ambil(uri.toString());
        if (tersimpan != null) {
          return {
            ...tersimpan.isi,
            penandaCache: true,
            penandaWaktuCache: tersimpan.waktu.toIso8601String(),
          };
        }
      }
      return {'success': false, penandaOffline: true, 'message': 'Gagal terhubung ke server: $e'};
    }
  }

  /// Penanda bahwa permintaan disimpan ke antrean, bukan terkirim.
  static const String penandaDiantre = 'diantre';

  /// POST, dengan antrean offline opsional.
  ///
  /// `judulAntrean` yang tidak null berarti pemanggil MENYATAKAN permintaan ini
  /// aman ditunda. Sengaja harus disebutkan di tempat pemanggilan, bukan
  /// disimpulkan sendiri di sini: keputusan "boleh terkirim tiga jam kemudian"
  /// adalah keputusan domain, bukan keputusan lapisan jaringan. Lihat
  /// AntreanOffline untuk alasan mengapa uang dan alarm tidak pernah diantre.
  static Future<Map<String, dynamic>> post(
    String url, {
    Map<String, dynamic>? body,
    String? judulAntrean,
  }) async {
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
      if (judulAntrean != null && AntreanOffline.bolehDiantre(url, 'POST')) {
        final masuk = await AntreanOffline.tambah(
          metode: 'POST',
          endpoint: url,
          body: body ?? {},
          judul: judulAntrean,
        );
        if (masuk) {
          // `success: true` DISENGAJA. Dari sudut pandang pengguna permintaannya
          // memang sudah diterima — tersimpan dan pasti dikirim. Mengembalikan
          // kegagalan akan membuat layar menyuruh mencoba lagi, dan percobaan
          // itu menghasilkan pengaduan kedua yang sama persis.
          return {
            'success': true,
            penandaDiantre: true,
            'message': 'Tidak ada koneksi. Tersimpan dan akan dikirim otomatis '
                'begitu jaringan tersedia.',
          };
        }
      }
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

  /// Membuka sebuah unduhan tanpa pernah menaruh token sesi di URL.
  ///
  /// Tombol Export dulu menyusun `.../export?token=<jwt>` lalu menyerahkannya ke
  /// [launchUrl]. Itu satu-satunya cara yang tersedia — sebuah NAVIGASI TIDAK
  /// BISA MEMBAWA HEADER, jadi `Authorization` bukan pilihan. Harganya: token
  /// berumur 24 jam ikut tercatat di log akses server dan setiap proxy di
  /// jalurnya, di riwayat browser, dan di header `Referer`.
  ///
  /// Sekarang aplikasi menukar sesinya dulu menjadi tiket: nilai acak berumur
  /// 60 detik, sekali pakai, yang hanya membuka satu unduhan tertentu dan mati
  /// begitu pemiliknya menekan Keluar. Yang bocor ke log menjadi tiket mati,
  /// bukan sesi.
  ///
  /// [parameter] berisi filter yang biasanya menjadi query string — server
  /// menyimpannya bersama tiket, sehingga URL yang akhirnya dibuka tidak
  /// memuat apa pun selain tiketnya.
  ///
  /// Mengembalikan `{'success': bool, 'message': String?}` mengikuti amplop
  /// yang sama seperti [get]/[post]; ia tidak pernah melempar.
  static Future<Map<String, dynamic>> unduhDenganTiket(
    String jenis, {
    Map<String, dynamic> parameter = const {},
  }) async {
    // Nilai null dibuang, bukan dikirim: server menyimpan parameter apa adanya
    // dan meneruskannya sebagai query, sedangkan filter yang tidak dipilih
    // memang tidak boleh ikut.
    final bersih = <String, dynamic>{
      for (final e in parameter.entries)
        if (e.value != null && e.value != '') e.key: e.value,
    };

    final hasil = await post(ApiConstants.unduhTiket, body: {
      'jenis': jenis,
      'parameter': bersih,
    });

    if (hasil['success'] != true) return hasil;

    final tiket = hasil['data']?['tiket'] as String?;
    if (tiket == null) {
      return {'success': false, 'message': 'Server tidak mengembalikan tiket unduhan.'};
    }

    final uri = Uri.parse(ApiConstants.unduh(tiket));
    // `_self` supaya berkas turun di tab yang sama dan tidak meninggalkan tab
    // kosong — jawaban server adalah lampiran, jadi halamannya tidak berpindah.
    final terbuka = await launchUrl(uri, webOnlyWindowName: '_self');
    if (!terbuka) {
      return {'success': false, 'message': 'Tidak dapat membuka tautan unduhan.'};
    }
    return {'success': true};
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
