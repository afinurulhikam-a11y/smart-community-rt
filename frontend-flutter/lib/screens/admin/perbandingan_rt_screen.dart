import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/pesan.dart';
import '../../core/responsif.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../providers/rt_provider.dart';
import '../../widgets/keadaan_daftar.dart';
import '../../widgets/tabel_responsif.dart';

/// Perbandingan antar-RT dalam satu RW.
///
/// ===================================================================
/// Kenapa layar ini ada
/// ===================================================================
///
/// Ketua RW yang memilih "Semua RT" sudah mendapat angka se-RW, tetapi angka
/// itu AGREGAT: satu saldo, satu jumlah warga. Untuk mengetahui RT mana yang
/// perlu perhatian — dan itulah seluruh isi pekerjaannya — ia harus menekan
/// pemilih RT satu per satu lalu mengingat angkanya sendiri.
///
/// Terukur pada dua RT: kas gabungan Rp 1.410.000 tidak memberi tahu apa pun,
/// sementara RT 001 Rp 1.250.000 dan RT 002 Rp 160.000 langsung menunjukkan
/// mana yang baru mulai. Dengan lima RT, membandingkan dengan cara menekan
/// satu per satu sudah tidak masuk akal.
///
/// ===================================================================
/// Layar ini SENGAJA hanya membaca
/// ===================================================================
///
/// Tidak ada tombol yang mengubah data RT lain dari sini. Ketua RW mengawasi;
/// yang mencatat tetap pengurus RT masing-masing. Satu-satunya tombol yang
/// menghasilkan sesuatu adalah Ekspor, dan itu pun hanya menyalin yang sudah
/// boleh ia lihat.
class PerbandinganRtScreen extends StatefulWidget {
  const PerbandinganRtScreen({super.key});

  @override
  State<PerbandinganRtScreen> createState() => _PerbandinganRtScreenState();
}

