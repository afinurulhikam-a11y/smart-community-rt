import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../providers/bop_provider.dart';
import '../../providers/kategori_bop_provider.dart';
import '../../providers/alokasi_bop_provider.dart';
import '../../models/finance_model.dart';
import '../../models/bop_model.dart';
import '../../models/kategori_kas_model.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/banner_lihat_saja.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
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

const List<String> _opsiTermin = [
  'Tahunan',
  'Triwulan I',
  'Triwulan II',
  'Triwulan III',
  'Triwulan IV',
  'Semester I',
  'Semester II',
];

const Color _hijau = Color(0xFF1B7A6A);
const Color _merah = Color(0xFFEF4444);
const Color _hijauTerang = Color(0xFF059669);

class BopScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const BopScreen({super.key, this.onBack});

  @override
  State<BopScreen> createState() => _BopScreenState();
}

/// Kode modul di tabel izin. Sekretaris hanya punya `view` di sini.
const String _kodeIzin = 'keuangan.bop';

class _BopScreenState extends State<BopScreen> {
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  // `_currentPage` DIHAPUS: halaman kini milik BopProvider, bukan layar ini.
  // Menyimpannya di dua tempat berarti keduanya bisa berbeda, dan yang
  // terlihat di tombol halaman belum tentu yang benar-benar diminta server.
  final int _itemsPerPage = 10;
  String _searchQuery = '';
  String _tipe = 'Semua Jenis';
  String _bulan = 'Semua Bulan';
  String _tahun = DateTime.now().year.toString();

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KategoriBopProvider>().fetchKategoriBop();
      context.read<AlokasiBopProvider>().fetchAlokasi();
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? get _periodeFilter {
    if (_bulan == 'Semua Bulan') return null;
    final idx = _namaBulan.indexOf(_bulan);
    if (idx < 0) return null;
    return '$_tahun-${(idx + 1).toString().padLeft(2, '0')}';
  }

  void _loadData({int page = 1}) {
    context.read<BopProvider>().fetchTransactions(
      tipe: _tipe == 'Semua Jenis' ? null : (_tipe == 'Pemasukan' ? 'pemasukan' : 'pengeluaran'),
      bulan: _periodeFilter,
      // Tahun selalu dikirim: pagu dan realisasi memang berbasis tahun.
      tahun: _tahun,
      search: _searchQuery.isEmpty ? null : _searchQuery,
      page: page,
      limit: _itemsPerPage,
    );
  }

