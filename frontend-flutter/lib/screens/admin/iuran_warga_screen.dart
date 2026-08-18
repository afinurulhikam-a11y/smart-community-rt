import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../providers/bill_provider.dart';
import '../../providers/jenis_iuran_provider.dart';
import '../../providers/family_provider.dart';
import '../../models/bill_model.dart';
import '../../models/jenis_iuran_model.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/banner_lihat_saja.dart';
import '../../widgets/dialog_bacaan_meteran.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/format.dart';
import '../../core/pesan.dart';
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

class IuranWargaScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const IuranWargaScreen({super.key, this.onBack});

  @override
  State<IuranWargaScreen> createState() => _IuranWargaScreenState();
}

/// Kode modul di tabel izin. Sekretaris hanya punya `view` di sini.
const String _kodeIzin = 'keuangan.iuran';

class _IuranWargaScreenState extends State<IuranWargaScreen> {
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  String _searchQuery = '';
  String _status = 'Semua Status';
  int? _jenisIuranId;
  String _bulan = 'Semua Bulan';
  String _tahun = DateTime.now().year.toString();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JenisIuranProvider>().fetchJenisIuran();
      context.read<FamilyProvider>().fetchFamilies(limit: 1000);
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
    context.read<BillProvider>().fetchBills(
      status: _status == 'Semua Status' ? null : (_status == 'Lunas' ? 'lunas' : 'unpaid'),
      bulan: _periodeFilter,
      tahun: _periodeFilter == null ? _tahun : null,
      jenisIuranId: _jenisIuranId,
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
    final provider = context.watch<BillProvider>();
    final semua = provider.bills;

    final totalHalaman = provider.totalPages;
    final halamanIni = semua;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BannerLihatSaja(kode: _kodeIzin),
        _buildHeader(),
        const SizedBox(height: 24),
        _buildStatCards(provider),
        const SizedBox(height: 24),
        _buildActionButtons(),
        const SizedBox(height: 24),
        _buildFilters(),
        const SizedBox(height: 24),
        _buildTableCard(provider, semua, halamanIni, totalHalaman),
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
                  child: Icon(Icons.monetization_on_outlined, color: _hijau, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Keuangan / Iuran Warga',
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

  // ------------------------------------------------------------ stat cards

  Widget _buildStatCards(BillProvider provider) {
    final s = provider.stats;
    final kartu = [
      _statCard(
        'Total Tagihan',
        s.totalTagihan.toString(),
        '${s.jumlahKk} kartu keluarga',
        Icons.receipt_long,
        const Color(0xFF0F766E),
      ),
      _statCard(
        'Sudah Bayar',
        s.jumlahLunas.toString(),
        _rupiah(s.nominalTerkumpul),
        Icons.check_circle,
        const Color(0xFF10B981),
      ),
      _statCard(
        'Tunggakan',
        s.jumlahTunggakan.toString(),
        _rupiah(s.nominalTertunggak),
        Icons.warning_amber_rounded,
        const Color(0xFFEF4444),
      ),
      _statCard(
        'Ketercapaian',
        '${s.persentaseLunas.toStringAsFixed(1)}%',
        'dari ${_rupiah(s.nominalTotal)}',
        Icons.trending_up,
        const Color(0xFF3B82F6),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final kolom = c.maxWidth > 900 ? 4 : (c.maxWidth > 500 ? 2 : 1);
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
                    fontSize: 22,
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
        _filledBtn(
          Icons.water_drop_outlined,
          'Bacaan Meteran',
          const Color(0xFF0EA5E9),
          () async {
            await showDialog(
              context: context,
              builder: (_) => const DialogBacaanMeteran(),
            );
            if (mounted) _loadData();
          },
        ),
        if (_bolehUbah)
          _outlinedBtn(
            Icons.category_outlined,
            'Master Iuran',
            _hijau,
            _showJenisIuranDialog,
          ),
        if (_bolehUbah)
          _outlinedBtn(
            Icons.bolt_outlined,
            'Terbitkan Tagihan',
            const Color(0xFF8B5CF6),
            () => _showGenerateTagihanDialog(),
          ),
        if (_bolehUbah)
          _outlinedBtn(
            Icons.chat_outlined,
            'Tagih Semua (WA)',
            const Color(0xFF22C55E),
            _showTagihWaDialog,
          ),
        _filledBtn(
          Icons.table_chart_outlined,
          'Laporan Excel',
          const Color(0xFF10B981),
          () => context.read<BillProvider>().downloadExport(format: 'excel'),
        ),
        _filledBtn(
          Icons.picture_as_pdf_outlined,
          'Laporan PDF',
          const Color(0xFFEF4444),
          () => context.read<BillProvider>().downloadExport(format: 'pdf'),
        ),
      ],
    );
  }

  Widget _outlinedBtn(IconData icon, String label, Color color, VoidCallback? onTap) {
    final mati = onTap == null;
    final c = mati ? context.teksTersier : color;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(
        label,
        style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

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

  // --------------------------------------------------------------- filters

  Widget _buildFilters() {
    final jenisList = context.watch<JenisIuranProvider>().aktif;
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
          _dropdownFilter<String>(
            'Status',
            _status,
            const [
              'Semua Status',
              'Lunas',
              'Belum Bayar',
            ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            (v) {
              setState(() => _status = v!);
              _loadData();
            },
          ),
          _dropdownFilter<int?>(
            'Master Iuran',
            _jenisIuranId,
            [
              const DropdownMenuItem<int?>(value: null, child: Text('Semua Jenis')),
              ...jenisList.map(
                (j) => DropdownMenuItem<int?>(value: j.id, child: Text(j.namaIuran)),
              ),
            ],
            (v) {
              setState(() => _jenisIuranId = v);
              _loadData();
            },
          ),
          _dropdownFilter<String>(
            'Bulan',
            _bulan,
            [
              'Semua Bulan',
              ..._namaBulan,
            ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            (v) {
              setState(() => _bulan = v!);
              _loadData();
            },
          ),
          _dropdownFilter<String>(
            'Tahun',
            _tahun,
            List.generate(
              5,
              (i) => (DateTime.now().year - 2 + i).toString(),
            ).map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
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
                _status = 'Semua Status';
                _jenisIuranId = null;
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
              visualDensity: VisualDensity.standard,
              minimumSize: const Size(0, AppTheme.sasaranSentuh),
              maximumSize: const Size(double.infinity, AppTheme.sasaranSentuh),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownFilter<T>(
    String label,
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.teksKedua)),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(
            minHeight: AppTheme.sasaranSentuh,
            maxHeight: AppTheme.sasaranSentuh,
          ),
          width: lebarKolomFilter(context),
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
      ],
    );
  }

  // ----------------------------------------------------------------- table

  Widget _buildTableCard(
    BillProvider provider,
    List<BillModel> semua,
    List<BillModel> halamanIni,
    int totalHalaman,
  ) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_alt, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Semua Data Iuran',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: context.teksUtama,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${provider.totalData} data',
                  style: TextStyle(fontSize: 12, color: context.teksKedua),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
                    hintText: 'Cari nama, no KK, alamat...',
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
                      borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
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
          const SizedBox(height: 16),

          // Tabel di dalam container bergaris (seragam dengan Data Warga & Data KK)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.latarKartu,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.garis),
            ),
            child: Column(
              children: [
                Container(
                  constraints: pakaiKartu(context)
                      ? const BoxConstraints()
                      : const BoxConstraints(minHeight: 560),
                  child: provider.isLoading && semua.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (semua.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 40, color: context.garis),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Belum ada data iuran',
                                      style: TextStyle(color: context.teksTersier, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Gunakan tombol "Terbitkan Tagihan" untuk membuat tagihan satu periode.',
                                      style: TextStyle(color: context.garis, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Builder(builder: (context) {
                              final adaMeteran = halamanIni.any((b) => b.pakaiMeteran);
                              return Padding(
                                padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                                child: TabelResponsif(
                                  tinggiBarisMaks: 70,
                                  kolom: [
                                    'NO',
                                    'KEPALA KELUARGA',
                                    'MASTER IURAN',
                                    'PERIODE',
                                    if (adaMeteran) ...['METERAN LALU', 'METERAN KINI', 'TERPAKAI'],
                                    'NOMINAL',
                                    'STATUS',
                                    'TGL BAYAR',
                                  ],
                                  baris: List.generate(halamanIni.length, (i) {
                                    final b = halamanIni[i];
                                    return _buildRow(
                                      b,
                                      ((provider.currentPage - 1) * provider.perPage) + i + 1,
                                      adaMeteran,
                                    );
                                  }),
                                  currentPage: provider.currentPage,
                                  totalPages: provider.totalPages,
                                  totalData: provider.totalData,
                                  perPage: provider.perPage,
                                  onPageChanged: (page) => _loadData(page: page),
                                ),
                              );
                            })),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BarisTabel _buildRow(BillModel b, int nomor, bool adaMeteran) {
    final terlambat = b.isTerlambat;
    return BarisTabel(
      sel: [
        SelTabel.teks('NO', '$nomor', sembunyiDiKartu: true),
        SelTabel(
          'KEPALA KELUARGA',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    b.kepalaKeluarga,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  // Nama sementara: KK ini belum punya anggota berstatus
                  // Kepala Keluarga, jadi yang tampil adalah anggota pertamanya.
                  if (!b.kepalaTerkonfirmasi)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message:
                            'KK ini belum punya anggota berstatus Kepala Keluarga.\n'
                            'Nama yang tampil diambil dari anggota pertama.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'sementara',
                            style: TextStyle(fontSize: 9, color: Color(0xFFD97706)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Text('KK: ${b.noKk}', style: TextStyle(fontSize: 11, color: context.teksTersier)),
            ],
          ),
          utama: true,
        ),
        SelTabel.teks('MASTER IURAN', b.namaIuran),
        SelTabel.teks('PERIODE', b.bulan),
        if (adaMeteran) ...[
          SelTabel.teks('METERAN LALU', b.meteranLalu?.toString() ?? '—'),
          // Belum dibaca ditandai jelas, bukan dibiarkan kosong: tagihan yang
          // meterannya belum dicatat masih akan bertambah nilainya, dan itu
          // beda maknanya dengan angka nol.
          SelTabel(
            'METERAN KINI',
            b.sudahDibaca
                ? Text(
                    '${b.meteranSekarang}',
                    style: const TextStyle(fontSize: 13),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'BELUM DIBACA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),
          ),
          SelTabel.teks(
            'TERPAKAI',
            b.sudahDibaca ? '${b.terpakai} m³' : '—',
            gaya: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
        SelTabel.teks(
          'NOMINAL',
          _rupiah(b.nominal),
          gaya: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SelTabel(
          'STATUS',
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: b.isLunas
                  ? const Color(0xFFD1FAE5)
                  : (terlambat ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              b.isLunas ? 'LUNAS' : (terlambat ? 'TERLAMBAT' : 'BELUM BAYAR'),
              style: TextStyle(
                color: b.isLunas
                    ? const Color(0xFF10B981)
                    : (terlambat ? const Color(0xFFEF4444) : const Color(0xFFD97706)),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SelTabel.teks(
          'TGL BAYAR',
          b.paidAt == null ? '-' : DateFormat('dd MMM yyyy').format(b.paidAt!),
          gaya: TextStyle(
            fontSize: 12,
            color: b.paidAt == null ? context.teksTersier : context.teksUtama,
          ),
        ),
      ],
      aksi: Transform.translate(
        offset: const Offset(geserAksiTabel, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Urutan konsisten: Approve → Edit → Delete. Setiap tombol memakai
            // gayaAksiTabel dengan ukuran hover 30×30 dan sasaran sentuh 48dp,
            // dipusatkan simetris dan ditarik geserAksiTabel (-9px) agar rata
            // kiri tepat di bawah label "AKSI".

            // APPROVE / BAYAR
            if (!b.isLunas && _bolehUbah)
              IconButton(
                tooltip: 'Bayar',
                icon: const Icon(Icons.payments_outlined, size: 20, color: Color(0xFF059669)),
                style: gayaAksiTabel(const Color(0xFF059669)),
                onPressed: () => _bayarSatu(b),
              )
            else if (b.isLunas)
              IconButton(
                tooltip: 'Sudah lunas',
                onPressed: null,
                icon: const Icon(Icons.check_circle, size: 20),
                style: IconButton.styleFrom(
                  alignment: Alignment.center,
                  minimumSize: const Size(ukuranHoverAksi, ukuranHoverAksi),
                  maximumSize: const Size(ukuranHoverAksi, ukuranHoverAksi),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  disabledForegroundColor: const Color(0xFF10B981),
                ),
              ),

            // EDIT
            if (_bolehUbah)
              IconButton(
                tooltip: b.isLunas
                    ? 'Tagihan lunas tidak bisa diubah'
                    : 'Edit Tagihan',
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: b.isLunas ? context.garis : const Color(0xFF3B82F6),
                ),
                onPressed: b.isLunas ? null : () => _editTagihan(b),
                style: gayaAksiTabel(b.isLunas ? context.garis : const Color(0xFF3B82F6)),
              ),

            // DELETE
            if (_bolehHapus)
              IconButton(
                tooltip: 'Hapus Tagihan',
                icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFEF4444)),
                style: gayaAksiTabel(const Color(0xFFEF4444)),
                onPressed: () => _hapusTagihan(b),
              ),

            // Kolom aksi kosong — tidak ada izin sama sekali — tetap tampilkan
            // placeholder agar barisnya tidak terlihat "hilang" dibanding baris
            // lain yang punya tombol.
            if (!_bolehUbah && !_bolehHapus)
              Text('—', style: TextStyle(fontSize: 13, color: context.teksTersier)),
          ],
        ),
      ),
    );
  }



  // --------------------------------------------------------------- actions

  Future<void> _bayarSatu(BillModel b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi Pembayaran'),
        content: Text(
          'Tandai tagihan ${b.namaIuran} periode ${b.bulan} atas nama ${b.kepalaKeluarga} '
          'sebesar ${_rupiah(b.nominal)} sebagai LUNAS?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            style: TextButton.styleFrom(
              foregroundColor: c.gelap ? Colors.white : Colors.black,
            ),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            child: const Text('Bayar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final berhasil = await context.read<BillProvider>().payBill(b.id);
    _pesan(
      berhasil ? 'Pembayaran berhasil dicatat.' : 'Gagal mencatat pembayaran.',
      sukses: berhasil,
    );
  }


  Future<void> _hapusTagihan(BillModel b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Tagihan'),
        content: Text(
          'Hapus tagihan ${b.namaIuran} periode ${b.bulan} '
          'atas nama ${b.kepalaKeluarga}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            style: TextButton.styleFrom(
              foregroundColor: c.gelap ? Colors.white : Colors.black,
            ),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final hasil = await context.read<BillProvider>().deleteBill(b.id);
    _pesan(hasil['message']?.toString() ?? 'Selesai.', sukses: hasil['success'] == true);
  }

  /// Ubah tagihan yang belum lunas.
  ///
  /// Untuk tagihan bermeteran, yang diisi petugas adalah ANGKA BACAAN, bukan
  /// nominalnya — totalnya dihitung backend dari selisih meteran. Kolom nominal
  /// karena itu disembunyikan; membiarkannya berarti menawarkan dua sumber
  /// kebenaran untuk satu angka, dan yang diketik tangan akan diabaikan diam-diam.
  void _editTagihan(BillModel b) {
    final nominalCtrl = TextEditingController(text: b.nominal.toStringAsFixed(0));
    final meteranLaluCtrl = TextEditingController(text: b.meteranLalu?.toString() ?? '');
    final meteranKiniCtrl = TextEditingController(text: b.meteranSekarang?.toString() ?? '');
    final alasanCtrl = TextEditingController();
    final keteranganCtrl = TextEditingController(text: b.keterangan ?? '');
    final jatuhTempoCtrl = TextEditingController(
      text: b.jatuhTempo == null ? '' : DateFormat('yyyy-MM-dd').format(b.jatuhTempo!),
    );
    DateTime? jatuhTempo;

    InputDecoration dekor(String label, IconData ikon) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 14, color: context.teksKedua),
      prefixIcon: Icon(ikon, color: const Color(0xFF1B7A6A), size: 20),
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
        borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
      ),
    );

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                b.pakaiMeteran ? Icons.water_drop_outlined : Icons.edit_outlined,
                color: const Color(0xFF1B7A6A),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                b.pakaiMeteran ? 'Catat Meteran Air' : 'Edit Tagihan',
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
          width: lebarDialog(context, maksimal: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.latarLembut,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.garis),
                  ),
                  child: Text(
                    '${b.namaIuran} — ${b.bulan}\n${b.kepalaKeluarga}',
                    style: TextStyle(fontSize: 13, color: context.teksKedua, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                if (b.pakaiMeteran) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: meteranLaluCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: dekor('Meteran Lalu', Icons.speed_outlined),
                          onChanged: (_) => setDialog(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: meteranKiniCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: dekor('Meteran Kini', Icons.speed),
                          onChanged: (_) => setDialog(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _pratinjauAir(b, meteranLaluCtrl.text, meteranKiniCtrl.text),
                  const SizedBox(height: 14),
                  TextField(
                    controller: alasanCtrl,
                    decoration: dekor('Alasan Koreksi (wajib jika mengubah meteran)', Icons.note_alt_outlined),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  TextField(
                    controller: nominalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: dekor('Nominal (Rp)', Icons.attach_money),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: keteranganCtrl,
                  maxLines: 2,
                  decoration: dekor('Keterangan', Icons.notes),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: jatuhTempoCtrl,
                  readOnly: true,
                  decoration: dekor('Jatuh Tempo (opsional)', Icons.event),
                  onTap: () async {
                    final dipilih = await showDatePicker(
                      context: c,
                      initialDate: b.jatuhTempo ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      helpText: 'Pilih Jatuh Tempo',
                    );
                    if (dipilih != null) {
                      jatuhTempo = dipilih;
                      jatuhTempoCtrl.text =
                          '${dipilih.year.toString().padLeft(4, '0')}-${dipilih.month.toString().padLeft(2, '0')}-${dipilih.day.toString().padLeft(2, '0')}';
                    }
                  },
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
              foregroundColor: c.gelap ? Colors.white : Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              int? mLalu;
              int? mKini;

              if (b.pakaiMeteran) {
                mLalu = int.tryParse(meteranLaluCtrl.text.trim());
                mKini = int.tryParse(meteranKiniCtrl.text.trim());
                if (mLalu == null) {
                  _pesan('Meteran bulan lalu wajib diisi.', sukses: false);
                  return;
                }
                if (mKini != null && mKini < mLalu) {
                  _pesan(
                    'Meteran kini tidak boleh lebih kecil daripada meteran bulan lalu.',
                    sukses: false,
                  );
                  return;
                }
                final meteranBerubah =
                    mLalu != b.meteranLalu || mKini != b.meteranSekarang;
                if (meteranBerubah && alasanCtrl.text.trim().isEmpty) {
                  _pesan('Alasan koreksi wajib diisi saat mengubah meteran.', sukses: false);
                  return;
                }
              } else {
                final nominal = double.tryParse(nominalCtrl.text);
                if (nominal == null || nominal <= 0) {
                  _pesan('Nominal harus berupa angka lebih dari 0.', sukses: false);
                  return;
                }
              }

              Navigator.pop(c);
              final hasil = await context.read<BillProvider>().updateBill(
                b.id,
                // Nominal tidak dikirim untuk tagihan bermeteran: backend
                // menghitungnya sendiri dan mengabaikan yang dikirim klien.
                nominal: b.pakaiMeteran ? null : double.tryParse(nominalCtrl.text),
                meteranLalu: mLalu,
                meteranSekarang: mKini,
                keterangan: keteranganCtrl.text.trim(),
                alasan: alasanCtrl.text.trim(),
                jatuhTempo: jatuhTempo == null
                    ? null
                    : DateFormat('yyyy-MM-dd').format(jatuhTempo!),
              );
              _pesan(
                hasil['message']?.toString() ?? 'Selesai.',
                sukses: hasil['success'] == true,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B7A6A),
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

  /// Pratinjau rincian tagihan air, dihitung ulang saat angka meteran diketik.
  ///
  /// Rumusnya sama dengan yang dipakai backend. Menampilkannya di sini bukan
  /// sekadar kenyamanan: petugas mengetik angka meteran di lapangan, dan
  /// melihat totalnya langsung adalah satu-satunya cara ia menyadari salah
  /// ketik — angka 2340 alih-alih 234 menghasilkan tagihan jutaan yang tidak
  /// akan pernah terlihat janggal di dalam sebuah kolom isian.
  Widget _pratinjauAir(BillModel b, String teksLalu, String teksKini) {
    final lalu = int.tryParse(teksLalu.trim());
    final kini = int.tryParse(teksKini.trim());
    final tarif = b.tarifPerM3 ?? 0;
    final abon = b.abondement ?? 0;
    final sampah = b.biayaSampah ?? 0;

    final belumLengkap = lalu == null || kini == null;
    final mundur = !belumLengkap && kini < lalu;
    final terpakai = belumLengkap || mundur ? 0 : kini - lalu;
    final biayaAir = terpakai * tarif;
    final total = biayaAir + abon + sampah;

    Widget baris(String kiri, String kanan, {bool tebal = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              kiri,
              style: TextStyle(
                fontSize: 12,
                color: tebal ? context.teksUtama : context.teksKedua,
                fontWeight: tebal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            kanan,
            style: TextStyle(
              fontSize: tebal ? 14 : 12,
              color: tebal ? const Color(0xFF1B7A6A) : context.teksUtama,
              fontWeight: tebal ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mundur ? const Color(0xFFFEE2E2) : context.latarLembut,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mundur ? const Color(0xFFEF4444) : context.garis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mundur)
            const Text(
              'Meteran kini lebih kecil daripada bulan lalu',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFB91C1C),
              ),
            )
          else if (belumLengkap)
            Text(
              'Isi kedua angka meteran untuk melihat totalnya',
              style: TextStyle(fontSize: 12, color: context.teksTersier),
            ),
          if (!mundur) ...[
            if (!belumLengkap) ...[
              baris('Pemakaian', '$terpakai m³'),
              baris('Air  ($terpakai × ${_rupiah(tarif.toDouble())})', _rupiah(biayaAir.toDouble())),
            ],
            baris('Abondement', _rupiah(abon.toDouble())),
            baris('Sampah', _rupiah(sampah.toDouble())),
            Divider(height: 14, color: context.garis),
            baris('TOTAL', _rupiah(total.toDouble()), tebal: true),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- dialogs

  void _showTagihWaDialog() {
    final belum = context.read<BillProvider>().bills.where((b) => !b.isLunas).toList();

    // Digabung per KK agar satu keluarga menerima satu pesan berisi semua
    // tunggakannya, bukan satu pesan per tagihan.
    final perKk = <String, List<BillModel>>{};
    for (final b in belum) {
      perKk.putIfAbsent(b.noKk, () => []).add(b);
    }

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tagih via WhatsApp'),
        content: SizedBox(
          width: lebarDialog(context, maksimal: 520),
          height: 480,
          child: perKk.isEmpty
              ? const Center(child: Text('Tidak ada tunggakan pada filter ini.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kirim SEMUA lewat gateway backend (Fonnte) dalam satu
                    // klik. Tombol ini yang dipakai untuk pengiriman massal —
                    // daftar di bawah tetap ada untuk mengirim per keluarga.
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final r = await context.read<BillProvider>().tagihSemuaWA();
                          if (!c.mounted) return;
                          Navigator.pop(c);
                          _pesan(
                            r['message']?.toString() ?? 'Selesai.',
                            sukses: r['success'] == true,
                          );
                        },
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          'Kirim Semua ke ${perKk.length} Keluarga',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${perKk.length} keluarga memiliki tunggakan. '
                      'Tombol di atas mengirim lewat gateway (Fonnte); '
                      'browser memblokir pembukaan banyak tab, jadi kirim per keluarga '
                      'hanya untuk kasus tertentu.',
                      style: TextStyle(fontSize: 11, color: context.teksKedua),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: perKk.entries.map((e) {
                          final list = e.value;
                          final total = list.fold<double>(0, (s, b) => s + b.nominal);
                          final adaHp = list.first.noHp?.isNotEmpty ?? false;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              list.first.kepalaKeluarga,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${list.length} tagihan · ${_rupiah(total)}'
                              '${adaHp ? '' : ' · nomor HP belum diisi'}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.chat,
                                color: adaHp ? const Color(0xFF22C55E) : context.garis,
                              ),
                              // Per keluarga juga lewat gateway backend — satu
                              // klik, tanpa membuka wa.me.
                              onPressed: adaHp
                                  ? () async {
                                      final hasil = await context
                                          .read<BillProvider>()
                                          .tagihSemuaWA(billIds: list.map((b) => b.id).toList());
                                      if (!c.mounted) return;
                                      _pesan(
                                        hasil['message']?.toString() ?? 'Selesai.',
                                        sukses: hasil['success'] == true,
                                      );
                                    }
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            style: TextButton.styleFrom(
              foregroundColor: c.gelap ? Colors.white : Colors.black,
            ),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showJenisIuranDialog() {
    showDialog(
      context: context,
      builder: (c) => Consumer<JenisIuranProvider>(
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
                const Text('Kelola Master Iuran'),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: _hijau),
                  tooltip: 'Tambah Master Iuran',
                  onPressed: () => _showFormJenis(null),
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
                ? const Center(child: Text('Belum ada Master Iuran.'))
                : ListView.separated(
                    itemCount: prov.list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final j = prov.list[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                j.namaIuran,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (!j.isAktif) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Non-aktif',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          j.tipeHitung == 'meteran'
                              ? 'Nominal: Rp ${_rupiah(j.nominalDefault)} · Abondement: Rp ${_rupiah(j.abondement)} · Sampah: Rp ${_rupiah(j.biayaSampah)}'
                              : 'Nominal: Rp ${_rupiah(j.nominalDefault)} · ${j.periodeLabel}',
                          style: TextStyle(fontSize: 12, color: context.teksKedua),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _showFormJenis(j),
                            ),
                            IconButton(
                              icon: Icon(
                                j.isAktif ? Icons.block_outlined : Icons.check_circle_outline,
                                size: 18,
                                color: j.isAktif ? Colors.red : Colors.green,
                              ),
                              onPressed: () async {
                                final r = await prov.update(j.id, isAktif: !j.isAktif);
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
                                color: j.bisaDihapus
                                    ? const Color(0xFFEF4444)
                                    : context.garis,
                              ),
                              // Backend juga menolak, tapi menonaktifkan tombol
                              // lebih jujur daripada memunculkan error.
                              tooltip: j.bisaDihapus
                                  ? 'Hapus'
                                  : 'Tidak bisa dihapus, sudah dipakai tagihan',
                              onPressed: j.bisaDihapus
                                  ? () async {
                                      final r = await prov.delete(j.id);
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
                foregroundColor: c2.gelap ? Colors.white : Colors.black,
              ),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGenerateTagihanDialog([JenisIuranModel? jenisAwal]) {
    final jenisList = context
        .read<JenisIuranProvider>()
        .list
        .where((j) => j.isAktif)
        .toList();

    if (jenisList.isEmpty) {
      _pesan('Tidak ada Master Iuran aktif untuk diterbitkan.', sukses: false);
      return;
    }

    JenisIuranModel terpilih = jenisAwal ?? jenisList.first;
    final bulanCtrl = TextEditingController(text: periodeSekarang());
    final nominalCtrl = TextEditingController(
      text: terpilih.pakaiMeteran ? '' : terpilih.nominalDefault.toStringAsFixed(0),
    );
    final ketCtrl = TextEditingController();
    DateTime? jatuhTempo;
    final jatuhTempoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_outlined, color: Color(0xFF8B5CF6)),
                ),
                const SizedBox(width: 10),
                const Text('Terbitkan Tagihan Periode'),
              ],
            ),
            content: SizedBox(
              width: lebarDialog(context, maksimal: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: terpilih.id,
                      decoration: const InputDecoration(
                        labelText: 'Pilih Master Iuran *',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: jenisList.map((j) {
                        return DropdownMenuItem<int>(
                          value: j.id,
                          child: Text('${j.namaIuran} (${j.pakaiMeteran ? 'Meteran' : 'Nominal Tetap'})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setLocal(() {
                            terpilih = jenisList.firstWhere((element) => element.id == val);
                            if (!terpilih.pakaiMeteran) {
                              nominalCtrl.text = terpilih.nominalDefault.toStringAsFixed(0);
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bulanCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Periode (YYYY-MM) *',
                        hintText: 'Contoh: 2026-08',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!terpilih.pakaiMeteran) ...[
                      TextField(
                        controller: nominalCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Nominal per KK (Rp) *',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: ketCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Keterangan Tambahan (opsional)',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: jatuhTempoCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Jatuh Tempo (opsional)',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: c,
                          initialDate: DateTime.now().add(const Duration(days: 10)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) {
                          jatuhTempo = d;
                          jatuhTempoCtrl.text = DateFormat('yyyy-MM-dd').format(d);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                style: TextButton.styleFrom(
                  foregroundColor: c.gelap ? Colors.white : Colors.black,
                ),
                child: const Text('Batal'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Terbitkan Tagihan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final bln = bulanCtrl.text.trim();
                  if (bln.isEmpty) {
                    _pesan('Periode bulan wajib diisi.', sukses: false);
                    return;
                  }
                  double? nominal;
                  if (!terpilih.pakaiMeteran) {
                    nominal = double.tryParse(nominalCtrl.text.trim());
                    if (nominal == null || nominal <= 0) {
                      _pesan('Nominal wajib diisi dengan benar.', sukses: false);
                      return;
                    }
                  }

                  Navigator.pop(c);
                  final res = await context.read<BillProvider>().generateBills(
                    jenisIuranId: terpilih.id,
                    bulan: bln,
                    nominal: nominal,
                    keterangan: ketCtrl.text.trim().isEmpty ? null : ketCtrl.text.trim(),
                    jatuhTempo: jatuhTempo == null ? null : DateFormat('yyyy-MM-dd').format(jatuhTempo!),
                  );

                  _pesan(
                    res['message']?.toString() ?? 'Selesai.',
                    sukses: res['success'] == true,
                  );
                  if (res['success'] == true) {
                    _loadData();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFormJenis(JenisIuranModel? existing) {
    final namaCtrl = TextEditingController(text: existing?.namaIuran ?? '');
    final nominalCtrl = TextEditingController(
      text: (existing?.nominalDefault ?? 0).toStringAsFixed(0),
    );
    final ketCtrl = TextEditingController(text: existing?.keterangan ?? '');
    final tarifCtrl = TextEditingController(
      text: (existing?.tarifPerM3 ?? 0).toStringAsFixed(0),
    );
    final abonCtrl = TextEditingController(
      text: (existing?.abondement ?? 0).toStringAsFixed(0),
    );
    final sampahCtrl = TextEditingController(
      text: (existing?.biayaSampah ?? 0).toStringAsFixed(0),
    );
    String periode = existing?.periode ?? 'bulanan';
    String tipeHitung = existing?.tipeHitung ?? 'tetap';

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) {
          final bermeteran = tipeHitung == 'meteran';
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(existing == null ? 'Tambah Master Iuran' : 'Ubah Master Iuran'),
            content: SizedBox(
              width: lebarDialog(context, maksimal: 400),
              // Formulir bermeteran menambah tiga field. Tanpa scroll, isinya
              // terpotong di layar ponsel — dan yang terpotong adalah tombol
              // Simpan.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: namaCtrl,
                      decoration: const InputDecoration(labelText: 'Nama Iuran *'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tipeHitung,
                      decoration: const InputDecoration(
                        labelText: 'Cara Hitung',
                        helperText: 'Meteran: nominal dihitung dari pemakaian air',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'tetap', child: Text('Nominal Tetap')),
                        DropdownMenuItem(value: 'meteran', child: Text('Meteran Air')),
                      ],
                      onChanged: (v) => setLocal(() => tipeHitung = v!),
                    ),
                    const SizedBox(height: 12),
                    if (bermeteran) ...[
                      // Tarif di sini adalah tarif untuk tagihan YANG AKAN
                      // DATANG. Ketiga angkanya disalin ke tiap tagihan saat
                      // terbit, jadi menaikkannya tidak pernah mengubah tagihan
                      // yang sudah ada — warga yang sudah lunas tidak mendadak
                      // terlihat kurang bayar.
                      TextField(
                        controller: tarifCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tarif per m³ (Rp) *',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: abonCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Abondement (Rp)',
                          helperText: 'Ditagih walau pemakaian nol',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sampahCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Biaya Sampah (Rp)',
                          helperText: 'Hanya untuk rumah yang berlangganan',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _hijau.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Tagihan = pemakaian × tarif + abondement'
                          '${(double.tryParse(sampahCtrl.text) ?? 0) > 0 ? ' + sampah' : ''}'
                          '\nTarif baru hanya berlaku untuk tagihan berikutnya.',
                          style: TextStyle(fontSize: 11, color: c2.teksKedua),
                        ),
                      ),
                    ] else
                      TextField(
                        controller: nominalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nominal Default (Rp)',
                        ),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: periode,
                      decoration: const InputDecoration(labelText: 'Periode'),
                      items: const [
                        DropdownMenuItem(value: 'bulanan', child: Text('Bulanan')),
                        DropdownMenuItem(value: 'tahunan', child: Text('Tahunan')),
                        DropdownMenuItem(value: 'sekali', child: Text('Sekali Bayar')),
                      ],
                      onChanged: (v) => setLocal(() => periode = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ketCtrl,
                      decoration: const InputDecoration(labelText: 'Keterangan (opsional)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                style: TextButton.styleFrom(
                  foregroundColor: c.gelap ? Colors.white : Colors.black,
                ),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (namaCtrl.text.trim().isEmpty) {
                    _pesan('Nama iuran wajib diisi.', sukses: false);
                    return;
                  }
                  final tarif = double.tryParse(tarifCtrl.text) ?? 0;
                  // Dijaga di sini juga, bukan hanya di backend: jenis
                  // bermeteran tanpa tarif menerbitkan tagihan sebesar
                  // abondement saja untuk seluruh RT, dan tidak ada yang
                  // terlihat salah sampai ada yang membandingkannya.
                  if (bermeteran && tarif <= 0) {
                    _pesan('Tarif per m³ wajib diisi untuk jenis bermeteran.', sukses: false);
                    return;
                  }
                  Navigator.pop(c);
                  final prov = context.read<JenisIuranProvider>();
                  final nominal = double.tryParse(nominalCtrl.text) ?? 0;
                  final abon = double.tryParse(abonCtrl.text) ?? 0;
                  final sampah = double.tryParse(sampahCtrl.text) ?? 0;
                  final r = existing == null
                      ? await prov.create(
                          namaIuran: namaCtrl.text.trim(),
                          nominalDefault: nominal,
                          periode: periode,
                          keterangan: ketCtrl.text.trim(),
                          tipeHitung: tipeHitung,
                          tarifPerM3: bermeteran ? tarif : null,
                          abondement: bermeteran ? abon : null,
                          biayaSampah: bermeteran ? sampah : null,
                        )
                      : await prov.update(
                          existing.id,
                          namaIuran: namaCtrl.text.trim(),
                          nominalDefault: nominal,
                          periode: periode,
                          keterangan: ketCtrl.text.trim(),
                          tipeHitung: tipeHitung,
                          tarifPerM3: bermeteran ? tarif : null,
                          abondement: bermeteran ? abon : null,
                          biayaSampah: bermeteran ? sampah : null,
                        );
                  _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
                },
                style: ElevatedButton.styleFrom(backgroundColor: _hijau),
                child: const Text('Simpan', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}
