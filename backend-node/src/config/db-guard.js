/**
 * Database Safety Guard
 * ===================================================================
 * Centralized, fail-closed safety guard to prevent accidental modification,
 * migration, seeding, or test execution against Railway / Cloud / Production
 * PostgreSQL databases.
 *
 * Rules:
 * 1. Test scripts (test-*.js) MUST ONLY run against local development databases.
 * 2. Destructive scripts (init-db, kosongkan-data, demo seeds) are strictly
 *    blocked on production databases.
 * 3. Migrations & seed-master on production databases require EXPLICIT
 *    confirmation (ALLOW_PROD_MIGRATION=true or --confirm-production).
 * 4. Error messages NEVER leak passwords, secrets, JWTs, or raw DATABASE_URL.
 * 5. Fail-closed: any non-local, unclassified, or remote host is treated as
 *    protected / production by default.
 * ===================================================================
 */

const { URL } = require('url');

const LOCAL_HOST_PATTERNS = [
  /^localhost$/i,
  /^127\.\d+\.\d+\.\d+$/,
  /^::1$/,
  /^0\.0\.0\.0$/,
  /^postgres$/i,
  /^postgresql$/i,
  /^db$/i,
  /^local-pg$/i,
  /^host\.docker\.internal$/i,
  /\.local$/i,
  /\.localhost$/i,
  /\.test$/i,
];

const KNOWN_CLOUD_PROD_PATTERNS = [
  /railway\.app$/i,
  /rlwy\.net$/i,
  /render\.com$/i,
  /supabase\.co$/i,
  /neon\.tech$/i,
  /aivencloud\.com$/i,
  /amazonaws\.com$/i,
  /azure\.com$/i,
  /google\.com$/i,
  /elephantsql\.com$/i,
  /cockroachlabs\.cloud$/i,
  /timescale\.com$/i,
  /kinsta\.cloud$/i,
  /fly\.dev$/i,
];

/**
 * Sanitize a database connection string or host info, masking the password.
 * NEVER prints real credentials.
 */
function sanitizeDbUrl(connectionStringOrTarget) {
  if (!connectionStringOrTarget) return '(tidak terkonfigurasi / default pg)';

  if (typeof connectionStringOrTarget === 'object') {
    const {
      user = 'postgres',
      host = 'localhost',
      port = 5432,
      database = 'smart_community_rt',
    } = connectionStringOrTarget;
    return `postgres://${user || 'user'}:***@${host}:${port}/${database}`;
  }

  const str = String(connectionStringOrTarget).trim();
  try {
    const parsed = new URL(str);
    const user = parsed.username || 'user';
    const host = parsed.hostname || 'unknown';
    const port = parsed.port ? `:${parsed.port}` : '';
    const pathname = parsed.pathname || '';
    return `${parsed.protocol}//${user}:***@${host}${port}${pathname}`;
  } catch {
    // Fallback regex masking in case URL constructor fails
    return str.replace(/(:\/\/)([^:@\s]+)(:[^@\s]+)?@/, '$1$2:***@');
  }
}

/**
 * Parse database target configuration and classify whether it is local or protected/prod.
 */
