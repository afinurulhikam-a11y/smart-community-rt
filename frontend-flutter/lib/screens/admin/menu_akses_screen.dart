import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_service.dart';
import '../../models/permission_model.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/responsive_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

const Color _hijau = Color(0xFF10B981);
const Color _merah = Color(0xFFEF4444);

class MenuAksesScreen extends StatefulWidget {
  const MenuAksesScreen({super.key});

  @override
  State<MenuAksesScreen> createState() => _MenuAksesScreenState();
}

class _MenuAksesScreenState extends State<MenuAksesScreen> {
  List<MenuItemModel> _menus = [];
  List<RoleInfo> _roles = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String _filterGrup = 'Semua Menu';

  /// Perubahan yang belum disimpan: "role|menu_kode" -> Izin.
  final Map<String, Izin> _draft = {};

  bool get _adaPerubahan => _draft.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }


  Future<void> _muat() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final r = await ApiService.get(ApiConstants.menuAkses);
    if (!mounted) return;

    if (r['success'] == true) {
      setState(() {
        _menus = (r['data'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(MenuItemModel.fromJson)
            .toList();
        _roles = (r['roles'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(RoleInfo.fromJson)
            .toList();
        _draft.clear();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = r['message']?.toString() ?? 'Gagal memuat data hak akses.';
        _isLoading = false;
      });
    }
  }

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses, durasi: const Duration(seconds: 5));
  }

  String _kunci(String role, String kode) => '$role|$kode';

  Izin _izinSaatIni(MenuItemModel m, String role) =>
      _draft[_kunci(role, m.kode)] ?? m.izin[role] ?? const Izin();

  void _ubah(MenuItemModel m, String role, String aksi, bool nilai) {
    final kini = _izinSaatIni(m, role);
    Izin baru;
    switch (aksi) {
      case 'view':
        // Mencabut hak lihat berarti mencabut semuanya: tidak masuk akal bisa
        // menambah data pada menu yang tidak bisa dibuka.
        baru = nilai ? kini.salin(lihat: true) : const Izin();
        break;
      case 'create':
        baru = kini.salin(tambah: nilai, lihat: nilai ? true : kini.lihat);
        break;
      case 'update':
        baru = kini.salin(ubah: nilai, lihat: nilai ? true : kini.lihat);
        break;
      default:
        baru = kini.salin(hapus: nilai, lihat: nilai ? true : kini.lihat);
    }
    setState(() => _draft[_kunci(role, m.kode)] = baru);
  }

  Future<void> _simpan() async {
    if (!_adaPerubahan) return;
    setState(() => _isSaving = true);

    final perubahan = _draft.entries.map((e) {
      final bagian = e.key.split('|');
      return {'role': bagian[0], 'menu_kode': bagian[1], ...e.value.toJson()};
    }).toList();

    final r = await ApiService.put(ApiConstants.menuAkses, body: {'perubahan': perubahan});
    if (!mounted) return;
    setState(() => _isSaving = false);

    _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
    if (r['success'] == true) {
      await _muat();
      // Izin milik admin sendiri tidak berubah, tetapi muat ulang menjaga
      // sidebar tetap sinkron bila suatu saat aturannya diperluas.
      if (mounted) await context.read<PermissionProvider>().muat();
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Kembalikan ke Bawaan'),
        content: const Text(
          'Seluruh pengaturan hak akses akan dikembalikan ke matriks bawaan. '
          'Perubahan yang pernah Anda buat akan hilang. Lanjutkan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: _merah),
            child: const Text('Kembalikan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final r = await ApiService.post(ApiConstants.menuAksesReset);
    if (!mounted) return;
    _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);
    if (r['success'] == true) await _muat();
  }

  List<String> get _daftarGrup {
    final g = <String>{'Semua Menu'};
    for (final m in _menus) {
      g.add(m.grup);
    }
    return g.toList();
  }

  List<MenuItemModel> get _menuTampil =>
      _filterGrup == 'Semua Menu' ? _menus : _menus.where((m) => m.grup == _filterGrup).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _buildError()
        else ...[
          _buildStatGrid(),
          const SizedBox(height: 24),
          _buildPenjelasan(),
          const SizedBox(height: 16),
          _buildFilterBar(),
          const SizedBox(height: 16),
          _buildTabel(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.security, color: context.teksUtama, size: 24),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pengaturan Menu & Hak Akses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.teksUtama,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Atur menu apa saja yang bisa dibuka dan diubah tiap role',
                    style: TextStyle(fontSize: 12, color: context.teksKedua),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _reset,
              icon: const Icon(Icons.restore, size: 16, color: _merah),
              label: const Text(
                'Kembalikan ke Bawaan',
                style: TextStyle(color: _merah, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _merah),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            ElevatedButton.icon(
              onPressed: (_adaPerubahan && !_isSaving) ? _simpan : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _hijau,
                foregroundColor: Colors.white,
                disabledBackgroundColor: context.garis,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save, size: 16),
              label: Text(
                _adaPerubahan ? 'Simpan ${_draft.length} Perubahan' : 'Simpan Perubahan',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 40, color: _merah),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
        ],
      ),
    );
  }

  /// Menjelaskan aturan yang tidak bisa diubah, supaya sakelar terkunci tidak
  /// terlihat seperti kerusakan.
  Widget _buildPenjelasan() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFF2563EB)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Administrator selalu berakses penuh dan sakelarnya dikunci — ini disengaja agar '
              'tidak ada yang bisa mengunci dirinya sendiri dari sistem. Menu bergembok '
              '(Menu & Akses, Reset Sistem) juga hanya untuk Administrator. '
              'Perubahan berlaku setelah pengguna terkait masuk ulang.',
              style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final kolom = ResponsiveLayout.isMobile(context)
            ? 2
            : (ResponsiveLayout.isTablet(context) ? 3 : 2 + _roles.length);
        final lebar = (c.maxWidth - (16 * (kolom - 1))) / kolom;

        final kartu = <Widget>[
          _statCard('Total Menu', '${_menus.length}', context.teksUtama),
          _statCard(
            'Menu Aktif',
            '${_menus.where((m) => m.isAktif).length}',
            const Color(0xFF8B5CF6),
          ),
          ..._roles.map((r) {
            final jumlah = _menus.where((m) => _izinSaatIni(m, r.kode).lihat).length;
            return _statCard(
              '${r.nama} Akses',
              '$jumlah',
              r.terkunci ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
            );
          }),
        ];

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: kartu.map((w) => SizedBox(width: lebar, child: w)).toList(),
        );
      },
    );
  }

  Widget _statCard(String judul, String jumlah, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        children: [
          Text(
            jumlah,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: warna),
          ),
          const SizedBox(height: 4),
          Text(
            judul,
            style: TextStyle(fontSize: 11, color: context.teksKedua),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.garis),
      ),
      // Satu baris yang bisa digeser mendatar, bukan Wrap.
      //
      // Wrap membungkus chip ke beberapa baris dan lebar tiap chip mengikuti
      // panjang katanya, sehingga tepi kanannya selalu bergerigi — "Umum" dan
      // "Kependudukan" tidak akan pernah berakhir di titik yang sama. Baris
      // yang digeser adalah bentuk baku Material untuk filter chip: rapi,
      // rata, dan tidak menghabiskan tinggi layar.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _daftarGrup.map((g) {
            final aktif = _filterGrup == g;
            return Padding(
              padding: const EdgeInsets.only(right: AppTheme.spasiS),
              child: InkWell(
                onTap: () => setState(() => _filterGrup = g),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: AppTheme.sasaranSentuh),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spasiL),
                  decoration: BoxDecoration(
                    color: aktif ? const Color(0xFF1B7A6A) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: aktif ? const Color(0xFF1B7A6A) : context.garis,
                    ),
                  ),
                  child: Text(
                    g,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: aktif ? FontWeight.bold : FontWeight.w500,
                      color: aktif ? Colors.white : context.teksKedua,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTabel() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(context.latarLembut),
                headingRowHeight: 62,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 48,
                columnSpacing: 20,
                columns: [
                  DataColumn(
                    label: Text(
                      'NAMA MENU',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: context.teksKedua,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'AKTIF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: context.teksKedua,
                      ),
                    ),
                  ),
                  ..._roles.map(_kolomRole),
                ],
                rows: _menuTampil.map(_baris).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  DataColumn _kolomRole(RoleInfo role) {
    return DataColumn(
      label: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                role.nama,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.teksKedua,
                ),
              ),
              if (role.terkunci) ...[
                const SizedBox(width: 4),
                Icon(Icons.lock, size: 10, color: context.teksTersier),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  'LIHAT',
                  style: TextStyle(fontSize: 8, color: context.teksTersier),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  'TAMBAH',
                  style: TextStyle(fontSize: 8, color: context.teksTersier),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  'UBAH',
                  style: TextStyle(fontSize: 8, color: context.teksTersier),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  'HAPUS',
                  style: TextStyle(fontSize: 8, color: context.teksTersier),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DataRow _baris(MenuItemModel m) {
    final isDark = context.gelap;
    return DataRow(
      color: WidgetStateProperty.all(
        m.isSistem
            ? (isDark ? const Color(0xFF78350F).withValues(alpha: 0.3) : const Color(0xFFFEF3C7).withValues(alpha: 0.6))
            : context.latarKartu,
      ),
      cells: [
        DataCell(
          Row(
            children: [
              if (m.isSistem)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.lock, size: 12, color: Color(0xFFD97706)),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    m.nama,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.teksUtama,
                    ),
                  ),
                  Text(m.grup, style: TextStyle(fontSize: 9, color: context.teksTersier)),
                ],
              ),
            ],
          ),
        ),
        DataCell(
          _sakelar(
            nilai: m.isAktif,
            // Menu sistem tidak boleh dinonaktifkan — aplikasi bisa kehilangan
            // pintu masuk ke pengaturannya sendiri.
            //
            // Dikunci juga selama permintaan menu INI sedang berjalan, supaya
            // ketukan kedua tidak menjadi permintaan kedua yang saling
            // mendahului dan menyisakan keadaan yang tidak diminta siapa pun.
            aktif: !m.isSistem && _menoggle != m.kode,
            sibuk: _menoggle == m.kode,
            onUbah: (v) => _toggleAktif(m, v),
            tooltip: m.isSistem ? 'Menu sistem tidak bisa dinonaktifkan' : null,
          ),
        ),
        ..._roles.map((r) => _selRole(m, r)),
      ],
    );
  }

  DataCell _selRole(MenuItemModel m, RoleInfo role) {
    // Admin selalu penuh; menu sistem tertutup untuk role lain.
    final terkunci = role.terkunci || m.isSistem;
    final izin = role.terkunci ? Izin.penuh() : _izinSaatIni(m, role.kode);
    final tampil = m.isSistem && !role.terkunci ? const Izin() : izin;

    final tooltip = role.terkunci
        ? 'Administrator selalu berakses penuh'
        : (m.isSistem ? '${m.nama} hanya untuk Administrator' : null);

    return DataCell(
      Row(
        children: [
          _sakelar(
            nilai: tampil.lihat,
            aktif: !terkunci,
            tooltip: tooltip,
            onUbah: (v) => _ubah(m, role.kode, 'view', v),
          ),
          const SizedBox(width: 10),
          _sakelar(
            nilai: tampil.tambah,
            aktif: !terkunci,
            tooltip: tooltip,
            onUbah: (v) => _ubah(m, role.kode, 'create', v),
          ),
          const SizedBox(width: 10),
          _sakelar(
            nilai: tampil.ubah,
            aktif: !terkunci,
            tooltip: tooltip,
            onUbah: (v) => _ubah(m, role.kode, 'update', v),
          ),
          const SizedBox(width: 10),
          _sakelar(
            nilai: tampil.hapus,
            aktif: !terkunci,
            tooltip: tooltip,
            onUbah: (v) => _ubah(m, role.kode, 'delete', v),
          ),
        ],
      ),
    );
  }

  /// Kode menu yang saklar Aktif-nya sedang dikirim. Null bila tidak ada.
  ///
  /// Satu nilai, bukan Set: dua permintaan bersamaan atas menu yang BERBEDA
  /// tidak saling merusak, sedangkan dua permintaan atas menu yang SAMA justru
  /// yang berbahaya — itulah yang dijaga di sini.
  String? _menoggle;

  Future<void> _toggleAktif(MenuItemModel m, bool nilai) async {
    if (_menoggle == m.kode) return;
    setState(() => _menoggle = m.kode);

    final r = await ApiService.put(ApiConstants.menuAktif(m.kode), body: {'is_aktif': nilai});
    if (!mounted) return;

    setState(() => _menoggle = null);
    _pesan(r['message']?.toString() ?? 'Selesai.', sukses: r['success'] == true);

    // Tidak ada pembaruan optimistis di sini: saklar digambar dari `m.isAktif`
    // milik data server. Jadi kegagalan tidak perlu di-rollback — tidak ada
    // yang terlanjur berubah untuk dikembalikan, dan layar tetap menampilkan
    // apa yang benar-benar tersimpan.
    if (r['success'] == true) {
      await _muat();
      // Izin milik pengguna ini ikut dimuat ulang. Mematikan sebuah menu
      // mengubah apa yang boleh dilihat SEKARANG, dan sidebar membacanya dari
      // PermissionProvider — tanpa ini, sidebar baru menyusul setelah aplikasi
      // dibuka ulang.
      if (mounted) await context.read<PermissionProvider>().muat();
    }
  }

  Widget _sakelar({
    required bool nilai,
    required bool aktif,
    required ValueChanged<bool> onUbah,
    String? tooltip,
    bool sibuk = false,
  }) {
    // Selama menunggu jawaban server, saklarnya diganti lingkaran menunggu.
    // Saklar yang tetap terlihat normal selama permintaan berjalan membuat
    // orang mengira ketukannya tidak terbaca, lalu menekannya lagi.
    if (sibuk) {
      return const SizedBox(
        width: 34,
        child: Center(
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final w = InkWell(
      onTap: aktif ? () => onUbah(!nilai) : null,
      mouseCursor: aktif ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 16,
        alignment: nilai ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: nilai ? (aktif ? _hijau : const Color(0xFF93C5FD)) : context.garis,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          width: 12,
          height: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(color: context.latarKartu, shape: BoxShape.circle),
          ),
        ),
      ),
    );

    if (tooltip == null) {
      return SizedBox(width: 34, child: Center(child: w));
    }
    return SizedBox(
      width: 34,
      child: Center(child: Tooltip(message: tooltip, child: w)),
    );
  }
}
