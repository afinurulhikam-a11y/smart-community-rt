# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Smart Community RT — a neighborhood (RT) management platform in three parts:

- `backend-node/` — Express + PostgreSQL REST API with a WebSocket server on the same HTTP port
- `frontend-flutter/` — Flutter client (Android / Web / Windows) consuming that API
- `iot-firmware/esp32_alarm/` — ESP32 sketch that connects to the backend WebSocket as a physical alarm (buzzer + LEDs)

Domain language is Indonesian throughout (warga = resident, iuran = dues, kas = cash book, surat = letter, pengaduan = complaint). Keep new identifiers, log messages, and user-facing strings in Indonesian to match.

`install.cmd` at the repo root is the Claude Code installer, not part of this project. Ignore it.

## Commands

### Backend (`cd backend-node`)

```bash
npm run dev          # nodemon on src/index.js
npm start            # kills port 3001 first (prestart), then node src/index.js
npx eslint .         # lint — configured in eslint.config.js, but no npm script wraps it
```

The server reads `PORT` from `.env` (currently 3001). `src/index.js` falls back to 3000 if `PORT` is unset — but the Flutter client and the `prestart` kill-port both hardcode 3001, so leave `PORT=3001` set.

Required `.env` keys: `PORT`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `JWT_SECRET`.

Health check: `GET http://localhost:3001/api/health` — also reports the live WebSocket client count.

### Frontend (`cd frontend-flutter`)

```bash
flutter run -d chrome              # web
flutter run -d windows             # desktop
flutter run                        # attached device
flutter test                       # all tests
flutter test test/widget_test.dart # single test file
flutter test --name "<substring>"  # single test by name
flutter analyze                    # lint (flutter_lints via analysis_options.yaml)
```

### Firmware

Open `iot-firmware/esp32_alarm/esp32_alarm.ino` in Arduino IDE. Requires the `WebSockets` library (Markus Sattler). Edit `WIFI_SSID`, `WIFI_PASSWORD`, and `WS_HOST` at the top before flashing.

## Database setup

**Two commands, from nothing to a running database:**

```bash
cd backend-node
node init-db.js       # drops + recreates the DB, loads database/schema.sql
node seed-master.js   # menus, permissions, master tables, first admin account
```

`database/schema.sql` is now captured directly from the running database and is the **single source of structure** — 29 tables. It replaced both the 16-step migration chain and the old `schema.sql`, which had described a normalized design (`users.role_id → roles`, `users.warga_id → warga`) the controllers never used.

`seed-master.js` reads menus and permissions from `src/config/permissions.js` rather than hardcoding INSERTs, so that file stays the one source of truth it already is for the middleware and the permission-reset endpoint. Master rows (`jenis_iuran`, `kategori_kas`, `kategori_bop`) and the first admin come from `src/config/master-data.js`.

The 16 historical migrations live in `database/migrations-lama/` with a README explaining each. **Do not run them** — everything they did is already in `schema.sql`. They are kept because several record *why* a column exists (v6: bills moved from per-person to per-KK; v10: `inventory.jumlah` must not be decremented on loan).

**Adding a schema change:** write a new idempotent `migration_vN_*.js` in `backend-node/`, run it, then re-capture `schema.sql` with `pg_dump --schema-only --no-owner --no-privileges --no-comments` and delete the `\restrict` / `\unrestrict` lines (psql meta-commands that `node-postgres` cannot parse). Then move the migration into `migrations-lama/`.

`node periksa-kesehatan.js` audits a live installation after a testing session: money integrity (paid bills with no payment record, payments with no cash row, double-posted cash, orphans), stale `is_pending` locks that would silently block a resident from paying, an endpoint sweep across all five roles, and per-table row counts. **It only reads** — safe to run against real data. Exits 1 when it finds something. Every check is written so that *any* row returned means a problem, so the output needs no interpretation.

`kosongkan-data.js` empties all operational data while keeping pengurus accounts, masters, menus, and permissions. It reads the delete order from `GRUP_TOTAL` in `src/config/reset-groups.js` instead of duplicating it.

Primary keys are mostly `UUID DEFAULT uuid_generate_v4()` for the core tables, but `SERIAL` for the tables that came from `migration_v2.sql` — check before writing joins.

**`anggota_keluarga.jenis_kelamin` is `varchar(1)` holding `L`/`P`, and every write must go through `jenisKelamin()` in `src/utils/normalisasi.js`.** Statistik counts `= 'L'` / `= 'P'`, so the narrow column is a feature: it stops inconsistent values from silently skewing the demographic charts.

The old inline rule `nilai.startsWith('P') ? 'P' : 'L'` in the Excel importer **inverted the two commonest Indonesian words** — `PRIA` became `P` and `WANITA` became `L`, with no error at all. The normaliser matches whole words first and only falls back to a prefix guess. Unrecognised input returns the caller's default rather than inventing a gender.

Excel export writes **`Laki-laki` / `Perempuan`**, not `L`/`P`: the file is edited by humans, and single letters invited free-form entries like "Pria" that the old importer then mis-mapped. The importer accepts both, so older exported files still import correctly.

**Resident data lives in `keluarga` + `anggota_keluarga`** — that is the only source both Data Warga and Statistik read. `warga.controller.js` joins those two despite its name; it never touched a table called `warga`.

**Thirteen tables have been dropped and must not be resurrected.** Each was verified first by sweeping all of `backend-node/src` for any `FROM` / `JOIN` / `INSERT` / `UPDATE` / `DELETE` naming it:

- v12: `warga`, `kartu_keluarga`, `pengaduan`, `surat_pengantar`, `tagihan_iuran`, `buku_kas`, `pengumuman` — the abandoned half of the old normalized design, plus the dead column `users.warga_id` (filled 0 of 48).
- v14: `media` — the Berita/Video module, removed as unneeded.
- v15: `roles`, `master_pekerjaan`, `master_pendidikan`, `struktur_rt`, `umkm`, plus `users.role_id`.

`roles` repeated the `warga_id` pattern exactly: a real FK from `users.role_id`, filled in 1 of 48 rows, while every authorization check reads the `users.role` VARCHAR. **Roles are strings, not a table.**

**`users` carries two vestigial columns from the old design and only one survives.** `password` was dropped in v16 — it was written (a copy of `password_hash`) and never read by a single query. `username` stays and is load-bearing: `warga.controller.js` stores each resident's NIK there, and `login` matches `email = $1 OR username = $1`. What v16 fixed was its `NOT NULL`: because `auth.controller.js` register never sets it, **`POST /api/auth/register` failed for every caller** until then. The bug hid because the only account-creation path anyone used was Data Warga, which happens to fill both columns.

