import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import '../../widgets/responsive_layout.dart';
import 'package:provider/provider.dart';
import '../../providers/bill_provider.dart';
import '../../providers/letter_provider.dart';
import '../../providers/finance_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/permission_provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../core/theme/warna_konteks.dart';

class WargaDashboardContent extends StatelessWidget {
  final AuthService auth;

  /// Dipanggil saat warga menekan kartu pintasan, diteruskan ke MainDashboard
  /// agar layar yang dituju terbuka. Tanpa ini seluruh pintasan hanya hiasan.
  final void Function(int menuIndex)? onPilihMenu;

  const WargaDashboardContent({super.key, required this.auth, this.onPilihMenu});

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final isTablet = ResponsiveLayout.isTablet(context);
    final bills = context.watch<BillProvider>();
    final letters = context.watch<LetterProvider>();
    final finances = context.watch<FinanceProvider>();
    final complaints = context.watch<ComplaintProvider>();

    final unpaidCount = bills.unpaidBills.length;
    final totalTunggakan = bills.unpaidBills.fold(0.0, (sum, item) => sum + item.nominal);
    final suratPending = letters.pendingCount;
    // Backend sudah menyaring pengaduan milik warga yang sedang masuk, jadi
    // yang tersisa tinggal menghitung yang belum selesai.
    final aduanAktif = complaints.complaints
        .where((c) => (c['status']?.toString() ?? '') != 'Selesai')
        .length;
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final totalTunggakanStr = formatter.format(totalTunggakan);
    final saldoKas = formatter.format(finances.summary?.saldo ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Greeting
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B7A6A), Color(0xFF0F766E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1B7A6A).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selamat Datang, ${auth.userName}! 👋',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kelola kebutuhan RT Anda dengan mudah.',
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Summary Cards
        //
        // Keempat kartu disusun sekali lalu ditata ulang menurut lebar layar.
        // Sebelumnya markupnya ditulis tiga kali — dan dua salinan untuk
        // tablet/ponsel masih memuat angka '0' yang ditulis mati, sehingga
        // warga di layar kecil selalu melihat "Sudah lunas" walau menunggak.
        _buildGridRingkasan(isDesktop, isTablet, [
          _buildSummaryCard(
            context,
            'Tagihan Belum Lunas',
            '$unpaidCount',
            unpaidCount == 0 ? 'Sudah lunas ✓' : 'Segera bayar',
            Icons.receipt_long_rounded,
            unpaidCount == 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            unpaidCount == 0 ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
          ),
          _buildSummaryCard(
            context,
            'Total Tunggakan',
            totalTunggakanStr,
            totalTunggakan == 0 ? 'Tidak ada tunggakan' : 'Tunggakan aktif',
            Icons.account_balance_wallet_outlined,
            const Color(0xFFF59E0B),
            const Color(0xFFFEF3C7),
          ),
          _buildSummaryCard(
            context,
            'Surat Dalam Proses',
            '$suratPending',
            suratPending == 0 ? 'Tidak ada pengajuan' : 'Menunggu persetujuan',
            Icons.description_outlined,
            const Color(0xFF3B82F6),
            const Color(0xFFDBEAFE),
          ),
          _buildSummaryCard(
            context,
            'Pengaduan Aktif',
            '$aduanAktif',
            aduanAktif == 0 ? 'Semua terselesaikan' : 'Sedang ditangani',
            Icons.support_agent_rounded,
            const Color(0xFF8B5CF6),
            const Color(0xFFEDE9FE),
          ),
        ]),

        const SizedBox(height: 24),

        // Saldo Kas RT Banner
        _buildSaldoKasBanner(saldoKas),

        const SizedBox(height: 24),

        // Pengumuman Terbaru (Full Width)
        _buildPengumumanCard(context),

        const SizedBox(height: 24),

