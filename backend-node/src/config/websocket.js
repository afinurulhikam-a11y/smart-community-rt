const WebSocket = require('ws');
const jwt = require('jsonwebtoken');

let wss = null;

function initWebSocket(server) {
  wss = new WebSocket.Server({ server });

  wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress;

    // Autentikasi: klien harus mengirim token JWT lewat query parameter
    // ws://host:port?token=xxx — pola yang lazim untuk WebSocket.
    const url = new (require('url').URL)(req.url, `http://${req.headers.host}`);
    const token = url.searchParams.get('token');
    if (token) {
      try {
        // Allowlist algoritma sama dengan authMiddleware — lihat alasannya di
        // sana. Jalur ini menerima token dari query string, jadi justru di sini
        // penjaga itu paling tidak boleh bergantung pada bawaan pustaka.
        const decoded = jwt.verify(token, process.env.JWT_SECRET, { algorithms: ['HS256'] });
        ws.userId = decoded.id;
        ws.userNama = decoded.nama || decoded.email;
        ws.userRole = decoded.role;
      } catch (err) {
        ws.close(4401, 'Token tidak valid');
        return;
      }
    }
    // Koneksi TANPA token tetap diterima — ESP32 tidak bisa memegang JWT — dan
    // ditandai sebagai perangkat. Tandanya dipakai `broadcast()` untuk memilih
    // muatan mana yang boleh dikirim ke sana.
    //
    // Ini yang menutup kebocoran nyata: dulu setiap klien menerima setiap
    // pesan, termasuk nama, nomor telepon, dan alamat rumah orang yang sedang
    // menekan tombol darurat. Siapa pun yang bisa menjangkau server ini —
    // tanpa akun, tanpa token — cukup membuka satu koneksi WebSocket untuk
    // menyadapnya. Justru pada saat orang itu paling rentan.
    ws.terautentikasi = Boolean(ws.userId);

    console.log(`websocket client terhubung${ws.userNama ? ` (${ws.userNama})` : ''}`);

    ws.send(JSON.stringify({
      type: 'CONNECTED',
      message: 'Terhubung ke Smart Community RT WebSocket Server',
      timestamp: new Date().toISOString(),
    }));

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());
        console.log(`📨 WS Message dari ${clientIp}:`, message);
      } catch (err) {
        console.log(`📨 WS Raw Message: ${data}`);
      }
    });

    ws.on('close', () => {
      console.log(`websocket client terputus${ws.userNama ? ` (${ws.userNama})` : ''}`);
    });

    ws.on('error', (err) => {
      console.error(`⚠️ WebSocket Error (${clientIp}):`, err.message);
    });
  });

  console.log('🔌 WebSocket Server siap (upgrade dari HTTP server)');
  return wss;
}

/**
 * Siarkan pesan ke klien yang terhubung.
 *
 * @param {object|string} data     muatan lengkap, untuk klien yang sudah login
 * @param {object} [dataPerangkat] muatan terbatas untuk koneksi tanpa token
 *                                 (ESP32). Bila tidak diberikan, koneksi tanpa
 *                                 token TIDAK menerima apa-apa.
 *
 * Bawaannya sengaja menutup, bukan membuka: pesan baru yang lupa menyertakan
 * versi perangkatnya tidak akan pernah bocor ke koneksi anonim. Yang hilang
 * paling banter satu bunyi bel; yang dicegah adalah kebocoran data pribadi.
 */
function broadcast(data, dataPerangkat) {
  if (!wss) {
    console.warn('⚠️ WebSocket Server belum diinisialisasi');
    return;
  }

  const pesanPenuh = typeof data === 'string' ? data : JSON.stringify(data);
  const pesanPerangkat = dataPerangkat === undefined
    ? null
    : (typeof dataPerangkat === 'string' ? dataPerangkat : JSON.stringify(dataPerangkat));

  let keAkun = 0;
  let kePerangkat = 0;

  wss.clients.forEach((client) => {
    if (client.readyState !== WebSocket.OPEN) return;

    if (client.terautentikasi) {
      client.send(pesanPenuh);
      keAkun++;
    } else if (pesanPerangkat !== null) {
      client.send(pesanPerangkat);
      kePerangkat++;
    }
  });

  console.log(`📡 Broadcast: ${keAkun} akun, ${kePerangkat} perangkat —`, data?.type || data);
  return keAkun + kePerangkat;
}

function getConnectedClients() {
  if (!wss) return 0;
  let count = 0;
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) count++;
  });
  return count;
}

module.exports = { initWebSocket, broadcast, getConnectedClients };
