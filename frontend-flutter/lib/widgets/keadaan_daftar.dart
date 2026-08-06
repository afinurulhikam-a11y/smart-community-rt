import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';

/// Keadaan sebuah daftar ketika isinya tidak bisa ditampilkan.
///
/// ===================================================================
/// Kenapa "kosong" dan "gagal" tidak boleh terlihat sama
/// ===================================================================
///
/// Pola yang tersebar di banyak layar sebelumnya hanya punya dua cabang:
/// sedang memuat, atau daftarnya kosong. Cabang galat tidak ada. Padahal
/// `ApiService` tidak pernah melempar — kegagalan datang sebagai
/// `success: false`, provider menyimpannya di `errorMessage`, dan daftarnya
/// tetap kosong.
///
/// Akibatnya layar mengatakan **"Belum ada data yang tercatat."** ketika yang
/// sebenarnya terjadi adalah server tidak terjangkau. Itu bukan sekadar pesan
/// yang kurang tepat: ia menyatakan sesuatu yang keliru tentang data pengguna.
/// Pada layar Log Aktivitas kalimat itu berbunyi "belum ada log aktivitas
/// sistem yang tercatat" — persis kebalikan dari kenyataan bahwa lognya ada,
/// hanya tidak bisa diambil.
///
/// Membedakan keduanya juga menentukan tindakan yang tepat: daftar kosong
/// berarti "silakan tambah data", gagal berarti "coba lagi", dan offline
/// berarti "periksa koneksi" — tiga hal yang tidak boleh dijawab sama.
class KeadaanDaftar extends StatelessWidget {
  const KeadaanDaftar({
    super.key,
    required this.kosong,
    this.galat,
    this.offline = false,
    this.onCobaLagi,
    this.ikonKosong = Icons.inbox_outlined,
  });

  /// Kalimat untuk daftar yang memang benar-benar kosong.
  final String kosong;

  /// Pesan galat dari provider. Bila null, keadaannya dianggap kosong biasa.
  final String? galat;

  /// Benar bila kegagalannya karena server tidak terjangkau, bukan ditolak.
  final bool offline;

  final VoidCallback? onCobaLagi;
  final IconData ikonKosong;

  @override
  Widget build(BuildContext context) {
    final adaGalat = galat != null && galat!.isNotEmpty;

    final ikon = !adaGalat
        ? ikonKosong
        : (offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded);

    final warna = !adaGalat
        ? context.teksTersier
        : (offline ? const Color(0xFFD97706) : const Color(0xFFEF4444));

    final judul = !adaGalat
        ? kosong
        : (offline ? 'Tidak dapat terhubung ke server' : 'Gagal memuat data');

    // Keterangan kedua hanya muncul saat gagal. Untuk keadaan offline, pesan
    // mentah dari ApiService ("Gagal terhubung ke server: ...") tidak membantu
    // siapa pun, jadi diganti kalimat yang menyebutkan tindakan yang bisa
    // diambil pengguna.
    final keterangan = !adaGalat
        ? null
        : (offline
            ? 'Periksa koneksi internet Anda, lalu coba lagi.'
            : galat);

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon, size: 40, color: warna),
            const SizedBox(height: AppTheme.spasiM),
            Text(
              judul,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: adaGalat ? FontWeight.w600 : FontWeight.normal,
                color: adaGalat ? context.teksUtama : context.teksKedua,
              ),
            ),
            if (keterangan != null) ...[
              const SizedBox(height: AppTheme.spasiXs),
              Text(
                keterangan,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.teksKedua),
              ),
            ],
            if (adaGalat && onCobaLagi != null) ...[
              const SizedBox(height: AppTheme.spasiM),
              OutlinedButton.icon(
                onPressed: onCobaLagi,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Coba Lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
