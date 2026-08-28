import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/izin_layar.dart';
import '../../core/pesan.dart';
import '../../core/responsif.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../providers/rt_provider.dart';
import '../../widgets/keadaan_daftar.dart';
import '../../widgets/tabel_responsif.dart';
import '../../core/peran.dart';
import '../../core/services/auth_service.dart';
import '../../widgets/tombol_kembali.dart';
import 'data_warga_screen.dart';

/// Daftar RT dalam satu RW, beserta penambahan dan penyuntingannya.
///
/// ===================================================================
/// Kenapa layar ini ada
/// ===================================================================
///
/// `POST/PUT/DELETE /api/rt` sudah ada sejak modul RT dibuat, tetapi tidak ada
/// satu pun layar yang memanggilnya. Artinya menambah RT ketiga hanya bisa
/// lewat SQL atau Postman — sebuah kemampuan yang secara teknis ada dan secara
/// praktis tidak dimiliki siapa pun yang memakai aplikasi ini.
///
/// ===================================================================
/// Kenapa penjaganya `role`, bukan izin modul
/// ===================================================================
///
/// Rutenya memakai `roleGuard('admin')`, sama seperti Menu & Akses dan Reset
/// Sistem, dan alasannya sama: RT adalah batas yang menentukan seluruh
/// pelingkupan data. Kewenangan menggeser batas itu tidak boleh bergantung
/// pada tabel izin yang batas itu ikut menjaganya.
///
/// Karena itu layar ini juga tidak punya baris di `permissions.js`. Saklar
/// yang tidak mengubah apa pun lebih berbahaya daripada tidak ada saklar — ia
/// membuat administrator yakin sudah menutup sesuatu.
///
/// ===================================================================
/// Nomor RT tidak bisa diubah setelah dibuat
/// ===================================================================
///
/// Nomornya tertanam pada topik MQTT di setiap perangkat alarm yang sudah
/// terpasang (`smart-community/rt/{kode}/alarm/command`). Menggantinya dari
/// layar akan membuat sirene RT itu berhenti berbunyi tanpa satu pun pesan
/// galat — kegagalan paling buruk yang bisa dihasilkan aplikasi ini. Server
/// pun sudah menolaknya; kolomnya di sini dinonaktifkan supaya penolakan itu
/// tidak datang sebagai kejutan setelah seseorang selesai mengetik.
class KelolaRtScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const KelolaRtScreen({super.key, this.onBack});

  @override
  State<KelolaRtScreen> createState() => _KelolaRtScreenState();
}

