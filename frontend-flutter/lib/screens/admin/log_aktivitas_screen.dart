import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/keadaan_daftar.dart';
import '../../widgets/tombol_kembali.dart';
import '../../providers/log_provider.dart';
import '../../core/theme/warna_konteks.dart';

class LogAktivitasScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const LogAktivitasScreen({super.key, this.onBack});

  @override
  State<LogAktivitasScreen> createState() => _LogAktivitasScreenState();
}

class _LogAktivitasScreenState extends State<LogAktivitasScreen> {
  final int _limit = 25;
  int _halaman = 1;
  String _tipe = 'Semua';
  DateTime? _dari;
  DateTime? _sampai;
  final TextEditingController _searchController = TextEditingController();
  Timer? _autoRefreshTimer;

  /// Harus tetap sama persis dengan `TIPE` di `src/services/log.service.js`.
  static const List<String> _daftarTipe = [
    'Semua',
    'LOGIN',
    'LOGIN_GAGAL',
    'CREATE',
    'UPDATE',
    'DELETE',
    'PEMBAYARAN',
    'IMPORT',
    'AKSES',
    'RESET',
    'DARURAT',
  ];

  bool get _adaPenyaring =>
      _tipe != 'Semua' ||
      _dari != null ||
      _sampai != null ||
      _searchController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      // Muat ulang di latar belakang (silent) tanpa memicu spinner dan tanpa merusak scroll.
      // Hanya berjalan di halaman pertama tanpa penyaring aktif.
      if (mounted && !_adaPenyaring && _halaman == 1) {
        final provider = context.read<LogProvider>();
        if (!provider.isLoading) _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadData({bool silent = false}) {
    final provider = context.read<LogProvider>();
    provider.fetchLogs(
      limit: _limit,
      offset: (_halaman - 1) * _limit,
      search: _searchController.text.isNotEmpty ? _searchController.text.trim() : null,
      tipe: _tipe,
      dari: _dari,
      sampai: _sampai,
      silent: silent,
    );
  }

  /// Setiap perubahan penyaring mengembalikan ke halaman 1.
  void _ubahPenyaring(VoidCallback ubah) {
    setState(() {
      ubah();
      _halaman = 1;
    });
    _loadData();
  }

  Future<void> _pilihTanggal({required bool awal}) async {
    final sekarang = DateTime.now();
    final terpilih = await showDatePicker(
      context: context,
      initialDate: (awal ? _dari : _sampai) ?? sekarang,
      firstDate: DateTime(2020),
      lastDate: DateTime(sekarang.year + 1, 12, 31),
      helpText: awal ? 'Dari tanggal' : 'Sampai tanggal',
    );
    if (terpilih == null) return;
    _ubahPenyaring(() {
      if (awal) {
        _dari = terpilih;
        if (_sampai != null && _sampai!.isBefore(terpilih)) _sampai = terpilih;
      } else {
        _sampai = terpilih;
        if (_dari != null && _dari!.isAfter(terpilih)) _dari = terpilih;
      }
    });
  }

  int _totalHalaman(int total) => total <= 0 ? 1 : ((total - 1) ~/ _limit) + 1;

  void _bersihkanPenyaring() {
    _searchController.clear();
    _ubahPenyaring(() {
      _tipe = 'Semua';
      _dari = null;
      _sampai = null;
    });
  }

  void _showInfoLogPermanen() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Aktivitas bersifat permanen'),
        content: const Text(
          'Jejak audit tidak dapat dihapus oleh siapa pun, termasuk Administrator.\n\n'
          'Catatan ini justru paling dibutuhkan ketika yang perlu diperiksa adalah '
          'pemegang akses tertinggi — kalau bisa dihapus, ia tidak membuktikan apa-apa.\n\n'
          'Reset Sistem juga tidak menyentuhnya, dan database menolak setiap '
          'perintah hapus terhadap tabel ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: ctx.warnaTombolTutup),
            child: const Text('Mengerti'),
          ),
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
      case 'DELETE':
      case 'LOGIN_GAGAL':
      case 'RESET':
      case 'DARURAT':
        return const Color(0xFFEF4444);
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
        // Header Breadcrumb
        Container(
          padding: EdgeInsets.all(paddingKartu(context)),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.garis),
          ),
          child: Row(
            children: [
              TombolKembali(onPressed: widget.onBack),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded, color: Color(0xFF3B82F6), size: 20),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Pengaturan / Log Aktivitas',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.teksKedua,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Table Card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.garis),
          ),
          child: Consumer<LogProvider>(
            builder: (context, provider, _) {
              final logs = provider.logs;
              final isLoading = provider.isLoading;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table Header Title (Center)
                  Padding(
                    padding: EdgeInsets.all(paddingKartu(context)),
                    child: Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          const Icon(Icons.history_rounded, color: Color(0xFF3B82F6), size: 20),
                          Text(
                            'Log Aktivitas Sistem',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: context.teksUtama,
                            ),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            onPressed: _showInfoLogPermanen,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.teksKedua,
                              side: BorderSide(color: context.garis),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.lock_outline, size: 13),
                            label: const Text(
                              'Permanen',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: context.garis),
                  const SizedBox(height: 16),

                  // Baris 1: Pencarian & Refresh (Center)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: paddingKartu(context)),
                    child: Center(
                      child: Wrap(
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
                              onSubmitted: (_) => _loadData(),
                              decoration: InputDecoration(
                                hintText: 'Cari aktivitas, user, IP...',
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
                                focusedBorder: const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(8)),
                                  borderSide: BorderSide(color: Color(0xFF3B82F6)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _loadData(),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Muat Ulang', style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.teksKedua,
                              side: BorderSide(color: context.garis),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Baris 2: Tipe Log Chips (Center)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: paddingKartu(context)),
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _daftarTipe.map((t) {
                            final aktif = _tipe == t;
                            final warna = t == 'Semua' ? context.teksKedua : _getTipeColor(t);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: aktif ? FontWeight.bold : FontWeight.normal,
                                    color: aktif ? Colors.white : warna,
                                  ),
                                ),
                                selected: aktif,
                                showCheckmark: false,
                                selectedColor: warna,
                                backgroundColor: context.latarLembut,
                                side: BorderSide(color: aktif ? warna : context.garis),
                                onSelected: (_) => _ubahPenyaring(() => _tipe = t),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Baris 3: Rentang Tanggal & Bersihkan (Center)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: paddingKartu(context)),
                    child: Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Text(
                            'Rentang:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: context.teksKedua,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pilihTanggal(awal: true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.teksUtama,
                              side: BorderSide(color: context.garis),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text(
                              _dari == null ? 'Dari tanggal' : DateFormat('dd MMM yyyy').format(_dari!),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pilihTanggal(awal: false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.teksUtama,
                              side: BorderSide(color: context.garis),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.event_available, size: 16),
                            label: Text(
                              _sampai == null ? 'Sampai tanggal' : DateFormat('dd MMM yyyy').format(_sampai!),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (_adaPenyaring)
                            TextButton.icon(
                              onPressed: _bersihkanPenyaring,
                              icon: const Icon(Icons.close, size: 15),
                              label: const Text('Bersihkan Filter', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: context.warnaTombolTutup,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Data Table or Loader
                  if (isLoading && logs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6))),
                    )
                  else if (logs.isEmpty)
                    KeadaanDaftar(
                      kosong: _adaPenyaring
                          ? 'Tidak ada kejadian yang cocok dengan penyaring ini.'
                          : 'Belum ada log aktivitas sistem yang tercatat.',
                      galat: provider.errorMessage,
                      offline: provider.offline,
                      onCobaLagi: _loadData,
                      ikonKosong: Icons.history_toggle_off,
                    )
                  else
                    Padding(
                      padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                      child: TabelResponsif(
                        tinggiBarisMin: 64,
                        tinggiBarisMaks: 64,
                        kolom: const ['NO', 'WAKTU', 'USER', 'TIPE', 'AKTIVITAS', 'IP ADDRESS'],
                        baris: logs.asMap().entries.map((entry) {
                          final nomor = entry.key + 1 + ((_halaman - 1) * _limit);
                          final log = entry.value;
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
                        currentPage: _halaman,
                        totalPages: _totalHalaman(provider.total),
                        totalData: provider.total,
                        perPage: _limit,
                        onPageChanged: (p) {
                          setState(() => _halaman = p);
                          _loadData();
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
