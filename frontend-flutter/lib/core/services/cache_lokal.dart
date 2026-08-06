import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Penyimpanan lokal untuk jawaban API yang terakhir berhasil diambil.
///
/// ===================================================================
/// Kenapa ada
/// ===================================================================
///
/// Sebelum ini aplikasi sama sekali tidak menyimpan data apa pun secara lokal.
/// `SharedPreferences` hanya memuat tiga kunci — token, identitas pengguna, dan
/// pilihan mode gelap — dan tidak satu pun daftar tagihan, kas, warga, atau
/// inventaris pernah bertahan melewati satu kali buka aplikasi.
///
/// Akibatnya sinyal yang hilang berarti layar kosong. Bukan "data kemarin",
/// bukan "sedang mencoba lagi" — kosong, dengan kalimat yang bahkan mengatakan
/// bahwa datanya memang belum ada. Untuk aplikasi RT yang dipakai di ponsel,
/// berpindah antara Wi-Fi rumah dan data seluler saja sudah cukup untuk
/// mengalaminya.
///
/// ===================================================================
/// Yang SENGAJA tidak dilakukan
/// ===================================================================
///
/// Ini cache BACA, bukan basis data kedua. Ia tidak pernah menjadi sumber
/// kebenaran: begitu jaringan tersedia, jawaban dari server selalu menang dan
/// menimpa isinya. Yang disimpan adalah badan respons apa adanya, tanpa
/// ditafsirkan — sehingga perubahan bentuk data di backend tidak bisa membuat
/// cache dan aplikasi berbeda pendapat tentang isinya.
///
/// Setiap baris menyimpan waktu pengambilannya, dan layar WAJIB menampilkannya
/// ketika menyajikan data tersimpan. Data lama yang ditampilkan sebagai data
/// baru lebih berbahaya daripada layar kosong — pengurus bisa menyimpulkan
/// iuran belum dibayar padahal pembayarannya sudah masuk sejam lalu.
///
/// Di Web ini tidak aktif: `sqflite` tidak punya implementasi di sana, dan
/// peramban sudah punya penyimpanannya sendiri. Semua fungsi di bawah menjadi
/// tanpa-efek, bukan gagal.
class CacheLokal {
  static Database? _db;

  /// Umur simpan. Setelah lewat ini barisnya dianggap tidak layak pakai lagi.
  ///
  /// Tujuh hari dipilih supaya seseorang yang membuka aplikasi setelah sepekan
  /// tanpa sinyal tetap melihat sesuatu, sementara data yang jauh lebih tua
  /// dari itu lebih mungkin menyesatkan daripada menolong.
  static const Duration umurMaksimum = Duration(days: 7);

  static bool get _didukung => !kIsWeb;

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
      p.join(dir, 'cache_rt.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cache_api (
            kunci TEXT PRIMARY KEY,
            isi TEXT NOT NULL,
            diambil_pada INTEGER NOT NULL
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

  /// Simpan badan respons untuk sebuah URL lengkap.
  static Future<void> simpan(String kunci, Map<String, dynamic> isi) async {
    final db = await _buka();
    if (db == null) return;
    try {
      await db.insert(
        'cache_api',
        {
          'kunci': kunci,
          'isi': jsonEncode(isi),
          'diambil_pada': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // Kegagalan menyimpan cache tidak boleh menjatuhkan permintaan yang
      // sebenarnya sudah berhasil. Diam-diam dilewati adalah perilaku yang
      // benar di sini — datanya sudah sampai ke pengguna.
      debugPrint('CacheLokal.simpan gagal: $e');
    }
  }

  /// Ambil jawaban tersimpan, atau null bila tidak ada / sudah kedaluwarsa.
  static Future<({Map<String, dynamic> isi, DateTime waktu})?> ambil(String kunci) async {
    final db = await _buka();
    if (db == null) return null;
    try {
      final baris = await db.query('cache_api', where: 'kunci = ?', whereArgs: [kunci], limit: 1);
      if (baris.isEmpty) return null;

      final waktu = DateTime.fromMillisecondsSinceEpoch(baris.first['diambil_pada'] as int);
      if (DateTime.now().difference(waktu) > umurMaksimum) return null;

      final isi = jsonDecode(baris.first['isi'] as String) as Map<String, dynamic>;
      return (isi: isi, waktu: waktu);
    } catch (e) {
      debugPrint('CacheLokal.ambil gagal: $e');
      return null;
    }
  }

  /// Kosongkan seluruh cache.
  ///
  /// Dipanggil saat logout. Tanpa ini, data pengguna sebelumnya tetap ada di
  /// penyimpanan perangkat dan bisa muncul kembali pada sesi berikutnya ketika
  /// jaringan sedang mati — tepat pada saat tidak ada apa pun yang menimpanya.
  static Future<void> kosongkan() async {
    final db = await _buka();
    if (db == null) return;
    try {
      await db.delete('cache_api');
    } catch (e) {
      debugPrint('CacheLokal.kosongkan gagal: $e');
    }
  }
}
