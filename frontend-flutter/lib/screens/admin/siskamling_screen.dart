import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../providers/patrol_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/tabel_responsif.dart';
import '../../core/theme/warna_konteks.dart';

const String _kodeIzin = 'kegiatan.ronda';

class SiskamlingScreen extends StatefulWidget {
  const SiskamlingScreen({super.key});

  @override
  State<SiskamlingScreen> createState() => _SiskamlingScreenState();
}

class _SiskamlingScreenState extends State<SiskamlingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final prov = context.read<PatrolProvider>();
    prov.fetchSchedules();
    prov.fetchAttendances();
    prov.fetchPosQr();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Breadcrumb & Actions
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            children: [
              if (!pakaiKartu(context))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.shield_outlined, color: Color(0xFF1B7A6A), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Kegiatan & Info / Jadwal & Absensi Ronda',
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
                onPressed: () => _showAbsenDialog(context),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text(
                  'Absen Pos Ronda',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B7A6A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Navigation Tabs
        Container(
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.garis),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF1B7A6A),
            labelColor: const Color(0xFF1B7A6A),
            unselectedLabelColor: context.teksKedua,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Jadwal Ronda'),
              Tab(icon: Icon(Icons.history, size: 18), text: 'Log Absensi'),
              Tab(icon: Icon(Icons.qr_code_2, size: 18), text: 'QR Pos Ronda'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTabJadwal(context),
              _buildTabAbsensi(context),
              _buildTabQrPos(context),
            ],
          ),
        ),
      ],
    );
  }

  // ======================== TAB 1: JADWAL RONDA ========================

  Widget _buildTabJadwal(BuildContext context) {
    return Consumer<PatrolProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final schedules = provider.schedules;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Jadwal Siskamling Warga',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.teksUtama,
                    ),
                  ),
                  if (_bolehTambah)
                    ElevatedButton.icon(
                      onPressed: () => _showTambahJadwalDialog(context),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(
                        'Tambah Jadwal',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B7A6A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (schedules.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: context.latarKartu,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.garis),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.shield_outlined, size: 48, color: context.teksTersier),
                      const SizedBox(height: 12),
                      Text(
                        'Belum Ada Jadwal Siskamling',
                        style: TextStyle(fontWeight: FontWeight.bold, color: context.teksUtama),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pengurus dapat membuat jadwal giliran ronda malam untuk warga.',
                        style: TextStyle(fontSize: 12, color: context.teksTersier),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, c) {
                    final kolom = c.maxWidth > 900 ? 3 : (c.maxWidth > 600 ? 2 : 1);
                    final lebar = (c.maxWidth - (12 * (kolom - 1))) / kolom;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final s in schedules)
                          SizedBox(
                            width: lebar,
                            child: _buildJadwalCard(context, s, provider),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJadwalCard(BuildContext context, Map<String, dynamic> s, PatrolProvider provider) {
    final hari = s['hari'] ?? 'Senin';
    final shift = s['shift'] ?? 'Shift Malam';
    final petugas = s['petugas_warga'] ?? '-';
    final ket = s['keterangan'] ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hari,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B7A6A),
                    fontSize: 12,
                  ),
                ),
              ),
              if (_bolehHapus)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Hapus Jadwal'),
                        content: Text('Hapus jadwal ronda hari $hari?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await provider.deleteSchedule(s['id']);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: context.teksTersier),
              const SizedBox(width: 4),
              Text(shift, style: TextStyle(fontSize: 12, color: context.teksKedua)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Petugas Ronda:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B7A6A))),
          const SizedBox(height: 4),
          Text(petugas, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.teksUtama)),
          if (ket.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Ket: $ket', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: context.teksTersier)),
          ],
        ],
      ),
    );
  }

  // ======================== TAB 2: ABSENSI RONDA ========================

  Widget _buildTabAbsensi(BuildContext context) {
    return Consumer<PatrolProvider>(
      builder: (context, provider, _) {
        final attendances = provider.attendances;

        return Container(
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.garis),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Riwayat Kehadiran Ronda',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: context.teksUtama),
                    ),
                    Text(
                      '${attendances.length} catat',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                  child: TabelResponsif(
                    labelAksi: 'STATUS',
                    kolom: const ['NO', 'WAKTU SCAN', 'NAMA PETUGAS', 'LOKASI POS', 'STATUS', 'CATATAN'],
                    kosong: const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Belum ada data absensi ronda')),
                    ),
                    baris: attendances.asMap().entries.map((entry) {
                      final i = entry.key + 1;
                      final a = entry.value;
                      final tglStr = a['waktu_scan'] != null
                          ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(a['waktu_scan']))
                          : '-';
                      final status = a['status'] ?? 'Hadir';

                      return BarisTabel(
                        sel: [
                          SelTabel.teks('NO', i.toString(), sembunyiDiKartu: true),
                          SelTabel.teks('WAKTU SCAN', tglStr, utama: true),
                          SelTabel.teks('NAMA PETUGAS', a['nama_petugas'] ?? '-'),
                          SelTabel.teks('LOKASI POS', a['lokasi_pos'] ?? 'Pos Ronda Utama'),
                          SelTabel(
                            'STATUS',
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: status == 'Tepat Waktu'
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: status == 'Tepat Waktu' ? Colors.green : Colors.orange,
                                ),
                              ),
                            ),
                          ),
                          SelTabel.teks('CATATAN', a['catatan'] ?? '-'),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ======================== TAB 3: QR CODE POS RONDA ========================

  Widget _buildTabQrPos(BuildContext context) {
    return Consumer<PatrolProvider>(
      builder: (context, provider, _) {
        final posData = provider.posQrData;

        return SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.latarKartu,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.garis),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_2, color: Color(0xFF1B7A6A), size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    posData?['pos_name'] ?? 'Pos Ronda Utama Siskamling',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.teksUtama),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tempelkan poster QR ini di fisik Pos Ronda',
                    style: TextStyle(fontSize: 12, color: context.teksTersier),
                  ),
                  const SizedBox(height: 20),
                  // Mockup QR Display Card
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300, width: 2),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.qr_code_2, size: 120, color: Color(0xFF1B7A6A)),
                          const SizedBox(height: 4),
                          Text(
                            posData?['qr_code_data'] ?? 'POS_RONDA_OFFICIAL_QR',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.garis.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.key, size: 16, color: Color(0xFF1B7A6A)),
                        const SizedBox(width: 6),
                        Text(
                          'Secret Token: ${posData?['qr_code_data'] ?? "POS_RONDA_OFFICIAL_QR"}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.teksUtama),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ======================== DIALOGS ========================

  void _showAbsenDialog(BuildContext context) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner, color: Color(0xFF1B7A6A)),
            SizedBox(width: 8),
            Text('Absensi Pos Ronda'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tekan tombol di bawah untuk mencatatkan kehadiran ronda malam Anda di Pos Ronda hari ini.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan Petugas (Opsional)',
                hintText: 'Misal: Ronda bersama Pak Budi & Pak Slamet',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(c);
              final res = await context.read<PatrolProvider>().submitAttendance(
                catatan: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? ''),
                    backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Kirim Absensi'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A6A), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showTambahJadwalDialog(BuildContext context) {
    String selectedHari = 'Senin';
    final shiftCtrl = TextEditingController(text: 'Shift Malam (22:00 - 04:00)');
    final petugasCtrl = TextEditingController();
    final ketCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Tambah Jadwal Siskamling'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedHari,
                  decoration: const InputDecoration(labelText: 'Hari Ronda *'),
                  items: const [
                    DropdownMenuItem(value: 'Senin', child: Text('Senin')),
                    DropdownMenuItem(value: 'Selasa', child: Text('Selasa')),
                    DropdownMenuItem(value: 'Rabu', child: Text('Rabu')),
                    DropdownMenuItem(value: 'Kamis', child: Text('Kamis')),
                    DropdownMenuItem(value: 'Jumat', child: Text('Jumat')),
                    DropdownMenuItem(value: 'Sabtu', child: Text('Sabtu')),
                    DropdownMenuItem(value: 'Minggu', child: Text('Minggu')),
                  ],
                  onChanged: (v) => setSt(() => selectedHari = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: shiftCtrl,
                  decoration: const InputDecoration(labelText: 'Shift Jam *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: petugasCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Petugas Warga *',
                    hintText: 'Misal: Budi, Agus, Slamet, Afi',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ketCtrl,
                  decoration: const InputDecoration(labelText: 'Keterangan'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                if (petugasCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Petugas ronda wajib diisi!'), backgroundColor: Colors.red),
                  );
                  return;
                }
                Navigator.pop(c);
                await context.read<PatrolProvider>().createSchedule(
                  hari: selectedHari,
                  shift: shiftCtrl.text.trim(),
                  petugasWarga: petugasCtrl.text.trim(),
                  keterangan: ketCtrl.text.trim().isNotEmpty ? ketCtrl.text.trim() : null,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A6A), foregroundColor: Colors.white),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
