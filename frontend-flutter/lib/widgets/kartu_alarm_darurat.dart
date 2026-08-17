import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/pesan.dart';
import '../core/responsif.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';
import '../providers/emergency_provider.dart';

/// Panel kendali darurat, dipakai dasbor SEMUA peran.
///
/// ===================================================================
/// Kenapa satu widget untuk semua peran
/// ===================================================================
///
/// Warga dan pengurus memakai dasbor yang berbeda (`WargaDashboardContent` dan
/// `_buildDashboardContent`), tetapi panel daruratnya harus persis sama —
/// tampilannya, PIN-nya, dan perilakunya. Menyalinnya ke dua tempat berarti
/// suatu hari yang satu diperbaiki dan yang lain tidak, dan yang tertinggal
/// justru baru ketahuan saat keadaan darurat.
///
/// ===================================================================
/// Bahasa visualnya mengikuti kartu dasbor yang sudah ada
/// ===================================================================
///
/// Kartu di dasbor ini **outlined, bukan shadowed** — `latarKartu` + garis
/// tipis + radius 16 — dan panel ini memakai kerangka yang sama supaya tidak
/// terasa ditempel dari aplikasi lain. Yang membedakannya bukan bentuk
/// melainkan **warna dan bobot**: aksen merah bahaya, ikon di kotak bertint,
/// dan status yang menonjol.
///
/// Peringatan dibuat tegas tetapi tidak berteriak. Kartu yang selalu menyala
/// merah menyilaukan akan diabaikan dalam sepekan, dan tepat pada hari ia
/// benar-benar penting, mata sudah terbiasa melewatinya.
///
/// ===================================================================
/// Yang TIDAK dilakukan widget ini
/// ===================================================================
///
/// Ia tidak memverifikasi PIN. PIN dikirim apa adanya ke backend dan diperiksa
/// di sana. Memeriksanya di sini hanya menyaring salah ketik — siapa pun bisa
/// memanggil endpoint langsung dan melewatinya.
///
/// Ia juga tidak pernah menyentuh broker MQTT maupun kredensialnya. Aplikasi
/// memanggil endpoint HTTP biasa; server yang menerbitkan perintahnya.
class KartuAlarmDarurat extends StatefulWidget {
  const KartuAlarmDarurat({super.key});

  @override
  State<KartuAlarmDarurat> createState() => _KartuAlarmDaruratState();
}

