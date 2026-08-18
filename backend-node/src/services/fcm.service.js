const { pool } = require('../config/database');
const { getMessaging, isFirebaseConfigured, getFirebaseDiagnostic } = require('../config/firebase');

/**
 * Service Pengirim Notifikasi Firebase Cloud Messaging (FCM).
 *
 * ===================================================================
 * Fitur & Karakteristik Arsitektur
 * ===================================================================
 *
 * 1. Target Pengiriman:
 *    - `sendToToken(token, payload)`: Kirim ke token spesifik perangkat.
 *    - `sendToTokens(tokens, payload)`: Kirim multicast ke sekumpulan token.
 *    - `sendToUser(userId, payload)`: Kirim ke seluruh perangkat aktif milik 1 user (UUID).
 *    - `sendToUsers(userIds, payload)`: Kirim ke seluruh perangkat aktif milik daftar user (UUID array).
 *
 * 2. Multi-Device & Status Token:
 *    Hanya token dengan `is_active = true` pada tabel `user_fcm_tokens` yang akan
 *    diberi notifikasi.
 *
 * 3. Sanitasi Payload:
 *    - `notification`: Objek berisikan `title` dan `body`.
 *    - `data`: Seluruh key dan value DIWAJIBKAN bertipe String (aturan protokol FCM).
 *
 * 4. Pembersihan Token Otomatis (Stale Token Pruning):
 *    Jika FCM merespons dengan error `UNREGISTERED` / `registration-token-not-registered`
 *    atau token tidak valid, token tersebut langsung dinonaktifkan (`is_active = false`)
 *    di database agar tidak membebani pengiriman berikutnya.
 *
 * 5. Fail-Safe Simulation Mode:
 *    Bila Firebase kredensial belum dikonfigurasi di environment, fungsi tetap
 *    berjalan dalam mode simulasi (log) tanpa membuat backend crash.
 */

const INVALID_TOKEN_ERRORS = [
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
  'registration-token-not-registered',
  'invalid-registration-token',
  'UNREGISTERED',
  'INVALID_ARGUMENT',
];

function isInvalidTokenError(err) {
  if (!err) return false;
  const code = err.code || '';
  const message = err.message || '';
  return INVALID_TOKEN_ERRORS.some((pattern) => code.includes(pattern) || message.includes(pattern));
}

async function deactivateInvalidToken(token, reason = 'invalid_or_unregistered') {
  if (!token) return;
  try {
    const result = await pool.query(
      `UPDATE public.user_fcm_tokens
       SET is_active = false, updated_at = CURRENT_TIMESTAMP
       WHERE fcm_token = $1
       RETURNING id, user_id, fcm_token`,
      [token]
    );
    if (result.rowCount > 0) {
      console.log(`ℹ️ FCM Service: Token dinonaktifkan (${reason}): ${token.slice(0, 16)}...`);
    }
  } catch (dbErr) {
    console.error('⚠️ Gagal menonaktifkan token invalid di database:', dbErr.message);
  }
}

function sanitizeDataPayload(rawData) {
  if (!rawData || typeof rawData !== 'object') return {};
  const sanitized = {};
  for (const [key, value] of Object.entries(rawData)) {
    if (value !== undefined && value !== null) {
      sanitized[String(key)] = typeof value === 'string' ? value : JSON.stringify(value);
    }
  }
  return sanitized;
}

function buildFcmPayload({ title, body, data = {}, priority = 'high', collapseKey = null }) {
  const sanitizedData = sanitizeDataPayload(data);
  const isHighPriority = priority === 'high';

  const payload = {
    notification: {
      title: String(title || ''),
      body: String(body || ''),
    },
    data: sanitizedData,
    android: {
      priority: isHighPriority ? 'high' : 'normal',
      notification: {
        sound: 'default',
        channelId: isHighPriority ? 'darurat_channel' : 'umum_channel',
        priority: isHighPriority ? 'max' : 'default',
      },
    },
  };

  if (collapseKey) {
    payload.android.collapseKey = collapseKey;
  }

  return payload;
}

async function sendToToken(token, { title, body, data = {}, priority = 'high', collapseKey = null }) {
  if (!token || typeof token !== 'string' || token.trim() === '') {
    throw new Error('fcm_token wajib diisi.');
  }

  const cleanToken = token.trim();
  const fcmPayload = buildFcmPayload({ title, body, data, priority, collapseKey });

  const messaging = getMessaging();

  if (!messaging) {
    // Simulation Mode
    console.log('\n📲 [SIMULASI PUSH NOTIFIKASI FCM - CREDENTIAL BELUM DIPASANG]');
    console.log(`  Target Token : ${cleanToken.slice(0, 20)}...`);
    console.log(`  Judul        : ${fcmPayload.notification.title}`);
    console.log(`  Isi Pesan    : ${fcmPayload.notification.body}`);
    console.log(`  Data Payload :`, fcmPayload.data);
    console.log('');
    return {
      success: true,
      simulated: true,
      messageId: `simulated-${Date.now()}`,
    };
  }

  try {
    const message = {
      token: cleanToken,
      ...fcmPayload,
    };
    const messageId = await messaging.send(message);
    return {
      success: true,
      simulated: false,
      messageId,
    };
  } catch (err) {
    console.error('❌ Gagal mengirim FCM ke token:', err.message);
    if (isInvalidTokenError(err)) {
      await deactivateInvalidToken(cleanToken, err.code || err.message);
    }
    return {
      success: false,
      simulated: false,
      error: err.code || err.message,
    };
  }
}

