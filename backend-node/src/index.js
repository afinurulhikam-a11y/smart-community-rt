require('dotenv').config();

const express = require('express');
const compression = require('compression');
const morgan = require('morgan');
const http = require('http');

// Config
const { initWebSocket } = require('./config/websocket');
const { testConnection } = require('./config/database');
const { periksaSaatStartup } = require('./config/midtrans');

// Routes
const authRoutes = require('./routes/auth.routes');
const userRoutes = require('./routes/user.routes');
const billRoutes = require('./routes/bill.routes');
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
const resetRoutes = require('./routes/reset.routes');
const paymentRoutes = require('./routes/payment.routes');

const app = express();
const PORT = process.env.PORT || 3000;

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

// Menangani preflight OPTIONS request SEBELUM middleware lain
app.options('*', (req, res) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS');
  res.header('Access-Control-Allow-Headers', HEADER_DIIZINKAN);
  res.header('Access-Control-Allow-Private-Network', 'true');
  res.header('Access-Control-Max-Age', '86400');
  return res.sendStatus(204);
});
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS');
  res.header('Access-Control-Allow-Headers', HEADER_DIIZINKAN);
  res.header('Access-Control-Allow-Private-Network', 'true');
  next();
});
app.use(compression());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));
app.use(morgan('dev'));

// ========================
// Routes
// ========================
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/bills', billRoutes);
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
app.use('/api/reset', resetRoutes);
app.use('/api/payments', paymentRoutes);

// Health check
app.get('/api/health', (req, res) => {
  const { getConnectedClients } = require('./config/websocket');
  res.json({
    success: true,
    message: 'Smart Community RT — Backend API is running 🚀',
    websocket_clients: getConnectedClients(),
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
  console.error('Uncaught Exception:', err);
  gracefulShutdown('uncaughtException');
});
