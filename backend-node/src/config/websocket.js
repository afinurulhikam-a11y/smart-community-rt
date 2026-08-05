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
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        ws.userId = decoded.id;
        ws.userNama = decoded.nama || decoded.email;
        ws.userRole = decoded.role;
      } catch (err) {
        ws.close(4401, 'Token tidak valid');
        return;
      }
    }
    // Koneksi tanpa token tetap diterima (backward-compatible / IoT device)
    // tetapi tidak menerima data sensitif di masa depan.

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

function broadcast(data) {
  if (!wss) {
    console.warn('⚠️ WebSocket Server belum diinisialisasi');
    return;
  }

  const message = typeof data === 'string' ? data : JSON.stringify(data);
  let sentCount = 0;

  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
      sentCount++;
    }
  });

  console.log(`📡 Broadcast ke ${sentCount} client:`, data);
  return sentCount;
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
