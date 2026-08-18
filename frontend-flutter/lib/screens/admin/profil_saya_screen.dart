import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../core/services/auth_service.dart';
import '../../widgets/responsive_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

class ProfilSayaScreen extends StatefulWidget {
  const ProfilSayaScreen({super.key});

  @override
  State<ProfilSayaScreen> createState() => _ProfilSayaScreenState();
}

class _ProfilSayaScreenState extends State<ProfilSayaScreen> {
  late TextEditingController _namaController;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _noHpController;

  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  /// Profil lengkap sedang diambil dari `/auth/profil`.
  bool _memuatProfil = true;

  @override
  void initState() {
    super.initState();
    // Nama dan username ada di profil ringkas yang tersimpan, jadi keduanya
    // bisa langsung tampil. Email dan nomor HP TIDAK — keduanya sengaja tidak
    // lagi disimpan di perangkat, dan diambil saat layar ini dibuka.
    final auth = context.read<AuthService>();
    final ringkas = auth.user ?? {};
    _namaController = TextEditingController(text: ringkas['nama']?.toString() ?? '');
    _usernameController = TextEditingController(text: ringkas['username']?.toString() ?? '');
    _emailController = TextEditingController();
    _noHpController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) => _muatProfil());
  }

  Future<void> _muatProfil() async {
    final profil = await context.read<AuthService>().muatProfilLengkap();
    if (!mounted) return;
    setState(() {
      _memuatProfil = false;
      if (profil == null) return;
      // Nilai dari server menimpa yang sudah ada — kecuali bila pengguna sudah
      // terlanjur mengetik, yang tidak mungkin terjadi karena formnya masih
      // menampilkan keadaan memuat sampai titik ini.
      _namaController.text = profil['nama']?.toString() ?? _namaController.text;
      _usernameController.text = profil['username']?.toString() ?? _usernameController.text;
      final emailVal = profil['email']?.toString() ?? '';
      final nikVal = profil['nik']?.toString() ?? '';
      final unameVal = profil['username']?.toString() ?? '';
      _emailController.text = (emailVal.isNotEmpty && emailVal != nikVal && emailVal != unameVal) ? emailVal : '';

      final hpVal = profil['no_hp']?.toString() ?? '';
      _noHpController.text = (hpVal.isNotEmpty && hpVal != '0000000000000000' && hpVal != '0') ? hpVal : '';
    });
  }

  @override
  void dispose() {
    _namaController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _noHpController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }


  Future<void> _handleSaveProfile() async {
    final auth = context.read<AuthService>();
    if (_namaController.text.trim().isEmpty) {
      pesanGagal(context, 'Nama lengkap wajib diisi');
      return;
    }

    final success = await auth.updateProfile(
      nama: _namaController.text.trim(),
      email: _emailController.text.trim(),
      noHp: _noHpController.text.trim(),
      username: _usernameController.text.trim(),
    );

    if (mounted) {
      if (success) {
        pesanSukses(context, 'Profil berhasil diperbarui!');
      } else {
        pesanGagal(context, auth.errorMessage ?? 'Gagal memperbarui profil');
      }
    }
  }

  Future<void> _handleChangePassword() async {
    final auth = context.read<AuthService>();
    final oldPass = _oldPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      pesanGagal(context, 'Semua kolom password wajib diisi');
      return;
    }

    if (newPass.length < 6) {
      pesanGagal(context, 'Password baru minimal 6 karakter');
      return;
    }

    if (newPass != confirmPass) {
      pesanGagal(context, 'Konfirmasi password baru tidak cocok');
      return;
    }

    final success = await auth.changePassword(oldPassword: oldPass, newPassword: newPass);

    if (mounted) {
      if (success) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        pesanSukses(context, 'Password berhasil diubah!');
      } else {
        pesanGagal(context, auth.errorMessage ?? 'Gagal mengubah password');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        return _buildProfilAkunContent(auth);
      },
    );
  }

  Widget _buildProfilAkunContent(AuthService auth) {
    // Nama, username, dan peran datang dari profil ringkas yang tersimpan.
    // Email, no_hp, dan is_active datang dari `/auth/profil` — keduanya tidak
    // lagi disimpan di perangkat, jadi selama permintaan itu berjalan
    // ditampilkan sebagai "Memuat…" alih-alih "-" yang menyatakan data kosong.
    final ringkas = auth.user ?? {};
    final lengkap = auth.profilLengkap ?? const <String, dynamic>{};
    final belumAda = _memuatProfil ? 'Memuat…' : '-';

    final nama = (lengkap['nama'] ?? ringkas['nama'])?.toString() ?? 'Pengguna';
    final username = (lengkap['username'] ?? ringkas['username'])?.toString() ?? '-';
    final rawEmail = lengkap['email']?.toString() ?? '';
    final nikStr = lengkap['nik']?.toString() ?? '';
    final email = (rawEmail.isNotEmpty && rawEmail != username && rawEmail != nikStr)
        ? rawEmail
        : belumAda;
    final rawHp = lengkap['no_hp']?.toString() ?? '';
    final noHp = (rawHp.isNotEmpty && rawHp != '0000000000000000' && rawHp != '0') ? rawHp : '';
    final roleLabel = auth.userRoleLabel;
    // Pengguna yang sedang melihat layar ini pasti aktif — akun nonaktif
    // ditolak middleware. Nilai dari server tetap dipakai bila sudah ada.
    final isActive = lengkap.isEmpty ? true : lengkap['is_active'] != false;

    return _buildResponsiveSplit(
      leftFlex: 1,
      rightFlex: 2,
      left: Column(
        children: [
          // Profile Summary Card
          Container(
            decoration: BoxDecoration(
              color: context.latarKartu,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: context.garis,
              ),
            ),
            child: Column(
              children: [
                // Green Banner
                Container(
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B7A6A),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                // Avatar and Info
                Transform.translate(
                  offset: const Offset(0, -40),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: context.garis,
                        ),
                        child: const CircleAvatar(
                          radius: 36,
                          backgroundColor: Color(0xFF1B7A6A),
                          child: Icon(Icons.person, color: Colors.white, size: 42),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        nama,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.teksUtama),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B7A6A).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          roleLabel,
                          style: const TextStyle(
                            color: Color(0xFF1B7A6A),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              color: isActive ? const Color(0xFF166534) : const Color(0xFF991B1B),
                              size: 8,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isActive ? 'Aktif' : 'Non-Aktif',
                              style: TextStyle(
                                color: isActive ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: context.garis),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 14, color: context.teksKedua),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Username',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: context.teksKedua),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            username,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.email_outlined, size: 14, color: context.teksKedua),
                              SizedBox(width: 8),
                              Text(
                                'Email',
                                style: TextStyle(fontSize: 13, color: context.teksKedua),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Text(
                              email,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.end,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_outlined, size: 14, color: context.teksKedua),
                              SizedBox(width: 8),
                              Text(
                                'No HP / WA',
                                style: TextStyle(fontSize: 13, color: context.teksKedua),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Text(
                              noHp.isNotEmpty ? noHp : '-',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.end,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Ganti Password Card
          Container(
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
                const Row(
                  children: [
                    Icon(Icons.lock_outline, color: Color(0xFFEF4444), size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Ganti Password',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Minimal 6 karakter',
                  style: TextStyle(fontSize: 12, color: context.teksKedua),
                ),
                const SizedBox(height: 20),

                _buildPasswordField(
                  'Password Lama',
                  'Password saat ini',
                  _oldPasswordController,
                  _obscureOldPassword,
                  () => setState(() => _obscureOldPassword = !_obscureOldPassword),
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  'Password Baru',
                  'Minimal 6 karakter',
                  _newPasswordController,
                  _obscureNewPassword,
                  () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  'Konfirmasi Password Baru',
                  'Ulangi password baru',
                  _confirmPasswordController,
                  _obscureConfirmPassword,
                  () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),

                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: auth.isLoading ? null : _handleChangePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: auth.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.shield_outlined, size: 16),
                  label: Text(
                    auth.isLoading ? 'Memproses...' : 'Ubah Password',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      right: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.latarKartu,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1B7A6A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.edit_note, color: Color(0xFF1B7A6A), size: 20),
                SizedBox(width: 8),
                // Flexible + ellipsis: judul ini bersama ikonnya melampaui
                // lebar kartu di layar sempit.
                Flexible(
                  child: Text(
                    'Edit Informasi Profil',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Data akan diperbarui di akun Anda',
              style: TextStyle(fontSize: 12, color: context.teksKedua),
            ),

            const SizedBox(height: 24),

            Container(
              padding: EdgeInsets.all(paddingKartu(context)),
              decoration: BoxDecoration(
                color: context.latarLembut,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.garis),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person_outline, color: Color(0xFF1B7A6A), size: 16),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'INFORMASI AKUN',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF1B7A6A),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spasiXl),
                  // Dua kolom bersebelahan hanya di layar lebar.
                  //
                  // Di layar 360px tiap kolom cuma kebagian sekitar 130px
                  // setelah padding kartu, sehingga ikon, teks petunjuk, dan
                  // isian yang sedang diketik sama-sama terpotong. Ditumpuk,
                  // masing-masing mendapat lebar penuh.
                  _pasangKolom(
                    kiri: [
                      _buildLabel('Nama Lengkap *'),
                      _buildInputField(_namaController, 'Nama Lengkap', Icons.person_outline),
                    ],
                    kanan: [
                      _buildLabel('Username *'),
                      _buildInputField(
                        _usernameController,
                        'Username',
                        Icons.account_circle_outlined,
                      ),
                      const SizedBox(height: AppTheme.spasiXs),
                      Text(
                        'Hanya huruf dan angka, tanpa spasi',
                        style: TextStyle(fontSize: 11, color: context.teksTersier),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spasiL),
                  _pasangKolom(
                    kiri: [
                      _buildLabel('Email'),
                      _buildInputField(_emailController, 'Email', Icons.email_outlined),
                    ],
                    kanan: [
                      _buildLabel('No HP / WhatsApp'),
                      _buildInputField(
                        _noHpController,
                        'No HP',
                        Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(15),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Flexible: tombolnya berpadding 24 di kiri-kanan ditambah
                // label panjang, dan di layar sempit itu melampaui lebar kartu.
                // Tanpa ini tombol memaksa lebarnya sendiri dan meluber.
                Flexible(
                  child: ElevatedButton.icon(
                    onPressed: auth.isLoading ? null : _handleSaveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B7A6A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    icon: auth.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      auth.isLoading ? 'Menyimpan...' : 'Simpan Perubahan',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveSplit({
    required Widget left,
    required Widget right,
    int leftFlex = 1,
    int rightFlex = 1,
  }) {
    if (ResponsiveLayout.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [left, const SizedBox(height: 24), right],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        const SizedBox(width: 24),
        Expanded(flex: rightFlex, child: right),
      ],
    );
  }

  /// Dua kelompok isian: bersebelahan di layar lebar, bertumpuk di ponsel.
  ///
  /// Memisahkannya ke satu tempat supaya keempat pasangan kolom di formulir ini
  /// tidak perlu mengulang percabangan yang sama.
  Widget _pasangKolom({required List<Widget> kiri, required List<Widget> kanan}) {
    Widget kolom(List<Widget> isi) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: isi,
    );

    if (pakaiKartu(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          kolom(kiri),
          const SizedBox(height: AppTheme.spasiL),
          kolom(kanan),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: kolom(kiri)),
        const SizedBox(width: AppTheme.spasiL),
        Expanded(child: kolom(kanan)),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.teksUtama),
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      height: AppTheme.sasaranSentuh,
      constraints: const BoxConstraints(
        minHeight: AppTheme.sasaranSentuh,
        maxHeight: AppTheme.sasaranSentuh,
      ),
      decoration: BoxDecoration(
        color: context.latarKartu,
        border: Border.all(color: context.garis),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: 13, color: context.teksUtama),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: context.teksTersier),
          prefixIcon: Icon(icon, size: 18, color: context.teksTersier),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            maxWidth: 40,
            minHeight: AppTheme.sasaranSentuh,
            maxHeight: AppTheme.sasaranSentuh,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    String label,
    String hint,
    TextEditingController controller,
    bool obscure,
    VoidCallback onToggle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        Container(
          height: AppTheme.sasaranSentuh,
          constraints: const BoxConstraints(
            minHeight: AppTheme.sasaranSentuh,
            maxHeight: AppTheme.sasaranSentuh,
          ),
          decoration: BoxDecoration(
            color: context.latarLembut,
            border: Border.all(color: context.garis),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(fontSize: 13, color: context.teksUtama),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: context.teksTersier),
              prefixIcon: Icon(Icons.lock_outline, size: 16, color: context.teksTersier),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 40,
                maxWidth: 40,
                minHeight: AppTheme.sasaranSentuh,
                maxHeight: AppTheme.sasaranSentuh,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 16,
                  color: context.teksTersier,
                ),
                onPressed: onToggle,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                maxWidth: 40,
                minHeight: AppTheme.sasaranSentuh,
                maxHeight: AppTheme.sasaranSentuh,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}
