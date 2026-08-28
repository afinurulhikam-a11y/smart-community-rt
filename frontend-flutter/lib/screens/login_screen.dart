import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/services/auth_service.dart';
import '../core/services/autofill_helper.dart';
import '../core/pesan.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// Penjaga kirim-ganda, dan ia harus ada di layar ini — bukan hanya di
  /// [AuthService].
  ///
  /// `login()` memang menyetel `_isLoading = true` sebelum `await` pertamanya,
  /// tetapi tombol Masuk membaca nilai itu lewat `context.watch`, dan
  /// `notifyListeners()` baru membangun ulang pada frame BERIKUTNYA. Jadi dua
  /// pemicuan dalam satu frame — Enter yang ditahan sehingga berulang, atau
  /// Enter berbarengan dengan klik — dua-duanya masih melihat tombol dalam
  /// keadaan aktif dan keduanya mengirim permintaan.
  ///
  /// Bendera ini disetel serentak (`setState` menugaskan nilainya seketika,
  /// walau pembangunan ulangnya ditunda), sehingga pemicuan kedua berhenti di
  /// baris pertama [_handleLogin] sebelum menyentuh jaringan.
  bool _sedangMasuk = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Satu-satunya jalan masuk: tombol "Masuk ke Sistem" dan tombol Enter pada
  /// kedua kolom memanggil fungsi yang sama persis.
  ///
  /// Logika autentikasinya tidak berubah sedikit pun — validasi form, panggilan
  /// `auth.login`, dan penanganan gagalnya tetap seperti semula. Yang ditambah
  /// hanya penjaga kirim-ganda di sekelilingnya.
  Future<void> _handleLogin() async {
    // Diperiksa PALING awal, sebelum validasi: pemicuan kedua harus berhenti
    // di sini, bukan sesudah sempat menjalankan apa pun.
    if (_sedangMasuk) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _sedangMasuk = true);
    // Beri tahu browser & engine autofill bahwa form login sedang dikirim
    // selagi elemen input DOM masih terpasang dan aktif di layar.
    TextInput.finishAutofillContext(shouldSave: true);

    final auth = context.read<AuthService>();
    try {
      final success = await auth.login(_emailController.text.trim(), _passwordController.text);
      if (success) {
        // Panggil Credential Management API untuk memicu prompt simpan sandi
        // secara aktif (floating bubble) di Google Chrome & browser berbasis Chromium.
        simpanKredensialWeb(_emailController.text.trim(), _passwordController.text);
      } else {
        // Jika kredensial salah, batalkan sesi penyimpanan autofill
        TextInput.finishAutofillContext(shouldSave: false);
        if (mounted) {
          pesanGagal(context, auth.errorMessage ?? 'Login gagal');
        }
      }
    } finally {
      // Saat login berhasil, AuthGate menukar layar ini sehingga State-nya
      // sudah dilepas — `setState` pada widget yang tidak terpasang akan
      // melempar. Yang perlu dibuka kembali hanyalah kasus gagal, dan di situ
      // layarnya masih hidup.
      if (mounted) setState(() => _sedangMasuk = false);
    }
  }

  Future<void> _bukaBantuanWhatsApp() async {
    const pesan =
        'Halo Pengurus RT, saya butuh bantuan terkait akun dan akses masuk aplikasi Auto RT.';
    final uri = Uri.parse(
      'https://wa.me/6289692216853?text=${Uri.encodeComponent(pesan)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Gagal membuka WhatsApp: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    return Title(
      title: 'Masuk | Auto RT',
      color: const Color(0xFF1B7A6A),
      child: isDesktop
          ? Scaffold(
              backgroundColor: const Color(0xFFE6F4F1),
              body: Center(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    width: 800,
                    height: 580,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 40,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: _buildLeftPanel(true)),
                        Expanded(flex: 6, child: _buildRightPanel(auth, true)),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : _tampilanPonsel(auth),
    );
  }

  Widget _tampilanPonsel(AuthService auth) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, batas) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: batas.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _kepalaPonsel(),
                      Expanded(child: _buildRightPanel(auth, false)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _kepalaPonsel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFF1B7A6A),
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            child: const Icon(Icons.home_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sistem Informasi RT',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Kelola data warga, keuangan, dan layanan RT dalam satu platform',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(bool isDesktop) {
    final konten = Padding(
      padding: EdgeInsets.all(isDesktop ? 36 : 24),
      child: _kontenKiri(isDesktop),
    );

    return Container(
      color: const Color(0xFF1B7A6A),
      child: Stack(
        children: [
          Positioned(
            top: -150,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          if (isDesktop) Positioned.fill(child: konten) else konten,
        ],
      ),
    );
  }

  Widget _kontenKiri(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 24),
        const Text(
          'Sistem\nInformasi RT',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Kelola data warga, keuangan, dan\nlayanan RT dalam satu platform.',
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
        ),
        const SizedBox(height: 32),
        _buildFeatureItem(Icons.group, 'Data Warga & KK'),
        _buildFeatureItem(Icons.account_balance_wallet, 'Keuangan & Iuran'),
        _buildFeatureItem(Icons.inventory_2_outlined, 'Inventaris RT'),
        _buildFeatureItem(Icons.campaign_outlined, 'Pengumuman & Surat'),
        if (isDesktop) const Spacer() else const SizedBox(height: 32),
        Text(
          '©2026 Sistem RT',
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(AuthService auth, bool isDesktop) {
    // Dua sumber, satu keadaan: `_sedangMasuk` berubah pada frame pemicuan,
    // `auth.isLoading` menyusul lewat notifyListeners. Menggabungkannya membuat
    // tombol tidak pernah tampak aktif padahal permintaan sudah berjalan.
    final sedangProses = auth.isLoading || _sedangMasuk;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 48 : 24, vertical: isDesktop ? 40 : 8),
      color: Colors.white,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isDesktop) ...[
                const Text(
                  'Selamat Datang',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Masukkan Akun Anda untuk melanjutkan',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 36),
              ],

              // Username Field
              const Text(
                'USERNAME (NIK)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: TextInputType.text,
                autofillHints: const [AutofillHints.username],
                // Enter di kolom ini mengirim form, sama seperti menekan tombol
                // "Masuk ke Sistem". `TextInputAction.go` dipilih, bukan `.next`:
                // label "berikutnya" pada papan tombol ponsel menjanjikan
                // perpindahan fokus yang tidak terjadi — tombolnya tetap
                // mengirim, karena keduanya sama-sama memicu `onFieldSubmitted`.
                textInputAction: TextInputAction.go,
                onFieldSubmitted: (_) => _handleLogin(),
                // Batasi maksimal 16 karakter — NIK warga selalu 16 digit.
                // `LengthLimitingTextInputFormatter` berlaku saat mengetik maupun
                // menempel (paste), dan memotong kelebihan sebelum validator
                // berjalan. `FilteringTextInputFormatter.digitsOnly` SENGAJA tidak
                // dipakai: field ini juga menerima username/email pengurus yang
                // mengandung huruf, jadi memaksa digit saja akan memutus login
                // non-NIK.
                inputFormatters: [LengthLimitingTextInputFormatter(16)],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Masukkan NIK atau Username',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    color: Color(0xFF64748B),
                    size: 21,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Username wajib diisi';
                  if (v.length > 16) return 'Maksimal 16 karakter';
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Password Field
              const Text(
                'PASSWORD',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                textAlignVertical: TextAlignVertical.center,
                obscureText: _obscurePassword,
                keyboardType: TextInputType.text,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.go,
                onFieldSubmitted: (_) => _handleLogin(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Masukkan password',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
                  prefixIcon: const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
                  suffixIcon: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 46, minHeight: 46),
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: const Color(0xFF64748B),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password wajib diisi';
                  return null;
                },
              ),

              SizedBox(height: isDesktop ? 32 : 20),

              // Login Button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  // `_sedangMasuk` ikut dibaca supaya tombol dan spinner berubah
                  // pada frame yang sama dengan pemicuannya. Bila hanya
                  // `auth.isLoading`, menekan Enter tidak memberi tanda apa pun
                  // sampai `notifyListeners()` sempat membangun ulang — dan diam
                  // sesaat itulah yang membuat orang menekan Enter sekali lagi.
                  onPressed: sedangProses ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7A6A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: sedangProses ? const SizedBox() : const Icon(Icons.login_rounded, size: 18),
                  label: sedangProses
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text(
                          'Masuk',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),

              SizedBox(height: isDesktop ? 16 : 12),

              // Demo Account Chips
              Center(
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app_outlined, size: 13, color: Color(0xFF64748B)),
                        const SizedBox(width: 5),
                        Text(
                          'Pilih Akun Demo (Klik untuk Isi):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B).withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chipAkunDemo('Ketua RW', 'ketuarw', 'ketuarw123', const Color(0xFF0D9488)),
                        _chipAkunDemo('Ketua RT', 'ketua', 'ketua123', const Color(0xFF1B7A6A)),
                        _chipAkunDemo('Sekretaris', 'sekretaris', 'sekretaris123', const Color(0xFF0284C7)),
                        _chipAkunDemo('Bendahara', 'bendahara', 'bendahara123', const Color(0xFF059669)),
                        _chipAkunDemo('Warga', '3201012345670001', '12345678', const Color(0xFF8B5CF6)),
                        _chipAkunDemo('Admin', 'Developer', 'admin123', const Color(0xFF475569)),
                      ],
                    ),
                  ],
                ),
              ),

              if (isDesktop) const Spacer() else const SizedBox(height: 16),

              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Butuh bantuan ? Hubungi ',
                      style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF64748B).withValues(alpha: 0.9),
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _bukaBantuanWhatsApp,
                        child: const Text(
                          'pengurus RT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1B7A6A),
                            decoration: TextDecoration.underline,
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
      ),
    );
  }

  Widget _chipAkunDemo(String label, String username, String password, Color warna) {
    return Material(
      color: warna.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _emailController.text = username;
          _passwordController.text = password;
          pesanSukses(context, 'Akun demo $label ($username) dipilih.');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: warna.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: warna,
            ),
          ),
        ),
      ),
    );
  }
}
