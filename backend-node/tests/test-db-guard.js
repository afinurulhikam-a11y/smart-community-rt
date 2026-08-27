/**
 * Test Suite: Database Safety Guard
 * ===================================================================
 * Verifies all security requirements for database safety guard:
 * 1. development + database lokal = allowed
 * 2. test + database lokal = allowed
 * 3. development/test + database production = blocked
 * 4. production tanpa explicit confirmation = blocked
 * 5. production dengan explicit confirmation = allowed
 * 6. destructive script pada production = blocked
 * 7. password dan kredensial tersanitasi (tidak pernah bocor)
 * 8. fail-closed terhadap remote host / proxy / cloud URL
 * ===================================================================
 */

const assert = require('assert');
const {
  sanitizeDbUrl,
  inspectDatabaseTarget,
  assertCanRunTest,
  assertCanRunMigration,
  assertCanRunDestructive,
  assertCanRunSeedMaster,
} = require('../src/config/db-guard');

function runAllTests() {
  console.log('\n================================================================');
  console.log('TEST SUITE: DATABASE SAFETY GUARD (DEV / PROD PROTECTION)');
  console.log('================================================================\n');

  let passed = 0;
  let total = 0;

  function it(name, fn) {
    total++;
    try {
      fn();
      console.log(`  ✅ PASS: ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ❌ FAIL: ${name}`);
      console.error(`     Reason: ${err.message}\n`);
      throw err;
    }
  }

  // --------------------------------------------------------------------------
  // TEST GROUP 1: URL Sanitization & Credential Protection
  // --------------------------------------------------------------------------
  console.log('--- 1. Sanitasi URL & Perlindungan Kredensial ---');

  it('Menyembunyikan password pada format postgresql:// standar', () => {
    const raw = 'postgresql://admin_user:superSecretP@ss123@roundhouse.proxy.rlwy.net:54321/railway_prod';
    const sanitized = sanitizeDbUrl(raw);
    assert.strictEqual(sanitized.includes('superSecretP@ss123'), false, 'Password tidak boleh bocor!');
    assert.strictEqual(sanitized, 'postgresql://admin_user:***@roundhouse.proxy.rlwy.net:54321/railway_prod');
  });

  it('Menyembunyikan password pada object konfigurasi lokal', () => {
    const sanitized = sanitizeDbUrl({
      user: 'postgres',
      host: 'localhost',
      port: 5432,
      database: 'smart_community_rt',
    });
    assert.strictEqual(sanitized, 'postgres://postgres:***@localhost:5432/smart_community_rt');
  });

  it('Menangani URL tanpa password dengan aman', () => {
    const raw = 'postgresql://postgres@localhost:5432/smart_community_rt';
    const sanitized = sanitizeDbUrl(raw);
    assert.strictEqual(sanitized, 'postgresql://postgres:***@localhost:5432/smart_community_rt');
  });

  // --------------------------------------------------------------------------
  // TEST GROUP 2: Klasifikasi Target (Local vs Protected)
  // --------------------------------------------------------------------------
  console.log('\n--- 2. Klasifikasi Database (Local vs Protected) ---');

  it('Mendeteksi localhost / 127.0.0.1 sebagai local database', () => {
    const target1 = inspectDatabaseTarget({
      DATABASE_URL: 'postgresql://postgres:pass@localhost:5432/smart_community_rt',
      NODE_ENV: 'development',
    });
    assert.strictEqual(target1.isLocalHost, true);
    assert.strictEqual(target1.isProtected, false);

    const target2 = inspectDatabaseTarget({
      DB_HOST: '127.0.0.1',
      DB_PORT: '5432',
      DB_NAME: 'smart_community_rt',
      NODE_ENV: 'development',
    });
    assert.strictEqual(target2.isLocalHost, true);
    assert.strictEqual(target2.isProtected, false);
  });

  it('Mendeteksi host Docker local (postgres, db, host.docker.internal) sebagai local', () => {
    const target = inspectDatabaseTarget({
      DATABASE_URL: 'postgresql://postgres:pass@postgres:5432/smart_community_rt',
      NODE_ENV: 'development',
    });
    assert.strictEqual(target.isLocalHost, true);
    assert.strictEqual(target.isProtected, false);
  });

  it('Mendeteksi domain Railway / Cloud sebagai protected database', () => {
    const target = inspectDatabaseTarget({
      DATABASE_URL: 'postgresql://postgres:secret@roundhouse.proxy.rlwy.net:12345/railway',
      NODE_ENV: 'development',
    });
    assert.strictEqual(target.isLocalHost, false);
    assert.strictEqual(target.isCloudHost, true);
    assert.strictEqual(target.isProtected, true);
  });

  it('Fail-closed terhadap remote IP atau hostname yang tidak dikenal', () => {
    const target = inspectDatabaseTarget({
      DATABASE_URL: 'postgresql://postgres:secret@203.0.113.50:5432/community_db',
      NODE_ENV: 'development',
    });
    assert.strictEqual(target.isLocalHost, false);
    assert.strictEqual(target.isProtected, true);
  });

  it('Mendeteksi flag NODE_ENV=production sebagai protected database walau di localhost', () => {
    const target = inspectDatabaseTarget({
      DATABASE_URL: 'postgresql://postgres:pass@localhost:5432/smart_community_rt',
      NODE_ENV: 'production',
    });
    assert.strictEqual(target.isExplicitProdEnv, true);
    assert.strictEqual(target.isProtected, true);
  });

  it('Mendeteksi flag RAILWAY_ENVIRONMENT=production sebagai protected database', () => {
    const target = inspectDatabaseTarget({
      DATABASE_URL: 'postgresql://postgres:pass@localhost:5432/smart_community_rt',
      RAILWAY_ENVIRONMENT: 'production',
    });
    assert.strictEqual(target.isExplicitProdEnv, true);
    assert.strictEqual(target.isProtected, true);
  });

  // --------------------------------------------------------------------------
  // TEST GROUP 3: Guard untuk Script Test
  // --------------------------------------------------------------------------
  console.log('\n--- 3. Guard Script Test ---');

  it('Test + Local Database = ALLOWED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:pass@localhost:5432/smart_community_rt',
      NODE_ENV: 'test',
    };
    const target = assertCanRunTest('test-agenda-crud', { env });
    assert.strictEqual(target.isProtected, false);
  });

  it('Test + Production/Railway Database = BLOCKED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:secret@monorail.proxy.rlwy.net:54321/railway',
      NODE_ENV: 'test',
    };
    assert.throws(
      () => assertCanRunTest('test-agenda-crud', { env }),
      (err) => {
        assert.strictEqual(err.code, 'DB_GUARD_TEST_PROHIBITED');
        assert.strictEqual(err.message.includes('secret'), false, 'Password tidak boleh bocor dalam pesan error!');
        assert.strictEqual(err.message.includes('monorail.proxy.rlwy.net:54321/railway'), true);
        return true;
      }
    );
  });

  // --------------------------------------------------------------------------
  // TEST GROUP 4: Guard untuk Migrasi Database
  // --------------------------------------------------------------------------
  console.log('\n--- 4. Guard Migrasi Database ---');

  it('Development + Local Database = ALLOWED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:pass@127.0.0.1:5432/smart_community_rt',
      NODE_ENV: 'development',
    };
    const target = assertCanRunMigration('migration_v32', { env });
    assert.strictEqual(target.isProtected, false);
  });

  it('Production Database TANPA konfirmasi eksplisit = BLOCKED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:secret@roundhouse.proxy.rlwy.net:54321/railway',
      NODE_ENV: 'production',
    };
    assert.throws(
      () => assertCanRunMigration('migration_v32', { env, argv: ['node', 'migration_v32.js'] }),
      (err) => {
        assert.strictEqual(err.code, 'DB_GUARD_PROD_CONFIRMATION_REQUIRED');
        assert.strictEqual(err.message.includes('secret'), false, 'Password tidak boleh bocor!');
        assert.strictEqual(err.message.includes('ALLOW_PROD_MIGRATION=true'), true);
        return true;
      }
    );
  });

  it('Production Database DENGAN env ALLOW_PROD_MIGRATION=true = ALLOWED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:secret@roundhouse.proxy.rlwy.net:54321/railway',
      NODE_ENV: 'production',
      ALLOW_PROD_MIGRATION: 'true',
    };
    const target = assertCanRunMigration('migration_v32', { env, argv: [] });
    assert.strictEqual(target.isProtected, true);
  });

  it('Production Database DENGAN CLI flag --confirm-production = ALLOWED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:secret@roundhouse.proxy.rlwy.net:54321/railway',
      NODE_ENV: 'production',
    };
    const argv = ['node', 'migration_v32.js', '--confirm-production'];
    const target = assertCanRunMigration('migration_v32', { env, argv });
    assert.strictEqual(target.isProtected, true);
  });

  // --------------------------------------------------------------------------
  // TEST GROUP 5: Guard untuk Script Destruktif & Seed Master
  // --------------------------------------------------------------------------
  console.log('\n--- 5. Guard Script Destruktif (init-db, kosongkan-data) & Seed ---');

  it('Destruktif + Local Database = ALLOWED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:pass@localhost:5432/smart_community_rt',
      NODE_ENV: 'development',
    };
    const target = assertCanRunDestructive('kosongkan-data', { env });
    assert.strictEqual(target.isProtected, false);
  });

  it('Destruktif + Production Database = BLOCKED KERAS', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:secret@roundhouse.proxy.rlwy.net:54321/railway',
      NODE_ENV: 'production',
    };
    assert.throws(
      () => assertCanRunDestructive('kosongkan-data', { env }),
      (err) => {
        assert.strictEqual(err.code, 'DB_GUARD_DESTRUCTIVE_PROHIBITED');
        assert.strictEqual(err.message.includes('secret'), false);
        return true;
      }
    );
  });

  it('Seed Master + Local Database = ALLOWED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:pass@localhost:5432/smart_community_rt',
      NODE_ENV: 'development',
    };
    const target = assertCanRunSeedMaster('seed-master', { env });
    assert.strictEqual(target.isProtected, false);
  });

  it('Seed Master + Production Database TANPA konfirmasi = BLOCKED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:secret@roundhouse.proxy.rlwy.net:54321/railway',
      NODE_ENV: 'production',
    };
    assert.throws(
      () => assertCanRunSeedMaster('seed-master', { env, argv: [] }),
      (err) => {
        assert.strictEqual(err.code, 'DB_GUARD_PROD_CONFIRMATION_REQUIRED');
        return true;
      }
    );
  });

  it('Seed Master + Production Database DENGAN konfirmasi = ALLOWED', () => {
    const env = {
      DATABASE_URL: 'postgresql://postgres:secret@roundhouse.proxy.rlwy.net:54321/railway',
      NODE_ENV: 'production',
      ALLOW_PROD_MIGRATION: 'true',
    };
    const target = assertCanRunSeedMaster('seed-master', { env, argv: [] });
    assert.strictEqual(target.isProtected, true);
  });

  // --------------------------------------------------------------------------
  // Summary
  // --------------------------------------------------------------------------
  console.log('\n================================================================');
  console.log(`HASIL: Semua ${passed} / ${total} test Safety Guard LULUS!`);
  console.log('================================================================\n');
}

if (require.main === module) {
  runAllTests();
}

module.exports = { runAllTests };
