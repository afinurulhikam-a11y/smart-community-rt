import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/pesan.dart';
import '../core/responsif.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';
import '../providers/emergency_provider.dart';

/// Kartu tombol darurat, dipakai dasbor SEMUA peran.
///
/// ===================================================================
/// Kenapa satu widget untuk semua peran
/// ===================================================================
///
/// Warga dan pengurus memakai dasbor yang berbeda (`WargaDashboardContent` dan
/// `_buildDashboardContent`), tetapi tombol daruratnya harus persis sama —
/// tampilannya, PIN-nya, dan perilakunya. Menyalinnya ke dua tempat berarti
/// suatu hari yang satu diperbaiki dan yang lain tidak, dan yang tertinggal
/// justru baru ketahuan saat keadaan darurat.
///
/// ===================================================================
/// Yang TIDAK dilakukan widget ini
/// ===================================================================
///
/// Ia tidak memverifikasi PIN. PIN dikirim apa adanya ke backend dan
/// diperiksa di sana. Memeriksanya di sini hanya menyaring salah ketik —
/// siapa pun bisa memanggil endpoint langsung dan melewatinya.
///
/// Ia juga tidak pernah menyentuh broker MQTT maupun kredensialnya. Aplikasi
/// memanggil endpoint HTTP biasa; server yang menerbitkan perintahnya.
class KartuAlarmDarurat extends StatelessWidget {
  const KartuAlarmDarurat({super.key});

  @override
  Widget build(BuildContext context) {
    final darurat = context.watch<EmergencyProvider>();
    final menyala = darurat.alarmMenyala;
    final sibuk = darurat.mengirimAlarm;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(pakaiKartu(context) ? 20 : 16),
      decoration: BoxDecoration(
        color: menyala
            ? AppTheme.dangerColor.withValues(alpha: 0.10)
            : context.latarKartu,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(
          color: menyala
              ? AppTheme.dangerColor
              : AppTheme.dangerColor.withValues(alpha: 0.35),
          width: menyala ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                menyala ? Icons.notifications_active : Icons.warning_amber_rounded,
                color: AppTheme.dangerColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  menyala ? 'ALARM SEDANG MENYALA' : 'Tombol Darurat',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: menyala ? AppTheme.dangerColor : context.teksUtama,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            menyala
                // Kalimatnya sengaja tidak berbunyi "alat berbunyi". Aplikasi
                // hanya tahu perintahnya terkirim; alat tidak melapor balik.
                ? 'Perintah menyalakan sirene sudah dikirim. Tekan MATIKAN bila keadaan sudah aman.'
                : 'Menyalakan sirene di lingkungan RT. Gunakan hanya untuk keadaan darurat sungguhan.',
            style: TextStyle(fontSize: 13, color: context.teksKedua),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _tombol(
                  context,
                  label: 'NYALAKAN',
                  ikon: Icons.campaign,
                  warna: AppTheme.dangerColor,
                  // Dikunci saat sedang mengirim DAN saat sudah menyala.
                  // Menekan NYALAKAN dua kali tidak menambah apa pun selain
                  // baris ganda di audit log.
                  aktif: !sibuk && !menyala,
                  sibuk: sibuk && !menyala,
                  onTap: () => _mintaPin(context, 'ON'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tombol(
                  context,
                  label: 'MATIKAN',
                  ikon: Icons.notifications_off,
                  warna: context.teksKedua,
                  // MATIKAN sengaja SELALU tersedia selama tidak sedang
                  // mengirim — termasuk ketika aplikasi mengira alarm sudah
                  // mati. Aplikasi bisa saja salah (dibuka ulang, dinyalakan
                  // dari perangkat lain), dan buzzer yang tidak bisa
                  // dihentikan jauh lebih buruk daripada perintah OFF berlebih.
                  aktif: !sibuk,
                  sibuk: sibuk && menyala,
                  onTap: () => _mintaPin(context, 'OFF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tombol(
    BuildContext context, {
    required String label,
    required IconData ikon,
    required Color warna,
    required bool aktif,
    required bool sibuk,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: aktif ? onTap : null,
      icon: sibuk
          ? const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(ikon, size: 18),
      label: Text(sibuk ? 'Mengirim…' : label),
      style: ElevatedButton.styleFrom(
        backgroundColor: warna,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, AppTheme.sasaranSentuh),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
      ),
    );
  }

  /// Dialog konfirmasi + PIN. Satu dialog untuk ON dan OFF; hanya kalimatnya
  /// yang berbeda, supaya keduanya tidak bisa berbeda perilaku.
  Future<void> _mintaPin(BuildContext context, String aksi) async {
    final nyala = aksi == 'ON';
    final kontrolPin = TextEditingController();
    final darurat = context.read<EmergencyProvider>();

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? galatLokal;
        return StatefulBuilder(
          builder: (ctx, setLokal) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  nyala ? Icons.campaign : Icons.notifications_off,
                  color: nyala ? AppTheme.dangerColor : ctx.teksKedua,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(nyala ? 'Nyalakan alarm?' : 'Matikan alarm?')),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: lebarDialog(ctx, maksimal: 400)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nyala
                        ? 'Sirene akan berbunyi di lingkungan RT dan seluruh pengurus akan diberi tahu. '
                          'Penekanan ini tercatat beserta nama Anda.'
                        : 'Sirene akan berhenti berbunyi. Penekanan ini juga tercatat.',
                    style: TextStyle(fontSize: 13, color: ctx.teksKedua),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: kontrolPin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'PIN Darurat',
                      hintText: 'Masukkan PIN',
                      errorText: galatLokal,
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) {
                        setLokal(() => galatLokal = 'PIN wajib diisi');
                        return;
                      }
                      Navigator.pop(ctx, v.trim());
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () {
                  final v = kontrolPin.text.trim();
                  if (v.isEmpty) {
                    setLokal(() => galatLokal = 'PIN wajib diisi');
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: nyala ? AppTheme.dangerColor : null,
                ),
                child: Text(nyala ? 'Nyalakan' : 'Matikan'),
              ),
            ],
          ),
        );
      },
    );

    if (pin == null || pin.isEmpty) return;

    final galat = await darurat.kendaliAlarm(aksi, pin);
    if (!context.mounted) return;

    // Lewat helper bersama, bukan SnackBar sendiri: `lib/core/pesan.dart`
    // adalah satu-satunya tempat warna pesan ditentukan, dan
    // `test/pesan_test.dart` menegakkannya. Merah berarti tidak jadi, hijau
    // berarti jadi — pada tombol darurat, perbedaan itu yang paling penting.
    if (galat != null) {
      pesanGagal(context, galat);
    } else {
      pesanSukses(
        context,
        nyala
            ? 'Alarm dinyalakan. Periksa alat untuk memastikan sirene berbunyi.'
            : 'Alarm dimatikan.',
      );
    }
  }
}