        // Quick Menu
        Text(
          'Menu Cepat',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.teksUtama),
        ),
        const SizedBox(height: 16),
        _buildQuickMenuGrid(context),
      ],
    );
  }

  /// Empat di satu baris pada desktop, dua kolom pada tablet, bertumpuk pada
  /// ponsel — memakai kartu yang sama, bukan tiga salinan markup.
  Widget _buildGridRingkasan(bool isDesktop, bool isTablet, List<Widget> kartu) {
    if (isDesktop) {
      return Row(
        children: [
          for (int i = 0; i < kartu.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: kartu[i]),
          ],
        ],
      );
    }

    if (isTablet) {
      return Column(
        children: [
          for (int i = 0; i < kartu.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: kartu[i]),
                const SizedBox(width: 16),
                if (i + 1 < kartu.length)
                  Expanded(child: kartu[i + 1])
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ],
      );
    }

    return Column(
      children: [
        for (int i = 0; i < kartu.length; i++) ...[if (i > 0) const SizedBox(height: 16), kartu[i]],
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    Color bgColor,
  ) {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.teksKedua,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: context.teksTersier)),
        ],
      ),
    );
  }

  Widget _buildSaldoKasBanner(String saldoKas) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFA7F3D0),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.account_balance_wallet, color: Color(0xFF047857), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SALDO KAS RT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF047857),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  saldoKas,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF065F46),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => onPilihMenu?.call(22),
            icon: const Icon(Icons.bar_chart, size: 16),
            label: const Text('Lihat Laporan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF047857),
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: const Color(0xFF047857).withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPengumumanCard(BuildContext context) {
    final agendaProvider = context.watch<AgendaProvider>();
    final agendaList = agendaProvider.agendaList;

    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.campaign_rounded, color: Color(0xFFD97706), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Pengumuman Terbaru',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.teksUtama,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => onPilihMenu?.call(50),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Lihat Semua',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1B7A6A),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF1B7A6A)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (agendaProvider.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (agendaList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.campaign_outlined, size: 36, color: context.teksTersier.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text(
                      'Belum ada pengumuman terbaru',
                      style: TextStyle(fontSize: 13, color: context.teksTersier),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(
              agendaList.length > 4 ? 4 : agendaList.length,
              (index) {
                final item = agendaList[index];
                final title = item['judul']?.toString() ?? 'Pengumuman';
                final tipe = item['tipe']?.toString();

                String subtitle = '';
                if (item['tanggal'] != null && item['tanggal'].toString().isNotEmpty) {
                  try {
                    final dt = DateTime.parse(item['tanggal'].toString());
                    subtitle += DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(dt);
                  } catch (_) {
                    subtitle += item['tanggal'].toString();
                  }
                }
                if (item['waktu_mulai'] != null && item['waktu_mulai'].toString().isNotEmpty) {
                  subtitle += ' pukul ${item['waktu_mulai']}';
                }
                if (item['lokasi'] != null && item['lokasi'].toString().isNotEmpty) {
                  subtitle += ' · ${item['lokasi']}';
                }
                if (subtitle.isEmpty) {
                  subtitle = item['deskripsi']?.toString() ?? '-';
                }

                IconData icon = Icons.campaign_rounded;
                Color color = const Color(0xFFD97706);
                if (tipe?.toLowerCase() == 'kegiatan' || title.toLowerCase().contains('bakti')) {
                  icon = Icons.construction_rounded;
                  color = const Color(0xFF0F766E);
                } else if (tipe?.toLowerCase() == 'iuran' || title.toLowerCase().contains('iuran')) {
                  icon = Icons.payments_rounded;
                  color = const Color(0xFFEF4444);
                } else if (tipe?.toLowerCase() == 'rapat' || title.toLowerCase().contains('rapat')) {
                  icon = Icons.groups_rounded;
                  color = const Color(0xFF3B82F6);
                }

                final isLast = index == (agendaList.length > 4 ? 4 : agendaList.length) - 1;

                return Column(
                  children: [
                    _buildPengumumanItem(
                      context,
                      title,
                      subtitle,
                      icon,
                      color,
                      onTap: () => onPilihMenu?.call(50),
                    ),
                    if (!isLast) Divider(height: 24, color: context.latarLembut),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // `context` diterima sebagai parameter: pembantu ini bukan `build`, jadi ia
  // tidak punya akses ke context milik State.
  Widget _buildPengumumanItem(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.teksUtama,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: context.teksTersier),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.garis, size: 20),
          ],
        ),
      ),
    );
  }



  Widget _buildQuickMenuGrid(BuildContext context) {
    // `menu` adalah indeks yang dikenali MainDashboard._buildBody. Pengumuman
    // menumpang layar Agenda & Kegiatan (50), sesuai penggabungan keduanya.
    final permissions = context.watch<PermissionProvider>();
    final menus = [
      {
        'icon': Icons.receipt_long,
        'title': 'Iuran Saya',
        'subtitle': 'Lihat & Bayar',
        'color': const Color(0xFF14B8A6),
        'bgColor': const Color(0xFFCCFBF1),
        'menu': 21,
      },
      {
        'icon': Icons.description_outlined,
        'title': 'Ajukan Surat',
        'subtitle': 'Permohonan Baru',
        'color': const Color(0xFF3B82F6),
        'bgColor': const Color(0xFFDBEAFE),
        'menu': 44,
      },
      if (permissions.bolehLihat('layanan.visitor'))
        {
          'icon': Icons.badge_outlined,
          'title': 'E-Visitor',
          'subtitle': 'Buku Tamu',
          'color': const Color(0xFF10B981),
          'bgColor': const Color(0xFFD1FAE5),
          'menu': 43,
        },
      {
        'icon': Icons.campaign_rounded,
        'title': 'Pengumuman',
        'subtitle': 'Lihat Info',
        'color': const Color(0xFF8B5CF6),
        'bgColor': const Color(0xFFEDE9FE),
        'menu': 50,
      },
      {
        'icon': Icons.error_outline_rounded,
        'title': 'Pengaduan',
        'subtitle': 'Laporkan',
        'color': const Color(0xFFEF4444),
        'bgColor': const Color(0xFFFEE2E2),
        'menu': 61,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ResponsiveLayout.isDesktop(context)
            ? 4
            : ResponsiveLayout.isTablet(context)
            ? 2
            : 1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: ResponsiveLayout.isDesktop(context) ? 2.5 : 3.0,
      ),
      itemCount: menus.length,
      itemBuilder: (context, index) {
        final menu = menus[index];
        return InkWell(
          onTap: () => onPilihMenu?.call(menu['menu'] as int),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.all(paddingKartu(context)),
            decoration: BoxDecoration(
              color: context.latarKartu,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.garis),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: menu['bgColor'] as Color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(menu['icon'] as IconData, color: menu['color'] as Color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        menu['title'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: menu['color'] as Color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        menu['subtitle'] as String,
                        style: TextStyle(fontSize: 11, color: context.teksTersier),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
