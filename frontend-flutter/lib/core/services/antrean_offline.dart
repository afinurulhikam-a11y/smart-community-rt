import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Satu permintaan tulis yang menunggu jaringan.
class TulisanTertunda {
  const TulisanTertunda({
    required this.id,
    required this.metode,
    required this.endpoint,
    required this.body,
    required this.dibuatPada,
    required this.judul,
  });

  final int id;
  final String metode;
  final String endpoint;
  final Map<String, dynamic> body;
  final DateTime dibuatPada;

  /// Kalimat yang bisa dibaca pengguna, mis. "Pengaduan: Lampu jalan mati".
  final String judul;
}

/// Antrean permintaan tulis yang dibuat saat perangkat tidak terhubung.
///
/// ===================================================================
/// Kenapa hanya sebagian jenis tulisan yang boleh diantre
/// ===================================================================
///
/// Sebelumnya tidak ada antrean sama sekali. `ApiService` mengulang dua kali
/// dalam hitungan detik, lalu menyerah; permintaannya hilang dan pengguna harus
/// mengingat sendiri untuk mengulang nanti. Untuk warga yang mengetik pengaduan
/// panjang di daerah tanpa sinyal, itu berarti pekerjaannya lenyap.
///
/// Tetapi TIDAK semua tulisan pantas diantre. Yang menyangkut uang dan
/// keputusan tidak boleh: melunasi tagihan, memicu alarm darurat, menyetujui
/// peminjaman, mengubah izin. Alasannya bukan teknis melainkan soal makna —
/// sebuah tindakan yang dikirim tiga jam kemudian, dalam keadaan yang mungkin
/// sudah berubah, bukan lagi tindakan yang sama. Alarm darurat yang menyala
/// tiga jam setelah ditekan justru berbahaya, dan pelunasan yang dikirim ulang
/// diam-diam bertabrakan dengan pembayaran yang barangkali sudah dicatat lewat
/// jalur lain.
///
/// Yang boleh diantre hanyalah pengajuan yang menunggu ditinjau manusia dan
/// tidak mengubah apa pun seketika: pengaduan dan permohonan surat. Keduanya
/// memang berjalan dalam hitungan hari, jadi selisih beberapa menit tidak
/// mengubah artinya.
class AntreanOffline {
  static Database? _db;

  static bool get _didukung => !kIsWeb;

  /// Endpoint yang boleh diantre. Sengaja daftar-izin, bukan daftar-larangan:
  /// endpoint baru tidak otomatis ikut, dan harus disebutkan dengan sadar.
  static const List<String> endpointBoleh = ['/complaints', '/letters'];

  static bool bolehDiantre(String endpoint, String metode) {
    if (metode.toUpperCase() != 'POST') return false;
    return endpointBoleh.any((e) => endpoint.endsWith(e));
  }

  static Future<Database?> _buka() async {
    if (!_didukung) return null;
    if (_db != null) return _db;

    // Dibungkus try: di lingkungan uji widget pluginnya tidak terpasang dan
    // getDatabasesPath melempar MissingPluginException. Cache yang tidak
    // tersedia bukan alasan untuk menjatuhkan aplikasi — ia memang lapisan
    // tambahan, bukan syarat.
    try {
      final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'antrean_rt.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE antrean (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            metode TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            body TEXT NOT NULL,
            judul TEXT NOT NULL,
            dibuat_pada INTEGER NOT NULL
          )
        ''');
      },
    );
      return _db;
    } catch (e) {
      debugPrint('Penyimpanan lokal tidak tersedia: $e');
      return null;
    }
  }

  static Future<bool> tambah({
    required String metode,
    required String endpoint,
    required Map<String, dynamic> body,
    required String judul,
  }) async {
    final db = await _buka();
    if (db == null) return false;
    try {
      await db.insert('antrean', {
        'metode': metode,
        'endpoint': endpoint,
        'body': jsonEncode(body),
        'judul': judul,
        'dibuat_pada': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      debugPrint('AntreanOffline.tambah gagal: $e');
      return false;
    }
  }

  static Future<List<TulisanTertunda>> daftar() async {
    final db = await _buka();
    if (db == null) return [];
    try {
      final baris = await db.query('antrean', orderBy: 'dibuat_pada ASC');
      return baris.map((b) => TulisanTertunda(
        id: b['id'] as int,
        metode: b['metode'] as String,
        endpoint: b['endpoint'] as String,
        body: jsonDecode(b['body'] as String) as Map<String, dynamic>,
        judul: b['judul'] as String,
        dibuatPada: DateTime.fromMillisecondsSinceEpoch(b['dibuat_pada'] as int),
      )).toList();
    } catch (e) {
      debugPrint('AntreanOffline.daftar gagal: $e');
      return [];
    }
  }

  static Future<void> hapus(int id) async {
    final db = await _buka();
    if (db == null) return;
    try {
      await db.delete('antrean', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('AntreanOffline.hapus gagal: $e');
    }
  }

  /// Dipanggil saat logout. Antrean milik satu pengguna tidak boleh terkirim
  /// atas nama pengguna berikutnya — tokennya sudah berbeda, dan pengaduan
  /// orang lain akan tercatat sebagai milik yang baru masuk.
  static Future<void> kosongkan() async {
    final db = await _buka();
    if (db == null) return;
    try {
      await db.delete('antrean');
    } catch (e) {
      debugPrint('AntreanOffline.kosongkan gagal: $e');
    }
  }
}