function inspectDatabaseTarget(env = process.env) {
  let host = env.DB_HOST || env.PGHOST || '';
  let port = env.DB_PORT || env.PGPORT || 5432;
  let database = env.DB_NAME || env.PGDATABASE || 'smart_community_rt';
  let user = env.DB_USER || env.PGUSER || 'postgres';
  const rawUrl = env.DATABASE_URL || '';
  const isUrlConfigured = Boolean(rawUrl && rawUrl.trim() !== '');

  if (isUrlConfigured) {
    try {
      const parsed = new URL(rawUrl.trim());
      host = parsed.hostname || host;
      port = parsed.port ? parseInt(parsed.port, 10) : port;
      database = parsed.pathname ? parsed.pathname.replace(/^\//, '') : database;
      user = parsed.username || user;
    } catch {
      // If parsing fails, fail-closed
      host = host || 'unparsed-remote-url';
    }
  }

  if (!host) {
    host = 'localhost';
  }

  const isLocalHost = LOCAL_HOST_PATTERNS.some((pattern) => pattern.test(host));
  const isCloudHost = KNOWN_CLOUD_PROD_PATTERNS.some((pattern) => pattern.test(host));

  const isExplicitProdEnv =
    env.NODE_ENV === 'production' ||
    env.RAILWAY_ENVIRONMENT === 'production' ||
    Boolean(env.RAILWAY_PROJECT_NAME) ||
    env.VERCEL_ENV === 'production' ||
    env.DB_ENVIRONMENT === 'production' ||
    env.IS_PRODUCTION_DB === 'true';

  const isProdNamedDb =
    !isLocalHost &&
    (database.toLowerCase().includes('prod') || database.toLowerCase().includes('railway'));

  // Fail-closed determination:
  // Target is considered PROTECTED / PRODUCTION if:
  // 1. Explicit production env flag is set, OR
  // 2. Host matches known cloud/production patterns, OR
  // 3. Host is NOT in the local host whitelist (remote IP/domain), OR
  // 4. Database name indicates production.
  const isProtected = isExplicitProdEnv || isCloudHost || !isLocalHost || isProdNamedDb;

  const sanitizedTarget = sanitizeDbUrl(
    isUrlConfigured ? rawUrl : { user, host, port, database }
  );

  return {
    host,
    port,
    database,
    user,
    isUrlConfigured,
    isLocalHost,
    isCloudHost,
    isExplicitProdEnv,
    isProtected,
    sanitizedTarget,
  };
}

/**
 * Check if the current process has explicit confirmation to perform operations on a protected database.
 */
function hasExplicitConfirmation(env = process.env, argv = process.argv) {
  const envFlag =
    env.ALLOW_PROD_MIGRATION === 'true' ||
    env.CONFIRM_PROD_MIGRATION === 'yes' ||
    env.ALLOW_PROD_OPERATION === 'true' ||
    env.CONFIRM_PROD_DB === 'true';

  const cliFlag =
    argv.includes('--confirm-production') ||
    argv.includes('--allow-prod-migration') ||
    argv.includes('--force-production');

  return envFlag || cliFlag;
}

/**
 * Guard for running test scripts.
 * Test scripts are STRICTLY PROHIBITED on production / remote databases.
 */
function assertCanRunTest(testName = 'Script Pengujian', { env = process.env } = {}) {
  const target = inspectDatabaseTarget(env);

  if (target.isProtected) {
    const errorMsg =
      `\n❌ [DB_GUARD_BLOCKED] ${testName} DITOLAK!\n` +
      `Target database terdeteksi sebagai database PRODUCTION / REMOTE: ${target.sanitizedTarget}\n` +
      `Test suite dan pengujian otomatis dilarang keras menulis atau memanipulasi database production.\n` +
      `Gunakan PostgreSQL lokal (localhost / 127.0.0.1) untuk menjalankan pengujian.\n`;
    const err = new Error(errorMsg);
    err.code = 'DB_GUARD_TEST_PROHIBITED';
    err.target = target.sanitizedTarget;
    throw err;
  }

  return target;
}

/**
 * Guard for running database migrations.
 * Production migrations require explicit confirmation (ALLOW_PROD_MIGRATION=true or --confirm-production).
 */
function assertCanRunMigration(
  migrationName = 'Migrasi Database',
  { env = process.env, argv = process.argv } = {}
) {
  const target = inspectDatabaseTarget(env);

  if (!target.isProtected) {
    // Local development database: allowed immediately
    return target;
  }

  const confirmed = hasExplicitConfirmation(env, argv);
  if (!confirmed) {
    const errorMsg =
      `\n❌ [DB_GUARD_BLOCKED] ${migrationName} DITOLAK!\n` +
      `Target database (${target.sanitizedTarget}) terdeteksi sebagai DATABASE PRODUCTION / REMOTE.\n` +
      `Migrasi pada database production memerlukan konfirmasi eksplisit untuk mencegah kerusakan data secara tidak sengaja.\n\n` +
      `Cara menjalankan secara aman pada production:\n` +
      `  - Set environment variable: ALLOW_PROD_MIGRATION=true\n` +
      `  - Atau sertakan flag CLI: node <script> --confirm-production\n`;
    const err = new Error(errorMsg);
    err.code = 'DB_GUARD_PROD_CONFIRMATION_REQUIRED';
    err.target = target.sanitizedTarget;
    throw err;
  }

  console.log(
    `⚠️  [DB_GUARD] Menjalankan ${migrationName} pada database PRODUCTION (${target.sanitizedTarget}) dengan konfirmasi eksplisit.`
  );
  return target;
}

/**
 * Guard for running destructive scripts (init-db, kosongkan-data, demo seeds).
 * Prohibited on production unless an ultra-strict confirmation is provided.
 */
function assertCanRunDestructive(
  scriptName = 'Operasi Destruktif',
  { env = process.env, argv = process.argv } = {}
) {
  const target = inspectDatabaseTarget(env);

  if (!target.isProtected) {
    // Local development database: allowed
    return target;
  }

  const ultraStrictConfirmed =
    env.ALLOW_DESTRUCTIVE_PROD_SCRIPT === 'I_KNOW_WHAT_I_AM_DOING' &&
    argv.includes('--force-destructive-prod');

  if (!ultraStrictConfirmed) {
    const errorMsg =
      `\n🛑 [DB_GUARD_BLOCKED] ${scriptName} DITOLAK KERAS!\n` +
      `Target database (${target.sanitizedTarget}) adalah DATABASE PRODUCTION / REMOTE.\n` +
      `Operasi destruktif (DROP/TRUNCATE/DELETE ALL/DEMO DATA) dilarang pada database production.\n`;
    const err = new Error(errorMsg);
    err.code = 'DB_GUARD_DESTRUCTIVE_PROHIBITED';
    err.target = target.sanitizedTarget;
    throw err;
  }

  console.warn(
    `🚨 [DB_GUARD_WARNING] Menjalankan operasi destruktif ${scriptName} pada PRODUCTION (${target.sanitizedTarget})!`
  );
  return target;
}

/**
 * Guard for master data seeder (seed-master.js).
 */
function assertCanRunSeedMaster(
  scriptName = 'Seed Master',
  { env = process.env, argv = process.argv } = {}
) {
  const target = inspectDatabaseTarget(env);

  if (!target.isProtected) {
    return target;
  }

  const confirmed =
    hasExplicitConfirmation(env, argv) || env.ALLOW_PROD_SEED === 'true';

  if (!confirmed) {
    const errorMsg =
      `\n❌ [DB_GUARD_BLOCKED] ${scriptName} DITOLAK!\n` +
      `Target database (${target.sanitizedTarget}) adalah DATABASE PRODUCTION / REMOTE.\n` +
      `Seeding master pada production memerlukan konfirmasi: ALLOW_PROD_MIGRATION=true atau --confirm-production.\n`;
    const err = new Error(errorMsg);
    err.code = 'DB_GUARD_PROD_CONFIRMATION_REQUIRED';
    err.target = target.sanitizedTarget;
    throw err;
  }

  console.log(
    `⚠️  [DB_GUARD] Menjalankan ${scriptName} pada database PRODUCTION (${target.sanitizedTarget}) dengan konfirmasi eksplisit.`
  );
  return target;
}

/**
 * Safe read-only metadata verification on an active connection.
 */
async function verifyConnectionMetadata(clientOrPool) {
  try {
    const res = await clientOrPool.query(`
      SELECT
        current_database() AS db_name,
        current_user AS user_name,
        inet_server_addr() AS server_ip,
        version() AS pg_version
    `);
    const row = res.rows[0] || {};
    return {
      dbName: row.db_name,
      userName: row.user_name,
      serverIp: row.server_ip ? String(row.server_ip) : null,
      version: row.pg_version,
    };
  } catch {
    // If metadata query fails, return null
    return null;
  }
}

module.exports = {
  sanitizeDbUrl,
  inspectDatabaseTarget,
  hasExplicitConfirmation,
  assertCanRunTest,
  assertCanRunMigration,
  assertCanRunDestructive,
  assertCanRunSeedMaster,
  verifyConnectionMetadata,
};
