const https = require('https');

/**
 * Service pengirim notifikasi WhatsApp otomatis via WA Gateway (Fonnte API / Custom).
 *
 * Menggunakan native Node.js https module agar tidak membutuhkan dependensi eksternal.
 * Jika FONNTE_TOKEN belum dipasang di .env, sistem akan secara otomatis melakukan
 * simulasi pengiriman (log ke console) tanpa mengganggu jalannya aplikasi.
 */

function formatPhone(noHp) {
  if (!noHp) return '';
  let clean = String(noHp).replace(/\D/g, '');
  if (clean.startsWith('0')) {
    clean = '62' + clean.slice(1);
  }
  return clean;
}

/**
 * Kirim pesan WhatsApp generik.
 * @param {String} target - Nomor HP tujuan (misal: 08123456789 atau 628123456789)
 * @param {String} message - Teks pesan WA yang akan dikirim
 */
async function sendWA({ target, message }) {
  const token = process.env.FONNTE_TOKEN;
  const hpFormatted = formatPhone(target);

  if (!hpFormatted) {
    console.log('ℹ️ WA Service: Nomor HP tujuan tidak valid.');
    return false;
  }

  if (!token) {
    console.log('\n📲 [SIMULASI WA GATEWAY - FONNTE_TOKEN BELUM DIPASANG]');
    console.log(`  Target  : ${hpFormatted} (${target})`);
    console.log(`  Pesan   :\n${message}\n`);
    return true;
  }

  return new Promise((resolve) => {
    const postData = JSON.stringify({
      target: hpFormatted,
      message: message,
    });

    const options = {
      hostname: 'api.fonnte.com',
      path: '/send',
      method: 'POST',
      headers: {
        'Authorization': token,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.status) {
            console.log(`✅ WA Berhasil Terkirim ke ${hpFormatted}`);
          } else {
            console.log(`⚠️ WA Response Fonnte:`, parsed.reason || data);
          }
        } catch (e) {
          console.log(`ℹ️ WA Response Data:`, data);
        }
        resolve(true);
      });
    });

    req.on('error', (err) => {
      console.error('❌ WA Request Error:', err.message);
      resolve(false);
    });

    req.write(postData);
    req.end();
  });
}

/** Notifikasi WhatsApp untuk Kredensial Akun Baru Warga */
async function sendCredentialsWA({ userNama, noHp, username, password }) {
  const pesan = 
`Assalamualaikum, Yth. Bapak/Ibu *${userNama || 'Warga'}*,

Akun akses aplikasi Sistem Manajemen RT Anda telah dibuat:

• *Username*: ${username}
• *Password*: ${password}

Demi keamanan akun, mohon segera *GANTI password* setelah login pertama Anda melalui menu Profil.

Terima kasih.
— *Pengurus RT*`;

  if (noHp) {
    await sendWA({ target: noHp, message: pesan });
  }
}

/** Notifikasi WhatsApp untuk Sinyal Darurat Panic Button */
async function sendEmergencyWA({ userNama, alamat, noHp, tipeEmergency }) {
  const pesan = 
`🚨 *PERINGATAN DARURAT* 🚨

Bantuan darurat dibutuhkan segera oleh:
👤 *Nama*: ${userNama || 'Warga'}
🏠 *Alamat*: ${alamat || 'Wilayah RT'}
📞 *No. HP*: ${noHp || '-'}
⚠️ *Jenis Darurat*: ${tipeEmergency || 'Bahaya / Butuh Pertolongan'}

*Mohon Petugas Keamanan / Pengurus RT terdekat segera menuju ke lokasi!*`;

  if (noHp) {
    await sendWA({ target: noHp, message: pesan });
  }
}

/** Notifikasi WhatsApp untuk Penerbitan Tagihan Iuran Warga */
async function sendBillWA({ userNama, noHp, namaIuran, nominal, bulan, linkBayar }) {
  const pesan = 
`💳 *TAGIHAN IURAN RT*

Yth. Bpk/Ibu *${userNama || 'Warga'}*,

Tagihan iuran lingkungan untuk periode *${bulan || 'Bulan Ini'}* telah diterbitkan:
📌 *Jenis*: ${namaIuran || 'Iuran Wajib RT'}
💰 *Nominal*: Rp ${Number(nominal || 0).toLocaleString('id-ID')}

Silakan melakukan pembayaran praktis via QRIS / Transfer Bank melalui tautan berikut:
🔗 ${linkBayar || 'https://smart-community-rt.vercel.app'}

Terima kasih atas partisipasi Bpk/Ibu dalam menjaga kenyamanan lingkungan.
— *Pengurus RT*`;

  if (noHp) {
    await sendWA({ target: noHp, message: pesan });
  }
}

