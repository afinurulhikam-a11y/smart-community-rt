require('dotenv').config();

// Dijalankan SEBELUM apa pun yang lain. Kalau konfigurasi kurang, satu-satunya
// waktu yang berguna untuk mengetahuinya adalah sekarang — bukan setelah server
// menerima permintaan pertama dan diam-diam memakai nilai bawaan.
require('./config/periksa-env').periksaEnv();

const express = require('express');
const compression = require('compression');
const morgan = require('morgan');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const http = require('http');
const path = require('path');

// Config
const { initWebSocket } = require('./config/websocket');
const { testConnection } = require('./config/database');
const { periksaSaatStartup } = require('./config/midtrans');

// Routes
const authRoutes = require('./routes/auth.routes');
const userRoutes = require('./routes/user.routes');
const billRoutes = require('./routes/bill.routes');
const meteranRoutes = require('./routes/meteran.routes');
const jenisIuranRoutes = require('./routes/jenis_iuran.routes');
const kategoriKasRoutes = require('./routes/kategori_kas.routes');
const kategoriBopRoutes = require('./routes/kategori_bop.routes');
const alokasiBopRoutes = require('./routes/alokasi_bop.routes');
const financeRoutes = require('./routes/finance.routes');
const letterRoutes = require('./routes/letter.routes');
const emergencyRoutes = require('./routes/emergency.routes');
const sensorRoutes = require('./routes/sensor.routes');
const demographicsRoutes = require('./routes/demographics.routes');
const announcementRoutes = require('./routes/announcement.routes');
const complaintRoutes = require('./routes/complaint.routes');
const agendaRoutes = require('./routes/agenda.routes');
const pollingRoutes = require('./routes/polling.routes');
const visitorRoutes = require('./routes/visitor.routes');
const bantuanSosialRoutes = require('./routes/bantuan_sosial.routes');
const inventoryRoutes = require('./routes/inventory.routes');
const familyRoutes = require('./routes/family.routes');
const wargaRoutes = require('./routes/warga.routes');
const bopRoutes = require('./routes/bop.routes');
const logRoutes = require('./routes/log.routes');
const menuAksesRoutes = require('./routes/menu_akses.routes');
const rtRoutes = require('./routes/rt.routes');
const resetRoutes = require('./routes/reset.routes');
const paymentRoutes = require('./routes/payment.routes');

const uploadRoutes = require('./routes/upload.routes');
const unduhRoutes = require('./routes/unduh.routes');
const notificationRoutes = require('./routes/notification.routes');
const { initMqtt } = require('./config/mqtt');

const app = express();
const PORT = process.env.PORT || 3000;

// ========================
// Security Middleware
// ========================
// Helmet menyetel header keamanan HTTP (X-Content-Type-Options, X-Frame-Options, dll)
app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));

// Rate limiter untuk endpoint login — maks 5 percobaan per menit per IP
const loginLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Terlalu banyak percobaan login. Silakan coba lagi setelah 1 menit.',
  },
});

// Untuk jalur yang rahasianya pendek dan bisa ditebak paksa: PIN darurat 4
// angka, sandi lama, dan pengaturan ulang sandi. Lebih ketat dari login karena
// tidak ada alasan sah untuk memanggilnya berkali-kali dalam semenit.
const limiterKetat = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Terlalu banyak percobaan. Silakan tunggu 1 menit sebelum mencoba lagi.',
  },
});

/**
 * Header yang boleh dikirim klien.
 *
 * `ngrok-skip-browser-warning` WAJIB ada di sini. Setiap klien browser —
 * Flutter Web maupun `frontend-web` — mengirimkannya pada SETIAP permintaan
 * untuk menghindari halaman peringatan HTML dari ngrok paket gratis. Header itu
 * bukan header sederhana, jadi browser mendahuluinya dengan preflight; kalau
 * namanya tidak disebut di sini, preflight gagal dan SELURUH permintaan
 * diblokir sebelum sempat dikirim. Gejalanya menyesatkan: di aplikasi terlihat
 * seperti server mati, padahal server tidak pernah dihubungi.
 */
const HEADER_DIIZINKAN =
  'Content-Type, Authorization, Origin, Accept, X-Requested-With, ngrok-skip-browser-warning';

