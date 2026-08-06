import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class SidebarMenu extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final VoidCallback onLogout;
  final String role;

  const SidebarMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
    this.role = 'admin',
  });

  @override
  State<SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<SidebarMenu> {
  // Track expanded submenu groups
  final Set<int> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _autoExpandActiveGroup();
  }

  @override
  void didUpdateWidget(covariant SidebarMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _autoExpandActiveGroup();
    }
  }

  void _autoExpandActiveGroup() {
    final group = widget.selectedIndex ~/ 10;
    if (group > 0) {
      _expandedGroups.add(group);
    }
  }

  bool get isAdmin => widget.role == 'admin';
  bool get isWarga => widget.role == 'warga';

  // Visibilitas menu sekarang berasal dari izin yang dimuat backend, bukan
  // ditebak dari nama role. Ini sekaligus menghapus dua cacat lama: Profil
  // Saya yang hanya muncul untuk admin, dan Inventaris yang ikut tersembunyi
  // saat role tidak punya akses Keuangan.
  late PermissionProvider _izin;

  bool _lihat(String kode) => _izin.bolehLihat(kode);
  bool _hanyaLihat(String kode) => _izin.hanyaLihat(kode);
  bool _lihatSalahSatu(List<String> kode) => _izin.bolehLihatSalahSatu(kode);

  @override
  Widget build(BuildContext context) {
    _izin = context.watch<PermissionProvider>();
    return Container(
      width: 240,
      color: const Color(0xFF1B7A6A),
      // SafeArea: di ponsel laci ini menempel ke tepi atas layar, dan pada
      // perangkat berponi atau berkamera lubang, logo "AUTO RT" tertutup
      // takik. Tidak ada satu pun SafeArea di aplikasi ini sebelumnya.
      //
      // `bottom: false` disengaja — daftar menunya sudah bisa digulir dan
      // menyisakan jarak di bawah justru memotongnya lebih awal.
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Logo Area
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AUTO RT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Sistem Manajemen RT Terintegrasi',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Menu Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildMenuItem(index: 0, icon: Icons.dashboard_rounded, label: 'Dashboard'),
                  if (_lihatSalahSatu(const [
                    'kependudukan.warga',
                    'kependudukan.bansos',
                    'kependudukan.statistik',
                  ])) ...[
                    _buildExpandableMenuItem(
                      groupIndex: 1,
                      icon: Icons.people_rounded,
                      label: 'Kependudukan',
                    ),
                    if (_expandedGroups.contains(1)) ...[
                      if (_lihat('kependudukan.warga'))
                        _buildSubMenuItem(
                          index: 12,
                          icon: Icons.people_outline,
                          label: 'Data Warga',
                          isViewOnly: _hanyaLihat('kependudukan.warga'),
                        ),
                      if (_lihat('kependudukan.bansos'))
                        _buildSubMenuItem(
                          index: 13,
                          icon: Icons.favorite_border_rounded,
                          label: 'Bantuan Sosial',
                          isViewOnly: _hanyaLihat('kependudukan.bansos'),
                        ),
                      if (_lihat('kependudukan.statistik'))
                        _buildSubMenuItem(
                          index: 14,
                          icon: Icons.pie_chart_outline_rounded,
                          label: 'Statistik & Grafik',
                        ),
                    ],
                  ],
                  if (_lihatSalahSatu(const [
                    'keuangan.iuran',
                    'keuangan.kas',
                    'keuangan.bop',
                  ])) ...[
                    _buildExpandableMenuItem(
                      groupIndex: 2,
                      icon: Icons.account_balance_wallet_rounded,
                      label: isWarga ? 'Keuangan Saya' : 'Keuangan',
                    ),
                    if (_expandedGroups.contains(2)) ...[
                      // Indeks menu sama untuk semua role; yang berbeda hanya
                      // layar tujuannya, dipilih di main_dashboard._buildBody.
                      // Warga melihat tagihan kartu keluarganya, pengurus
                      // melihat pengelolaan iuran seluruh RT.
                      if (_lihat('keuangan.iuran'))
                        _buildSubMenuItem(
                          index: 21,
                          icon: Icons.receipt_long_rounded,
                          label: isWarga ? 'Tagihan Saya' : 'Iuran Warga',
                          isViewOnly: !isWarga && _hanyaLihat('keuangan.iuran'),
                        ),
                      if (_lihat('keuangan.kas'))
                        _buildSubMenuItem(
                          index: 22,
                          icon: Icons.account_balance_rounded,
                          label: isWarga ? 'Laporan Kas RT' : 'Kas RT',
                          isViewOnly: !isWarga && _hanyaLihat('keuangan.kas'),
                        ),
                      if (_lihat('keuangan.bop'))
                        _buildSubMenuItem(
                          index: 23,
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Dana BOP',
                          isViewOnly: _hanyaLihat('keuangan.bop'),
                        ),
                    ],
                  ],
                  // Inventaris berdiri sendiri, tidak lagi menumpang gerbang
                  // Keuangan — dulu sekretaris kehilangan menu ini karenanya.
                  if (_lihatSalahSatu(const ['inventaris.barang', 'inventaris.peminjaman'])) ...[
                    _buildExpandableMenuItem(
                      groupIndex: 3,
                      icon: Icons.inventory_2_rounded,
                      label: 'Inventaris',
                    ),
                    if (_expandedGroups.contains(3)) ...[
                      if (_lihat('inventaris.barang'))
                        _buildSubMenuItem(
                          index: 31,
                          icon: Icons.grid_view_rounded,
                          label: 'Data Barang',
                          isViewOnly: _hanyaLihat('inventaris.barang'),
                        ),
                      if (_lihat('inventaris.peminjaman'))
                        _buildSubMenuItem(
                          index: 32,
                          icon: Icons.swap_horiz_rounded,
                          label: isWarga ? 'Pinjam Barang' : 'Peminjaman',
                          isViewOnly: _hanyaLihat('inventaris.peminjaman'),
                        ),
                    ],
                  ],
                  if (_lihatSalahSatu(const ['layanan.visitor', 'layanan.surat'])) ...[
                    _buildExpandableMenuItem(
                      groupIndex: 4,
                      icon: Icons.room_service_rounded,
                      label: 'Layanan Warga',
                    ),
                    if (_expandedGroups.contains(4)) ...[
                      if (_lihat('layanan.visitor'))
                        _buildSubMenuItem(
                          index: 43,
                          icon: Icons.badge_outlined,
                          label: isWarga ? 'Buku Tamu Saya' : 'E-Visitor',
                          isViewOnly: _hanyaLihat('layanan.visitor'),
                        ),
                      if (_lihat('layanan.surat'))
                        _buildSubMenuItem(
                          index: 44,
                          icon: Icons.description_outlined,
                          label: isWarga ? 'Pengajuan Surat' : 'Surat Menyurat',
                          isViewOnly: !isWarga && _hanyaLihat('layanan.surat'),
                        ),
                    ],
                  ],
                  if (_lihatSalahSatu(const ['kegiatan.agenda', 'kegiatan.ronda'])) ...[
                    _buildExpandableMenuItem(
                      groupIndex: 5,
                      icon: Icons.event_rounded,
                      label: 'Kegiatan & Info',
                    ),
                    if (_expandedGroups.contains(5)) ...[
                      if (_lihat('kegiatan.agenda'))
                        _buildSubMenuItem(
                          index: 50,
                          icon: Icons.event_available_rounded,
                          label: 'Agenda & Kegiatan',
                          isViewOnly: _hanyaLihat('kegiatan.agenda'),
                        ),
                      if (_lihat('kegiatan.ronda'))
                        _buildSubMenuItem(
                          index: 51,
                          icon: Icons.shield_outlined,
                          label: 'Jadwal & Absensi Ronda',
                          isViewOnly: _hanyaLihat('kegiatan.ronda'),
                        ),
                    ],
                  ],
                  if (_lihatSalahSatu(const [
                    'aspirasi.darurat',
                    'aspirasi.pengaduan',
                    'aspirasi.polling',
                  ])) ...[
                    _buildExpandableMenuItem(
                      groupIndex: 6,
                      icon: Icons.forum_rounded,
                      label: 'Aspirasi & Partisipasi',
                    ),
                    if (_expandedGroups.contains(6)) ...[
                      if (_lihat('aspirasi.darurat'))
                        _buildSubMenuItem(
                          index: 60,
                          icon: Icons.crisis_alert,
                          label: 'Status Darurat',
                          isViewOnly: _hanyaLihat('aspirasi.darurat'),
                        ),
                      if (_lihat('aspirasi.pengaduan'))
                        _buildSubMenuItem(
                          index: 61,
                          icon: Icons.error_outline_rounded,
                          label: 'Pengaduan',
                          isViewOnly: _hanyaLihat('aspirasi.pengaduan'),
                        ),
                      if (_lihat('aspirasi.polling'))
                        _buildSubMenuItem(
                          index: 62,
                          icon: Icons.bar_chart_rounded,
                          label: 'Polling Warga',
                          // Warga memang hanya punya `view`, tetapi ikut memilih
                          // dijaga `view` juga — jadi lencana "lihat saja" akan
                          // menyesatkan. Pada modul ini `create` berarti membuat
                          // polling, bukan menyuarakannya.
                          isViewOnly: !isWarga && _hanyaLihat('aspirasi.polling'),
                        ),
                    ],
                  ],

                  // Profil Saya tersedia untuk SEMUA role tanpa izin apa pun —
                  // setiap orang selalu boleh membuka profilnya sendiri.
                  ...[
                    _buildExpandableMenuItem(
                      groupIndex: 8,
                      icon: Icons.settings_rounded,
                      label: 'Pengaturan',
                    ),
                    if (_expandedGroups.contains(8)) ...[
                      _buildSubMenuItem(
                        index: 81,
                        icon: Icons.account_circle_rounded,
                        label: 'Profil Saya',
                      ),
                      if (isAdmin)
                        _buildSubMenuItem(
                          index: 82,
                          icon: Icons.manage_accounts_rounded,
                          label: 'Manajemen Pengguna',
                        ),
                      if (_lihat('pengaturan.log'))
                        _buildSubMenuItem(
                          index: 84,
                          icon: Icons.history_rounded,
                          label: 'Log Aktivitas',
                          isViewOnly: _hanyaLihat('pengaturan.log'),
                        ),
                      // Dua menu sistem: backend menolaknya untuk selain admin,
                      // apa pun isi tabel izin.
                      if (isAdmin)
                        _buildSubMenuItem(
                          index: 85,
                          icon: Icons.security_rounded,
                          label: 'Menu & Akses',
                        ),
                      if (isAdmin)
                        _buildSubMenuItem(
                          index: 86,
                          icon: Icons.warning_amber_rounded,
                          label: 'Reset',
                          iconColor: const Color(0xFFF87171),
                        ),
                    ],
                  ],
                ],
              ),
            ),

            // Logout Button
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildMenuItem(
                index: -1,
                icon: Icons.logout_rounded,
                label: 'Keluar',
                isLogout: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required int index,
    required IconData icon,
    required String label,
    bool isLogout = false,
  }) {
    final isSelected = widget.selectedIndex == index && !isLogout;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (isLogout) {
              widget.onLogout();
            } else {
              widget.onItemSelected(index);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.2)
                  : (isLogout ? Colors.red.withValues(alpha: 0.1) : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isLogout
                      ? const Color(0xFFFF3333)
                      : (isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6)),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isLogout
                          ? const Color(0xFFFF3333)
                          : (isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7)),
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableMenuItem({
    required int groupIndex,
    required IconData icon,
    required String label,
  }) {
    final isExpanded = _expandedGroups.contains(groupIndex);
    final isGroupSelected =
        widget.selectedIndex == groupIndex ||
        (widget.selectedIndex > groupIndex * 10 && widget.selectedIndex < (groupIndex + 1) * 10);
    final isHighlighted = isExpanded || isGroupSelected;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedGroups.remove(groupIndex);
              } else {
                _expandedGroups.add(groupIndex);
              }
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: isHighlighted ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        color: isHighlighted ? Colors.white : Colors.white.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isHighlighted
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 18,
                      ),
                    ],
                  ),
                ),
                if (isHighlighted)
                  Container(
                    width: 4,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Color(0xFFA7F3D0),
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubMenuItem({
    required int index,
    required IconData icon,
    required String label,
    double leftMargin = 16,
    Color? iconColor,
    bool isViewOnly = false,
  }) {
    final isSelected = widget.selectedIndex == index;

    return Container(
      margin: EdgeInsets.only(bottom: 2, left: leftMargin),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            widget.onItemSelected(index);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color:
                      iconColor ??
                      (isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6)),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
