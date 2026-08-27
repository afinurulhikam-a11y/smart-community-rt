import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../core/responsif.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';

/// Perilaku scroll mendatar yang mengizinkan gesture sentuh, mouse drag, dan trackpad.
class _PerilakuScrollMendatar extends MaterialScrollBehavior {
  const _PerilakuScrollMendatar();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

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
class TabelResponsif extends StatefulWidget {
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

  // Pagination controls
  final int? currentPage;
  final int? totalPages;
  final int? totalData;

  /// Jumlah data per halaman — dipakai menghitung rentang pada ringkasan
  /// "Menampilkan X–Y dari Z". Default 10 menyesuaikan batas backend.
  final int? perPage;

  /// Bila `true`, footer hanya memuat pagination (Previous/Next + "Halaman X
  /// dari Y") yang di tengah, TANPA ringkasan "Menampilkan X–Y dari Z".
  /// Dipakai Bantuan Sosial; layar lain yang ingin ringkasan diputar default.
  final bool footerTerpusat;
  final ValueChanged<int>? onPageChanged;

  const TabelResponsif({
    super.key,
    required this.kolom,
    required this.baris,
    this.judulKolom,
    this.kosong,
    this.labelAksi = 'AKSI',
    this.tinggiBarisMin = 60,
    this.tinggiBarisMaks = 80,
    this.currentPage,
    this.totalPages,
    this.totalData,
    this.perPage,
    this.footerTerpusat = false,
    this.onPageChanged,
  });

  /// Fungsi, bukan konstanta statis: warnanya kini berasal dari tema, dan tema
  /// hanya bisa dibaca lewat `context`.
  static TextStyle _gayaJudulKolom(BuildContext context) => TextStyle(
    color: context.teksKedua,
    fontSize: 11,
    fontWeight: FontWeight.bold,
  );

  @override
  State<TabelResponsif> createState() => _TabelResponsifState();
}

class _TabelResponsifState extends State<TabelResponsif> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _adaAksi => widget.baris.any((b) => b.aksi != null);