/**
 * ===================================================================
 * Asal yang boleh memanggil API
 * ===================================================================
 *
 * Bentuk lamanya satu nilai yang dipantulkan mentah dengan cadangan `*`.
 * Dua akibatnya:
 *
 *   1. Tanpa CORS_ORIGIN, API terbuka untuk SETIAP situs di internet.
 *   2. Menyetelnya justru memutus pengembangan: `flutter run -d chrome`
 *      memilih PORT ACAK setiap kali dijalankan, jadi satu origin tetap akan
 *      salah pada pemanggilan berikutnya.
 *
 * Karena itu daftarnya kini JAMAK, dan origin pemanggil dipantulkan setelah
 * dicocokkan — peramban hanya menerima satu nilai pada
 * `Access-Control-Allow-Origin`, bukan sebuah daftar.
 *
 * ===================================================================
 * Kenapa cadangannya TETAP `*`, bukan "localhost saja"
 * ===================================================================
 *
 * Percobaan pertama mengganti cadangannya menjadi "localhost port berapa
 * pun". Itu lebih aman di atas kertas dan **langsung mematikan produksi**:
 * pemasangan di Railway tidak menyetel CORS_ORIGIN karena selama ini `*`
 * memang cukup, sehingga klien di Vercel mendadak tidak menerima satu pun
 * header dan setiap permintaan diblokir peramban. Gejalanya "Failed to
 * fetch" — yang terbaca sebagai server mati, padahal servernya sehat.
 *
 * Aturannya sudah tertulis di repo ini untuk `IZINKAN_TOKEN_QUERY`:
 * **sebuah deploy yang lupa menyetel variabel tidak boleh mematikan klien
 * yang sudah jalan.** Pengetatan yang mengubah bawaan dari permisif menjadi
 * ketat melanggarnya, dan kerusakannya baru terlihat di produksi.
 *
 * Jadi bawaannya kembali permisif dan pengetatannya menjadi TINDAKAN SADAR:
 *
 *   (tidak disetel)                             terbuka + peringatan keras
 *   CORS_ORIGIN=https://rt.example.com          satu domain
 *   CORS_ORIGIN=https://a.example.com,https://b.id  beberapa domain
 *   CORS_ORIGIN=lokal                           localhost port berapa pun
 *
 * `lokal` disediakan supaya pengembangan bisa diketatkan tanpa harus menebak
 * port acak Flutter — nilai yang dulu menjadi cadangan, kini menjadi pilihan.
 */
const CORS_DAFTAR = (process.env.CORS_ORIGIN || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

/** Tidak disetel sama sekali, atau disetel `*` — dua-duanya berarti terbuka. */
const CORS_TERBUKA = CORS_DAFTAR.length === 0 || CORS_DAFTAR.includes('*');

/** Kata kunci untuk "localhost port berapa pun". */
const CORS_LOKAL = CORS_DAFTAR.includes('lokal');

/** Origin pengembangan: localhost / 127.0.0.1 / [::1] pada port berapa pun. */
const POLA_LOKAL = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;

/**
 * Origin yang PERNAH ditolak, supaya tiap origin hanya dicatat sekali.
 *
 * Tanpa ini satu klien yang salah konfigurasi membanjiri log dengan baris
 * yang sama pada setiap permintaan, dan baris yang membanjir adalah baris
 * yang berhenti dibaca — padahal justru inilah satu-satunya petunjuk ketika
 * sebuah klien mendadak tidak bisa memanggil API.
 */
const asalDitolak = new Set();

/**
 * Nilai `Access-Control-Allow-Origin` untuk sebuah permintaan.
 *
 * `null` berarti tidak ada header yang dipasang — permintaan tanpa `Origin`
 * (curl, aplikasi Flutter di Android/Windows, webhook Midtrans) memang tidak
 * melakukan CORS sama sekali.
 */
function asalDiizinkan(req) {
  if (CORS_TERBUKA) return '*';
  const asal = req.headers.origin;
  if (!asal) return null;
  if (CORS_DAFTAR.includes(asal)) return asal;
  if (CORS_LOKAL && POLA_LOKAL.test(asal)) return asal;

  if (!asalDitolak.has(asal)) {
    asalDitolak.add(asal);
    console.warn(
      `⚠️  CORS menolak origin "${asal}" — tidak ada di CORS_ORIGIN. `
      + 'Klien dari asal itu akan melihat "Failed to fetch". '
      + `Tambahkan ke CORS_ORIGIN bila memang sah. Daftar saat ini: ${CORS_DAFTAR.join(', ')}`
    );
  }
  return null;
}

/**
 * Memasang header CORS. Dipakai jalur preflight dan jalur biasa, supaya
 * keduanya tidak mungkin menjawab berbeda.
 *
 * `Vary: Origin` wajib begitu nilainya bergantung pada pemanggil: tanpa itu
 * perantara boleh menyimpan jawaban untuk satu origin lalu menyajikannya ke
 * origin lain.
 */
function pasangHeaderCors(req, res) {
  const asal = asalDiizinkan(req);
  if (asal) res.header('Access-Control-Allow-Origin', asal);
  if (!CORS_TERBUKA) res.header('Vary', 'Origin');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS');
  res.header('Access-Control-Allow-Headers', HEADER_DIIZINKAN);
  res.header('Access-Control-Allow-Private-Network', 'true');
  return asal;
}


// Menangani preflight OPTIONS request SEBELUM middleware lain
app.options('*', (req, res) => {
  pasangHeaderCors(req, res);
  res.header('Access-Control-Max-Age', '86400');
  return res.sendStatus(204);
});
app.use((req, res, next) => {
  pasangHeaderCors(req, res);
  next();
});
app.use(compression());
// Batas ukuran badan permintaan.
//
// Sebelumnya 50MB untuk SETIAP rute. Login, vote polling, checkout tamu —
// semuanya menyanggupi menampung 50MB di memori sebelum satu baris validasi
// pun berjalan. `/api/payments/notifikasi` bahkan tanpa autentikasi, jadi
// tuasnya terbuka untuk siapa saja yang bisa menjangkau server.
//
// 1MB cukup untuk setiap muatan JSON di sistem ini. Rute yang benar-benar
// menerima berkas besar — impor Excel dan unggah — memakai multer yang punya
// batasnya sendiri dan tidak melewati parser JSON ini sama sekali.
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ limit: '1mb', extended: true }));
app.use(morgan('dev'));
app.use('/public', express.static(path.join(__dirname, '../public')));

