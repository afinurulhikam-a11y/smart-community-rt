import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import '../core/services/antrean_offline.dart';
import '../core/services/api_service.dart';

/// Status koneksi perangkat, dan pengiriman ulang antrean tulis.
///
/// ===================================================================
/// Kenapa perlu memantau, bukan sekadar menunggu permintaan gagal
/// ===================================================================
///
/// Sebelum ini aplikasi sama sekali tidak tahu keadaan jaringan. Ia baru
/// menyadari ada masalah setelah sebuah permintaan gagal — dan itu memakan
/// waktu ~21 detik, karena `ApiService` mencoba ulang dua kali dengan batas
/// sepuluh detik. Selama itu pengguna melihat pemuatan yang tidak berujung
/// tanpa keterangan apa pun.
///
/// Yang lebih penting: tanpa pemantau, tidak ada momen yang bisa dijadikan
/// tanda "sekarang saatnya mengirim ulang". Antrean tulis hanya berguna kalau
/// ada yang memperhatikan kapan jaringan kembali.
///
/// ===================================================================
/// Terhubung ke Wi-Fi TIDAK sama dengan bisa menjangkau server
/// ===================================================================
///
/// `connectivity_plus` hanya melaporkan adanya antarmuka jaringan. Wi-Fi hotel
/// dengan halaman login, Wi-Fi rumah dengan internet mati, atau backend yang
/// sedang redeploy semuanya tampak "terhubung". Karena itu status daring di
/// sini baru ditetapkan setelah `/api/health` benar-benar menjawab.
class KoneksiProvider extends ChangeNotifier {
  /// [pantau] dimatikan pada uji widget: berlangganan connectivity dan membuka
  /// SQLite menuntut plugin yang tidak ada di sana, dan langganan yang
  /// tertinggal membuat uji gagal karena "pending timers" alih-alih karena
  /// hal yang sedang diuji.
  KoneksiProvider({bool pantau = true}) {
    if (pantau) _mulaiPantau();
  }

  bool _daring = true;
  bool _sedangKirimUlang = false;
  int _tertunda = 0;
  StreamSubscription<List<ConnectivityResult>>? _langganan;

  /// Benar bila server terakhir kali terbukti bisa dijangkau.
  bool get daring => _daring;

  /// Jumlah tulisan yang menunggu jaringan.
  int get tertunda => _tertunda;

  bool get sedangKirimUlang => _sedangKirimUlang;

  void _mulaiPantau() {
    try {
      hitungTertunda();
      _langganan = Connectivity().onConnectivityChanged.listen((hasil) {
        final adaAntarmuka = hasil.any((r) => r != ConnectivityResult.none);
        if (!adaAntarmuka) {
          _setDaring(false);
          return;
        }
        // Ada antarmuka — belum tentu server terjangkau. Buktikan dulu.
        periksaServer();
      });
    } catch (e) {
      debugPrint('Pemantau koneksi tidak aktif: $e');
    }
  }

  /// Pastikan server benar-benar menjawab, lalu kirim ulang antrean bila iya.
  Future<void> periksaServer() async {
    try {
      final r = await http
          .get(Uri.parse('${ApiConstants.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      _setDaring(r.statusCode == 200);
    } catch (_) {
      _setDaring(false);
    }
    if (_daring) await kirimUlangAntrean();
  }

  void _setDaring(bool nilai) {
    if (_daring == nilai) return;
    _daring = nilai;
    notifyListeners();
  }

  Future<void> hitungTertunda() async {
    _tertunda = (await AntreanOffline.daftar()).length;
    notifyListeners();
  }

  /// Kirim ulang seluruh tulisan yang tertunda, berurutan.
  ///
  /// Berurutan, bukan serentak: dua pengaduan yang dikirim bersamaan bisa
  /// tercatat dengan urutan terbalik dari yang ditulis pengguna, dan pada
  /// jaringan yang baru pulih mengirim semuanya sekaligus justru paling
  /// mungkin gagal lagi.
  ///
  /// Sebuah entri hanya dihapus bila server BENAR-BENAR menerimanya. Kegagalan
  /// jaringan menyisakannya di antrean untuk percobaan berikutnya; penolakan
  /// dari server (data tidak valid, izin dicabut) juga menghapusnya, karena
  /// mengulanginya selamanya tidak akan pernah berhasil dan hanya membuat
  /// antrean tersumbat.
  Future<void> kirimUlangAntrean() async {
    if (_sedangKirimUlang) return;
    final daftar = await AntreanOffline.daftar();
    if (daftar.isEmpty) {
      _tertunda = 0;
      notifyListeners();
      return;
    }

    _sedangKirimUlang = true;
    notifyListeners();

    for (final t in daftar) {
      final hasil = await ApiService.post(t.endpoint, body: t.body);
      final gagalJaringan = hasil[ApiService.penandaOffline] == true;
      if (!gagalJaringan) {
        await AntreanOffline.hapus(t.id);
      }
    }

    _sedangKirimUlang = false;
    await hitungTertunda();
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  void bersihkan() {
    _tertunda = 0;
    _sedangKirimUlang = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _langganan?.cancel();
    super.dispose();
  }
}