  /// Rapatkan isi kolom aksi ke tepi kiri kolomnya.
  Widget _rapatkanAksi(BuildContext context, Widget aksi) {
    final tema = Theme.of(context);
    final gayaLama = tema.iconButtonTheme.style ?? const ButtonStyle();

    return Theme(
      data: tema.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: gayaLama.copyWith(
            alignment: Alignment.centerLeft,
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          ),
        ),
      ),
      child: aksi,
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.baris.every((b) => b.sel.length == widget.kolom.length),
      'Jumlah sel harus sama dengan jumlah kolom (${widget.kolom.length}). '
      'Ketidakcocokan ini membuat DataTable melempar galat saat dirender.',
    );

    if (widget.baris.isEmpty) {
      return widget.kosong ??
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('Belum ada data.', style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
    }

    Widget content = pakaiKartu(context) ? _daftarKartu(context) : _tabel(context);

    // Footer ringkasan + pagination. Ditampilkan bila totalData diberikan
    // (satu-satunya cara tahu rentang "Menampilkan X–Y dari Z" yang benar) —
    // termasuk saat cuma satu halaman, supaya ringkasannya tetap terbaca.
    // Layar yang tidak mengirim totalData memakai pagination lama di bawah.
    if (widget.totalData != null && widget.currentPage != null && widget.totalPages != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const Divider(height: 1),
          _buildFooter(context),
        ],
      );
    }

    if (widget.currentPage != null && widget.totalPages != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const SizedBox(height: 16),
          _buildPagination(context),
        ],
      );
    }
    return content;
  }

  Widget _pageBtn(
    BuildContext context,
    String text,
    bool aktif,
    VoidCallback? onTap,
  ) {
    final mati = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: aktif
              ? const Color(0xFF3B82F6)
              : (mati ? context.latarLembut : context.latarKartu),
          border: Border.all(
            color: aktif ? const Color(0xFF3B82F6) : context.garis,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: aktif
                ? Colors.white
                : (mati ? context.teksTersier : context.teksKedua),
            fontWeight: aktif ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final halaman = widget.currentPage ?? 1;
    final totalHal = widget.totalPages ?? 1;
    final per = widget.perPage ?? 10;
    final total = widget.totalData ?? 0;

    // Rentang baris yang sedang tampil, mis. "1–10". Dihitung dari halaman,
    // bukan dari panjang baris, agar benar walau halaman terakhir lebih pendek.
    final mulai = (halaman - 1) * per + 1;
    final akhir = (halaman * per) > total ? total : halaman * per;

    int startPage = 1;
    int endPage = totalHal;
    if (totalHal > 5) {
      if (halaman <= 3) {
        startPage = 1;
        endPage = 5;
      } else if (halaman >= totalHal - 2) {
        startPage = totalHal - 4;
        endPage = totalHal;
      } else {
        startPage = halaman - 2;
        endPage = halaman + 2;
      }
    }

    Widget pagination() => Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _pageBtn(
          context,
          '<',
          false,
          halaman > 1 ? () => widget.onPageChanged?.call(halaman - 1) : null,
        ),
        for (int p = startPage; p <= endPage; p++)
          _pageBtn(
            context,
            '$p',
            p == halaman,
            () => widget.onPageChanged?.call(p),
          ),
        _pageBtn(
          context,
          '>',
          false,
          halaman < totalHal ? () => widget.onPageChanged?.call(halaman + 1) : null,
        ),
      ],
    );

    // Mode terpusat: hanya pagination ditampilkan, tanpa ringkasan, dan
    // berada di tengah baris.
    if (widget.footerTerpusat) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: pagination()),
      );
    }

    return Padding(
      padding: EdgeInsets.all(paddingKartu(context)),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Text(
            total == 0
                ? 'Tidak ada data'
                : 'Menampilkan $mulai – $akhir dari $total data',
            style: TextStyle(fontSize: 13, color: context.teksKedua),
          ),
          pagination(),
        ],
      ),
    );
  }

  Widget _buildPagination(BuildContext context) {
    final halaman = widget.currentPage ?? 1;
    final totalHal = widget.totalPages ?? 1;

    int startPage = 1;
    int endPage = totalHal;
    if (totalHal > 5) {
      if (halaman <= 3) {
        startPage = 1;
        endPage = 5;
      } else if (halaman >= totalHal - 2) {
        startPage = totalHal - 4;
        endPage = totalHal;
      } else {
        startPage = halaman - 2;
        endPage = halaman + 2;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _pageBtn(
              context,
              '<',
              false,
              halaman > 1 ? () => widget.onPageChanged?.call(halaman - 1) : null,
            ),
            for (int p = startPage; p <= endPage; p++)
              _pageBtn(
                context,
                '$p',
                p == halaman,
                () => widget.onPageChanged?.call(p),
              ),
            _pageBtn(
              context,
              '>',
              false,
              halaman < totalHal ? () => widget.onPageChanged?.call(halaman + 1) : null,
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- tabel

  Widget _tabel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double targetWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 0.0;
        return ScrollConfiguration(
          behavior: const _PerilakuScrollMendatar(),
          child: Scrollbar(
            controller: _scrollController,
            interactive: true,
            thickness: 6.0,
            radius: const Radius.circular(3.0),
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: targetWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  dataRowMinHeight: widget.tinggiBarisMin,
                  dataRowMaxHeight: widget.tinggiBarisMaks,
                  headingTextStyle: TabelResponsif._gayaJudulKolom(context),
                  dataTextStyle: Theme.of(context).textTheme.bodyMedium,
                  columns: [
                    for (int i = 0; i < widget.kolom.length; i++)
                      DataColumn(label: widget.judulKolom?[i] ?? Text(widget.kolom[i])),
                    if (_adaAksi) DataColumn(label: Text(widget.labelAksi)),
                  ],
                  rows: [
                    for (final b in widget.baris)
                      DataRow(
                        color: b.warna == null ? null : WidgetStatePropertyAll(b.warna!),
                        onSelectChanged: b.onTap == null ? null : (_) => b.onTap!(),
                        cells: [
                          for (final s in b.sel) DataCell(s.isi),
                          if (_adaAksi)
                            DataCell(
                              b.aksi == null
                                  ? const SizedBox.shrink()
                                  : _rapatkanAksi(context, b.aksi!),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
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
        for (int i = 0; i < widget.baris.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _kartu(context, widget.baris[i]),
        ],
      ],
    );
  }

  Widget _kartu(BuildContext context, BarisTabel b) {
    final utama = b.sel.where((s) => s.utama && !s.sembunyiDiKartu).toList();
    final sisa = b.sel.where((s) => !s.utama && !s.sembunyiDiKartu).toList();
    final teks = Theme.of(context).textTheme;

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
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: DefaultTextStyle.merge(style: teks.bodyMedium!, child: s.isi),
          ),
        ),
      ],
    );
  }
}
