import 'package:flutter_test/flutter_test.dart';
import 'package:smart_community/providers/permission_provider.dart';

/// Uji untuk gerbang menu.
///
/// ===================================================================
/// Kenapa berkas ini ada
/// ===================================================================
///
/// `PermissionProvider` menentukan menu mana yang muncul untuk setiap peran dan
/// tombol Tambah/Ubah/Hapus mana yang digambar di setiap layar. Ia adalah
/// SELURUH mekanisme kendali akses di sisi tampilan, dan sampai sekarang tidak
/// punya satu pun uji.
///
/// Itu titik buta yang berbahaya bentuknya: kekeliruan di sini tidak membuat
/// aplikasi menabrak. Ia hanya membuat sebuah modul muncul untuk peran yang
/// salah, atau hilang untuk peran yang berhak — dua-duanya terlihat seperti
/// tampilan biasa, dan tidak satu pun dari 151 uji yang ada akan menyadarinya
/// karena semuanya merender dengan provider kosong.
///
/// Uji ini TIDAK menggantikan penegakan di backend. Menyembunyikan menu bukan
/// kontrol akses; `requirePermission` yang menjaga. Yang diuji di sini adalah
/// bahwa tampilannya tidak menjanjikan sesuatu yang akan berakhir 403, dan
/// tidak menyembunyikan sesuatu yang sebenarnya boleh.

/// Muatan seperti yang dikirim `GET /api/menu-akses/saya`.
Map<String, dynamic> muatan(String peran, List<Map<String, dynamic>> menus) => {
  'role': peran,
  'role_label': peran,
  'menus': menus,
};

Map<String, dynamic> menu(
  String kode, {
  bool lihat = false,
  bool tambah = false,
  bool ubah = false,
  bool hapus = false,
}) => {
  'kode': kode,
  'can_view': lihat,
  'can_create': tambah,
  'can_update': ubah,
  'can_delete': hapus,
};

