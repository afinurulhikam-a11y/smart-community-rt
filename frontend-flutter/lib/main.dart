import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

// Core
import 'core/theme/app_theme.dart';
import 'core/services/auth_service.dart';
import 'core/services/websocket_service.dart';

// Providers
import 'providers/bill_provider.dart';
import 'providers/jenis_iuran_provider.dart';
import 'providers/kategori_kas_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/kategori_bop_provider.dart';
import 'providers/alokasi_bop_provider.dart';
import 'providers/finance_provider.dart';
import 'providers/letter_provider.dart';
import 'providers/emergency_provider.dart';
import 'providers/demographic_provider.dart';
import 'providers/bop_provider.dart';
import 'providers/announcement_provider.dart';
import 'providers/complaint_provider.dart';
import 'providers/agenda_provider.dart';
import 'providers/polling_provider.dart';
import 'providers/visitor_provider.dart';
import 'providers/bantuan_sosial_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/family_provider.dart';
import 'providers/warga_provider.dart';
import 'providers/log_provider.dart';
import 'providers/reset_provider.dart';
import 'providers/aksi_utama_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/patrol_provider.dart';
import 'providers/tema_provider.dart';
import 'providers/koneksi_provider.dart';
import 'core/services/cache_lokal.dart';
import 'core/services/antrean_offline.dart';

// Screens
import 'screens/login_screen.dart';
import 'screens/admin/main_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  // Dibaca sebelum runApp supaya bingkai PERTAMA sudah memakai tema yang benar.
  // Memuatnya belakangan membuat aplikasi berkedip dari terang ke gelap tepat
  // di depan mata pengguna. Ini penyimpanan lokal, bukan jaringan — aturan
  // "tidak ada panggilan jaringan di jalur mulai" tetap terjaga.
  final gelapAwal = await TemaProvider.bacaTersimpan();

  runApp(SmartCommunityApp(gelapAwal: gelapAwal));
}

class SmartCommunityApp extends StatelessWidget {
  /// Pilihan tema yang sudah dibaca di [main], sebelum bingkai pertama.
  final bool gelapAwal;

  const SmartCommunityApp({super.key, this.gelapAwal = false});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TemaProvider(gelapAwal: gelapAwal)),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => BillProvider()),
        ChangeNotifierProvider(create: (_) => JenisIuranProvider()),
        ChangeNotifierProvider(create: (_) => KategoriKasProvider()),
        ChangeNotifierProvider(create: (_) => KategoriBopProvider()),
        ChangeNotifierProvider(create: (_) => AlokasiBopProvider()),
        ChangeNotifierProvider(create: (_) => FinanceProvider()),
        ChangeNotifierProvider(create: (_) => BopProvider()),
        ChangeNotifierProvider(create: (_) => LetterProvider()),
        ChangeNotifierProvider(create: (_) => EmergencyProvider()),
        ChangeNotifierProvider(create: (_) => DemographicProvider()),
        ChangeNotifierProvider(create: (_) => AnnouncementProvider()),
        ChangeNotifierProvider(create: (_) => ComplaintProvider()),
        ChangeNotifierProvider(create: (_) => AgendaProvider()),
        ChangeNotifierProvider(create: (_) => PollingProvider()),
        ChangeNotifierProvider(create: (_) => VisitorProvider()),
        ChangeNotifierProvider(create: (_) => BantuanSosialProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => FamilyProvider()),
        ChangeNotifierProvider(create: (_) => WargaProvider()),
        ChangeNotifierProvider(create: (_) => LogProvider()),
        ChangeNotifierProvider(create: (_) => ResetProvider()),
        ChangeNotifierProvider(create: (_) => PaymentProvider()),
        ChangeNotifierProvider(create: (_) => PatrolProvider()),
        ChangeNotifierProvider(create: (_) => AksiUtamaProvider()),
        // Memantau jaringan DAN mengirim ulang tulisan yang tertunda. Dibuat
        // di akar supaya pemantauannya berjalan sepanjang aplikasi hidup,
        // bukan hanya selama satu layar terbuka.
        ChangeNotifierProvider(create: (_) => KoneksiProvider()),
      ],
      // Tema dipasang di AKAR, bukan pada satu subtree.
      //
      // Sebelumnya hanya isi yang menggulir di dalam MainDashboard yang
      // dibungkus `Theme()`, sehingga AppBar, laci, navigasi bawah, tombol
      // mengambang, layar Login, dan SETIAP dialog tidak pernah ikut menggelap
      // — `showDialog` memakai Navigator akar, jadi ia selalu membaca tema dari
      // sini, bukan dari pembungkus di tengah pohon.
      child: Consumer<TemaProvider>(
        builder: (context, tema, _) => MaterialApp(
          title: 'Smart Community RT',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: tema.mode,
          home: const AuthGate(),
          routes: {'/login': (_) => const LoginScreen()},
        ),
      ),
    );
  }
}

