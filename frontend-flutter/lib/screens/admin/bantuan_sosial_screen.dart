import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/bantuan_sosial_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/responsif.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_service.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/banner_lihat_saja.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';
import 'data_warga_screen.dart';

/// Format string YYYY-MM-DD atau ISO String menjadi DateTime lokal tanpa geser zona waktu.
DateTime? parseDateString(dynamic val) {
  if (val == null) return null;
  final str = val.toString().split('T')[0].trim();
  if (str.isEmpty) return null;
  final parts = str.split('-');
  if (parts.length == 3) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y != null && m != null && d != null) {
      return DateTime(y, m, d);
    }
  }
  return DateTime.tryParse(str);
}

/// Format string YYYY-MM-DD atau ISO String menjadi format tanggal Indonesia (mis. 15 Agustus 2026).
String formatTanggalIndo(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '-';
  final cleanStr = dateStr.split('T')[0];
  final parts = cleanStr.split('-');
  if (parts.length == 3) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y != null && m != null && d != null && m >= 1 && m <= 12) {
      const bulan = [
        'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
      ];
      return '$d ${bulan[m - 1]} $y';
    }
  }
  return cleanStr;
}

/// Helper untuk menampilkan teks tanggal/periode bantuan sosial secara lengkap.
String formatPeriodeBansos(Map<String, dynamic> b) {
  final tBantuan = b['tanggal_bantuan']?.toString();
  final tMulai = b['tanggal_mulai']?.toString();
  final tSelesai = b['tanggal_selesai']?.toString();
  final tahun = b['tahun'];

  if (tBantuan != null && tBantuan.isNotEmpty) {
    return formatTanggalIndo(tBantuan);
  }
  if (tMulai != null && tMulai.isNotEmpty) {
    final mulai = formatTanggalIndo(tMulai);
    if (tSelesai != null && tSelesai.isNotEmpty) {
      return '$mulai s.d. ${formatTanggalIndo(tSelesai)}';
    }
    return '$mulai s.d. Selesai';
  }
  if (tahun != null) {
    return tahun.toString();
  }
  return '-';
}

/// Kode modul di tabel izin. Bendahara hanya punya `view` di sini.
const String _kodeIzin = 'kependudukan.bansos';

class BantuanSosialScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const BantuanSosialScreen({super.key, this.onBack});

  @override
  State<BantuanSosialScreen> createState() => _BantuanSosialScreenState();
}

class _BantuanSosialScreenState extends State<BantuanSosialScreen> {
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  String _selectedTahun = 'Semua';
  String _jenisBantuan = 'Semua Jenis';
  String _status = 'Semua Status';
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();
  final List<String> _tahunList = ['Semua', '2026', '2025', '2024', '2023', '2022', '2021', '2020'];

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

  void _resetSemuaFilter() {
    setState(() {
      _selectedTahun = 'Semua';
      _jenisBantuan = 'Semua Jenis';
      _status = 'Semua Status';
      _searchQuery = '';
      _searchController.clear();
    });
    _loadData();
  }

  Future<void> _exportData(String format) async {
    final queryParams = [];
    if (_selectedTahun != 'Semua') queryParams.add('tahun=$_selectedTahun');
    if (_jenisBantuan != 'Semua Jenis') {
      queryParams.add('jenis_bantuan=${Uri.encodeComponent(_jenisBantuan)}');
    }
    if (_status != 'Semua Status') queryParams.add('status=${Uri.encodeComponent(_status)}');
    if (_searchQuery.isNotEmpty) queryParams.add('search=${Uri.encodeComponent(_searchQuery)}');
    queryParams.add('format=$format');
    final token = ApiService.token;
    if (token != null) queryParams.add('token=$token');

    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final url = Uri.parse('${ApiConstants.baseUrl}/bantuan-sosial/export$queryString');

    if (!await launchUrl(url)) {
      if (mounted) {
        pesanGagal(context, 'Gagal mengunduh file');
      }
    }
  }

