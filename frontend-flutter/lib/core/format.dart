import 'package:intl/intl.dart';

/// Pemformatan bersama untuk seluruh aplikasi.
///
/// ===================================================================
/// Kenapa satu tempat
/// ===================================================================
///
/// Format rupiah sebelumnya ditulis ulang di lebih dari enam layar, dan
/// hasilnya BUKAN satu bentuk melainkan dua: sebagian memakai
/// `'Rp ${NumberFormat('#,###','id_ID').format(...)}'`, sebagian lagi
/// `NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ')`. Keduanya berbeda
/// dalam pemisah ribuan dan penempatan spasi, sehingga angka yang sama bisa
/// tampil berbeda di layar Kas RT dan di dasbor — pada aplikasi yang seluruh
/// kredibilitasnya bertumpu pada catatan uang.
///
/// Ada juga perbedaan pembulatan yang lebih halus: sebagian memakai `.toInt()`
/// (memotong) dan sebagian `.round()` (membulatkan). Untuk 1.500,6 yang satu
/// menulis 1.500 dan yang lain 1.501. Di sini dipakai `round()` secara
/// konsisten, karena memotong selalu merugikan ke satu arah.

final NumberFormat _angka = NumberFormat('#,###', 'id_ID');

/// "Rp 50.000". Selalu bentuk ini, di mana pun.
String rupiah(num? nilai) => 'Rp ${_angka.format((nilai ?? 0).round())}';

/// "50.000" — tanpa awalan, untuk kolom yang judulnya sudah menyebut Rupiah.
String angkaRupiah(num? nilai) => _angka.format((nilai ?? 0).round());

/// "5 Agustus 2026". Null menjadi tanda hubung, bukan teks kosong: sel tabel
/// yang kosong terbaca seperti kolomnya rusak.
String tanggalPanjang(DateTime? t) =>
    t == null ? '-' : DateFormat('d MMMM yyyy', 'id_ID').format(t);

/// "05 Agu 2026" — bentuk pendek untuk tabel yang rapat.
String tanggalPendek(DateTime? t) =>
    t == null ? '-' : DateFormat('dd MMM yyyy', 'id_ID').format(t);

/// `yyyy-MM-dd` dari komponen LOKAL, untuk dikirim ke backend.
///
/// TIDAK memakai `toIso8601String()`: ia mengubah ke UTC lebih dulu, sehingga
/// 1 Agustus pukul 00.30 WIB terkirim sebagai 31 Juli. Sehari penuh bergeser
/// tanpa ada yang tampak salah — dan pada penyaring laporan keuangan, pergeseran
/// itu memindahkan transaksi ke bulan yang keliru.
String tanggalKirim(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
