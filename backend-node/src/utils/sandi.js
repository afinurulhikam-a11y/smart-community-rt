const crypto = require('crypto');

/**
 * Sandi awal acak untuk akun warga yang dibuat otomatis.
 *
 * ===================================================================
 * Kenapa tidak `123456`
 * ===================================================================
 *
 * Setiap akun warga dulu dibuat dengan sandi `123456` dan username berupa NIK.
 * Dua-duanya bisa ditebak: sandinya tertulis di kode sumber, dan NIK adalah
 * angka yang tercetak di KK maupun KTP — dokumen yang di satu lingkungan RT
 * beredar lebih luas daripada yang orang kira.
 *
 * Jadi siapa pun yang tahu NIK tetangganya bisa masuk sebagai orang itu, dan
 * membaca tagihannya, surat-suratnya, serta pengaduannya. Tidak perlu keahlian
 * apa pun. Selama sandinya sama untuk semua orang, satu-satunya yang melindungi
 * seorang warga adalah harapan bahwa ia sempat menggantinya lebih dulu.
 *
 * Sandi acak memutus itu di akarnya. Konsekuensinya memang lebih merepotkan —
 * pengurus harus menyampaikan sandi yang berbeda ke tiap warga alih-alih satu
 * kalimat untuk semua — tetapi kerepotan itu justru wujud dari keamanannya.
 *
 * Karena itu sandinya SELALU dikembalikan ke pemanggil sekali, saat dibuat.
 * Ia tidak pernah bisa dibaca lagi setelah itu: yang tersimpan hanya hash-nya.
 *
 * ===================================================================
 * Kenapa hurufnya dipilih
 * ===================================================================
 *
 * Tanpa 0/O dan 1/l/I. Sandi ini dibacakan lewat telepon, ditulis tangan di
 * kertas, dan diketik ulang di ponsel — situasi di mana huruf yang mirip
 * berubah menjadi keluhan "tidak bisa masuk" yang sebenarnya hanya salah baca.
 */
const HURUF = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

function sandiAcak(panjang = 10) {
  const bytes = crypto.randomBytes(panjang);
  let hasil = '';
  for (let i = 0; i < panjang; i++) hasil += HURUF[bytes[i] % HURUF.length];
  return hasil;
}

module.exports = { sandiAcak };
