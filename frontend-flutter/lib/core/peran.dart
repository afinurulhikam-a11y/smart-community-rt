/// Daftar peran pengguna — satu-satunya di sisi klien.
///
/// ===================================================================
/// Kenapa berkas ini ada
/// ===================================================================
///
/// Peran `ketua_rw` ditambahkan di backend beserta seluruh baris izinnya,
/// tetapi klien menyimpan daftar perannya sendiri di EMPAT tempat terpisah,
/// dan tidak satu pun ikut diperbarui. Yang paling merusak ada di `AuthGate`:
///
/// ```dart
/// const roleDikenal = {'admin', 'ketua_rt', 'sekretaris', 'bendahara', 'warga'};
/// return roleDikenal.contains(auth.userRole) ? const MainDashboard() : const LoginScreen();
/// ```
///
/// Akibatnya login sebagai Ketua RW **berhasil** — token tersimpan, server
/// menjawab 200 — lalu layarnya kembali ke Login tanpa satu pun pesan. Dari
/// sisi pemakai: menekan Masuk tidak terjadi apa-apa. Tidak ada galat untuk
/// dibaca, tidak ada yang bisa ditebak, dan tidak ada uji yang melihatnya
/// karena semuanya benar menurut kodenya masing-masing.
///
/// Daftar yang ditulis di empat tempat adalah daftar yang cepat atau lambat
/// berbeda di salah satunya. Satu peran baru berikutnya akan mengulang hal
/// yang sama persis, kecuali daftarnya cuma satu.
///
/// Cermin dari `users.role` di backend — peran adalah VARCHAR, bukan tabel
/// (lihat `roles` yang sudah dihapus di v15).
library;

class Peran {
  const Peran._();

  static const String admin = 'admin';
  static const String ketuaRw = 'ketua_rw';
  static const String ketuaRt = 'ketua_rt';
  static const String sekretaris = 'sekretaris';
  static const String bendahara = 'bendahara';
  static const String warga = 'warga';

  /// Peran warisan. `pengurus_rt` tidak pernah dimiliki akun mana pun dan
  /// sudah dihapus dari backend, tetapi tetap dikenali di sini supaya token
  /// lama — yang berumur tujuh hari — tidak mendadak terlempar ke layar login.
  static const String pengurusRtLawas = 'pengurus_rt';

  /// Setiap peran yang boleh masuk ke aplikasi.
  ///
  /// Peran di luar daftar ini dikembalikan ke layar Login. Itu perilaku yang
  /// benar — sebuah peran yang tidak dikenal klien tidak punya menu, tidak
  /// punya beranda, dan tidak ada yang bisa ia lakukan — tetapi ia HANYA benar
  /// selama daftarnya lengkap.
  static const Set<String> semua = {
    admin,
    ketuaRw,
    ketuaRt,
    sekretaris,
    bendahara,
    warga,
    pengurusRtLawas,
  };

  /// Peran yang boleh melihat lebih dari satu RT.
  ///
  /// Cermin dari `PERAN_LINTAS_RT` di `src/utils/lingkup-rt.js`. Dipakai
  /// menentukan apakah pemilih RT ditampilkan — meski keputusan sebenarnya
  /// tetap di server, yang menyaring isinya apa pun yang dikirim klien.
  static const Set<String> lintasRt = {admin, ketuaRw};

  /// Bukan warga: berhak memanggil endpoint yang tertutup untuk warga.
  ///
  /// Dipakai supaya klien tidak menembakkan permintaan yang sudah pasti
  /// ditolak 403. `ketua_rw` termasuk di sini: ia memegang izin LIHAT pada
  /// hampir seluruh modul, jadi mengeluarkannya berarti layar-layar itu
  /// membiarkan dirinya kosong tanpa pernah bertanya ke server.
  static const Set<String> pengurus = {
    admin,
    ketuaRw,
    ketuaRt,
    sekretaris,
    bendahara,
    pengurusRtLawas,
  };

  static bool dikenal(String role) => semua.contains(role);
  static bool bolehLintasRt(String role) => lintasRt.contains(role);

  /// Nama yang ditampilkan. Peran tak dikenal jatuh ke 'Pengguna' alih-alih
  /// memunculkan kode mentah seperti `ketua_rw` di layar.
  static String label(String role) {
    switch (role) {
      case admin:
        return 'Administrator';
      case ketuaRw:
        return 'Ketua RW';
      case ketuaRt:
        return 'Ketua RT';
      case sekretaris:
        return 'Sekretaris';
      case bendahara:
        return 'Bendahara';
      case warga:
        return 'Warga RT';
      case pengurusRtLawas:
        return 'Pengurus RT';
      default:
        return 'Pengguna';
    }
  }
}
