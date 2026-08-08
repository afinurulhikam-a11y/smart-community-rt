import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_service.dart';
import '../../providers/aksi_utama_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../models/borrowing_model.dart';
import '../../providers/permission_provider.dart';
import '../../core/services/auth_service.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';
import 'data_warga_screen.dart';

const Color _hijau = Color(0xFF1B7A6A);
const Color _merah = Color(0xFFEF4444);
const Color _hijauTerang = Color(0xFF059669);
const Color _kuning = Color(0xFFD97706);

class PeminjamanScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PeminjamanScreen({super.key, this.onBack});

  @override
  State<PeminjamanScreen> createState() => _PeminjamanScreenState();
}

/// Kode modul di tabel izin. Bendahara `view`, warga `view + create`.
const String _kodeIzin = 'inventaris.peminjaman';

class _PeminjamanScreenState extends State<PeminjamanScreen> {
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  /// Warga mengajukan pinjam untuk dirinya sendiri; pengurus mencatatkan
  /// peminjaman atas nama warga lain. Perbedaan itu mengubah bentuk formnya.
  bool get _sebagaiWarga => context.read<AuthService>().userRole == 'warga';

  String _selectedFilter = 'Semua';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  /// Calon peminjam: hanya pengguna yang punya data kependudukan.
  List<Map<String, dynamic>> _daftarWarga = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      // Warga tidak punya izin inventaris maupun daftar pengguna, jadi kedua
      // permintaan itu hanya akan menghasilkan 403. Ia memakai endpoint ringkas
      // di bawah modul peminjaman, dan peminjamnya selalu dirinya sendiri.
      final prov = context.read<InventoryProvider>();
      if (_sebagaiWarga) {
        prov.fetchBarangTersedia();
      } else {
        prov.fetchInventory();
        _muatDaftarWarga();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _muatDaftarWarga() async {
    final r = await ApiService.get(ApiConstants.users, queryParams: {'terdaftar': 'true'});
    if (r['success'] == true && mounted) {
      setState(() {
        _daftarWarga = (r['data'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
      });
    }
  }

  void _loadData() {
    context.read<InventoryProvider>().fetchBorrowings(
      status: _selectedFilter == 'Semua' ? null : _selectedFilter,
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );
  }

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses);
  }

  String _tgl(DateTime? d) => d == null ? '-' : DateFormat('dd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    // Aksi utama layar ini, digambar kerangka sebagai FAB.
    final aksi = context.read<AksiUtamaProvider>();
    if (_bolehTambah && pakaiKartu(context)) {
      aksi.pasang(
        aksi: () => _showFormPinjam(null),
        label: _sebagaiWarga ? 'Ajukan' : 'Catat',
        ikon: Icons.add,
      );
    } else {
      aksi.lepas();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(provider),
        const SizedBox(height: 24),
        _buildStatCards(provider),
        const SizedBox(height: 24),
        _buildFilters(),
        const SizedBox(height: 16),
        _buildTabel(provider),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHeader(InventoryProvider provider) {
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
                  child: Icon(Icons.swap_horiz_rounded, color: _hijau, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Inventaris / Peminjaman',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.teksKedua,
                    ),
                  ),
                ),
              ],
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _outlinedBtn(
                Icons.table_chart_outlined,
                'Excel',
                const Color(0xFF10B981),
                () => provider.downloadExport(format: 'excel', peminjaman: true),
              ),
              _outlinedBtn(
                Icons.picture_as_pdf_outlined,
                'PDF',
                _merah,
                () => provider.downloadExport(format: 'pdf', peminjaman: true),
              ),
              if (_bolehTambah)
                ElevatedButton.icon(
                  onPressed: () => _showFormPinjam(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    _sebagaiWarga ? 'Ajukan Pinjam' : 'Catat Peminjaman',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hijauTerang,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards(InventoryProvider provider) {
    final s = provider.statsPinjam;
    return LayoutBuilder(
      builder: (context, c) {
        final kolom = c.maxWidth > 900 ? 4 : (c.maxWidth > 500 ? 2 : 1);
        final lebar = (c.maxWidth - (16 * (kolom - 1))) / kolom;
        final kartu = [
          _statCard(
            'Total Catatan',
            '${s.total}',
            Icons.swap_calls,
            const Color(0xFF8B5CF6),
            const Color(0xFFF3E8FF),
          ),
          _statCard(
            'Sedang Dipinjam',
            '${s.dipinjam}',
            Icons.outbond_outlined,
            const Color(0xFFF59E0B),
            const Color(0xFFFEFCE8),
          ),
          _statCard(
            'Dikembalikan',
            '${s.dikembalikan}',
            Icons.check_circle_outline,
            const Color(0xFF10B981),
            const Color(0xFFF0FDF4),
          ),
          // Dulu selalu 0: tidak ada tanggal jatuh tempo, dan status 'Terlambat'
          // tidak pernah ditulis ke database. Sekarang dihitung backend.
          _statCard(
            'Terlambat',
            '${s.terlambat}',
            Icons.access_time,
            _merah,
            const Color(0xFFFEF2F2),
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

  Widget _statCard(String label, String nilai, IconData ikon, Color warna, Color latar) {
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
            decoration: BoxDecoration(color: latar, borderRadius: BorderRadius.circular(12)),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _chip('Semua', Icons.menu),
        _chip('Dipinjam', Icons.outbond_outlined),
        _chip('Dikembalikan', Icons.check_circle_outline),
        _chip('Terlambat', Icons.access_time),
        const SizedBox(width: 8),
        SizedBox(
          width: lebarKolomFilter(context, maksimal: 250),
          child: TextField(
            controller: _searchController,
            onSubmitted: (v) {
              _searchQuery = v;
              _loadData();
            },
            decoration: InputDecoration(
              hintText: 'Cari barang / peminjam...',
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
    );
  }

  Widget _chip(String label, IconData ikon) {
    final aktif = _selectedFilter == label;
    return InkWell(
      onTap: () {
        setState(() => _selectedFilter = label);
        _loadData();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: aktif ? const Color(0xFF1B7A6A) : context.latarKartu,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: aktif ? const Color(0xFF1B7A6A) : context.garis),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon, size: 14, color: aktif ? Colors.white : context.teksKedua),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: aktif ? Colors.white : context.teksKedua,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabel(InventoryProvider provider) {
    if (provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (provider.borrowings.isEmpty) {
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
            Icon(Icons.swap_horiz, size: 48, color: context.garis),
            SizedBox(height: 12),
            Text(
              'Belum ada catatan peminjaman',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.teksUtama),
            ),
            SizedBox(height: 4),
            Text(
              'Gunakan tombol "Catat Peminjaman" untuk mencatat barang yang keluar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.teksTersier),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Padding(
        padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
        child: TabelResponsif(
          tinggiBarisMaks: 76,
          kolom: const [
            'NO',
            'BARANG',
            'PEMINJAM',
            'JUMLAH',
            'TGL PINJAM',
            'JATUH TEMPO',
            'TGL KEMBALI',
            'STATUS',
          ],
          baris: List.generate(
            provider.borrowings.length,
            (i) => _buildRow(provider.borrowings[i], i + 1),
          ),
        ),
      ),
    );
  }

  BarisTabel _buildRow(BorrowingModel b, int nomor) {
    final sNama = b.status.toLowerCase();
    final isPending = sNama.contains('menunggu');
    final isDitolak = sNama.contains('ditolak');
    final isDipinjam = sNama == 'dipinjam';
    final terlambat = b.isTerlambat;

    final warnaStatus = terlambat
        ? _merah
        : (b.isDikembalikan
            ? _hijauTerang
            : (isPending ? _kuning : (isDitolak ? _merah : const Color(0xFFEA580C))));
    final latarStatus = terlambat
        ? const Color(0xFFFEE2E2)
        : (b.isDikembalikan
            ? const Color(0xFFDCFCE7)
            : (isPending
                ? const Color(0xFFFEF3C7)
                : (isDitolak ? const Color(0xFFFEE2E2) : const Color(0xFFFFEDD5))));

    return BarisTabel(
      // Baris yang lewat tempo ditandai agar langsung terlihat.
      warna: terlambat ? _merah.withValues(alpha: 0.04) : null,
      sel: [
        SelTabel.teks('NO', '$nomor', sembunyiDiKartu: true),
        SelTabel(
          'BARANG',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(b.namaBarang, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (b.kategori != null)
                Text(b.kategori!, style: TextStyle(fontSize: 10, color: context.teksTersier)),
            ],
          ),
          utama: true,
        ),
        SelTabel.teks('PEMINJAM', b.namaPeminjam),
        SelTabel.teks(
          'JUMLAH',
          '${b.jumlah}',
          gaya: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SelTabel.teks(
          'TGL PINJAM',
          _tgl(b.tanggalPinjam),
          gaya: TextStyle(fontSize: 12, color: context.teksUtama),
        ),
        SelTabel.teks(
          'JATUH TEMPO',
          _tgl(b.tanggalRencanaKembali),
          gaya: TextStyle(
            fontSize: 12,
            color: terlambat ? _merah : const Color(0xFF334155),
            fontWeight: terlambat ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        SelTabel.teks(
          'TGL KEMBALI',
          _tgl(b.tanggalKembali),
          gaya: TextStyle(
            fontSize: 12,
            color: b.tanggalKembali == null ? context.garis : const Color(0xFF334155),
          ),
        ),
        SelTabel(
          'STATUS',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: latarStatus,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  b.statusEfektif.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: warnaStatus),
                ),
              ),
              if (terlambat)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${b.hariTerlambat} hari',
                    style: const TextStyle(fontSize: 10, color: _merah),
                  ),
                ),
            ],
          ),
        ),
      ],
      aksi: Transform.translate(
        offset: const Offset(geserAksiTabel, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPending && _bolehUbah) ...[
              IconButton(
                tooltip: 'Setujui',
                icon: const Icon(Icons.check_circle_outline, size: 20, color: _hijauTerang),
                style: gayaAksiTabel(_hijauTerang),
                onPressed: () async {
                  final r = await context.read<InventoryProvider>().approveBorrowing(b.id);
                  if (mounted && r['success'] == true) {
                    pesanSukses(context, 'Peminjaman berhasil disetujui.');
                  }
                },
              ),
              IconButton(
                tooltip: 'Tolak',
                icon: const Icon(Icons.highlight_off_outlined, size: 20, color: _merah),
                style: gayaAksiTabel(_merah),
                onPressed: () async {
                  final r = await context.read<InventoryProvider>().rejectBorrowing(b.id);
                  if (mounted && r['success'] == true) {
                    pesanSukses(context, 'Peminjaman ditolak.');
                  }
                },
              ),
            ] else if ((isDipinjam || !b.isDikembalikan) && !isDitolak && _bolehUbah) ...[
              IconButton(
                tooltip: 'Kembalikan',
                icon: const Icon(Icons.assignment_return_outlined, size: 20, color: _hijauTerang),
                style: gayaAksiTabel(_hijauTerang),
                onPressed: () => _kembalikan(b),
              ),
            ],
            if (!b.isDikembalikan && _bolehUbah)
              IconButton(
                tooltip: 'Ubah',
                icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF3B82F6)),
                style: gayaAksiTabel(const Color(0xFF3B82F6)),
                onPressed: () => _showFormPinjam(b),
              ),
            if (_bolehHapus || (context.watch<AuthService>().userId.toString() == b.userId && !b.isDikembalikan))
              IconButton(
                tooltip: b.bisaDibatalkan
                    ? 'Batalkan catatan'
                    : 'Riwayat pengembalian tidak bisa dihapus',
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: b.bisaDibatalkan ? _merah : context.garis,
                ),
                style: gayaAksiTabel(b.bisaDibatalkan ? _merah : context.garis),
                onPressed: b.bisaDibatalkan ? () => _batalkan(b) : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _outlinedBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  // -------------------------------------------------------------- dialogs

  Future<void> _kembalikan(BorrowingModel b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi Pengembalian'),
        content: Text(
          'Tandai ${b.jumlah} unit ${b.namaBarang} dari ${b.namaPeminjam} '
          'sebagai sudah dikembalikan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: _hijauTerang),
            child: const Text('Kembalikan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await context.read<InventoryProvider>().returnBorrowing(b.id);
    _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
  }

  Future<void> _batalkan(BorrowingModel b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Batalkan Catatan'),
        content: Text(
          'Hapus catatan peminjaman ${b.namaBarang} oleh ${b.namaPeminjam}? '
          'Gunakan ini hanya bila catatannya keliru.',
        ),
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
    final r = await context.read<InventoryProvider>().deleteBorrowing(b.id);
    _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
  }

  void _showFormPinjam(BorrowingModel? existing, {int? initialBarangId}) {
    final prov = context.read<InventoryProvider>();
    final barangList = existing == null
        ? prov.barangTersedia
        : prov.items; // saat mengubah, barangnya sudah terpilih

    if (existing == null && barangList.isEmpty) {
      _pesan('Tidak ada barang yang tersedia untuk dipinjam.', sukses: false);
      return;
    }
    // Warga meminjam untuk dirinya sendiri, jadi tidak perlu daftar warga —
    // dan memang tidak boleh mengaksesnya.
    if (!_sebagaiWarga && _daftarWarga.isEmpty) {
      _pesan('Daftar warga belum termuat. Coba beberapa saat lagi.', sukses: false);
      return;
    }

    int? barangId = existing?.inventoryId ?? initialBarangId ?? (barangList.isNotEmpty ? barangList.first.id : null);
    // Untuk warga dibiarkan null: backend memakai req.user.id dan mengabaikan
    // apa pun yang dikirim di sini.
    String? peminjamId = _sebagaiWarga
        ? null
        : (existing?.userId ?? _daftarWarga.first['id']?.toString());

    final jumlahCtrl = TextEditingController(text: (existing?.jumlah ?? 1).toString());
    final ketCtrl = TextEditingController(text: existing?.keterangan ?? '');
    final pinjamCtrl = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(existing?.tanggalPinjam ?? DateTime.now()),
    );
    final temposCtrl = TextEditingController(
      text: existing?.tanggalRencanaKembali == null
          ? DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 7)))
          : DateFormat('yyyy-MM-dd').format(existing!.tanggalRencanaKembali!),
    );

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) {
          final barangDipilih = barangList.where((b) => b.id == barangId).firstOrNull;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(existing == null ? 'Catat Peminjaman' : 'Ubah Peminjaman'),
            content: SizedBox(
              width: lebarDialog(context, maksimal: 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: barangId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Barang'),
                      // Saat mencatat baru, hanya barang bersisa yang bisa dipilih.
                      items: barangList
                          .map(
                            (b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(
                                '${b.namaBarang} — tersedia ${b.tersedia}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: existing == null ? (v) => setLocal(() => barangId = v) : null,
                    ),
                    const SizedBox(height: 12),
                    // Warga tidak memilih peminjam — pinjaman selalu atas namanya
                    // sendiri, dan backend yang memastikannya.
                    if (!_sebagaiWarga)
                      DropdownButtonFormField<String>(
                        initialValue: peminjamId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Peminjam'),
                        items: _daftarWarga
                            .map(
                              (w) => DropdownMenuItem(
                                value: w['id']?.toString(),
                                child: Text(
                                  w['nama']?.toString() ?? '-',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => peminjamId = v),
                      ),
                    if (!_sebagaiWarga) const SizedBox(height: 12),
                    TextField(
                      controller: jumlahCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Jumlah',
                        helperText: barangDipilih == null
                            ? null
                            : 'Tersedia ${barangDipilih.tersedia} dari ${barangDipilih.jumlahTotal}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pinjamCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Tanggal Pinjam',
                        prefixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: c,
                          initialDate: existing?.tanggalPinjam ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (d != null) pinjamCtrl.text = DateFormat('yyyy-MM-dd').format(d);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: temposCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Rencana Kembali (jatuh tempo)',
                        helperText: 'Lewat tanggal ini, status otomatis Terlambat',
                        prefixIcon: Icon(Icons.event_available, size: 18),
                      ),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: c,
                          initialDate:
                              existing?.tanggalRencanaKembali ??
                              DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (d != null) temposCtrl.text = DateFormat('yyyy-MM-dd').format(d);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ketCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Keterangan (opsional)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
              ElevatedButton(
                onPressed: () async {
                  final jumlah = int.tryParse(jumlahCtrl.text);
                  if (jumlah == null || jumlah <= 0) {
                    _pesan('Jumlah harus berupa angka lebih dari 0.', sukses: false);
                    return;
                  }
                  if (barangId == null) {
                    _pesan('Barang wajib dipilih.', sukses: false);
                    return;
                  }
                  if (!_sebagaiWarga && peminjamId == null) {
                    _pesan('Peminjam wajib dipilih.', sukses: false);
                    return;
                  }
                  Navigator.pop(c);
                  final r = existing == null
                      ? await prov.createBorrowing(
                          inventoryId: barangId!,
                          userId: peminjamId,
                          jumlah: jumlah,
                          tanggalPinjam: pinjamCtrl.text,
                          tanggalRencanaKembali: temposCtrl.text,
                          keterangan: ketCtrl.text.trim(),
                        )
                      : await prov.updateBorrowing(existing.id, {
                          'user_id': peminjamId,
                          'jumlah': jumlah,
                          'tanggal_pinjam': pinjamCtrl.text,
                          'tanggal_rencana_kembali': temposCtrl.text,
                          'keterangan': ketCtrl.text.trim(),
                        });
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
