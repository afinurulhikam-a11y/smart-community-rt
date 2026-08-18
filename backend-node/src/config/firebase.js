const admin = require('firebase-admin');
const { initializeApp, getApps, cert, applicationDefault, deleteApp } = require('firebase-admin/app');
const { getMessaging: getAdminMessaging } = require('firebase-admin/messaging');
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

function sanitizeServiceAccount(serviceAccount) {
  if (!serviceAccount || typeof serviceAccount !== 'object') return null;
  const sa = { ...serviceAccount };
  // Normalisasi escaped newlines pada private_key jika ada (format umum di env vars cloud seperti Railway)
  if (typeof sa.private_key === 'string') {
    sa.private_key = sa.private_key.replace(/\\n/g, '\n');
  }
  return sa;
}

function parseServiceAccountKey(rawKey) {
  if (!rawKey || typeof rawKey !== 'string') return null;
  let trimmed = rawKey.trim();
  if (!trimmed) return null;

  // 1. Coba parsing langsung sebagai JSON
  try {
    let parsed = JSON.parse(trimmed);
    if (typeof parsed === 'string') {
      try {
        parsed = JSON.parse(parsed);
      } catch (nestedErr) {
        void nestedErr;
      }
    }
    if (parsed && typeof parsed === 'object') {
      return sanitizeServiceAccount(parsed);
    }
  } catch (err) {
    void err; // Abaikan dan coba penanganan kutip / Base64 di bawah
  }

  // 2. Jika berbalut tanda kutip luar (' atau "), buang kutip luar
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    const unquoted = trimmed.slice(1, -1).trim();
    try {
      let parsed = JSON.parse(unquoted);
      if (typeof parsed === 'string') {
        try {
          parsed = JSON.parse(parsed);
        } catch (nestedErr) {
          void nestedErr;
        }
      }
      if (parsed && typeof parsed === 'object') {
        return sanitizeServiceAccount(parsed);
      }
    } catch (err) {
      void err;
      trimmed = unquoted;
    }
  }

  // 3. Coba decoding dari Base64
  try {
    const decoded = Buffer.from(trimmed, 'base64').toString('utf8');
    let parsed = JSON.parse(decoded);
    if (typeof parsed === 'string') {
      try {
        parsed = JSON.parse(parsed);
      } catch (nestedErr) {
        void nestedErr;
      }
    }
    if (parsed && typeof parsed === 'object') {
      return sanitizeServiceAccount(parsed);
    }
  } catch (err) {
    void err; // Bukan JSON dan bukan Base64 valid
  }

  return null;
}

function loadServiceAccountFromEnv() {
  const rawKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
  if (rawKey && rawKey.trim() !== '') {
    const sa = parseServiceAccountKey(rawKey);
    if (sa) return sa;
  }

  const filePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (filePath && filePath.trim() !== '') {
    const resolvedPath = path.isAbsolute(filePath)
      ? filePath
      : path.resolve(process.cwd(), filePath);

    if (fs.existsSync(resolvedPath)) {
      try {
        const content = fs.readFileSync(resolvedPath, 'utf8');
        return parseServiceAccountKey(content);
      } catch (err) {
        console.warn(`⚠️ Gagal membaca berkas service account di ${resolvedPath}:`, err.message);
      }
    }
  }

  return null;
}

function getExistingApps() {
  if (typeof getApps === 'function') return getApps();
  if (admin && typeof admin.getApps === 'function') return admin.getApps();
  if (admin && Array.isArray(admin.apps)) return admin.apps;
  return [];
}

function createCertCredential(serviceAccount) {
  if (typeof cert === 'function') return cert(serviceAccount);
  if (admin && typeof admin.cert === 'function') return admin.cert(serviceAccount);
  if (admin && admin.credential && typeof admin.credential.cert === 'function') {
    return admin.credential.cert(serviceAccount);
  }
  throw new Error('Metode cert() tidak tersedia pada instalasi Firebase Admin.');
}

