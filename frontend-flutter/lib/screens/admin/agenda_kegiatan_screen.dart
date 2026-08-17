import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

/// Kode modul di tabel izin. Bendahara dan warga hanya punya `view`.
const String _kodeIzin = 'kegiatan.agenda';

class AgendaKegiatanScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AgendaKegiatanScreen({super.key, this.onBack});

  @override
  State<AgendaKegiatanScreen> createState() => _AgendaKegiatanScreenState();
}

class _AgendaKegiatanScreenState extends State<AgendaKegiatanScreen> {
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  int _selectedTabIndex = 0;

  List<String> get _tabs => const ['Semua Agenda', 'Akan Datang', 'Selesai'];

  /// Kotak pilihan yang tampil seperti kolom isian.
  ///
  /// `InputDecorator` memakai `inputDecorationTheme` yang sama dengan
  /// `TextFormField`, jadi bingkai, warna, dan tinggi minimumnya otomatis
  /// selaras — termasuk saat mode gelap dinyalakan.
  Widget _kotakPilih({
    required IconData ikon,
    required String label,
    required String nilai,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.borderRadiusM,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(ikon)),
        child: Text(nilai, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  /// Baris tab.
  ///
  /// Di layar lebar ketiganya berbagi lebar sama rata lewat `Expanded`. Di
  /// ponsel itu memberi tiap tab hanya ~78px, sehingga di layar sempit barisnya
  /// digeser mendatar dan tiap label memakai lebarnya sendiri.
  Widget _barisTab() {
    final sempit = pakaiKartu(context);

    Widget tab(int idx, String teks) {
      final terpilih = _selectedTabIndex == idx;
      return GestureDetector(
        onTap: () {
          setState(() => _selectedTabIndex = idx);
          _loadData();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
          padding: EdgeInsets.symmetric(horizontal: sempit ? AppTheme.spasiL : 0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: terpilih ? const Color(0xFF3B82F6) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            teks,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: terpilih ? const Color(0xFF3B82F6) : context.teksTersier,
            ),
          ),
        ),
      );
    }

    final daftar = _tabs.asMap().entries.toList();

    if (sempit) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (final e in daftar) tab(e.key, e.value)]),
      );
    }
    return Row(
      children: [for (final e in daftar) Expanded(child: tab(e.key, e.value))],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData({int page = 1}) {
    final provider = context.read<AgendaProvider>();
    String? statusFilter;
    if (_selectedTabIndex == 1) statusFilter = 'Akan Datang';
    if (_selectedTabIndex == 2) statusFilter = 'Selesai';
    provider.fetchAgenda(status: statusFilter, page: page);
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
            spacing: 12,
            runSpacing: 12,
            children: [
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
                    child: const Icon(Icons.event_outlined, color: Color(0xFF1B7A6A), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Kegiatan & Info / Agenda Kegiatan',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.teksKedua,
                      ),
                    ),
                  ),
                ],
              ),
              if (_bolehTambah)
                ElevatedButton.icon(
                  onPressed: () {
                    _showAddAgendaDialog();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Buat Agenda'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Custom Tabs
        Container(
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: AppTheme.borderRadiusM,
            border: Border.all(color: context.garis),
          ),
          child: _barisTab(),
        ),

        const SizedBox(height: 16),

        // Content
        Consumer<AgendaProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && provider.agendaList.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (provider.errorMessage != null) {
              return Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(provider.errorMessage!, style: const TextStyle(color: Colors.red)),
                ),
              );
            }

            if (provider.agendaList.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy_rounded, size: 64, color: context.garis),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada agenda',
                        style: TextStyle(color: context.teksTersier, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: provider.agendaList.length,
                  itemBuilder: (context, index) {
                    final event = provider.agendaList[index];
                    return _buildEventCard(event);
                  },
                ),
                _buildAgendaPagination(provider),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAgendaPagination(AgendaProvider provider) {
    if (provider.agendaList.isEmpty) return const SizedBox.shrink();
    final totalData = provider.totalData;
    final currentPage = provider.currentPage;
    final totalPages = provider.totalPages;
    final mulai = (currentPage - 1) * 25;
    final akhir = (mulai + provider.agendaList.length).clamp(0, totalData);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Text(
            totalData == 0
                ? 'Tidak ada data'
                : 'Menampilkan ${mulai + 1} – $akhir dari $totalData agenda',
            style: TextStyle(fontSize: 13, color: context.teksKedua),
          ),
          Wrap(
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

  // ========================= AGENDA =========================

  Widget _buildEventCard(Map<String, dynamic> event) {
    final tipe = event['tipe'] ?? 'Kegiatan';

    // Agenda bertipe "Pengumuman" tampil dengan card bergaya pengumuman.
    if (tipe == 'Pengumuman') {
      return _buildKartuAgendaPengumuman(event);
    }

    final status = event['status'] ?? 'Akan Datang';
    final isUpcoming = status == 'Akan Datang';
    final isRapat = tipe == 'Rapat';

    final rawDate = event['tanggal']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(rawDate);
    final dayStr = parsedDate != null
        ? parsedDate.day.toString().padLeft(2, '0')
        : (rawDate.isNotEmpty ? rawDate.split('-').last.substring(0, 2) : '-');

    final timeStr =
        '${event['waktu_mulai']?.substring(0, 5) ?? '00:00'} - ${event['waktu_selesai']?.substring(0, 5) ?? 'Selesai'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Box
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isUpcoming ? const Color(0xFFEFF6FF) : context.latarLembut,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUpcoming ? const Color(0xFFBFDBFE) : context.garis,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayStr,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        color: isUpcoming ? const Color(0xFF1D4ED8) : context.teksKedua,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getMonthName(rawDate),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                        color: isUpcoming ? const Color(0xFF3B82F6) : context.teksTersier,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isRapat ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isRapat
                                    ? const Color(0xFFFECACA)
                                    : const Color(0xFFBBF7D0),
                              ),
                            ),
                            child: Text(
                              tipe,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isRapat
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF16A34A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isUpcoming
                                  ? const Color(0xFFFFFBEB)
                                  : context.latarLembut,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isUpcoming
                                    ? const Color(0xFFD97706)
                                    : context.teksKedua,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (_bolehUbah && isUpcoming)
                        Tooltip(
                          message: 'Tandai Selesai',
                          child: InkWell(
                            onTap: () async {
                              final conf = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Tandai Selesai?'),
                                  content: Text(
                                    'Tandai "${event['judul']}" sebagai sudah selesai?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Batal'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Tandai Selesai'),
                                    ),
                                  ],
                                ),
                              );
                              if (conf == true && mounted) {
                                await context.read<AgendaProvider>().updateAgenda(
                                  event['id'],
                                  {'status': 'Selesai'},
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF6EE7B7)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded, size: 14, color: Color(0xFF059669)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Selesai',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_bolehUbah)
                        IconButton(
                          tooltip: 'Ubah',
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B82F6)),
                          onPressed: () => _showEditAgendaDialog(event),
                        ),
                      if (_bolehHapus)
                        IconButton(
                          tooltip: 'Hapus',
                          icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                          onPressed: () async {
                            final conf = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Hapus'),
                                content: const Text('Yakin ingin menghapus agenda ini?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Batal'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text(
                                      'Hapus',
                                      style: TextStyle(color: Color(0xFFEF4444)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (conf == true && mounted) {
                              await context.read<AgendaProvider>().deleteAgenda(event['id']);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    event['judul'] ?? '-',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.teksUtama,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 16, color: context.teksTersier),
                      const SizedBox(width: 6),
                      Text(timeStr, style: TextStyle(color: context.teksKedua, fontSize: 13)),
                      const SizedBox(width: 16),
                      Icon(Icons.location_on_outlined, size: 16, color: context.teksTersier),
                      const SizedBox(width: 6),
                      Text(
                        event['lokasi'] ?? '-',
                        style: TextStyle(color: context.teksKedua, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    event['deskripsi'] ?? '-',
                    style: TextStyle(color: context.teksKedua, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Card bergaya pengumuman untuk agenda dengan tipe "Pengumuman".
  ///
  /// Mengadaptasi desain `_buildKartuPengumuman()` yang lama ke field agenda:
  /// - Badge kategori → badge tetap biru "Pengumuman"
  /// - Isi konten → dari `deskripsi` agenda
  /// - Tanggal → dari `tanggal` agenda
  /// - Edit/hapus → memakai izin agenda (`bolehUbah` / `bolehHapus`)
  Widget _buildKartuAgendaPengumuman(Map<String, dynamic> event) {
    final judul = event['judul']?.toString() ?? '-';
    final deskripsi = event['deskripsi']?.toString() ?? '';
    final rawDate = event['tanggal']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(rawDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pengumuman',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
              const Spacer(),
              if (_bolehUbah)
                IconButton(
                  tooltip: 'Ubah',
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B82F6)),
                  onPressed: () => _showEditAgendaDialog(event),
                ),
              if (_bolehHapus)
                IconButton(
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                  onPressed: () async {
                    final conf = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Hapus Pengumuman'),
                        content: Text('Hapus "$judul"? Tindakan ini tidak bisa dibatalkan.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Batal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text(
                              'Hapus',
                              style: TextStyle(color: Color(0xFFEF4444)),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (conf == true && mounted) {
                      await context.read<AgendaProvider>().deleteAgenda(event['id']);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            judul,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.teksUtama,
            ),
          ),
          if (deskripsi.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(deskripsi, style: TextStyle(fontSize: 13, height: 1.5, color: context.teksKedua)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (parsedDate != null) ...[
                Icon(Icons.schedule, size: 13, color: context.teksTersier),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd MMM yyyy', 'id_ID').format(parsedDate),
                  style: TextStyle(fontSize: 11, color: context.teksTersier),
                ),
              ],
              if (event['lokasi'] != null && event['lokasi'].toString().isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.location_on_outlined, size: 13, color: context.teksTersier),
                const SizedBox(width: 4),
                Text(
                  event['lokasi'].toString(),
                  style: TextStyle(fontSize: 11, color: context.teksTersier),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showAddAgendaDialog() {
    final judulController = TextEditingController();
    final lokasiController = TextEditingController();
    final deskripsiController = TextEditingController();
    final tipeNotifier = ValueNotifier<String>('Kegiatan');
    DateTime selectedDate = DateTime.now();
    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Buat Agenda Baru'),
          content: SizedBox(
            width: lebarDialog(context),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: judulController,
                    decoration: const InputDecoration(
                      labelText: 'Judul Agenda *',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  ValueListenableBuilder<String>(
                    valueListenable: tipeNotifier,
                    builder: (_, tipe, __) => DropdownButtonFormField<String>(
                      initialValue: tipe,
                      decoration: const InputDecoration(
                        labelText: 'Tipe',
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Kegiatan', child: Text('Kegiatan')),
                        DropdownMenuItem(value: 'Rapat', child: Text('Rapat')),
                        DropdownMenuItem(value: 'Pengumuman', child: Text('Pengumuman / Info')),
                      ],
                      onChanged: (v) => tipeNotifier.value = v!,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  // Tanggal dan waktu memakai bingkai yang sama dengan kolom
                  // isian di atasnya. Sebagai ListTile polos keduanya terlihat
                  // seperti tautan yang tercecer, bukan bagian dari formulir.
                  _kotakPilih(
                    ikon: Icons.calendar_today,
                    label: 'Tanggal',
                    nilai: DateFormat('d MMMM yyyy', 'id_ID').format(selectedDate),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  _kotakPilih(
                    ikon: Icons.access_time,
                    label: 'Waktu',
                    nilai: '${startTime.format(ctx)} - ${endTime.format(ctx)}',
                    onTap: () async {
                      final pickedStart = await showTimePicker(context: ctx, initialTime: startTime);
                      if (pickedStart == null) return;
                      setDialogState(() => startTime = pickedStart);
                      if (!ctx.mounted) return;
                      final pickedEnd = await showTimePicker(context: ctx, initialTime: endTime);
                      if (pickedEnd != null) setDialogState(() => endTime = pickedEnd);
                    },
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  TextFormField(
                    controller: lokasiController,
                    decoration: const InputDecoration(
                      labelText: 'Lokasi',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  TextFormField(
                    controller: deskripsiController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Deskripsi',
                      prefixIcon: Icon(Icons.description),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final judul = judulController.text.trim();
                if (judul.isEmpty) {
                  pesanGagal(context, 'Judul agenda tidak boleh kosong');
                  return;
                }
                final formattedDate =
                    '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                final formattedStart =
                    '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
                final formattedEnd =
                    '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

                final provider = context.read<AgendaProvider>();
                final success = await provider.createAgenda(
                  judul: judul,
                  tanggal: formattedDate,
                  deskripsi: deskripsiController.text.trim(),
                  tipe: tipeNotifier.value,
                  waktuMulai: formattedStart,
                  waktuSelesai: formattedEnd,
                  lokasi: lokasiController.text.trim(),
                );

                if (!ctx.mounted) return;
                if (success) {
                  Navigator.pop(ctx);
                  if (mounted) {
                    pesanSukses(context, 'Agenda berhasil dibuat!');
                  }
                } else {
                  if (mounted) {
                    pesanGagal(context, provider.errorMessage ?? 'Gagal membuat agenda');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAgendaDialog(Map<String, dynamic> event) {
    final judulController = TextEditingController(text: event['judul'] ?? '');
    final lokasiController = TextEditingController(text: event['lokasi'] ?? '');
    final deskripsiController = TextEditingController(text: event['deskripsi'] ?? '');
    final tipeNotifier = ValueNotifier<String>(event['tipe'] ?? 'Kegiatan');
    final statusNotifier = ValueNotifier<String>(event['status'] ?? 'Akan Datang');

    DateTime selectedDate = DateTime.tryParse(event['tanggal'] ?? '') ?? DateTime.now();

    TimeOfDay parseTime(String? timeStr) {
      if (timeStr == null || !timeStr.contains(':')) return const TimeOfDay(hour: 8, minute: 0);
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts[1]) ?? 0);
    }

    TimeOfDay startTime = parseTime(event['waktu_mulai']);
    TimeOfDay endTime = parseTime(event['waktu_selesai']);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Agenda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: judulController,
                  decoration: const InputDecoration(
                    labelText: 'Judul Agenda *',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: tipeNotifier,
                  builder: (_, tipe, __) => DropdownButtonFormField<String>(
                    initialValue: tipe,
                    decoration: const InputDecoration(
                      labelText: 'Tipe',
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Kegiatan', child: Text('Kegiatan')),
                      DropdownMenuItem(value: 'Rapat', child: Text('Rapat')),
                      DropdownMenuItem(value: 'Pengumuman', child: Text('Pengumuman / Info')),
                    ],
                    onChanged: (v) => tipeNotifier.value = v!,
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (_, status, __) => DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.check_circle_outline),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Akan Datang', child: Text('Akan Datang')),
                      DropdownMenuItem(value: 'Selesai', child: Text('Selesai')),
                      DropdownMenuItem(value: 'Batal', child: Text('Batal')),
                    ],
                    onChanged: (v) => statusNotifier.value = v!,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(
                    'Tanggal: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setDialogState(() => selectedDate = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: Text('Waktu: ${startTime.format(ctx)} - ${endTime.format(ctx)}'),
                  onTap: () async {
                    final pickedStart = await showTimePicker(context: ctx, initialTime: startTime);
                    if (pickedStart != null) {
                      setDialogState(() => startTime = pickedStart);
                      if (!ctx.mounted) return;
                      final pickedEnd = await showTimePicker(context: ctx, initialTime: endTime);
                      if (pickedEnd != null) setDialogState(() => endTime = pickedEnd);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: lokasiController,
                  decoration: const InputDecoration(
                    labelText: 'Lokasi',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: deskripsiController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi',
                    prefixIcon: Icon(Icons.description),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final judul = judulController.text.trim();
                if (judul.isEmpty) {
                  pesanGagal(context, 'Judul agenda tidak boleh kosong');
                  return;
                }
                final formattedDate =
                    '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                final formattedStart =
                    '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
                final formattedEnd =
                    '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

                final provider = context.read<AgendaProvider>();
                final success = await provider.updateAgenda(event['id'], {
                  'judul': judul,
                  'tanggal': formattedDate,
                  'deskripsi': deskripsiController.text.trim(),
                  'tipe': tipeNotifier.value,
                  'status': statusNotifier.value,
                  'waktu_mulai': formattedStart,
                  'waktu_selesai': formattedEnd,
                  'lokasi': lokasiController.text.trim(),
                });

                if (!ctx.mounted) return;
                if (success) {
                  Navigator.pop(ctx);
                  if (mounted) {
                    pesanSukses(context, 'Agenda berhasil diubah!');
                  }
                } else {
                  if (mounted) {
                    pesanGagal(context, provider.errorMessage ?? 'Gagal memperbarui agenda');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              child: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(String date) {
    if (date.isEmpty) return '';
    final dt = DateTime.tryParse(date);
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ags',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    if (dt != null && dt.month >= 1 && dt.month <= 12) {
      return months[dt.month];
    }
    final parts = date.split('-');
    if (parts.length >= 2) {
      final intMonth = int.tryParse(parts[1]) ?? 0;
      if (intMonth > 0 && intMonth <= 12) return months[intMonth];
    }
    return '';
  }
}
