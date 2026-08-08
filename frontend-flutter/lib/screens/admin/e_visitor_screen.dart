import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../providers/visitor_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

class EVisitorScreen extends StatefulWidget {
  final bool isWarga;
  final VoidCallback? onBack;
  const EVisitorScreen({super.key, this.isWarga = false, this.onBack});

  @override
  State<EVisitorScreen> createState() => _EVisitorScreenState();
}

class _EVisitorScreenState extends State<EVisitorScreen> {
  String _searchQuery = '';
  String _status = 'Semua Status';
  String _tipe = 'Semua Tipe';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final provider = context.read<VisitorProvider>();
    provider.fetchStats();
    provider.fetchVisitors(
      status: _status == 'Semua Status' ? null : _status,
      tipe: _tipe == 'Semua Tipe' ? null : _tipe,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        SizedBox(
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
                        color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.badge_outlined, color: Color(0xFF1B7A6A), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.isWarga ? 'Layanan Warga / Buku Tamu Saya' : 'Layanan Warga / E-Visitor',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
              ElevatedButton.icon(
                onPressed: () => _showFormRegistrasi(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Registrasi Tamu',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Stat Cards
        Consumer<VisitorProvider>(
          builder: (context, provider, _) {
            final stats = provider.stats;
            // Jumlah kolom mengikuti lebar layar. Dipaksa empat sejajar, tiap
            // kartu hanya kebagian ~75px di ponsel dan isinya meluber.
            return LayoutBuilder(
              builder: (context, c) {
                final kolom = c.maxWidth > 900 ? 4 : (c.maxWidth > 500 ? 2 : 1);
                final lebar = (c.maxWidth - (12 * (kolom - 1))) / kolom;
                final w = widget.isWarga;
                final kartu = [
                  _buildStatCard(
                    w ? 'TAMU SAYA HARI INI' : 'TAMU HARI INI',
                    '${stats['tamu_hari_ini']}',
                    w ? 'Tamu Anda hari ini' : 'Kunjungan tercatat',
                    Icons.book,
                    const [Color(0xFF0D9488), Color(0xFF14B8A6)],
                  ),
                  _buildStatCard(
                    w ? 'TAMU SAYA DI DALAM' : 'SEDANG DI DALAM',
                    '${stats['sedang_di_dalam']}',
                    w ? 'Tamu Anda belum checkout' : 'Belum checkout',
                    Icons.door_front_door_outlined,
                    const [Color(0xFF059669), Color(0xFF34D399)],
                  ),
                  _buildStatCard(
                    w ? 'TAMU SAYA MENGINAP' : 'TAMU MENGINAP',
                    '${stats['tamu_menginap']}',
                    w ? 'Tamu Anda menginap' : 'Sedang menginap',
                    Icons.house_outlined,
                    const [Color(0xFFD97706), Color(0xFFF59E0B)],
                  ),
                  _buildStatCard(
                    w ? 'TOTAL TAMU SAYA' : 'TOTAL SEMUA',
                    '${stats['total_semua']}',
                    w ? 'Seluruh riwayat tamu Anda' : 'Riwayat lengkap',
                    Icons.library_books,
                    const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (final k in kartu) SizedBox(width: lebar, child: k)],
                );
              },
            );
          },
        ),

        const SizedBox(height: 24),

        // Filter Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.garis),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_alt, size: 18, color: Color(0xFF10B981)),
                  SizedBox(width: 4),
                  Text(
                    'Filter',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              // Bukan Expanded: induknya Wrap, dan Expanded hanya sah di Flex.
              SizedBox(
                width: lebarKolomFilter(context, maksimal: 240),
                child: Container(
                  constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.garis),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    onSubmitted: (_) => _loadData(),
                    decoration: InputDecoration(
                      hintText: 'Cari nama, blok, plat nomor...',
                      hintStyle: TextStyle(fontSize: 13, color: context.teksTersier),
                      prefixIcon: Icon(Icons.search, size: 18, color: context.teksTersier),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              // Tanpa SizedBox pemisah di antaranya: Wrap sudah mengatur jarak
              // lewat `spacing`, dan menyisipkan SizedBox sebagai ANAK Wrap
              // membuatnya diperlakukan sebagai satu unsur tersendiri — jaraknya
              // jadi berganda dan tidak rata.
              _buildDropdown(_status, ['Semua Status', 'Di Dalam', 'Checkout'], (v) {
                setState(() => _status = v!);
                _loadData();
              }),
              _buildDropdown(_tipe, ['Semua Tipe', 'Kunjungan', 'Menginap'], (v) {
                setState(() => _tipe = v!);
                _loadData();
              }),
              TextButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(foregroundColor: context.teksKedua),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Data Table
        Consumer<VisitorProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(
                child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
              );
            }

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
                              Icon(Icons.assignment, color: Color(0xFF10B981), size: 18),
                              SizedBox(width: 8),
                              // Flexible + ellipsis: judul ini meluber begitu
                              // pengguna memperbesar font sistem Android.
                              Flexible(
                                child: Text(
                                  widget.isWarga ? 'Daftar Tamu Saya' : 'Daftar Kunjungan',
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
                            '${provider.visitors.length} data',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  Padding(
                    padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                    child: TabelResponsif(
                      labelAksi: 'MANAJEMEN CHECK',
                      kolom: const [
                        'NO',
                        'JAM / TGL',
                        'IDENTITAS TAMU',
                        'TUJUAN',
                        'KEPERLUAN',
                        'KENDARAAN',
                        'STATUS',
                      ],
                      kosong: const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: Text('Tidak ada data pengunjung')),
                      ),
                      baris: provider.visitors.asMap().entries.map((entry) {
                        return _buildDataRow(entry.key + 1, entry.value, context, provider);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  BarisTabel _buildDataRow(
    int index,
    Map<String, dynamic> k,
    BuildContext context,
    VisitorProvider provider,
  ) {
    final status = k['status'] ?? 'Di Dalam';
    final isCheckout = status == 'Checkout';

    final jamMasuk = k['jam_masuk']?.substring(0, 5) ?? '-';
    final jamKeluar = k['jam_keluar']?.substring(0, 5) ?? '-';
    final dateStr = k['created_at'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(k['created_at']))
        : '-';

    return BarisTabel(
      sel: [
        SelTabel.teks('NO', index.toString(), sembunyiDiKartu: true),
        SelTabel(
          'JAM / TGL',
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.login, size: 12, color: Color(0xFF10B981)),
                  const SizedBox(width: 4),
                  Text(
                    jamMasuk,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              if (isCheckout)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 12, color: Color(0xFFEF4444)),
                    const SizedBox(width: 4),
                    Text(
                      jamKeluar,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 2),
              Text(dateStr, style: TextStyle(fontSize: 11, color: context.teksTersier)),
            ],
          ),
        ),
        SelTabel(
          'IDENTITAS TAMU',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                decoration: const BoxDecoration(color: Color(0xFFE0F2FE), shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    k['nama_tamu'].toString().substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      k['nama_tamu'] ?? '-',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.teksUtama,
                      ),
                    ),
                    if (k['no_hp_tamu'] != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble, size: 10, color: Color(0xFF10B981)),
                          const SizedBox(width: 2),
                          Text(
                            k['no_hp_tamu'],
                            style: TextStyle(fontSize: 11, color: context.teksTersier),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          utama: true,
        ),
        SelTabel(
          'TUJUAN',
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on, size: 12, color: Color(0xFF10B981)),
                  const SizedBox(width: 4),
                  Text(
                    k['blok_tujuan'] ?? '-',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: context.teksUtama,
                    ),
                  ),
                ],
              ),
              if (k['no_hp_tujuan'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'WA. ${k['no_hp_tujuan']}',
                    style: TextStyle(fontSize: 11, color: context.teksTersier),
                  ),
                ),
            ],
          ),
        ),
        SelTabel(
          'KEPERLUAN',
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge, size: 12, color: Color(0xFF10B981)),
                  const SizedBox(width: 4),
                  Text(
                    k['tipe_keperluan'] ?? '-',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                k['detail_keperluan'] ?? '-',
                style: TextStyle(fontSize: 11, color: context.teksKedua),
              ),
            ],
          ),
        ),
        SelTabel(
          'KENDARAAN',
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                k['plat_nomor'] ?? '-',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.teksUtama,
                ),
              ),
              Text(
                k['jenis_kendaraan'] ?? '-',
                style: TextStyle(fontSize: 11, color: context.teksTersier),
              ),
            ],
          ),
        ),
        SelTabel(
          'STATUS',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCheckout ? Icons.check_circle : Icons.timer,
                size: 14,
                color: isCheckout ? const Color(0xFF10B981) : const Color(0xFFD97706),
              ),
              const SizedBox(width: 4),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  color: isCheckout ? const Color(0xFF10B981) : const Color(0xFFD97706),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
      aksi: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCheckout)
            ElevatedButton(
              onPressed: () async {
                await provider.checkoutVisitor(k['id']);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Checkout', style: TextStyle(fontSize: 11)),
            ),
          if (!isCheckout && !widget.isWarga) const SizedBox(width: 4),
          if (!widget.isWarga)
            _buildActionBtn(Icons.delete, const Color(0xFFEF4444), const Color(0xFFFEE2E2), () async {
              final conf = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Hapus'),
                  content: const Text('Yakin hapus data pengunjung ini?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (conf == true && context.mounted) {
                await provider.deleteVisitor(k['id']);
              }
            }),
        ],
      ),
    );
  }

  /// Dua kolom isian: berdampingan di layar lebar, bertumpuk di ponsel.
  ///
  /// Di dalam dialog selebar ~312px, dua kolom berdampingan hanya menyisakan
  /// ~150px masing-masing — cukup untuk memotong label seperti
  /// "No. HP Warga Tujuan" di tengah kata.
  Widget _duaKolom({required Widget kiri, required Widget kanan}) {
    if (pakaiKartu(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [kiri, const SizedBox(height: AppTheme.spasiL), kanan],
      );
    }
    return Row(
      children: [
        Expanded(child: kiri),
        const SizedBox(width: AppTheme.spasiM),
        Expanded(child: kanan),
      ],
    );
  }

  void _showFormRegistrasi() {
    final namaCtrl = TextEditingController();
    final noHpCtrl = TextEditingController();
    final blokCtrl = TextEditingController();
    final noHpTujuanCtrl = TextEditingController();
    final detailCtrl = TextEditingController();
    final platCtrl = TextEditingController();
    String tipeKeperluan = 'Kunjungan';
    String jenisKendaraan = 'Motor';
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text(
            'Registrasi Tamu Baru',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: lebarDialog(context, maksimal: 400),
              // Setiap kolom isian dipisahkan jarak yang sama, dan dropdown
              // memakai DropdownButtonFormField supaya ikut berbingkai seperti
              // kolom lain. Sebelumnya kolomnya menempel tanpa jarak dan
              // dropdown-nya polos berlabel abu-abu kecil, sehingga formulir
              // terlihat seperti tumpukan unsur yang tidak sepadan.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: namaCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Tamu *'),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  TextField(
                    controller: noHpCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'No. HP Tamu *'),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  _duaKolom(
                    kiri: TextField(
                      controller: blokCtrl,
                      decoration: const InputDecoration(labelText: 'Blok Tujuan *'),
                    ),
                    kanan: TextField(
                      controller: noHpTujuanCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'No. HP Warga Tujuan *'),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  DropdownButtonFormField<String>(
                    initialValue: tipeKeperluan,
                    decoration: const InputDecoration(labelText: 'Tipe Keperluan *'),
                    items: const [
                      DropdownMenuItem(value: 'Kunjungan', child: Text('Kunjungan')),
                      DropdownMenuItem(value: 'Menginap', child: Text('Menginap')),
                    ],
                    onChanged: (v) => setState(() => tipeKeperluan = v!),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  TextField(
                    controller: detailCtrl,
                    decoration: const InputDecoration(labelText: 'Detail Keperluan *'),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  _duaKolom(
                    kiri: DropdownButtonFormField<String>(
                      initialValue: jenisKendaraan,
                      decoration: const InputDecoration(labelText: 'Kendaraan *'),
                      items: const [
                        DropdownMenuItem(value: 'Motor', child: Text('Motor')),
                        DropdownMenuItem(value: 'Mobil', child: Text('Mobil')),
                        DropdownMenuItem(value: 'Jalan Kaki', child: Text('Jalan Kaki')),
                      ],
                      onChanged: (v) => setState(() => jenisKendaraan = v!),
                    ),
                    kanan: TextField(
                      controller: platCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Plat Nomor *'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Batal', style: TextStyle(color: context.teksKedua)),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      // Validasi: semua kolom wajib diisi
                      final kosong = <String>[];
                      if (namaCtrl.text.trim().isEmpty) kosong.add('Nama Tamu');
                      if (noHpCtrl.text.trim().isEmpty) kosong.add('No. HP Tamu');
                      if (blokCtrl.text.trim().isEmpty) kosong.add('Blok Tujuan');
                      if (noHpTujuanCtrl.text.trim().isEmpty) kosong.add('No. HP Warga Tujuan');
                      if (detailCtrl.text.trim().isEmpty) kosong.add('Detail Keperluan');
                      if (platCtrl.text.trim().isEmpty) kosong.add('Plat Nomor');

                      if (kosong.isNotEmpty) {
                        pesanGagal(
                          context,
                          'Kolom berikut wajib diisi: ${kosong.join(", ")}',
                        );
                        return;
                      }
                      setState(() => isSaving = true);
                      final success = await context.read<VisitorProvider>().createVisitor(
                        namaTamu: namaCtrl.text.trim(),
                        noHpTamu: noHpCtrl.text.trim(),
                        blokTujuan: blokCtrl.text.trim(),
                        noHpTujuan: noHpTujuanCtrl.text.trim(),
                        tipeKeperluan: tipeKeperluan,
                        detailKeperluan: detailCtrl.text.trim(),
                        platNomor: platCtrl.text.trim(),
                        jenisKendaraan: jenisKendaraan,
                      );
                      setState(() => isSaving = false);
                      if (success) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          pesanSukses(context, 'Tamu berhasil didaftarkan');
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String value, List<String> items, Function(String?) onChanged) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.garis),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: context.teksKedua),
          style: TextStyle(fontSize: 13, color: context.teksUtama),
          items: items.map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    String subtitle,
    IconData icon,
    List<Color> colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
      ),
      // Tetap Row, bukan Wrap: Expanded hanya sah di dalam Flex, dan di sini
      // ia justru yang membuat teks menyusut mengikuti lebar kartu.
      child: SizedBox(
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.crop_square, color: Colors.white.withValues(alpha: 0.7), size: 10),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, Color iconColor, Color bgColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }
}
