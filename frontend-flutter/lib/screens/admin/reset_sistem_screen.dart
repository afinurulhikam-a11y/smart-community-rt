import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';

import '../../core/theme/app_theme.dart';
import '../../models/reset_model.dart';
import '../../providers/reset_provider.dart';
import '../../widgets/responsive_layout.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

/// Warna aksen aplikasi. AppTheme.primaryColor masih #1B5E20 warisan lama,
/// sedangkan seluruh layar admin memakai #1B7A6A — layar ini mengikuti yang
/// benar-benar dipakai.
const Color _hijau = Color(0xFF1B7A6A);
const Color _hijauMuda = Color(0xFFE8F3F1);
// Konstanta tingkat berkas tidak punya `context`, jadi tidak bisa memakai
// token tema. Ketiganya dihapus; pemakaiannya diganti langsung dengan
// `context.garis` / `context.teksKedua` / `context.teksUtama` di dalam widget.

class ResetSistemScreen extends StatefulWidget {
  const ResetSistemScreen({super.key});

  @override
  State<ResetSistemScreen> createState() => _ResetSistemScreenState();
}

class _ResetSistemScreenState extends State<ResetSistemScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ResetProvider>().muatRingkasan(),
    );
  }

  // ==================== ALUR RESET ====================

  /// Pratinjau dulu, baru dialog konfirmasi. Tidak ada jalan pintas: dampaknya
  /// harus terlihat sebelum apa pun bisa dihapus.
  Future<void> _mulaiReset(ResetGroup grup) async {
    final provider = context.read<ResetProvider>();
    final pratinjau = await provider.pratinjau(grup.kode);
    if (!mounted) return;

    if (pratinjau == null) {
      _pesan(provider.error ?? 'Gagal menghitung dampak reset.', gagal: true);
      return;
    }

    if (pratinjau.kosong) {
      _pesan('Tidak ada data untuk dihapus pada "${grup.nama}".');
      return;
    }

    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogKonfirmasi(grup: grup, pratinjau: pratinjau),
    );

    if (!mounted || hasil == null) return;
    _pesan(hasil['message']?.toString() ?? 'Reset selesai.', gagal: hasil['success'] != true);
  }

  void _pesan(String teks, {bool gagal = false}) {
    tampilkanPesan(
      context,
      teks,
      sukses: !gagal,
      perilaku: SnackBarBehavior.floating,
      durasi: Duration(seconds: gagal ? 8 : 4),
    );
  }

  // ==================== TAMPILAN ====================

  @override
  Widget build(BuildContext context) {
    return Consumer<ResetProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.grup.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator(color: _hijau)),
          );
        }

        if (provider.grup.isEmpty) {
          return _kosong(provider.error);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bannerPeringatan(provider),
            const SizedBox(height: 16),
            _bannerDilindungi(),
            const SizedBox(height: 24),
            _grid(provider.kelompokBiasa.map(_kartuGrup).toList()),
            const SizedBox(height: 24),
            if (provider.grupTotal != null) _kartuResetTotal(provider.grupTotal!),
          ],
        );
      },
    );
  }

  Widget _kosong(String? error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 40, color: context.teksKedua),
          const SizedBox(height: 12),
          Text(
            error ?? 'Data reset tidak tersedia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.teksKedua),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.read<ResetProvider>().muatRingkasan(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Coba Lagi'),
            style: OutlinedButton.styleFrom(foregroundColor: _hijau),
          ),
        ],
      ),
    );
  }

  Widget _bannerPeringatan(ResetProvider provider) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(color: _hijau, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 26),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reset Data Sistem',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Setiap reset menampilkan rincian dampaknya lebih dulu, termasuk data '
                  'lain yang ikut terhapus karena saling terkait. Penghapusan berjalan '
                  'dalam satu transaksi: bila ada yang gagal, tidak ada satu baris pun '
                  'yang terhapus. Data yang sudah terhapus TIDAK DAPAT DIKEMBALIKAN.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${provider.totalBaris} baris data operasional tercatat saat ini',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Daftar ini menyebut apa yang BENAR-BENAR dilindungi backend, sesuai
  /// TABEL_DILINDUNGI di reset-groups.js — bukan janji yang tidak ditepati.
  Widget _bannerDilindungi() {
    final isDark = context.gelap;
    final warnaAksen = isDark ? const Color(0xFF34D399) : _hijau;

    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : _hijauMuda,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF065F46) : _hijau.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: warnaAksen, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tidak Pernah Ikut Terhapus',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: warnaAksen),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bahkan oleh Reset Total, backend selalu mempertahankan:',
                  style: TextStyle(fontSize: 12, color: context.teksKedua),
                ),
                const SizedBox(height: 8),
                _butir('Akun Admin, Ketua RT, Sekretaris, dan Bendahara', warnaAksen),
                _butir('Master Iuran, Kategori Kas, dan Kategori BOP', warnaAksen),
                _butir('Daftar menu dan hak akses per role', warnaAksen),
                _butir('Struktur pengurus RT dan master pendidikan/pekerjaan', warnaAksen),
                _butir('Riwayat reset itu sendiri, agar jejaknya tidak hilang', warnaAksen),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _butir(String teks, Color warnaAksen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 13, color: warnaAksen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(teks, style: TextStyle(fontSize: 12, color: context.teksUtama)),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<Widget> kartu) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int kolom = ResponsiveLayout.isMobile(context)
            ? 1
            : (ResponsiveLayout.isTablet(context) ? 2 : 3);
        final double lebar = (constraints.maxWidth - (16 * (kolom - 1))) / kolom;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: kartu.map((c) => SizedBox(width: lebar, child: c)).toList(),
        );
      },
    );
  }

  Widget _kartuGrup(ResetGroup grup) {
    final bool kosong = grup.kosong;
    final provider = context.watch<ResetProvider>();
    final isDark = context.gelap;
    final warnaAksen = isDark ? const Color(0xFF34D399) : _hijau;
    final warnaLatarIkon = kosong
        ? context.latarLembut
        : (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.4) : _hijauMuda);
    final warnaIkon = kosong ? context.teksKedua : warnaAksen;

    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: warnaLatarIkon,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(grup.ikonData, color: warnaIkon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  grup.nama,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: Text(
              grup.deskripsi,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.4, color: context.teksKedua),
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.garis),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${grup.jumlah}',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: kosong ? context.teksKedua : context.teksUtama,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('baris', style: TextStyle(fontSize: 11, color: context.teksKedua)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (kosong || provider.sedangProses) ? null : () => _mulaiReset(grup),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.dangerColor,
                side: BorderSide(
                  color: kosong ? context.garis : AppTheme.dangerColor.withValues(alpha: 0.5),
                ),
                minimumSize: const Size(double.infinity, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(
                kosong ? 'Sudah Kosong' : 'Reset',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuResetTotal(ResetGroup grup) {
    final provider = context.watch<ResetProvider>();
    final isDark = context.gelap;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF450A0A).withValues(alpha: 0.4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dangerColor.withValues(alpha: isDark ? 0.6 : 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(grup.ikonData, color: AppTheme.dangerColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grup.nama,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFCA5A5) : AppTheme.dangerColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      grup.deskripsi,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: isDark ? const Color(0xFFFCA5A5).withValues(alpha: 0.9) : const Color(0xFF7F1D1D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '${grup.jumlah} baris akan dihapus',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFFCA5A5) : AppTheme.dangerColor,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (grup.kosong || provider.sedangProses) ? null : () => _mulaiReset(grup),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever),
            label: Text(
              grup.kosong ? 'TIDAK ADA DATA UNTUK DIRESET' : 'EKSEKUSI RESET TOTAL',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== DIALOG KONFIRMASI ====================

/// Empat lapis penghalang sebelum data hilang: rincian dampak, tawaran
/// cadangan, frasa yang harus diketik persis, dan password admin.
class _DialogKonfirmasi extends StatefulWidget {
  final ResetGroup grup;
  final ResetPreview pratinjau;

  const _DialogKonfirmasi({required this.grup, required this.pratinjau});

  @override
  State<_DialogKonfirmasi> createState() => _DialogKonfirmasiState();
}

class _DialogKonfirmasiState extends State<_DialogKonfirmasi> {
  final _frasaCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _mauCadangan = true;
  bool _sudahUnduh = false;
  bool _lihatPassword = false;
  bool _sedangKirim = false;

  @override
  void dispose() {
    _frasaCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Tombol hapus baru hidup bila frasa persis sama, password terisi, dan —
  /// bila pengguna memilih mencadangkan — berkasnya sudah benar-benar diunduh.
  bool get _bolehLanjut {
    if (_sedangKirim) return false;
    if (_frasaCtrl.text.trim() != widget.pratinjau.konfirmasi) return false;
    if (_passwordCtrl.text.isEmpty) return false;
    if (_mauCadangan && !_sudahUnduh) return false;
    return true;
  }

  Future<void> _unduh() async {
    final berhasil = await context.read<ResetProvider>().unduhCadangan(widget.grup.kode);
    if (!mounted) return;

    setState(() => _sudahUnduh = berhasil);
    if (!berhasil) {
      tampilkanPesan(
        context,
        'Berkas cadangan gagal diunduh. Penghapusan tidak dilanjutkan.',
        sukses: false,
        perilaku: SnackBarBehavior.floating,
      );
    }
  }

  Future<void> _jalankan() async {
    setState(() => _sedangKirim = true);

    final hasil = await context.read<ResetProvider>().eksekusi(
      kode: widget.grup.kode,
      konfirmasi: _frasaCtrl.text.trim(),
      password: _passwordCtrl.text,
      dicadangkan: _mauCadangan && _sudahUnduh,
    );

    if (!mounted) return;

    // Password atau frasa yang ditolak bukan alasan menutup dialog — pengguna
    // tinggal memperbaikinya tanpa mengulang seluruh alur dari awal.
    if (hasil['success'] != true) {
      setState(() => _sedangKirim = false);
      tampilkanPesan(
        context,
        hasil['message']?.toString() ?? 'Reset gagal.',
        sukses: false,
        perilaku: SnackBarBehavior.floating,
        durasi: const Duration(seconds: 8),
      );
      return;
    }

    Navigator.of(context).pop(hasil);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pratinjau;
    final isDark = context.gelap;

    return AlertDialog(
      backgroundColor: context.latarKartu,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.dangerColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reset ${p.nama}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: context.teksUtama),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: lebarDialog(context, maksimal: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                p.deskripsi,
                style: TextStyle(fontSize: 12, height: 1.5, color: context.teksKedua),
              ),
              const SizedBox(height: 20),

              _judulBagian('Data yang akan dihapus'),
              const SizedBox(height: 8),
              ...p.utama.map((b) => _barisDampak(b, ikutan: false)),

              if (p.adaIkutan) ...[const SizedBox(height: 16), _kotakIkutan(p)],

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF450A0A).withValues(alpha: 0.4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: isDark ? Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.4)) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF7F1D1D),
                      ),
                    ),
                    Text(
                      '${p.total} baris',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.dangerColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _judulBagian('Cadangan'),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _mauCadangan,
                onChanged: _sedangKirim
                    ? null
                    : (v) => setState(() {
                        _mauCadangan = v ?? false;
                        if (!_mauCadangan) _sudahUnduh = false;
                      }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                activeColor: _hijau,
                title: Text(
                  'Unduh cadangan Excel dulu',
                  style: TextStyle(fontSize: 13, color: context.teksUtama),
                ),
                subtitle: Text(
                  'Berisi seluruh baris yang akan dihapus, satu sheet per tabel.',
                  style: TextStyle(fontSize: 11, color: context.teksKedua),
                ),
              ),
              if (_mauCadangan) _tombolUnduh(),

              const SizedBox(height: 20),
              _judulBagian('Konfirmasi'),
              const SizedBox(height: 10),
              Text(
                'Ketik persis: ${p.konfirmasi}',
                style: TextStyle(fontSize: 12, color: context.teksKedua),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _frasaCtrl,
                enabled: !_sedangKirim,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: _dekorasi(hint: p.konfirmasi),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordCtrl,
                enabled: !_sedangKirim,
                obscureText: !_lihatPassword,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _bolehLanjut ? _jalankan() : null,
                style: const TextStyle(fontSize: 13),
                decoration: _dekorasi(
                  hint: 'Password akun admin Anda',
                  ikon: IconButton(
                    icon: Icon(
                      _lihatPassword ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                      color: context.teksKedua,
                    ),
                    onPressed: () => setState(() => _lihatPassword = !_lihatPassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: _sedangKirim ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: context.teksKedua),
          child: const Text('Batal'),
        ),
        ElevatedButton.icon(
          onPressed: _bolehLanjut ? _jalankan : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.dangerColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE5E7EB),
            disabledForegroundColor: context.teksKedua,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: _sedangKirim
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.delete_forever, size: 18),
          label: Text(
            _sedangKirim ? 'Menghapus...' : 'Hapus ${p.total} Baris',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  InputDecoration _dekorasi({required String hint, Widget? ikon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: context.teksTersier),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: ikon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: context.garis),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _hijau, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: context.garis),
      ),
    );
  }

  Widget _judulBagian(String teks) {
    return Text(
      teks.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.6,
        color: context.teksKedua,
      ),
    );
  }

  Widget _barisDampak(ResetBaris b, {required bool ikutan}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              b.tabel,
              style: TextStyle(fontSize: 12, color: ikutan ? const Color(0xFF92400E) : context.teksUtama),
            ),
          ),
          Text(
            '${b.jumlah}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ikutan ? const Color(0xFF92400E) : context.teksUtama,
            ),
          ),
        ],
      ),
    );
  }

  /// Inilah bagian yang mencegah kejutan: data milik modul LAIN yang ikut
  /// terhapus karena rantai foreign key, ditampilkan terpisah dan disorot.
  Widget _kotakIkutan(ResetPreview p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.link, size: 15, color: Color(0xFFB45309)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ikut terhapus karena saling terkait',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Data ini milik modul lain, tetapi tidak bisa dipertahankan bila '
            'data di atas dihapus.',
            style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF92400E)),
          ),
          const SizedBox(height: 10),
          ...p.ikutan.map((b) => _barisDampak(b, ikutan: true)),
        ],
      ),
    );
  }

  Widget _tombolUnduh() {
    if (_sudahUnduh) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: _hijauMuda, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 16, color: _hijau),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Cadangan sudah diunduh.',
                style: TextStyle(fontSize: 12, color: _hijau, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: _sedangKirim ? null : _unduh,
              style: TextButton.styleFrom(
                foregroundColor: _hijau,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Unduh lagi', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _sedangKirim ? null : _unduh,
        style: OutlinedButton.styleFrom(
          foregroundColor: _hijau,
          side: const BorderSide(color: _hijau),
          minimumSize: const Size(double.infinity, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.download, size: 16),
        label: const Text(
          'Unduh Cadangan Sekarang',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