**Iuran (`bills`) is billed per kartu keluarga, not per person.** `bills.keluarga_id` is the billing target; `bills.user_id` only records who paid. `jenis_iuran` is the editable master table behind the type dropdown — it is live, not legacy, and had no FK into the dropped tables. `POST /api/bills/generate` inserts one row per `keluarga` and relies on `bills_kk_jenis_bulan_uniq` to stay idempotent, so it is safe to re-run. Do not bill against `users` with `role = 'warga'`: those accounts are created one per resident — infants included — and some have no `anggota_keluarga` row at all.

## Pembayaran online (Midtrans)

**`payment_transactions` records *attempts*; `bill_payments` records *money actually received*.** Keeping them separate is what lets a bill stay unpaid while a payment is in flight, and it is why `finances` never reports money that did not arrive. `catatKeKasRt()` is reached only from the settlement path.

A bill is **never** marked lunas from anything the client sends. The single path is `terapkanStatus()` in `payment.controller.js`, and it always starts from `midtrans.ambilStatus()` — the official status fetched from Midtrans' own servers.

**Four money guards, all load-bearing:**
1. `verifikasiTandaTangan` checks `sha512(order_id + status_code + gross_amount + serverKey)`. Without it, anyone who learns the webhook URL could POST a fake `settlement`.
2. The webhook **re-fetches status from Midtrans** and ignores the POST body's own claims.
3. `gross_amount` from Midtrans must match the stored amount — otherwise someone could pay Rp1 against a Rp50.000 bill.
4. Idempotency in three layers: `order_id` UNIQUE, transitions only allowed from `pending`, and `finances_ref_uniq` as the backstop. **Midtrans deliberately resends the same notification**; three identical deliveries must still produce exactly one cash row.

`payment_transaction_bills.is_pending` exists because a partial unique index **cannot reference another table**. It mirrors the parent's status so `payment_bill_pending_uniq` can enforce one live payment attempt per bill — without it a resident could open two Midtrans orders for the same bill.

`nominal` is **copied** into the join table rather than re-read from `bills`: the amount charged must stay what was quoted when the resident pressed Bayar.

`POST /payments/notifikasi` and `GET /payments/selesai` are registered **above** `router.use(authMiddleware)` — Midtrans has no JWT, so requiring one would make the webhook impossible.

`POST /payments/iuran` is guarded by `view`, **not `create`** — same trap as polling: `create` on this module means *issuing a bill* (`POST /bills`). Ownership is enforced in the controller instead.

**`POST /bills/:id/pay` is now `requirePermission('keuangan.iuran','update')`.** It previously had no permission guard at all while the warga screen offered "Tunai" and "Transfer" buttons calling it — so a resident could mark their own bill lunas and post income to Kas RT without paying anything. That route is now for pengurus recording cash they actually received.

`payment_screen.dart` uses `webview_flutter` on Android but **falls back to `url_launcher` when `kIsWeb`** — `webview_flutter` has no web implementation, and instantiating `WebViewController` there would throw.

**Paying an iuran bill auto-posts to the Kas RT cash book.** `payBill` and `payBillsBulk` call `catatKeKasRt()` inside their existing transaction, so a payment can never exist without its `finances` row. The link is `finances.ref_id → bill_payments.id`, and `finances_ref_uniq` makes double-posting impossible. Rows with `sumber = 'iuran'` are rejected by `updateTransaction` and `deleteTransaction` — correct them through Iuran Warga, not the cash book.

`FinanceModel` is shared by `BopProvider` and six screens (Kas RT, BOP, Laporan Keuangan, both dashboards, the warga report) — a BOP row has the same shape as a Kas RT row. Only ever **add** fields with defaults; `kategori` must stay a String. `FinanceSummary` is shared by everything *except* BOP, which uses `BopSummary` instead because pagu has no Kas RT counterpart. `finances.getSummary` deliberately returns both scopes: `pemasukan_bulan`/`pengeluaran_bulan` follow the period filter, `saldo_total` never does — that is what makes the "SALDO KAS SAAT INI" card honest.

**Dana BOP tracks a budget ceiling, so it has two different "remaining" numbers and both are correct.** `sisa_pagu` = `alokasi` − `terpakai` (spending headroom, from `alokasi_bop`), while `saldo` = pemasukan − pengeluaran (cash actually on hand). They diverge whenever an allocation is recorded before the money is disbursed. The dashboard "SISA DANA BOP" card and the pengurus screen both read `sisaPagu`. Overspending the pagu is **warned, never blocked** — `createTransaction` returns a `peringatan` field and still saves, because a treasurer must be able to record what already happened.

