require('dotenv').config();
const { assertCanRunDestructive } = require('../../src/config/db-guard');
assertCanRunDestructive('seed_dummy_inventory');

const { pool } = require('../../src/config/database');

const dummyItems = [
  {
    nama_barang: 'Tenda Lipat Serbaguna (4x6m)',
    kategori: 'Peralatan Acara',
    jumlah: 5,
    kondisi: 'Baik',
    lokasi: 'Gudang Balai RT',
    nilai_barang: 1200000,
    keterangan: 'Bisa dipinjam untuk acara keluarga / hajan warga',
  },
  {
    nama_barang: 'Kursi Plastik Napolly',
    kategori: 'Peralatan Acara',
    jumlah: 100,
    kondisi: 'Baik',
    lokasi: 'Gudang Balai RT',
    nilai_barang: 75000,
    keterangan: 'Warna hijau, susunan di rak gudang',
  },
  {
    nama_barang: 'Sound System Portable & Mic Wireless',
    kategori: 'Elektronik',
    jumlah: 2,
    kondisi: 'Baik',
    lokasi: 'Rumah Ketua RT',
    nilai_barang: 2500000,
    keterangan: 'Lengkap dengan 2 mic wireless & kabel charger',
  },
  {
    nama_barang: 'Genset Silent Honda 2500W',
    kategori: 'Peralatan',
    jumlah: 2,
    kondisi: 'Baik',
    lokasi: 'Gudang Pos Ronda',
    nilai_barang: 4500000,
    keterangan: 'Bahan bakar bensin murni',
  },
  {
    nama_barang: 'Meja Lipat Stenlis 120x60',
    kategori: 'Peralatan Acara',
    jumlah: 10,
    kondisi: 'Baik',
    lokasi: 'Gudang Balai RT',
    nilai_barang: 350000,
    keterangan: 'Kaki lipat praktis',
  },
  {
    nama_barang: 'Proyektor Epson & Layar Screen 70 Inch',
    kategori: 'Elektronik',
    jumlah: 1,
    kondisi: 'Baik',
    lokasi: 'Rumah Sekretaris RT',
    nilai_barang: 5000000,
    keterangan: 'Kabel HDMI & tripod screen lengkap',
  },
  {
    nama_barang: 'Mesin Pemotong Rumput Honda',
    kategori: 'Peralatan Kebersihan',
    jumlah: 3,
    kondisi: 'Baik',
    lokasi: 'Pos Ronda Utama',
    nilai_barang: 150000,
    keterangan: 'Alat pengaman ronda malam',
  },
  {
    nama_barang: 'HT / Handy Talkie Radio',
    kategori: 'Keamanan',
    jumlah: 4,
    kondisi: 'Baik',
    lokasi: 'Pos Ronda Utama',
    nilai_barang: 350000,
    keterangan: 'Frekuensi siskamling RT',
  },
  {
    nama_barang: 'Rompi Siskamling',
    kategori: 'Keamanan',
    jumlah: 10,
    kondisi: 'Baik',
    lokasi: 'Pos Ronda Utama',
    nilai_barang: 280000,
    keterangan: '4 stop kontak tugas berat',
  },
  {
    nama_barang: 'Lampu Sorot LED Portable 100W',
    kategori: 'Peralatan Acara',
    jumlah: 6,
    kondisi: 'Baik',
    lokasi: 'Pos Ronda Utama',
    nilai_barang: 220000,
    keterangan: 'Sudah dilengkapi kabel & colokan',
  },
];

async function seedInventory() {
  try {
    console.log('Inserting dummy inventory items...');
    for (const item of dummyItems) {
      // Check if already exists to avoid duplicates
      const check = await pool.query('SELECT id FROM inventory WHERE nama_barang = $1', [item.nama_barang]);
      if (check.rows.length === 0) {
        await pool.query(
          `INSERT INTO inventory (nama_barang, kategori, jumlah, kondisi, lokasi, nilai_barang, keterangan, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())`,
          [item.nama_barang, item.kategori, item.jumlah, item.kondisi, item.lokasi, item.nilai_barang, item.keterangan]
        );
        console.log(`[+] Added: ${item.nama_barang} (${item.jumlah} unit)`);
      } else {
        console.log(`[*] Skipped (already exists): ${item.nama_barang}`);
      }
    }
    console.log('\nSeed dummy inventory completed successfully!');
  } catch (err) {
    console.error('Seed Error:', err);
  } finally {
    await pool.end();
  }
}

seedInventory();
