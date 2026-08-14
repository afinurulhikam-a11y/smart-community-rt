import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/pesan.dart';
import '../core/responsif.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';
import '../providers/emergency_provider.dart';

/// Panel kendali darurat, dipakai dasbor SEMUA peran.
///
/// ===================================================================
/// Kenapa satu widget untuk semua peran
/// ===================================================================
///
/// Warga dan pengurus memakai dasbor yang berbeda (`WargaDashboardContent` dan
/// `_buildDashboardContent`), tetapi panel daruratnya harus persis sama —
/// tampilannya, PIN-nya, dan perilakunya. Menyalinnya ke dua tempat berarti
/// suatu hari yang satu diperbaiki dan yang lain tidak, dan yang tertinggal
/// justru baru ketahuan saat keadaan darurat.
///
/// ===================================================================
/// Bahasa visualnya mengikuti kartu dasbor yang sudah ada
/// ===================================================================
///
/// Kartu di dasbor ini **outlined, bukan shadowed** — `latarKartu` + garis
/// tipis + radius 16 — dan panel ini memakai kerangka yang sama supaya tidak
/// terasa ditempel dari aplikasi lain. Yang membedakannya bukan bentuk
/// melainkan **warna dan bobot**: aksen merah bahaya, ikon di kotak bertint,
/// dan status yang menonjol.
///
/// Peringatan dibuat tegas tetapi tidak berteriak. Kartu yang selalu menyala
/// merah menyilaukan akan diabaikan dalam sepekan, dan tepat pada hari ia
/// benar-benar penting, mata sudah terbiasa melewatinya.
///
/// ===================================================================
/// Yang TIDAK dilakukan widget ini
/// ===================================================================
///
/// Ia tidak memverifikasi PIN. PIN dikirim apa adanya ke backend dan diperiksa
/// di sana. Memeriksanya di sini hanya menyaring salah ketik — siapa pun bisa
/// memanggil endpoint langsung dan melewatinya.
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
    final rapat = !pakaiKartu(context);

    return AnimatedContainer(
      // Perpindahan warna dibuat halus, bukan berkedip. Animasi berdurasi
      // terbatas — BUKAN yang berulang tanpa henti — karena animasi abadi
      // meninggalkan timer aktif dan membuat widget test gagal pada "pending
      // timers" alih-alih pada hal yang sedang diuji.
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: EdgeInsets.all(rapat ? AppTheme.spasiL : AppTheme.spasiXl),
      decoration: BoxDecoration(
        color: menyala
            ? AppTheme.dangerColor.withValues(alpha: 0.06)
            : context.latarKartu,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(
          color: menyala ? AppTheme.dangerColor : context.garis,
          width: menyala ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kepala(context, menyala: menyala, rapat: rapat),
          SizedBox(height: rapat ? AppTheme.spasiM : AppTheme.spasiL),
          Divider(height: 1, thickness: 1, color: context.garis),
          SizedBox(height: rapat ? AppTheme.spasiM : AppTheme.spasiL),
          _peringatan(context, menyala: menyala),
          SizedBox(height: rapat ? AppTheme.spasiM : AppTheme.spasiL),
          _aksi(context, menyala: menyala, sibuk: sibuk),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────── kepala
  //
  // Hierarki: ikon → judul → deskripsi di kiri, lencana status di kanan.
  // Judul dan status adalah dua hal yang paling dicari mata, jadi keduanya
  // diletakkan pada satu baris pandang.
  Widget _kepala(BuildContext context, {required bool menyala, required bool rapat}) {
    final judul = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Kendali Darurat',
          style: TextStyle(
            fontSize: rapat ? 16 : 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: context.teksUtama,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Sirene lingkungan RT',
          style: TextStyle(fontSize: 13, color: context.teksKedua),
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ikon dalam kotak bertint — pola yang sudah dipakai kartu lain di
        // dasbor, jadi panel ini terbaca sebagai bagian dari keluarga yang sama.
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.dangerColor.withValues(alpha: menyala ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          child: Icon(
            menyala ? Icons.notifications_active_rounded : Icons.campaign_rounded,
            color: AppTheme.dangerColor,
            size: 24,
          ),
        ),
        const SizedBox(width: AppTheme.spasiM),
        Expanded(child: judul),
        const SizedBox(width: AppTheme.spasiS),
        _lencanaStatus(context, menyala: menyala),
      ],
    );
  }

  // ─────────────────────────────────────────────────────── lencana status
  //
  // Titik + teks, bukan hanya warna. Sekitar satu dari dua belas laki-laki
  // kesulitan membedakan merah dari hijau, dan status alarm bukan tempat untuk
  // mengandalkan warna sendirian.
  Widget _lencanaStatus(BuildContext context, {required bool menyala}) {
    final warna = menyala ? AppTheme.dangerColor : AppTheme.successColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: warna.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: warna, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            menyala ? 'AKTIF' : 'SIAGA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────── peringatan
  Widget _peringatan(BuildContext context, {required bool menyala}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          menyala ? Icons.volume_up_rounded : Icons.info_outline_rounded,
          size: 16,
          color: menyala ? AppTheme.dangerColor : context.teksTersier,
        ),
        const SizedBox(width: AppTheme.spasiS),
        Expanded(
          child: Text(
            menyala
                // Kalimatnya sengaja tidak berbunyi "alat berbunyi". Aplikasi
                // hanya tahu perintahnya terkirim; alat tidak melapor balik ke
                // sini. Mengaku tahu lebih banyak daripada yang sebenarnya
                // diketahui membuat orang berhenti memeriksa alatnya sendiri.
                ? 'Perintah menyalakan sirene sudah dikirim. Tekan MATIKAN bila keadaan sudah aman.'
                : 'Menyalakan sirene di lingkungan RT. Gunakan hanya untuk keadaan darurat sungguhan — setiap penekanan tercatat beserta nama Anda.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: menyala ? context.teksUtama : context.teksKedua,
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────── aksi
  //
  // Kedua tombol berbagi lebar sama rata — keduanya penting, dan menyempitkan
  // salah satunya membuatnya sulit ditekan justru saat tangan gemetar.
  //
  // Yang berbeda adalah BOBOTNYA, dan bobot itu BERPINDAH mengikuti keadaan:
  //
  //   siaga  -> NYALAKAN terisi penuh (aksi utama), MATIKAN bergaris saja
  //   aktif  -> MATIKAN terisi penuh (aksi utama), NYALAKAN dinonaktifkan
  //
  // Alasannya sederhana: ketika sirene sedang meraung, satu-satunya hal yang
  // ingin dilakukan orang adalah menghentikannya. Tombol utama harus tombol
  // yang sedang dibutuhkan, bukan tombol yang sama sepanjang waktu.
  Widget _aksi(BuildContext context, {required bool menyala, required bool sibuk}) {
    final nyalakan = _TombolAksi(
      label: 'NYALAKAN',
      ikon: Icons.campaign_rounded,
      warna: AppTheme.dangerColor,
      utama: !menyala,
      // Dikunci saat sedang mengirim DAN saat sudah menyala. Menekan NYALAKAN
      // dua kali tidak menambah apa pun selain baris ganda di audit log.
      aktif: !sibuk && !menyala,
      sibuk: sibuk && !menyala,
      onTap: () => _mintaPin(context, 'ON'),
    );

    final matikan = _TombolAksi(
      label: 'MATIKAN',
      ikon: Icons.notifications_off_rounded,
      warna: menyala ? AppTheme.dangerColor : context.teksKedua,
      utama: menyala,
      // MATIKAN sengaja SELALU tersedia selama tidak sedang mengirim —
      // termasuk ketika aplikasi mengira alarm sudah mati. Aplikasi bisa saja
      // salah (dibuka ulang, atau dinyalakan dari perangkat lain), dan buzzer
      // yang tidak bisa dihentikan jauh lebih buruk daripada perintah OFF
      // yang berlebih.
      aktif: !sibuk,
      sibuk: sibuk && menyala,
      onTap: () => _mintaPin(context, 'OFF'),
    );

    // Di bawah ~360 px dua tombol berdampingan memaksa labelnya terpotong.
    // Ditumpuk, keduanya tetap selebar layar dan tetap mudah ditekan.
    return LayoutBuilder(
      builder: (ctx, batas) {
        if (batas.maxWidth < 360) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: nyalakan),
              const SizedBox(height: AppTheme.spasiS),
              SizedBox(width: double.infinity, child: matikan),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: nyalakan),
            const SizedBox(width: AppTheme.spasiM),
            Expanded(child: matikan),
          ],
        );
      },
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusS),
                  ),
                  child: Icon(
                    nyala ? Icons.campaign_rounded : Icons.notifications_off_rounded,
                    color: nyala ? AppTheme.dangerColor : ctx.teksKedua,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppTheme.spasiM),
                Expanded(
                  child: Text(
                    nyala ? 'Nyalakan alarm?' : 'Matikan alarm?',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
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
                    style: TextStyle(fontSize: 13, height: 1.4, color: ctx.teksKedua),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
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
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
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
    // `test/pesan_test.dart` menegakkannya.
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

/// Tombol aksi panel darurat.
///
/// Dipisah menjadi widget sendiri supaya NYALAKAN dan MATIKAN tidak mungkin
/// berbeda ukuran, radius, atau perilaku keadaan — keduanya hanya berbeda pada
/// nilai yang dioper.
///
/// [utama] menentukan bobot visual: terisi penuh bila utama, bergaris bila
/// sekunder. Keduanya tetap berukuran sama.
class _TombolAksi extends StatelessWidget {
  final String label;
  final IconData ikon;
  final Color warna;
  final bool utama;
  final bool aktif;
  final bool sibuk;
  final VoidCallback onTap;

  const _TombolAksi({
    required this.label,
    required this.ikon,
    required this.warna,
    required this.utama,
    required this.aktif,
    required this.sibuk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isi = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sibuk)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: utama ? Colors.white : warna,
            ),
          )
        else
          Icon(ikon, size: 18),
        const SizedBox(width: AppTheme.spasiS),
        Flexible(
          child: Text(
            // Label berubah saat memuat, bukan hanya ikonnya. Teks "Mengirim…"
            // menjelaskan apa yang sedang terjadi; spinner sendirian tidak.
            sibuk ? 'Mengirim…' : label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
        ),
      ],
    );

    final bentuk = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
    );

    // Tinggi minimum, bukan tetap: kotak bertinggi mati akan memotong isinya
    // saat pengguna menaikkan skala huruf perangkat.
    const ukuranMinimum = Size(0, AppTheme.sasaranSentuh);

    if (utama) {
      return ElevatedButton(
        onPressed: aktif ? onTap : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((keadaan) {
            if (keadaan.contains(WidgetState.disabled)) {
              return warna.withValues(alpha: 0.35);
            }
            if (keadaan.contains(WidgetState.pressed)) {
              // Ditekan → lebih gelap. Umpan balik sentuh harus terlihat tanpa
              // menunggu jaringan menjawab.
              return Color.lerp(warna, Colors.black, 0.18);
            }
            if (keadaan.contains(WidgetState.hovered)) {
              return Color.lerp(warna, Colors.black, 0.08);
            }
            return warna;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          elevation: WidgetStateProperty.resolveWith(
            (keadaan) => keadaan.contains(WidgetState.pressed) ? 0 : 1,
          ),
          minimumSize: WidgetStateProperty.all(ukuranMinimum),
          shape: WidgetStateProperty.all(bentuk),
        ),
        child: isi,
      );
    }

    return OutlinedButton(
      onPressed: aktif ? onTap : null,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((keadaan) =>
            keadaan.contains(WidgetState.disabled) ? warna.withValues(alpha: 0.4) : warna),
        backgroundColor: WidgetStateProperty.resolveWith((keadaan) {
          if (keadaan.contains(WidgetState.pressed)) {
            return warna.withValues(alpha: 0.16);
          }
          if (keadaan.contains(WidgetState.hovered)) {
            return warna.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((keadaan) => BorderSide(
              color: keadaan.contains(WidgetState.disabled)
                  ? context.garis
                  : warna.withValues(alpha: 0.55),
              width: 1.5,
            )),
        minimumSize: WidgetStateProperty.all(ukuranMinimum),
        shape: WidgetStateProperty.all(bentuk),
      ),
      child: isi,
    );
  }
}