The running-balance window uses `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, not the default `RANGE`. Rows inserted in one transaction share an identical `created_at` (Postgres `CURRENT_TIMESTAMP` is transaction-start time), and `RANGE` would collapse those ties into one bucket and report the wrong balance.

**Inventaris: `inventory.jumlah` is total owned and is never mutated by borrowing.** Availability is derived at read time as total minus the sum of open borrowings — the old code did `UPDATE inventory SET jumlah = jumlah - n`, which silently redefined the column as remaining stock and destroyed the record of how many items the RT actually owns. Likewise `Terlambat` is a **derived** status, computed from `tanggal_rencana_kembali < CURRENT_DATE`; only `Dipinjam` and `Dikembalikan` are ever stored, so no scheduler is needed. Filtering by `status=Terlambat` maps to that same condition. In `inventory.routes.js` every `/borrowings` route must stay declared **before** `/:id`, or `GET /borrowings` is swallowed as an item lookup.

`node-postgres` returns a `DATE` column as local midnight, so formatting one with `toISOString()` shifts it back a day in WIB. Use local date components — see `formatTanggal` in `src/controllers/warga.controller.js`. ExcelJS is the opposite: its date cells are UTC-based, so `parseTanggalExcel` in the same file uses `getUTC*`.

## Access control

**Permissions live in the database, not in role names.** `requirePermission(kode, aksi)` in `src/middleware/auth.middleware.js` reads `role_permissions`; `roleGuard` survives only for genuinely role-based rules (`roleGuard('warga')` on emergency/trigger, `roleGuard('admin')` on the access screen itself). The default matrix and the menu registry are both in `src/config/permissions.js` — that file is the single source of truth, and `POST /api/menu-akses/reset` replays it.

Three things keep an administrator from ever being locked out, and all three are load-bearing:
1. `requirePermission` returns `next()` for `role === 'admin'` **before touching the table at all**.
2. Menus flagged `is_sistem` (Menu & Akses, Reset Sistem) are refused for every non-admin role regardless of what the table says.
3. `PUT /api/menu-akses` rejects any change targeting `role = 'admin'` or an `is_sistem` menu.

`pengurus_rt` **is gone.** It used to be a roleGuard alias that expanded into ketua_rt + sekretaris + bendahara, which is why all three had identical access. No user ever had that role. Do not reintroduce it — give the three roles distinct permission rows instead.

A route file must call `router.use(authMiddleware)` **before** any `requirePermission`; putting the permission check first yields 401 instead of 403 because `req.user` is not populated yet.

**`auth.routes.js` is the one file where `router.use(authMiddleware)` must NOT sit at the top.** `POST /login` and `POST /register` issue the token, so guarding them makes login impossible for everyone — and the failure is invisible to an already-logged-in session, because `tryAutoLogin()` reuses the stored token. Both routes are declared *above* the `router.use(authMiddleware)` line; keep them there. Anything that bulk-normalizes route files must skip this one.

Hiding a menu in `sidebar_menu.dart` is presentation only. `PermissionProvider` drives what is shown, but the endpoint guard is what actually enforces it.

**Every role goes through the same sidebar and the same screens — including `warga`.** There is no `!isWarga` gate and no hardcoded resident menu; both existed and meant admins could grant warga a module in Menu & Akses and nothing would appear. Three modules render a different screen per role, chosen in `main_dashboard._buildBody`, not by a separate menu index:

| Menu index | Pengurus | Warga |
|---|---|---|
| 21 `keuangan.iuran` | `IuranWargaScreen` | `BillListScreen` |
| 22 `keuangan.kas` | `KasRtScreen` | `FinanceReportScreen` |
| 44 `layanan.surat` | `SuratMenyuratScreen` | `LetterRequestScreen` |

**Screens must gate their own action buttons.** The sidebar's *View* badge is cosmetic; a screen that ignores permissions shows Add/Edit/Delete buttons that all end in 403. Each gated screen declares a `_kodeIzin` constant and `_bolehTambah` / `_bolehUbah` / `_bolehHapus` getters over `PermissionProvider`, and renders `BannerLihatSaja(kode: _kodeIzin)` which appears by itself when the role is view-only. Export buttons stay ungated on purpose — copying data you are allowed to read is not a mutation, and sekretaris needs it for reports.

**`aspirasi.polling`'s `create` means creating a poll, not voting.** `POST /polling` and `POST /polling/:id/vote` would otherwise share a permission, so granting warga `create` to let them vote would also let them start polls. Voting is guarded by `view` instead; the domain rules (poll must be active, `UNIQUE (polling_id, user_id)`) do the rest. `getPolling` returns `sudah_vote` and `pilihan_saya` per caller so the screen can lock the button instead of letting it 409.

**Row-level scoping for `warga` lives in the controllers, not the permission table.** The pattern is one `if (req.user.role === 'warga')` clause per list query: `bills` via `users.no_kk`, `letters` and `complaints` and `borrowings` via `user_id`. Stats endpoints must be filtered the same way or the cards report on data the resident may not see. `createBorrowing` **ignores `user_id` from the body for warga** and forces `req.user.id` — otherwise a resident could log a loan against a neighbour.

`GET /inventory/borrowings/barang-tersedia` exists because warga hold `inventaris.peminjaman` but not `inventaris.barang`: it is guarded by the loan permission and returns only what the borrow form needs, without `nilai_barang`.

## Modules that share a screen

**Pengumuman has no screen of its own — it is the fourth tab of Agenda & Kegiatan.** `announcements` keeps its own table, controller, route, and `kegiatan.pengumuman` permission, so an admin can still open or close it independently in Menu & Akses; only the UI is shared. `AnnouncementProvider` is consumed solely by `agenda_kegiatan_screen.dart`. The tile on the warga dashboard therefore points at menu index 50, not a separate index.

**The project ships with no data.** `users` holds only the four pengurus accounts; every operational table is empty. Screens will look blank until data is entered — that is expected, not a bug. `seed-master.js` creates `admin@example.com` / `admin123` on a fresh install; change it immediately.

## Reset Sistem

**Deletion order is hand-written in `src/config/reset-groups.js` and must stay that way.** Postgres cannot be trusted to work it out, because the schema contains a cascade that runs straight into a restrict:

```
keluarga --CASCADE--> bills --RESTRICT--> bill_payments
```

Deleting `keluarga` cascades into `bills`, and that cascade is then refused by `bill_payments`, aborting the whole transaction. The only way through is to delete `bill_payments` explicitly first. The same shape applies to `users`: eight tables (`bills`, `bill_payments`, `finances`, `letters`, `emergency_alerts`, `bop_finances`, `alokasi_bop`, `borrowings`) hold RESTRICT references, so a warga account cannot be deleted while any of them still points at it.

Each group therefore lists its tables child → parent, and rows that die because of an FK chain rather than because they are the group's target are flagged `ikutan: true` so the preview can show them separately. **Nothing gets deleted silently.**

The controller never accepts a table name from the client — only a group `kode`. A load-time self-check in `reset-groups.js` throws if any group references a protected table, so a typo stops the server at startup instead of destroying data at runtime.

### Audit trail

**`logActivity(req, tipe, aktivitas)` in `src/services/log.service.js` is called from every write path that touches money, resident data, or access control** — 11 controllers. It was 4, and in practice recorded almost nothing: a real testing session produced 22 log rows of which 20 were logins, while a Rp 50.000 cash payment left no trace at all. The Log Aktivitas screen existed and looked complete, which made the gap easy to miss.

`logActivity` swallows its own errors by design, so a failed insert can never fail the request. Call it **after** the operation succeeds — and after `COMMIT` where there is a transaction, so the trail only records what actually persisted.

`tipe` is one of `CREATE`, `UPDATE`, `DELETE`, `PEMBAYARAN`, `IMPORT`, `AKSES`, `LOGIN`. Keep to that set: the Log Aktivitas screen filters on it. `rupiah()` from the same service formats amounts so a line reads the same whether it came from Kas RT, BOP, or an iuran payment.

`reset_logs` records every execution and is itself protected from every group, including Reset Total. That matters because the "Log Aktivitas" group empties `activity_logs`: `logActivity` is called **after** COMMIT, or the reset would erase its own audit trail.

Protected from every reset: `roles`, `menu_items`, `role_permissions`, `jenis_iuran`, `kategori_kas`, `kategori_bop`, `struktur_rt`, `master_pendidikan`, `master_pekerjaan`, `reset_logs`, and `users` rows with role `admin`/`ketua_rt`/`sekretaris`/`bendahara`.

Routes use `roleGuard('admin')`, not `requirePermission` — same reasoning as `menu_akses.routes.js`. The authority to wipe data must not depend on a table that can itself be wiped.

`ResetProvider.eksekusi` deliberately bypasses `ApiService.post`: that helper retries twice on timeout, and a retried DELETE would log the same reset twice. It uses a single `http.post` with a 120s timeout instead.

## Architecture

### Backend request flow

`src/index.js` → `src/routes/*.routes.js` → `src/controllers/*.controller.js` → `pool.query` from `src/config/database.js`.

There is no service or model layer. Controllers own raw parameterized SQL directly. There is one shared `pg.Pool`.

Adding a feature means four coordinated edits: a controller, a route file, a `app.use('/api/...')` line in `src/index.js`, and a matching getter in `frontend-flutter/lib/core/constants/api_constants.dart`.

### Auth and roles

`src/middleware/auth.middleware.js` exports two pieces, composed per-route:

```js
router.post('/', authMiddleware, roleGuard('admin', 'pengurus_rt'), createBill);
```

- `authMiddleware` accepts a JWT from `Authorization: Bearer <token>` **or** from a `?token=` query param — the query fallback exists so browsers can hit PDF/file download endpoints directly.
- `roleGuard('pengurus_rt')` implicitly expands to also allow `ketua_rt`, `sekretaris`, and `bendahara`. Pass `'pengurus_rt'` when you mean "any board member"; name the specific role only to narrow.

Roles in use: `admin`, `pengurus_rt`, `ketua_rt`, `sekretaris`, `bendahara`, `warga`.

### Response envelope

Every endpoint returns `{ success: bool, message?: string, data?: any, count?: number }`. The Flutter `ApiService` relies on this — it returns the decoded body directly and callers branch on `response['success'] == true`, so a bare array or a raw error string will break the client silently.

**`success: false` alone does not tell you whether the server refused or was never reached.** `ApiService` never throws, so a dead backend and a rejected token look identical to callers. Two fields disambiguate them and both must be preserved:

- `statusCode` — injected by `_handleResponse` from the HTTP response (`??=`, so a backend-supplied value wins).
- `ApiService.penandaOffline` (`'offline': true`) — added on the connection-failure path only.

**Nothing on the startup path may await a network call.** `ApiService` retries twice on a 10s timeout with backoff, so one unreachable request costs ~31s. `AuthGate` used to await `tryAutoLogin()` *and then* `izin.muat()` before showing anything — close to a minute of motionless splash screen when the phone could not reach the backend, indistinguishable from a hang. `tryAutoLogin` now restores the cached session and returns immediately, validating the token in the background (`_periksaSesiDiLatar`), and `izin.muat()` is bounded by `_batasTungguIzin` (6s). A briefly incomplete menu beats a frozen splash. `test/auto_login_test.dart` asserts session restore finishes in under 3s.

**This mattered enough to log users out.** `AuthService.tryAutoLogin` validated the stored token against `/auth/me` and treated *any* non-success reply as a rejection, calling `logout()` and deleting the token. Since an unreachable server also returns `success: false`, the backend merely being slow to start — or ngrok not yet up, or Wi-Fi not yet associated — wiped the session. The user was sent to the login screen on every launch and there was nothing on screen to explain why. It now logs out **only on 401/403**; anything else keeps the cached session and lets the next real request fail with its own message. `test/auto_login_test.dart` covers it — the test needs no mocking, because running without a backend *is* the failure case.

### WebSocket / panic button

`src/config/websocket.js` attaches a `ws` server to the same HTTP server and exports `broadcast(data)`. Broadcasts are untargeted — every connected client (Flutter apps and ESP32 boards alike) receives every message, and there is no auth on the WebSocket upgrade.

The alarm flow:

1. `POST /api/emergency/trigger` → row inserted into `emergency_alerts` → `broadcast({ type: 'ALARM_ON', ... })`
2. Flutter `WebSocketService` sets `_lastAlarm`, exposing `hasActiveAlarm`; ESP32 fires buzzer + red LED
3. `POST /api/emergency/dismiss/:id` → row set to `dismissed` → `broadcast({ type: 'ALARM_OFF', ... })`

Message `type` is the discriminator, matched by string in both `websocket_service.dart` and the ESP32 sketch. Adding a new type means updating both clients.

### Flutter state

`provider` with `ChangeNotifier`. Every provider is registered eagerly in the `MultiProvider` in `lib/main.dart` — a new provider must be added there or it will not resolve at runtime.

Providers follow a fixed shape: private `_items` / `_isLoading` / `_errorMessage`, public getters, and async methods that call the static `ApiService`, set state, and `notifyListeners()`. Mutations re-fetch the whole list rather than patching locally.

`ApiService` is fully static, holds the JWT in a static field mirrored to `SharedPreferences` under `auth_token`, and retries network failures twice with backoff on a 10s timeout. It never throws — connection failures come back as `{'success': false, 'message': ...}`.

`AuthGate` in `main.dart` is the router: it calls `tryAutoLogin()`, then sends every authenticated role to `MainDashboard`. Role-based visibility is handled inside `lib/widgets/sidebar_menu.dart`, not by routing.

### Client host configuration

`lib/core/constants/api_constants.dart` resolves the backend address in this order:

1. `--dart-define=API_BASE_URL` — a **complete origin**, for tunnels and deployed servers
2. `--dart-define=API_HOST` — host only, keeps the `http://<host>:3001` shape (LAN)
3. `localhost` on web, otherwise `_hostBawaan`

```bash
flutter run -d chrome                                                    # localhost
flutter run -d <android> --dart-define=API_HOST=192.168.1.10             # LAN
flutter run -d <android> --dart-define=API_BASE_URL=https://x.ngrok-free.app
```

**`API_BASE_URL` exists because host-only override cannot reach a tunnel.** `baseUrl` used to hardcode both `http://` and `:3001`, so an ngrok address became `http://x.ngrok-free.app:3001` — wrong scheme *and* a port that isn't there. The override is normalised: a trailing `/` or an accidentally pasted `/api` are both stripped.

**`wsUrl` derives its scheme from the origin** — `https` → `wss`, `http` → `ws`. Connecting to `ws://` from an HTTPS origin is refused, and the panic button would fail silently. `test/api_constants_test.dart` asserts the pairing, and is worth running under several `--dart-define` values since `String.fromEnvironment` is resolved at compile time:

```bash
flutter test --dart-define=API_BASE_URL=https://x.ngrok-free.app
```

`_hostBawaan` **will go stale** — a DHCP lease changes it. Treat `--dart-define` as the real answer, not the constant.

`ApiService` always sends `ngrok-skip-browser-warning: true`. ngrok's free tier otherwise returns an HTML interstitial to anything that looks like a browser, and every call fails while looking like a server problem. Other hosts ignore the header. `_handleResponse` additionally detects an HTML body and says so, rather than the unhelpful "response tidak valid".

### Testing from outside the LAN

A private `192.168.x.x` address is unreachable from anywhere but the same Wi-Fi, and the PC sits behind NAT. Two ways out:

- **Tunnel (ngrok, Cloudflare Tunnel)** — backend and PostgreSQL stay on the dev PC. Needed anyway for the **Midtrans webhook**, which requires a public URL. ngrok's free URL changes on every restart, so both `--dart-define` and the Midtrans notification URL must be updated each time.
- **Deploy** — a permanent URL and HTTPS, and the PC can be off. Remember the **database has to move too**: the backend in the cloud cannot reach PostgreSQL on the dev PC. Setup there is the same two commands (`init-db.js`, `seed-master.js`) against a managed Postgres.

### Testing on a physical Android device

Three things are required and each fails silently in its own way:

1. **`android/app/src/main/res/xml/network_security_config.xml`** with `cleartextTrafficPermitted="true"`, referenced from `<application android:networkSecurityConfig=…>`. `targetSdk` is 36 and Android has blocked cleartext HTTP since API 28 — without this every request to `http://…:3001` fails and the app merely looks disconnected. **This is a LAN-testing concession, not production-safe**; move the backend to HTTPS before shipping.
2. **`<uses-permission android:name="android.permission.INTERNET" />` in `src/main/AndroidManifest.xml`** — not only in `src/debug`. `flutter run` works either way because the debug manifest injects it, so a missing entry only surfaces in a release APK.
3. **A Windows Firewall inbound rule for port 3001.** The server binds `0.0.0.0`, but the firewall blocks LAN inbound by default. Run as administrator:
   ```powershell
   New-NetFirewallRule -DisplayName "Smart Community RT backend" -Direction Inbound -Protocol TCP -LocalPort 3001 -Action Allow -Profile Private
   ```
   Verify from the phone's browser at `http://<ip-pc>:3001/api/health` **before** debugging the Flutter app — it separates a network problem from an app problem.

**A `Stack` whose children are *all* `Positioned` cannot size itself** — it falls back to `constraints.biggest`, which is `Infinity` under any scroll view. `login_screen.dart`'s left panel hit exactly this: fine on desktop (height pinned by `Container(height: 580)`), fatal on a phone where it sits in a vertical `Flex` inside a `SingleChildScrollView`. The panel now leaves its content **non-positioned on mobile** so the content itself defines the height, and keeps `Positioned.fill` only on desktop. `Spacer` is likewise desktop-only, since it needs a bounded main axis.

`test/login_screen_test.dart` renders the login screen at five real device sizes and asserts `takeException()` is null, which catches both that assertion and any overflow. Run `flutter test` before trusting a layout change — `flutter analyze` cannot see layout errors at all.

### Design system

**`lib/core/theme/app_theme.dart` is the single source of colour, type, spacing, and radius.** It always contained a complete Material 3 theme; the screens simply never used it. The measurement that proved it: 1.065 hardcoded `Color(0x…)` literals across 96 distinct colours, `Theme.of(context)` referenced 7 times, `Card` used **zero** times against 231 hand-rolled `Container + BoxDecoration`, and `AppBar` used once in the whole app.

The clinching detail: `AppTheme.primaryColor` was `#1B5E20` (deep green) while every screen painted itself `#1B7A6A` (teal). **The theme's own primary colour was not the app's colour.** The token now follows the colour the app actually uses — never the reverse, or every screen would have shifted hue at once.

Consequences worth keeping in mind when adding UI:

- **Body text is 14sp (`bodyMedium`).** The app previously used 11–13px on 405 of ~580 sizes — web-dashboard density on a phone, and the main reason it read as cramped. `labelSmall` at 11sp is the floor; there is deliberately no step below it.
- **Three radii only** (`radiusS` 8 / `radiusM` 12 / `radiusL` 16). There used to be eleven. Values 20 and 24 survive on purpose for pill-shaped buttons — normalising those would change the button's shape, not tidy it.
- **Spacing is a 4dp grid** (`spasiXs`…`spasiXxl`), replacing 14 ad-hoc vertical gaps.
- **`sasaranSentuh` is 48dp**, applied through `iconButtonTheme` and every button's `minimumSize`. 216 icons sit below 24dp and many are tappable.
- **Cards are outlined, not shadowed.** This app stacks cards inside cards; layered shadows read as smudge.
- `darkTheme` is a real second theme. The old dark mode did `Theme.of(context).copyWith(brightness:)`, which does **not** rebuild the `ColorScheme` — so only the hardcoded colours changed and everything else stayed light.

### Dark mode: the theme belongs at the root, and only there

`MaterialApp` now carries `theme` + `darkTheme` + `themeMode`, driven by `TemaProvider` (persisted to `SharedPreferences` under `mode_gelap`, read in `main()` *before* `runApp` so the first frame is already correct).

Before that, `darkTheme` was never passed to `MaterialApp` at all. A `Theme()` wrapper sat around the scrolling content inside `MainDashboard`, which meant everything outside it stayed light no matter what: the AppBar, the drawer, the bottom navigation, the FAB, the whole Login screen, and **every dialog** — `showDialog` mounts on the root Navigator, so it reads the root theme, never a wrapper halfway down the tree. `_isDarkMode` was also plain `State`, so the choice was lost on every launch.

**Screens read colours from `context`, via the extension in `lib/core/theme/warna_konteks.dart`**: `teksUtama`, `teksKedua`, `teksTersier`, `garis`, `latarKartu`, `latarHalaman`, `latarLembut`. That extension deliberately holds no brand colours — teal, red, green, blue, and amber are correct in both modes and stay written out. Separating the two is what makes the neutral half safe to migrate mechanically.

The migration moved 457 neutral literals and 124 `Colors.grey*` to zero. **`Colors.white` was not touched wholesale, and must not be**: it means a card surface in some places and text-or-icon-on-brand-colour in others. Replacing the second kind yields dark text on teal — unreadable, and invisible to every test. `sidebar_menu.dart` is the clearest case: its background is brand teal, so all 22 of its whites are correct as-is and the file needed no changes at all.

Three places genuinely cannot use the extension and keep explicit colours on purpose: file-level `const` declarations, `static const` styles, and `CustomPainter` — none of them have a `context`. The chart painter receives an `isDarkMode` flag instead.

**Replacing a `const` colour with a theme lookup breaks `const` on the enclosing widget.** That is not a nuisance; `flutter analyze` flagging it is what guides the migration file by file.

`test/mode_gelap_test.dart` renders all fifteen screens plus `MainDashboard` in dark mode, and — more importantly — asserts `Theme.of(context).brightness`, `scaffoldBackgroundColor`, and `cardColor` actually match `AppTheme.darkTheme`. Rendering alone would pass even if `darkTheme` fell off `MaterialApp` again; that assertion is what makes the test worth having. `bungkusLayar()` and `bungkusDasbor()` in `bantuan_uji.dart` take a `gelap` flag, and `semuaProvider()` must include `TemaProvider` or the dashboard throws `ProviderNotFoundException`.

**What the tests still cannot see:** a label that kept a hardcoded colour renders fine and passes. Only eyes on a device catch that.

On the web side the same idea appears as `semburat()` in `src/core/theme.ts` — tints are 8–12% in light mode but 16–22% in dark, because a tint tuned for white is nearly invisible on `#0F172A`. `Statistik.tsx` likewise carries a second, lighter chart palette for dark mode.

### Android shell

`MainDashboard` is the only `Scaffold`; every module is a plain widget rendered inside it. On mobile it now supplies:

- **A real `AppBar`** whose title comes from `judulMenu(index)` in `lib/widgets/navigasi_bawah.dart`. It shows the *current* menu — the old header bar said "Dashboard" on every screen. On any screen but Beranda the leading icon is a back arrow to Beranda, not a hamburger.
- **`NavigationBar`** with four role-appropriate destinations plus "Lainnya", which opens the drawer. Destinations are filtered through `PermissionProvider`, not role names — otherwise revoking a module in Menu & Akses would leave a bottom-bar button that 403s. The indices are the *same* menu indices the sidebar and `_buildBody` use, so there is no second menu registry to maintain. When a drawer-only screen is open, "Lainnya" is the highlighted destination.
- **`FloatingActionButton`** driven by `AksiUtamaProvider`. Screens cannot host their own FAB because they are not `Scaffold`s, so each registers its primary action from `build` and the shell draws it. **All menu changes must go through `_pilihMenu`**, which calls `lepas()` first — otherwise a screen with no primary action inherits the previous screen's FAB.
- **`RefreshIndicator`** with `AlwaysScrollableScrollPhysics`, without which the pull gesture is not detected on short pages.

**Nine screens' internal titles are hidden on mobile** (`if (!pakaiKartu(context))`). Once the AppBar names the screen, the in-screen icon + title + breadcrumb block is duplicate chrome costing ~90px at the top of every page. It stays on wide screens, where there is no AppBar.

### Responsive sizing

**`lib/core/responsif.dart` is the single source of size rules** — `paddingKonten`, `paddingKartu`, `lebarDialog`, `lebarKolomFilter`, `pakaiKartu`. It piggybacks on the thresholds already in `ResponsiveLayout` rather than inventing new ones; two sets of breakpoints would make the sidebar and its contents change shape at different widths.

- **`lebarDialog(context, maksimal: N)`** replaced 25 hardcoded `SizedBox(width: 400…600)` inside `AlertDialog`. A fixed width there does not shrink on a narrow screen; the dialog overflows and its fields get squeezed.
- **`lebarKolomFilter`** returns `double.infinity` on mobile so filter and search boxes fill one row each. It is **only safe inside `Wrap` or `Column`** — inside a `Row`, infinite width throws; use `Expanded` there instead.

**`lib/widgets/tabel_responsif.dart` renders a `DataTable` on wide screens and stacked cards on phones**, from one `BarisTabel`/`SelTabel` list. Twelve of the thirteen tables use it. `SelTabel.label` doubles as the column heading and the per-field label on the card, so the two forms cannot drift apart. `sembunyiDiKartu` drops table-only columns (row numbers); `utama` promotes one cell to the card headline. `judulKolom` exists solely for Iuran Warga's "select all" checkbox heading — a checkbox cannot serve as a card label, so `kolom` must still carry text for that column.

**Never put a fixed `maxHeight` around `TabelResponsif`.** `data_warga_screen.dart` capped it at 560 — "keeps layout fixed for 10 items exactly", which is true for a `DataTable` at ~50px per row. In card mode each row is ~250px, so three residents overflowed by 486px and painted over the pagination. Any height that is right for one form is wrong for the other; on mobile the page already scrolls, so let the list be as tall as its contents.

**That bug is also the clearest example of what the widget tests cannot see.** Providers hold no data during tests, so `TabelResponsif` renders its empty state and stays short — the cap never binds. Layout defects that only appear *with rows in them* still need a real device or a screenshot. `test/tabel_responsif_test.dart` covers the widget itself with long text, but not a screen that constrains it.

**Filter chips and tabs scroll horizontally on mobile, they do not wrap.** A `Wrap` sizes each chip to its own label, so the right edge is always ragged and 4 tabs sharing `Expanded` width squeeze "Pengumuman" into "Pengumuma n". `menu_akses_screen.dart` and `agenda_kegiatan_screen.dart` both use a horizontal `SingleChildScrollView` on narrow screens and keep the even split on wide ones.

**A `SizedBox` between `Wrap` children is a bug, not a spacer.** `Wrap` already spaces via `spacing:`; an extra `SizedBox` becomes a *child*, so it gets its own slot and the gaps come out uneven. This was making the E-Visitor filter card look misaligned.

**Menu & Akses deliberately keeps its horizontal-scroll table.** It is a permission matrix — six roles × four checkboxes per menu — and one card per menu would be six times taller while reading worse. A matrix is genuinely a matrix.

**Two `Row` habits caused nearly every overflow found, and both are easy to reintroduce:**

1. **`Expanded` and `Spacer` in the same `Row`.** Both default to flex 1, so the leftover space is split evenly. In `main_dashboard._buildHeaderBar` that left roughly 29px for the title on a 360px phone. `Expanded` alone already pushes the trailing widgets to the edge.
2. **A screen header as `Row(mainAxisAlignment: spaceBetween)`.** A `Row` forces one line. These are now `SizedBox(width: double.infinity, child: Wrap(alignment: WrapAlignment.spaceBetween, …))`. **The `SizedBox` is load-bearing**: without a definite width a `Wrap` shrinks to its contents, leaving `spaceBetween` no slack to distribute, and the buttons would sit against the title on desktop. Direct `Row` children of a `Wrap` also need `mainAxisSize: MainAxisSize.min`, and their text `Column` needs `Flexible` — `min` only sizes the Row, not its children.

**The 1-second clock timer only runs on desktop.** `MainDashboard` used to `setState` every second to refresh the header clock, rebuilding the *entire* dashboard — chart recomputation and canvas repaint included — once per second. The clock is no longer shown on mobile, so on a phone that was a full render per second for nothing, and the app felt frozen as soon as you navigated. `_timer` is nullable and only started when `ResponsiveLayout.isDesktop`.

**`SafeArea` was absent from the whole app.** The drawer sits flush against the top edge, so on notched or hole-punch phones the "AUTO RT" logo was covered. `SidebarMenu` now wraps its content in `SafeArea(bottom: false)` — `bottom: false` because the menu list already scrolls and reserving space there just truncates it sooner.

### Developing on Chrome is fine — the tests must cover what Chrome hides

This app was built and tested almost entirely in Chrome, then looked broken everywhere the first time it ran on an Android phone. Chrome is not a bad dev target; it simply cannot show four things, and every one of them produced a real bug here:

| Chrome cannot show | What it caused |
|---|---|
| Camera notch / status bar | The drawer's "AUTO RT" logo sat under the cutout |
| Gesture bar | Bottom controls overlapped |
| System font scaling | Fixed-height boxes clipped their own contents |
| 48dp finger target | 28 controls were 32–44dp and easy to miss |

`test/bantuan_uji.dart` defines `kondisiUji` — the screen sizes **plus** two conditions that stand in for a real phone: `poniAtas`/`gesturBawah` (applied via `tester.view.padding`, which is what `SafeArea` reads) and `skalaFont: 1.3`, Android's common "Large" setting, applied through `MaterialApp.builder` so it reaches dialogs too. Use `pasangKondisi(tester, k)` rather than setting `physicalSize` by hand — setting only the size is exactly what let these bugs through.

**2.0× font scaling is deliberately out of scope.** Full accessibility scaling needs a different layout approach; 1.3× is the setting people actually use.

**Interactive boxes take a minimum height, never a fixed one.** `Container(height: 40)` fails twice on a phone: below the touch target, and it clips when text scales. Use `constraints: BoxConstraints(minHeight: AppTheme.sasaranSentuh)`. Text fields need nothing — `inputDecorationTheme` carries that constraint, so every `TextField` inherits it.

Only one thing still needs a physical device: `webview_flutter` has no web implementation, so the embedded Midtrans page falls back to `url_launcher` in a browser tab.

**Rendering tests are blind to interaction bugs — `test/interaksi_dashboard_test.dart` exists because of one.** A regex-driven refactor that routed every menu change through `_pilihMenu` also rewrote the body of `_pilihMenu` itself, leaving `_pilihMenu(indeks)` calling `_pilihMenu(indeks)`. Every menu tap then threw `StackOverflowError` after ~128k frames and the app froze. `flutter analyze` cannot see unbounded recursion — it is valid Dart — and all 101 tests at the time only *rendered* screens, never tapped anything, so the whole suite passed. The interaction test taps the AppBar profile button, the back arrow, and a drawer entry; it failed with `StackOverflowError` before the fix, which is what makes it worth keeping. It immediately found a second bug too: `profil_saya_screen.dart` overflowed, because that screen had never been in any test's screen list.

**Any regex-based bulk edit must be checked against the definition of whatever it rewrites calls into.** The `_pilihMenu` damage came from a pattern that matched its own target's body. `scratchpad/cari-rekursi.js`-style sweeps help, but they produce false positives (a method calling a *sibling* helper looks identical), so read every hit.

**`test/bantuan_uji.dart` holds the shared widget-test scaffolding** — `semuaProvider()`, `bungkusLayar()`, `bungkusDasbor()`, and `WsTanpaSambung`. Use it rather than re-declaring providers per test file.

**`test/mobile_layout_test.dart` renders thirteen screens *plus MainDashboard* at 320/360/412/800/1440 and asserts `takeException()` is null.** The dashboard was added after the chart and the Progress Iuran / Status Darurat pair were found overflowing on a real device: both live in `MainDashboard`, which no test had ever rendered — every test touched only the module screens. It needs its own wrapper (it brings its own `Scaffold`) and a `WebSocketService` stub, because the real one schedules a 5-second reconnect timer *after* the frame and the test then fails on "Pending timers" instead of on layout.

The chart's month labels were `'MMM yyyy'` — "Agu 2026", six of them across ~222px. On mobile it now shows four months labelled `'MMM'`, and each label sits in an `Expanded` so an over-wide label ellipsizes instead of shoving its neighbours off the edge.

**`test/login_screen_test.dart` asserts `maxScrollExtent == 0` on three phone widths.** The login screen must fit one screen; stacking the desktop marketing panel above the form made it taller than the display, so users scrolled just to reach the Masuk button. Mobile now gets a compact header instead, and the form drops its duplicate "Selamat Datang" heading. `ConstrainedBox(minHeight:) + IntrinsicHeight` inside a `SingleChildScrollView` is what keeps it exactly one screen tall while still scrolling when the keyboard shrinks the viewport. It found 39 real overflows on its first run. Providers are empty (no backend during tests), so it catches *structural* defects — headers, filters, toolbars, pagination — not ones that only appear with long data; `test/tabel_responsif_test.dart` covers that half with deliberately long text. Note the test font is Ahem, where every glyph is a square of the font size, so text measures wider there than on a device — a 2px failure in the test is not necessarily visible in production, but the fix (`Flexible` + ellipsis) is correct either way.

### Demo data

`node seed-demo.js` creates one kartu keluarga with three members, links `warga@example.com` to it via `no_kk`, and issues three unpaid bills — enough to exercise the payment flow immediately. Idempotent, and deliberately **separate from `seed-master.js`** so fabricated data never ships with a real install. Remove it with `kosongkan-data.js` or the Reset Sistem screen.

The `no_kk` link is the load-bearing part: `bills` are filtered by `keluarga.no_kk = users.no_kk`, so an account without it sees an empty list even when bills exist.

A parameter used twice in one `INSERT` makes Postgres fail with *"inconsistent types deduced"* unless it is explicitly cast — existing queries do this correctly (`$3::int`, `$2::uuid`); when in doubt compute the value in JS instead.

### Default accounts

`seed-master.js` creates `admin@example.com` / `admin123` and `warga@example.com` / `warga123`. Both are testing credentials — change them before any real use. Login matches `email = $1 OR username = $1`, so either field works.

The seeded warga has **no `no_kk`**, so Tagihan Saya renders empty — correct behaviour, since bills are filtered through the resident's kartu keluarga. Real warga accounts are created by Data Warga using the NIK as both username and email, with password `123456`.

## `frontend-web/` — the React client

A second client, sharing the same backend. **The backend is untouched by it** — 84 routes, the four Midtrans money guards, and the permission matrix all apply unchanged, because the Flutter client was already a thin layer over a standalone REST API. Porting was a UI rewrite, not a system rewrite: 27.516 lines of Dart became ~10.500 lines of TypeScript.

```bash
cd frontend-web
npm run dev          # http://localhost:5173
npm run build        # dist/
npx tsc --noEmit -p tsconfig.app.json    # typecheck — there is no npm script
npx oxlint src       # lint (oxlint, not eslint — Vite 8's default)
```

Stack: React 19 + TypeScript + Vite 8, MUI 9, React Router 7, TanStack Query 5, Recharts.

**Configure the backend address with `VITE_` env vars, not `--dart-define`** — `VITE_API_BASE_URL` (full origin, for tunnels) or `VITE_API_HOST` (host only, keeps `http://<host>:3001`), resolved in `src/core/apiConstants.ts` in the same order as the Flutter client. `wsUrl` derives its scheme the same way: https → wss.

### What was ported deliberately, not incidentally

`src/core/apiClient.ts` mirrors `ApiService` including the parts that look redundant: it never throws, injects `statusCode` from the HTTP response, and adds `penandaOffline` **only** on the connection-failure path. `AuthContext` logs out on 401/403 alone and validates the token in the background without blocking first paint. Both exist because of real bugs — see the Flutter sections above.

**Postgres sends NUMERIC as a string.** `jumlah` arrives as `"50000"`. In Dart that was a type error; in JavaScript it silently produces `"50000" + 500 === "50000500"`. Every money field goes through `keAngka()` in `src/types/index.ts`. Likewise **never format a date with `toISOString()`** — a `DATE` column arrives as `2026-07-31T17:00:00.000Z`, which is 1 August in WIB; `src/core/format.ts` builds send-strings from local components instead.

`retry: false` on the TanStack Query client is deliberate: `apiClient` already retries twice, and letting Query retry on top compounds it to nine attempts.

### Navigation is URL-based, not index-based

`src/core/menu.ts` maps each permission `kode` to a path (`keuangan.iuran` → `/keuangan/iuran`). The `menu_index` numbers are kept as cross-reference only. Bookmarkable URLs and a working Back button are what web users expect, and an integer index cannot provide either.

**The three role-branching modules use one screen each, not two.** In Flutter, `main_dashboard._buildBody` picks `IuranWargaScreen` vs `BillListScreen` by role. Here the branch is inside the screen and keyed on *permission*: warga holds `view` on `keuangan.kas` so no mutating buttons render at all, and `BannerLihatSaja` appears by itself. That removes a second screen registry, and closes the old trap where granting warga a module in Menu & Akses produced nothing because the screen was gated on a role name.

### Downloads must go through `fetch`, never through a link

**A browser navigation cannot carry a header.** `<a href>`, `window.open`, and Flutter's `url_launcher` all navigate — so none of them can send `ngrok-skip-browser-warning`, and behind a tunnel every Export button opened ngrok's interstitial page instead of downloading the file. The symptom is maximally misleading: every other feature works (they go through `fetch`, which *can* set the header), so it reads as "the backend died" while the backend was never contacted.

`unduhBerkas()` in `src/core/apiClient.ts` fetches the file as a Blob and triggers the download from an object URL. `TombolEkspor` wraps it. Three consequences worth keeping:

- The token no longer travels in the query string, where it lands in server logs and browser history.
- A 403 surfaces as a readable message instead of a silently corrupt file.
- A 200 response whose `Content-Type` is `text/html` is caught explicitly — that is exactly what the ngrok interstitial looks like, and without the check the "file" downloads fine and only fails when opened in Excel.

**The Flutter client still uses `url_launcher` for exports**, so it remains subject to this. The workaround there is to open the ngrok address once in the phone's browser and press "Visit Site"; a proper fix would download in-app.

`GET /reset/cadangan` **requires a `grup` query parameter** — the backup is per reset group, not whole-database. Omitting it returns 400 `"Kelompok reset tidak dikenal"`, which is dangerous precisely here: the user believes they have a backup right before deleting data. Group codes are the real ones from `/reset/ringkasan` (`keuangan.iuran`, `kependudukan`, `total`, …), not the short names.

### CORS: `ngrok-skip-browser-warning` had to be allowed

Every browser client sends that header on every request. It is not a simple header, so the browser preflights it — and `Access-Control-Allow-Headers` never listed it, so the preflight failed and **the request was blocked before it was ever sent**. The symptom is misleading: the app looks like the server is down, while the server was never contacted. `HEADER_DIIZINKAN` in `src/index.js` now includes it. This affected Flutter Web too, not only the React client.

### What is not covered

There are no automated tests here yet — the Flutter suite (133 tests) does not transfer, and `tsc` plus `oxlint` catch neither layout defects nor interaction bugs. That is the same blind spot that let the Flutter layout bugs through; a `@testing-library/react` suite over the same device widths is the equivalent worth adding.

## Code graph (codebase-memory-mcp)

The repo is indexed into a queryable code graph by the `codebase-memory-mcp` server (registered globally, so nothing in this repo configures it). **Both halves are covered** — the indexer handles Dart as well as JavaScript, which is not the usual case for graph indexers and was verified rather than assumed: 87 JS files / 86 Dart files, `frontend-flutter` 804 nodes against `backend-node` 243, 2255 nodes and 5934 edges in total, 84 routes. `.git`, `node_modules`, `build`, and `.dart_tool` are excluded.

Ten read-only tools are pre-approved in `.claude/settings.json`. `index_repository`, `delete_project`, `manage_adr`, and `ingest_traces` are deliberately **left out** — they write, so they still ask first.

Reach for the graph where it beats a text search, and only there:

| Question | Use |
|---|---|
| Where does this function / class / route live? | `search_graph` — not `Grep` |
| Who calls this before I change it? | `trace_path` |
| Getting oriented in an unfamiliar module | `get_architecture` |
| Free text — a comment, a UI string, an error message | still `Grep`; the graph indexes structure, not prose |

**A stale graph is more dangerous than no graph**, because it answers confidently. Auto-index is on (`config set auto_index true`), which costs roughly 2 GB of the machine's 8 GB plus a file watcher; if the laptop starts to drag, turn it off and re-index by hand after any large change — `detect_changes` reports what has drifted. Never conclude that something *doesn't* exist from a graph miss alone; confirm with `Grep` before acting on an absence.

The graph does not replace this file. `CLAUDE.md` records **why** — why `is_pending` exists, why a fixed `maxHeight` is forbidden. The graph records **where, and connected to what**.

## Project rules

`.antigravity/rules/nodejs_backend_resilience.md` is a standing rule for this repo. Two requirements when touching backend server setup:

1. **Graceful shutdown is mandatory.** Any `server.listen` must keep the `SIGINT` / `SIGTERM` / `uncaughtException` handlers that call `server.close()` with a 5s forced-exit fallback. This prevents `EADDRINUSE` from zombie Node processes on Windows.
2. **CORS and Private Network Access headers are explicit.** `src/index.js` handles `OPTIONS *` before any other middleware and sets `Access-Control-Allow-Private-Network: true` on every response. Do not replace this with a bare `app.use(cors())` — Chrome's PNA rules will block Flutter Web against a localhost backend.