// ========================
// Routes
// ========================
// Pembatasan laju dipasang SEBELUM routes, jadi permintaan berlebih ditolak
// sebelum menyentuh controller mana pun.
//
// Sebelumnya hanya /auth/login yang dijaga. Tiga jalur di bawah ini sama-sama
// bisa ditebak paksa dan akibatnya sama beratnya:
//
//   /emergency/*   PIN-nya hanya empat angka. Tanpa pembatasan, seluruh ruang
//                  tebakan habis dalam hitungan detik — dan yang didapat
//                  penebak adalah kemampuan memicu alarm palsu sekaligus
//                  menyiarkan WhatsApp ke seluruh warga, atau justru mematikan
//                  alarm yang sedang berbunyi sungguhan.
//   /change-password  menebak sandi lama, tanpa batas percobaan.
//   /users/credentials  jalur pengaturan ulang sandi; percobaan berulang di
//                  sini pantas terlihat dan pantas diperlambat.
app.use('/api/auth/login', loginLimiter);
app.use('/api/emergency', limiterKetat);
app.use('/api/auth/change-password', limiterKetat);
app.use('/api/users/credentials', limiterKetat);
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/bills', billRoutes);
// Bacaan meteran air. Berkas terpisah dari tagihan karena siklus hidupnya
// berbeda — bacaan lahir tgl 1, tagihan tgl 25 — tetapi berbagi izin
// keuangan.iuran, mengikuti preseden alokasi_bop terhadap keuangan.bop.
app.use('/api/meteran', meteranRoutes);
app.use('/api/jenis-iuran', jenisIuranRoutes);
app.use('/api/kategori-kas', kategoriKasRoutes);
app.use('/api/kategori-bop', kategoriBopRoutes);
app.use('/api/alokasi-bop', alokasiBopRoutes);
app.use('/api/finances', financeRoutes);
app.use('/api/letters', letterRoutes);
app.use('/api/emergency', emergencyRoutes);
app.use('/api/sensors', sensorRoutes);
app.use('/api/demographics', demographicsRoutes);
app.use('/api/announcements', announcementRoutes);
app.use('/api/complaints', complaintRoutes);
app.use('/api/agenda', agendaRoutes);
app.use('/api/polling', pollingRoutes);
app.use('/api/visitors', visitorRoutes);
app.use('/api/bantuan-sosial', bantuanSosialRoutes);
app.use('/api/inventory', inventoryRoutes);
app.use('/api/families', familyRoutes);
app.use('/api/warga', wargaRoutes);
app.use('/api/bop', bopRoutes);
app.use('/api/activity-logs', logRoutes);
app.use('/api/menu-akses', menuAksesRoutes);
app.use('/api/rt', rtRoutes);
app.use('/api/reset', resetRoutes);
app.use('/api/payments', paymentRoutes);

app.use('/api/upload', uploadRoutes);

// Tiket unduh sekali pakai — penggantinya `?token=` di URL tombol Export.
app.use('/api/unduh', unduhRoutes);
app.use('/api/notifications', notificationRoutes);

