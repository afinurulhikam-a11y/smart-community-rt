import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/websocket_service.dart';
import '../../providers/aksi_utama_provider.dart';
import '../../providers/tema_provider.dart';
import '../../core/theme/warna_konteks.dart';
import '../../providers/finance_provider.dart';
import '../../providers/bill_provider.dart';
import '../../providers/letter_provider.dart';
import '../../providers/emergency_provider.dart';
import '../../models/emergency_model.dart';
import '../../providers/demographic_provider.dart';
import '../../providers/bop_provider.dart';
import '../../providers/permission_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/warga_provider.dart';
import '../../providers/bantuan_sosial_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/visitor_provider.dart';
import '../../providers/announcement_provider.dart';

import '../../providers/polling_provider.dart';
import '../../providers/log_provider.dart';
import '../../widgets/navigasi_bawah.dart';
import '../../widgets/sidebar_menu.dart';
import '../../widgets/gradient_stat_card.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/banner_offline.dart';
import 'data_warga_screen.dart';
import 'bantuan_sosial_screen.dart';
import 'statistik_kependudukan_screen.dart';
import 'iuran_warga_screen.dart';
import 'kas_rt_screen.dart';
import 'bop_screen.dart';
import 'data_barang_screen.dart';
import 'peminjaman_screen.dart';
import 'e_visitor_screen.dart';
import 'surat_menyurat_screen.dart';
import 'agenda_kegiatan_screen.dart';

import 'pengaduan_screen.dart';
import 'status_darurat_screen.dart';
import 'polling_warga_screen.dart';

import 'profil_saya_screen.dart';
import 'log_aktivitas_screen.dart';
import 'menu_akses_screen.dart';
import 'reset_sistem_screen.dart';

