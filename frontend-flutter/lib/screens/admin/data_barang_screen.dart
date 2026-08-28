import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../providers/inventory_provider.dart';
import '../../models/inventory_model.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/banner_lihat_saja.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/format.dart';
import '../../core/pesan.dart';

const Color _hijau = Color(0xFF1B7A6A);
const Color _merah = Color(0xFFEF4444);
const Color _hijauTerang = Color(0xFF059669);

const List<String> _opsiKategori = [
  'Elektronik',
  'Furnitur',
  'Perlengkapan Acara',
  'Alat Kebersihan',
  'Olahraga',
  'Lainnya',
];

const List<String> _opsiKondisi = ['Baik', 'Perlu Perbaikan', 'Rusak'];

class DataBarangScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const DataBarangScreen({super.key, this.onBack});

  @override
  State<DataBarangScreen> createState() => _DataBarangScreenState();
}

/// Kode modul di tabel izin. Bendahara hanya punya `view`, dan warga tidak
/// punya akses sama sekali — ia meminjam lewat layar Peminjaman.
const String _kodeIzin = 'inventaris.barang';

class _DataBarangScreenState extends State<DataBarangScreen> {
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  String _kategori = 'Semua Kategori';
  String _kondisi = 'Semua Kondisi';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    context.read<InventoryProvider>().fetchInventory(
      kategori: _kategori == 'Semua Kategori' ? null : _kategori,
      kondisi: _kondisi == 'Semua Kondisi' ? null : _kondisi,
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );
  }

  String _rupiah(double n) => rupiah(n);

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BannerLihatSaja(kode: _kodeIzin),
        _buildHeader(),
        const SizedBox(height: 16),
        _buildStatCards(provider),
        const SizedBox(height: 16),
        _buildActionButtons(provider),
        const SizedBox(height: 16),
        _buildDataCard(provider),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
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
              color: _hijau.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.grid_view_rounded, color: _hijau, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Inventaris / Data Barang',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.teksKedua,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(InventoryProvider provider) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _filledBtn(
          Icons.table_chart_outlined,
          'Laporan Excel',
          const Color(0xFF10B981),
          () => provider.downloadExport(format: 'excel', peminjaman: false),
        ),
        _filledBtn(
          Icons.picture_as_pdf_outlined,
          'Laporan PDF',
          _merah,
          () => provider.downloadExport(format: 'pdf', peminjaman: false),
        ),
        if (_bolehTambah)
          _filledBtn(
            Icons.add,
            'Tambah Barang',
            _hijauTerang,
            () => _showFormBarang(null),
          ),
      ],
    );
  }

  Widget _buildStatCards(InventoryProvider provider) {
    final s = provider.statsBarang;
    return LayoutBuilder(
      builder: (context, c) {
        final kolom = c.maxWidth > 900 ? 4 : (c.maxWidth > 500 ? 2 : 1);
        final lebar = (c.maxWidth - (16 * (kolom - 1))) / kolom;
        final kartu = [
          _statCard(
            'Total Aset',
            '${s.totalAset}',
            '${s.totalUnit} unit',
            Icons.inventory_2_outlined,
            _hijau,
          ),
          _statCard(
            'Kondisi Baik',
            '${s.kondisiBaik}',
            'jenis barang',
            Icons.check_circle_outline,
            const Color(0xFF10B981),
          ),
          _statCard(
            'Perlu Perbaikan',
            '${s.perluPerbaikan}',
            'jenis barang',
            Icons.warning_amber_rounded,
            const Color(0xFFF59E0B),
          ),
          _statCard(
            'Total Nilai',
            _rupiah(s.totalNilai),
            '${s.unitDipinjam} unit dipinjam',
            Icons.credit_card,
            const Color(0xFF3B82F6),
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

  Widget _statCard(
    String label,
    String nilai,
    String sub,
    IconData ikon,
    Color warna,
  ) {
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

  Widget _buildDataCard(InventoryProvider provider) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Icon(Icons.inventory_2_outlined, color: _hijau),
                Text(
                  'Data Barang Inventaris',
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
                width: 250,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: context.teksUtama, fontSize: 13),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) {
                    _searchQuery = v.trim();
                    _loadData();
                  },
                  decoration: InputDecoration(
                    hintText: 'Nama barang, lokasi...',
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
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: _hijau),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _kategori = 'Semua Kategori';
                    _kondisi = 'Semua Kondisi';
                    _searchQuery = '';
                    _searchController.clear();
                  });
                  _loadData();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.teksKedua,
                  side: BorderSide(color: context.garis),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _dropdownFilter('Kategori:', _kategori, ['Semua Kategori', ..._opsiKategori], (v) {
                setState(() => _kategori = v!);
                _loadData();
              }),
              _dropdownFilter('Kondisi:', _kondisi, ['Semua Kondisi', ..._opsiKondisi], (v) {
                setState(() => _kondisi = v!);
                _loadData();
              }),
            ],
          ),
          const SizedBox(height: 20),
          if (provider.isLoading && provider.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator(color: _hijau)),
            )
          else if (provider.items.isEmpty)
            _buildKosong()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 650;
                final itemWidth = isMobile
                    ? constraints.maxWidth
                    : (constraints.maxWidth > 950
                        ? (constraints.maxWidth - 32) / 3
                        : (constraints.maxWidth - 16) / 2);
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: provider.items
                      .map((item) => SizedBox(
                            width: itemWidth,
                            child: _buildBarangCard(item),
                          ))
                      .toList(),
                );
              },
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.teksKedua)),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(
            minHeight: AppTheme.sasaranSentuh,
            maxHeight: AppTheme.sasaranSentuh,
          ),
          width: 140,
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

  Widget _buildKosong() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: context.garis),
          SizedBox(height: 12),
          Text(
            'Tidak ada barang ditemukan',
            style: TextStyle(fontSize: 14, color: context.teksTersier),
          ),
          SizedBox(height: 4),
          Text(
            'Gunakan tombol "Tambah Barang" untuk mencatat inventaris RT.',
            style: TextStyle(fontSize: 11, color: context.garis),
          ),
        ],
      ),
    );
  }

  Widget _buildBarangCard(InventoryModel b) {
    final baik = b.kondisiBaik;
    return Container(
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 130,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.garis,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Icon(Icons.inventory_2, size: 52, color: context.teksTersier),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: baik ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        baik ? Icons.check_circle : Icons.build_circle,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        b.kondisi,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (b.sedangDipinjam > 0)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${b.sedangDipinjam} dipinjam',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981)),
                        ),
                        child: Text(
                          b.kategori ?? 'Lainnya',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (b.lokasi != null && b.lokasi!.isNotEmpty)
                        Flexible(
                          child: Text(
                            b.lokasi!,
                            style: TextStyle(fontSize: 10, color: context.teksTersier),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  b.namaBarang,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_rupiah(b.nilaiBarang)} / unit  ·  total ${_rupiah(b.nilaiTotal)}',
                  style: TextStyle(fontSize: 11, color: context.teksKedua),
                ),
                const SizedBox(height: 12),
                // Tiga angka yang dulu tercampur menjadi satu kolom.
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: context.latarLembut,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _angkaStok('Total', b.jumlahTotal, const Color(0xFF334155)),
                      _angkaStok('Dipinjam', b.sedangDipinjam, const Color(0xFF3B82F6)),
                      _angkaStok('Tersedia', b.tersedia, b.tersedia > 0 ? _hijauTerang : _merah),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _showDetail(b),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hijauTerang,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          'Detail',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_bolehUbah)
                      IconButton(
                        tooltip: 'Ubah',
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B82F6)),
                        onPressed: () => _showFormBarang(b),
                      ),
                    if (_bolehHapus)
                      IconButton(
                        tooltip: b.bisaDihapus
                            ? 'Hapus'
                            : 'Tidak bisa dihapus, ${b.sedangDipinjam} unit sedang dipinjam',
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: b.bisaDihapus ? _merah : context.garis,
                        ),
                        onPressed: b.bisaDihapus ? () => _hapusBarang(b) : null,
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

  Widget _angkaStok(String label, int nilai, Color warna) {
    return Column(
      children: [
        Text(
          '$nilai',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: warna),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: context.teksTersier)),
      ],
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


  // -------------------------------------------------------------- dialogs

  Future<void> _hapusBarang(InventoryModel b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Barang'),
        content: Text('Hapus "${b.namaBarang}" (${b.jumlahTotal} unit) dari inventaris?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            style: TextButton.styleFrom(foregroundColor: c.warnaTombolTutup),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: _merah),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await context.read<InventoryProvider>().deleteInventory(b.id);
    _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
  }

  void _showFormBarang(InventoryModel? existing) {
    final namaCtrl = TextEditingController(text: existing?.namaBarang ?? '');
    final jumlahCtrl = TextEditingController(text: (existing?.jumlahTotal ?? 1).toString());
    final lokasiCtrl = TextEditingController(text: existing?.lokasi ?? '');
    final nilaiCtrl = TextEditingController(text: (existing?.nilaiBarang ?? 0).toStringAsFixed(0));
    final ketCtrl = TextEditingController(text: existing?.keterangan ?? '');
    final tglCtrl = TextEditingController(
      text: existing?.tanggalPerolehan == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(existing!.tanggalPerolehan!),
    );
    String kategori = _opsiKategori.contains(existing?.kategori)
        ? existing!.kategori!
        : _opsiKategori.last;
    String kondisi = _opsiKondisi.contains(existing?.kondisi)
        ? existing!.kondisi
        : _opsiKondisi.first;

    InputDecoration dekor(
      String label,
      IconData ikon, {
      String? helperText,
      String? hintText,
    }) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 14, color: context.teksKedua),
      hintText: hintText,
      helperText: helperText,
      prefixIcon: Icon(ikon, color: _hijau, size: 20),
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
        borderSide: const BorderSide(color: _hijau, width: 1.5),
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
                  color: _hijau.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: _hijau, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  existing == null ? 'Tambah Barang' : 'Ubah Barang',
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
                    controller: namaCtrl,
                    decoration: dekor('Nama Barang *', Icons.inventory_2_outlined),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: kategori,
                    isExpanded: true,
                    decoration: dekor('Kategori', Icons.category_outlined),
                    dropdownColor: context.latarKartu,
                    borderRadius: BorderRadius.circular(12),
                    items: _opsiKategori
                        .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                        .toList(),
                    onChanged: (v) => setLocal(() => kategori = v!),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: jumlahCtrl,
                          keyboardType: TextInputType.number,
                          decoration: dekor(
                            'Jumlah Total *',
                            Icons.format_list_numbered,
                            helperText: existing != null && existing.sedangDipinjam > 0
                                ? 'Min. ${existing.sedangDipinjam} (sedang dipinjam)'
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: kondisi,
                          isExpanded: true,
                          decoration: dekor('Kondisi', Icons.rule_outlined),
                          dropdownColor: context.latarKartu,
                          borderRadius: BorderRadius.circular(12),
                          items: _opsiKondisi
                              .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                              .toList(),
                          onChanged: (v) => setLocal(() => kondisi = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nilaiCtrl,
                    keyboardType: TextInputType.number,
                    decoration: dekor(
                      'Nilai per Unit (Rp)',
                      Icons.attach_money,
                      helperText: 'Dipakai kartu Total Nilai',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: lokasiCtrl,
                    decoration: dekor(
                      'Lokasi Penyimpanan',
                      Icons.place_outlined,
                      hintText: 'contoh: Gudang RT',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: tglCtrl,
                    readOnly: true,
                    decoration: dekor('Tanggal Perolehan', Icons.calendar_today),
                    onTap: () async {
                      final dipilih = await showDatePicker(
                        context: c,
                        initialDate: existing?.tanggalPerolehan ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        helpText: 'Pilih Tanggal Perolehan',
                      );
                      if (dipilih != null) {
                        tglCtrl.text = DateFormat('yyyy-MM-dd').format(dipilih);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ketCtrl,
                    maxLines: 2,
                    decoration: dekor('Keterangan (opsional)', Icons.notes),
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
                if (namaCtrl.text.trim().isEmpty) {
                  _pesan('Nama barang wajib diisi.', sukses: false);
                  return;
                }
                final jumlah = int.tryParse(jumlahCtrl.text);
                if (jumlah == null || jumlah < 0) {
                  _pesan('Jumlah harus berupa angka tidak negatif.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final prov = context.read<InventoryProvider>();
                final r = existing == null
                    ? await prov.createInventory(
                        namaBarang: namaCtrl.text.trim(),
                        kategori: kategori,
                        jumlah: jumlah,
                        kondisi: kondisi,
                        lokasi: lokasiCtrl.text.trim(),
                        nilaiBarang: double.tryParse(nilaiCtrl.text) ?? 0,
                        tanggalPerolehan: tglCtrl.text,
                        keterangan: ketCtrl.text.trim(),
                      )
                    : await prov.updateInventory(existing.id, {
                        'nama_barang': namaCtrl.text.trim(),
                        'kategori': kategori,
                        'jumlah': jumlah,
                        'kondisi': kondisi,
                        'lokasi': lokasiCtrl.text.trim(),
                        'nilai_barang': double.tryParse(nilaiCtrl.text) ?? 0,
                        if (tglCtrl.text.isNotEmpty) 'tanggal_perolehan': tglCtrl.text,
                        'keterangan': ketCtrl.text.trim(),
                      });
                _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _hijau,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(InventoryModel b) async {
    final detail = await context.read<InventoryProvider>().fetchInventoryDetail(b.id);
    if (!mounted) return;
    if (detail == null) {
      _pesan('Gagal memuat detail barang.', sukses: false);
      return;
    }

    final riwayat = (detail['riwayat'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(b.namaBarang),
        content: SizedBox(
          width: lebarDialog(context, maksimal: 560),
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _detailBaris('Kategori', b.kategori ?? '-'),
                  _detailBaris('Kondisi', b.kondisi),
                  _detailBaris('Lokasi', b.lokasi ?? '-'),
                  _detailBaris('Total', '${b.jumlahTotal} unit'),
                  _detailBaris('Dipinjam', '${b.sedangDipinjam} unit'),
                  _detailBaris('Tersedia', '${b.tersedia} unit'),
                  _detailBaris('Nilai/unit', _rupiah(b.nilaiBarang)),
                  _detailBaris('Nilai total', _rupiah(b.nilaiTotal)),
                  if (b.tanggalPerolehan != null)
                    _detailBaris(
                      'Perolehan',
                      DateFormat('dd MMM yyyy').format(b.tanggalPerolehan!),
                    ),
                ],
              ),
              if (b.keterangan != null && b.keterangan!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(b.keterangan!, style: TextStyle(fontSize: 12, color: context.teksKedua)),
              ],
              const Divider(height: 24),
              const Text(
                'Riwayat Peminjaman',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: riwayat.isEmpty
                    ? Center(
                        child: Text(
                          'Belum pernah dipinjam.',
                          style: TextStyle(fontSize: 12, color: context.teksTersier),
                        ),
                      )
                    : ListView.separated(
                        itemCount: riwayat.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = riwayat[i];
                          final status = r['status_efektif']?.toString() ?? '-';
                          final terlambat = status == 'Terlambat';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${r['nama_peminjam'] ?? '-'} · ${r['jumlah'] ?? 0} unit',
                              style: const TextStyle(fontSize: 12),
                            ),
                            subtitle: Text(
                              'Pinjam ${r['tanggal_pinjam']?.toString().split('T').first ?? '-'}'
                              '${r['tanggal_kembali'] != null ? ' · kembali ${r['tanggal_kembali'].toString().split('T').first}' : ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: terlambat
                                    ? _merah
                                    : (status == 'Dikembalikan'
                                          ? _hijauTerang
                                          : const Color(0xFFD97706)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            style: TextButton.styleFrom(foregroundColor: c.warnaTombolTutup),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _detailBaris(String label, String nilai) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: context.teksTersier)),
          Text(
            nilai,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