function createAdcCredential() {
  if (typeof applicationDefault === 'function') return applicationDefault();
  if (admin && typeof admin.applicationDefault === 'function') return admin.applicationDefault();
  if (admin && admin.credential && typeof admin.credential.applicationDefault === 'function') {
    return admin.credential.applicationDefault();
  }
  throw new Error('Metode applicationDefault() tidak tersedia pada instalasi Firebase Admin.');
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
      const projectId = serviceAccount.project_id || process.env.FIREBASE_PROJECT_ID;
      const credential = createCertCredential(serviceAccount);
      const appInitFn = typeof initializeApp === 'function' ? initializeApp : admin.initializeApp;
      firebaseApp = appInitFn({
        credential,
        projectId,
      });
      console.log(`🔥 Firebase Admin SDK berhasil diinisialisasi untuk project: ${projectId || 'default'}`);
      return firebaseApp;
    } catch (err) {
      console.error('❌ Gagal inisialisasi Firebase Admin dengan service account:', err.message);
    }
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    try {
      const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
      const credential = createAdcCredential();
      const appInitFn = typeof initializeApp === 'function' ? initializeApp : admin.initializeApp;
      firebaseApp = appInitFn({
        credential,
        projectId,
      });
      console.log(`🔥 Firebase Admin SDK diinisialisasi via Application Default Credentials (project: ${projectId || 'default'})`);
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
  if (app) {
    try {
      if (typeof getAdminMessaging === 'function') {
        return getAdminMessaging(app);
      }
      if (admin && typeof admin.messaging === 'function') {
        return admin.messaging(app);
      }
    } catch (err) {
      console.warn('⚠️ Gagal mengambil Firebase Messaging instance:', err.message);
    }
  }

  return null;
}

function isFirebaseConfigured() {
  return mockMessagingInstance !== null || initFirebase() !== null;
}

/**
 * Diagnostic / Readiness check yang AMAN untuk memverifikasi Firebase FCM status
 * tanpa pernah membocorkan private_key, client_email, FIREBASE_SERVICE_ACCOUNT_KEY, atau token.
 */
function getFirebaseDiagnostic() {
  const isMock = mockMessagingInstance !== null;
  const app = initFirebase();
  const configured = isFirebaseConfigured();

  let credentialSource = 'none';
  if (isMock) {
    credentialSource = 'mock';
  } else if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY && process.env.FIREBASE_SERVICE_ACCOUNT_KEY.trim() !== '') {
    credentialSource = 'service_account_key';
  } else if (process.env.FIREBASE_SERVICE_ACCOUNT_PATH && process.env.FIREBASE_SERVICE_ACCOUNT_PATH.trim() !== '') {
    credentialSource = 'service_account_path';
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS && process.env.GOOGLE_APPLICATION_CREDENTIALS.trim() !== '') {
    credentialSource = 'application_default_credentials';
  }

  // Cari project ID yang aman (public project identifier)
  let projectId = null;
  if (app && app.options && app.options.projectId) {
    projectId = app.options.projectId;
  } else if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PROJECT_ID.trim() !== '') {
    projectId = process.env.FIREBASE_PROJECT_ID.trim();
  } else {
    const sa = loadServiceAccountFromEnv();
    if (sa && sa.project_id) {
      projectId = sa.project_id;
    }
  }

  return {
    configured,
    simulation_mode: !configured,
    project_id: projectId || null,
    credential_source: credentialSource,
    app_name: app ? app.name : (isMock ? '[MOCK]' : null),
  };
}

/**
 * Jalur pengujian unit (mocking Firebase Messaging).
 */
function setMockMessaging(mockInstance) {
  mockMessagingInstance = mockInstance;
}

/**
 * Helper isolasi test suite untuk mereset instance Firebase Admin.
 */
async function resetFirebaseForTesting() {
  const existingApps = typeof getApps === 'function' ? getApps() : (admin && Array.isArray(admin.apps) ? admin.apps : []);
  if (Array.isArray(existingApps) && existingApps.length > 0) {
    await Promise.all(
      existingApps.map((app) => {
        if (!app) return Promise.resolve();
        if (typeof deleteApp === 'function') {
          return deleteApp(app).catch(() => {});
        }
        if (typeof app.delete === 'function') {
          return app.delete().catch(() => {});
        }
        return Promise.resolve();
      })
    );
  }
  firebaseApp = null;
  mockMessagingInstance = null;
}

module.exports = {
  admin,
  initFirebase,
  getMessaging,
  isFirebaseConfigured,
  getFirebaseDiagnostic,
  setMockMessaging,
  resetFirebaseForTesting,
  parseServiceAccountKey,
};