  // Diteruskan ke util bersama; lihat lib/core/format.dart untuk alasan
  // kenapa format ini tidak boleh ditulis ulang per layar.
  String _rupiah(double amount) => rupiah(amount);

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses, durasi: const Duration(seconds: 5));
  }

  /// Backend tetap menyimpan transaksi walau melampaui pagu, tetapi
  /// peringatannya harus terlihat jelas — bukan sekadar snackbar sekilas.
  void _tampilkanHasil(Map<String, dynamic> hasil) {
    final sukses = hasil['success'] == true;
    final peringatan = hasil['peringatan']?.toString();

    if (sukses && peringatan != null) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Text('Melampaui Pagu'),
            ],
          ),
          content: Text(peringatan),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Mengerti'))],
        ),
      );
      return;
    }
    _pesan(hasil['message']?.toString() ?? 'Selesai.', sukses: sukses);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BopProvider>();

    // Halaman datang dari server, tidak lagi dipotong di sini. `sublist` yang
    // dulu ada di baris ini menuntut seluruh tabel diambil lebih dulu — window
    // function saldo berjalan dihitung atas setiap baris yang pernah ada, hanya
    // untuk menampilkan sepuluh.
    final halamanIni = provider.transactions;
    final totalHalaman = provider.totalPages;
    final currentPage = provider.currentPage;
    final totalData = provider.totalData;
    final mulai = (currentPage - 1) * _itemsPerPage;
    final akhir = (mulai + halamanIni.length).clamp(0, totalData);

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
        _buildTableCard(provider, totalData, halamanIni, totalHalaman, currentPage, mulai, akhir),
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
                    'Keuangan / Dana BOP',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.teksKedua,
                    ),
                  ),
                ),
              ],
            ),
          // Tombol "Transfer Kas" sengaja tidak ada, konsisten dengan Kas RT:
          // tidak ada kantong kas lain sebagai tujuan pemindahan dana.
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
                _outlinedBtn(Icons.savings_outlined, 'Alokasi Dana', _hijau, _showAlokasiDialog),
              if (_bolehUbah)
                _outlinedBtn(
                  Icons.account_balance_wallet,
                  'Master Kas',
                  _hijau,
                  _showMasterKategoriDialog,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- summary cards

  Widget _buildSummaryCards(BopProvider provider) {
    // Keempat kartu berbasis TAHUN, bukan bulan: pagu dan realisasinya memang
    // dihitung setahun, dan saldo kas selalu sepanjang masa.
    final s = provider.summary ?? const BopSummary();

    return LayoutBuilder(
      builder: (context, c) {
        final kolom = c.maxWidth > 1100 ? 4 : (c.maxWidth > 600 ? 2 : 1);
        final lebar = (c.maxWidth - (16 * (kolom - 1))) / kolom;

        final kartu = [
          _summaryCard(
            'ALOKASI $_tahun',
            _rupiah(s.alokasi),
            const [Color(0xFF0F766E), Color(0xFF14B8A6)],
            Icons.savings,
            sub: 'Pagu dana tahun ini',
          ),
          _summaryCard(
            'TERPAKAI $_tahun',
            _rupiah(s.terpakai),
            const [Color(0xFFDC2626), Color(0xFFEF4444)],
            Icons.trending_down,
            sub: 'Realisasi belanja',
          ),
          // Dua angka "sisa" yang berbeda dan dua-duanya benar: sisa pagu adalah
          // jatah belanja, saldo kas adalah uang yang benar-benar ada.
          _summaryCard(
            'SISA PAGU',
            _rupiah(s.sisaPagu),
            s.melampauiPagu
                ? const [Color(0xFFB91C1C), Color(0xFFDC2626)]
                : const [Color(0xFF7C3AED), Color(0xFFA78BFA)],
            s.melampauiPagu ? Icons.warning_amber_rounded : Icons.pie_chart_outline,
            sub: s.alokasi == 0
                ? 'Alokasi belum dicatat'
                : (s.melampauiPagu
                      ? 'Melampaui pagu'
                      : '${(s.porsiTerpakai * 100).toStringAsFixed(0)}% pagu terpakai'),
          ),
          _summaryCard(
            'SALDO KAS BOP',
            _rupiah(s.saldo),
            const [Color(0xFF1E3A5F), Color(0xFF334155)],
            Icons.account_balance_wallet,
            sub: 'Uang yang benar-benar ada',
          ),
        ];

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: kartu.map((w) => SizedBox(width: lebar, child: w)).toList(),
        );
      },
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    List<Color> colors,
    IconData icon, {
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                    fontSize: 10,
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Icon(icon, color: Colors.white.withValues(alpha: 0.35), size: 30),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- filters

  Widget _buildFilters() {
    final kategoriList = context.watch<KategoriBopProvider>().list;
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
          if (kategoriList.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kategori', style: TextStyle(fontSize: 12, color: context.teksKedua)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                  width: lebarKolomFilter(context, maksimal: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.garis),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: context.watch<BopProvider>().filterAktif['kategori_id'] == null
                          ? null
                          : int.tryParse(context.watch<BopProvider>().filterAktif['kategori_id']!),
                      isExpanded: true,
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: context.teksKedua,
                      ),
                      style: TextStyle(fontSize: 13, color: context.teksUtama),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Semua Kategori')),
                        ...kategoriList.map(
                          (k) => DropdownMenuItem<int?>(value: k.id, child: Text(k.namaKategori)),
                        ),
                      ],
                      onChanged: (v) {
                        context.read<BopProvider>().fetchTransactions(
                          tipe: _tipe == 'Semua Jenis'
                              ? null
                              : (_tipe == 'Pemasukan' ? 'pemasukan' : 'pengeluaran'),
                          bulan: _periodeFilter,
                          tahun: _tahun,
                          kategoriId: v,
                          search: _searchQuery.isEmpty ? null : _searchQuery,
                        );
                      },
                    ),
                  ),
                ),
              ],
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
          width: lebarKolomFilter(context, maksimal: 170),
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
    BopProvider provider,
    int totalData,
    List<FinanceModel> halamanIni,
    int totalHalaman,
    int currentPage,
    int mulai,
    int akhir,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                        'Riwayat Transaksi BOP',
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
                      Align(alignment: Alignment.centerLeft, child: label),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: tombol),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: Align(alignment: Alignment.centerLeft, child: label),
                    ),
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
                      'Belum ada transaksi BOP',
                      style: TextStyle(color: context.teksTersier, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Catat alokasi dulu lewat tombol "Alokasi Dana", lalu catat pencairannya.',
                      style: TextStyle(color: context.garis, fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
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
                // Wrap, bukan Row — alasannya sama persis dengan Kas RT: tujuh
                // tombol dalam satu Row tidak bisa pindah baris dan melimpah
                // 8,7px pada font sistem 1,3x. Jaraknya lewat spacing, bukan
                // SizedBox di antara anak Wrap.
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
        // Kolom ini dulu selalu menampilkan "Umum" karena bop_finances tidak
        // punya kolom kategori sama sekali. Sekarang datanya sungguhan.
        SelTabel.teks('KATEGORI', t.kategori),
        SelTabel(
          'KETERANGAN',
          SizedBox(
            width: pakaiKartu(context) ? null : 240,
            child: Text(
              t.deskripsi,
              style: TextStyle(fontSize: 12, color: context.teksUtama),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
      aksi: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_bolehUbah)
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B82F6)),
              onPressed: () => _showFormTransaksi(t.tipe, existing: t),
            ),
          if (_bolehHapus)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline, size: 18, color: _merah),
              onPressed: () => _hapusTransaksi(t),
            ),
          if (!_bolehUbah && !_bolehHapus)
            Text('—', style: TextStyle(fontSize: 13, color: context.teksTersier)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- tombol

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

  Future<void> _hapusTransaksi(FinanceModel t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Transaksi BOP'),
        content: Text('Hapus "${t.deskripsi}" sebesar ${_rupiah(t.jumlah)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: _merah),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final hasil = await context.read<BopProvider>().deleteTransaction(t.id);
    _pesan(hasil['message']?.toString() ?? 'Selesai.', sukses: hasil['success'] == true);
  }

  void _showFormTransaksi(String tipe, {FinanceModel? existing}) {
    final kategoriList = context.read<KategoriBopProvider>().untukTipe(tipe);
    if (kategoriList.isEmpty) {
      _pesan(
        'Belum ada kategori ${tipe == 'pemasukan' ? 'pemasukan' : 'belanja'} BOP yang aktif. '
        'Tambahkan lewat tombol "Master Kas".',
        sukses: false,
      );
      return;
    }

    int? kategoriId = kategoriList.any((k) => k.id == existing?.kategoriId)
        ? existing!.kategoriId
        : kategoriList.first.id;

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
                    ? (masuk ? 'Catat Pemasukan BOP' : 'Catat Belanja BOP')
                    : 'Ubah Transaksi BOP',
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
                final prov = context.read<BopProvider>();
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
                if (mounted) _tampilkanHasil(hasil);
              },
              style: ElevatedButton.styleFrom(backgroundColor: masuk ? _hijauTerang : _merah),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlokasiDialog() {
    showDialog(
      context: context,
      builder: (c) => Consumer<AlokasiBopProvider>(
        builder: (c2, prov, _) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                const Text('Alokasi Dana BOP'),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: _hijau),
                  tooltip: 'Tambah alokasi',
                  onPressed: () => _showFormAlokasi(null),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 600),
            height: 400,
            child: prov.isLoading
                ? const Center(child: CircularProgressIndicator())
                : prov.list.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada alokasi dana yang dicatat.',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: prov.list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = prov.list[i];
                      final lampau = a.sisaTahun < 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${a.termin} ${a.tahun} — ${_rupiah(a.nominal)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (a.sumberDana != null && a.sumberDana!.isNotEmpty)
                              Text('Sumber: ${a.sumberDana}', style: const TextStyle(fontSize: 11)),
                            Text(
                              'Realisasi ${a.tahun}: ${_rupiah(a.realisasiTahun)} '
                              'dari pagu ${_rupiah(a.totalPaguTahun)} '
                              '· sisa ${_rupiah(a.sisaTahun)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: lampau ? _merah : context.teksKedua,
                                fontWeight: lampau ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Ubah',
                              onPressed: () => _showFormAlokasi(a),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: a.bisaDihapus ? _merah : context.garis,
                              ),
                              // Backend juga menolak, tapi menonaktifkan tombol
                              // lebih jujur daripada memunculkan error.
                              tooltip: a.bisaDihapus
                                  ? 'Hapus'
                                  : 'Tidak bisa dihapus, tahun ini sudah ada belanja',
                              onPressed: a.bisaDihapus
                                  ? () async {
                                      final bop = context.read<BopProvider>();
                                      final r = await prov.delete(a.id);
                                      if (r['success'] == true) {
                                        await bop.fetchSummary(tahun: _tahun);
                                      }
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

  void _showFormAlokasi(AlokasiBopModel? existing) {
    final tahunCtrl = TextEditingController(
      text: (existing?.tahun ?? DateTime.now().year).toString(),
    );
    final nominalCtrl = TextEditingController(text: (existing?.nominal ?? 0).toStringAsFixed(0));
    final sumberCtrl = TextEditingController(text: existing?.sumberDana ?? '');
    final ketCtrl = TextEditingController(text: existing?.keterangan ?? '');
    String termin = existing?.termin ?? 'Tahunan';

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'Tambah Alokasi Dana' : 'Ubah Alokasi Dana'),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tahunCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tahun Anggaran *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _opsiTermin.contains(termin) ? termin : 'Tahunan',
                  decoration: const InputDecoration(labelText: 'Termin'),
                  items: _opsiTermin
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => termin = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal Pagu (Rp) *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sumberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Sumber Dana',
                    hintText: 'contoh: Kelurahan',
                  ),
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
                final tahun = int.tryParse(tahunCtrl.text);
                final nominal = double.tryParse(nominalCtrl.text);
                if (tahun == null || tahun < 2000 || tahun > 2100) {
                  _pesan('Tahun harus antara 2000 dan 2100.', sukses: false);
                  return;
                }
                if (nominal == null || nominal <= 0) {
                  _pesan('Nominal pagu harus lebih dari 0.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final prov = context.read<AlokasiBopProvider>();
                final r = existing == null
                    ? await prov.create(
                        tahun: tahun,
                        termin: termin,
                        nominal: nominal,
                        sumberDana: sumberCtrl.text.trim(),
                        keterangan: ketCtrl.text.trim(),
                      )
                    : await prov.update(
                        existing.id,
                        tahun: tahun,
                        termin: termin,
                        nominal: nominal,
                        sumberDana: sumberCtrl.text.trim(),
                        keterangan: ketCtrl.text.trim(),
                      );
                if (r['success'] == true && mounted) {
                  await context.read<BopProvider>().fetchSummary(tahun: _tahun);
                }
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

  void _showMasterKategoriDialog() {
    showDialog(
      context: context,
      builder: (c) => Consumer<KategoriBopProvider>(
        builder: (c2, prov, _) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                const Text('Kelola Kategori BOP'),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: _hijau),
                  tooltip: 'Tambah kategori',
                  onPressed: () => _showFormKategori(null),
                ),
              ],
            ),
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
    String tipe = existing?.tipe ?? 'OUT';
    final tipeTerkunci = existing != null && existing.jumlahTransaksi > 0;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'Tambah Kategori BOP' : 'Ubah Kategori BOP'),
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
                        ? 'Terkunci: sudah dipakai ${existing.jumlahTransaksi} transaksi'
                        : null,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('Pemasukan')),
                    DropdownMenuItem(value: 'OUT', child: Text('Belanja')),
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
                final prov = context.read<KategoriBopProvider>();
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
