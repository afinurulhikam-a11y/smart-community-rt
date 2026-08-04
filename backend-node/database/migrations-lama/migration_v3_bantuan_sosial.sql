-- migration_v3_bantuan_sosial.sql
-- Migrasi: Tambahkan kolom NIK ke tabel users & perbaikan tabel bantuan_sosial
-- Jalankan: psql -U postgres -d smart_community_rt -f database/migration_v3_bantuan_sosial.sql

-- ==============================================================================
-- 1. Tambah kolom NIK ke tabel users
-- NIK adalah data fundamental kependudukan, berguna untuk:
-- Bantuan sosial, surat pengantar, demografi, dll.
-- ==============================================================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS nik VARCHAR(16) UNIQUE;

-- ==============================================================================
-- 2. Pastikan tabel bantuan_sosial sudah ada (idempotent)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS bantuan_sosial (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    jenis_bantuan VARCHAR(100) NOT NULL,
    tahun INT NOT NULL,
    nominal NUMERIC DEFAULT 0,
    status VARCHAR(20) DEFAULT 'Aktif',
    keterangan TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 3. Tambahkan index untuk performa query
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_bantuan_sosial_user_id ON bantuan_sosial(user_id);
CREATE INDEX IF NOT EXISTS idx_bantuan_sosial_tahun ON bantuan_sosial(tahun);
CREATE INDEX IF NOT EXISTS idx_bantuan_sosial_status ON bantuan_sosial(status);
CREATE INDEX IF NOT EXISTS idx_bantuan_sosial_jenis ON bantuan_sosial(jenis_bantuan);
CREATE INDEX IF NOT EXISTS idx_users_nik ON users(nik);
