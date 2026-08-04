import 'package:flutter/material.dart';

import '../core/responsif.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';

/// Satu sel: isi kolom beserta nama kolomnya.
///
/// [label] dipakai dua kali — sebagai judul kolom di tabel, dan sebagai label
/// di sebelah nilainya ketika baris berubah menjadi kartu. Menyatukannya
/// mencegah tabel dan kartu perlahan menyimpang isinya.
class SelTabel {
  /// Nama kolom, mis. `'TANGGAL'`.
  final String label;

  /// Isi selnya. Boleh widget apa pun — lencana, tombol, teks berwarna.
  final Widget isi;

  /// Jadikan sel ini judul kartu: ditampilkan menonjol di baris paling atas,
  /// tanpa label. Biasanya kolom nama atau keterangan.
  final bool utama;

  /// Sembunyikan sel ini dari kartu, tetapi tetap tampilkan di tabel.
  /// Dipakai untuk kolom yang hanya berguna dalam bentuk tabel — nomor urut,
  /// misalnya, yang di kartu tidak menambah apa pun.
  final bool sembunyiDiKartu;

  const SelTabel(this.label, this.isi, {this.utama = false, this.sembunyiDiKartu = false});

  /// Pintasan untuk sel berisi teks biasa.
  ///
  /// Tanpa [gaya], teksnya sengaja TIDAK diberi gaya apa pun di sini — ia
  /// mewarisi `DefaultTextStyle` dari kartu atau `dataTextStyle` dari tabel,
  /// yang keduanya berasal dari tema. Memasang gaya di sini justru menimpa
  /// ukuran dari tema: itulah yang membuat pembesaran teks kartu ke 14sp
  /// semula tidak berpengaruh sama sekali.
  ///
  /// [gaya] tetap ada untuk sel yang maknanya bergantung pada rupa — nominal
  /// pemasukan hijau, pengeluaran merah, tanggal kosong abu-abu.
  factory SelTabel.teks(
    String label,
    String nilai, {
    bool utama = false,
    bool sembunyiDiKartu = false,
    TextStyle? gaya,
  }) {
    return SelTabel(
      label,
      Text(nilai, style: gaya),
      utama: utama,
      sembunyiDiKartu: sembunyiDiKartu,
    );
  }
}

/// Satu baris data, apa pun bentuk tampilannya.
class BarisTabel {
  /// Sel-selnya, urut sesuai `kolom` milik [TabelResponsif].
  final List<SelTabel> sel;

  /// Tombol-tombol untuk baris ini. Di tabel menjadi kolom terakhir; di kartu
  /// diletakkan di kaki kartu, dipisahkan garis.
  final Widget? aksi;

  /// Dijalankan saat kartu atau baris ditekan — biasanya membuka rincian.
  final VoidCallback? onTap;

  /// Latar penanda, mis. baris peminjaman yang lewat tempo. Berlaku sama di
  /// kedua bentuk — sebagai warna baris di tabel, dan latar kartu di ponsel.
  final Color? warna;

  const BarisTabel({required this.sel, this.aksi, this.onTap, this.warna});
}

/// Tabel di layar lebar, kartu bertumpuk di ponsel — dari data yang sama.
///
/// Ketiga belas `DataTable` di aplikasi ini sudah dibungkus scroll mendatar,
/// jadi tidak ada yang meluber. Tetapi membaca tabel sembilan kolom di layar
/// 360px berarti menggeser ke samping terus-menerus, dan judul kolomnya hilang
/// dari pandangan begitu digeser. Di ponsel setiap baris karena itu disusun
/// ulang menjadi kartu: label menempel pada nilainya, dan tidak ada geseran
/// mendatar sama sekali.
///
/// Ambangnya [pakaiKartu], sama dengan yang dipakai sidebar dan grid.
class TabelResponsif extends StatelessWidget {
  /// Judul kolom. Panjangnya harus sama dengan panjang `sel` setiap baris.
  final List<String> kolom;

  /// Judul kolom yang bukan sekadar teks, dipetakan menurut nomor kolom.
  ///
  /// Ada karena Iuran Warga memasang kotak centang "pilih semua" di kepala
  /// kolom pertamanya. [kolom] tetap wajib berisi teks untuk kolom itu, karena
  /// teks itulah yang dipakai sebagai label ketika barisnya menjadi kartu —
  /// kotak centang tidak bisa dijadikan label.
  final Map<int, Widget>? judulKolom;

  final List<BarisTabel> baris;

  /// Ditampilkan ketika [baris] kosong.
  final Widget? kosong;

