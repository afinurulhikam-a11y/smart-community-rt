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
  int _halaman = 1;
  String _tipe = 'Semua';
  DateTime? _dari;
  DateTime? _sampai;
  final TextEditingController _searchController = TextEditingController();
  Timer? _autoRefreshTimer;

  /// Harus tetap sama persis dengan `TIPE` di `src/services/log.service.js`.
  ///
  /// Sebuah tipe yang ditambahkan hanya di satu sisi tetap tercatat di database
  /// tetapi tidak pernah bisa ditemukan dari layar ini — dan justru tipe-tipe
  /// baru itulah yang biasanya paling perlu dicari (LOGIN_GAGAL, RESET).
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
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Muat ulang otomatis hanya di halaman pertama tanpa penyaring apa pun.
      // Kalau tidak, hasil yang sedang dibaca akan tergeser sendiri setiap
      // lima detik justru saat seseorang sedang menelusuri sesuatu.
      if (mounted && !_adaPenyaring && _halaman == 1) {
        final provider = context.read<LogProvider>();
        if (!provider.isLoading) _loadData();
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
      offset: (_halaman - 1) * _limit,
      search: _searchController.text.isNotEmpty ? _searchController.text.trim() : null,
      tipe: _tipe,
      dari: _dari,
      sampai: _sampai,
    );
  }

  /// Setiap perubahan penyaring mengembalikan ke halaman 1.
  ///
  /// Tanpa ini, menyaring saat berada di halaman 8 menghasilkan layar kosong
  /// walau datanya ada — offset-nya sudah melewati ujung hasil yang baru.
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
        // Rentang terbalik tidak pernah mengembalikan apa pun. Daripada
        // menampilkan hasil kosong yang membingungkan, batas satunya digeser.
        if (_sampai != null && _sampai!.isBefore(terpilih)) _sampai = terpilih;
      } else {
        _sampai = terpilih;
        if (_dari != null && _dari!.isAfter(terpilih)) _dari = terpilih;
      }
    });
  }

  int _totalHalaman(int total) => total <= 0 ? 1 : ((total - 1) ~/ _limit) + 1;

  /// "Menampilkan 1 – 25 dari 4.312 kejadian".
  ///
  /// Angka totalnya yang penting, bukan yang tampil: ia satu-satunya petunjuk
  /// bahwa masih ada ribuan baris lain di belakang layar ini.
  String _ringkasanBaris(int tampil, int total) {
    if (total == 0) return 'Tidak ada kejadian yang cocok';
    final mulai = (_halaman - 1) * _limit + 1;
    final akhir = mulai + tampil - 1;
    final akhiran = _adaPenyaring ? ' (tersaring)' : '';
    return 'Menampilkan $mulai – $akhir dari $total kejadian$akhiran';
  }

  void _bersihkanPenyaring() {
    _searchController.clear();
    _ubahPenyaring(() {
      _tipe = 'Semua';
      _dari = null;
      _sampai = null;
    });
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
                                      // Lewat _ubahPenyaring supaya halaman ikut
                                      // kembali ke 1. Mengubah ukuran halaman
                                      // sambil berada di halaman 8 membuat
                                      // offset-nya melewati ujung data.
                                      onChanged: (val) {
                                        if (val != null) _ubahPenyaring(() => _limit = val);
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
                              // Dulu berbunyi "$_limit Terakhir". Setelah ada
                              // pagination itu keliru: yang dimuat adalah
                              // halaman yang sedang dibuka, bukan N terbaru.
                              label: const Text(
                                'Muat Ulang',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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

                  // Penyaring tipe + rentang tanggal.
                  //
                  // Jejak audit tidak pernah dihapus, jadi tabelnya hanya
                  // bertambah selamanya. Tanpa penyaring, sebulan lagi layar
                  // ini berisi ribuan baris dan tidak ada cara menemukan satu
                  // kejadian tertentu — datanya lengkap tetapi tidak terpakai.
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      paddingKartu(context),
                      0,
                      paddingKartu(context),
                      paddingKartu(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Chip menggulir mendatar di layar sempit, tidak
                        // membungkus: sebelas chip yang membungkus memakan
                        // empat baris penuh di ponsel.
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _daftarTipe.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final t = _daftarTipe[i];
                              final aktif = _tipe == t;
                              final warna = t == 'Semua' ? context.teksKedua : _getTipeColor(t);
                              return ChoiceChip(
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
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _pilihTanggal(awal: true),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.teksUtama,
                                side: BorderSide(color: context.garis),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              icon: const Icon(Icons.event, size: 15),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              icon: const Icon(Icons.event_available, size: 15),
                              label: Text(
                                _sampai == null ? 'Sampai tanggal' : DateFormat('dd MMM yyyy').format(_sampai!),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (_adaPenyaring)
                              TextButton.icon(
                                onPressed: _bersihkanPenyaring,
                                icon: const Icon(Icons.close, size: 15),
                                label: const Text('Bersihkan', style: TextStyle(fontSize: 12)),
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
                            _ringkasanBaris(logs.length, provider.total),
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Halaman sebelumnya',
                                onPressed: _halaman > 1
                                    ? () {
                                        setState(() => _halaman--);
                                        _loadData();
                                      }
                                    : null,
                                icon: const Icon(Icons.chevron_left, size: 20),
                              ),
                              Text(
                                'Hal. $_halaman / ${_totalHalaman(provider.total)}',
                                style: TextStyle(fontSize: 12, color: context.teksKedua),
                              ),
                              IconButton(
                                tooltip: 'Halaman berikutnya',
                                onPressed: _halaman < _totalHalaman(provider.total)
                                    ? () {
                                        setState(() => _halaman++);
                                        _loadData();
                                      }
                                    : null,
                                icon: const Icon(Icons.chevron_right, size: 20),
                              ),
                            ],
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