class _KelolaRtScreenState extends State<KelolaRtScreen> {
  /// Menambah dan menghapus RT tetap milik administrator.
  ///
  /// Keduanya MENGGESER BATAS yang menentukan seluruh pelingkupan data, dan
  /// nomor RT-nya tertanam di topik MQTT setiap perangkat alarm yang sudah
  /// terpasang. Menambah RT tanpa memflash perangkatnya menghasilkan RT yang
  /// sirenenya tidak pernah berbunyi — dan tidak ada layar yang bisa memberi
  /// tahu hal itu.
  ///
  /// Mengubah nama, alamat sekretariat, dan siapa ketuanya tidak menggeser
  /// batas apa pun, dan justru itu pekerjaan Ketua RW yang paling biasa.
  ///
  /// Server tetap penjaga sesungguhnya: `POST` dan `DELETE /api/rt` dijaga
  /// `roleGuard('admin')`. Yang dilakukan di sini hanya menyembunyikan tombol
  /// yang pasti ditolak — tombol yang selalu berakhir 403 lebih buruk
  /// daripada tombol yang tidak ada.
  bool get _bolehTambahHapus => context.watch<AuthService>().userRole == Peran.admin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RtProvider>().muat();
    });
  }

  Future<void> _formRt({RtModel? rt}) async {
    final ubah = rt != null;
    final kodeC = TextEditingController(text: rt?.kode ?? '');
    final namaC = TextEditingController(text: rt?.nama ?? '');
    final alamatC = TextEditingController(text: '');
    final rwC = TextEditingController(text: rt?.rwKode ?? '');
    final kunciForm = GlobalKey<FormState>();

    final simpan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.latarKartu,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text(
          ubah ? 'Ubah RT ${rt.kode}' : 'Tambah RT',
          style: TextStyle(color: ctx.teksUtama, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: lebarDialog(ctx),
          child: SingleChildScrollView(
            child: Form(
              key: kunciForm,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: kodeC,
                    enabled: !ubah,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Nomor RT *',
                      hintText: '003',
                      helperText: ubah
                          ? 'Nomor RT tidak bisa diubah — sudah dipakai perangkat alarm.'
                          : 'Boleh diketik "3"; disimpan sebagai "003".',
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      if (ubah) return null;
                      if ((v ?? '').trim().isEmpty) return 'Nomor RT wajib diisi.';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTheme.spasiM),
                  TextFormField(
                    controller: namaC,
                    decoration: const InputDecoration(
                      labelText: 'Nama RT',
                      hintText: 'RT 003 Kampung Melati',
                    ),
                  ),
                  const SizedBox(height: AppTheme.spasiM),
                  if (!ubah) ...[
                    TextFormField(
                      controller: rwC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nomor RW',
                        hintText: 'Kosongkan untuk mengikuti RW Anda',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                  ],
                  TextFormField(
                    controller: alamatC,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Alamat sekretariat',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: ctx.warnaTombolTutup),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (kunciForm.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(ubah ? 'Simpan' : 'Tambah'),
          ),
        ],
      ),
    );

    if (simpan != true || !mounted) return;

    final provider = context.read<RtProvider>();
    final galat = ubah
        ? await provider.ubah(
            rt.id,
            nama: namaC.text.trim(),
            alamatSekretariat: alamatC.text.trim(),
          )
        : await provider.tambah(
            kode: kodeC.text.trim(),
            nama: namaC.text.trim(),
            rwKode: rwC.text.trim(),
            alamatSekretariat: alamatC.text.trim(),
          );

    if (!mounted) return;
    _pesan(
      galat ?? (ubah ? 'Data RT berhasil diperbarui.' : 'RT berhasil ditambahkan.'),
      gagal: galat != null,
    );
  }

  Future<void> _hapusRt(RtModel rt) async {
    // Penolakan server ("masih memiliki N kartu keluarga dan M akun")
    // ditampilkan apa adanya, tetapi jumlahnya sudah terlihat di tabel — jadi
    // konfirmasinya menyebutkan lebih dulu apa yang akan menghalangi.
    final terisi = rt.jumlahKk > 0 || rt.jumlahAkun > 0;
    final ok = await konfirmasiHapus(
      context,
      judul: 'Hapus ${rt.label}?',
      pesan: terisi
          ? '${rt.label} masih memiliki ${rt.jumlahKk} kartu keluarga dan '
              '${rt.jumlahAkun} akun. Selama masih ada isinya, penghapusan akan '
              'ditolak — pindahkan atau hapus datanya lebih dulu.'
          : '${rt.label} akan dihapus dari daftar RT. Tindakan ini tidak bisa dibatalkan.',
    );
    if (!ok || !mounted) return;

    final galat = await context.read<RtProvider>().hapus(rt.id);
    if (!mounted) return;
    _pesan(galat ?? 'RT berhasil dihapus.', gagal: galat != null);
  }

  void _pesan(String teks, {bool gagal = false}) {
    // Lewat `core/pesan.dart`, tidak pernah memanggil messenger sendiri:
    // warnanya ditentukan di satu tempat, dan `pesan_test.dart` menyapu
    // seluruh `lib/` untuk memastikan tidak ada jalur kedua. Sapuan itu
    // bekerja atas teks berkas, jadi menyebut nama metodenya di komentar pun
    // ikut tertangkap — dan itu memang lebih baik daripada penjaga yang harus
    // menebak mana teks yang sungguhan kode.
    tampilkanPesan(context, teks, sukses: !gagal);
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.watch<RtProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Breadcrumb
        Container(
          padding: EdgeInsets.all(paddingKartu(context)),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.garis),
          ),
          child: Row(
            children: [
              TombolKembali(onPressed: widget.onBack),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.apartment_outlined, color: Color(0xFF0F766E), size: 20),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Pengaturan / Kelola RT',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.teksKedua,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Baris Tombol Aksi
        if (_bolehTambahHapus) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _formRt(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Tambah RT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Data Table Card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.garis),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Center: Ikon + Judul
              Padding(
                padding: EdgeInsets.all(paddingKartu(context)),
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      const Icon(Icons.apartment_outlined, color: Color(0xFF0F766E), size: 20),
                      Text(
                        'Daftar Rukun Tetangga (RT)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: context.teksUtama,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: context.garis),

              if (rt.isLoading && rt.daftar.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF0F766E))),
                )
              else
                Padding(
                  padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                  child: TabelResponsif(
                    kolom: const ['NO', 'NOMOR RT', 'NAMA', 'KETUA', 'KK', 'AKUN'],
                    baris: [
                      for (var i = 0; i < rt.daftar.length; i++)
                        _baris(context, rt.daftar[i], i),
                    ],
                    kosong: KeadaanDaftar(
                      kosong: 'Belum ada RT yang terdaftar.',
                      galat: rt.errorMessage,
                      ikonKosong: Icons.apartment_outlined,
                      onCobaLagi: () => context.read<RtProvider>().muat(),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  BarisTabel _baris(BuildContext context, RtModel r, int i) {
    return BarisTabel(
      sel: [
        SelTabel.teks('NO', '${i + 1}', sembunyiDiKartu: true),
        SelTabel.teks('NOMOR RT', 'RT ${r.kode} / RW ${r.rwKode}'),
        SelTabel.teks('NAMA', r.nama.isEmpty ? '-' : r.nama, utama: true),
        SelTabel.teks('KETUA', r.ketuaNama ?? '-'),
        SelTabel.teks('KK', '${r.jumlahKk}'),
        SelTabel.teks('AKUN', '${r.jumlahAkun}'),
      ],
      aksi: Transform.translate(
        offset: const Offset(geserAksiTabel, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF3B82F6)),
              style: gayaAksiTabel(const Color(0xFF3B82F6)),
              onPressed: () => _formRt(rt: r),
            ),
            if (_bolehTambahHapus)
              IconButton(
                tooltip: 'Hapus',
                icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFEF4444)),
                style: gayaAksiTabel(const Color(0xFFEF4444)),
                onPressed: () => _hapusRt(r),
              ),
          ],
        ),
      ),
    );
  }
}