  void _loadData({int page = 1}) {
    final provider = context.read<BantuanSosialProvider>();
    provider.fetchStats();
    provider.fetchWargaList();
    provider.fetchBantuanSosial(
      tahun: _selectedTahun == 'Semua' ? null : _selectedTahun,
      jenisBantuan: _jenisBantuan == 'Semua Jenis' ? null : _jenisBantuan,
      status: _status == 'Semua Status' ? null : _status,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      page: page,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BannerLihatSaja(kode: _kodeIzin),
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
                      child: const Icon(
                        Icons.monitor_heart_outlined,
                        color: Color(0xFF1B7A6A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Kependudukan / Bantuan Sosial',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildActionButton(
                    Icons.description,
                    'Export Excel',
                    const Color(0xFF059669),
                    onTap: () => _exportData('excel'),
                  ),
                  _buildActionButton(
                    Icons.picture_as_pdf,
                    'Export PDF',
                    const Color(0xFFDC2626),
                    onTap: () => _exportData('pdf'),
                  ),
                  if (_bolehTambah)
                    _buildActionButton(
                      Icons.person_add,
                      'Tambah Penerima',
                      const Color(0xFF1B7A6A),
                      onTap: () => _showFormDialog(),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Stat Cards
        Consumer<BantuanSosialProvider>(
          builder: (context, provider, _) {
            final stats = provider.stats;
            return LayoutBuilder(
              builder: (context, c) {
                final kolom = c.maxWidth > 900 ? 4 : (c.maxWidth > 500 ? 2 : 1);
                final lebar = (c.maxWidth - (12 * (kolom - 1))) / kolom;
                final kartu = [
                  _buildStatCard(
                    'Total Penerima',
                    '${stats['total_penerima'] ?? 0}',
                    Icons.people_outline,
                    const Color(0xFF1B7A6A),
                    const Color(0xFFF0FDF4),
                  ),
                  _buildStatCard(
                    'Aktif',
                    '${stats['aktif'] ?? 0}',
                    Icons.check_circle_outline,
                    const Color(0xFF10B981),
                    const Color(0xFFF0FDF4),
                  ),
                  _buildStatCard(
                    'Selesai',
                    '${stats['selesai'] ?? 0}',
                    Icons.check,
                    const Color(0xFFF59E0B),
                    const Color(0xFFFEFCE8),
                  ),
                  _buildStatCard(
                    'Jenis Aktif',
                    '${stats['jenis_aktif'] ?? 0}',
                    Icons.card_giftcard,
                    const Color(0xFF8B5CF6),
                    const Color(0xFFF3E8FF),
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

        // Filters - Tahun Chips
        Row(
          children: [
            Icon(Icons.calendar_month, size: 16, color: context.teksKedua),
            const SizedBox(width: 8),
            Text('Tahun:', style: TextStyle(fontSize: 13, color: context.teksKedua)),
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _tahunList
                      .map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildTahunChip(t),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Filters - Row 2
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: context.garis),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _jenisBantuan,
                  icon: Icon(Icons.keyboard_arrow_down, size: 16, color: context.teksKedua),
                  style: TextStyle(fontSize: 13, color: context.teksUtama),
                  items: [
                    'Semua Jenis',
                    'Sembako',
                    'BLT',
                    'Kesehatan',
                    'PKH',
                    'BPNT',
                    'BST',
                    'BLT Dana Desa',
                    'PBI-JKN',
                    'Lainnya',
                  ].map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
                  onChanged: (v) {
                    setState(() => _jenisBantuan = v!);
                    _loadData();
                  },
                ),
              ),
            ),

            Container(
              constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: context.garis),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _status,
                  icon: Icon(Icons.keyboard_arrow_down, size: 16, color: context.teksKedua),
                  style: TextStyle(fontSize: 13, color: context.teksUtama),
                  items: [
                    'Semua Status',
                    'Aktif',
                    'Selesai',
                  ].map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
                  onChanged: (v) {
                    setState(() => _status = v!);
                    _loadData();
                  },
                ),
              ),
            ),

            SizedBox(
              width: lebarKolomFilter(context, maksimal: 260),
              height: AppTheme.sasaranSentuh,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: context.garis),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  onSubmitted: (_) => _loadData(),
                  decoration: InputDecoration(
                    hintText: 'Cari nama atau NIK..',
                    hintStyle: TextStyle(fontSize: 13, color: context.teksTersier),
                    prefixIcon: Icon(Icons.search, size: 18, color: context.teksTersier),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),

            SizedBox(
              height: AppTheme.sasaranSentuh,
              child: OutlinedButton.icon(
                onPressed: _resetSemuaFilter,
                icon: Icon(Icons.refresh, size: 16, color: context.teksKedua),
                label: Text(
                  'Reset',
                  style: TextStyle(color: context.teksKedua, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.garis),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, AppTheme.sasaranSentuh),
                  maximumSize: const Size(double.infinity, AppTheme.sasaranSentuh),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Data Section
        Consumer<BantuanSosialProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(
                child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
              );
            }

            return Container(
              width: double.infinity,
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
                          Wrap(
                            children: [
                              const Icon(Icons.list_alt, color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Data Penerima Bantuan',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: context.teksUtama,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${provider.totalData} data',
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  if (provider.bantuanList.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 80),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF0FDF4),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.monitor_heart_outlined,
                                size: 40,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Belum Ada Data',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: context.teksUtama,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tambahkan data penerima bantuan sosial warga RT.',
                              style: TextStyle(fontSize: 13, color: context.teksTersier),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                      child: TabelResponsif(
                        labelAksi: 'Aksi',
                        kolom: const [
                          'No',
                          'Nama Warga',
                          'NIK',
                          'Jenis Bantuan',
                          'Tanggal / Periode',
                          'Status',
                          'Keterangan',
                        ],
                        baris: provider.bantuanList.asMap().entries.map((entry) {
                          final index = entry.key;
                          final b = entry.value;
                          final nomor =
                              ((provider.currentPage - 1) * provider.perPage) + index + 1;
                          return BarisTabel(
                            sel: [
                              SelTabel.teks('No', '$nomor', sembunyiDiKartu: true),
                              SelTabel.teks('Nama Warga', b['nama_warga'] ?? '-', utama: true),
                              SelTabel.teks('NIK', b['nik_warga'] ?? '-'),
                              SelTabel.teks('Jenis Bantuan', b['jenis_bantuan'] ?? '-'),
                              SelTabel.teks('Tanggal / Periode', formatPeriodeBansos(b)),
                              SelTabel(
                                'Status',
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: b['status'] == 'Aktif'
                                        ? const Color(0xFFD1FAE5)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    b['status'] ?? '-',
                                    style: TextStyle(
                                      color: b['status'] == 'Aktif'
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              SelTabel.teks('Keterangan', b['keterangan'] ?? '-'),
                            ],
                            aksi: Transform.translate(
                              offset: const Offset(geserAksiTabel, 0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_bolehUbah)
                                    IconButton(
                                      tooltip: 'Edit',
                                      icon: const Icon(Icons.edit_outlined, color: Color(0xFF0F766E), size: 20),
                                      style: gayaAksiTabel(const Color(0xFF0F766E)),
                                      onPressed: () => _showFormDialog(data: b),
                                    ),
                                  if (_bolehHapus)
                                    IconButton(
                                      tooltip: 'Hapus',
                                      icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                      style: gayaAksiTabel(const Color(0xFFEF4444)),
                                      onPressed: () async {
                                        final conf = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('Hapus'),
                                            content: const Text('Yakin hapus data ini?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(c, false),
                                                child: const Text('Batal'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(c, true),
                                                child: const Text(
                                                  'Hapus',
                                                  style: TextStyle(color: Colors.red),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (conf == true && mounted) {
                                          final ok = await provider.deleteBantuanSosial(b['id']);
                                          if (!context.mounted) return;
                                          if (ok) {
                                            pesanSukses(context, 'Data berhasil dihapus');
                                          } else {
                                            pesanGagal(
                                              context,
                                              provider.errorMessage ?? 'Gagal menghapus data',
                                            );
                                          }
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        currentPage: provider.currentPage,
                        totalPages: provider.totalPages,
                        totalData: provider.totalData,
                        perPage: provider.perPage,
                        footerTerpusat: true,
                        onPageChanged: (page) => _loadData(page: page),
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

  Widget _buildTahunChip(String label) {
    bool isSelected = _selectedTahun == label;
    return InkWell(
      onTap: () {
        setState(() => _selectedTahun = label);
        _loadData();
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1B7A6A) : Colors.transparent,
          border: Border.all(color: isSelected ? const Color(0xFF1B7A6A) : context.garis),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : context.teksKedua,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: context.teksKedua)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap ?? () {},
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showFormDialog({Map<String, dynamic>? data}) {
    final provider = context.read<BantuanSosialProvider>();
    final isEdit = data != null;

    String? selectedUserId = isEdit
        ? data['user_id']
        : (provider.wargaList.isNotEmpty ? provider.wargaList.first['id'] : null);
    String selectedJenis = isEdit ? (data['jenis_bantuan'] ?? 'Sembako') : 'Sembako';
    String status = isEdit ? (data['status'] ?? 'Aktif') : 'Aktif';

    String tipePeriode = 'satu_kali';
    DateTime? tanggalBantuan;
    DateTime? tanggalMulai;
    DateTime? tanggalSelesai;

    if (isEdit) {
      if (data['tanggal_bantuan'] != null) {
        tipePeriode = 'satu_kali';
        tanggalBantuan = parseDateString(data['tanggal_bantuan']);
      } else if (data['tanggal_mulai'] != null) {
        tipePeriode = 'periode';
        tanggalMulai = parseDateString(data['tanggal_mulai']);
        if (data['tanggal_selesai'] != null) {
          tanggalSelesai = parseDateString(data['tanggal_selesai']);
        }
      } else {
        tipePeriode = 'satu_kali';
        tanggalBantuan = DateTime.now();
      }
    } else {
      tipePeriode = 'satu_kali';
      tanggalBantuan = DateTime.now();
    }

    final nominalController = TextEditingController(
      text: isEdit ? data['nominal']?.toString() : '',
    );
    final ketController = TextEditingController(text: isEdit ? data['keterangan'] ?? '' : '');

    final jenisBantuanList = [
      'Sembako',
      'BLT',
      'Kesehatan',
      'PKH',
      'BPNT',
      'BST',
      'BLT Dana Desa',
      'PBI-JKN',
      'Lainnya',
    ];

    bool nominalNol() {
      final t = nominalController.text.trim();
      final n = int.tryParse(t) ?? 0;
      return n == 0;
    }

    String? toDateString(DateTime? dt) {
      if (dt == null) return null;
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            InputDecoration buildDecor(String label, IconData icon) {
              return InputDecoration(
                labelText: label,
                labelStyle: TextStyle(fontSize: 14, color: context.teksKedua),
                prefixIcon: Icon(icon, color: const Color(0xFF1B7A6A), size: 20),
                filled: true,
                fillColor: context.latarLembut,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.garis),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.garis),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
                ),
              );
            }

            Widget buildDateField({
              required String label,
              required DateTime? value,
              required ValueChanged<DateTime?> onChanged,
              bool optional = false,
            }) {
              final textValue = value != null
                  ? formatTanggalIndo(toDateString(value))
                  : (optional ? 'Pilih Tanggal Selesai (Opsional)' : 'Pilih Tanggal *');
              return InkWell(
                onTap: () async {
                  final initial = value ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    onChanged(picked);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: buildDecor(label, Icons.calendar_today_outlined),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        textValue,
                        style: TextStyle(
                          fontSize: 14,
                          color: value != null ? context.teksUtama : context.teksTersier,
                        ),
                      ),
                      if (optional && value != null)
                        InkWell(
                          onTap: () => onChanged(null),
                          child: Icon(Icons.clear, size: 18, color: context.teksKedua),
                        ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_document : Icons.person_add_alt_1_rounded,
                      color: const Color(0xFF1B7A6A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Penerima' : 'Tambah Penerima',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: context.teksUtama,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: lebarDialog(context, maksimal: 500),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      if (!isEdit)
                        DropdownButtonFormField<String>(
                          decoration: buildDecor('Pilih Warga *', Icons.person_outline),
                          initialValue: selectedUserId,
                          dropdownColor: context.latarKartu,
                          borderRadius: BorderRadius.circular(12),
                          items: provider.wargaList.map((w) {
                            return DropdownMenuItem<String>(
                              value: w['id'],
                              child: Text('${w['nama']}'),
                            );
                          }).toList(),
                          onChanged: (v) => setDialogState(() => selectedUserId = v),
                        ),
                      if (!isEdit) const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: buildDecor('Jenis Bantuan *', Icons.card_giftcard),
                        initialValue: selectedJenis,
                        dropdownColor: context.latarKartu,
                        borderRadius: BorderRadius.circular(12),
                        items: jenisBantuanList
                            .map((j) => DropdownMenuItem(value: j, child: Text(j)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedJenis = v!),
                      ),
                      const SizedBox(height: 16),

                      // Tipe Periode Toggle (Satu Kali vs Berperiode)
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Satu Kali (1 Tanggal)'),
                              selected: tipePeriode == 'satu_kali',
                              onSelected: (sel) {
                                if (sel) {
                                  setDialogState(() {
                                    tipePeriode = 'satu_kali';
                                    tanggalBantuan ??= DateTime.now();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Berperiode (Mulai-Selesai)'),
                              selected: tipePeriode == 'periode',
                              onSelected: (sel) {
                                if (sel) {
                                  setDialogState(() {
                                    tipePeriode = 'periode';
                                    tanggalMulai ??= DateTime.now();
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (tipePeriode == 'satu_kali') ...[
                        buildDateField(
                          label: 'Tanggal Bantuan *',
                          value: tanggalBantuan,
                          onChanged: (val) => setDialogState(() => tanggalBantuan = val),
                        ),
                      ] else ...[
                        buildDateField(
                          label: 'Tanggal Mulai *',
                          value: tanggalMulai,
                          onChanged: (val) => setDialogState(() => tanggalMulai = val),
                        ),
                        const SizedBox(height: 16),
                        buildDateField(
                          label: 'Tanggal Selesai (Opsional)',
                          value: tanggalSelesai,
                          optional: true,
                          onChanged: (val) => setDialogState(() => tanggalSelesai = val),
                        ),
                      ],
                      const SizedBox(height: 16),

                      TextField(
                        controller: nominalController,
                        decoration: buildDecor('Nominal *', Icons.monetization_on_outlined),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 16),
                      if (isEdit) ...[
                        DropdownButtonFormField<String>(
                          decoration: buildDecor('Status', Icons.check_circle_outline),
                          initialValue: status,
                          dropdownColor: context.latarKartu,
                          borderRadius: BorderRadius.circular(12),
                          items: [
                            'Aktif',
                            'Selesai',
                          ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) => setDialogState(() => status = v!),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: ketController,
                        decoration: buildDecor(
                          nominalNol()
                              ? 'Keterangan (Wajib)'
                              : 'Keterangan (Opsional)',
                          Icons.notes,
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    foregroundColor: context.teksKedua,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!isEdit && selectedUserId == null) {
                      pesanGagal(context, 'Pilih warga terlebih dahulu');
                      return;
                    }

                    if (tipePeriode == 'satu_kali' && tanggalBantuan == null) {
                      pesanGagal(context, 'Tanggal bantuan wajib diisi');
                      return;
                    }
                    if (tipePeriode == 'periode') {
                      if (tanggalMulai == null) {
                        pesanGagal(context, 'Tanggal mulai wajib diisi');
                        return;
                      }
                      if (tanggalSelesai != null && tanggalSelesai!.isBefore(tanggalMulai!)) {
                        pesanGagal(context, 'Tanggal selesai tidak boleh lebih awal dari tanggal mulai');
                        return;
                      }
                    }

                    final nominal = double.tryParse(nominalController.text.trim());
                    if (nominal == null || nominal < 0) {
                      pesanGagal(context, 'Nominal wajib diisi dan tidak boleh negatif');
                      return;
                    }
                    if (nominal == 0 && ketController.text.trim().isEmpty) {
                      pesanGagal(context, 'Keterangan wajib diisi bila nominal 0');
                      return;
                    }

                    final tBantuanStr = tipePeriode == 'satu_kali' ? toDateString(tanggalBantuan) : null;
                    final tMulaiStr = tipePeriode == 'periode' ? toDateString(tanggalMulai) : null;
                    final tSelesaiStr = tipePeriode == 'periode' ? toDateString(tanggalSelesai) : null;

                    final refDt = tanggalBantuan ?? tanggalMulai ?? DateTime.now();

                    final payload = {
                      if (isEdit) 'user_id': data['user_id'] else 'user_id': selectedUserId,
                      'jenis_bantuan': selectedJenis,
                      'tanggal_bantuan': tBantuanStr,
                      'tanggal_mulai': tMulaiStr,
                      'tanggal_selesai': tSelesaiStr,
                      'tahun': refDt.year,
                      'nominal': nominal,
                      'keterangan': ketController.text,
                      if (isEdit) 'status': status,
                    };

                    bool success;
                    if (isEdit) {
                      success = await provider.updateBantuanSosial(data['id'], payload);
                    } else {
                      success = await provider.createBantuanSosial(
                        userId: selectedUserId!,
                        jenisBantuan: selectedJenis,
                        tanggalBantuan: tBantuanStr,
                        tanggalMulai: tMulaiStr,
                        tanggalSelesai: tSelesaiStr,
                        tahun: refDt.year,
                        nominal: nominal,
                        keterangan: ketController.text,
                      );
                    }

                    if (!context.mounted || !ctx.mounted) return;
                    if (success) {
                      Navigator.pop(ctx);
                      pesanSukses(context, isEdit ? 'Data diperbarui' : 'Data ditambahkan');
                    } else {
                      pesanGagal(context, provider.errorMessage ?? 'Gagal menyimpan data');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7A6A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    isEdit ? 'Simpan Perubahan' : 'Simpan & Tambahkan',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