import '../warga/warga_dashboard_content.dart';
import '../warga/bill_list_screen.dart';
import '../warga/finance_report_screen.dart';
import '../warga/letter_request_screen.dart';
import '../../core/pesan.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedMenuIndex = 0;
  final List<int> _menuHistory = [];
  String _chartDataSource = 'Kas RT';
  bool _isEmergencyDialogShowing = false;
  final Set<String> _dismissedPopupAlertIds = {};
  final Set<String> _dismissingAlertIds = {};

  /// Dibaca dari tema, bukan disimpan sendiri.
  ///
  /// Dulu ini `bool _isDarkMode` milik layar ini saja, dengan dua akibat:
  /// pilihannya hilang setiap aplikasi ditutup, dan hanya bagian di bawah
  /// pembungkus `Theme()` yang ikut menggelap. Sekarang temanya dipasang di
  /// akar `MaterialApp`, jadi cukup menanyakannya — pola yang sama sudah
  /// dipakai delapan layar lain.
  bool get _gelap => Theme.of(context).brightness == Brightness.dark;

  void _gantiTema() => context.read<TemaProvider>().ganti();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WebSocketService>().connect();
      _loadData();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _loadData() {
    final izin = context.read<PermissionProvider>();
    final auth = context.read<AuthService>();
    if (auth.userRole.isNotEmpty) {
      izin.setRole(auth.userRole);
    }

    if (izin.bolehLihat('keuangan.iuran', userRole: auth.userRole)) {
      context.read<BillProvider>().fetchBills();
      context.read<BillProvider>().fetchStatsBulanIni();
    }
    if (izin.bolehLihat('keuangan.kas', userRole: auth.userRole)) {
      context.read<FinanceProvider>().fetchTransactions();
      // Summary dashboard SELALU seluruh masa: card SALDO KAS menampilkan
      // "saldo kas RT", bukan angka yang ikut tersaring filter 'Non Iuran'
      // atau bulan yang dipilih pengurus di layar Kas RT. fetchTransactions
      // memanggil fetchSummary dengan _filterAktif; di sini dipanggil lagi
      // secara eksplisit tanpa filter supaya card-nya independen.
      context.read<FinanceProvider>().fetchSummary(bulan: null, sumber: null);
      context.read<FinanceProvider>().fetchBulanan();
    }
    if (izin.bolehLihat('layanan.surat', userRole: auth.userRole)) {
      context.read<LetterProvider>().fetchLetters();
    }
    if (izin.bolehLihat('aspirasi.darurat', userRole: auth.userRole)) {
      context.read<EmergencyProvider>().fetchAlerts();
    }
    // Dipakai kartu "Pengaduan Aktif" pada dashboard warga.
    if (izin.bolehLihat('aspirasi.pengaduan', userRole: auth.userRole)) {
      context.read<ComplaintProvider>().fetchComplaints();
    }
    if (izin.bolehLihat('keuangan.bop', userRole: auth.userRole)) {
      context.read<BopProvider>().fetchSummary();
      context.read<BopProvider>().fetchTransactions();
      context.read<BopProvider>().fetchBulanan();
    }
    if (izin.bolehLihat('kependudukan.statistik', userRole: auth.userRole) || izin.bolehLihat('kependudukan.warga', userRole: auth.userRole)) {
      context.read<DemographicProvider>().fetchDemographics();
    }
    if (izin.bolehLihat('kegiatan.agenda', userRole: auth.userRole)) {
      context.read<AgendaProvider>().fetchAgenda();
    }
  }

  /// Muat ulang data milik layar yang SEDANG dibuka.
  ///
  /// `RefreshIndicator` di bawah membungkus seluruh badan dashboard, tetapi
  /// dulu selalu memanggil `_loadData()` — yang hanya menyegarkan delapan
  /// provider milik layar Beranda. Akibatnya menarik-untuk-menyegarkan di Data
  /// Warga, Data Barang, Peminjaman, E-Visitor, Siskamling, Polling, Log
  /// Aktivitas, dan Bantuan Sosial memutar indikatornya lalu tidak melakukan
  /// apa pun terhadap yang terlihat di layar.
  ///
  /// Gerakan yang berputar tanpa hasil lebih buruk daripada tidak ada gerakan
  /// sama sekali: ia meyakinkan pengguna bahwa datanya baru.
  ///
  /// Indeksnya sama persis dengan yang dipakai sidebar dan `_buildBody`, jadi
  /// tidak ada registri menu kedua yang harus dijaga tetap seiring.
  Future<void> _muatUlangLayarAktif() async {
    // Provider diambil SEBELUM await mana pun. Membaca `context` setelah
    // sebuah await berisiko: widget-nya bisa sudah dilepas ketika baris itu
    // dijalankan, dan analyzer menandainya sebagai use_build_context_synchronously.
    final warga = context.read<WargaProvider>();
    final bansos = context.read<BantuanSosialProvider>();
    final demografi = context.read<DemographicProvider>();
    final tagihan = context.read<BillProvider>();
    final kas = context.read<FinanceProvider>();
    final bop = context.read<BopProvider>();
    final inventaris = context.read<InventoryProvider>();
    final tamu = context.read<VisitorProvider>();
    final surat = context.read<LetterProvider>();
    final agenda = context.read<AgendaProvider>();
    final pengumuman = context.read<AnnouncementProvider>();

    final darurat = context.read<EmergencyProvider>();
    final pengaduan = context.read<ComplaintProvider>();
    final polling = context.read<PollingProvider>();
    final log = context.read<LogProvider>();

    switch (_selectedMenuIndex) {
      case 12:
        await warga.fetchWarga();
      case 13:
        await bansos.fetchBantuanSosial();
      case 14:
        await demografi.fetchDemographics();
      case 21:
        await tagihan.fetchBills();
        await tagihan.fetchStatsBulanIni();
      case 22:
        await kas.refresh();
        await kas.fetchBulanan();
      case 23:
        await bop.refresh();
        await bop.fetchBulanan();
      case 31:
      case 32:
        await inventaris.fetchInventory();
      case 43:
        await tamu.fetchVisitors();
      case 44:
        await surat.fetchLetters();
      case 50:
        await agenda.fetchAgenda();
        await pengumuman.fetchAnnouncements();

      case 60:
        await darurat.fetchAlerts();
      case 61:
        await pengaduan.fetchComplaints();
      case 62:
        await polling.fetchPolling();

        await log.fetchLogs();
      default:
        // Beranda (0) dan layar tanpa daftar sendiri — Profil, Menu & Akses,
        // Reset Sistem — jatuh ke pemuatan dashboard.
        _loadData();
    }
  }

  void _showEmergencyPopup(Map<String, dynamic>? wsAlarm, EmergencyModel? activeAlertObj) {
    final alertId = wsAlarm?['alert_id']?.toString() ?? activeAlertObj?.id;
    if (alertId != null && (_dismissedPopupAlertIds.contains(alertId) || _dismissingAlertIds.contains(alertId))) {
      return;
    }
    if (_isEmergencyDialogShowing) return;
    _isEmergencyDialogShowing = true;

    final message = wsAlarm?['message'] ?? activeAlertObj?.message ?? 'Warga membutuhkan bantuan!';
    final sender = wsAlarm?['nama'] ?? activeAlertObj?.namaWarga ?? 'Seseorang';
    final phone = wsAlarm?['no_hp'] ?? activeAlertObj?.noHp ?? '-';
    final address = wsAlarm?['alamat'] ?? activeAlertObj?.alamat ?? '-';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade900.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                '🚨 PERINGATAN DARURAT AKTIF 🚨',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.latarKartu,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 18, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pelapor: $sender',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: context.teksUtama),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 18, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Text('No HP: $phone', style: TextStyle(fontSize: 13, color: context.teksKedua)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.home, size: 18, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Alamat: $address', style: TextStyle(fontSize: 13, color: context.teksKedua)),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Text('Pesan / Detail Kejadian:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.teksKedua)),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.teksUtama),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Builder(
                builder: (ctx) {
                  final izin = context.read<PermissionProvider>();
                  final bisaKelola = izin.bolehLihat('aspirasi.darurat');

                  if (!bisaKelola) {
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (alertId != null) _dismissedPopupAlertIds.add(alertId);
                          _isEmergencyDialogShowing = false;
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFDC2626),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Saya Mengerti', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            if (alertId != null) _dismissedPopupAlertIds.add(alertId);
                            _isEmergencyDialogShowing = false;
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Tutup Popup'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _showResolvePinModal(alertId, ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFDC2626),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Selesaikan Alarm', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      _isEmergencyDialogShowing = false;
    });
  }

  void _showResolvePinModal(String? alertId, BuildContext parentCtx) {
    final pinController = TextEditingController();
    String? pinError;

    showDialog(
      context: context,
      builder: (pinCtx) => StatefulBuilder(
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
                            'Verifikasi Keamanan 2-Langkah',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.teksUtama),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Konfirmasi Penutupan Alarm Darurat',
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        onPressed: () => Navigator.pop(pinCtx),
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
                          if (alertId != null) {
                            final success = await provider.dismissAlarm(alertId, pin: pin);
                            if (mounted) {
                              if (success) {
                                _dismissingAlertIds.add(alertId);
                                _dismissedPopupAlertIds.add(alertId);
                                if (pinCtx.mounted) Navigator.pop(pinCtx);
                                _isEmergencyDialogShowing = false;
                                if (parentCtx.mounted) Navigator.pop(parentCtx);

                                tampilkanPesanDi(
                                  messenger,
                                  'Status darurat telah diselesaikan.',
                                  sukses: true,
                                );
                              } else {
                                setModalState(() {
                                  pinError = provider.errorMessage ?? 'PIN Keamanan salah! Penutupan dibatalkan.';
                                });
                              }
                            }
                          }
                        },
                        child: const Text('Verifikasi & Selesaikan', style: TextStyle(fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isDesktop = ResponsiveLayout.isDesktop(context);
    // WebSocketService SENGAJA tidak di-watch di sini — lihat Builder di bawah.
    //
    // Ia memanggil notifyListeners pada SETIAP pesan masuk, termasuk pesan
    // CONNECTED dan tipe apa pun yang ditambahkan kelak, bukan hanya alarm.
    // Meng-watch-nya di tingkat ini membangun ulang seluruh dashboard setiap
    // kali — dan SidebarMenu (554 baris, memeriksa izin untuk setiap item)
    // ikut terbawa karena ia bukan const.
    //
    // Watch-nya dipindahkan ke dalam Builder yang benar-benar memakainya,
    // sehingga pesan WebSocket hanya membangun ulang bagian alarm.
    final emergency = context.watch<EmergencyProvider>();

    final warga = auth.userRole == 'warga';
    final izin = context.watch<PermissionProvider>();
    final tujuan = tujuanNavigasi(warga: warga, izin: izin);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.latarHalaman,

      // AppBar sungguhan, bukan Row buatan sendiri. Ini yang memberi judul
      // halaman, tombol kembali, dan bayangan-saat-digulir seperti aplikasi
      // Android lain — semuanya dulu tidak ada.
      appBar: isDesktop ? null : _appBar(auth, warga),

      // FAB hanya di ponsel. Di desktop tombolnya sudah ada di bilah layar,
      // dan tombol mengambang di sudut layar lebar justru mengganggu.
      floatingActionButton: isDesktop ? null : _fab(),

      // Navigasi bawah hanya di ponsel; di desktop sidebar yang berperan.
      bottomNavigationBar: isDesktop
          ? null
          : NavigasiBawah(
              tujuan: tujuan,
              indeksMenuTerpilih: _selectedMenuIndex,
              onPilihMenu: (i) => _pilihMenu(i),
              onBukaLaci: () => _scaffoldKey.currentState?.openDrawer(),
            ),

      drawer: isDesktop
          ? null
          : Drawer(
              child: SidebarMenu(
                selectedIndex: _selectedMenuIndex,
                role: auth.userRole,
                onItemSelected: (index) {
                  _pilihMenu(index);
                  Navigator.pop(context); // Close drawer
                },
                onLogout: () => auth.logout(),
              ),
            ),
      body: Column(
        children: [
          Builder(
            builder: (context) {
              // Builder memberi BuildContext-nya sendiri, jadi watch di sini
              // membatasi pembangunan ulang pada subtree ini saja.
              final ws = context.watch<WebSocketService>();
              final activeFromWs = ws.hasActiveAlarm;
              final activeAlertObj = emergency.activeAlert;
              final hasActive = activeFromWs || activeAlertObj != null;

              final alertId = activeAlertObj?.id ?? ws.lastAlarm?['alert_id']?.toString() ?? ws.lastAlarm?['id']?.toString();
              final isDismissed = alertId != null && (_dismissedPopupAlertIds.contains(alertId) || _dismissingAlertIds.contains(alertId));

              if (hasActive && !isDismissed && !_isEmergencyDialogShowing) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isEmergencyDialogShowing) {
                    final currentAlertId = emergency.activeAlert?.id ?? ws.lastAlarm?['alert_id']?.toString() ?? ws.lastAlarm?['id']?.toString();
                    if (currentAlertId != null && (_dismissedPopupAlertIds.contains(currentAlertId) || _dismissingAlertIds.contains(currentAlertId))) {
                      return;
                    }
                    _showEmergencyPopup(ws.lastAlarm, activeAlertObj);
                  }
                });
              }

              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: Row(
              children: [
                // Sidebar (only on desktop)
                if (isDesktop)
                  SidebarMenu(
                    selectedIndex: _selectedMenuIndex,
                    role: auth.userRole,
                    onItemSelected: (index) {
                      _pilihMenu(index);
                    },
                    onLogout: () => auth.logout(),
                  ),

                // Main Content
                Expanded(
                  child: Column(
                    children: [
                      // Bilah judul lama hanya untuk desktop; di ponsel
                      // digantikan AppBar milik Scaffold.
                      if (isDesktop) _buildHeaderBar(auth),

                      // Scrollable Content
                      //
                      // Tidak ada lagi pembungkus `Theme()` di sini. Temanya
                      // dipasang di akar `MaterialApp`, sehingga AppBar, laci,
                      // navigasi bawah, dan setiap dialog ikut menggelap —
                      // dulu semuanya tertinggal terang karena berada di LUAR
                      // pembungkus ini.
                      Expanded(
                        // Tarik-untuk-muat-ulang: gerakan yang dicoba orang
                        // secara refleks di aplikasi Android, dan sebelumnya
                        // tidak melakukan apa pun di sini.
                        child: RefreshIndicator(
                          onRefresh: _muatUlangLayarAktif,
                          child: SingleChildScrollView(
                            // Selalu bisa digulir, walau isinya pendek —
                            // kalau tidak, gerakan tariknya tidak tertangkap
                            // di layar yang isinya sedikit.
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.all(paddingKonten(context)),
                            // Pita status jaringan di ATAS setiap layar.
                            //
                            // Cache dan antrean offline membuat aplikasi tetap
                            // berguna tanpa sinyal, tetapi keduanya berbahaya
                            // bila bekerja diam-diam: data lama tampak persis
                            // seperti data baru, dan pengaduan yang masih di
                            // antrean tampak sudah terkirim. Aplikasi boleh
                            // menolong tanpa diminta, tidak boleh diam soal
                            // keadaan datanya.
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const BannerOffline(),
                                _buildBody(auth),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pindah menu, sekaligus melepas aksi utama layar sebelumnya.
  ///
  /// Tanpa `lepas()`, layar yang tidak punya aksi utama akan mewarisi FAB milik
  /// layar sebelumnya — misalnya tombol "Pemasukan" tertinggal di Statistik.
  /// Layar tujuan yang memang punya aksi akan memasangnya kembali pada build
  /// yang sama, jadi tombolnya tidak berkedip.
  void _pilihMenu(int indeks, {bool isBack = false}) {
    context.read<AksiUtamaProvider>().lepas();
    if (!isBack && _selectedMenuIndex != indeks) {
      _menuHistory.add(_selectedMenuIndex);
    }
    setState(() => _selectedMenuIndex = indeks);

    // Kembali ke Beranda berarti memuat ulang kartu ringkasannya.
    //
    // Setiap layar modul adalah widget tersendiri yang mengambil datanya di
    // `initState`, jadi berpindah ke sana sudah otomatis menyegarkan. Beranda
    // TIDAK: isinya dibangun sebaris di `_buildBody`, tanpa initState, jadi
    // angkanya bertahan sejak terakhir kali dimuat.
    //
    // Akibatnya menambah warga di Data Warga lalu kembali ke Beranda tetap
    // menampilkan jumlah yang lama — datanya benar di server, yang basi hanya
    // yang di layar. Itu terlihat persis seperti angka yang salah hitung.
    if (indeks == 0) _loadData();
  }

  void _kembaliMenu() {
    if (_menuHistory.isNotEmpty) {
      final prev = _menuHistory.removeLast();
      _pilihMenu(prev, isBack: true);
    } else {
      _pilihMenu(0, isBack: true);
    }
  }

  /// Tombol aksi utama layar yang sedang terbuka.
  ///
  /// Isinya didaftarkan oleh layar itu sendiri lewat [AksiUtamaProvider] —
  /// layar bukan Scaffold, jadi ia tidak bisa memasang FAB-nya sendiri.
  /// Layar yang tidak mendaftarkan apa pun tidak memunculkan tombol.
  Widget? _fab() {
    final aksi = context.watch<AksiUtamaProvider>();
    if (!aksi.ada) return null;

    return FloatingActionButton.extended(
      onPressed: aksi.aksi,
      icon: Icon(aksi.ikon),
      label: Text(aksi.label!),
    );
  }

  /// AppBar ponsel.
  ///
  /// Judulnya mengikuti menu yang sedang dibuka, bukan selalu "Dashboard" —
  /// sebelumnya bilah atas menampilkan tulisan itu di semua layar, sehingga
  /// pengguna kehilangan penanda sedang berada di mana.
  ///
  /// Tanggal dan jam yang dulu memenuhi bilah ini dipindahkan ke kartu sambutan
  /// di Beranda: di ponsel ruangnya terlalu berharga untuk jam berdetik.
  PreferredSizeWidget _appBar(AuthService auth, bool warga) {
    final diBeranda = _selectedMenuIndex == 0;

    return AppBar(
      // Di layar selain Beranda, panah kembali ke Beranda lebih sesuai
      // kebiasaan Android daripada ikon hamburger di setiap halaman.
      leading: diBeranda
          ? IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Menu',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Kembali',
              onPressed: () => _pilihMenu(0),
            ),
      title: Text(judulMenu(_selectedMenuIndex, warga: warga)),
      actions: [
        IconButton(
          tooltip: _gelap ? 'Mode terang' : 'Mode gelap',
          icon: Icon(_gelap ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: _gantiTema,
        ),
        IconButton(
          tooltip: 'Profil Saya',
          icon: const CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.primaryColor,
            child: Icon(Icons.person, color: Colors.white, size: 16),
          ),
          onPressed: () => _pilihMenu(81),
        ),
        const SizedBox(width: AppTheme.spasiXs),
      ],
    );
  }

  Widget _buildHeaderBar(AuthService auth) {
    final sempit = ResponsiveLayout.isMobile(context);
    final bool warga = auth.userRole == 'warga';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: sempit ? 8 : 24, vertical: 16),
      color: context.latarKartu,
      child: Row(
        children: [
          // Hamburger Menu (Mobile/Tablet only)
          if (!ResponsiveLayout.isDesktop(context)) ...[
            IconButton(
              icon: Icon(Icons.menu, color: context.teksUtama),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            SizedBox(width: sempit ? 4 : 16),
          ],

          // Title + Date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  judulMenu(_selectedMenuIndex, warga: warga),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: sempit ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: context.teksUtama,
                  ),
                ),
                const SizedBox(height: 2),
                RealTimeClockText(
                  isMobile: sempit,
                  isDarkMode: _gelap,
                ),
              ],
            ),
          ),

          // Tombol mode gelap.
          //
          // IconButton, bukan GestureDetector: bentuk lamanya tidak punya
          // sasaran sentuh 48dp, tidak punya tooltip, dan tidak terbaca
          // pembaca layar.
          IconButton(
            onPressed: _gantiTema,
            tooltip: _gelap ? 'Mode terang' : 'Mode gelap',
            style: IconButton.styleFrom(
              backgroundColor: context.latarLembut,
              shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusS),
            ),
            icon: Icon(
              _gelap ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: _gelap ? Colors.amber : context.teksKedua,
              size: 20,
            ),
          ),
          SizedBox(width: sempit ? 8 : 16),

          // User Info
          //
          // Nama role disembunyikan di ponsel. Teksnya tanpa batas lebar —
          // "Administrator" saja sudah sekitar 90px — dan itu diambil langsung
          // dari jatah judul. Avatar di sebelahnya sudah menandakan akun, dan
          // nama role tetap terbaca di menu Profil Saya.
          // User Info & Avatar (Klik untuk membuka Profil Saya)
          InkWell(
            onTap: () => _pilihMenu(81),
            borderRadius: BorderRadius.circular(24),
            child: Tooltip(
              message: 'Buka Profil Saya (${_getRoleDisplayName(auth.userRole)})',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!sempit) ...[
                      Text(
                        auth.userName.isNotEmpty ? auth.userName : _getRoleDisplayName(auth.userRole),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.teksUtama,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFF1B7A6A),
                      child: Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'pengurus_rt':
        return 'Pengurus RT';
      case 'ketua_rt':
        return 'Ketua RT';
      case 'sekretaris':
        return 'Sekretaris';
      case 'bendahara':
        return 'Bendahara';
      case 'warga':
        return 'Warga RT';
      default:
        return 'Pengguna';
    }
  }

  Widget _buildBody(AuthService auth) {
    final bool warga = auth.userRole == 'warga';

    if (warga && _selectedMenuIndex == 0) {
      return WargaDashboardContent(
        auth: auth,
        onPilihMenu: (i) => _pilihMenu(i),
      );
    }

    switch (_selectedMenuIndex) {
      case 12:
        return DataWargaScreen(onBack: _kembaliMenu);
      case 13:
        return BantuanSosialScreen(onBack: _kembaliMenu);
      case 14:
        return StatistikKependudukanScreen(onBack: _kembaliMenu);

      // Tiga modul di bawah punya dua wajah. Indeks menunya sama untuk semua
      // role — sidebar tidak perlu tahu — dan role yang menentukan layarnya:
      // warga melihat miliknya sendiri, pengurus mengelola milik seluruh RT.
      case 21:
        return warga ? const BillListScreen() : IuranWargaScreen(onBack: _kembaliMenu);
      case 22:
        return warga ? const FinanceReportScreen() : KasRtScreen(onBack: _kembaliMenu);

      case 23:
        return BopScreen(onBack: _kembaliMenu);
      case 31:
        return DataBarangScreen(onBack: _kembaliMenu);
      case 32:
        return PeminjamanScreen(onBack: _kembaliMenu);
      case 43:
        return warga ? const EVisitorScreen(isWarga: true) : EVisitorScreen(onBack: _kembaliMenu);
      case 44:
        return warga ? const LetterRequestScreen() : SuratMenyuratScreen(onBack: _kembaliMenu);
      case 50:
        return AgendaKegiatanScreen(onBack: _kembaliMenu);
      case 60:
        return StatusDaruratScreen(onBack: _kembaliMenu);
      case 61:
        return PengaduanScreen(onBack: _kembaliMenu);
      case 62:
        return PollingWargaScreen(onBack: _kembaliMenu);

      case 81:
        return const ProfilSayaScreen();

      case 84:
        return const LogAktivitasScreen();
      case 85:
        return const MenuAksesScreen();
      case 86:
        return const ResetSistemScreen();

      default:
        return _buildDashboardContent(auth);
    }
  }

  Widget _buildDashboardContent(AuthService auth) {
    final finance = context.watch<FinanceProvider>();
    final bills = context.watch<BillProvider>();
    // Sumber yang sama dengan layar Statistik & Data Warga, supaya angkanya
    // tidak pernah berbeda antar layar.
    final demografi = context.watch<DemographicProvider>();
    final izin = context.watch<PermissionProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Welcome Section
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selamat Datang, ${auth.userRoleLabel}!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: context.teksUtama,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.grid_view_rounded, color: const Color(0xFF1B7A6A), size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Sistem Manajemen RT Terintegrasi',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFF1B7A6A).withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 24),

        // === STAT CARDS ===
        // Setiap kartu mengarah ke sebuah modul, jadi hanya ditampilkan bila
        // modulnya boleh dibuka. Tanpa ini bendahara diarahkan ke layar yang
        // backend-nya menolak, dan angkanya pun kosong karena datanya 403.
        _buildResponsiveGrid([
          if (izin.bolehLihat('kependudukan.warga'))
            GradientStatCard(
              label: 'TOTAL WARGA',
              value: (demografi.data?.summary.totalWarga ?? 0).toString(),
              subtitle: 'Warga terdaftar',
              icon: Icons.group,
              gradientColors: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
              onTap: () => _pilihMenu(12),
            ),
          if (izin.bolehLihat('keuangan.kas'))
            GradientStatCard(
              label: 'SALDO KAS',
              value: _formatRupiah(finance.summary?.saldo ?? 0),
              subtitle: 'Saldo kas RT',
              icon: Icons.savings,
              gradientColors: const [Color(0xFF059669), Color(0xFF34D399)],
              onTap: () => _pilihMenu(22),
            ),
          if (izin.bolehLihat('keuangan.bop'))
            GradientStatCard(
              // "PAGU", bukan "DANA". Angkanya adalah sisa jatah belanja
              // (alokasi − terpakai), sedangkan kata "dana" terbaca sebagai
              // uang yang ada di kas — dan itu angka yang berbeda.
              //
              // Keduanya kebetulan sama besar selama seluruh alokasi sudah
              // cair penuh, jadi tidak ada apa pun di layar yang membantah
              // salah baca itu. Bedanya baru muncul saat pencairan bertahap:
              // pagu bisa menyisakan Rp 4 juta sementara kasnya sudah minus.
              //
              // Layar BOP menampilkan keduanya berdampingan sebagai "SISA
              // PAGU" dan "SALDO KAS BOP"; nama di sini kini mengikutinya.
              label: 'SISA PAGU BOP',
              value: _formatRupiah(context.watch<BopProvider>().summary?.sisaPagu ?? 0),
              subtitle: 'Bantuan Operasional Penyelenggaraan',
              icon: Icons.account_balance_wallet,
              gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
              onTap: () => _pilihMenu(23),
            ),
        ], defaultCrossAxisCount: 3),

        const SizedBox(height: 24),

        // === FINANCIAL CHART ===
        if (izin.bolehLihat('keuangan.kas') || izin.bolehLihat('keuangan.bop')) ...[
          _buildFinancialChart(
            _chartDataSource == 'Kas RT'
                ? finance.bulanan
                : context.watch<BopProvider>().bulanan,
          ),
          const SizedBox(height: 24),
        ],

        // === BARIS 1: PROGRESS IURAN + PERMOHONAN SURAT ===
        if (pakaiKartu(context)) ...[
          if (izin.bolehLihat('keuangan.iuran')) _buildProgressIuranCard(bills),
          if (izin.bolehLihat('keuangan.iuran') && izin.bolehLihat('layanan.surat'))
            const SizedBox(height: 16),
          if (izin.bolehLihat('layanan.surat')) _buildSuratPendingCard(),
        ] else ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (izin.bolehLihat('keuangan.iuran'))
                  Expanded(child: _buildProgressIuranCard(bills)),

                if (izin.bolehLihat('keuangan.iuran') && izin.bolehLihat('layanan.surat'))
                  const SizedBox(width: 16),

                if (izin.bolehLihat('layanan.surat'))
                  Expanded(child: _buildSuratPendingCard()),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // === BARIS 2 (PALING BAWAH): STATUS DARURAT + PENGADUAN WARGA ===
        if (pakaiKartu(context)) ...[
          if (izin.bolehLihat('aspirasi.darurat')) _buildStatusDaruratCard(),
          if (izin.bolehLihat('aspirasi.darurat') && izin.bolehLihat('aspirasi.pengaduan'))
            const SizedBox(height: 16),
          if (izin.bolehLihat('aspirasi.pengaduan')) _buildPengaduanCard(),
        ] else ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (izin.bolehLihat('aspirasi.darurat'))
                  Expanded(child: _buildStatusDaruratCard()),

                if (izin.bolehLihat('aspirasi.darurat') && izin.bolehLihat('aspirasi.pengaduan'))
                  const SizedBox(width: 16),

                if (izin.bolehLihat('aspirasi.pengaduan'))
                  Expanded(child: _buildPengaduanCard()),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // === PROGRESS PENAGIHAN IURAN BULAN INI ===
  Widget _buildProgressIuranCard(BillProvider bills) {
    // Memakai statistik bulan berjalan yang dihitung BACKEND
    // (GET /bills/stats?bulan=YYYY-MM&tahun=YYYY), bukan memotong-memotong
    // `bills.bills` di klien. Dulu card ini menghitung dari daftar yang
    // ter-paginate (hanya halaman pertama 10 baris) dan `unpaidBills` yang
    // merangkum seluruh data dalam memori — keduanya membuat angka bulan ini
    // salah. `fetchStatsBulanIni` di provider mengambil angka yang jujur.
    final st = bills.statsBulanIni;
    final totalBills = st.totalTagihan;
    final paidBills = st.jumlahLunas;
    final unpaid = st.jumlahTunggakan;
    final progress = totalBills > 0 ? paidBills / totalBills : 0.0;
    final percentage = (progress * 100).toInt();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _pilihMenu(21);
        },
        child: Container(
          padding: EdgeInsets.all(paddingKartu(context)),
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
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      color: Color(0xFF2563EB),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Progress Iuran Bulan Ini',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.teksUtama,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tingkat kepatuhan pembayaran warga',
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

              const SizedBox(height: 20),

              // Progress circle + stats
              Row(
                children: [
                  // Circular progress indicator
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 8,
                            // Track slate gelap (#334155) senada tema dark navy;
                            // progress utama Emerald (#10B981). Warna TIDAK lagi
                            // berubah berdasarkan persentase — tetap emerald di
                            // semua tingkat kepatuhan, selaras elemen UI lain.
                            backgroundColor: const Color(0xFF334155),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF10B981),
                            ),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Text(
                          '$percentage%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.teksUtama,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Detail stats
                  Expanded(
                    child: Column(
                      children: [
                        _buildProgressStatRow(
                          Icons.check_circle_rounded,
                          const Color(0xFF059669),
                          'Sudah Bayar',
                          '$paidBills warga',
                        ),
                        const SizedBox(height: 10),
                        _buildProgressStatRow(
                          Icons.pending_rounded,
                          const Color(0xFFD97706),
                          'Belum Bayar',
                          '$unpaid warga',
                        ),
                        const SizedBox(height: 10),
                        _buildProgressStatRow(
                          Icons.people_alt_rounded,
                          context.teksKedua,
                          'Total Tagihan',
                          '$totalBills tagihan',
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress bar at bottom
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFF334155),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStatRow(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.teksKedua,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.teksUtama,
          ),
        ),
      ],
    );
  }

  // === STATUS DARURAT & PENGADUAN ===
  Widget _buildStatusDaruratCard() {
    final emergency = context.watch<EmergencyProvider>();
    final activeAlerts = emergency.alerts.where((a) => a.isActive).toList();
    final hasActive = activeAlerts.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _pilihMenu(60);
        },
        child: Container(
          padding: EdgeInsets.all(paddingKartu(context)),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasActive
                  ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                  : (context.garis),
              width: hasActive ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hasActive
                          ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                          : const Color(0xFF059669).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      hasActive ? Icons.warning_amber_rounded : Icons.shield_rounded,
                      color: hasActive ? const Color(0xFFEF4444) : const Color(0xFF059669),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status Darurat',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.teksUtama,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Laporan dan sinyal darurat warga',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.teksTersier,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasActive
                          ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                          : const Color(0xFF059669).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hasActive ? '⚠ ${activeAlerts.length} Aktif' : '✓ Aman',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasActive ? const Color(0xFFEF4444) : const Color(0xFF059669),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Content
              if (hasActive) ...[
                // Show list of active alerts
                ...activeAlerts
                    .take(3)
                    .map(
                      (alert) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.crisis_alert, size: 16, color: Color(0xFFEF4444)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alert.namaWarga ?? 'Warga',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.teksUtama,
                                      ),
                                    ),
                                    Text(
                                      alert.message,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.teksKedua,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                DateFormat('HH:mm').format(alert.createdAt),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.teksTersier,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ] else ...[
                // Calm state
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: _gelap
                        ? const Color(0xFF059669).withValues(alpha: 0.05)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 36,
                        color: const Color(0xFF059669).withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lingkungan Aman & Kondusif',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _gelap ? Colors.white70 : const Color(0xFF166534),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tidak ada laporan darurat aktif saat ini',
                        style: TextStyle(
                          fontSize: 11,
                          color: _gelap ? Colors.white38 : const Color(0xFF4ADE80),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Summary row
              Row(
                children: [
                  _buildAlertSummaryChip(
                    Icons.crisis_alert,
                    'Darurat',
                    '${emergency.alerts.where((a) => a.isActive).length}',
                    const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  _buildAlertSummaryChip(
                    Icons.history_rounded,
                    'Selesai',
                    '${emergency.alerts.where((a) => !a.isActive).length}',
                    const Color(0xFF059669),
                  ),
                  const SizedBox(width: 8),
                  _buildAlertSummaryChip(
                    Icons.bar_chart_rounded,
                    'Total',
                    '${emergency.alerts.length}',
                    context.teksKedua,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // === PENGADUAN WARGA ===
  Widget _buildPengaduanCard() {
    final complaintProvider = context.watch<ComplaintProvider>();
    final complaints = complaintProvider.complaints;
    final pendingCount = complaints.where((c) => (c['status'] ?? '').toString().toLowerCase() == 'pending').length;
    final diprosesCount = complaints.where((c) => (c['status'] ?? '').toString().toLowerCase() == 'diproses').length;
    final selesaiCount = complaints.where((c) => (c['status'] ?? '').toString().toLowerCase() == 'selesai').length;
    final activeComplaints = complaints.where((c) {
      final st = (c['status'] ?? '').toString().toLowerCase();
      return st == 'pending' || st == 'diproses';
    }).toList();
    final hasActive = activeComplaints.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _pilihMenu(61);
        },
        child: Container(
          padding: EdgeInsets.all(paddingKartu(context)),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasActive
                  ? const Color(0xFFD97706).withValues(alpha: 0.5)
                  : context.garis,
              width: hasActive ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hasActive
                          ? const Color(0xFFD97706).withValues(alpha: 0.1)
                          : const Color(0xFF059669).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      hasActive ? Icons.rate_review_rounded : Icons.mark_chat_read_rounded,
                      color: hasActive ? const Color(0xFFD97706) : const Color(0xFF059669),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pengaduan Warga',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.teksUtama,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Keluhan dan aspirasi warga',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.teksTersier,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasActive
                          ? const Color(0xFFD97706).withValues(alpha: 0.1)
                          : const Color(0xFF059669).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hasActive ? '💬 ${activeComplaints.length} Aktif' : '✓ Terkendali',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasActive ? const Color(0xFFD97706) : const Color(0xFF059669),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (complaintProvider.isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (activeComplaints.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: _gelap
                        ? const Color(0xFF059669).withValues(alpha: 0.05)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.mark_chat_read_rounded,
                        size: 36,
                        color: const Color(0xFF059669).withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Semua Laporan Ditangani',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _gelap ? Colors.white70 : const Color(0xFF166534),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tidak ada pengaduan aktif saat ini',
                        style: TextStyle(
                          fontSize: 11,
                          color: _gelap ? Colors.white38 : const Color(0xFF4ADE80),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                ...activeComplaints
                    .take(3)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _gelap
                                ? const Color(0xFFD97706).withValues(alpha: 0.05)
                                : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFD97706).withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.report_problem_rounded, size: 16, color: Color(0xFFD97706)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (item['judul'] ?? item['title'] ?? 'Pengaduan').toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.teksUtama,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      (item['nama_pelapor'] ?? item['nama'] ?? 'Warga').toString(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.teksKedua,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (item['status'] ?? '').toString().toLowerCase() == 'pending'
                                      ? const Color(0xFFD97706).withValues(alpha: 0.15)
                                      : const Color(0xFF2563EB).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (item['status'] ?? 'pending').toString().toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: (item['status'] ?? '').toString().toLowerCase() == 'pending'
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],

              const SizedBox(height: 12),

              // Summary row
              Row(
                children: [
                  _buildAlertSummaryChip(
                    Icons.pending_actions_rounded,
                    'Pending',
                    '$pendingCount',
                    const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 8),
                  _buildAlertSummaryChip(
                    Icons.sync_rounded,
                    'Proses',
                    '$diprosesCount',
                    const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  _buildAlertSummaryChip(
                    Icons.check_circle_outline_rounded,
                    'Selesai',
                    '$selesaiCount',
                    const Color(0xFF059669),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertSummaryChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              '$value ',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === SURAT MENUNGGU PERSETUJUAN ===
  Widget _buildSuratPendingCard() {
    final letterProvider = context.watch<LetterProvider>();
    final pendingLetters = letterProvider.pendingLetters;

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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: Color(0xFF3B82F6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Permohonan Surat',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.teksUtama,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Surat warga yang perlu diproses',
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

          const SizedBox(height: 16),

          if (letterProvider.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (pendingLetters.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: _gelap
                    ? const Color(0xFF64748B).withValues(alpha: 0.05)
                    : context.latarLembut,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.mark_email_read_rounded,
                    size: 36,
                    color: context.teksTersier,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Semua Surat Diproses',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.teksKedua,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tidak ada permohonan surat baru',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.teksTersier,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            ...pendingLetters
                .take(3)
                .map(
                  (surat) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _gelap
                            ? const Color(0xFF3B82F6).withValues(alpha: 0.05)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                            child: Text(
                              (surat.namaPemohon ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  surat.jenisSurat,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.teksUtama,
                                  ),
                                ),
                                Text(
                                  surat.namaPemohon ?? '-',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.teksTersier,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () {
                setState(() {
                  _selectedMenuIndex = 44;
                });
              },
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                foregroundColor: const Color(0xFF3B82F6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Lihat Semua Permohonan (${pendingLetters.length})'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRupiah(double amount) {
    if (amount == 0) return 'Rp 0';
    final formatter = NumberFormat('#,###', 'id_ID');
    return 'Rp ${formatter.format(amount.toInt())}';
  }

  String _formatChartValue(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}jt';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}rb';
    return value.toStringAsFixed(0);
  }

  Widget _buildFinancialChart(List<Map<String, dynamic>> bulanan) {
    // Agregat per bulan datang dari backend (GET /finances/bulanan dan
    // /bop/bulanan), dijumlahkan di SQL atas SEMUA baris. Dulu chart ini
    // dibangun dari daftar transaksi yang ter-paginate — hanya halaman pertama
    // — sehingga bulan-bulan di luar halaman itu dilaporkan nol padahal datanya
    // ada.
    final now = DateTime.now();
    final List<Map<String, dynamic>> monthlyData = [];

    // Enam bulan dengan label "Agu 2026" membutuhkan sekitar 55px per label,
    // sedangkan di ponsel hanya tersedia ~222px untuk keenamnya — barisnya
    // meluber dan sebagian bulan terpotong. Di layar sempit grafiknya karena
    // itu menampilkan empat bulan terakhir dengan label bulan saja.
    final sempit = pakaiKartu(context);
    final jumlahBulan = sempit ? 4 : 6;
    final polaLabel = sempit ? 'MMM' : 'MMM yyyy';

    // Backend hanya mengembalikan bulan yang MEMILIKI transaksi; bulan kosong
    // diisi nol di sini agar sumbu tetap utuh dan tidak melompat-lompat.
    final perBulan = <String, Map<String, dynamic>>{
      for (final b in bulanan) b['bulan'].toString(): b,
    };

    for (int i = jumlahBulan - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthLabel = DateFormat(polaLabel, 'id_ID').format(month);
      final monthKey = DateFormat('yyyy-MM').format(month);

      final data = perBulan[monthKey];
      monthlyData.add({
        'label': monthLabel,
        'pemasukan': (data?['pemasukan'] as num?)?.toDouble() ?? 0,
        'pengeluaran': (data?['pengeluaran'] as num?)?.toDouble() ?? 0,
      });
    }

    // Calculate max value for scaling
    double maxValue = 0;
    for (final d in monthlyData) {
      maxValue = math.max(maxValue, (d['pemasukan'] as double));
      maxValue = math.max(maxValue, (d['pengeluaran'] as double));
    }
    if (maxValue == 0) maxValue = 1000000; // Default scale if no data

    // Round up maxValue to a nice number
    final double niceMax = _niceMaxValue(maxValue);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(paddingKonten(context)),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.garis),
        boxShadow: _gelap
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          //
          // Di ponsel judul dan pemilih sumber data DITUMPUK, tidak sebaris.
          // Sebaris, pemilihnya memakan ~120px dan ikonnya ~48px, menyisakan
          // sekitar 130px untuk judul — "Pemasukan vs Pengeluaran" dan
          // keterangannya sama-sama terpotong elipsis. Ditumpuk, judulnya
          // mendapat lebar penuh dan terbaca utuh.
          if (pakaiKartu(context)) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bar_chart_rounded, color: const Color(0xFF0D9488), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: _judulGrafik()),
              ],
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: _pemilihSumberGrafik()),
          ] else
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bar_chart_rounded, color: const Color(0xFF0D9488), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: _judulGrafik()),
                const SizedBox(width: 12),
                _pemilihSumberGrafik(),
              ],
            ),

          const SizedBox(height: 24),

          // Chart Area
          SizedBox(
            height: 260,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Y-axis labels
                SizedBox(
                  width: 50,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(5, (i) {
                      final val = niceMax - (niceMax / 4 * i);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          _formatChartValue(val),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.teksTersier,
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                // Chart body
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        painter: _BarChartPainter(
                          data: monthlyData,
                          maxValue: niceMax,
                          isDarkMode: _gelap,
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // X-axis labels
          //
          // Tiap label diberi jatah selebar satu kolom grafik lewat Expanded.
          // Dengan Row spaceAround, label yang lebih lebar dari jatahnya
          // mendorong tetangganya sampai meluber — itulah yang terjadi pada
          // label "Agu 2026". Sekarang jatahnya pasti sama rata dan teks yang
          // tidak muat dipotong dengan elipsis, bukan meluber.
          Padding(
            padding: const EdgeInsets.only(left: 50),
            child: Row(
              children: monthlyData.map((d) {
                return Expanded(
                  child: Text(
                    d['label'] as String,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.teksKedua,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(const Color(0xFF0D9488), 'Pemasukan'),
              const SizedBox(width: 24),
              _buildLegendItem(const Color(0xFFEF4444), 'Pengeluaran'),
            ],
          ),
        ],
      ),
    );
  }

  /// Judul dan keterangan kartu grafik.
  ///
  /// Tanpa `overflow: ellipsis` di sini — pemanggilnya sudah memastikan
  /// lebarnya cukup, dan elipsis justru menyembunyikan judul yang seharusnya
  /// terbaca utuh. Keterangannya boleh turun ke baris kedua.
  Widget _judulGrafik() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pemasukan vs Pengeluaran',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.teksUtama,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Perbandingan uang masuk dan keluar per bulan',
          style: TextStyle(
            fontSize: 12,
            color: context.teksTersier,
          ),
        ),
      ],
    );
  }

  Widget _pemilihSumberGrafik() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: context.garis),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _chartDataSource,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down,
            color: context.teksKedua,
          ),
          dropdownColor: context.latarKartu,
          style: TextStyle(
            fontSize: 13,
            color: context.teksUtama,
          ),
          items: const [
            DropdownMenuItem(value: 'Kas RT', child: Text('Lihat: Kas RT')),
            DropdownMenuItem(value: 'Dana BOP', child: Text('Lihat: Dana BOP')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _chartDataSource = val);
            }
          },
        ),
      ),
    );
  }

  double _niceMaxValue(double value) {
    if (value <= 0) return 1000000;
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
    final residual = value / magnitude;
    double nice;
    if (residual <= 1.5) {
      nice = 1.5;
    } else if (residual <= 2) {
      nice = 2;
    } else if (residual <= 3) {
      nice = 3;
    } else if (residual <= 5) {
      nice = 5;
    } else if (residual <= 7.5) {
      nice = 7.5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.teksKedua,
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveGrid(List<Widget> cards, {int defaultCrossAxisCount = 4}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = ResponsiveLayout.isMobile(context)
            ? 1
            : (ResponsiveLayout.isTablet(context) ? 2 : defaultCrossAxisCount);
        double spacing = 16.0;
        double calculatedWidth = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;
        double width = math.max(0.0, calculatedWidth);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final double maxValue;
  final bool isDarkMode;

  _BarChartPainter({required this.data, required this.maxValue, required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final int count = data.length;
    if (count == 0) return;

    final double sectionWidth = size.width / count;
    final double barWidth = math.min(sectionWidth * 0.28, 32);
    final double barGap = 4;

    // Draw horizontal grid lines
    final gridPaint = Paint()
      // CustomPainter tidak punya `context`, jadi warnanya tetap ditulis
      // eksplisit dan dipilih lewat `isDarkMode` yang diteruskan pemanggil.
      ..color = isDarkMode
          ? const Color(0xFF334155).withAlpha(120)
          : const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw bars
    for (int i = 0; i < count; i++) {
      final centerX = sectionWidth * i + sectionWidth / 2;
      final pemasukan = (data[i]['pemasukan'] as double);
      final pengeluaran = (data[i]['pengeluaran'] as double);

      final hasPemasukan = pemasukan > 0;
      final hasPengeluaran = pengeluaran > 0;

      double leftPemasukan;
      double leftPengeluaran;

      if (hasPemasukan && hasPengeluaran) {
        leftPemasukan = centerX - barWidth - barGap / 2;
        leftPengeluaran = centerX + barGap / 2;
      } else {
        leftPemasukan = centerX - barWidth / 2;
        leftPengeluaran = centerX - barWidth / 2;
      }

      if (hasPemasukan) {
        final pemasukanHeight = (pemasukan / maxValue) * size.height;
        final pemasukanRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            leftPemasukan,
            size.height - pemasukanHeight,
            barWidth,
            pemasukanHeight,
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );

        final pemasukanPaint = Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
          ).createShader(pemasukanRect.outerRect);

        canvas.drawRRect(pemasukanRect, pemasukanPaint);
      }

      if (hasPengeluaran) {
        final pengeluaranHeight = (pengeluaran / maxValue) * size.height;
        final pengeluaranRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            leftPengeluaran,
            size.height - pengeluaranHeight,
            barWidth,
            pengeluaranHeight,
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );

        final pengeluaranPaint = Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEF4444), Color(0xFFFCA5A5)],
          ).createShader(pengeluaranRect.outerRect);

        canvas.drawRRect(pengeluaranRect, pengeluaranPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.isDarkMode != isDarkMode;
  }
}

class RealTimeClockText extends StatefulWidget {
  final bool isMobile;
  final bool isDarkMode;

  const RealTimeClockText({
    super.key,
    required this.isMobile,
    required this.isDarkMode,
  });

  @override
  State<RealTimeClockText> createState() => _RealTimeClockTextState();
}

class _RealTimeClockTextState extends State<RealTimeClockText> {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dayNames = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final monthNames = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    final dayName = dayNames[_currentTime.weekday - 1];
    final dateStr =
        '$dayName, ${_currentTime.day.toString().padLeft(2, '0')} ${monthNames[_currentTime.month - 1]} ${_currentTime.year}';
    final timeStr =
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}';

    return Text(
      widget.isMobile ? '${dateStr.split(', ').last}  •  $timeStr' : '$dateStr  •  $timeStr',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: widget.isMobile ? 11 : 13,
        color: widget.isDarkMode ? Colors.white70 : context.teksKedua,
      ),
    );
  }
}
