import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

// Core
import 'core/theme/app_theme.dart';
import 'core/services/auth_service.dart';
import 'core/services/websocket_service.dart';
import 'core/pesan.dart';

// Providers
import 'providers/bill_provider.dart';
import 'providers/jenis_iuran_provider.dart';
import 'providers/meteran_provider.dart';
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
        ChangeNotifierProvider(create: (_) => MeteranProvider()),
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

  // Cegah dialog wajib ganti sandi tampil dua kali dalam satu build. Nilainya
  // sengaja tidak disimpan permanen: kalau warga keluar dan masuk lagi tanpa
  // mengganti sandi, dialog harus muncul lagi.
  bool _dialogSandiDitampilkan = false;

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
      if (auth.userRole.isNotEmpty) {
        izin.setRole(auth.userRole);
      }
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

  /// Tampilkan dialog yang MEWAJIBKAN penggantian kata sandi.
  ///
  /// Akun warga baru dibuat dengan kata sandi awal yang sama untuk semua (atau
  /// yang dicatat saat pendaftaran), jadi sudah diketahui orang lain selama
  /// proses tersebut. Warga yang pertama kali masuk wajib menggantinya sebelum
  /// aplikasi dipakai — bukan sekadar disarankan. Karena itu dialognya tidak
  /// bisa ditutup (barrierDismissible false) dan tanpa tombol batal; hanya
  /// "Simpan" yang meneruskannya. Sesi tetap bisa keluar lewat tombol logout
  /// aplikasi, dan warga diingatkan lagi pada login berikutnya.
  Future<void> _tampilkanWajibGantiSandi(AuthService auth) async {
    final lamaCtrl = TextEditingController();
    final baruCtrl = TextEditingController();
    final ulangiCtrl = TextEditingController();
    bool sembunyikan = true;
    bool menyimpan = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF1B7A6A)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Ganti Kata Sandi',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.security, color: Color(0xFFD97706), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Untuk keamanan akun, Anda wajib mengganti kata sandi '
                            'bawaan sebelum memakai aplikasi.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: lamaCtrl,
                    obscureText: sembunyikan,
                    decoration: InputDecoration(
                      labelText: 'Kata Sandi Lama',
                      prefixIcon: const Icon(Icons.password, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          sembunyikan ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () => setLocal(() => sembunyikan = !sembunyikan),
                      ),
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: baruCtrl,
                    obscureText: sembunyikan,
                    decoration: InputDecoration(
                      labelText: 'Kata Sandi Baru',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ulangiCtrl,
                    obscureText: sembunyikan,
                    decoration: InputDecoration(
                      labelText: 'Ulangi Kata Sandi Baru',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: menyimpan ? null : () async {
                await auth.logout();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Keluar'),
            ),
            ElevatedButton(
              onPressed: menyimpan
                  ? null
                  : () async {
                      final lama = lamaCtrl.text.trim();
                      final baru = baruCtrl.text.trim();
                      final ulangi = ulangiCtrl.text.trim();

                      if (lama.isEmpty || baru.isEmpty) {
                        tampilkanPesan(ctx, 'Lengkapi semua kolom.', sukses: false);
                        return;
                      }
                      if (baru.length < 6) {
                        tampilkanPesan(ctx, 'Kata sandi baru minimal 6 karakter.', sukses: false);
                        return;
                      }
                      if (baru != ulangi) {
                        tampilkanPesan(ctx, 'Ulangi kata sandi baru tidak cocok.', sukses: false);
                        return;
                      }

                      setLocal(() => menyimpan = true);
                      final ok = await auth.changePassword(oldPassword: lama, newPassword: baru);
                      if (!ctx.mounted) return;
                      setLocal(() => menyimpan = false);

                      if (ok) {
                        Navigator.pop(ctx);
                      } else {
                        tampilkanPesan(ctx, auth.errorMessage ?? 'Gagal mengganti kata sandi.', sukses: false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B7A6A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(menyimpan ? 'Menyimpan...' : 'Simpan'),
            ),
          ],
        ),
      ),
    );

    lamaCtrl.dispose();
    baruCtrl.dispose();
    ulangiCtrl.dispose();
    _dialogSandiDitampilkan = false;
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

        // Wajib ganti kata sandi untuk akun baru. Ditampilkan setelah login
        // (atau setelah sesi dipulihkan) — bukan saat `_isChecking`, supaya
        // dialognya tampil di atas layar yang sudah siap, bukan di atas splash.
        final wajibGanti = auth.user?['must_change_password'] == true;
        if (wajibGanti && !_dialogSandiDitampilkan) {
          _dialogSandiDitampilkan = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tampilkanWajibGantiSandi(auth);
          });
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
    context.read<MeteranProvider>().bersihkan();
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