/// AuthGate: Router utama berdasarkan status login & role
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  /// Batas menunggu izin sebelum aplikasi tetap dibuka.
  ///
  /// Tanpa batas ini, layar splash menahan selama ApiService mencoba ulang —
  /// tiga percobaan berbatas 10 detik ditambah jeda mundur, jadi sekitar 31
  /// detik bila server tidak terjangkau. Menu yang belum lengkap selama sesaat
  /// jauh lebih baik daripada layar diam yang terlihat seperti hang.
  static const Duration _batasTungguIzin = Duration(seconds: 6);

  Future<void> _checkAuth() async {
    final auth = context.read<AuthService>();
    final izin = context.read<PermissionProvider>();
    final masuk = await auth.tryAutoLogin();

    // Izin diusahakan siap sebelum sidebar dibangun, kalau tidak menunya
    // sempat tampil kosong lalu berubah — tetapi tidak ditunggu selamanya.
    if (masuk) {
      try {
        await izin.muat().timeout(_batasTungguIzin);
      } catch (_) {
        // Lewat batas atau gagal: aplikasi tetap dibuka. `muat()` yang
        // tertinggal akan memberi tahu pendengarnya sendiri bila akhirnya
        // selesai, dan sidebar ikut menyesuaikan.
      }
    }

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(color: Color(0xFF1B7A6A)),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_city_rounded, size: 64, color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Smart Community RT',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 20),
                Text('Memuat data...', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      );
    }

    return Consumer2<AuthService, PermissionProvider>(
      builder: (context, auth, izin, _) {
        if (!auth.isLoggedIn) {
          // Bersihkan izin DAN seluruh data pengguna sebelumnya.
          //
          // Dulu hanya izin yang dibersihkan. Dua puluh empat provider lain
          // dibuat sekali di MultiProvider akar dan hidup selama proses
          // berjalan, jadi daftar tagihan, transaksi kas, data warga, dan
          // seluruh isi layar milik pengguna terdahulu masih ada di memori
          // ketika orang berikutnya masuk — dan sempat terlihat sampai
          // pengambilan data yang baru selesai.
          //
          // Biasanya tertutupi oleh pengambilan ulang di initState tiap layar,
          // tetapi "biasanya tertutupi" bukan jaminan. Pada perangkat bersama
          // yang dipakai pengurus bergantian, jendela itu nyata.
          if (izin.sudahDimuat) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              izin.bersihkan();
              bersihkanSemuaProvider(context);
              context.read<KoneksiProvider>().bersihkan();

              // Penyimpanan di PERANGKAT ikut dikosongkan, bukan hanya memori.
              // Kalau tidak, data pengguna sebelumnya tetap tersimpan dan bisa
              // muncul kembali pada sesi berikutnya justru ketika jaringan mati
              // — tepat saat tidak ada apa pun yang menimpanya. Antreannya juga
              // dibuang: pengaduan milik satu orang tidak boleh terkirim atas
              // nama orang berikutnya yang masuk.
              CacheLokal.kosongkan();
              AntreanOffline.kosongkan();
            });
          }
          return const LoginScreen();
        }

        // Pemicu pemuatan hak akses di latar belakang jika belum sempat dimuat
        if (!izin.sudahDimuat && !izin.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) => izin.muat());
        }

        // Semua role memakai MainDashboard; sidebar menyaring menunya
        // berdasarkan izin yang dimuat di latar belakang.
        const roleDikenal = {'admin', 'ketua_rt', 'sekretaris', 'bendahara', 'warga'};
        return roleDikenal.contains(auth.userRole) ? const MainDashboard() : const LoginScreen();
      },
    );
  }
}

/// Kosongkan seluruh provider data saat pengguna keluar.
///
/// Daftarnya ditulis eksplisit, bukan dicari otomatis: `Provider` tidak
/// menyediakan cara menelusuri apa saja yang terdaftar, dan menuliskannya satu
/// per satu berarti provider baru yang lupa didaftarkan di sini akan terlihat
/// saat berkas ini dibaca — bukan diam-diam menyimpan data pengguna lama.
///
/// TemaProvider dan AksiUtamaProvider sengaja TIDAK ikut: yang pertama
/// menyimpan preferensi perangkat (mode gelap), bukan data pengguna, dan yang
/// kedua hanya registri tombol aksi yang sudah dilepas oleh perpindahan menu.
/// PermissionProvider dibersihkan terpisah karena punya urutannya sendiri.
void bersihkanSemuaProvider(BuildContext context) {
  try {
    context.read<AgendaProvider>().bersihkan();
    context.read<AlokasiBopProvider>().bersihkan();
    context.read<AnnouncementProvider>().bersihkan();
    context.read<BantuanSosialProvider>().bersihkan();
    context.read<BillProvider>().bersihkan();
    context.read<BopProvider>().bersihkan();
    context.read<ComplaintProvider>().bersihkan();
    context.read<DemographicProvider>().bersihkan();
    context.read<EmergencyProvider>().bersihkan();
    context.read<FamilyProvider>().bersihkan();
    context.read<FinanceProvider>().bersihkan();
    context.read<InventoryProvider>().bersihkan();
    context.read<JenisIuranProvider>().bersihkan();
    context.read<KategoriBopProvider>().bersihkan();
    context.read<KategoriKasProvider>().bersihkan();
    context.read<LetterProvider>().bersihkan();
    context.read<LogProvider>().bersihkan();
    context.read<PatrolProvider>().bersihkan();
    context.read<PaymentProvider>().bersihkan();
    context.read<PollingProvider>().bersihkan();
    context.read<ResetProvider>().bersihkan();
    context.read<VisitorProvider>().bersihkan();
    context.read<WargaProvider>().bersihkan();
  } catch (_) {
    // Konteks bisa saja sudah dilepas ketika callback ini berjalan. Kegagalan
    // membersihkan tidak boleh menjatuhkan aplikasi di jalur logout — layar
    // berikutnya tetap mengambil datanya sendiri.
  }
}