async function sendToTokens(tokens, { title, body, data = {}, priority = 'high', collapseKey = null }) {
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return {
      success: true,
      delivered: false,
      reason: 'empty_tokens',
      successCount: 0,
      failureCount: 0,
      results: [],
    };
  }

  const uniqueTokens = [...new Set(tokens.map((t) => String(t).trim()).filter(Boolean))];
  if (uniqueTokens.length === 0) {
    return {
      success: true,
      delivered: false,
      reason: 'no_valid_tokens',
      successCount: 0,
      failureCount: 0,
      results: [],
    };
  }

  const fcmPayload = buildFcmPayload({ title, body, data, priority, collapseKey });
  const messaging = getMessaging();

  if (!messaging) {
    // Simulation Mode
    console.log('\n📲 [SIMULASI MULTICAST FCM - CREDENTIAL BELUM DIPASANG]');
    console.log(`  Target Tokens : ${uniqueTokens.length} perangkat`);
    console.log(`  Judul         : ${fcmPayload.notification.title}`);
    console.log(`  Isi Pesan     : ${fcmPayload.notification.body}`);
    console.log(`  Data Payload  :`, fcmPayload.data);
    console.log('');
    return {
      success: true,
      simulated: true,
      successCount: uniqueTokens.length,
      failureCount: 0,
      results: uniqueTokens.map((t, idx) => ({
        token: t,
        success: true,
        messageId: `simulated-multi-${idx}`,
      })),
    };
  }

  try {
    const multicastMessage = {
      tokens: uniqueTokens,
      ...fcmPayload,
    };

    const response = await messaging.sendEachForMulticast(multicastMessage);

    // Periksa respons setiap token untuk pembersihan otomatis token invalid
    if (response.responses && response.responses.length > 0) {
      for (let i = 0; i < response.responses.length; i++) {
        const item = response.responses[i];
        if (!item.success && item.error && isInvalidTokenError(item.error)) {
          const invalidToken = uniqueTokens[i];
          await deactivateInvalidToken(invalidToken, item.error.code || item.error.message);
        }
      }
    }

    return {
      success: true,
      simulated: false,
      successCount: response.successCount,
      failureCount: response.failureCount,
      results: response.responses,
    };
  } catch (err) {
    console.error('❌ Gagal mengirim FCM multicast:', err.message);
    return {
      success: false,
      simulated: false,
      error: err.code || err.message,
      successCount: 0,
      failureCount: uniqueTokens.length,
    };
  }
}

async function sendToUser(userId, { title, body, data = {}, priority = 'high', collapseKey = null }) {
  if (!userId) {
    throw new Error('userId (UUID) wajib diisi.');
  }

  const result = await pool.query(
    `SELECT fcm_token FROM public.user_fcm_tokens
     WHERE user_id = $1 AND is_active = true`,
    [userId]
  );

  const tokens = result.rows.map((r) => r.fcm_token);

  if (tokens.length === 0) {
    return {
      success: true,
      delivered: false,
      reason: 'no_active_tokens',
      tokensCount: 0,
    };
  }

  if (tokens.length === 1) {
    const singleRes = await sendToToken(tokens[0], { title, body, data, priority, collapseKey });
    return {
      ...singleRes,
      delivered: singleRes.success,
      tokensCount: 1,
    };
  }

  const multiRes = await sendToTokens(tokens, { title, body, data, priority, collapseKey });
  return {
    ...multiRes,
    delivered: multiRes.success && multiRes.successCount > 0,
    tokensCount: tokens.length,
  };
}

async function sendToUsers(userIds, { title, body, data = {}, priority = 'high', collapseKey = null }) {
  if (!Array.isArray(userIds) || userIds.length === 0) {
    return {
      success: true,
      delivered: false,
      reason: 'empty_user_ids',
      tokensCount: 0,
      userCount: 0,
    };
  }

  const uniqueUserIds = [...new Set(userIds.filter(Boolean))];

  const result = await pool.query(
    `SELECT DISTINCT fcm_token FROM public.user_fcm_tokens
     WHERE user_id = ANY($1) AND is_active = true`,
    [uniqueUserIds]
  );

  const tokens = result.rows.map((r) => r.fcm_token);

  if (tokens.length === 0) {
    return {
      success: true,
      delivered: false,
      reason: 'no_active_tokens',
      tokensCount: 0,
      userCount: uniqueUserIds.length,
    };
  }

  const multiRes = await sendToTokens(tokens, { title, body, data, priority, collapseKey });
  return {
    ...multiRes,
    delivered: multiRes.success && multiRes.successCount > 0,
    tokensCount: tokens.length,
    userCount: uniqueUserIds.length,
  };
}

module.exports = {
  sendToToken,
  sendToTokens,
  sendToUser,
  sendToUsers,
  buildFcmPayload,
  sanitizeDataPayload,
  deactivateInvalidToken,
  isInvalidTokenError,
  isFirebaseConfigured,
  getFirebaseDiagnostic,
};
