# Migrasi Lama — Riwayat, Jangan Dijalankan

Berkas di folder ini adalah rantai migrasi yang dulu harus dijalankan berurutan
untuk menyiapkan database. **Seluruh hasilnya sudah tercermin di
`database/schema.sql`**, jadi tidak ada satu pun yang perlu dijalankan lagi.

Disimpan sebagai riwayat: setiap berkas mencatat alasan sebuah kolom atau tabel
ada, dan sebagian memuat penjelasan yang tidak terekam di tempat lain — misalnya
mengapa `bills` pindah dari per-orang ke per-kartu keluarga (v6), atau mengapa
`inventory.jumlah` tidak boleh dikurangi saat barang dipinjam (v10).

## Pemasangan dari nol

```bash
node init-db.js       # buat database + muat database/schema.sql
node seed-master.js   # isi menu, hak akses, master, dan akun admin pertama
```

## Menambah perubahan skema

Tulis migrasi baru di akar `backend-node`, jalankan, lalu **tangkap ulang**
`database/schema.sql`:

```bash
pg_dump -U postgres -d smart_community_rt --schema-only \
        --no-owner --no-privileges --no-comments
```

Buang baris `\restrict` dan `\unrestrict` dari hasilnya — keduanya meta-command
psql yang tidak dikenali driver node-postgres. Setelah skema ditangkap ulang,
pindahkan migrasi itu ke folder ini.

## Isi

| Berkas | Ringkasan |
|---|---|
| `migration_v2.sql` | announcements, complaints, agenda, polling, visitors, inventory, keluarga, anggota_keluarga |
| `migration_v3_bantuan_sosial.sql` | `users.nik` |
| `migrate.js`, `migration_v4/v5.js` | kolom demografi `anggota_keluarga` |
| `migration_v6_iuran.js` | iuran per kartu keluarga + indeks unik anti-duplikat |
| `migration_v7_kepala_keluarga.js` | isi `keluarga.kepala_keluarga` dari anggota pertama |
| `migration_v8_kas.js` | kategori kas + `finances.ref_id` (anti dobel-posting) |
| `migration_v9_bop.js` | `kategori_bop` dan `alokasi_bop` (pagu) |
| `migration_v10_inventaris.js` | nilai barang + tanggal rencana kembali |
| `migration_v11_hak_akses.js` | `menu_items` dan `role_permissions` |
| `migration_v12_reset_sistem.js` | jatuhkan 7 tabel warisan, buat `reset_logs` |
| `migration_v13_akses_warga.js` | warga boleh mengajukan peminjaman |
| `migration_v14_hapus_media.js` | jatuhkan modul Media |
| `migration_v15_bersihkan.js` | jatuhkan `roles`, `master_*`, `struktur_rt`, `umkm` |
| `fix-db.js` | pembentukan awal tabel inti — digantikan `schema.sql` |
