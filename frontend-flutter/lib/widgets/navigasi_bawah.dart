import 'package:flutter/material.dart';

import '../providers/permission_provider.dart';

/// Satu tujuan di bilah navigasi bawah.
class TujuanNav {
  /// Indeks menu yang sama dipakai sidebar dan `_buildBody` — sengaja, supaya
  /// navigasi bawah tidak menjadi daftar menu kedua yang harus ikut dirawat.
  final int indeks;
  final IconData ikon;
  final IconData ikonAktif;
  final String label;

  /// Kode izin yang harus dimiliki role. `null` berarti selalu tampil.
  final String? kodeIzin;

  const TujuanNav({
    required this.indeks,
    required this.ikon,
    required this.ikonAktif,
    required this.label,
    this.kodeIzin,
  });
}

/// Indeks khusus: bukan sebuah layar, melainkan perintah membuka laci menu.
///
/// Navigasi bawah Android hanya sanggup menampung 3–5 tujuan sebelum labelnya
/// terpotong. Menu aplikasi ini ada 19, jadi empat yang paling sering dibuka
/// naik ke bilah bawah dan sisanya tetap di laci lewat tujuan "Lainnya".
const int indeksLainnya = -1;

/// Nama menu untuk judul AppBar.
///
/// Beberapa menu berganti nama menurut role: menu 21 adalah "Iuran Warga" bagi
/// pengurus dan "Tagihan Saya" bagi warga, karena layarnya memang berbeda.
String judulMenu(int indeks, {required bool warga}) {
  switch (indeks) {
    case 0:
      return 'Dashboard';
    case 12:
      return 'Data Warga';
    case 13:
      return 'Bantuan Sosial';
    case 14:
      return 'Statistik';
    case 21:
      return warga ? 'Tagihan Saya' : 'Iuran Warga';
    case 22:
      return warga ? 'Laporan Kas RT' : 'Kas RT';
    case 23:
      return 'Dana BOP';
    case 31:
      return 'Data Barang';
    case 32:
      return warga ? 'Pinjam Barang' : 'Peminjaman';
    case 43:
      return warga ? 'Buku Tamu Saya' : 'E-Visitor';
    case 44:
      return warga ? 'Pengajuan Surat' : 'Surat Menyurat';
    case 50:
      return 'Agenda & Kegiatan';
    case 60:
      return 'Status Darurat';
    case 61:
      return 'Pengaduan';
    case 62:
      return 'Polling Warga';
    case 81:
      return 'Profil Saya';
    case 84:
      return 'Log Aktivitas';
    case 85:
      return 'Menu & Akses';
    case 86:
      return 'Reset Sistem';
    default:
      return 'Dashboard';
  }
}

/// Empat tujuan tetap warga, diurutkan menurut yang paling sering dibuka.
const List<TujuanNav> _tujuanWarga = [
  TujuanNav(indeks: 0, ikon: Icons.home_outlined, ikonAktif: Icons.home_rounded, label: 'Dashboard'),
  TujuanNav(
    indeks: 21,
    ikon: Icons.receipt_long_outlined,
    ikonAktif: Icons.receipt_long_rounded,
    label: 'Tagihan',
    kodeIzin: 'keuangan.iuran',
  ),
  TujuanNav(
    indeks: 44,
    ikon: Icons.mail_outline_rounded,
    ikonAktif: Icons.mail_rounded,
    label: 'Surat',
    kodeIzin: 'layanan.surat',
  ),
  TujuanNav(
    indeks: 61,
    ikon: Icons.support_agent_outlined,
    ikonAktif: Icons.support_agent_rounded,
    label: 'Pengaduan',
    kodeIzin: 'aspirasi.pengaduan',
  ),
];

/// Empat tujuan tetap pengurus.
const List<TujuanNav> _tujuanPengurus = [
  TujuanNav(
    indeks: 0,
    ikon: Icons.dashboard_outlined,
    ikonAktif: Icons.dashboard_rounded,
    label: 'Dashboard',
  ),
  TujuanNav(
    indeks: 12,
    ikon: Icons.groups_outlined,
    ikonAktif: Icons.groups_rounded,
    label: 'Warga',
    kodeIzin: 'kependudukan.warga',
  ),
  TujuanNav(
    indeks: 21,
    ikon: Icons.receipt_long_outlined,
    ikonAktif: Icons.receipt_long_rounded,
    label: 'Iuran',
    kodeIzin: 'keuangan.iuran',
  ),
  TujuanNav(
    indeks: 22,
    ikon: Icons.account_balance_wallet_outlined,
    ikonAktif: Icons.account_balance_wallet_rounded,
    label: 'Kas RT',
    kodeIzin: 'keuangan.kas',
  ),
];

/// Tujuan yang benar-benar boleh dilihat role ini.
///
/// Disaring lewat [PermissionProvider], bukan nama role — sejalan dengan
/// sidebar. Kalau tidak, admin yang mencabut satu modul di Menu & Akses akan
/// meninggalkan tombol yang berujung 403 di bilah bawah.
List<TujuanNav> tujuanNavigasi({required bool warga, required PermissionProvider izin}) {
  final semua = warga ? _tujuanWarga : _tujuanPengurus;
  return semua.where((t) => t.kodeIzin == null || izin.bolehLihat(t.kodeIzin!)).toList();
}

/// Bilah navigasi bawah, plus tujuan terakhir "Lainnya" yang membuka laci.
class NavigasiBawah extends StatelessWidget {
  final List<TujuanNav> tujuan;
  final int indeksMenuTerpilih;
  final ValueChanged<int> onPilihMenu;
  final VoidCallback onBukaLaci;

  const NavigasiBawah({
    super.key,
    required this.tujuan,
    required this.indeksMenuTerpilih,
    required this.onPilihMenu,
    required this.onBukaLaci,
  });

  @override
  Widget build(BuildContext context) {
    // Menu yang tidak ada di bilah bawah — Agenda, Peminjaman, Reset Sistem —
    // dibuka dari laci. Saat salah satunya aktif, "Lainnya" yang disorot,
    // supaya bilah bawah tidak pernah menunjukkan tujuan yang keliru.
    final posisi = tujuan.indexWhere((t) => t.indeks == indeksMenuTerpilih);
    final terpilih = posisi >= 0 ? posisi : tujuan.length;

    return NavigationBar(
      selectedIndex: terpilih,
      onDestinationSelected: (i) {
        if (i == tujuan.length) {
          onBukaLaci();
        } else {
          onPilihMenu(tujuan[i].indeks);
        }
      },
      destinations: [
        for (final t in tujuan)
          NavigationDestination(
            icon: Icon(t.ikon),
            selectedIcon: Icon(t.ikonAktif),
            label: t.label,
          ),
        const NavigationDestination(
          icon: Icon(Icons.menu_rounded),
          selectedIcon: Icon(Icons.menu_open_rounded),
          label: 'Lainnya',
        ),
      ],
    );
  }
}
