import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../providers/polling_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

/// Kode modul di tabel izin.
///
/// Perhatikan: `create` di sini berarti MEMBUAT polling, bukan menyuarakannya.
/// Ikut memilih dijaga `view` — sejalan dengan polling.routes.js — sehingga
/// warga bisa memilih tanpa bisa membuat polling sendiri.
const String _kodeIzin = 'aspirasi.polling';

class PollingWargaScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PollingWargaScreen({super.key, this.onBack});

  @override
  State<PollingWargaScreen> createState() => _PollingWargaScreenState();
}

class _PollingWargaScreenState extends State<PollingWargaScreen> {
  bool get _bolehBuat => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  /// Ikut memilih cukup dengan `view`; lihat catatan pada [_kodeIzin].
  bool get _bolehPilih => context.watch<PermissionProvider>().bolehLihat(_kodeIzin);

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses, perilaku: SnackBarBehavior.floating);
  }

  String _activeTab = 'Semua';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final provider = context.read<PollingProvider>();
    provider.fetchPolling(status: _activeTab == 'Semua' ? null : _activeTab);
  }

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bar_chart, color: Color(0xFF0F766E), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Aspirasi & Partisipasi / Polling Warga',
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
              if (_bolehBuat)
                ElevatedButton.icon(
                  onPressed: _showFormPolling,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Buat Polling',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Filter Tabs
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildTab('Semua', Icons.grid_view),
            _buildTab('Aktif', Icons.play_circle_outline),
            _buildTab('Selesai', Icons.check_circle_outline),
            _buildTab('Ditutup', Icons.lock_outline),
          ],
        ),

        const SizedBox(height: 24),

        // Polling Cards
        Consumer<PollingProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.errorMessage != null) {
              return Center(
                child: Text(provider.errorMessage!, style: const TextStyle(color: Colors.red)),
              );
            }

            if (provider.pollingList.isEmpty) {
              return const Center(child: Text('Tidak ada data polling.'));
            }

            return Wrap(
              spacing: 24,
              runSpacing: 24,
              children: provider.pollingList.map((polling) {
                final dateMulai =
                    DateTime.tryParse(polling['tanggal_mulai'] ?? '') ?? DateTime.now();
                final dateSelesai =
                    DateTime.tryParse(polling['tanggal_selesai'] ?? '') ?? DateTime.now();
                final dateRange =
                    '${DateFormat('dd MMM yyyy').format(dateMulai)} - ${DateFormat('dd MMM yyyy').format(dateSelesai)}';

                // Nama field mengikuti yang benar-benar dikirim backend:
                // `total_votes` dan `vote_count`, bukan `total_suara` dan
                // `jumlah_suara` — yang lama selalu null, sehingga setiap
                // kartu menampilkan opsi "-" dengan 0%.
                final int totalSuara = int.tryParse(polling['total_votes']?.toString() ?? '0') ?? 0;
                final optionsData = polling['options'] as List? ?? [];
                final int? pilihanSaya = int.tryParse(polling['pilihan_saya']?.toString() ?? '');
                final bool lewatDeadline = polling['lewat_deadline'] == true ||
                    (dateSelesai.isBefore(DateTime.now()) &&
                        (polling['tanggal_selesai']?.toString().contains(':') ?? false));
                final bool belumMulai = polling['belum_mulai'] == true;
                final options = optionsData.map<Map<String, dynamic>>((opt) {
                  final int votes = int.tryParse(opt['vote_count']?.toString() ?? '0') ?? 0;
                  final int percentage = totalSuara > 0 ? ((votes / totalSuara) * 100).round() : 0;
                  final int optId = int.tryParse(opt['id']?.toString() ?? '') ?? 0;
                  return {
                    'id': optId,
                    'label': opt['label']?.toString() ?? '-',
                    'percentage': percentage,
                    'suara': votes,
                    'dipilih': pilihanSaya != null && pilihanSaya == optId,
                    'color': const Color(0xFF0F766E),
                  };
                }).toList();

                return SizedBox(
                  // Di ponsel kartunya mengisi lebar Wrap.
                  width: lebarKolomFilter(context, maksimal: 400),
                  child: _buildPollingCard(
                    id: polling['id'],
                    title: polling['judul'] ?? '-',
                    subtitle: polling['deskripsi'] ?? '-',
                    status: polling['status'] ?? 'Aktif',
                    dateRange: dateRange,
                    totalVotes: '$totalSuara suara',
                    options: options,
                    sudahVote: polling['sudah_vote'] == true,
                    pilihanSaya: pilihanSaya,
                    lewatDeadline: lewatDeadline,
                    belumMulai: belumMulai,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTab(String label, IconData icon) {
    bool isActive = _activeTab == label;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = label;
        });
        _loadData();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF0F766E)
              : (context.latarKartu),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF0F766E)
                : (context.garis),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? Colors.white
                  : (_isDarkMode ? Colors.white70 : context.teksKedua),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive
                    ? Colors.white
                    : (context.teksKedua),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPollingCard({
    required int id,
    required String title,
    required String subtitle,
    required String status,
    required String dateRange,
    required String totalVotes,
    required List<Map<String, dynamic>> options,
    bool sudahVote = false,
    int? pilihanSaya,
    bool lewatDeadline = false,
    bool belumMulai = false,
  }) {
    final rawStatus = status.toLowerCase();
    String displayStatus = 'Aktif';
    if (rawStatus == 'selesai') {
      displayStatus = 'Selesai';
    } else if (rawStatus == 'ditutup' || lewatDeadline) {
      displayStatus = 'Ditutup';
    } else if (belumMulai) {
      displayStatus = 'Belum Mulai';
    } else if (rawStatus.isNotEmpty) {
      displayStatus = '${status[0].toUpperCase()}${status.substring(1)}';
    }

    IconData statusIcon = Icons.play_circle_outline;
    Color statusColor = const Color(0xFF0F766E);
    if (displayStatus == 'Selesai') {
      statusIcon = Icons.check_circle_outline;
      statusColor = const Color(0xFF166534);
    } else if (displayStatus == 'Ditutup') {
      statusIcon = Icons.lock_outline;
      statusColor = const Color(0xFFDC2626);
    } else if (displayStatus == 'Belum Mulai') {
      statusIcon = Icons.schedule;
      statusColor = const Color(0xFFD97706);
    }

    return Container(
      height: 520,
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(paddingKartu(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            displayStatus,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.people_outline, size: 14, color: context.teksKedua),
                          const SizedBox(width: 4),
                          Text(
                            totalVotes,
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: context.teksUtama,
                            ),
                          ),
                          if (subtitle.isNotEmpty && subtitle != '-') ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: _isDarkMode ? Colors.white70 : context.teksKedua,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          ...options.map(
                            (opt) => _buildProgressRow(
                              opt['label'],
                              opt['percentage'],
                              opt['color'],
                              dipilih: opt['dipilih'] == true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 12, color: context.teksTersier),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dateRange,
                          style: TextStyle(fontSize: 11, color: context.teksTersier),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _tombolPilih(
                    id: id,
                    status: status,
                    options: options,
                    sudahVote: sudahVote,
                    pilihanSaya: pilihanSaya,
                    lewatDeadline: lewatDeadline,
                    belumMulai: belumMulai,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.garis),
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status.toLowerCase() == 'aktif' && _bolehUbah && !lewatDeadline) ...[
                        _buildActionButton(
                          Icons.lock_outline,
                          'Tutup',
                          const Color(0xFFD97706),
                          () async {
                            await context.read<PollingProvider>().updatePollingStatus(
                              id,
                              'Ditutup',
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          Icons.check_circle_outline,
                          'Selesai',
                          const Color(0xFF166534),
                          () async {
                            await context.read<PollingProvider>().updatePollingStatus(
                              id,
                              'Selesai',
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                  if (_bolehHapus)
                    _buildActionButton(
                      Icons.delete_outline,
                      'Hapus',
                      const Color(0xFFEF4444),
                      () async {
                        final conf = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Hapus'),
                            content: const Text('Yakin hapus polling ini?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Batal'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (conf == true && mounted) {
                          await context.read<PollingProvider>().deletePolling(id);
                        }
                      },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, int percentage, Color color, {bool dipilih = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: dipilih ? FontWeight.bold : FontWeight.normal,
                      color: context.teksUtama,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (dipilih) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle, size: 12, color: Color(0xFF0F766E)),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.latarLembut,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (percentage / 100).clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 34,
            child: Text(
              '$percentage%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: context.teksUtama,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Form membuat polling baru. Hanya untuk role ber-izin `create`.
  void _showFormPolling() {
    final judulCtrl = TextEditingController();
    final deskripsiCtrl = TextEditingController();
    final opsiCtrl = <TextEditingController>[TextEditingController(), TextEditingController()];
    DateTime mulai = DateTime.now();
    DateTime selesai = DateTime.now().add(const Duration(days: 7));
    final fmt = DateFormat('yyyy-MM-dd');

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Buat Polling',
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
                    decoration: const InputDecoration(labelText: 'Pertanyaan Polling'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deskripsiCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Keterangan (opsional)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final today = DateTime(now.year, now.month, now.day);
                            final initial = mulai.isBefore(today) ? today : mulai;
                            final d = await showDatePicker(
                              context: c2,
                              initialDate: initial,
                              firstDate: today,
                              lastDate: DateTime(2100),
                            );
                            if (d != null) {
                              setLocal(() {
                                mulai = d;
                                if (selesai.isBefore(mulai)) {
                                  selesai = mulai.add(const Duration(days: 7));
                                }
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Mulai'),
                            child: Text(fmt.format(mulai)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final initial = selesai.isBefore(mulai) ? mulai : selesai;
                            final d = await showDatePicker(
                              context: c2,
                              initialDate: initial,
                              firstDate: mulai,
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setLocal(() => selesai = d);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Selesai'),
                            child: Text(fmt.format(selesai)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pilihan Jawaban',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.teksKedua,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(opsiCtrl.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: opsiCtrl[i],
                              decoration: InputDecoration(labelText: 'Pilihan ${i + 1}'),
                            ),
                          ),
                          // Minimal dua pilihan; kurang dari itu bukan polling.
                          if (opsiCtrl.length > 2)
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: Color(0xFFEF4444),
                              ),
                              onPressed: () => setLocal(() => opsiCtrl.removeAt(i)),
                            ),
                        ],
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setLocal(() => opsiCtrl.add(TextEditingController())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Tambah Pilihan'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF0F766E)),
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
                final opsi = opsiCtrl.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
                if (judul.isEmpty) {
                  _pesan('Pertanyaan polling wajib diisi.', sukses: false);
                  return;
                }
                if (opsi.length < 2) {
                  _pesan('Isi minimal dua pilihan jawaban.', sukses: false);
                  return;
                }
                if (selesai.isBefore(mulai)) {
                  _pesan('Tanggal selesai tidak boleh mendahului tanggal mulai.', sukses: false);
                  return;
                }
                Navigator.pop(c);
                final prov = context.read<PollingProvider>();
                final ok = await prov.createPolling(
                  judul: judul,
                  deskripsi: deskripsiCtrl.text.trim(),
                  tanggalMulai: fmt.format(mulai),
                  tanggalSelesai: fmt.format(selesai),
                  options: opsi,
                );
                _pesan(
                  ok ? 'Polling berhasil dibuat.' : (prov.errorMessage ?? 'Polling gagal dibuat.'),
                  sukses: ok,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  /// Tombol memberikan suara atau mengubah pilihan.
  ///
  /// Keadaan yang ditangani:
  /// 1. Polling ditutup / selesai / lewat deadline:
  ///    - Jika sudah vote: tampilkan "Pilihan Anda: [Label] (Terkunci)".
  ///    - Jika belum vote: tampilkan keterangan polling ditutup / selesai.
  /// 2. Polling aktif & belum lewat deadline:
  ///    - Jika sudah vote: tampilkan "Pilihan Anda: [Label]" dan tombol "Ubah Pilihan".
  ///    - Jika belum vote: tampilkan tombol "Berikan Suara".
  Widget _tombolPilih({
    required int id,
    required String status,
    required List<Map<String, dynamic>> options,
    required bool sudahVote,
    int? pilihanSaya,
    bool lewatDeadline = false,
    bool belumMulai = false,
  }) {
    final st = status.toLowerCase();
    final isDitutup = st == 'ditutup' || lewatDeadline;
    final isSelesai = st == 'selesai';

    final pilihan = options.where((o) => o['dipilih'] == true).firstOrNull;

    if (belumMulai) {
      if (sudahVote) {
        return _kotakInfo(
          Icons.schedule,
          pilihan == null ? 'Pilihan Anda tercatat' : 'Pilihan Anda: ${pilihan['label']}',
          context.teksKedua,
        );
      }
      return _kotakInfo(Icons.schedule, 'Polling belum dimulai.', context.teksTersier);
    }

    if (isDitutup) {
      if (sudahVote) {
        return _kotakInfo(
          Icons.lock_outline,
          pilihan == null ? 'Pilihan Anda: - (Terkunci)' : 'Pilihan Anda: ${pilihan['label']} (Terkunci)',
          context.teksKedua,
        );
      }
      return _kotakInfo(Icons.lock_outline, 'Polling sudah ditutup.', context.teksTersier);
    }

    if (isSelesai) {
      if (sudahVote) {
        return _kotakInfo(
          Icons.check_circle_outline,
          pilihan == null ? 'Pilihan Anda tercatat (Selesai)' : 'Pilihan Anda: ${pilihan['label']} (Selesai)',
          const Color(0xFF166534),
        );
      }
      return _kotakInfo(Icons.check_circle_outline, 'Polling telah selesai.', const Color(0xFF166534));
    }

    if (st != 'aktif') {
      return _kotakInfo(Icons.lock_outline, 'Polling sudah ditutup.', context.teksTersier);
    }

    if (sudahVote) {
      if (!_bolehPilih) {
        return _kotakInfo(
          Icons.check_circle,
          pilihan == null ? 'Pilihan Anda tercatat' : 'Pilihan Anda: ${pilihan['label']}',
          const Color(0xFF0F766E),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _kotakInfo(
            Icons.check_circle,
            pilihan == null ? 'Pilihan Anda tercatat' : 'Pilihan Anda: ${pilihan['label']}',
            const Color(0xFF0F766E),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('tombol_ubah_pilihan'),
            onPressed: () => _pilihDialog(
              id,
              options,
              initialOptionId: pilihanSaya,
              isUbah: true,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F766E),
              side: const BorderSide(color: Color(0xFF0F766E)),
              minimumSize: const Size(double.infinity, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text(
              'Ubah Pilihan',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    if (!_bolehPilih) {
      return _kotakInfo(
        Icons.visibility_outlined,
        'Anda hanya dapat melihat hasil polling.',
        context.teksTersier,
      );
    }

    return ElevatedButton(
      key: const Key('tombol_berikan_suara'),
      onPressed: () => _pilihDialog(id, options, isUbah: false),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.how_to_vote_outlined, size: 16),
          SizedBox(width: 8),
          Text('Berikan Suara'),
        ],
      ),
    );
  }

  Widget _kotakInfo(IconData ikon, String teks, Color warna) {
    return Container(
      width: double.infinity,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(ikon, size: 15, color: warna),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              teks,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: warna),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _pilihDialog(
    int pollingId,
    List<Map<String, dynamic>> options, {
    int? initialOptionId,
    bool isUbah = false,
  }) {
    int? terpilih = initialOptionId ?? (options.isNotEmpty ? options.first['id'] as int? : null);

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isUbah ? 'Ubah Pilihan' : 'Berikan Suara',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: lebarDialog(context, maksimal: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUbah
                      ? 'Anda dapat mengubah pilihan selama polling masih aktif dan belum melewati batas waktu.'
                      : 'Pilihan dapat diubah kembali selama polling masih aktif dan belum melewati batas waktu.',
                  style: TextStyle(fontSize: 12, color: context.teksKedua),
                ),
                const SizedBox(height: 12),
                RadioGroup<int>(
                  groupValue: terpilih,
                  onChanged: (v) => setLocal(() => terpilih = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: options
                        .map(
                          (o) => RadioListTile<int>(
                            value: o['id'] as int,
                            activeColor: const Color(0xFF0F766E),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              o['label']?.toString() ?? '-',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              key: const Key('tombol_simpan_suara'),
              onPressed: terpilih == null
                  ? null
                  : () async {
                      Navigator.pop(c);
                      final prov = context.read<PollingProvider>();
                      final ok = await prov.vote(pollingId, terpilih!);
                      _pesan(
                        ok
                            ? (isUbah ? 'Pilihan Anda berhasil diperbarui.' : 'Suara Anda tersimpan. Terima kasih.')
                            : (prov.errorMessage ?? 'Suara gagal disimpan.'),
                        sukses: ok,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              child: Text(isUbah ? 'Simpan Perubahan' : 'Kirim Suara'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    final isDanger = color == const Color(0xFFEF4444) || label.toLowerCase().contains('hapus');
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: isDanger ? const Color(0xFFEF4444) : color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDanger ? const Color(0xFFEF4444) : color,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 36),
        backgroundColor: isDanger ? const Color(0xFFFEF2F2) : color.withValues(alpha: 0.06),
        side: BorderSide(
          color: isDanger ? const Color(0xFFFCA5A5) : color.withValues(alpha: 0.2),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