class _PerbandinganRtScreenState extends State<PerbandinganRtScreen> {
  bool _sedangEkspor = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RtProvider>().muatPerbandingan();
    });
  }

  Future<void> _ekspor() async {
    if (_sedangEkspor) return;
    setState(() => _sedangEkspor = true);
    // Lewat tiket sekali pakai, bukan URL ber-token: sebuah navigasi tidak
    // bisa membawa header, dan berkas ini memuat rekap keuangan seluruh RT.
    final hasil = await ApiService.unduhDenganTiket('rt.rekap');
    if (!mounted) return;
    setState(() => _sedangEkspor = false);
    if (hasil['success'] == true) {
      pesanSukses(context, 'Rekap se-RW sedang diunduh.');
    } else {
      pesanGagal(context, hasil['message']?.toString() ?? 'Gagal mengunduh rekap.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.watch<RtProvider>();
    final total = rt.totalBanding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Judul internal disembunyikan di ponsel — AppBar sudah menamai layar.
        if (!pakaiKartu(context)) ...[
          Row(
            children: [
              const Icon(Icons.compare_arrows_rounded, color: AppTheme.primaryColor),
              const SizedBox(width: AppTheme.spasiS),
              Text(
                'Perbandingan RT',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.teksUtama,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spasiM),
        ],

        if (total != null) ...[
          _ringkasanRw(context, total, rt.banding.length),
          const SizedBox(height: AppTheme.spasiM),
        ],

        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            border: Border.all(color: context.garis),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(paddingKartu(context)),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppTheme.spasiM,
                    runSpacing: AppTheme.spasiS,
                    children: [
                      Text(
                        'Keadaan tiap RT hari ini',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: context.teksUtama,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _sedangEkspor ? null : _ekspor,
                        icon: _sedangEkspor
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: Text(_sedangEkspor ? 'Menyiapkan…' : 'Ekspor Rekap'),
                      ),
                    ],
                  ),
                ),
              ),
              if (rt.memuatBanding && rt.banding.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                TabelResponsif(
                  kolom: const [
                    'RT', 'KETUA', 'KK', 'WARGA', 'SALDO KAS',
                    'TUNGGAKAN', 'PENGADUAN', 'SURAT', 'DARURAT',
                  ],
                  baris: [
                    for (final b in rt.banding) _baris(context, b),
                    if (total != null) _barisTotal(context, total, rt.banding.length),
                  ],
                  kosong: KeadaanDaftar(
                    kosong: 'Belum ada RT untuk dibandingkan.',
                    galat: rt.galatBanding,
                    ikonKosong: Icons.compare_arrows_rounded,
                    onCobaLagi: () => context.read<RtProvider>().muatPerbandingan(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  BarisTabel _baris(BuildContext context, BandingRt b) {
    return BarisTabel(
      // Baris yang menuntut perhatian ditandai latar, bukan hanya angka.
      // Dengan lima RT dan sembilan kolom, menemukan satu angka bukan nol
      // dengan cara membacanya satu per satu adalah pekerjaan yang akan
      // dilewati orang justru pada hari yang sibuk.
      warna: b.perluPerhatian
          ? AppTheme.dangerColor.withValues(alpha: 0.06)
          : null,
      sel: [
        SelTabel.teks('RT', 'RT ${b.kode}', utama: true),
        SelTabel.teks('KETUA', b.ketuaNama ?? '-'),
        SelTabel.teks('KK', '${b.jumlahKk}'),
        SelTabel.teks('WARGA', '${b.jumlahWarga}'),
        SelTabel.teks(
          'SALDO KAS',
          rupiah(b.saldoKas),
          gaya: TextStyle(
            color: b.saldoKas < 0 ? AppTheme.dangerColor : null,
            fontWeight: FontWeight.w600,
          ),
        ),
        _selAngka(context, 'TUNGGAKAN', b.tunggakanJumlah,
            keterangan: b.tunggakanJumlah > 0 ? rupiah(b.tunggakanNominal) : null),
        _selAngka(context, 'PENGADUAN', b.pengaduanTerbuka),
        _selAngka(context, 'SURAT', b.suratTertunda),
        _selAngka(context, 'DARURAT', b.daruratAktif, gawat: true),
      ],
    );
  }

  BarisTabel _barisTotal(BuildContext context, BandingRt t, int jumlahRt) {
    const tebal = TextStyle(fontWeight: FontWeight.bold);
    return BarisTabel(
      warna: context.latarLembut,
      sel: [
        SelTabel.teks('RT', 'TOTAL', utama: true, gaya: tebal),
        SelTabel.teks('KETUA', '$jumlahRt RT', gaya: tebal),
        SelTabel.teks('KK', '${t.jumlahKk}', gaya: tebal),
        SelTabel.teks('WARGA', '${t.jumlahWarga}', gaya: tebal),
        SelTabel.teks('SALDO KAS', rupiah(t.saldoKas), gaya: tebal),
        SelTabel.teks('TUNGGAKAN', '${t.tunggakanJumlah}', gaya: tebal),
        SelTabel.teks('PENGADUAN', '${t.pengaduanTerbuka}', gaya: tebal),
        SelTabel.teks('SURAT', '${t.suratTertunda}', gaya: tebal),
        SelTabel.teks('DARURAT', '${t.daruratAktif}', gaya: tebal),
      ],
    );
  }

  /// Angka nol ditulis abu-abu dan angka bukan nol diberi warna.
  ///
  /// Nol adalah keadaan yang baik di setiap kolom ini, jadi yang harus menarik
  /// mata justru yang bukan nol.
  SelTabel _selAngka(
    BuildContext context,
    String label,
    int nilai, {
    String? keterangan,
    bool gawat = false,
  }) {
    final warna = nilai == 0
        ? context.teksTersier
        : (gawat ? AppTheme.dangerColor : const Color(0xFFB45309));
    return SelTabel(
      label,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$nilai',
            style: TextStyle(
              color: warna,
              fontWeight: nilai == 0 ? FontWeight.normal : FontWeight.bold,
            ),
          ),
          if (keterangan != null)
            Text(
              keterangan,
              style: TextStyle(fontSize: 11, color: context.teksKedua),
            ),
        ],
      ),
    );
  }

  /// Ringkasan se-RW di atas tabel.
  ///
  /// Angkanya datang dari baris TOTAL yang dihitung server dari data yang sama
  /// dengan tabelnya — bukan dijumlah ulang di sini. Pada layar yang gunanya
  /// membandingkan, dua sumber untuk satu angka adalah dua angka yang cepat
  /// atau lambat berbeda.
  Widget _ringkasanRw(BuildContext context, BandingRt t, int jumlahRt) {
    final perluPerhatian = t.daruratAktif > 0 || t.tunggakanJumlah > 0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.apartment_rounded, size: 18, color: AppTheme.primaryColor),
              const SizedBox(width: AppTheme.spasiS),
              Expanded(
                child: Text(
                  'Seluruh RW — $jumlahRt RT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spasiS),
          Wrap(
            spacing: AppTheme.spasiL,
            runSpacing: AppTheme.spasiS,
            children: [
              _angkaRingkas(context, 'Kartu Keluarga', '${t.jumlahKk}'),
              _angkaRingkas(context, 'Warga', '${t.jumlahWarga}'),
              _angkaRingkas(context, 'Saldo Kas', rupiah(t.saldoKas)),
              _angkaRingkas(context, 'Tunggakan', '${t.tunggakanJumlah} lembar'),
            ],
          ),
          if (perluPerhatian) ...[
            const SizedBox(height: AppTheme.spasiS),
            Text(
              t.daruratAktif > 0
                  ? '${t.daruratAktif} kejadian darurat masih aktif.'
                  : '${t.tunggakanJumlah} tagihan belum dibayar, '
                      'senilai ${rupiah(t.tunggakanNominal)}.',
              style: const TextStyle(
                color: AppTheme.dangerColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _angkaRingkas(BuildContext context, String label, String nilai) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: context.teksKedua)),
        Text(
          nilai,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.teksUtama,
          ),
        ),
      ],
    );
  }
}
