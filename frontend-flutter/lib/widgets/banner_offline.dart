import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/koneksi_provider.dart';

/// Pita status jaringan dan antrean kiriman.
///
/// ===================================================================
/// Kenapa harus terlihat
/// ===================================================================
///
/// Cache dan antrean offline membuat aplikasi tetap berguna tanpa sinyal —
/// tetapi keduanya justru menciptakan bahaya baru bila dikerjakan diam-diam.
/// Data lama yang tampil persis seperti data baru bisa membuat pengurus
/// menyimpulkan iuran belum dibayar padahal sudah, dan pengaduan yang tersimpan
/// di antrean bisa dikira sudah sampai ke pengurus padahal belum.
///
/// Aturannya: aplikasi boleh menolong secara diam-diam, tetapi tidak boleh
/// diam soal keadaan datanya.
class BannerOffline extends StatelessWidget {
  const BannerOffline({super.key});

  @override
  Widget build(BuildContext context) {
    final koneksi = context.watch<KoneksiProvider>();
    final adaAntrean = koneksi.tertunda > 0;

    if (koneksi.daring && !adaAntrean) return const SizedBox.shrink();

    final warna = koneksi.daring ? const Color(0xFF0D9488) : const Color(0xFFD97706);
    final ikon = koneksi.daring
        ? (koneksi.sedangKirimUlang ? Icons.cloud_sync_outlined : Icons.schedule_send_outlined)
        : Icons.wifi_off_rounded;

    final teks = !koneksi.daring
        ? (adaAntrean
            ? 'Tidak ada koneksi — ${koneksi.tertunda} kiriman menunggu'
            : 'Tidak ada koneksi. Data yang tampil mungkin tersimpan sebelumnya.')
        : (koneksi.sedangKirimUlang
            ? 'Mengirim ${koneksi.tertunda} kiriman yang tertunda…'
            : '${koneksi.tertunda} kiriman menunggu dikirim');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppTheme.spasiM),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spasiM,
        vertical: AppTheme.spasiS,
      ),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(color: warna.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(ikon, size: 16, color: warna),
          const SizedBox(width: AppTheme.spasiS),
          Expanded(
            child: Text(
              teks,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: warna),
            ),
          ),
          if (koneksi.daring && adaAntrean && !koneksi.sedangKirimUlang)
            TextButton(
              onPressed: koneksi.kirimUlangAntrean,
              style: TextButton.styleFrom(
                foregroundColor: warna,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spasiS),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Kirim', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// Keterangan kapan data yang sedang ditampilkan diambil.
///
/// Dipasang oleh layar yang membaca lewat cache. Hanya muncul bila isinya
/// memang berasal dari penyimpanan lokal — pada keadaan normal ia tidak
/// mengambil ruang sama sekali.
class LabelDataTersimpan extends StatelessWidget {
  const LabelDataTersimpan({super.key, required this.waktu});

  /// Waktu pengambilan, dalam ISO-8601. Null berarti data berasal dari server.
  final String? waktu;

  @override
  Widget build(BuildContext context) {
    if (waktu == null) return const SizedBox.shrink();

    final t = DateTime.tryParse(waktu!)?.toLocal();
    if (t == null) return const SizedBox.shrink();

    final selisih = DateTime.now().difference(t);
    final usia = selisih.inMinutes < 1
        ? 'baru saja'
        : selisih.inHours < 1
            ? '${selisih.inMinutes} menit lalu'
            : selisih.inDays < 1
                ? '${selisih.inHours} jam lalu'
                : '${selisih.inDays} hari lalu';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spasiS),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.save_outlined, size: 13, color: Color(0xFFD97706)),
          const SizedBox(width: AppTheme.spasiXs),
          Flexible(
            child: Text(
              'Data tersimpan — terakhir diperbarui $usia',
              style: const TextStyle(fontSize: 11, color: Color(0xFFD97706)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
