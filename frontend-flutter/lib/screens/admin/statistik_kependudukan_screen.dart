import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/responsif.dart';
import '../../widgets/gradient_stat_card.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/tombol_kembali.dart';
import '../../../providers/demographic_provider.dart';
import '../../../models/demographic_model.dart';
import '../../core/theme/warna_konteks.dart';

/// Palet bersama untuk seluruh chart. Sebelumnya tiap chart memakai warna
/// hardcoded sendiri, sehingga kategori yang sama tampil beda warna antar chart.
const List<Color> _palet = [
  Color(0xFF0F766E),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFF59E0B),
  Color(0xFFF43F5E),
  Color(0xFF14B8A6),
  Color(0xFF6366F1),
  Color(0xFFEC4899),
  Color(0xFF84CC16),
  Color(0xFF06B6D4),
];

/// Abu-abu netral khusus kategori kosong, supaya tidak terlihat seperti
/// kategori sungguhan pada chart.
// Konstanta tingkat berkas tidak bisa memakai token tema (tidak ada `context`).
const Color _warnaKosong = Color(0xFF94A3B8);
const String _labelKosong = 'Tidak Diisi';

Color _warnaUntuk(String label, int index) =>
    label == _labelKosong ? _warnaKosong : _palet[index % _palet.length];

int _totalDari(List<KategoriStat> items) => items.fold(0, (sum, e) => sum + e.jumlah);

/// Pilih jarak antar garis bantu yang bulat, supaya sumbu kiri tidak
/// menampilkan angka desimal seperti 2.4 / 4.8 / 7.2.
double _intervalBulat(int nilaiTertinggi) {
  const langkah = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000];
  final kasar = nilaiTertinggi / 4;
  for (final l in langkah) {
    if (kasar <= l) return l.toDouble();
  }
  return (kasar / 1000).ceil() * 1000;
}

class StatistikKependudukanScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const StatistikKependudukanScreen({super.key, this.onBack});

  @override
  State<StatistikKependudukanScreen> createState() => _StatistikKependudukanScreenState();
}

