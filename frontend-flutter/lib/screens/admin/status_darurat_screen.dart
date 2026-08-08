import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../providers/emergency_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

class StatusDaruratScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const StatusDaruratScreen({super.key, this.onBack});

  @override
  State<StatusDaruratScreen> createState() => _StatusDaruratScreenState();
}

class _StatusDaruratScreenState extends State<StatusDaruratScreen> {
  String _status = 'Semua Status';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData({int page = 1}) {
    final provider = context.read<EmergencyProvider>();
    String? statusFilter;
    if (_status == 'Aktif') statusFilter = 'active';
    if (_status == 'Selesai') statusFilter = 'dismissed';
    provider.fetchAlerts(status: statusFilter, page: page, limit: 10);
  }

  void _showSimulateDialog() {
    final msgController = TextEditingController(text: 'Latihan Darurat Kebakaran');
    final pinController = TextEditingController();
    String? pinError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shield_outlined, color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verifikasi Keamanan 2-Langkah',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.teksUtama),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Konfirmasi pemicuan simulasi darurat',
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Detail Pesan Simulasi:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.teksKedua),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: msgController,
                  decoration: InputDecoration(
                    hintText: 'Pesan / detail kejadian',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Masukkan PIN Keamanan (Default: 1234):',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.teksKedua),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Masukkan 4-digit PIN',
                    prefixIcon: const Icon(Icons.lock_outline, size: 18),
                    errorText: pinError,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Fitur verifikasi ini mencegah penyalahgunaan atau ketidaksengajaan tertekan oleh anak kecil.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final pin = pinController.text.trim();
                          if (pin.isEmpty) {
                            setModalState(() {
                              pinError = 'Wajib memasukkan PIN Keamanan';
                            });
                            return;
                          }
                          Navigator.pop(ctx);
                          final messenger = ScaffoldMessenger.of(context);
                          final provider = context.read<EmergencyProvider>();
                          final success = await provider.triggerAlarm(
                            message: msgController.text.trim(),
                            pin: pin,
                          );
                          if (mounted) {
                            if (success) {
                              tampilkanPesanDi(
                                messenger,
                                provider.successMessage ?? 'Sinyal darurat berhasil dikirim!',
                                sukses: true,
                              );
                            } else {
                              tampilkanPesanDi(
                                messenger,
                                provider.errorMessage ?? 'PIN Keamanan salah atau gagal mengirim sinyal.',
                                sukses: false,
                              );
                            }
                            _loadData();
                          }
                        },
                        child: const Text('Verifikasi & Kirim', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showResolveDialog(String alertId) {
    final pinController = TextEditingController();
    String? pinError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.verified_user_outlined, color: Color(0xFF059669), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Konfirmasi Penutupan Status Darurat',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.teksUtama),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Verifikasi 2-Langkah Penutupan Alarm',
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Apakah Anda yakin keadaan sudah aman dan laporan ini dapat ditutup?',
                  style: TextStyle(fontSize: 13, color: context.teksUtama),
                ),
                const SizedBox(height: 16),
                Text(
                  'Masukkan PIN Keamanan (Default: 1234):',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.teksKedua),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Masukkan 4-digit PIN',
                    prefixIcon: const Icon(Icons.lock_outline, size: 18),
                    errorText: pinError,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final pin = pinController.text.trim();
                          if (pin.isEmpty) {
                            setModalState(() {
                              pinError = 'Wajib memasukkan PIN Keamanan';
                            });
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final provider = context.read<EmergencyProvider>();
                          final success = await provider.dismissAlarm(alertId, pin: pin);
                          if (mounted) {
                            if (success) {
                              if (ctx.mounted) Navigator.pop(ctx);
                              tampilkanPesanDi(
                                messenger,
                                provider.successMessage ?? 'Status darurat berhasil diselesaikan.',
                                sukses: true,
                              );
                              _loadData();
                            } else {
                              setModalState(() {
                                pinError = provider.errorMessage ?? 'PIN Keamanan salah! Penutupan dibatalkan.';
                              });
                            }
                          }
                        },
                        child: const Text('Selesaikan', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
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
                    TombolKembali(onPressed: widget.onBack),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.crisis_alert, color: Color(0xFFEF4444), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Aspirasi & Partisipasi / Status Darurat',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _isDarkMode ? Colors.white70 : context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _showSimulateDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.warning, size: 18),
                  label: const Text(
                    'Simulasi Darurat',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
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
                    const Icon(Icons.history, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Riwayat Darurat',
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

              // Table Controls (Status filter)
              Padding(
                padding: EdgeInsets.all(paddingKartu(context)),
                // Label DI ATAS kontrolnya, bukan di sampingnya.
                //
                // Jaraknya dulu hanya mengandalkan satu spasi di dalam string
                // 'Status: ' — dan begitu Wrap membungkusnya ke baris baru,
                // spasi itu hilang sama sekali sehingga label menempel ke
                // kotak. Bentuk bertumpuk ini sama dengan filter Kas RT dan
                // Dana BOP, jadi ketiganya kini konsisten.
                child: Column(
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
                          items: ['Semua Status', 'Aktif', 'Selesai'].map((String val) {
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
              ),

              // Table
              Consumer<EmergencyProvider>(
                builder: (context, emergency, child) {
                  if (emergency.isLoading) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFFEF4444))),
                    );
                  }

                  if (emergency.alerts.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'Tidak ada data darurat.',
                          style: TextStyle(color: context.teksKedua),
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                    child: TabelResponsif(
                      labelAksi: 'Aksi',
                      kolom: const ['Waktu', 'Pelapor', 'Pesan', 'Status'],
                      baris: emergency.alerts.map((alert) {
                        final isActive = alert.isActive;
                        return BarisTabel(
                          sel: [
                            SelTabel.teks(
                              'Waktu',
                              DateFormat('dd MMM yyyy, HH:mm').format(alert.createdAt),
                            ),
                            SelTabel(
                              'Pelapor',
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: const Color(0xFF059669).withValues(alpha: 0.1),
                                    child: const Icon(Icons.person, size: 16, color: Color(0xFF059669)),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        alert.namaWarga ?? 'Warga',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: context.teksUtama,
                                        ),
                                      ),
                                      if (alert.alamat != null &&
                                          alert.alamat!.trim().isNotEmpty &&
                                          alert.alamat != '-')
                                        Text(
                                          alert.alamat!,
                                          style: TextStyle(color: context.teksKedua, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              utama: true,
                            ),
                            SelTabel.teks('Pesan', alert.message),
                            SelTabel(
                              'Status',
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? const Color(0xFFFEF2F2)
                                      : const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isActive
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFFA7F3D0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isActive ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isActive ? 'Aktif' : 'Selesai',
                                      style: TextStyle(
                                        color: isActive ? const Color(0xFF991B1B) : const Color(0xFF065F46),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          aksi: isActive
                              ? ElevatedButton.icon(
                                  onPressed: () => _showResolveDialog(alert.id),
                                  icon: const Icon(Icons.check_circle_outline, size: 14),
                                  label: const Text('Selesaikan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: context.latarLembut,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: context.garis),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified, size: 15, color: Color(0xFF059669)),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Selesai oleh:',
                                            style: TextStyle(fontSize: 10, color: context.teksKedua, fontWeight: FontWeight.w500),
                                          ),
                                          Text(
                                            (alert.dismissedByNama != null && alert.dismissedByNama!.trim().isNotEmpty && alert.dismissedByNama != '-')
                                                ? alert.dismissedByNama!
                                                : 'Pengurus RT',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: context.teksUtama,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                        );
                      }).toList(),
                      currentPage: emergency.currentPage,
                      totalPages: emergency.totalPages,
                      onPageChanged: (page) => _loadData(page: page),
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
}
