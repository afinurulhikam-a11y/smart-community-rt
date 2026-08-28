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

    // Membuka dialog ini BERARTI membacanya — jadi lencananya dipadamkan di
    // sini, bukan lewat tombol "tandai sudah dibaca" yang harus ditekan
    // sendiri. Backend menolak permintaan dari siapa pun selain pemiliknya,
    // jadi pengurus yang membuka aduan warga tidak menghapus lencana warga itu.
    final prov = context.read<ComplaintProvider>();
    if (prov.belumDibaca(c) && c['id'] is int) {
      prov.tandaiTanggapanDibaca(c['id'] as int);
    }

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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: ctx.warnaTombolTutup),
            child: const Text('Tutup'),
          ),
          if (_bolehUbah && c['status']?.toString() != 'Selesai')
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showFormTanggapi(c);
              },
              icon: const Icon(Icons.reply_rounded, size: 16),
              label: const Text('Tanggapi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  /// Dialog bagi pengurus untuk menanggapi pengaduan.
  ///
  /// Menggabungkan dua aksi — ubah status dan isi teks balasan — dalam satu
  /// formulir ringkas sehingga pengurus tidak perlu dua langkah terpisah.
  void _showFormTanggapi(Map<String, dynamic> c) {
    final id = c['id'] as int;
    final currentStatus = c['status']?.toString() ?? 'Menunggu';
    final existingResponse = c['response']?.toString() ?? '';

    // Default status = satu langkah lebih maju dari status saat ini.
    String selectedStatus = currentStatus == 'Menunggu' ? 'Diproses' : currentStatus;
    final tanggapanCtrl = TextEditingController(text: existingResponse);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tanggapi Pengaduan',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                c['judul']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: context.teksKedua,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Ubah Status',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: ['Diproses', 'Selesai', 'Ditolak']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setLocal(() => selectedStatus = v ?? selectedStatus),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tanggapanCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Teks Tanggapan',
                      alignLabelWithHint: true,
                      hintText: 'Jelaskan tindak lanjut atau respons terhadap pengaduan ini...',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: ctx.warnaTombolTutup),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final tanggapan = tanggapanCtrl.text.trim();
                Navigator.pop(ctx);
                final prov = context.read<ComplaintProvider>();
                final ok = await prov.updateComplaintStatus(
                  id,
                  status: selectedStatus,
                  response: tanggapan.isNotEmpty ? tanggapan : null,
                );
                _pesan(
                  ok
                      ? 'Tanggapan berhasil disimpan.'
                      : (prov.errorMessage ?? 'Gagal menyimpan tanggapan.'),
                  sukses: ok,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Simpan Tanggapan'),
            ),
          ],
        ),
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
            TextButton(
              onPressed: () => Navigator.pop(c),
              style: TextButton.styleFrom(foregroundColor: c.warnaTombolTutup),
              child: const Text('Batal'),
            ),
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

  Widget _buildStatCards(ComplaintProvider provider) {
    final s = provider.stats;
    final total = s['total'] ?? 0;
    final pending = s['pending'] ?? 0;
    final diproses = s['diproses'] ?? 0;
    final selesai = s['selesai'] ?? 0;

    final kartu = [
      _statCard(
        'Total Pengaduan',
        '$total',
        'semua tiket',
        Icons.list_alt_rounded,
        const Color(0xFF0F766E),
      ),
      _statCard(
        'Status Menunggu',
        '$pending',
        'belum diproses',
        Icons.hourglass_empty_rounded,
        Colors.orange,
      ),
      _statCard(
        'Status Diproses',
        '$diproses',
        'sedang ditangani',
        Icons.sync_rounded,
        Colors.blue,
      ),
      _statCard(
        'Status Selesai',
        '$selesai',
        'telah ditindaklanjuti',
        Icons.check_circle_outline,
        const Color(0xFF166534),
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

  Widget _buildActionButtons() {
    if (!_bolehTambah) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: _showFormPengaduan,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Buat Pengaduan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ],
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

    final provider = context.watch<ComplaintProvider>();

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
                  Icons.error_outline_rounded,
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

        const SizedBox(height: 16),
        _buildStatCards(provider),
        if (_bolehTambah) ...[
          const SizedBox(height: 16),
          _buildActionButtons(),
        ],
        const SizedBox(height: 16),
        _buildTableCard(provider),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTableCard(ComplaintProvider provider) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          // Header: Ikon + Judul Semua Pengaduan (Center)
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFF0F766E),
                ),
                Text(
                  'Semua Pengaduan',
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
                    _loadData();
                  },
                  decoration: InputDecoration(
                    hintText: 'Cari judul pengaduan...',
                    hintStyle: TextStyle(fontSize: 12, color: context.teksTersier),
                    prefixIcon: Icon(Icons.search, size: 18, color: context.teksKedua),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      tooltip: 'Cari',
                      onPressed: () => _loadData(),
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
                      borderSide: const BorderSide(color: Color(0xFF0F766E)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _status = 'Semua Status');
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

          // Baris 2: Filter Status (Center)
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  'Status:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.teksKedua,
                  ),
                ),
                SizedBox(
                  width: lebarKolomFilter(context, maksimal: 180),
                  height: AppTheme.sasaranSentuh,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.garis),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _status,
                        isExpanded: true,
                        icon: Icon(Icons.keyboard_arrow_down, size: 16, color: context.teksKedua),
                        style: TextStyle(fontSize: 13, color: context.teksUtama),
                        items: ['Semua Status', 'Menunggu', 'Diproses', 'Selesai'].map((String val) {
                          return DropdownMenuItem<String>(value: val, child: Text(val));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _status = val);
                            _loadData();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Table Content
          if (provider.isLoading && provider.complaints.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF0F766E))),
            )
          else if (provider.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else if (provider.complaints.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'Tidak ada data pengaduan.',
                  style: TextStyle(color: context.teksKedua),
                ),
              ),
            )
          else
            Padding(
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
                  final idx = entry.key + 1 + ((provider.currentPage - 1) * 25);
                  final c = entry.value;
                  final id = c['id'];
                  final tiket = c['kode_tiket']?.toString() ?? 'TKT${id.toString().padLeft(6, '0')}';
                  final pengirim = c['nama_pengirim']?.toString() ?? '-';
                  final judul = c['judul'] ?? '-';
                  final kategori = c['kategori'] ?? '-';
                  final status = c['status'] ?? 'Menunggu';
                  final createdAt = DateTime.tryParse(c['created_at'] ?? '') ?? DateTime.now();
                  final dateStr = DateFormat('dd/MM/yyyy').format(createdAt);

                  Color statusColor = Colors.orange;
                  Color statusBgColor = Colors.orange.shade50;
                  if (status == 'Diproses') {
                    statusColor = Colors.blue;
                    statusBgColor = Colors.blue.shade50;
                  } else if (status == 'Selesai') {
                    statusColor = const Color(0xFF166534);
                    statusBgColor = const Color(0xFFDCFCE7);
                  } else if (status == 'Ditolak') {
                    statusColor = const Color(0xFFB91C1C);
                    statusBgColor = const Color(0xFFFEE2E2);
                  }

                  return BarisTabel(
                    onTap: () => _showDetail(c),
                    sel: [
                      SelTabel(
                        'NO',
                        Text(
                          '$idx',
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
                      SelTabel(
                        'JUDUL',
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                judul,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (context.read<ComplaintProvider>().belumDibaca(c)) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F766E),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Baru',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        utama: true,
                      ),
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
                          if (status != 'Selesai' && _bolehUbah)
                            IconButton(
                              tooltip: 'Tanggapi',
                              icon: const Icon(
                                Icons.reply_rounded,
                                size: 20,
                                color: Color(0xFF8B5CF6),
                              ),
                              style: gayaAksiTabel(const Color(0xFF8B5CF6)),
                              onPressed: () => _showFormTanggapi(c),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                currentPage: provider.currentPage,
                totalPages: provider.totalPages,
                totalData: provider.totalData,
                perPage: 25,
                onPageChanged: (page) => _loadData(page: page),
              ),
            ),
        ],
      ),
    );
  }
}
