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

/** Notifikasi WhatsApp untuk Sinyal Darurat Panic Button */
async function sendEmergencyWA({ userNama, alamat, noHp, tipeEmergency }) {
  const pesan = 
`🚨 *PERINGATAN DARURAT RT 05* 🚨

Bantuan darurat dibutuhkan segera oleh:
👤 *Nama*: ${userNama || 'Warga RT'}
🏠 *Alamat*: ${alamat || 'Wilayah RT 05'}
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
`💳 *TAGIHAN IURAN RT 05*

Yth. Bpk/Ibu *${userNama || 'Warga RT'}*,

Tagihan iuran lingkungan untuk periode *${bulan || 'Bulan Ini'}* telah diterbitkan:
📌 *Jenis*: ${namaIuran || 'Iuran Wajib RT'}
💰 *Nominal*: Rp ${Number(nominal || 0).toLocaleString('id-ID')}

Silakan melakukan pembayaran praktis via QRIS / Transfer Bank melalui tautan berikut:
🔗 ${linkBayar || 'https://smart-community-rt.vercel.app'}

Terima kasih atas partisipasi Bpk/Ibu dalam menjaga kenyamanan lingkungan RT 05.
— *Pengurus RT 05*`;

  if (noHp) {
    await sendWA({ target: noHp, message: pesan });
  }
}

/** Notifikasi WhatsApp untuk Persetujuan Surat Pengantar */
async function sendLetterApprovedWA({ userNama, noHp, jenisSurat }) {
  const pesan = 
`📄 *SURAT PENGANTAR RT DISETUJUI*

Halo Bpk/Ibu *${userNama || 'Warga RT'}*,

Permohonan *${jenisSurat || 'Surat Pengantar RT'}* Anda telah *DISETUJUI* dan ditandatangani oleh Pengurus RT.

Anda dapat mengunduh berkas PDF Surat Pengantar resmi langsung melalui aplikasi Web / Mobile:
🌐 https://smart-community-rt.vercel.app

Terima kasih.
— *Sekretaris RT 05*`;

  if (noHp) {
    await sendWA({ target: noHp, message: pesan });
  }
}

module.exports = {
  sendWA,
  sendEmergencyWA,
  sendBillWA,
  sendLetterApprovedWA,
};
