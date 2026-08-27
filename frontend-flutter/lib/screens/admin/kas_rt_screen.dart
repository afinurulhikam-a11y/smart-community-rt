import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../providers/aksi_utama_provider.dart';
import '../../providers/finance_provider.dart';
import '../../providers/kategori_kas_provider.dart';
import '../../models/finance_model.dart';
import '../../models/kategori_kas_model.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/banner_lihat_saja.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/format.dart';
import '../../core/pesan.dart';
import '../../core/izin_layar.dart';
import 'data_warga_screen.dart';

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
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  String _searchQuery = '';
  String _tipe = 'Semua Jenis';
  String _bulan = 'Semua Bulan';
  String _tahun = 'Semua Tahun';

  final TextEditingController _searchController = TextEditingController();
  final List<String> _tahunList = [
    'Semua Tahun',
    '2026',
    '2027',
    '2028',
    '2029',
    '2030',
  ];

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
    final thn = (_tahun == 'Semua Tahun' || _tahun == 'Semua') ? DateTime.now().year.toString() : _tahun;
    return '$thn-${(idx + 1).toString().padLeft(2, '0')}';
  }

  void _loadData({int page = 1}) {
    final thnParam = (_tahun == 'Semua Tahun' || _tahun == 'Semua') ? null : _tahun;
    context.read<FinanceProvider>().fetchTransactions(
      tipe: _tipe == 'Semua Jenis' || _tipe == 'Non Iuran'
          ? null
          : (_tipe == 'Pemasukan' ? 'pemasukan' : 'pengeluaran'),
      sumber: _tipe == 'Non Iuran' ? 'non_iuran' : null,
      bulan: _periodeFilter,
      tahun: _periodeFilter == null ? thnParam : null,
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
    final mulai = (currentPage - 1) * provider.perPage;

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
        _buildActionButtons(),
        const SizedBox(height: 24),
        _buildTableCard(provider, halamanIni, totalHalaman, mulai),
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
        ],
      ),
    );
  }

  // --------------------------------------------------------- summary cards

  Widget _buildSummaryCards(FinanceProvider provider) {
    final s = provider.summary;
    final labelPeriode = _periodeFilter == null ? 'Bulan Ini' : 'Periode Dipilih';

    final kartu = [
      _statCard(
        'Pemasukan $labelPeriode',
        _rupiah(s?.pemasukanBulan ?? 0),
        'Total pemasukan kas',
        Icons.trending_up,
        const Color(0xFF10B981),
      ),
      _statCard(
        'Pengeluaran $labelPeriode',
        _rupiah(s?.pengeluaranBulan ?? 0),
        'Total pengeluaran kas',
        Icons.trending_down,
        const Color(0xFFEF4444),
      ),
      _statCard(
        'Saldo Kas Saat Ini',
        _rupiah(s?.saldoTotal ?? 0),
        'Saldo kumulatif kas RT',
        Icons.account_balance_wallet,
        const Color(0xFF3B82F6),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final kolom = c.maxWidth > 900 ? 3 : (c.maxWidth > 500 ? 2 : 1);
        final lebar = (c.maxWidth - (16 * (kolom - 1))) / kolom;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: kartu.map((w) => SizedBox(width: lebar, child: w)).toList(),
        );
      },
    );
  }

  Widget _statCard(String label, String nilai, String sub, IconData ikon, Color warna) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: warna.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(ikon, color: warna, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.teksKedua,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nilai,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(fontSize: 11, color: context.teksTersier),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- action buttons

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
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
            Icons.category_outlined,
            'Master Kas',
            _hijau,
            _showMasterKasDialog,
          ),
        _filledBtn(
          Icons.table_chart_outlined,
          'Laporan Excel',
          const Color(0xFF10B981),
          () => context.read<FinanceProvider>().downloadExport(format: 'excel'),
        ),
        _filledBtn(
          Icons.picture_as_pdf_outlined,
          'Laporan PDF',
          _merah,
          () => context.read<FinanceProvider>().downloadExport(format: 'pdf'),
        ),
      ],
    );
  }

  Widget _dropdownFilter<T>(
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged, {
    double? lebar,
  }) {
    return SizedBox(
      width: lebar ?? lebarKolomFilter(context, maksimal: 160),
      height: AppTheme.sasaranSentuh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: context.garis),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down, size: 16, color: context.teksKedua),
            style: TextStyle(fontSize: 13, color: context.teksUtama),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- table

  Widget _buildTableCard(
    FinanceProvider provider,
    List<FinanceModel> halamanIni,
    int totalHalaman,
    int mulai,
  ) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          // Header: Ikon + Judul Riwayat Transaksi Kas (Center)
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Icon(
                  Icons.history_rounded,
                  color: Color(0xFF10B981),
                ),
                Text(
                  'Riwayat Transaksi Kas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Baris 1: Pencarian & Reset (Center)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Pencarian',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.teksKedua,
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: context.teksUtama, fontSize: 13),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) {
                    _searchQuery = v.trim();
                    _loadData();
                  },
                  decoration: InputDecoration(
                    hintText: 'Cari keterangan / kategori...',
                    hintStyle: TextStyle(fontSize: 12, color: context.teksTersier),
                    prefixIcon: Icon(Icons.search, size: 18, color: context.teksKedua),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      tooltip: 'Cari',
                      onPressed: () {
                        _searchQuery = _searchController.text.trim();
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
                      borderSide: const BorderSide(color: Color(0xFF1B7A6A)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _tipe = 'Semua Jenis';
                    _bulan = 'Semua Bulan';
                    _tahun = 'Semua Tahun';
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
                  visualDensity: VisualDensity.standard,
                  minimumSize: const Size(0, AppTheme.sasaranSentuh),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Baris 2: Dropdown Filter Jenis, Bulan, Tahun (Center)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _dropdownFilter<String>(
                _tipe,
                const ['Semua Jenis', 'Pemasukan', 'Pengeluaran', 'Non Iuran']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                (v) {
                  if (v != null) {
                    setState(() => _tipe = v);
                    _loadData();
                  }
                },
                lebar: lebarKolomFilter(context, maksimal: 160),
              ),
              _dropdownFilter<String>(
                _bulan,
                ['Semua Bulan', ..._namaBulan]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                (v) {
                  if (v != null) {
                    setState(() => _bulan = v);
                    _loadData();
                  }
                },
                lebar: lebarKolomFilter(context, maksimal: 160),
              ),
              _dropdownFilter<String>(
                _tahun,
                _tahunList
                    .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                (v) {
                  if (v != null) {
                    setState(() => _tahun = v);
                    _loadData();
                  }
                },
                lebar: lebarKolomFilter(context, maksimal: 160),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tabel di dalam container bergaris
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.latarKartu,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.garis),
            ),
            child: provider.isLoading && halamanIni.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : (halamanIni.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 40, color: context.garis),
                              const SizedBox(height: 12),
                              Text(
                                'Belum Ada Transaksi',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: context.teksUtama,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Transaksi kas RT akan muncul di sini.',
                                style: TextStyle(fontSize: 13, color: context.teksKedua),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
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
                            (i) => _buildRow(
                              halamanIni[i],
                              ((provider.currentPage - 1) * provider.perPage) + i + 1,
                            ),
                          ),
                          currentPage: provider.currentPage,
                          totalPages: provider.totalPages,
                          totalData: provider.totalData,
                          perPage: provider.perPage,
                          onPageChanged: (page) => _loadData(page: page),
                        ),
                      )),
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
      aksi: Transform.translate(
        offset: const Offset(geserAksiTabel, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_bolehUbah)
              IconButton(
                tooltip: t.bolehDiubah
                    ? 'Ubah'
                    : 'Transaksi dari pembayaran iuran tidak bisa diubah di sini',
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: t.bolehDiubah ? const Color(0xFF3B82F6) : context.garis,
                ),
                style: gayaAksiTabel(t.bolehDiubah ? const Color(0xFF3B82F6) : context.garis),
                onPressed: t.bolehDiubah ? () => _showFormTransaksi(t.tipe, existing: t) : null,
              ),
            if (_bolehHapus)
              IconButton(
                tooltip: t.bolehDiubah
                    ? 'Hapus'
                    : 'Transaksi dari pembayaran iuran tidak bisa dihapus di sini',
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: t.bolehDiubah ? const Color(0xFFEF4444) : context.garis,
                ),
                style: gayaAksiTabel(t.bolehDiubah ? const Color(0xFFEF4444) : context.garis),
                onPressed: t.bolehDiubah ? () => _hapusTransaksi(t) : null,
              ),
            if (!_bolehUbah && !_bolehHapus)
              Text('—', style: TextStyle(fontSize: 13, color: context.teksTersier)),
          ],
        ),
      ),
    );
  }

  Future<void> _hapusTransaksi(FinanceModel t) async {
    final ok = await konfirmasiHapus(
      context,
      judul: 'Hapus Transaksi',
      pesan:
          'Hapus ${t.isPemasukan ? 'pemasukan' : 'pengeluaran'} sebesar '
          '${_rupiah(t.jumlah)} (${t.deskripsi})?',
    );
    if (!ok || !mounted) return;
    final hasil = await context.read<FinanceProvider>().deleteTransaction(t.id);
    if (!mounted) return;
    _pesan(hasil['message']?.toString() ?? 'Selesai.', sukses: hasil['success'] == true);
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
    final warnaUtama = masuk ? _hijauTerang : _merah;

    // Dekorasi input yang sama untuk seluruh field, agar form ini terlihat
    // satu kesatuan dan sejajar — bukan campuran gaya bawaan Material.
    InputDecoration dekor(String label, IconData ikon) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 14, color: context.teksKedua),
      prefixIcon: Icon(ikon, color: warnaUtama, size: 20),
      filled: true,
      fillColor: context.latarLembut,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.garis),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.garis),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: warnaUtama, width: 1.5),
      ),
    );

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: warnaUtama.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  masuk ? Icons.arrow_downward : Icons.arrow_upward,
                  color: warnaUtama,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  existing == null
                      ? (masuk ? 'Catat Pemasukan' : 'Catat Pengeluaran')
                      : 'Ubah Transaksi',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: context.teksUtama,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: tanggalCtrl,
                    readOnly: true,
                    decoration: dekor('Tanggal', Icons.calendar_today),
                    onTap: () async {
                      final dipilih = await showDatePicker(
                        context: c,
                        initialDate: existing?.tanggal ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        helpText: 'Pilih Tanggal',
                      );
                      if (dipilih != null) {
                        tanggalCtrl.text = DateFormat('yyyy-MM-dd').format(dipilih);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: kategoriId,
                    isExpanded: true,
                    decoration: dekor('Kategori', Icons.category_outlined),
                    dropdownColor: context.latarKartu,
                    borderRadius: BorderRadius.circular(12),
                    items: kategoriList
                        .map((k) => DropdownMenuItem(value: k.id, child: Text(k.namaKategori)))
                        .toList(),
                    onChanged: (v) => setLocal(() => kategoriId = v),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: jumlahCtrl,
                    keyboardType: TextInputType.number,
                    decoration: dekor('Jumlah (Rp)', Icons.attach_money),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: deskripsiCtrl,
                    maxLines: 2,
                    decoration: dekor('Keterangan', Icons.notes),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                foregroundColor: context.warnaTombolTutup,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: warnaUtama,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              style: TextButton.styleFrom(
                foregroundColor: c2.warnaTombolTutup,
              ),
              child: const Text('Tutup'),
            ),
          ],
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
            TextButton(
              onPressed: () => Navigator.pop(c),
              style: TextButton.styleFrom(
                foregroundColor: c2.warnaTombolTutup,
              ),
              child: const Text('Batal'),
            ),
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
