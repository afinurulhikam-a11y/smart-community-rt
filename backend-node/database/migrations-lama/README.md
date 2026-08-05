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
| `migration_v19_log_append_only.js` | `activity_logs` jadi hanya-tambah: trigger menolak UPDATE, DELETE, **dan TRUNCATE**, plus tiga indeks |
| `migration_v20_log_lepas_fk_user.js` | melepas FK `activity_logs.user_id`, yang membuat v19 mustahil dipenuhi |
| `migration-soft-delete.js` | `deleted_at` pada `users`, `keluarga`, `inventory` |
| `migration-soft-delete-tahap3.js` | `deleted_at` pada `complaints`, `letters`, `agenda`, `finances` |
| `fix-db.js` | pembentukan awal tabel inti — digantikan `schema.sql` |

**Kedua skrip soft-delete itu adalah alasan konvensi penamaan ini ada.** Namanya tidak mengikuti pola `migration_vN_*`, jadi keduanya luput saat `schema.sql` ditangkap ulang — dan selama berbulan-bulan `schema.sql` tidak punya kolom `deleted_at` sementara delapan controller menyaring dengan `WHERE deleted_at IS NULL`. Efeknya tidak terlihat di mesin yang sudah pernah menjalankannya, tetapi **setiap instalasi baru langsung mati**: panggilan pertama ke `/api/families`, `/api/complaints`, `/api/letters`, `/api/inventory`, `/api/finances`, atau `/api/users` gagal dengan `column "deleted_at" does not exist`.

Kolomnya kini ada di `schema.sql`, jadi instalasi baru tidak perlu menjalankan keduanya. Beri nama `migration_vN_*.js` untuk migrasi berikutnya, dan tangkap ulang `schema.sql` sesudahnya.

**v19 dan v20 sudah ada di `schema.sql`, jadi instalasi baru tidak perlu menjalankannya.** Keduanya disimpan karena mencatat dua hal yang tidak terbaca dari hasil akhirnya:

- **v19: TRUNCATE butuh trigger-nya sendiri.** `BEFORE DELETE FOR EACH ROW` tidak pernah menyala saat TRUNCATE. Trigger baris saja memberi rasa aman palsu — dan itu terjadi sungguhan di sistem ini: jumlah log turun dari 67 ke 10 baris *setelah* trigger baris terpasang.
- **v20: tabel hanya-tambah tidak bisa memikul `ON DELETE SET NULL`.** Aksi itu diwujudkan sebagai `UPDATE`, yang ditolak trigger v19. Akibatnya tidak ada akun yang pernah muncul di jejak audit yang bisa dihapus — selamanya. Itu efek samping, bukan keputusan.

Keduanya tetap perlu dijalankan pada database yang **sudah ada sebelum** kedua perubahan itu masuk ke `schema.sql` — misalnya database produksi di Railway.
