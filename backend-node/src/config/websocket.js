const WebSocket = require('ws');

let wss = null;

function initWebSocket(server) {
  wss = new WebSocket.Server({ server });

  wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress;
    console.log('websocket client terhubung');

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
      console.log('websocket client terputus');
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
