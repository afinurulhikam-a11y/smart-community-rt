import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../widgets/tabel_responsif.dart';
import '../../providers/log_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';

class LogAktivitasScreen extends StatefulWidget {
  const LogAktivitasScreen({super.key});

  @override
  State<LogAktivitasScreen> createState() => _LogAktivitasScreenState();
}

class _LogAktivitasScreenState extends State<LogAktivitasScreen> {
  int _limit = 25;
  final TextEditingController _searchController = TextEditingController();
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _searchController.text.isEmpty) {
        final provider = context.read<LogProvider>();
        if (!provider.isLoading) {
          provider.fetchLogs(limit: _limit);
        }
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    final provider = context.read<LogProvider>();
    provider.fetchLogs(
      limit: _limit,
      search: _searchController.text.isNotEmpty ? _searchController.text.trim() : null,
    );
  }

  /// Menjelaskan kenapa jejak audit tidak bisa dibersihkan.
  ///
  /// Menggantikan tombol "Bersihkan Log" yang dulu ada di sini. Tombol itu
  /// memanggil `DELETE /api/activity-logs`, yang berarti satu-satunya peran
  /// yang paling perlu diawasi justru dibolehkan menghapus catatan
  /// pengawasannya sendiri. Endpoint-nya sudah dihapus dan `activity_logs`
  /// kini menolak DELETE maupun TRUNCATE di tingkat database.
  ///
  /// Dialog penjelasan ini sengaja dipertahankan alih-alih menghilangkan
  /// tombolnya begitu saja: seorang admin yang mencarinya berhak tahu ke mana
  /// perginya, bukan sekadar mendapati menunya lenyap.
  void _showInfoLogPermanen() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Aktivitas bersifat permanen'),
        content: const Text(
          'Jejak audit tidak dapat dihapus oleh siapa pun, termasuk Administrator.\n\n'
          'Catatan ini justru paling dibutuhkan ketika yang perlu diperiksa adalah '
          'pemegang akses tertinggi — kalau bisa dihapus, ia tidak membuktikan apa-apa.\n\n'
          'Reset Sistem juga tidak menyentuhnya, dan database menolak setiap '
          'perintah hapus terhadap tabel ini.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti')),
        ],
      ),
    );
  }

  Color _getTipeColor(String tipe) {
    switch (tipe.toUpperCase()) {
      case 'LOGIN':
        return const Color(0xFF06B6D4);
      case 'CREATE':
        return const Color(0xFF10B981);
      case 'UPDATE':
        return const Color(0xFFF59E0B);
      // Merah untuk empat jenis yang pertama dicari saat memeriksa
      // penyalahgunaan: penghapusan, percobaan pembobolan, reset massal,
      // dan alarm darurat.
      case 'DELETE':
      case 'LOGIN_GAGAL':
      case 'RESET':
      case 'DARURAT':
        return const Color(0xFFEF4444);
      // Perubahan wewenang: peran, status akun, hak akses menu.
      case 'AKSES':
        return const Color(0xFFD97706);
      case 'PEMBAYARAN':
        return const Color(0xFF1B7A6A);
      case 'IMPORT':
        return const Color(0xFF8B5CF6);
      default:
        return context.teksKedua;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Content Card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.garis,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Consumer<LogProvider>(
            builder: (context, provider, _) {
              final logs = provider.logs;
              final isLoading = provider.isLoading;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toolbar & Filter Controls
                  Padding(
                    padding: EdgeInsets.all(paddingKartu(context)),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Tampilkan',
                                  style: TextStyle(fontSize: 13, color: context.teksKedua),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: context.garis),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: _limit,
                                      icon: Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 16,
                                        color: context.teksKedua,
                                      ),
                                      items: [10, 25, 50, 100].map((int val) {
                                        return DropdownMenuItem<int>(
                                          value: val,
                                          child: Text('$val', style: const TextStyle(fontSize: 13)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _limit = val);
                                          _loadData();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              width: lebarKolomFilter(context, maksimal: 288),
                              child: Row(
                                children: [
                                  Text(
                                    'Cari Log:',
                                    style: TextStyle(fontSize: 13, color: context.teksKedua),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: context.garis),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: TextField(
                                        controller: _searchController,
                                        onSubmitted: (_) => _loadData(),
                                        decoration: InputDecoration(
                                          hintText: 'Ketik lalu Enter...',
                                          hintStyle: TextStyle(
                                            fontSize: 12,
                                            color: context.teksTersier,
                                          ),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              Icons.search,
                                              size: 16,
                                              color: context.teksKedua,
                                            ),
                                            onPressed: () => _loadData(),
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.symmetric(
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _loadData(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF3B82F6),
                                side: const BorderSide(color: Color(0xFFDBEAFE)),
                                backgroundColor: const Color(0xFFEFF6FF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              icon: const Icon(Icons.refresh, size: 15),
                              label: Text(
                                '$_limit Terakhir',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            // Dulu di sini ada tombol "Bersihkan Log" berwarna
                            // merah. Diganti penanda bahwa jejaknya permanen —
                            // lihat _showInfoLogPermanen untuk alasannya.
                            OutlinedButton.icon(
                              onPressed: _showInfoLogPermanen,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.teksKedua,
                                side: BorderSide(color: context.garis),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              icon: const Icon(Icons.lock_outline, size: 15),
                              label: const Text(
                                'Permanen',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Data Table or Loader
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6))),
                    )
                  else if (logs.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(
                        child: Text(
                          'Belum ada log aktivitas sistem yang tercatat.',
                          style: TextStyle(color: context.teksKedua),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                      child: TabelResponsif(
                        tinggiBarisMin: 64,
                        tinggiBarisMaks: 64,
                        kolom: const ['WAKTU', 'USER', 'TIPE', 'AKTIVITAS', 'IP ADDRESS'],
                        baris: logs.map((log) {
                          DateTime? dt;
                          if (log['created_at'] != null) {
                            dt = DateTime.tryParse(log['created_at'].toString())?.toLocal();
                          }
                          final dateStr = dt != null ? DateFormat('dd MMM yyyy').format(dt) : '-';
                          final timeStr = dt != null ? DateFormat('HH:mm:ss').format(dt) : '-';
                          final tipe = log['tipe']?.toString() ?? 'SYSTEM';
                          final tipeColor = _getTipeColor(tipe);

                          return BarisTabel(
                            sel: [
                              SelTabel(
                                'WAKTU',
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: context.teksUtama,
                                      ),
                                    ),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.teksTersier,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SelTabel(
                                'USER',
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.person_outline,
                                      size: 16,
                                      color: Color(0xFF3B82F6),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            log['user_nama']?.toString() ?? 'Sistem',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: context.teksUtama,
                                            ),
                                          ),
                                          Text(
                                            log['user_role']?.toString() ?? 'User',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.teksTersier,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SelTabel(
                                'TIPE',
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tipeColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    tipe.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              SelTabel.teks(
                                'AKTIVITAS',
                                log['aktivitas']?.toString() ?? '',
                                utama: true,
                              ),
                              SelTabel.teks(
                                'IP ADDRESS',
                                log['ip_address']?.toString() ?? '127.0.0.1',
                                gaya: TextStyle(fontSize: 13, color: context.teksKedua),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),

                  Divider(height: 1, color: context.garis),

                  // Footer Summary
                  Padding(
                    padding: EdgeInsets.all(paddingKartu(context)),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          Text(
                            'Menampilkan ${logs.length} log aktivitas sistem terbaru',
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