class _KartuAlarmDaruratState extends State<KartuAlarmDarurat>
    with WidgetsBindingObserver {
  /// ===================================================================
  /// Kenapa kartu ini memuat keadaannya sendiri
  /// ===================================================================
  ///
  /// Sebelumnya `muatStatusAlarm()` TIDAK PERNAH dipanggil satu layar pun —
  /// satu-satunya pemanggilnya adalah `kendaliAlarm` sesudah tombol ditekan.
  /// Akibatnya kartu ini selalu lahir dalam keadaan SIAGA:
  ///
  ///   - membuka ulang aplikasi saat darurat masih menyala → tampak SIAGA
  ///   - darurat yang dinyalakan orang lain → tidak pernah terlihat
  ///
  /// Keduanya adalah keadaan salah pada layar yang paling tidak boleh salah,
  /// dan keduanya diam — tidak ada galat yang muncul.
  ///
  /// Pemuatannya diletakkan di kartu, bukan di kedua dasbor, karena kartu ini
  /// dipakai dasbor pengurus DAN dasbor warga. Menaruhnya di layar berarti
  /// suatu hari yang satu ingat memanggil dan yang lain lupa.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Setelah frame pertama: `muatStatusAlarm` memanggil notifyListeners, dan
    // memanggilnya selama build akan melempar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<EmergencyProvider>().muatStatusAlarm();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Membaca ulang keadaan saat aplikasi kembali aktif.
  ///
  /// Tanpa ini, ponsel yang dikunci sepuluh menit lalu dibuka lagi menampilkan
  /// keadaan sepuluh menit lalu — dan darurat bisa saja sudah diselesaikan
  /// orang lain dari perangkat lain. Hanya `resumed` yang memicu; tidak ada
  /// timer dan tidak ada polling berkala.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<EmergencyProvider>().muatStatusAlarm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final darurat = context.watch<EmergencyProvider>();
    final menyala = darurat.alarmMenyala;
    final sibuk = darurat.mengirimAlarm;
    final bolehMatikan = darurat.bolehMatikan;
    final milikOrangLain = darurat.daruratMilikOrangLain;
    final pengaktif = darurat.namaPengaktif;
    final rapat = !pakaiKartu(context);

    return AnimatedContainer(
      // Perpindahan warna dibuat halus, bukan berkedip. Animasi berdurasi
      // terbatas — BUKAN yang berulang tanpa henti — karena animasi abadi
      // meninggalkan timer aktif dan membuat widget test gagal pada "pending
      // timers" alih-alih pada hal yang sedang diuji.
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: EdgeInsets.all(rapat ? AppTheme.spasiL : AppTheme.spasiXl),
      decoration: BoxDecoration(
        color: menyala
            ? AppTheme.dangerColor.withValues(alpha: 0.06)
            : context.latarKartu,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(
          color: menyala ? AppTheme.dangerColor : context.garis,
          width: menyala ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kepala(context, menyala: menyala, rapat: rapat),
          SizedBox(height: rapat ? AppTheme.spasiM : AppTheme.spasiL),
          Divider(height: 1, thickness: 1, color: context.garis),
          SizedBox(height: rapat ? AppTheme.spasiM : AppTheme.spasiL),
          _peringatan(context,
              menyala: menyala,
              milikOrangLain: milikOrangLain,
              bolehMatikan: bolehMatikan,
              pengaktif: pengaktif),
          // Detail kejadian hanya muncul ketika ada yang bisa diceritakan.
          // Blok kosong berlabel "Keterangan" pada kartu siaga hanya menambah
          // kebisingan pada layar yang harus terbaca dalam sekali pandang.
          if (menyala && darurat.keteranganKejadian.isNotEmpty) ...[
            SizedBox(height: rapat ? AppTheme.spasiM : AppTheme.spasiL),
            _detailKejadian(
              context,
              pengaktif: pengaktif,
              keterangan: darurat.keteranganKejadianTampil,
              legacy: darurat.kejadianTanpaKeteranganLegacy,
              waktu: darurat.waktuKejadian,
            ),
          ],
          SizedBox(height: rapat ? AppTheme.spasiM : AppTheme.spasiL),
          _aksi(context, menyala: menyala, sibuk: sibuk, bolehMatikan: bolehMatikan),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────── kepala
  //
  // Hierarki: ikon → judul → deskripsi di kiri, lencana status di kanan.
  // Judul dan status adalah dua hal yang paling dicari mata, jadi keduanya
  // diletakkan pada satu baris pandang.
  Widget _kepala(BuildContext context, {required bool menyala, required bool rapat}) {
    final judul = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Kendali Darurat',
          style: TextStyle(
            fontSize: rapat ? 16 : 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: context.teksUtama,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Sirene lingkungan RT',
          style: TextStyle(fontSize: 13, color: context.teksKedua),
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ikon dalam kotak bertint — pola yang sudah dipakai kartu lain di
        // dasbor, jadi panel ini terbaca sebagai bagian dari keluarga yang sama.
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.dangerColor.withValues(alpha: menyala ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          child: Icon(
            menyala ? Icons.notifications_active_rounded : Icons.campaign_rounded,
            color: AppTheme.dangerColor,
            size: 24,
          ),
        ),
        const SizedBox(width: AppTheme.spasiM),
        Expanded(child: judul),
        const SizedBox(width: AppTheme.spasiS),
        _lencanaStatus(context, menyala: menyala),
      ],
    );
  }

  // ─────────────────────────────────────────────────────── lencana status
  //
  // Titik + teks, bukan hanya warna. Sekitar satu dari dua belas laki-laki
  // kesulitan membedakan merah dari hijau, dan status alarm bukan tempat untuk
  // mengandalkan warna sendirian.
  Widget _lencanaStatus(BuildContext context, {required bool menyala}) {
    final warna = menyala ? AppTheme.dangerColor : AppTheme.successColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: warna.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: warna, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            menyala ? 'AKTIF' : 'SIAGA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────── peringatan
  Widget _peringatan(BuildContext context, {
    required bool menyala,
    required bool milikOrangLain,
    required bool bolehMatikan,
    required String pengaktif,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          menyala ? Icons.volume_up_rounded : Icons.info_outline_rounded,
          size: 16,
          color: menyala ? AppTheme.dangerColor : context.teksTersier,
        ),
        const SizedBox(width: AppTheme.spasiS),
        Expanded(
          child: Text(
            menyala
                // Kalimatnya sengaja tidak berbunyi "alat berbunyi". Aplikasi
                // hanya tahu perintahnya terkirim; alat tidak melapor balik ke
                // sini. Mengaku tahu lebih banyak daripada yang sebenarnya
                // diketahui membuat orang berhenti memeriksa alatnya sendiri.
                ? (milikOrangLain
                    ? 'Darurat ini dinyalakan oleh $pengaktif. '
                      '${bolehMatikan ? "Anda berwenang mematikannya bila keadaan sudah aman." : "Hanya pemiliknya atau Pengurus RT yang boleh mematikannya — hubungi Pengurus bila perlu."}'
                    : 'Perintah menyalakan sirene sudah dikirim. Tekan MATIKAN bila keadaan sudah aman.')
                : 'Menyalakan sirene di lingkungan RT. Gunakan hanya untuk keadaan darurat sungguhan — setiap penekanan tercatat beserta nama Anda.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: menyala ? context.teksUtama : context.teksKedua,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────── detail kejadian
  //
  // Siapa, apa, dan kapan — tiga hal yang ditanyakan orang begitu sirene
  // berbunyi, ditampilkan tanpa harus membuka layar lain.
  //
  // Keterangannya TIDAK dipotong di sini. Kartu ini adalah tempat orang
  // membaca apa yang sebenarnya terjadi, dan memotongnya menjadi satu baris
  // bisa menghilangkan justru bagian yang menentukan tindakan — "kebakaran di
  // dapur, **api sudah padam**" berubah maknanya sepenuhnya bila terpotong.
  Widget _detailKejadian(
    BuildContext context, {
    required String pengaktif,
    required String keterangan,
    bool legacy = false,
    DateTime? waktu,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spasiM),
      decoration: BoxDecoration(
        color: AppTheme.dangerColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wrap, bukan Row: pada layar sempit nama panjang dan jam tidak
          // saling mendorong keluar batas, keduanya turun baris dengan rapi.
          Wrap(
            spacing: AppTheme.spasiS,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: context.teksKedua),
                  const SizedBox(width: 4),
                  Text(
                    'Aktif oleh $pengaktif',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.teksUtama,
                    ),
                  ),
                ],
              ),
              if (waktu != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: context.teksTersier),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd MMM yyyy, HH:mm').format(waktu),
                      style: TextStyle(fontSize: 12, color: context.teksKedua),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spasiS),
          Text(
            keterangan,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              // Dimiringkan bila legacy: ia keterangan TENTANG kejadian, bukan
              // kalimat yang benar-benar diketik pelapor.
              color: legacy ? context.teksKedua : context.teksUtama,
              fontStyle: legacy ? FontStyle.italic : null,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────── aksi
  //
  // Kedua tombol berbagi lebar sama rata — keduanya penting, dan menyempitkan
  // salah satunya membuatnya sulit ditekan justru saat tangan gemetar.
  //
  // Yang berbeda adalah BOBOTNYA, dan bobot itu BERPINDAH mengikuti keadaan:
  //
  //   siaga  -> NYALAKAN terisi penuh (aksi utama), MATIKAN bergaris saja
  //   aktif  -> MATIKAN terisi penuh (aksi utama), NYALAKAN dinonaktifkan
  //
  // Alasannya sederhana: ketika sirene sedang meraung, satu-satunya hal yang
  // ingin dilakukan orang adalah menghentikannya. Tombol utama harus tombol
  // yang sedang dibutuhkan, bukan tombol yang sama sepanjang waktu.
  Widget _aksi(BuildContext context, {
    required bool menyala,
    required bool sibuk,
    required bool bolehMatikan,
  }) {
    final nyalakan = _TombolAksi(
      label: 'NYALAKAN',
      ikon: Icons.campaign_rounded,
      warna: AppTheme.dangerColor,
      utama: !menyala,
      // Dikunci saat sedang mengirim DAN saat sudah menyala. Menekan NYALAKAN
      // dua kali tidak menambah apa pun selain baris ganda di audit log.
      aktif: !sibuk && !menyala,
      sibuk: sibuk && !menyala,
      onTap: () => _mintaPin(context, 'ON'),
    );

    // MATIKAN DIHILANGKAN, bukan sekadar dinonaktifkan, ketika ada kejadian
    // aktif milik orang lain dan pengguna ini tidak berwenang menutupnya.
    //
    // Tombol mati yang tetap terlihat mengundang orang menekannya berulang
    // kali dalam keadaan darurat lalu menyimpulkan aplikasinya rusak. Yang
    // dibutuhkan bukan tombol, melainkan kalimat yang menyebut siapa
    // pemiliknya — dan itu sudah ada di blok peringatan.
    //
    // Saat TIDAK ada kejadian aktif, tombolnya tetap ada dengan sengaja:
    // aplikasi bisa saja tertinggal keadaan (dibuka ulang, atau alarm
    // dinyalakan dari perangkat lain), dan buzzer yang tidak bisa dihentikan
    // lebih buruk daripada satu perintah OFF yang berlebih.
    //
    // Ini semata soal tampilan. Endpoint OFF tetap menolak 403 bila yang
    // menekan bukan pemilik dan bukan pengurus.
    final tampilkanMatikan = !menyala || bolehMatikan;

    final matikan = _TombolAksi(
      label: 'MATIKAN',
      ikon: Icons.notifications_off_rounded,
      warna: menyala ? AppTheme.dangerColor : context.teksKedua,
      utama: menyala,
      // MATIKAN sengaja SELALU tersedia selama tidak sedang mengirim —
      // termasuk ketika aplikasi mengira alarm sudah mati. Aplikasi bisa saja
      // salah (dibuka ulang, atau dinyalakan dari perangkat lain), dan buzzer
      // yang tidak bisa dihentikan jauh lebih buruk daripada perintah OFF
      // yang berlebih.
      // Izin datang dari BACKEND (`boleh_matikan` di /alarm/status), bukan dari
      // peran yang ditebak klien.
      aktif: !sibuk,
      sibuk: sibuk && menyala,
      onTap: () => _mintaPin(context, 'OFF'),
    );

    // Tanpa MATIKAN, NYALAKAN berdiri sendiri selebar kartu — bukan setengah
    // baris dengan ruang kosong di sebelahnya yang terbaca seperti tombol yang
    // gagal dimuat.
    if (!tampilkanMatikan) {
      return SizedBox(width: double.infinity, child: nyalakan);
    }

    // Di bawah ~360 px dua tombol berdampingan memaksa labelnya terpotong.
    // Ditumpuk, keduanya tetap selebar layar dan tetap mudah ditekan.
    return LayoutBuilder(
      builder: (ctx, batas) {
        if (batas.maxWidth < 360) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: nyalakan),
              const SizedBox(height: AppTheme.spasiS),
              SizedBox(width: double.infinity, child: matikan),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: nyalakan),
            const SizedBox(width: AppTheme.spasiM),
            Expanded(child: matikan),
          ],
        );
      },
    );
  }

  /// Dialog konfirmasi + PIN, dan — khusus ON — keterangan kejadian.
  ///
  /// Satu dialog untuk ON dan OFF supaya keduanya tidak bisa berbeda perilaku;
  /// yang berbeda hanya kalimatnya dan ada-tidaknya kolom keterangan.
  ///
  /// Keterangan divalidasi di sini HANYA supaya pemakai tahu lebih awal.
  /// Aturannya yang sesungguhnya ada di backend, yang memvalidasi ulang setiap
  /// permintaan — klien yang dimodifikasi tetap dijawab 400.
  Future<void> _mintaPin(BuildContext context, String aksi) async {
    final nyala = aksi == 'ON';
    final kontrolPin = TextEditingController();
    final kontrolKeterangan = TextEditingController();
    final darurat = context.read<EmergencyProvider>();

    /// Mengembalikan pesan galat, atau null bila sah. Aturannya cermin dari
    /// `validasiKeterangan` di backend.
    String? periksaKeterangan(String v) {
      final t = v.trim();
      if (t.isEmpty) return 'Keterangan kejadian wajib diisi';
      if (t.length < EmergencyProvider.keteranganMin) {
        return 'Terlalu pendek — minimal ${EmergencyProvider.keteranganMin} karakter';
      }
      if (t.length > EmergencyProvider.keteranganMaks) {
        return 'Terlalu panjang — maksimal ${EmergencyProvider.keteranganMaks} karakter';
      }
      return null;
    }

    final hasil = await showDialog<_HasilDialogAlarm>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? galatLokal;
        String? galatKeterangan;

        /// Satu jalur pengiriman untuk tombol maupun tombol Enter.
        ///
        /// Dua salinan aturan validasi adalah cara termudah agar Enter suatu
        /// hari melewati pemeriksaan yang masih dijalankan tombolnya.
        void kirim(StateSetter setLokal, BuildContext ctx) {
          final ket = kontrolKeterangan.text;
          final pin = kontrolPin.text.trim();

          final galatKet = nyala ? periksaKeterangan(ket) : null;
          final galatPin = pin.isEmpty ? 'PIN wajib diisi' : null;

          // Keduanya diperiksa dan ditampilkan SEKALIGUS. Menampilkan satu
          // galat pada satu waktu memaksa orang menekan tombol berkali-kali
          // untuk menemukan semua yang kurang — di tengah keadaan darurat.
          if (galatKet != null || galatPin != null) {
            setLokal(() {
              galatKeterangan = galatKet;
              galatLokal = galatPin;
            });
            return;
          }

          Navigator.pop(
            ctx,
            _HasilDialogAlarm(pin: pin, keterangan: ket.trim()),
          );
        }

        return StatefulBuilder(
          builder: (ctx, setLokal) => AlertDialog(
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusS),
                  ),
                  child: Icon(
                    nyala ? Icons.campaign_rounded : Icons.notifications_off_rounded,
                    color: nyala ? AppTheme.dangerColor : ctx.teksKedua,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppTheme.spasiM),
                Expanded(
                  child: Text(
                    nyala ? 'Nyalakan alarm?' : 'Matikan alarm?',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: lebarDialog(ctx, maksimal: 400)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nyala
                        ? 'Sirene akan berbunyi di lingkungan RT dan seluruh pengurus akan diberi tahu. '
                          'Penekanan ini tercatat beserta nama Anda.'
                        : 'Sirene akan berhenti berbunyi. Penekanan ini juga tercatat.',
                    style: TextStyle(fontSize: 13, height: 1.4, color: ctx.teksKedua),
                  ),
                  if (nyala) ...[
                    const SizedBox(height: AppTheme.spasiL),
                    TextField(
                      controller: kontrolKeterangan,
                      autofocus: true,
                      // Beberapa baris, bukan satu: kejadian darurat jarang
                      // muat dalam satu baris, dan kolom sempit membuat orang
                      // memendekkan cerita yang justru perlu lengkap.
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      // Penghitung karakter ditampilkan, tetapi batasnya TIDAK
                      // dipaksakan pada ketikan — `MaxLengthEnforcement.none`.
                      //
                      // Dengan pemaksaan bawaan, menempelkan teks 600 karakter
                      // akan terpotong DIAM-DIAM menjadi 500: separuh kalimat
                      // tersimpan tanpa pemiliknya tahu, dan pada catatan
                      // darurat separuh kalimat bisa berarti kebalikannya.
                      // Alasan yang sama persis dipakai backend ketika memilih
                      // menolak alih-alih memangkas.
                      maxLength: EmergencyProvider.keteranganMaks,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      decoration: InputDecoration(
                        labelText: 'Keterangan Kejadian',
                        hintText: 'Contoh: Ada warga jatuh dan membutuhkan bantuan',
                        helperText: 'Wajib diisi',
                        errorText: galatKeterangan,
                        alignLabelWithHint: true,
                        prefixIcon: const Icon(Icons.notes_rounded),
                      ),
                      onChanged: (v) {
                        // Galat dibersihkan begitu pemakai memperbaikinya, dan
                        // TIDAK dimunculkan saat ia baru mulai mengetik —
                        // memerahkan kolom pada huruf pertama terasa seperti
                        // dimarahi sebelum sempat selesai.
                        if (galatKeterangan != null && periksaKeterangan(v) == null) {
                          setLokal(() => galatKeterangan = null);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: AppTheme.spasiL),
                  TextField(
                    controller: kontrolPin,
                    // Fokus awal jatuh ke keterangan bila ada, karena itu yang
                    // diisi lebih dulu; memaksa orang melompat mundur satu
                    // kolom membuat kesalahan pengisian lebih mungkin.
                    autofocus: !nyala,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'PIN Darurat',
                      hintText: 'Masukkan PIN',
                      errorText: galatLokal,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                    ),
                    onSubmitted: (_) => kirim(setLokal, ctx),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => kirim(setLokal, ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: nyala ? AppTheme.dangerColor : null,
                ),
                child: Text(nyala ? 'Nyalakan' : 'Matikan'),
              ),
            ],
          ),
        );
      },
    );

    if (hasil == null) return;

    final galat = await darurat.kendaliAlarm(
      aksi,
      hasil.pin,
      keterangan: hasil.keterangan,
    );
    if (!context.mounted) return;

    // Lewat helper bersama, bukan SnackBar sendiri: `lib/core/pesan.dart`
    // adalah satu-satunya tempat warna pesan ditentukan, dan
    // `test/pesan_test.dart` menegakkannya.
    if (galat != null) {
      pesanGagal(context, galat);
    } else {
      pesanSukses(
        context,
        nyala
            ? 'Alarm dinyalakan. Periksa alat untuk memastikan sirene berbunyi.'
            : 'Alarm dimatikan.',
      );
    }
  }
}

