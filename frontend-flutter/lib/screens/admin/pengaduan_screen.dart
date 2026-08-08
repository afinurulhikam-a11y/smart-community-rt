import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../providers/aksi_utama_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/permission_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';
import 'data_warga_screen.dart';

/// Kode modul di tabel izin. Warga `view + create` dan hanya melihat aduannya
/// sendiri (disaring backend); bendahara `view` saja.
const String _kodeIzin = 'aspirasi.pengaduan';

/// Pilihan kategori aduan. Sengaja terbatas supaya bisa dikelompokkan pengurus.
const List<String> _kategoriAduan = [
  'Lingkungan',
  'Keamanan',
  'Kebersihan',
  'Fasilitas Umum',
  'Administrasi',
  'Lainnya',
];

class PengaduanScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PengaduanScreen({super.key, this.onBack});

  @override
  State<PengaduanScreen> createState() => _PengaduanScreenState();
}

class _PengaduanScreenState extends State<PengaduanScreen> {
  String _status = 'Semua Status';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadData({int page = 1}) {
    final provider = context.read<ComplaintProvider>();
    provider.fetchComplaints(
      status: _status == 'Semua Status' ? null : _status,
      search: _searchController.text.isNotEmpty ? _searchController.text : null,
      page: page,
    );
  }

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses, perilaku: SnackBarBehavior.floating);
  }

  /// Rincian satu aduan, termasuk tanggapan pengurus bila sudah ada.
  ///
  /// Inilah cara warga memantau aduannya: uraian lengkapnya tidak muat di
  /// tabel, dan kolom tanggapan sama sekali tidak tampil di sana.
  void _showDetail(Map<String, dynamic> c) {
    final tanggapan = c['response']?.toString().trim() ?? '';
    final penanggap = c['responded_by_nama']?.toString() ?? '';
    final dibuat = DateTime.tryParse(c['created_at']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          c['judul']?.toString() ?? 'Detail Pengaduan',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: lebarDialog(context, maksimal: 460),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _barisDetail('Kode Tiket', c['kode_tiket']?.toString() ?? '-'),
                _barisDetail('Pengirim', c['nama_pengirim']?.toString() ?? '-'),
                _barisDetail('Kategori', c['kategori']?.toString() ?? '-'),
                _barisDetail('Status', c['status']?.toString() ?? 'Menunggu'),
                _barisDetail(
                  'Tanggal',
                  dibuat == null ? '-' : DateFormat('dd MMMM yyyy, HH:mm', 'id_ID').format(dibuat),
                ),
                const Divider(height: 24),
                Text(
                  'Uraian',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: context.teksKedua,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  (c['deskripsi']?.toString().trim().isEmpty ?? true)
                      ? 'Tidak ada uraian.'
                      : c['deskripsi'].toString(),
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tanggapan Pengurus',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: context.teksKedua,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tanggapan.isEmpty ? context.latarLembut : const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tanggapan.isEmpty
                        ? 'Belum ada tanggapan.'
                        : '$tanggapan${penanggap.isEmpty ? '' : '\n\n— $penanggap'}',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: tanggapan.isEmpty ? context.teksTersier : const Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ),
    );
  }

  Widget _barisDetail(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: context.teksKedua)),
          ),
          Expanded(
            child: Text(nilai, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Form ajukan pengaduan. Pengirimnya selalu akun yang sedang masuk —
  /// backend memakai req.user.id, jadi tidak ada kolom "atas nama".
  void _showFormPengaduan() {
    final judulCtrl = TextEditingController();
    final deskripsiCtrl = TextEditingController();
    String kategori = _kategoriAduan.first;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Ajukan Pengaduan',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: judulCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Judul Pengaduan',
                      hintText: 'Contoh: Lampu jalan depan blok C mati',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: kategori,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: _kategoriAduan
                        .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                        .toList(),
                    onChanged: (v) => setLocal(() => kategori = v ?? kategori),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deskripsiCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Uraian',
                      alignLabelWithHint: true,
                      hintText: 'Jelaskan lokasi dan keadaannya sejelas mungkin.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final judul = judulCtrl.text.trim();
                if (judul.isEmpty) {
                  _pesan('Judul pengaduan wajib diisi.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final prov = context.read<ComplaintProvider>();
                final ok = await prov.createComplaint(
                  judul: judul,
                  deskripsi: deskripsiCtrl.text.trim(),
                  kategori: kategori,
                );
                _pesan(
                  ok
                      ? 'Pengaduan terkirim. Pengurus akan menindaklanjuti.'
                      : (prov.errorMessage ?? 'Pengaduan gagal dikirim.'),
                  sukses: ok,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Aksi utama layar ini, digambar kerangka sebagai FAB.
    final aksi = context.read<AksiUtamaProvider>();
    if (_bolehTambah && pakaiKartu(context)) {
      aksi.pasang(aksi: _showFormPengaduan, label: 'Ajukan', ikon: Icons.add);
    } else {
      aksi.lepas();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Breadcrumb
        Container(
          padding: EdgeInsets.all(paddingKartu(context)),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.garis,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    TombolKembali(onPressed: widget.onBack),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        color: Color(0xFF0F766E),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Aspirasi & Partisipasi / Pengaduan',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _isDarkMode ? Colors.white70 : context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_bolehTambah)
                ElevatedButton.icon(
                  onPressed: _showFormPengaduan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text(
                    'Buat Pengaduan',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Data Table Card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.garis,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Table Header Title
              Padding(
                padding: EdgeInsets.all(paddingKartu(context)),
                child: Row(
                  children: [
                    const Icon(Icons.list, color: Color(0xFF0F766E), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Semua Pengaduan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.teksUtama,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.garis),

              // Table Controls (Status filter & Search)
              Padding(
                padding: EdgeInsets.all(paddingKartu(context)),
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status',
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                          const SizedBox(height: AppTheme.spasiS),
                          Container(
                            width: lebarKolomFilter(context, maksimal: 200),
                            constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: context.garis),
                              borderRadius: AppTheme.borderRadiusS,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _status,
                                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                                style: TextStyle(fontSize: 13, color: context.teksUtama),
                                items: ['Semua Status', 'Menunggu', 'Diproses', 'Selesai'].map((
                                  String val,
                                ) {
                                  return DropdownMenuItem<String>(value: val, child: Text(val));
                                }).toList(),
                                onChanged: (val) {
                                  setState(() => _status = val!);
                                  _loadData();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: lebarKolomFilter(context, maksimal: 240),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cari',
                              style: TextStyle(fontSize: 12, color: context.teksKedua),
                            ),
                            const SizedBox(height: AppTheme.spasiS),
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                                decoration: BoxDecoration(
                                  border: Border.all(color: context.garis),
                                  borderRadius: AppTheme.borderRadiusS,
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  onSubmitted: (_) => _loadData(),
                                  decoration: InputDecoration(
                                    hintText: 'Judul pengaduan...',
                                    hintStyle: TextStyle(fontSize: 13, color: context.teksTersier),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Divider(height: 1, color: context.garis),

              // The Table
              Consumer<ComplaintProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (provider.errorMessage != null) {
                    return Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          provider.errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    );
                  }

                  if (provider.complaints.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('Tidak ada data pengaduan.')),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                    child: TabelResponsif(
                      tinggiBarisMaks: 60,
                      kolom: const [
                        'NO',
                        'KODE TIKET',
                        'PENGIRIM',
                        'JUDUL',
                        'KATEGORI',
                        'STATUS',
                        'TANGGAL',
                      ],
                      baris: provider.complaints.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final c = entry.value;
                        final id = c['id'];
                        final tiket =
                            c['kode_tiket']?.toString() ?? 'TKT${id.toString().padLeft(6, '0')}';
                        final pengirim = c['nama_pengirim']?.toString() ?? '-';
                        final judul = c['judul'] ?? '-';
                        final kategori = c['kategori'] ?? '-';
                        final status = c['status'] ?? 'Menunggu';
                        final createdAt =
                            DateTime.tryParse(c['created_at'] ?? '') ?? DateTime.now();
                        final dateStr = DateFormat('dd/MM/yyyy').format(createdAt);

                        Color statusColor = Colors.orange;
                        Color statusBgColor = Colors.orange.shade50;
                        if (status == 'Diproses') {
                          statusColor = Colors.blue;
                          statusBgColor = Colors.blue.shade50;
                        } else if (status == 'Selesai') {
                          statusColor = const Color(0xFF166534);
                          statusBgColor = const Color(0xFFDCFCE7);
                        }

                        return BarisTabel(
                          onTap: () => _showDetail(c),
                          sel: [
                            SelTabel(
                              'NO',
                              Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.teksKedua,
                                ),
                              ),
                            ),
                            SelTabel(
                              'KODE TIKET',
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: context.latarLembut,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  tiket,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.teksKedua,
                                  ),
                                ),
                              ),
                            ),
                            SelTabel.teks('PENGIRIM', pengirim),
                            SelTabel.teks('JUDUL', judul, utama: true),
                            SelTabel.teks('KATEGORI', kategori),
                            SelTabel(
                              'STATUS',
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ),
                            SelTabel.teks('TANGGAL', dateStr),
                          ],
                          aksi: Transform.translate(
                            offset: const Offset(geserAksiTabel, 0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Lihat Detail',
                                  icon: const Icon(Icons.visibility_outlined, size: 20, color: Color(0xFF0F766E)),
                                  style: gayaAksiTabel(const Color(0xFF0F766E)),
                                  onPressed: () => _showDetail(c),
                                ),
                                // Menindaklanjuti aduan adalah wewenang
                                // pengurus; warga hanya memantau statusnya.
                                if (status != 'Selesai' && _bolehUbah)
                                  IconButton(
                                    tooltip: status == 'Menunggu' ? 'Proses' : 'Selesaikan',
                                    icon: Icon(
                                      status == 'Menunggu' ? Icons.published_with_changes : Icons.check_circle_outline,
                                      size: 20,
                                      color: status == 'Menunggu' ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                                    ),
                                    style: gayaAksiTabel(
                                      status == 'Menunggu' ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                                    ),
                                    onPressed: () async {
                                      final newStatus = status == 'Menunggu' ? 'Diproses' : 'Selesai';
                                      await provider.updateComplaintStatus(id, status: newStatus);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Consumer<ComplaintProvider>(
                builder: (context, provider, child) {
                  if (provider.complaints.isEmpty) return const SizedBox.shrink();
                  final totalData = provider.totalData;
                  final currentPage = provider.currentPage;
                  final totalPages = provider.totalPages;
                  final mulai = (currentPage - 1) * 25;
                  final akhir = (mulai + provider.complaints.length).clamp(0, totalData);
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          Text(
                            totalData == 0
                                ? 'Tidak ada data'
                                : 'Menampilkan ${mulai + 1} – $akhir dari $totalData pengaduan',
                            style: TextStyle(fontSize: 13, color: context.teksKedua),
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              _pageBtn(
                                '<',
                                false,
                                currentPage > 1 ? () => _loadData(page: currentPage - 1) : null,
                              ),
                              ...List.generate(totalPages.clamp(0, 5), (i) {
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
                                currentPage < totalPages ? () => _loadData(page: currentPage + 1) : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pageBtn(String text, bool aktif, VoidCallback? onTap) {
    final mati = onTap == null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: aktif ? const Color(0xFF0F766E) : (mati ? context.latarLembut : context.latarKartu),
          border: Border.all(color: aktif ? const Color(0xFF0F766E) : context.garis),
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
}
