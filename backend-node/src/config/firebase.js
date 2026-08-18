const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

/**
 * Konfigurasi Firebase Admin SDK untuk Backend Node.js.
 *
 * ===================================================================
 * Prinsip Keamanan & Desain Tanpa Hard-Code Credential
 * ===================================================================
 *
 * 1. Tidak ada private key / service account credentials yang di-hardcode.
 * 2. Mendukung konfigurasi via Environment Variables:
 *    - `FIREBASE_SERVICE_ACCOUNT_KEY`: String JSON atau Base64-encoded JSON.
 *    - `FIREBASE_SERVICE_ACCOUNT_PATH`: Path file ke JSON service account (misal di server).
 *    - `GOOGLE_APPLICATION_CREDENTIALS`: Standar Google Cloud ADC.
 * 3. Mode Simulasi / Fail-Safe:
 *    Jika kredensial belum disetel (misal saat pengembangan lokal atau pengujian),
 *    backend tetap menyala normal dan beralih ke mode simulasi (log ke konsol)
 *    mirip seperti `whatsapp.service.js` saat `FONNTE_TOKEN` belum dipasang.
 */

let firebaseApp = null;
let mockMessagingInstance = null;

function loadServiceAccountFromEnv() {
  const rawKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
  if (rawKey && rawKey.trim() !== '') {
    const trimmed = rawKey.trim();
    // Coba parsing langsung sebagai JSON
    try {
      return JSON.parse(trimmed);
    } catch (_) {
      // Jika gagal, coba decoding dari Base64
      try {
        const decoded = Buffer.from(trimmed, 'base64').toString('utf8');
        return JSON.parse(decoded);
      } catch (err) {
        console.warn('⚠️ Gagal mem-parsing FIREBASE_SERVICE_ACCOUNT_KEY:', err.message);
      }
    }
  }

  const filePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (filePath && filePath.trim() !== '') {
    const resolvedPath = path.isAbsolute(filePath)
      ? filePath
      : path.resolve(process.cwd(), filePath);

    if (fs.existsSync(resolvedPath)) {
      try {
        const content = fs.readFileSync(resolvedPath, 'utf8');
        return JSON.parse(content);
      } catch (err) {
        console.warn(`⚠️ Gagal membaca berkas service account di ${resolvedPath}:`, err.message);
      }
    }
  }

  return null;
}

function getExistingApps() {
  if (!admin) return [];
  if (typeof admin.getApps === 'function') return admin.getApps();
  if (Array.isArray(admin.apps)) return admin.apps;
  return [];
}

function initFirebase() {
  if (firebaseApp) return firebaseApp;

  // Cek apakah ada app default yang sudah terinisialisasi
  const apps = getExistingApps();
  if (apps.length > 0) {
    firebaseApp = apps[0];
    return firebaseApp;
  }

  const serviceAccount = loadServiceAccountFromEnv();

  if (serviceAccount) {
    try {
      firebaseApp = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id || process.env.FIREBASE_PROJECT_ID,
      });
      console.log(`🔥 Firebase Admin SDK berhasil diinisialisasi untuk project: ${serviceAccount.project_id || 'default'}`);
      return firebaseApp;
    } catch (err) {
      console.error('❌ Gagal inisialisasi Firebase Admin dengan service account:', err.message);
    }
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    try {
      firebaseApp = admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId: process.env.FIREBASE_PROJECT_ID,
      });
      console.log('🔥 Firebase Admin SDK diinisialisasi via Application Default Credentials');
      return firebaseApp;
    } catch (err) {
      console.error('❌ Gagal inisialisasi Firebase Admin via ADC:', err.message);
    }
  }

  return null;
}

function getMessaging() {
  if (mockMessagingInstance) {
    return mockMessagingInstance;
  }

  const app = initFirebase();
  if (app && typeof admin.messaging === 'function') {
    try {
      return admin.messaging(app);
    } catch (err) {
      console.warn('⚠️ Gagal mengambil admin.messaging(app):', err.message);
    }
  }

  return null;
}

function isFirebaseConfigured() {
  return mockMessagingInstance !== null || initFirebase() !== null;
}

/**
 * Jalur pengujian unit (mocking Firebase Messaging).
 */
function setMockMessaging(mockInstance) {
  mockMessagingInstance = mockInstance;
}

module.exports = {
  admin,
  initFirebase,
  getMessaging,
  isFirebaseConfigured,
  setMockMessaging,
};
