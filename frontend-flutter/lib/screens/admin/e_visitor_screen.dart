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
import 'data_warga_screen.dart';

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
    final provider = context.read<VisitorProvider>();
    provider.fetchStats();
    provider.fetchVisitors(
      status: _status == 'Semua Status' ? null : _status,
      tipe: _tipe == 'Semua Tipe' ? null : _tipe,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      page: page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisitorProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        _buildStatCards(provider),
        const SizedBox(height: 24),
        _buildActionButtons(),
        const SizedBox(height: 24),
        _buildTableCard(provider),
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
        ],
      ),
    );
  }

  // ------------------------------------------------------------ stat cards

  Widget _buildStatCards(VisitorProvider provider) {
    final stats = provider.stats;
    final w = widget.isWarga;
    final kartu = [
      _statCard(
        w ? 'Tamu Hari Ini' : 'Tamu Hari Ini',
        '${stats['tamu_hari_ini'] ?? 0}',
        w ? 'Tamu Anda hari ini' : 'Kunjungan tercatat',
        Icons.book_outlined,
        const Color(0xFF0D9488),
      ),
      _statCard(
        w ? 'Sedang Di Dalam' : 'Sedang Di Dalam',
        '${stats['sedang_di_dalam'] ?? 0}',
        w ? 'Tamu Anda belum checkout' : 'Belum checkout',
        Icons.door_front_door_outlined,
        const Color(0xFF10B981),
      ),
      _statCard(
        w ? 'Tamu Menginap' : 'Tamu Menginap',
        '${stats['tamu_menginap'] ?? 0}',
        w ? 'Tamu Anda menginap' : 'Sedang menginap',
        Icons.house_outlined,
        const Color(0xFFF59E0B),
      ),
      _statCard(
        w ? 'Total Tamu' : 'Total Semua',
        '${stats['total_semua'] ?? 0}',
        w ? 'Seluruh riwayat tamu Anda' : 'Riwayat lengkap',
        Icons.library_books_outlined,
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
          children: [for (final k in kartu) SizedBox(width: lebar, child: k)],
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
        ElevatedButton.icon(
          onPressed: () => _showFormRegistrasi(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text(
            'Registrasi Tamu',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
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

  Widget _buildTableCard(VisitorProvider provider) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          // Header: Ikon + Judul Daftar Kunjungan / Daftar Tamu Saya (Center)
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Icon(
                  Icons.assignment_rounded,
                  color: Color(0xFF10B981),
                ),
                Text(
                  widget.isWarga ? 'Daftar Tamu Saya' : 'Daftar Kunjungan',
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
                    hintText: 'Cari nama, blok, plat nomor...',
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
                    _status = 'Semua Status';
                    _tipe = 'Semua Tipe';
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

          // Baris 2: Dropdown Filter Status, Tipe (Center)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _dropdownFilter<String>(
                _status,
                const ['Semua Status', 'Di Dalam', 'Checkout']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                (v) {
                  if (v != null) {
                    setState(() => _status = v);
                    _loadData(page: 1);
                  }
                },
                lebar: lebarKolomFilter(context, maksimal: 160),
              ),
              _dropdownFilter<String>(
                _tipe,
                const ['Semua Tipe', 'Kunjungan', 'Menginap']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                    .toList(),
                (v) {
                  if (v != null) {
                    setState(() => _tipe = v);
                    _loadData(page: 1);
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
            child: provider.isLoading && provider.visitors.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : (provider.visitors.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.badge_outlined, size: 40, color: context.garis),
                              const SizedBox(height: 12),
                              Text(
                                'Belum Ada Data Pengunjung',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: context.teksUtama,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Data tamu dan kunjungan warga akan muncul di sini.',
                                style: TextStyle(fontSize: 13, color: context.teksKedua),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
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
                          baris: provider.visitors.asMap().entries.map((entry) {
                            return _buildDataRow(
                              (((provider.currentPage - 1) * provider.perPage) + entry.key + 1),
                              entry.value,
                              context,
                              provider,
                            );
                          }).toList(),
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
      aksi: Transform.translate(
        offset: const Offset(geserAksiTabel, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCheckout)
              _buildActionBtn(
                Icons.logout,
                const Color(0xFF10B981),
                const Color(0xFFD1FAE5),
                () async {
                  await provider.checkoutVisitor(k['id']);
                },
                tooltip: 'Checkout',
              ),
            if (!isCheckout && !widget.isWarga) const SizedBox(width: 6),
            if (!widget.isWarga)
              _buildActionBtn(
                Icons.delete,
                const Color(0xFFEF4444),
                const Color(0xFFFEE2E2),
                () async {
                  final conf = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Hapus'),
                      content: const Text('Yakin hapus data pengunjung ini?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          style: TextButton.styleFrom(
                            foregroundColor: c.warnaTombolTutup,
                          ),
                          child: const Text('Batal'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(c, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Hapus'),
                        ),
                      ],
                    ),
                  );
                  if (conf == true && context.mounted) {
                    await provider.deleteVisitor(k['id']);
                  }
                },
                tooltip: 'Hapus',
              ),
          ],
        ),
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
    final kendaraanLainnyaCtrl = TextEditingController();
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
                  if (jenisKendaraan == 'Jalan Kaki')
                    DropdownButtonFormField<String>(
                      initialValue: jenisKendaraan,
                      decoration: const InputDecoration(labelText: 'Kendaraan *'),
                      items: const [
                        DropdownMenuItem(value: 'Motor', child: Text('Motor')),
                        DropdownMenuItem(value: 'Mobil', child: Text('Mobil')),
                        DropdownMenuItem(value: 'Jalan Kaki', child: Text('Jalan Kaki')),
                        DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
                      ],
                      onChanged: (v) => setState(() => jenisKendaraan = v!),
                    )
                  else
                    _duaKolom(
                      kiri: DropdownButtonFormField<String>(
                        initialValue: jenisKendaraan,
                        decoration: const InputDecoration(labelText: 'Kendaraan *'),
                        items: const [
                          DropdownMenuItem(value: 'Motor', child: Text('Motor')),
                          DropdownMenuItem(value: 'Mobil', child: Text('Mobil')),
                          DropdownMenuItem(value: 'Jalan Kaki', child: Text('Jalan Kaki')),
                          DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
                        ],
                        onChanged: (v) => setState(() => jenisKendaraan = v!),
                      ),
                      kanan: TextField(
                        controller: platCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: jenisKendaraan == 'Lainnya' ? 'Plat Nomor' : 'Plat Nomor *',
                        ),
                      ),
                    ),
                  if (jenisKendaraan == 'Lainnya') ...[
                    const SizedBox(height: AppTheme.spasiL),
                    TextField(
                      controller: kendaraanLainnyaCtrl,
                      decoration: const InputDecoration(labelText: 'Kendaraan Lainnya *'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: ctx.warnaTombolTutup,
              ),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      // Validasi: kolom wajib diisi
                      final kosong = <String>[];
                      if (namaCtrl.text.trim().isEmpty) kosong.add('Nama Tamu');
                      if (noHpCtrl.text.trim().isEmpty) kosong.add('No. HP Tamu');
                      if (blokCtrl.text.trim().isEmpty) kosong.add('Blok Tujuan');
                      if (noHpTujuanCtrl.text.trim().isEmpty) kosong.add('No. HP Warga Tujuan');
                      if (detailCtrl.text.trim().isEmpty) kosong.add('Detail Keperluan');
                      if (jenisKendaraan == 'Lainnya') {
                        if (kendaraanLainnyaCtrl.text.trim().isEmpty) kosong.add('Kendaraan Lainnya');
                      } else if (jenisKendaraan != 'Jalan Kaki') {
                        if (platCtrl.text.trim().isEmpty) kosong.add('Plat Nomor');
                      }

                      if (kosong.isNotEmpty) {
                        pesanGagal(
                          context,
                          'Kolom berikut wajib diisi: ${kosong.join(", ")}',
                        );
                        return;
                      }
                      setState(() => isSaving = true);
                      final kendaraanFinal = jenisKendaraan == 'Lainnya'
                          ? kendaraanLainnyaCtrl.text.trim()
                          : jenisKendaraan;
                      final platFinal = jenisKendaraan == 'Jalan Kaki' ? '-' : platCtrl.text.trim();
                      final success = await context.read<VisitorProvider>().createVisitor(
                        namaTamu: namaCtrl.text.trim(),
                        noHpTamu: noHpCtrl.text.trim(),
                        blokTujuan: blokCtrl.text.trim(),
                        noHpTujuan: noHpTujuanCtrl.text.trim(),
                        tipeKeperluan: tipeKeperluan,
                        detailKeperluan: detailCtrl.text.trim(),
                        platNomor: platFinal,
                        jenisKendaraan: kendaraanFinal,
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
                backgroundColor: const Color(0xFF10B981),
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

  Widget _buildActionBtn(
    IconData icon,
    Color iconColor,
    Color bgColor,
    VoidCallback onTap, {
    String? tooltip,
  }) {
    Widget btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }
}