/**
 * Notifikasi WhatsApp saat pengaduan warga ditanggapi pengurus.
 *
 * Sejajar dengan `sendLetterApprovedWA`: warga mengajukan sesuatu, lalu
 * menunggu jawaban manusia. Tanpa ini ia tidak punya cara tahu bahwa jawabannya
 * sudah ada selain membuka aplikasi dan mengetuk aduannya satu per satu —
 * padahal justru saat berstatus "Diproses" tidak ada satu pun angka di
 * dasbornya yang berubah.
 *
 * Teks tanggapan ikut dikirim, bukan hanya "silakan buka aplikasi". Kalimat
 * yang menyuruh membuka aplikasi untuk membaca satu paragraf hanya memindahkan
 * pekerjaan ke warga; yang dipotong hanya bila panjangnya tidak wajar untuk WA.
 */
async function sendComplaintRepliedWA({ userNama, noHp, kodeTiket, judul, status, tanggapan }) {
  const label = {
    Diproses: '🔧 *SEDANG DIPROSES*',
    Selesai: '✅ *SELESAI DITANGANI*',
    Ditolak: '❌ *TIDAK DAPAT DIPROSES*',
  }[status] || `*${status || 'DITANGGAPI'}*`;

  const potong = (t, n = 400) => {
    const s = String(t || '').trim();
    return s.length > n ? `${s.slice(0, n)}…` : s;
  };

  const isiTanggapan = potong(tanggapan);

  const pesan =
`📣 *PENGADUAN ANDA DITANGGAPI*

Halo Bpk/Ibu *${userNama || 'Warga'}*,

Pengaduan Anda${kodeTiket ? ` [${kodeTiket}]` : ''} telah ditanggapi pengurus RT.
📌 *Perihal*: ${judul || '-'}
📊 *Status*: ${label}
${isiTanggapan ? `\n💬 *Tanggapan Pengurus*:\n${isiTanggapan}\n` : ''}
Rincian lengkapnya dapat dilihat di menu Pengaduan pada aplikasi:
🌐 https://smart-community-rt.vercel.app

Terima kasih sudah melapor.
— *Pengurus RT*`;

  if (noHp) {
    await sendWA({ target: noHp, message: pesan });
  }
}

/** Notifikasi WhatsApp untuk Persetujuan Surat Pengantar */
async function sendLetterApprovedWA({ userNama, noHp, jenisSurat }) {
  const pesan = 
`📄 *SURAT PENGANTAR RT DISETUJUI*

Halo Bpk/Ibu *${userNama || 'Warga'}*,

Permohonan *${jenisSurat || 'Surat Pengantar RT'}* Anda telah *DISETUJUI* dan ditandatangani oleh Pengurus RT.

Anda dapat mengunduh berkas PDF Surat Pengantar resmi langsung melalui aplikasi Web / Mobile:
🌐 https://smart-community-rt.vercel.app

Terima kasih.
— *Sekretaris RT*`;

  if (noHp) {
    await sendWA({ target: noHp, message: pesan });
  }
}

// `sendPatrolScheduleWA` dulu ada di sini — pesan penugasan jadwal ronda.
// Ikut hilang bersama modul ronda (commit `dd9104a`). Ia bertahan setelah
// modulnya dibongkar karena tidak menyentuh database sama sekali: ia hanya
// merangkai teks, jadi tidak ada tabel hilang yang membuatnya gagal dan tidak
// ada gejala apa pun yang menunjukkan ia sudah tak berpemanggil.
//
// Justru itu masalahnya. Fungsi yang diekspor tetapi tidak pernah dipanggil
// terbaca seperti fitur yang masih hidup, dan yang membaca berkas ini akan
// menyimpulkan penjadwalan ronda masih ada di sistem. Teksnya tetap terbaca di
// riwayat git bila modulnya suatu saat dihidupkan lagi.

module.exports = {
  sendWA,
  sendCredentialsWA,
  sendEmergencyWA,
  sendBillWA,
  sendLetterApprovedWA,
  sendComplaintRepliedWA,
};