  /// Judul kolom aksi di tabel. Kolomnya hanya muncul bila ada baris yang
  /// benar-benar punya tombol.
  final String labelAksi;

  final double tinggiBarisMin;
  final double tinggiBarisMaks;

  const TabelResponsif({
    super.key,
    required this.kolom,
    required this.baris,
    this.judulKolom,
    this.kosong,
    this.labelAksi = 'AKSI',
    this.tinggiBarisMin = 60,
    this.tinggiBarisMaks = 80,
  });

  /// Fungsi, bukan konstanta statis: warnanya kini berasal dari tema, dan tema
  /// hanya bisa dibaca lewat `context`.
  static TextStyle _gayaJudulKolom(BuildContext context) => TextStyle(
    color: context.teksKedua,
    fontSize: 11,
    fontWeight: FontWeight.bold,
  );

  bool get _adaAksi => baris.any((b) => b.aksi != null);

  @override
  Widget build(BuildContext context) {
    assert(
      baris.every((b) => b.sel.length == kolom.length),
      'Jumlah sel harus sama dengan jumlah kolom (${kolom.length}). '
      'Ketidakcocokan ini membuat DataTable melempar galat saat dirender.',
    );

    if (baris.isEmpty) {
      return kosong ??
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('Belum ada data.', style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
    }

    return pakaiKartu(context) ? _daftarKartu(context) : _tabel(context);
  }

  // --------------------------------------------------------------- tabel

  Widget _tabel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double targetWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 0.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: targetWidth),
            child: DataTable(
              dataRowMinHeight: tinggiBarisMin,
              dataRowMaxHeight: tinggiBarisMaks,
              headingTextStyle: _gayaJudulKolom(context),
              dataTextStyle: Theme.of(context).textTheme.bodyMedium,
              columns: [
                for (int i = 0; i < kolom.length; i++)
                  DataColumn(label: judulKolom?[i] ?? Text(kolom[i])),
                if (_adaAksi) DataColumn(label: Center(child: Text(labelAksi))),
              ],
              rows: [
                for (final b in baris)
                  DataRow(
                    color: b.warna == null ? null : WidgetStatePropertyAll(b.warna!),
                    onSelectChanged: b.onTap == null ? null : (_) => b.onTap!(),
                    cells: [
                      for (final s in b.sel) DataCell(s.isi),
                      // Baris tanpa tombol tetap butuh selnya, kalau tidak jumlah sel
                      // tidak cocok dengan jumlah kolom dan DataTable melempar galat.
                      if (_adaAksi) DataCell(Center(child: b.aksi ?? const SizedBox.shrink())),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- kartu

  Widget _daftarKartu(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < baris.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _kartu(context, baris[i]),
        ],
      ],
    );
  }

  Widget _kartu(BuildContext context, BarisTabel b) {
    final utama = b.sel.where((s) => s.utama && !s.sembunyiDiKartu).toList();
    final sisa = b.sel.where((s) => !s.utama && !s.sembunyiDiKartu).toList();
    final teks = Theme.of(context).textTheme;

    // Card, bukan Container berhias sendiri: warna, radius, dan garis tepinya
    // datang dari tema, jadi kartu di sini tidak akan menyimpang dari kartu
    // lain saat temanya berubah — termasuk saat mode gelap dinyalakan.
    return Card(
      color: b.warna,
      child: InkWell(
        onTap: b.onTap,
        borderRadius: AppTheme.borderRadiusL,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spasiL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in utama) ...[
                DefaultTextStyle.merge(style: teks.titleMedium!, child: s.isi),
                const SizedBox(height: AppTheme.spasiM),
              ],
              for (int i = 0; i < sisa.length; i++) ...[
                if (i > 0) const SizedBox(height: AppTheme.spasiS),
                _barisLabel(context, sisa[i]),
              ],
              if (b.aksi != null) ...[
                const Divider(height: AppTheme.spasiXl),
                Align(alignment: Alignment.centerRight, child: b.aksi!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _barisLabel(BuildContext context, SelTabel s) {
    final teks = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 104, child: Text(s.label, style: teks.bodySmall)),
        const SizedBox(width: AppTheme.spasiS),
        // Expanded, bukan lebar tetap: isinya bisa teks panjang, lencana,
        // atau apa pun, dan hanya sisa ruang yang tersedia untuknya.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            // bodyMedium = 14sp. Nilai di kartu dulu 13px dan labelnya 11px —
            // kerapatan dasbor desktop, dan itulah yang membuat daftar di
            // ponsel terbaca berdesakan.
            child: DefaultTextStyle.merge(style: teks.bodyMedium!, child: s.isi),
          ),
        ),
      ],
    );
  }
}
