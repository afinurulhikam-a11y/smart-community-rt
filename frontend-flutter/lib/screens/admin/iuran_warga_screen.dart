import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../../providers/bill_provider.dart';
import '../../../providers/jenis_iuran_provider.dart';
import '../../../providers/family_provider.dart';
import '../../../models/bill_model.dart';
import '../../../models/jenis_iuran_model.dart';
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

class IuranWargaScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const IuranWargaScreen({super.key, this.onBack});

  @override
  State<IuranWargaScreen> createState() => _IuranWargaScreenState();
}

/// Kode modul di tabel izin. Sekretaris hanya punya `view` di sini.
const String _kodeIzin = 'keuangan.iuran';

class _IuranWargaScreenState extends State<IuranWargaScreen> {
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  String _searchQuery = '';
  String _status = 'Semua Status';
  int? _jenisIuranId;
  String _bulan = 'Semua Bulan';
  String _tahun = DateTime.now().year.toString();

  /// Id tagihan yang dicentang. Dipakai tombol Bayar Massal.
  final Set<String> _terpilih = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JenisIuranProvider>().fetchJenisIuran();
      context.read<FamilyProvider>().fetchFamilies();
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
    setState(() {
      _terpilih.clear();
    });
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
    final adaPilihan = _terpilih.isNotEmpty;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        // Export tetap tersedia untuk role lihat-saja: menyalin angka yang
        // memang boleh dibaca bukan perubahan data. Sekretaris justru butuh
        // ini untuk menyusun laporan.
        if (_bolehUbah)
          _outlinedBtn(Icons.category_outlined, 'Jenis Iuran', _hijau, _showJenisIuranDialog),
        if (_bolehUbah)
          _outlinedBtn(
            Icons.payments_outlined,
            adaPilihan ? 'Bayar Massal (${_terpilih.length})' : 'Bayar Massal',
            _hijau,
            adaPilihan ? _bayarMassal : null,
          ),
        if (_bolehTambah)
          _outlinedBtn(Icons.autorenew_outlined, 'Generate Tagihan', _hijau, _showGenerateDialog),
        if (_bolehUbah)
          _outlinedBtn(
            Icons.chat_outlined,
            'Tagih Semua (WA)',
            const Color(0xFF22C55E),
            _showTagihWaDialog,
          ),
        _filledBtn(
          Icons.table_chart_outlined,
          'Export Excel',
          const Color(0xFF10B981),
          () => context.read<BillProvider>().downloadExport(format: 'excel'),
        ),
        _filledBtn(
          Icons.picture_as_pdf_outlined,
          'Export PDF',
          const Color(0xFFEF4444),
          () => context.read<BillProvider>().downloadExport(format: 'pdf'),
        ),
        if (_bolehTambah)
          _filledBtn(
            Icons.add_circle_outline,
            'Tambah Iuran',
            const Color(0xFF0F766E),
            _showTambahIuranDialog,
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
            'Jenis Iuran',
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: AppTheme.sasaranSentuh,
                child: ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.filter_alt_outlined, size: 16),
                  label: const Text(
                    'Filter',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
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
                child: Container(
                  height: AppTheme.sasaranSentuh,
                  width: AppTheme.sasaranSentuh,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: context.garis),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.close, size: 16, color: context.teksKedua),
                ),
              ),
            ],
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
          constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
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
    final idHalamanIni = halamanIni.map((b) => b.id).toSet();
    final belumLunasHalamanIni = halamanIni.where((b) => !b.isLunas).map((b) => b.id).toSet();
    final semuaTercentang =
        belumLunasHalamanIni.isNotEmpty && belumLunasHalamanIni.every(_terpilih.contains);

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
            child: SizedBox(
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
                      Icon(Icons.list_alt, color: Color(0xFF10B981), size: 20),
                      SizedBox(width: 8),
                      // Flexible + ellipsis: di layar 320px judul ini bersama
                      // ikonnya melampaui lebar kartu.
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
                    '${semua.length} data ditampilkan',
                    style: TextStyle(fontSize: 12, color: context.teksKedua),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(paddingKartu(context)),
            // Kolom pencarian diletakkan sendiri di tengah, dengan label "Cari"
            // di kiri kolomnya, supaya mata tidak perlu menyusuri baris untuk
            // mencari tempat mengetik.
            //
            // Tidak memakai lebarKolomFilter di sini: nilainya double.infinity
            // pada mobile, yang tidak aman di dalam Row (overflow). Kuncinya
            // ConstrainedBox berlebar maksimum + Expanded, jadi lebar selalu
            // berhingga dan bidang teks menyerap sisa ruang.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Row(
                  children: [
                    Text(
                      'Cari',
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
                          hintText: 'Cari nama, no KK, alamat...',
                          hintStyle: TextStyle(fontSize: 13, color: context.teksTersier),
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
          else if (semua.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 40, color: context.garis),
                    SizedBox(height: 12),
                    Text(
                      'Belum ada data iuran',
                      style: TextStyle(color: context.teksTersier, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gunakan tombol "Generate Tagihan" untuk membuat tagihan satu periode.',
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
                tinggiBarisMaks: 70,
                kolom: const [
                  'PILIH',
                  'NO',
                  'KEPALA KELUARGA',
                  'JENIS IURAN',
                  'PERIODE',
                  'NOMINAL',
                  'STATUS',
                  'TGL BAYAR',
                ],
                judulKolom: {
                  0: Checkbox(
                    value: semuaTercentang,
                    onChanged: belumLunasHalamanIni.isEmpty
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              _terpilih.addAll(belumLunasHalamanIni);
                            } else {
                              _terpilih.removeWhere(idHalamanIni.contains);
                            }
                          }),
                  ),
                },
                baris: List.generate(halamanIni.length, (i) {
                  final b = halamanIni[i];
                  return _buildRow(b, ((provider.currentPage - 1) * 25) + i + 1);
                }),
                currentPage: provider.currentPage,
                totalPages: provider.totalPages,
                onPageChanged: (page) => _loadData(page: page),
              ),
            ),
          // Hapus pagination lama, karena sudah ditangani oleh TabelResponsif
        ],
      ),
    );
  }

  BarisTabel _buildRow(BillModel b, int nomor) {
    final terlambat = b.isTerlambat;
    return BarisTabel(
      sel: [
        SelTabel(
          'PILIH',
          Checkbox(
            value: _terpilih.contains(b.id),
            // Tagihan lunas tidak bisa dipilih untuk dibayar lagi.
            onChanged: b.isLunas
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      _terpilih.add(b.id);
                    } else {
                      _terpilih.remove(b.id);
                    }
                  }),
          ),
        ),
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
        SelTabel.teks('JENIS IURAN', b.namaIuran),
        SelTabel.teks('PERIODE', b.bulan),
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
      aksi: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mencatat pembayaran adalah aksi `update` pada tagihan yang sudah
          // ada, bukan `create`.
          if (!b.isLunas && _bolehUbah)
            IconButton(
              tooltip: 'Bayar',
              icon: const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF059669)),
              onPressed: () => _bayarSatu(b),
            ),
          if (!b.isLunas && _bolehUbah && (b.noHp?.isNotEmpty ?? false))
            IconButton(
              tooltip: 'Tagih via WhatsApp',
              icon: const Icon(Icons.chat_outlined, size: 18, color: Color(0xFF22C55E)),
              onPressed: () => _tagihSatu(b),
            ),
          if (b.isLunas)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
            ),
          if (_bolehHapus)
            IconButton(
              tooltip: 'Hapus Tagihan',
              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
              onPressed: () => _hapusTagihan(b),
            ),
          if (!b.isLunas && !_bolehUbah && !_bolehHapus)
            Text('—', style: TextStyle(fontSize: 13, color: context.teksTersier)),
        ],
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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
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

  Future<void> _bayarMassal() async {
    final jumlah = _terpilih.length;
    final total = context
        .read<BillProvider>()
        .bills
        .where((b) => _terpilih.contains(b.id))
        .fold<double>(0, (s, b) => s + b.nominal);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Bayar Massal'),
        content: Text('Tandai $jumlah tagihan senilai ${_rupiah(total)} sebagai LUNAS?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            child: const Text('Bayar Semua', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final hasil = await context.read<BillProvider>().payBillsBulk(_terpilih.toList());

    // `mounted` diperiksa LAGI setelah await ini, bukan hanya setelah dialog.
    // payBillsBulk bisa memakan ~21 detik pada jaringan buruk (ApiService
    // mengulang dua kali dengan batas 10 detik), dan berpindah layar selama
    // rentang itu membuat setState di bawah dipanggil pada State yang sudah
    // dilepas — pengecualian yang muncul justru pada alur pembayaran.
    if (!mounted) return;

    setState(_terpilih.clear);
    _pesan(hasil['message']?.toString() ?? 'Selesai.', sukses: hasil['success'] == true);
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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
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

  Future<void> _tagihSatu(BillModel b) async {
    final berhasil = await context.read<BillProvider>().tagihViaWhatsApp(
      noHp: b.noHp ?? '',
      namaKepalaKeluarga: b.kepalaKeluarga,
      tagihan: [b],
    );
    if (!berhasil) _pesan('Gagal membuka WhatsApp. Pastikan nomor HP terisi.', sukses: false);
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
                              onPressed: adaHp
                                  ? () => context.read<BillProvider>().tagihViaWhatsApp(
                                      noHp: list.first.noHp!,
                                      namaKepalaKeluarga: list.first.kepalaKeluarga,
                                      tagihan: list,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup'))],
      ),
    );
  }

  void _showGenerateDialog() {
    final jenisList = context.read<JenisIuranProvider>().aktif;
    if (jenisList.isEmpty) {
      _pesan('Belum ada jenis iuran aktif. Tambahkan lewat tombol "Jenis Iuran".', sukses: false);
      return;
    }

    int jenisId = jenisList.first.id;
    final nominalCtrl = TextEditingController(
      text: jenisList.first.nominalDefault.toStringAsFixed(0),
    );
    final bulanCtrl = TextEditingController(text: DateFormat('yyyy-MM').format(DateTime.now()));

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Generate Tagihan'),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Membuat satu tagihan untuk setiap kartu keluarga. '
                    'KK yang sudah punya tagihan pada periode ini akan dilewati.',
                    style: TextStyle(fontSize: 12, color: context.teksKedua),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: jenisId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Jenis Iuran'),
                  items: jenisList
                      .map((j) => DropdownMenuItem(value: j.id, child: Text(j.namaIuran)))
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    jenisId = v!;
                    nominalCtrl.text = jenisList
                        .firstWhere((j) => j.id == v)
                        .nominalDefault
                        .toStringAsFixed(0);
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bulanCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Periode (YYYY-MM)',
                    hintText: '2026-07',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final nominal = double.tryParse(nominalCtrl.text);
                if (nominal == null || nominal <= 0) {
                  _pesan('Nominal harus berupa angka lebih dari 0.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final hasil = await context.read<BillProvider>().generateBills(
                  jenisIuranId: jenisId,
                  bulan: bulanCtrl.text.trim(),
                  nominal: nominal,
                );
                _pesan(
                  hasil['message']?.toString() ?? 'Selesai.',
                  sukses: hasil['success'] == true,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: _hijau),
              child: const Text('Generate', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showTambahIuranDialog() {
    final jenisList = context.read<JenisIuranProvider>().aktif;
    final keluargaList = context.read<FamilyProvider>().families;

    if (jenisList.isEmpty) {
      _pesan('Belum ada jenis iuran aktif.', sukses: false);
      return;
    }
    if (keluargaList.isEmpty) {
      _pesan('Belum ada data kartu keluarga.', sukses: false);
      return;
    }

    int jenisId = jenisList.first.id;
    int keluargaId = keluargaList.first['id'] as int;
    final nominalCtrl = TextEditingController(
      text: jenisList.first.nominalDefault.toStringAsFixed(0),
    );
    final bulanCtrl = TextEditingController(text: DateFormat('yyyy-MM').format(DateTime.now()));

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Iuran'),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: keluargaId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kartu Keluarga'),
                  items: keluargaList.map((k) {
                    final nama = (k['kepala_keluarga']?.toString().trim().isNotEmpty ?? false)
                        ? k['kepala_keluarga'].toString()
                        : '(Belum diisi)';
                    return DropdownMenuItem(
                      value: k['id'] as int,
                      child: Text('$nama — ${k['no_kk']}', overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (v) => setLocal(() => keluargaId = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: jenisId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Jenis Iuran'),
                  items: jenisList
                      .map((j) => DropdownMenuItem(value: j.id, child: Text(j.namaIuran)))
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    jenisId = v!;
                    nominalCtrl.text = jenisList
                        .firstWhere((j) => j.id == v)
                        .nominalDefault
                        .toStringAsFixed(0);
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bulanCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Periode (YYYY-MM)',
                    hintText: '2026-07',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(c);
                final hasil = await context.read<BillProvider>().createBill(
                  keluargaId: keluargaId,
                  jenisIuranId: jenisId,
                  bulan: bulanCtrl.text.trim(),
                  nominal: double.tryParse(nominalCtrl.text),
                );
                _pesan(
                  hasil['message']?.toString() ?? 'Selesai.',
                  sukses: hasil['success'] == true,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: _hijau),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
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
                const Text('Kelola Jenis Iuran'),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: _hijau),
                  tooltip: 'Tambah jenis iuran',
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
                ? const Center(child: Text('Belum ada jenis iuran.'))
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
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: j.isAktif ? null : context.teksKedua,
                                ),
                              ),
                            ),
                            if (!j.isAktif)
                              Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Text(
                                  'nonaktif',
                                  style: TextStyle(fontSize: 10, color: context.teksKedua),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${_rupiah(j.nominalDefault)} · ${j.periodeLabel} · '
                          '${j.jumlahTagihan} tagihan',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Ubah',
                              onPressed: () => _showFormJenis(j),
                            ),
                            IconButton(
                              icon: Icon(
                                j.isAktif ? Icons.toggle_on : Icons.toggle_off,
                                size: 22,
                                color: j.isAktif ? const Color(0xFF10B981) : context.teksKedua,
                              ),
                              tooltip: j.isAktif ? 'Nonaktifkan' : 'Aktifkan',
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
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup'))],
        ),
      ),
    );
  }

  void _showFormJenis(JenisIuranModel? existing) {
    final namaCtrl = TextEditingController(text: existing?.namaIuran ?? '');
    final nominalCtrl = TextEditingController(
      text: (existing?.nominalDefault ?? 0).toStringAsFixed(0),
    );
    final ketCtrl = TextEditingController(text: existing?.keterangan ?? '');
    String periode = existing?.periode ?? 'bulanan';

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'Tambah Jenis Iuran' : 'Ubah Jenis Iuran'),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: namaCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Iuran *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nominalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal Default (Rp)'),
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
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                if (namaCtrl.text.trim().isEmpty) {
                  _pesan('Nama iuran wajib diisi.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final prov = context.read<JenisIuranProvider>();
                final nominal = double.tryParse(nominalCtrl.text) ?? 0;
                final r = existing == null
                    ? await prov.create(
                        namaIuran: namaCtrl.text.trim(),
                        nominalDefault: nominal,
                        periode: periode,
                        keterangan: ketCtrl.text.trim(),
                      )
                    : await prov.update(
                        existing.id,
                        namaIuran: namaCtrl.text.trim(),
                        nominalDefault: nominal,
                        periode: periode,
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
