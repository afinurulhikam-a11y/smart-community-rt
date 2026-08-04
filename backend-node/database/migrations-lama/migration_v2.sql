-- migration_v2.sql
-- Migrasi database untuk modul-modul baru Smart Community RT
-- Jalankan: psql -U postgres -d smart_community_rt -f database/migration_v2.sql

-- ==============================================================================
-- PENGUMUMAN (Announcements)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS announcements (
    id SERIAL PRIMARY KEY,
    judul VARCHAR(255) NOT NULL,
    isi TEXT NOT NULL,
    kategori VARCHAR(50) DEFAULT 'Umum',
    status VARCHAR(20) DEFAULT 'draft',
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- PENGADUAN / SARAN (Complaints)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS complaints (
    id SERIAL PRIMARY KEY,
    kode_tiket VARCHAR(20) UNIQUE NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    judul VARCHAR(255) NOT NULL,
    deskripsi TEXT,
    kategori VARCHAR(100),
    status VARCHAR(50) DEFAULT 'Menunggu',
    response TEXT,
    responded_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- AGENDA KEGIATAN (Events)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS agenda (
    id SERIAL PRIMARY KEY,
    judul VARCHAR(255) NOT NULL,
    deskripsi TEXT,
    tipe VARCHAR(50) DEFAULT 'Kegiatan',
    tanggal DATE NOT NULL,
    waktu_mulai TIME,
    waktu_selesai TIME,
    lokasi VARCHAR(255),
    status VARCHAR(50) DEFAULT 'Akan Datang',
    notulen_url VARCHAR(500),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- POLLING WARGA
-- ==============================================================================
CREATE TABLE IF NOT EXISTS polling (
    id SERIAL PRIMARY KEY,
    judul VARCHAR(255) NOT NULL,
    deskripsi TEXT,
    status VARCHAR(20) DEFAULT 'aktif',
    tanggal_mulai DATE NOT NULL,
    tanggal_selesai DATE NOT NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS polling_options (
    id SERIAL PRIMARY KEY,
    polling_id INT REFERENCES polling(id) ON DELETE CASCADE,
    label VARCHAR(255) NOT NULL,
    vote_count INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS polling_votes (
    id SERIAL PRIMARY KEY,
    polling_id INT REFERENCES polling(id) ON DELETE CASCADE,
    option_id INT REFERENCES polling_options(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(polling_id, user_id)
);

-- ==============================================================================
-- E-VISITOR (Buku Tamu)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS visitors (
    id SERIAL PRIMARY KEY,
    nama_tamu VARCHAR(255) NOT NULL,
    no_hp_tamu VARCHAR(20),
    blok_tujuan VARCHAR(100),
    no_hp_tujuan VARCHAR(20),
    tipe_keperluan VARCHAR(50) DEFAULT 'Kunjungan',
    detail_keperluan TEXT,
    plat_nomor VARCHAR(20),
    jenis_kendaraan VARCHAR(50),
    jam_masuk TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    jam_keluar TIMESTAMP,
    status VARCHAR(20) DEFAULT 'Di Dalam',
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- UMKM (Direktori Usaha Warga)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS umkm (
    id SERIAL PRIMARY KEY,
    nama_usaha VARCHAR(255) NOT NULL,
    kategori VARCHAR(100) DEFAULT 'Lainnya',
    deskripsi TEXT,
    pemilik_id UUID REFERENCES users(id) ON DELETE CASCADE,
    no_hp VARCHAR(20),
    alamat VARCHAR(255),
    jam_operasional VARCHAR(100),
    status VARCHAR(20) DEFAULT 'Aktif',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- BANTUAN SOSIAL
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
-- INVENTARIS BARANG
-- ==============================================================================
CREATE TABLE IF NOT EXISTS inventory (
    id SERIAL PRIMARY KEY,
    nama_barang VARCHAR(255) NOT NULL,
    kategori VARCHAR(100),
    jumlah INT DEFAULT 0,
    kondisi VARCHAR(50) DEFAULT 'Baik',
    lokasi VARCHAR(255),
    keterangan TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- PEMINJAMAN BARANG
-- ==============================================================================
CREATE TABLE IF NOT EXISTS borrowings (
    id SERIAL PRIMARY KEY,
    inventory_id INT REFERENCES inventory(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    jumlah INT DEFAULT 1,
    tanggal_pinjam DATE DEFAULT CURRENT_DATE,
    tanggal_kembali DATE,
    status VARCHAR(20) DEFAULT 'Dipinjam',
    keterangan TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- STRUKTUR ORGANISASI RT
-- ==============================================================================
CREATE TABLE IF NOT EXISTS struktur_rt (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    nama VARCHAR(255) NOT NULL,
    jabatan VARCHAR(100) NOT NULL,
    no_hp VARCHAR(20),
    periode VARCHAR(50),
    urutan INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- KARTU KELUARGA
-- ==============================================================================
CREATE TABLE IF NOT EXISTS keluarga (
    id SERIAL PRIMARY KEY,
    no_kk VARCHAR(16) UNIQUE NOT NULL,
    kepala_keluarga VARCHAR(255) NOT NULL,
    alamat TEXT,
    rt VARCHAR(3) DEFAULT '001',
    rw VARCHAR(3) DEFAULT '001',
    kelurahan VARCHAR(100),
    kecamatan VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS anggota_keluarga (
    id SERIAL PRIMARY KEY,
    keluarga_id INT REFERENCES keluarga(id) ON DELETE CASCADE,
    nik VARCHAR(16) UNIQUE,
    nama VARCHAR(255) NOT NULL,
    jenis_kelamin VARCHAR(1) CHECK (jenis_kelamin IN ('L', 'P')),
    tempat_lahir VARCHAR(100),
    tanggal_lahir DATE,
    agama VARCHAR(50),
    status_keluarga VARCHAR(50),
    pekerjaan VARCHAR(100),
    pendidikan VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- MEDIA (Berita & Video)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS media (
    id SERIAL PRIMARY KEY,
    judul VARCHAR(255) NOT NULL,
    deskripsi TEXT,
    tipe VARCHAR(20) NOT NULL CHECK (tipe IN ('berita', 'video')),
    url VARCHAR(500),
    thumbnail_url VARCHAR(500),
    kategori VARCHAR(100),
    is_published BOOLEAN DEFAULT true,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