void main() {
  group('Admin selalu berakses penuh', () {
    test('admin lolos tanpa menyentuh tabel izin sama sekali', () {
      final p = PermissionProvider()..terapkanData(muatan('admin', []));

      // Daftar menunya KOSONG, dan itu memang bentuk respons untuk admin.
      // Kalau jalan pintas `isAdmin` hilang, seorang administrator akan
      // kehilangan seluruh menunya — termasuk Menu & Akses, satu-satunya
      // layar yang bisa mengembalikannya. Terkunci permanen dari sistemnya
      // sendiri.
      expect(p.isAdmin, isTrue);
      expect(p.bolehLihat('keuangan.kas'), isTrue);
      expect(p.bolehTambah('pengaturan.reset'), isTrue);
      expect(p.bolehUbah('kependudukan.warga'), isTrue);
      expect(p.bolehHapus('menu.yang.tidak.pernah.ada'), isTrue);
    });
  });

  group('Peran non-admin dibatasi tabel izin', () {
    test('bendahara: penuh di kas, tidak ada akses ke surat', () {
      final p = PermissionProvider()
        ..terapkanData(muatan('bendahara', [
          menu('keuangan.kas', lihat: true, tambah: true, ubah: true, hapus: true),
          menu('kependudukan.warga', lihat: true),
        ]));

      expect(p.isAdmin, isFalse);
      expect(p.bolehTambah('keuangan.kas'), isTrue);
      expect(p.bolehHapus('keuangan.kas'), isTrue);

      // Tidak disebut dalam muatan sama sekali.
      expect(p.bolehLihat('layanan.surat'), isFalse);
      expect(p.bolehTambah('layanan.surat'), isFalse);
    });

    test('sekretaris hanya-lihat memunculkan lencana View, bukan tombol', () {
      final p = PermissionProvider()
        ..terapkanData(muatan('sekretaris', [
          menu('keuangan.kas', lihat: true),
        ]));

      // Inilah yang membedakan "boleh membuka" dari "boleh mengubah".
      // Bila hanyaLihat salah menjawab, layar menggambar tombol Tambah yang
      // pasti berakhir 403 — pengguna diberi harapan lalu ditolak.
      expect(p.hanyaLihat('keuangan.kas'), isTrue);
      expect(p.bolehLihat('keuangan.kas'), isTrue);
      expect(p.bolehTambah('keuangan.kas'), isFalse);
      expect(p.bolehUbah('keuangan.kas'), isFalse);
      expect(p.bolehHapus('keuangan.kas'), isFalse);
    });

    test('hanyaLihat salah untuk izin penuh maupun tanpa akses', () {
      final p = PermissionProvider()
        ..terapkanData(muatan('ketua_rt', [
          menu('kependudukan.warga', lihat: true, tambah: true, ubah: true, hapus: true),
        ]));

      expect(p.hanyaLihat('kependudukan.warga'), isFalse);
      // Tanpa akses juga bukan "hanya lihat" — kalau ini terbalik, banner
      // "Anda hanya bisa melihat" muncul di layar yang tidak boleh dibuka.
      expect(p.hanyaLihat('menu.tanpa.akses'), isFalse);
    });

    test('warga hanya melihat modulnya sendiri', () {
      final p = PermissionProvider()
        ..terapkanData(muatan('warga', [
          menu('keuangan.iuran', lihat: true),
          menu('aspirasi.pengaduan', lihat: true, tambah: true),
          menu('aspirasi.polling', lihat: true),
        ]));

      expect(p.bolehLihat('keuangan.iuran'), isTrue);
      expect(p.bolehTambah('aspirasi.pengaduan'), isTrue);

      // `create` pada polling berarti MEMBUAT polling, bukan memilih.
      // Warga memilih lewat izin `view`. Kalau ini bocor, seorang warga bisa
      // membuka polling baru atas nama RT.
      expect(p.bolehTambah('aspirasi.polling'), isFalse);

      // Modul pengurus tertutup rapat.
      expect(p.bolehLihat('keuangan.kas'), isFalse);
      expect(p.bolehLihat('pengaturan.akses'), isFalse);
      expect(p.bolehLihat('pengaturan.reset'), isFalse);
      expect(p.bolehLihat('kependudukan.warga'), isFalse);
    });
  });

  group('bolehLihatSalahSatu', () {
    test('grup menu muncul bila satu saja anggotanya boleh dilihat', () {
      final p = PermissionProvider()
        ..terapkanData(muatan('bendahara', [
          menu('keuangan.kas', lihat: true),
        ]));

      expect(p.bolehLihatSalahSatu(['keuangan.iuran', 'keuangan.kas']), isTrue);
      expect(p.bolehLihatSalahSatu(['layanan.surat', 'layanan.visitor']), isFalse);
      expect(p.bolehLihatSalahSatu([]), isFalse);
    });
  });

  group('bersihkan() saat logout', () {
    test('izin peran sebelumnya tidak terbawa ke sesi berikutnya', () {
      final p = PermissionProvider()
        ..terapkanData(muatan('admin', []));
      expect(p.isAdmin, isTrue);

      p.bersihkan();

      // Kalau ini gagal, warga yang masuk setelah admin di perangkat yang sama
      // akan melihat SELURUH menu — termasuk Reset Sistem — sampai
      // pemuatan izin yang baru selesai.
      expect(p.isAdmin, isFalse);
      expect(p.role, isEmpty);
      expect(p.sudahDimuat, isFalse);
      expect(p.bolehLihat('keuangan.kas'), isFalse);
      expect(p.bolehLihat('pengaturan.reset'), isFalse);
    });
  });

  group('Muatan cacat tidak boleh membuka akses', () {
    test('menus null atau bukan daftar diperlakukan sebagai tanpa izin', () {
      final p = PermissionProvider()
        ..terapkanData({'role': 'warga', 'menus': null});

      expect(p.bolehLihat('keuangan.kas'), isFalse);
      expect(p.bolehTambah('keuangan.kas'), isFalse);
    });

    test('nilai izin non-boolean tidak dianggap true', () {
      // Backend mengirim boolean, tetapi bila suatu saat berubah menjadi
      // 1/0 atau "true", `== true` menjadikannya false — GAGAL TERTUTUP.
      // Menutup keliru berarti menu hilang dan segera dilaporkan orang;
      // membuka keliru berarti tidak ada yang menyadarinya.
      final p = PermissionProvider()
        ..terapkanData({
          'role': 'warga',
          'menus': [
            {'kode': 'keuangan.kas', 'can_view': 1, 'can_create': 'true'},
          ],
        });

      expect(p.bolehLihat('keuangan.kas'), isFalse);
      expect(p.bolehTambah('keuangan.kas'), isFalse);
    });
  });
}
