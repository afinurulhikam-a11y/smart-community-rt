import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../core/theme/warna_konteks.dart';
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../widgets/tabel_responsif.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedRoleFilter = 'semua';
  int _activeTab = 0; // 0: Semua Pengguna, 1: Menunggu Persetujuan

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    final userProvider = context.read<UserProvider>();
    userProvider.fetchUsers(
      role: _selectedRoleFilter == 'semua' ? null : _selectedRoleFilter,
      search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
    );
    userProvider.fetchPendingUsers();
  }

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(teks),
        backgroundColor: sukses ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!pakaiKartu(context))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF1B7A6A), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Pengaturan / Manajemen Pengguna',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
              ElevatedButton.icon(
                onPressed: () => _showDialogTambahUser(),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text('Tambah Akun Baru', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B7A6A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Navigation Tabs & Controls
        Consumer<UserProvider>(
          builder: (context, provider, _) {
            final countPending = provider.pendingUsers.length;

            return Column(
              children: [
                // Filter Tabs
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Semua Pengguna'),
                      selected: _activeTab == 0,
                      onSelected: (val) {
                        if (val) setState(() => _activeTab = 0);
                      },
                      selectedColor: const Color(0xFF1B7A6A),
                      labelStyle: TextStyle(
                        color: _activeTab == 0 ? Colors.white : context.teksUtama,
                        fontWeight: _activeTab == 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Menunggu Persetujuan'),
                          if (countPending > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _activeTab == 1 ? Colors.white : const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$countPending',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _activeTab == 1 ? const Color(0xFF1B7A6A) : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      selected: _activeTab == 1,
                      onSelected: (val) {
                        if (val) setState(() => _activeTab = 1);
                      },
                      selectedColor: const Color(0xFF1B7A6A),
                      labelStyle: TextStyle(
                        color: _activeTab == 1 ? Colors.white : context.teksUtama,
                        fontWeight: _activeTab == 1 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Search & Filter controls (only for Tab 0)
                if (_activeTab == 0) ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: pakaiKartu(context) ? double.infinity : 280,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Cari nama, email, NIK...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onSubmitted: (_) => _loadData(),
                        ),
                      ),
                      DropdownButton<String>(
                        value: _selectedRoleFilter,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'semua', child: Text('Semua Peran')),
                          DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                          DropdownMenuItem(value: 'ketua_rt', child: Text('Ketua RT')),
                          DropdownMenuItem(value: 'sekretaris', child: Text('Sekretaris')),
                          DropdownMenuItem(value: 'bendahara', child: Text('Bendahara')),
                          DropdownMenuItem(value: 'warga', child: Text('Warga')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedRoleFilter = val);
                            _loadData();
                          }
                        },
                      ),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.latarKartu,
                          foregroundColor: context.teksUtama,
                          elevation: 0,
                          side: BorderSide(color: context.garis),
                        ),
                        child: const Text('Cari'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),

        // Content Area
        Consumer<UserProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final displayList = _activeTab == 0 ? provider.users : provider.pendingUsers;

            if (displayList.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: context.latarKartu,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.garis),
                ),
                child: Center(
                  child: Text(
                    _activeTab == 0 ? 'Tidak ada akun pengguna ditemukan.' : 'Tidak ada pendaftaran pending.',
                    style: TextStyle(color: context.teksKedua),
                  ),
                ),
              );
            }

            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.latarKartu,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.garis),
              ),
              child: Padding(
                padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                child: TabelResponsif(
                  tinggiBarisMaks: 70,
                  kolom: const ['NO', 'PENGGUNA', 'PERAN', 'STATUS', 'TERDAFTAR'],
                  baris: displayList.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final user = entry.value;

                    final isActive = user.isActive;
                    final roleLabel = user.roleLabel;

                    return BarisTabel(
                      sel: [
                        SelTabel.teks('NO', '$index', sembunyiDiKartu: true),
                        SelTabel(
                          'PENGGUNA',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                user.nama,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: context.teksUtama,
                                ),
                              ),
                              Text(
                                '${user.email} ${user.nik != null ? "• NIK: ${user.nik}" : ""}',
                                style: TextStyle(fontSize: 12, color: context.teksKedua),
                              ),
                              if (user.noHp != null && user.noHp!.isNotEmpty)
                                Text(
                                  'HP: ${user.noHp}',
                                  style: TextStyle(fontSize: 11, color: context.teksTersier),
                                ),
                            ],
                          ),
                          utama: true,
                        ),
                        SelTabel(
                          'PERAN',
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getRoleBgColor(user.role),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _getRoleTextColor(user.role),
                              ),
                            ),
                          ),
                        ),
                        SelTabel(
                          'STATUS',
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isActive ? 'Aktif' : 'Non-aktif',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ),
                        SelTabel.teks(
                          'TERDAFTAR',
                          user.createdAt != null
                              ? DateFormat('dd MMM yyyy').format(user.createdAt!)
                              : '-',
                        ),
                      ],
                      aksi: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_activeTab == 1) ...[
                            // Opsi Setujui Akun Pending
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
                              tooltip: 'Setujui & Aktifkan',
                              onPressed: () async {
                                if (user.id != null) {
                                  final ok = await provider.updateUserStatus(user.id!, true);
                                  if (ok) _pesan('Akun ${user.nama} berhasil disetujui');
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444)),
                              tooltip: 'Tolak / Hapus',
                              onPressed: () async {
                                if (user.id != null) {
                                  final confirm = await _showConfirmDialog(
                                    'Tolak Pendaftaran',
                                    'Apakah Anda yakin ingin menolak pendaftaran ${user.nama}?',
                                  );
                                  if (confirm == true) {
                                    final ok = await provider.deleteUser(user.id!);
                                    if (ok) _pesan('Pendaftaran ${user.nama} berhasil ditolak');
                                  }
                                }
                              },
                            ),
                          ] else ...[
                            // Sakelar Aktif/Nonaktif
                            Switch(
                              value: isActive,
                              activeThumbColor: const Color(0xFF10B981),
                              onChanged: (val) async {
                                if (user.id != null) {
                                  final ok = await provider.updateUserStatus(user.id!, val);
                                  if (ok) {
                                    _pesan(val ? 'Akun diaktifkan' : 'Akun dinonaktifkan');
                                  } else if (provider.errorMessage != null) {
                                    _pesan(provider.errorMessage!, sukses: false);
                                  }
                                }
                              },
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (val) {
                                if (val == 'role') {
                                  _showDialogUbahRole(user);
                                } else if (val == 'password') {
                                  _showDialogResetPassword(user);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'role',
                                  child: Row(
                                    children: [
                                      Icon(Icons.badge_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Ubah Peran (Role)'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'password',
                                  child: Row(
                                    children: [
                                      Icon(Icons.lock_reset, size: 18),
                                      SizedBox(width: 8),
                                      Text('Reset Kata Sandi'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Color _getRoleBgColor(String role) {
    switch (role) {
      case 'admin':
        return const Color(0xFFFEE2E2);
      case 'ketua_rt':
        return const Color(0xFFDBEAFE);
      case 'sekretaris':
      case 'bendahara':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color _getRoleTextColor(String role) {
    switch (role) {
      case 'admin':
        return const Color(0xFFEF4444);
      case 'ketua_rt':
        return const Color(0xFF2563EB);
      case 'sekretaris':
      case 'bendahara':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF4B5563);
    }
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tolak', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDialogTambahUser() {
    final namaCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final hpCtrl = TextEditingController();
    final kkCtrl = TextEditingController();
    final nikCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    String selectedRole = 'warga';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Akun Pengguna Baru'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: namaCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Lengkap *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Kata Sandi *'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Peran / Role'),
                  items: const [
                    DropdownMenuItem(value: 'warga', child: Text('Warga')),
                    DropdownMenuItem(value: 'ketua_rt', child: Text('Ketua RT')),
                    DropdownMenuItem(value: 'sekretaris', child: Text('Sekretaris')),
                    DropdownMenuItem(value: 'bendahara', child: Text('Bendahara')),
                    DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                  ],
                  onChanged: (val) {
                    if (val != null) selectedRole = val;
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nikCtrl,
                  decoration: const InputDecoration(labelText: 'NIK (Opsional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hpCtrl,
                  decoration: const InputDecoration(labelText: 'No HP (Opsional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: kkCtrl,
                  decoration: const InputDecoration(labelText: 'No KK (Opsional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: alamatCtrl,
                  decoration: const InputDecoration(labelText: 'Alamat (Opsional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A6A)),
            onPressed: () async {
              if (namaCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passwordCtrl.text.trim().isEmpty) {
                _pesan('Nama, email, dan kata sandi wajib diisi', sukses: false);
                return;
              }
              Navigator.pop(ctx);
              final provider = context.read<UserProvider>();
              final ok = await provider.createUser(
                nama: namaCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                password: passwordCtrl.text.trim(),
                role: selectedRole,
                noHp: hpCtrl.text.trim().isEmpty ? null : hpCtrl.text.trim(),
                noKk: kkCtrl.text.trim().isEmpty ? null : kkCtrl.text.trim(),
                alamat: alamatCtrl.text.trim().isEmpty ? null : alamatCtrl.text.trim(),
              );

              if (ok) {
                _pesan('Berhasil membuat pengguna baru');
              } else if (provider.errorMessage != null) {
                _pesan(provider.errorMessage!, sukses: false);
              }
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDialogUbahRole(UserModel user) {
    String selectedRole = user.role;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ubah Peran ${user.nama}'),
        content: DropdownButtonFormField<String>(
          initialValue: selectedRole,
          decoration: const InputDecoration(labelText: 'Peran / Role Baru'),
          items: const [
            DropdownMenuItem(value: 'warga', child: Text('Warga')),
            DropdownMenuItem(value: 'ketua_rt', child: Text('Ketua RT')),
            DropdownMenuItem(value: 'sekretaris', child: Text('Sekretaris')),
            DropdownMenuItem(value: 'bendahara', child: Text('Bendahara')),
            DropdownMenuItem(value: 'admin', child: Text('Administrator')),
          ],
          onChanged: (val) {
            if (val != null) selectedRole = val;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A6A)),
            onPressed: () async {
              if (user.id == null) return;
              Navigator.pop(ctx);
              final provider = context.read<UserProvider>();
              final ok = await provider.updateUserRole(user.id!, selectedRole);

              if (ok) {
                _pesan('Peran ${user.nama} berhasil diperbarui');
              } else if (provider.errorMessage != null) {
                _pesan(provider.errorMessage!, sukses: false);
              }
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDialogResetPassword(UserModel user) {
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset Kata Sandi ${user.nama}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Masukkan kata sandi baru untuk ${user.nama}:', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Kata Sandi Baru (Min. 8 Karakter)',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A6A)),
            onPressed: () async {
              final newPass = passwordCtrl.text.trim();
              if (newPass.length < 8) {
                _pesan('Kata sandi minimal 8 karakter', sukses: false);
                return;
              }

              final nikOrUsername = user.nik ?? user.username ?? user.email;
              if (nikOrUsername.isEmpty) {
                _pesan('User tidak memiliki NIK / Username untuk diset', sukses: false);
                return;
              }

              Navigator.pop(ctx);
              final provider = context.read<UserProvider>();
              final ok = await provider.updateUserCredentials(
                nik: nikOrUsername,
                password: newPass,
              );

              if (ok) {
                _pesan('Kata sandi ${user.nama} berhasil diperbarui');
              } else if (provider.errorMessage != null) {
                _pesan(provider.errorMessage!, sukses: false);
              }
            },
            child: const Text('Simpan Sandi', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