class _StatistikKependudukanScreenState extends State<StatistikKependudukanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DemographicProvider>().fetchDemographics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DemographicProvider>();
    final data = provider.data;

    if (provider.isLoading && data == null) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
      );
    }

    if (provider.error != null || data == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              provider.error ?? 'Gagal memuat data statistik',
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.read<DemographicProvider>().fetchDemographics(),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    final summary = data.summary;
    final rentan = data.rentan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Section
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
                        Icons.pie_chart_outline_rounded,
                        color: Color(0xFF1B7A6A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Kependudukan / Statistik & Grafik',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: provider.isLoading ? null : () => provider.fetchDemographics(),
                    icon: provider.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_outlined, size: 18),
                    label: Text(provider.isLoading ? 'Memuat...' : 'Refresh Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // SECTION: RINGKASAN UTAMA
        _buildSectionTitle(Icons.people_outline, 'RINGKASAN UTAMA'),
        const SizedBox(height: 12),
        _buildResponsiveGrid([
          GradientStatCard(
            label: 'Total Jiwa',
            value: summary.totalWarga.toString(),
            subtitle: 'Warga aktif terdata',
            icon: Icons.people,
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          ),
          GradientStatCard(
            label: 'Total KK',
            value: summary.totalKk.toString(),
            subtitle: 'Kartu keluarga',
            icon: Icons.home,
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          ),
          GradientStatCard(
            label: 'Laki-laki',
            value: summary.lakiLaki.toString(),
            subtitle: _persenDari(summary.lakiLaki, summary.totalWarga),
            icon: Icons.male,
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          ),
          GradientStatCard(
            label: 'Perempuan',
            value: summary.perempuan.toString(),
            subtitle: _persenDari(summary.perempuan, summary.totalWarga),
            icon: Icons.female,
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          ),
          GradientStatCard(
            label: 'Total Rumah',
            value: '90 Rumah',
            subtitle: 'Fasilitas hunian',
            icon: Icons.other_houses_outlined,
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          ),
          GradientStatCard(
            label: 'Luas Wilayah',
            value: '2.5 Ha',
            subtitle: 'Cakupan lingkungan',
            icon: Icons.location_city_outlined,
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          ),
        ]),

        const SizedBox(height: 24),

        // SECTION: KELOMPOK RENTAN
        _buildSectionTitle(Icons.warning_amber_rounded, 'KELOMPOK RENTAN & SOSIAL'),
        const SizedBox(height: 12),
        _buildResponsiveGrid([
          _buildMiniCard('Balita (0-4 th)', rentan.balita.toString(), Icons.child_care, const [
            Color(0xFFF59E0B),
            Color(0xFFFBBF24),
          ]),
          _buildMiniCard('Lansia (≥60 th)', rentan.lansia.toString(), Icons.elderly, const [
            Color(0xFF8B5CF6),
            Color(0xFFA78BFA),
          ]),
          _buildMiniCard('Janda / Duda', rentan.jandaDuda.toString(), Icons.group, const [
            Color(0xFFF43F5E),
            Color(0xFFFB7185),
          ]),
          // Dihitung per kartu keluarga, bukan per jiwa — label menyebut KK
          // supaya tidak dikira jumlah orang.
          _buildMiniCard('KK Sewa/Kos', rentan.rumahSewaKos.toString(), Icons.house, const [
            Color(0xFF3B82F6),
            Color(0xFF60A5FA),
          ]),
        ], defaultCrossAxisCount: 4),

        const SizedBox(height: 24),

        // CHARTS GRID
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 800;
            final lebarKartu = isDesktop ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;

            Widget kartu(String judul, IconData ikon, Widget isi, {String? catatan}) => SizedBox(
              width: lebarKartu,
              child: _buildChartCard(judul, ikon, isi, catatan: catatan),
            );

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                kartu('Komposisi Gender', Icons.pie_chart, _buildPieChart(data.gender)),
                kartu(
                  'Status Domisili',
                  Icons.home_work,
                  _buildBarChart(data.domisili),
                  catatan: 'Dihitung per kartu keluarga',
                ),
                kartu(
                  'Kelompok Usia',
                  Icons.show_chart,
                  _buildBarChart(data.usia),
                  catatan: 'Berdasarkan tanggal lahir warga',
                ),
                kartu('Status Perkawinan', Icons.favorite, _buildPieChart(data.pernikahan)),
                kartu('Tingkat Pendidikan', Icons.school, _buildRankedList(data.pendidikan)),
                kartu('Mata Pencaharian', Icons.work, _buildRankedList(data.pekerjaan)),
                kartu('Komposisi Agama', Icons.mosque, _buildPieChart(data.agama)),
              ],
            );
          },
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  String _persenDari(int bagian, int total) {
    if (total == 0) return '';
    return '${(bagian / total * 100).toStringAsFixed(1)}% dari total';
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.teksKedua),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: context.teksKedua,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniCard(String label, String value, IconData icon, List<Color> gradientColors) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveGrid(
    List<Widget> cards, {
    int defaultCrossAxisCount = 4,
    double spacing = 16.0,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = ResponsiveLayout.isMobile(context)
            ? 1
            : (ResponsiveLayout.isTablet(context) ? 2 : defaultCrossAxisCount);

        double width = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;
        if (width < 0) width = constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildChartCard(String title, IconData icon, Widget chartWidget, {String? catatan}) {
    return Container(
      height: 360,
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
            children: [
              Icon(icon, size: 18, color: const Color(0xFF14B8A6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (catatan != null) ...[
            const SizedBox(height: 4),
            Text(catatan, style: TextStyle(fontSize: 11, color: context.teksTersier)),
          ],
          const SizedBox(height: 16),
          Expanded(child: chartWidget),
        ],
      ),
    );
  }

  // --- CHARTS IMPLEMENTATION ---

  /// Ditampilkan ketika seluruh kategori bernilai 0. Tanpa ini, `fl_chart`
  /// menggambar area kosong tanpa keterangan apa pun — inilah penyebab
  /// "blank page" pada chart Status Perkawinan.
  Widget _buildEmptyChart() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, size: 40, color: context.garis),
          SizedBox(height: 12),
          Text(
            'Data belum diisi',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.teksTersier),
          ),
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Lengkapi data pada menu Data Warga untuk menampilkan grafik ini.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.garis),
            ),
          ),
        ],
      ),
    );
  }

  /// Diagram batang untuk kategori berurutan dengan label pendek
  /// (Kelompok Usia, Status Domisili).
  Widget _buildBarChart(List<KategoriStat> items) {
    if (items.isEmpty || _totalDari(items) == 0) return _buildEmptyChart();

    final tertinggi = items.map((e) => e.jumlah).reduce((a, b) => a > b ? a : b);
    final interval = _intervalBulat(tertinggi);
    // Selalu sisakan satu tingkat di atas nilai tertinggi agar angka di atas
    // batang tidak terpotong.
    final maxY = ((tertinggi / interval).floor() + 1) * interval;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => context.teksUtama,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = items[group.x.toInt()];
              return BarTooltipItem(
                '${item.label}\n',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                children: [
                  TextSpan(
                    text: '${item.jumlah}',
                    style: const TextStyle(
                      color: Color(0xFF5EEAD4),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= items.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: SizedBox(
                    width: 64,
                    child: Text(
                      items[i].label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.teksKedua,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Angka di atas tiap batang, supaya terbaca tanpa perlu hover.
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 20,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= items.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${items[i].jumlah}',
                    style: TextStyle(
                      color: context.teksUtama,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              reservedSize: 32,
              // Hanya bilangan bulat; nilai pecahan diabaikan.
              getTitlesWidget: (value, meta) {
                if (value != value.roundToDouble()) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${value.toInt()}',
                    style: TextStyle(color: context.teksTersier, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(color: context.latarLembut, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(items.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: items[i].jumlah.toDouble(),
                color: _warnaUntuk(items[i].label, i),
                width: items.length > 5 ? 18 : 28,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: context.latarLembut,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// Donut + legend untuk komposisi dengan sedikit kategori
  /// (Gender, Perkawinan, Agama).
  Widget _buildPieChart(List<KategoriStat> items) {
    final total = _totalDari(items);
    if (items.isEmpty || total == 0) return _buildEmptyChart();

    // Kategori bernilai 0 tidak dirender agar tidak menghasilkan irisan
    // setipis garis yang labelnya saling tumpuk.
    final terpakai = <MapEntry<int, KategoriStat>>[];
    for (var i = 0; i < items.length; i++) {
      if (items[i].jumlah > 0) terpakai.add(MapEntry(i, items[i]));
    }

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              sections: terpakai.map((e) {
                final persen = e.value.jumlah / total * 100;
                return PieChartSectionData(
                  color: _warnaUntuk(e.value.label, e.key),
                  value: e.value.jumlah.toDouble(),
                  // Nama kategori pindah ke legend; irisan hanya memuat
                  // persentase, dan itu pun disembunyikan bila terlalu tipis.
                  title: persen >= 7 ? '${persen.toStringAsFixed(0)}%' : '',
                  radius: 46,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildLegend(terpakai),
      ],
    );
  }

  Widget _buildLegend(List<MapEntry<int, KategoriStat>> items) {
    return SizedBox(
      height: 58,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: items.map((e) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _warnaUntuk(e.value.label, e.key),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${e.value.label} (${e.value.jumlah})',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.teksKedua,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Daftar batang mendatar berperingkat untuk kategori yang banyak dan
  /// berlabel panjang (Pendidikan, Mata Pencaharian). Pie dengan 10+ irisan
  /// atau batang tegak dengan label "Belum/Tidak Bekerja" sama-sama tidak
  /// terbaca pada kartu selebar setengah layar.
  Widget _buildRankedList(List<KategoriStat> items) {
    final total = _totalDari(items);
    if (items.isEmpty || total == 0) return _buildEmptyChart();

    final tertinggi = items.map((e) => e.jumlah).reduce((a, b) => a > b ? a : b);
    final tampil = items.where((e) => e.jumlah > 0).toList();

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: tampil.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = tampil[i];
        final rasio = tertinggi == 0 ? 0.0 : item.jumlah / tertinggi;
        final persen = item.jumlah / total * 100;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.teksUtama,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${item.jumlah}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${persen.toStringAsFixed(0)}%)',
                  style: TextStyle(fontSize: 11, color: context.teksTersier),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: rasio,
                minHeight: 7,
                backgroundColor: context.latarLembut,
                valueColor: AlwaysStoppedAnimation<Color>(_warnaUntuk(item.label, i)),
              ),
            ),
          ],
        );
      },
    );
  }
}
