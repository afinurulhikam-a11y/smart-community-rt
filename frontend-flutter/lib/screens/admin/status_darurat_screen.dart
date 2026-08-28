import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../providers/emergency_provider.dart';
import '../../models/emergency_model.dart';
import '../../core/services/auth_service.dart';
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

  /// Boleh-tidaknya pengguna ini menutup kejadian [alert].
  ///
  /// **Cermin dari `bolehMenutupDarurat` di `emergency.controller.js`**:
  /// pemilik kejadian, atau Pengurus/Admin. Bila aturan di backend berubah,
  /// ubah di sini juga.
  ///
  /// Dipakai HANYA untuk memutuskan apa yang digambar. Ia bukan pengaman —
  /// endpoint OFF tetap menolak 403 untuk yang bukan pemilik dan bukan
  /// pengurus, jadi klien yang dimodifikasi tidak mendapat apa pun dari
  /// memaksa tombolnya muncul.
  ///
  /// Menyembunyikan aksinya TIDAK menyembunyikan kejadiannya: baris riwayat,
  /// nama pelapor, waktu, dan keterangannya tetap tampil untuk semua orang.
  /// Yang hilang hanya wewenang yang memang tidak dimiliki.
  bool _bolehMenyelesaikan(EmergencyModel alert) {
    final auth = context.read<AuthService>();
    if (auth.isPengurus) return true;

    final idSaya = auth.userId;
    return idSaya.isNotEmpty && idSaya == alert.userId;
  }

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

    // Status sirene global ikut dibaca, bukan hanya daftarnya.
    //
    // Keduanya berasal dari provider yang sama, jadi membiarkan yang satu
    // basi berarti dasbor dan layar ini bisa berbeda pendapat tentang
    // kejadian yang sama — persis keadaan yang hendak dihilangkan.
    provider.muatStatusAlarm();
  }

  /// Detail lengkap satu kejadian — termasuk keterangan yang di tabel dipotong.
  ///
  /// Hanya menampilkan; tidak ada satu pun aksi di sini yang mengubah status.
  /// Membuka detail sebuah kejadian tidak boleh menyelesaikannya.
  void _showDetailDialog(EmergencyModel alert) {
    final aktif = alert.isActive;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              aktif ? Icons.notifications_active_rounded : Icons.check_circle_outline,
              color: aktif ? AppTheme.dangerColor : const Color(0xFF059669),
              size: 22,
            ),
            const SizedBox(width: AppTheme.spasiM),
            Expanded(
              child: Text(
                aktif ? 'Darurat Aktif' : 'Darurat Selesai',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: lebarDialog(ctx, maksimal: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _barisDetail(ctx, 'Pelapor', alert.namaWarga?.trim().isNotEmpty == true
                    ? alert.namaWarga!
                    : 'Tidak diketahui'),
                if (alert.alamat?.trim().isNotEmpty == true)
                  _barisDetail(ctx, 'Alamat', alert.alamat!),
                if (alert.noHp?.trim().isNotEmpty == true)
                  _barisDetail(ctx, 'No. HP', alert.noHp!),
                _barisDetail(ctx, 'Waktu Kejadian',
                    DateFormat('dd MMM yyyy, HH:mm').format(alert.createdAt)),
                // Pelapor dan penyelesai sengaja ditampilkan sebagai dua baris
                // terpisah: ketika Pengurus menutup darurat milik warga,
                // keduanya memang orang yang berbeda, dan riwayat harus
                // menunjukkannya begitu.
                if (!aktif) ...[
                  _barisDetail(ctx, 'Diselesaikan oleh',
                      (alert.dismissedByNama?.trim().isNotEmpty == true &&
                              alert.dismissedByNama != '-')
                          ? alert.dismissedByNama!
                          : 'Tidak tercatat'),
                  if (alert.dismissedAt != null)
                    _barisDetail(ctx, 'Waktu Selesai',
                        DateFormat('dd MMM yyyy, HH:mm').format(alert.dismissedAt!)),
                ],
                const SizedBox(height: AppTheme.spasiM),
                Text(
                  'Keterangan Kejadian',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ctx.teksKedua,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spasiM),
                  decoration: BoxDecoration(
                    color: ctx.latarLembut,
                    borderRadius: BorderRadius.circular(AppTheme.radiusS),
                    border: Border.all(color: ctx.garis),
                  ),
                  // Tanpa maxLines: inilah tempat keterangan dibaca utuh.
                  child: Text(
                    alert.keteranganTampil,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: alert.tanpaKeteranganLegacy ? ctx.teksTersier : ctx.teksUtama,
                      fontStyle: alert.tanpaKeteranganLegacy ? FontStyle.italic : null,
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
        ],
      ),
    );
  }

  Widget _barisDetail(BuildContext ctx, String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: ctx.teksKedua),
            ),
          ),
          Expanded(
            child: Text(
              nilai,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ctx.teksUtama,
              ),
            ),
          ),
        ],
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
                  'Masukkan PIN Keamanan:',
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
          child: Row(
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
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      const Icon(Icons.history, color: Color(0xFFEF4444), size: 20),
                      Text(
                        'Riwayat Darurat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: context.teksUtama,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: context.garis),

              // Table Controls (Status filter)
              Padding(
                padding: EdgeInsets.all(paddingKartu(context)),
                child: Center(
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
                              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                              style: TextStyle(fontSize: 13, color: context.teksUtama),
                              items: ['Semua Status', 'Aktif', 'Selesai'].map((String val) {
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
              ),

              // Table
              Consumer<EmergencyProvider>(
                builder: (context, emergency, child) {
                  if (emergency.isLoading && emergency.alerts.isEmpty) {
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
                      kolom: const ['NO', 'Waktu', 'Pelapor', 'Pesan', 'Status'],
                      baris: emergency.alerts.asMap().entries.map((entry) {
                        final nomor = entry.key + 1 + ((emergency.currentPage - 1) * emergency.perPage);
                        final alert = entry.value;
                        final isActive = alert.isActive;
                        return BarisTabel(
                          onTap: () => _showDetailDialog(alert),
                          sel: [
                            SelTabel(
                              'NO',
                              Text(
                                '$nomor',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.teksKedua,
                                ),
                              ),
                            ),
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
                            // Dipotong dengan aman, bukan ditampilkan utuh:
                            // keterangan boleh sampai 500 karakter dan satu
                            // baris sepanjang itu akan merusak seluruh baris
                            // tabel. Teks penuhnya ada di dialog Detail.
                            SelTabel(
                              'Pesan',
                              Text(
                                alert.keteranganTampil,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                // Penanda legacy dimiringkan: ia keterangan
                                // TENTANG kejadian, bukan keterangan DARI
                                // pelapor, dan pembedaan itu harus terlihat
                                // tanpa harus membuka detail.
                                style: alert.tanpaKeteranganLegacy
                                    ? TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: context.teksTersier,
                                      )
                                    : null,
                              ),
                            ),
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
                              ? Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showDetailDialog(alert),
                                      icon: const Icon(Icons.info_outline, size: 14),
                                      label: const Text('Detail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    if (_bolehMenyelesaikan(alert))
                                      ElevatedButton.icon(
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
                                      ),
                                  ],
                                )
                              : Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showDetailDialog(alert),
                                      icon: const Icon(Icons.info_outline, size: 14),
                                      label: const Text('Detail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    Container(
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
                                  ],
                                ),
                        );
                      }).toList(),
                      currentPage: emergency.currentPage,
                      totalPages: emergency.totalPages,
                      totalData: emergency.totalData,
                      perPage: emergency.perPage,
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
