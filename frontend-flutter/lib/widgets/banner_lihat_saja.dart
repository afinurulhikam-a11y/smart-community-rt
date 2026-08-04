import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';

/// Ditampilkan di layar yang boleh dibuka tetapi tidak boleh diubah.
///
/// Tanpa ini, sebuah layar yang tombol aksinya disembunyikan terlihat seperti
/// aplikasi yang rusak. Banner ini menjelaskan bahwa memang begitu aturannya,
/// bukan ada yang gagal dimuat.
///
/// Muncul sendiri hanya bila role memang berstatus lihat-saja pada modul itu,
/// jadi layar cukup memasangnya tanpa pemeriksaan tambahan:
///
/// ```dart
/// const BannerLihatSaja(kode: 'keuangan.kas'),
/// ```
class BannerLihatSaja extends StatelessWidget {
  final String kode;

  /// Ditulis khusus bila kalimat bawaannya terasa kurang tepat untuk modulnya.
  final String? pesan;

  const BannerLihatSaja({super.key, required this.kode, this.pesan});

  @override
  Widget build(BuildContext context) {
    final izin = context.watch<PermissionProvider>();
    if (!izin.hanyaLihat(kode)) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pesan ??
                  'Anda membuka halaman ini dalam mode lihat saja. '
                      'Hubungi Administrator bila perlu mengubah datanya.',
              style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF1E40AF)),
            ),
          ),
        ],
      ),
    );
  }
}