// Health check
//
// Menyentuh database, bukan sekadar melaporkan bahwa Express hidup.
//
// Sebelumnya endpoint ini selalu 200 walau PostgreSQL mati total — sehingga
// satu-satunya cara mengetahui sistem rusak adalah dengan memakai aplikasinya
// dan menemui 500 di setiap layar. Health check yang tidak bisa membedakan
// "sehat" dari "tidak bisa melayani apa pun" lebih buruk daripada tidak ada,
// karena ia meyakinkan pembacanya bahwa keadaan baik-baik saja.
//
// `SELECT 1` sekaligus membuktikan pool masih punya koneksi tersisa — kondisi
// yang paling mungkin terjadi diam-diam saat impor Excel besar berjalan
// bersamaan dengan lalu lintas biasa.
app.get('/api/health', async (req, res) => {
  const { getConnectedClients } = require('./config/websocket');
  const { pool } = require('./config/database');
  const { getFirebaseDiagnostic } = require('./config/firebase');

  let database = 'ok';
  let sehat = true;
  try {
    await pool.query('SELECT 1');
  } catch (err) {
    database = `gagal: ${err.message}`;
    sehat = false;
  }

  // 503 saat database tidak terjangkau, supaya pemantau otomatis maupun manusia
  // sama-sama melihat kegagalannya tanpa harus membaca isi bodinya.
  res.status(sehat ? 200 : 503).json({
    success: sehat,
    message: sehat
      ? 'Smart Community RT — Backend API is running 🚀'
      : 'Backend hidup, tetapi database tidak dapat dihubungi.',
    database,
    websocket_clients: getConnectedClients(),
    firebase: getFirebaseDiagnostic(),
    timestamp: new Date().toISOString(),
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: `Route ${req.method} ${req.originalUrl} tidak ditemukan.`,
  });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error('Unhandled Error:', err);
  res.status(500).json({
    success: false,
    message: 'Internal Server Error',
  });
});

// ========================
// Start HTTP + WebSocket Server
// ========================
const server = http.createServer(app);

// Inisialisasi WebSocket pada server HTTP yang sama
initWebSocket(server);
initMqtt();  // Sambungan broker alarm dihangatkan sejak startup.

server.listen(PORT, () => {
  console.log(`
  ╔═══════════════════════════════════════════════════════════╗
  ║  Smart Community RT — Backend API                        ║
  ║  HTTP Server  : http://localhost:${PORT}                    ║
  ║  WebSocket    : ws://localhost:${PORT}                      ║
  ║  Health check : http://localhost:${PORT}/api/health          ║
  ╠═══════════════════════════════════════════════════════════╣
  ║  API Endpoints:                                          ║
  ║   POST /api/auth/register       → Registrasi             ║
  ║   POST /api/auth/login          → Login                  ║
  ║   GET  /api/auth/me             → Profil user            ║
  ║   CRUD /api/users               → Manajemen user         ║
  ║   CRUD /api/bills               → Tagihan warga          ║
  ║   CRUD /api/finances            → Kas RT                 ║
  ║   CRUD /api/letters             → Surat pengantar        ║
  ║   POST /api/emergency/trigger   → Panic Button           ║
  ║   POST /api/emergency/dismiss   → Matikan alarm          ║
  ║   POST /api/sensors/log         → Data IoT sensor        ║
  ╚═══════════════════════════════════════════════════════════╝
  `);
  // Test koneksi database saat server sudah siap
  testConnection();
  periksaSaatStartup();
  const { autoSetupCloud } = require('./config/auto-setup');
  autoSetupCloud();

  // Penjadwal penerbitan tagihan air. Memeriksa harian, bukan menembak sekali
  // tanggal 25 — kalau proses sedang mati pada detik itu, tagihan bulan itu
  // tidak akan pernah terbit dan tidak ada gejala apa pun yang memberi tahu.
  const { mulaiPenjadwal } = require('./config/scheduler');
  mulaiPenjadwal();
});

// ========================
// Graceful Shutdown Handler
// ========================
// Mencegah terjadinya "zombie process" / port nyangkut
function gracefulShutdown(signal) {
  console.log(`\n[${signal}] Mematikan server secara aman...`);
  server.close(() => {
    console.log('Server berhasil dimatikan. Port telah dibebaskan.');
    process.exit(0);
  });
  
  // Jika dalam 5 detik tidak mati juga, matikan paksa
  setTimeout(() => {
    console.error('Server gagal dimatikan dengan aman, mematikan paksa...');
    process.exit(1);
  }, 5000);
}

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception (Server Kept Alive):', err);
});
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
