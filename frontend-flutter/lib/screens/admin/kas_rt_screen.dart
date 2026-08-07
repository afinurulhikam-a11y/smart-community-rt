import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/responsif.dart';
import '../../../providers/aksi_utama_provider.dart';
import '../../../providers/finance_provider.dart';
import '../../../providers/kategori_kas_provider.dart';
import '../../../models/finance_model.dart';
import '../../../models/kategori_kas_model.dart';
import '../../../providers/permission_provider.dart';
import '../../../widgets/banner_lihat_saja.dart';
import '../../../widgets/tabel_responsif.dart';
import '../../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/format.dart';
import '../../core/pesan.dart';

const List<String> _namaBulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

const Color _hijau = Color(0xFF1B7A6A);
const Color _merah = Color(0xFFEF4444);
const Color _hijauTerang = Color(0xFF059669);

class KasRtScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const KasRtScreen({super.key, this.onBack});

  @override
  State<KasRtScreen> createState() => _KasRtScreenState();
}

/// Kode modul di tabel izin. Sekretaris hanya punya `view` di sini.
const String _kodeIzin = 'keuangan.kas';

class _KasRtScreenState extends State<KasRtScreen> {
  // Menyembunyikan tombol bukan kontrol akses — backend tetap penjaga
  // sesungguhnya. Ini agar pengguna tidak disodori tombol yang pasti 403.
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);

  String _searchQuery = '';
  String _tipe = 'Semua Jenis';
  String _bulan = 'Semua Bulan';
  String _tahun = DateTime.now().year.toString();

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KategoriKasProvider>().fetchKategoriKas();
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Ubah "Juli" + "2026" menjadi "2026-07" sesuai format yang dituntut backend.
  String? get _periodeFilter {
    if (_bulan == 'Semua Bulan') return null;
    final idx = _namaBulan.indexOf(_bulan);
    if (idx < 0) return null;
    return '$_tahun-${(idx + 1).toString().padLeft(2, '0')}';
  }

  void _loadData({int page = 1}) {
    context.read<FinanceProvider>().fetchTransactions(
      tipe: _tipe == 'Semua Jenis' ? null : (_tipe == 'Pemasukan' ? 'pemasukan' : 'pengeluaran'),
      bulan: _periodeFilter,
      tahun: _periodeFilter == null ? _tahun : null,
      search: _searchQuery.isEmpty ? null : _searchQuery,
      page: page,
    );
  }

  String _rupiah(double amount) => rupiah(amount);

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FinanceProvider>();
    final halamanIni = provider.transactions;
    final totalHalaman = provider.totalPages;
    final currentPage = provider.currentPage;
    final totalData = provider.totalData;
    final mulai = (currentPage - 1) * 25;
    final akhir = (mulai + halamanIni.length).clamp(0, totalData);

    // Aksi utama layar ini: mencatat pemasukan. Kerangka aplikasi yang
    // menggambarnya sebagai FAB — lihat AksiUtamaProvider.
    final aksi = context.read<AksiUtamaProvider>();
    if (_bolehTambah && pakaiKartu(context)) {
      aksi.pasang(
        aksi: () => _showFormTransaksi('pemasukan'),
        label: 'Pemasukan',
        ikon: Icons.add,
      );
    } else {
      aksi.lepas();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BannerLihatSaja(kode: _kodeIzin),
        _buildHeader(),
        const SizedBox(height: 24),
        _buildSummaryCards(provider),
        const SizedBox(height: 24),
        _buildFilters(),
        const SizedBox(height: 24),
        _buildTableCard(provider, halamanIni, totalHalaman, mulai, akhir, totalData, currentPage),
        const SizedBox(height: 32),
      ],
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeader() {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 16,
        children: [
          if (!pakaiKartu(context))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TombolKembali(onPressed: widget.onBack),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _hijau.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_balance_rounded, color: _hijau, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Keuangan / Kas RT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.teksKedua,
                    ),
                  ),
                ),
              ],
            ),
          // Tombol "Transfer Kas" sengaja tidak ada: RT ini hanya punya satu
          // kantong kas, jadi tidak ada tujuan pemindahan dana.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (_bolehTambah)
                _filledBtn(
                  Icons.arrow_downward,
                  'Pemasukan',
                  _hijauTerang,
                  () => _showFormTransaksi('pemasukan'),
                ),
              if (_bolehTambah)
                _filledBtn(
                  Icons.arrow_upward,
                  'Pengeluaran',
                  _merah,
                  () => _showFormTransaksi('pengeluaran'),
                ),
              if (_bolehUbah)
                _outlinedBtn(
                  Icons.account_balance_wallet,
                  'Master Kas',
                  _hijau,
                  _showMasterKasDialog,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- summary cards

  Widget _buildSummaryCards(FinanceProvider provider) {
    final s = provider.summary;
    final labelPeriode = _periodeFilter == null ? 'BULAN INI' : 'PERIODE DIPILIH';

    return LayoutBuilder(
      builder: (context, c) {
        final kolom = c.maxWidth > 900 ? 3 : 1;
        final lebar = (c.maxWidth - (16 * (kolom - 1))) / kolom;
        final kartu = [
          _summaryCard('PEMASUKAN $labelPeriode', _rupiah(s?.pemasukanBulan ?? 0), const [
            Color(0xFF0D9488),
            Color(0xFF14B8A6),
          ], Icons.trending_up),
          _summaryCard('PENGELUARAN $labelPeriode', _rupiah(s?.pengeluaranBulan ?? 0), const [
            Color(0xFFDC2626),
            Color(0xFFEF4444),
          ], Icons.trending_down),
          // Saldo selalu sepanjang masa — tidak ikut tersaring periode, sesuai
          // labelnya "SAAT INI".
          _summaryCard('SALDO KAS SAAT INI', _rupiah(s?.saldoTotal ?? 0), const [
            Color(0xFF1E3A5F),
            Color(0xFF334155),
          ], Icons.account_balance_wallet),
        ];
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: kartu.map((w) => SizedBox(width: lebar, child: w)).toList(),
        );
      },
    );
  }

  Widget _summaryCard(String label, String value, List<Color> colors, IconData icon) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 32),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- filters

  Widget _buildFilters() {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _dropdownFilter('Jenis', _tipe, const ['Semua Jenis', 'Pemasukan', 'Pengeluaran'], (v) {
            setState(() => _tipe = v!);
            _loadData();
          }),
          _dropdownFilter('Bulan', _bulan, ['Semua Bulan', ..._namaBulan], (v) {
            setState(() => _bulan = v!);
            _loadData();
          }),
          _dropdownFilter(
            'Tahun',
            _tahun,
            List.generate(5, (i) => (DateTime.now().year - 2 + i).toString()),
            (v) {
              setState(() => _tahun = v!);
              _loadData();
            },
          ),
          // Tanpa tombol "Filter": setiap dropdown langsung memuat ulang saat
          // nilainya berubah, jadi tombol itu hanya duplikasi. Yang tersisa
          // hanyalah Reset untuk mengembalikan semua filter ke awal.
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _tipe = 'Semua Jenis';
                _bulan = 'Semua Bulan';
                _tahun = DateTime.now().year.toString();
                _searchQuery = '';
                _searchController.clear();
              });
              _loadData();
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text(
              'Reset',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.teksKedua,
              side: BorderSide(color: context.garis),
              minimumSize: const Size(0, AppTheme.sasaranSentuh),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownFilter(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.teksKedua)),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
          // Selebar layar di ponsel: dengan 180 tetap, tiap filter tetap
          // turun ke barisnya sendiri tetapi menyisakan ruang kosong di
          // kanannya — itu yang membuat tampilan terlihat berserakan.
          width: lebarKolomFilter(context),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: context.garis),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, size: 16, color: context.teksKedua),
              style: TextStyle(fontSize: 13, color: context.teksUtama),
              items: items.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- table

  Widget _buildTableCard(
    FinanceProvider provider,
    List<FinanceModel> halamanIni,
    int totalHalaman,
    int mulai,
    int akhir,
    int totalData,
    int currentPage,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: paddingKartu(context), vertical: 16),
            // Label di tengah, tombol laporan di kanan atas sejajar labelnya —
            // pada layar lebar. Di layar sempit keduanya tidak muat satu baris,
            // jadi tombol turun ke barisnya sendiri (LayoutBuilder memilih).
            child: LayoutBuilder(
              builder: (context, constraints) {
                final label = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    // Flexible + ellipsis: di layar 320px judul ini bersama
                    // ikonnya melampaui lebar kartu.
                    Flexible(
                      child: Text(
                        'Riwayat Transaksi',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: context.teksUtama,
                        ),
                      ),
                    ),
                  ],
                );
                final tombol = Wrap(
                  spacing: 8,
                  children: [
                    _outlinedBtn(
                      Icons.table_chart_outlined,
                      'Laporan Excel',
                      const Color(0xFF10B981),
                      () => provider.downloadExport(format: 'excel'),
                      kecil: true,
                    ),
                    _outlinedBtn(
                      Icons.picture_as_pdf_outlined,
                      'Laporan PDF',
                      _merah,
                      () => provider.downloadExport(format: 'pdf'),
                      kecil: true,
                    ),
                  ],
                );

                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: label),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: tombol),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: Center(child: label)),
                    const SizedBox(width: 12),
                    tombol,
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(paddingKartu(context)),
            // Kolom pencarian diletakkan di tengah dengan label "Pencarian" di
            // kiri kolomnya. Tidak memakai lebarKolomFilter di sini: nilainya
            // double.infinity pada mobile, yang tidak aman di dalam Row —
            // ConstrainedBox + Expanded membuat lebar selalu berhingga.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Row(
                  children: [
                    Text(
                      'Pencarian',
                      style: TextStyle(fontSize: 13, color: context.teksKedua),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: (v) {
                          _searchQuery = v;
                          _loadData();
                        },
                        decoration: InputDecoration(
                          hintText: 'Cari keterangan / kategori...',
                          hintStyle: TextStyle(fontSize: 12, color: context.teksTersier),
                          prefixIcon: Icon(Icons.search, size: 18, color: context.teksKedua),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            onPressed: () {
                              _searchQuery = _searchController.text;
                              _loadData();
                            },
                          ),
                          filled: true,
                          fillColor: context.latarLembut,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.garis),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.garis),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (provider.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (halamanIni.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 40, color: context.garis),
                    SizedBox(height: 12),
                    Text(
                      'Belum ada transaksi',
                      style: TextStyle(color: context.teksTersier, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Pembayaran iuran warga akan otomatis muncul di sini.',
                      style: TextStyle(color: context.garis, fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: pakaiKartu(context) ? 12 : 0,
                vertical: pakaiKartu(context) ? 12 : 0,
              ),
              child: TabelResponsif(
                kolom: const [
                  'NO',
                  'TANGGAL',
                  'JENIS',
                  'KATEGORI',
                  'KETERANGAN',
                  'PEMASUKAN',
                  'PENGELUARAN',
                  'SALDO',
                ],
                baris: List.generate(
                  halamanIni.length,
                  (i) => _buildRow(halamanIni[i], mulai + i + 1),
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(paddingKartu(context)),
            // Wrap: keterangan jumlah data dan tombol halaman bersama memakan
            // sekitar 460px, jauh di atas ~296px yang tersedia di ponsel.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Text(
                  totalData == 0
                      ? 'Tidak ada data'
                      : 'Menampilkan ${mulai + 1} – $akhir dari $totalData transaksi',
                  style: TextStyle(fontSize: 13, color: context.teksKedua),
                ),
                // Wrap, bukan Row. Tujuh tombol (< 1 2 3 4 5 >) dalam sebuah Row
                // tidak bisa pindah baris: pada font sistem 1,3x lebarnya
                // ±358px di ruang 336px, melimpah 8,7px. Dengan Wrap, tombol
                // yang tidak muat turun ke baris berikutnya.
                //
                // Jaraknya diatur `spacing`/`runSpacing`, BUKAN SizedBox di
                // antara anak-anaknya — sebuah SizedBox di dalam Wrap menjadi
                // item tersendiri, bukan pemisah, sehingga jaraknya jadi tidak
                // rata begitu barisnya membungkus.
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _pageBtn(
                      '<',
                      false,
                      currentPage > 1 ? () => _loadData(page: currentPage - 1) : null,
                    ),
                    ...List.generate(totalHalaman.clamp(0, 5), (i) {
                      final n = i + 1;
                      return _pageBtn(
                        '$n',
                        n == currentPage,
                        () => _loadData(page: n),
                      );
                    }),
                    _pageBtn(
                      '>',
                      false,
                      currentPage < totalHalaman ? () => _loadData(page: currentPage + 1) : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BarisTabel _buildRow(FinanceModel t, int nomor) {
    final masuk = t.isPemasukan;
    return BarisTabel(
      sel: [
        // Nomor urut hanya berguna dalam bentuk tabel; di kartu ia tidak
        // menambah apa pun, jadi disembunyikan di sana.
        SelTabel.teks('NO', '$nomor', sembunyiDiKartu: true),
        SelTabel.teks('TANGGAL', DateFormat('dd MMM yyyy').format(t.tanggal)),
        SelTabel(
          'JENIS',
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: masuk ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  masuk ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 12,
                  color: masuk ? _hijauTerang : _merah,
                ),
                const SizedBox(width: 4),
                Text(
                  masuk ? 'MASUK' : 'KELUAR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: masuk ? _hijauTerang : _merah,
                  ),
                ),
              ],
            ),
          ),
        ),
        SelTabel.teks('KATEGORI', t.kategori),
        SelTabel(
          'KETERANGAN',
          // Lebar 240 hanya berlaku untuk bentuk tabel. Di kartu isinya
          // memakai sisa lebar layar lewat Expanded milik TabelResponsif.
          SizedBox(
            width: pakaiKartu(context) ? null : 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.deskripsi,
                  style: TextStyle(fontSize: 12, color: context.teksUtama),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // Baris hasil pembayaran iuran ditandai agar jelas kenapa tombol
                // ubah dan hapusnya mati.
                if (t.dariIuran)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'dari iuran',
                      style: TextStyle(fontSize: 9, color: Color(0xFF0369A1)),
                    ),
                  ),
              ],
            ),
          ),
          utama: true,
        ),
        SelTabel.teks(
          'PEMASUKAN',
          masuk ? _rupiah(t.jumlah) : '-',
          gaya: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _hijauTerang),
        ),
        SelTabel.teks(
          'PENGELUARAN',
          !masuk ? _rupiah(t.jumlah) : '-',
          gaya: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _merah),
        ),
        SelTabel.teks(
          'SALDO',
          _rupiah(t.saldoBerjalan),
          gaya: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.teksUtama,
          ),
        ),
      ],
      // Dua penjagaan yang berbeda dan keduanya perlu: `bolehDiubah` soal
      // aturan data (baris dari pembayaran iuran dikoreksi lewat Iuran
      // Warga), sedangkan izin soal wewenang role.
      aksi: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_bolehUbah)
            IconButton(
              tooltip: t.bolehDiubah
                  ? 'Ubah'
                  : 'Transaksi dari pembayaran iuran tidak bisa diubah di sini',
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: t.bolehDiubah ? const Color(0xFF3B82F6) : context.garis,
              ),
              onPressed: t.bolehDiubah ? () => _showFormTransaksi(t.tipe, existing: t) : null,
            ),
          if (!_bolehUbah)
            Text('—', style: TextStyle(fontSize: 13, color: context.teksTersier)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- tombol

  Widget _filledBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  Widget _outlinedBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap, {
    bool kecil = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: kecil ? 14 : 16, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontSize: kecil ? 12 : 13, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        padding: EdgeInsets.symmetric(horizontal: kecil ? 12 : 16, vertical: kecil ? 8 : 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kecil ? 8 : 24)),
      ),
    );
  }

  Widget _pageBtn(String text, bool aktif, VoidCallback? onTap) {
    final mati = onTap == null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          // `context.latarKartu`, bukan Colors.white — sisa migrasi mode gelap
          // yang terlewat: tombol halaman yang tidak aktif tetap putih di atas
          // latar gelap.
          color: aktif ? const Color(0xFF3B82F6) : (mati ? context.latarLembut : context.latarKartu),
          border: Border.all(color: aktif ? const Color(0xFF3B82F6) : context.garis),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: aktif ? Colors.white : (mati ? context.teksTersier : context.teksKedua),
            fontWeight: aktif ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- dialogs



  void _showFormTransaksi(String tipe, {FinanceModel? existing}) {
    final kategoriList = context.read<KategoriKasProvider>().untukTipe(tipe);
    if (kategoriList.isEmpty) {
      _pesan(
        'Belum ada kategori ${tipe == 'pemasukan' ? 'pemasukan' : 'pengeluaran'} yang aktif. '
        'Tambahkan lewat tombol "Master Kas".',
        sukses: false,
      );
      return;
    }

    int? kategoriId =
        existing?.kategoriId ??
        (kategoriList.any((k) => k.id == existing?.kategoriId)
            ? existing!.kategoriId
            : kategoriList.first.id);
    if (!kategoriList.any((k) => k.id == kategoriId)) kategoriId = kategoriList.first.id;

    final jumlahCtrl = TextEditingController(
      text: existing == null ? '' : existing.jumlah.toStringAsFixed(0),
    );
    final deskripsiCtrl = TextEditingController(text: existing?.deskripsi ?? '');
    final tanggalCtrl = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(existing?.tanggal ?? DateTime.now()),
    );

    final masuk = tipe == 'pemasukan';

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                masuk ? Icons.arrow_downward : Icons.arrow_upward,
                color: masuk ? _hijauTerang : _merah,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                existing == null
                    ? (masuk ? 'Catat Pemasukan' : 'Catat Pengeluaran')
                    : 'Ubah Transaksi',
              ),
            ],
          ),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tanggalCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Tanggal',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  onTap: () async {
                    final dipilih = await showDatePicker(
                      context: c,
                      initialDate: existing?.tanggal ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (dipilih != null) {
                      tanggalCtrl.text = DateFormat('yyyy-MM-dd').format(dipilih);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: kategoriId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: kategoriList
                      .map((k) => DropdownMenuItem(value: k.id, child: Text(k.namaKategori)))
                      .toList(),
                  onChanged: (v) => setLocal(() => kategoriId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: jumlahCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah (Rp)',
                    prefixIcon: Icon(Icons.attach_money, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deskripsiCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Keterangan'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final jumlah = double.tryParse(jumlahCtrl.text);
                if (jumlah == null || jumlah <= 0) {
                  _pesan('Jumlah harus berupa angka lebih dari 0.', sukses: false);
                  return;
                }
                if (deskripsiCtrl.text.trim().isEmpty) {
                  _pesan('Keterangan wajib diisi.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final prov = context.read<FinanceProvider>();
                final hasil = existing == null
                    ? await prov.createTransaction(
                        tipe: tipe,
                        jumlah: jumlah,
                        deskripsi: deskripsiCtrl.text.trim(),
                        kategoriId: kategoriId,
                        tanggal: tanggalCtrl.text,
                      )
                    : await prov.updateTransaction(
                        existing.id,
                        tipe: tipe,
                        jumlah: jumlah,
                        deskripsi: deskripsiCtrl.text.trim(),
                        kategoriId: kategoriId,
                        tanggal: tanggalCtrl.text,
                      );
                _pesan(
                  hasil['message']?.toString() ?? 'Selesai.',
                  sukses: hasil['success'] == true,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: masuk ? _hijauTerang : _merah),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showMasterKasDialog() {
    showDialog(
      context: context,
      builder: (c) => Consumer<KategoriKasProvider>(
        builder: (c2, prov, _) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Kelola Kategori Kas'),
              IconButton(
                icon: const Icon(Icons.add_circle, color: _hijau),
                tooltip: 'Tambah kategori',
                onPressed: () => _showFormKategori(null),
              ),
            ],
          ),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 560),
            height: 400,
            child: prov.isLoading
                ? const Center(child: CircularProgressIndicator())
                : prov.list.isEmpty
                ? const Center(child: Text('Belum ada kategori.'))
                : ListView.separated(
                    itemCount: prov.list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final k = prov.list[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          k.isPemasukan ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 18,
                          color: k.isAktif
                              ? (k.isPemasukan ? _hijauTerang : _merah)
                              : context.teksTersier,
                        ),
                        title: Text(
                          k.namaKategori,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: k.isAktif ? null : context.teksKedua,
                          ),
                        ),
                        subtitle: Text(
                          '${k.tipeLabel} · ${k.jumlahTransaksi} transaksi'
                          '${k.isAktif ? '' : ' · nonaktif'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Ubah',
                              onPressed: () => _showFormKategori(k),
                            ),
                            IconButton(
                              icon: Icon(
                                k.isAktif ? Icons.toggle_on : Icons.toggle_off,
                                size: 22,
                                color: k.isAktif ? const Color(0xFF10B981) : context.teksKedua,
                              ),
                              tooltip: k.isAktif ? 'Nonaktifkan' : 'Aktifkan',
                              onPressed: () async {
                                final r = await prov.update(k.id, isAktif: !k.isAktif);
                                _pesan(
                                  r['message']?.toString() ?? 'Selesai.',
                                  sukses: r['success'] == true,
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: k.bisaDihapus ? _merah : context.garis,
                              ),
                              // Backend juga menolak, tapi menonaktifkan tombol
                              // lebih jujur daripada memunculkan error.
                              tooltip: k.bisaDihapus
                                  ? 'Hapus'
                                  : 'Tidak bisa dihapus, sudah dipakai transaksi',
                              onPressed: k.bisaDihapus
                                  ? () async {
                                      final r = await prov.delete(k.id);
                                      _pesan(
                                        r['message']?.toString() ?? 'Selesai.',
                                        sukses: r['success'] == true,
                                      );
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup'))],
        ),
      ),
    );
  }

  void _showFormKategori(KategoriKasModel? existing) {
    final namaCtrl = TextEditingController(text: existing?.namaKategori ?? '');
    final ketCtrl = TextEditingController(text: existing?.keterangan ?? '');
    String tipe = existing?.tipe ?? 'IN';
    // Tipe kategori yang sudah dipakai tidak boleh diubah, karena akan membuat
    // transaksi lama bertentangan dengan tipenya sendiri.
    final tipeTerkunci = existing != null && existing.jumlahTransaksi > 0;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'Tambah Kategori' : 'Ubah Kategori'),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: namaCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Kategori *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tipe,
                  decoration: InputDecoration(
                    labelText: 'Tipe',
                    helperText: tipeTerkunci
                        ? 'Terkunci: kategori sudah dipakai ${existing.jumlahTransaksi} transaksi'
                        : null,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('Pemasukan')),
                    DropdownMenuItem(value: 'OUT', child: Text('Pengeluaran')),
                  ],
                  onChanged: tipeTerkunci ? null : (v) => setLocal(() => tipe = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ketCtrl,
                  decoration: const InputDecoration(labelText: 'Keterangan (opsional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                if (namaCtrl.text.trim().isEmpty) {
                  _pesan('Nama kategori wajib diisi.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final prov = context.read<KategoriKasProvider>();
                final r = existing == null
                    ? await prov.create(
                        namaKategori: namaCtrl.text.trim(),
                        tipe: tipe,
                        keterangan: ketCtrl.text.trim(),
                      )
                    : await prov.update(
                        existing.id,
                        namaKategori: namaCtrl.text.trim(),
                        tipe: tipeTerkunci ? null : tipe,
                        keterangan: ketCtrl.text.trim(),
                      );
                _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _hijau),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