/// Hasil dialog aktivasi: PIN dan keterangan kejadian.
///
/// Dibungkus menjadi satu tipe, bukan dikembalikan sebagai dua nilai lewat dua
/// dialog berurutan. Dua dialog berarti orang bisa mengisi keterangan lalu
/// membatalkan di PIN, dan keterangannya hilang tanpa jejak.
class _HasilDialogAlarm {
  final String pin;

  /// Kosong untuk aksi OFF — endpoint memang tidak memakainya di sana.
  final String keterangan;

  const _HasilDialogAlarm({required this.pin, required this.keterangan});
}

/// Tombol aksi panel darurat.
///
/// Dipisah menjadi widget sendiri supaya NYALAKAN dan MATIKAN tidak mungkin
/// berbeda ukuran, radius, atau perilaku keadaan — keduanya hanya berbeda pada
/// nilai yang dioper.
///
/// [utama] menentukan bobot visual: terisi penuh bila utama, bergaris bila
/// sekunder. Keduanya tetap berukuran sama.
class _TombolAksi extends StatelessWidget {
  final String label;
  final IconData ikon;
  final Color warna;
  final bool utama;
  final bool aktif;
  final bool sibuk;
  final VoidCallback onTap;

  const _TombolAksi({
    required this.label,
    required this.ikon,
    required this.warna,
    required this.utama,
    required this.aktif,
    required this.sibuk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isi = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sibuk)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: utama ? Colors.white : warna,
            ),
          )
        else
          Icon(ikon, size: 18),
        const SizedBox(width: AppTheme.spasiS),
        Flexible(
          child: Text(
            // Label berubah saat memuat, bukan hanya ikonnya. Teks "Mengirim…"
            // menjelaskan apa yang sedang terjadi; spinner sendirian tidak.
            sibuk ? 'Mengirim…' : label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
        ),
      ],
    );

    final bentuk = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
    );

    // Tinggi minimum, bukan tetap: kotak bertinggi mati akan memotong isinya
    // saat pengguna menaikkan skala huruf perangkat.
    const ukuranMinimum = Size(0, AppTheme.sasaranSentuh);

    if (utama) {
      return ElevatedButton(
        onPressed: aktif ? onTap : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((keadaan) {
            if (keadaan.contains(WidgetState.disabled)) {
              return warna.withValues(alpha: 0.35);
            }
            if (keadaan.contains(WidgetState.pressed)) {
              // Ditekan → lebih gelap. Umpan balik sentuh harus terlihat tanpa
              // menunggu jaringan menjawab.
              return Color.lerp(warna, Colors.black, 0.18);
            }
            if (keadaan.contains(WidgetState.hovered)) {
              return Color.lerp(warna, Colors.black, 0.08);
            }
            return warna;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          elevation: WidgetStateProperty.resolveWith(
            (keadaan) => keadaan.contains(WidgetState.pressed) ? 0 : 1,
          ),
          minimumSize: WidgetStateProperty.all(ukuranMinimum),
          shape: WidgetStateProperty.all(bentuk),
        ),
        child: isi,
      );
    }

    return OutlinedButton(
      onPressed: aktif ? onTap : null,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((keadaan) =>
            keadaan.contains(WidgetState.disabled) ? warna.withValues(alpha: 0.4) : warna),
        backgroundColor: WidgetStateProperty.resolveWith((keadaan) {
          if (keadaan.contains(WidgetState.pressed)) {
            return warna.withValues(alpha: 0.16);
          }
          if (keadaan.contains(WidgetState.hovered)) {
            return warna.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((keadaan) => BorderSide(
              color: keadaan.contains(WidgetState.disabled)
                  ? context.garis
                  : warna.withValues(alpha: 0.55),
              width: 1.5,
            )),
        minimumSize: WidgetStateProperty.all(ukuranMinimum),
        shape: WidgetStateProperty.all(bentuk),
      ),
      child: isi,
    );
  }
}
