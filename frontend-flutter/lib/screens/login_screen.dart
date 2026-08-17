import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/services/auth_service.dart';
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
    final auth = context.read<AuthService>();
    try {
      final success = await auth.login(_emailController.text.trim(), _passwordController.text);
      if (!success && mounted) {
        pesanGagal(context, auth.errorMessage ?? 'Login gagal');
      }
    } finally {
      // Saat login berhasil, AuthGate menukar layar ini sehingga State-nya
      // sudah dilepas — `setState` pada widget yang tidak terpasang akan
      // melempar. Yang perlu dibuka kembali hanyalah kasus gagal, dan di situ
      // layarnya masih hidup.
      if (mounted) setState(() => _sedangMasuk = false);
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
                hintText: 'Masukkan NIK atau Username',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                prefixIcon: const Icon(
                  Icons.person_outline,
                  color: Color(0xFF64748B),
                  size: 20,
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
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.go,
              onFieldSubmitted: (_) => _handleLogin(),
              decoration: InputDecoration(
                hintText: 'Masukkan password',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF64748B), size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: const Color(0xFF64748B),
                    size: 18,
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
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
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

            if (isDesktop) const Spacer() else const SizedBox(height: 16),

            Center(
              child: Text(
                'Butuh bantuan? Hubungi pengurus RT Anda',
                style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFF64748B).withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
