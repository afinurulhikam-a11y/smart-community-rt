import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/format.dart';
import '../core/pesan.dart';
import '../core/responsif.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';
import '../models/jenis_iuran_model.dart';
import '../models/meteran_model.dart';
import '../providers/jenis_iuran_provider.dart';
import '../providers/meteran_provider.dart';

/// Kartu meteran air milik warga, di atas daftar tagihannya.
///
/// **Kartu ini ada walau tagihan periode ini belum terbit — dan itu justru
/// alasannya ada.** Warga mengisi meteran tanggal 1–5; tagihannya baru lahir
/// tanggal 25. Kalau formulirnya menempel pada tagihan, tanggal 1 tidak ada
/// apa pun untuk diisi.
///
/// Enam keadaan yang ditampilkan berbeda-beda, dan tidak satu pun boleh
/// tampil sebagai layar kosong:
///
/// | Keadaan | Yang dilihat warga |
/// |---|---|
/// | belum diisi, ≤ tgl 5 | formulir |
/// | sudah diisi, ≤ tgl 5 | angkanya + tombol Ubah |
/// | sudah diisi, > tgl 5 | angkanya, terkunci, kapan tagihan terbit |
/// | **belum diisi, > tgl 5** | peringatan: hubungi pengurus |
/// | anomali | angkanya + penjelasan kenapa ditandai |
/// | akun tanpa KK | penjelasannya, bukan daftar kosong |
///
/// Keadaan keempat yang paling mudah terlewat: warga yang melewatkan
/// tanggalnya perlu tahu bahwa ia melewatkannya, bukan melihat kartu diam.
class KartuMeteranWarga extends StatefulWidget {
  const KartuMeteranWarga({super.key});

  @override
  State<KartuMeteranWarga> createState() => _KartuMeteranWargaState();
}

class _KartuMeteranWargaState extends State<KartuMeteranWarga> {
  bool _sedangSimpan = false;
  bool _sedangSampah = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MeteranProvider>().muatSaya();
      // Tarif dibutuhkan untuk memperkirakan tagihan sebelum ia terbit.
      // Warga memegang `keuangan.iuran:view`, jadi ini bukan izin baru.
      context.read<JenisIuranProvider>().fetchJenisIuran();
    });
  }

  JenisIuranModel? get _tarif {
    final daftar = context.read<JenisIuranProvider>().bermeteran;
    return daftar.isEmpty ? null : daftar.first;
  }

  Future<void> _bukaFormulir(MeteranSaya keadaan) async {
    final ctlSekarang = TextEditingController(
      text: keadaan.bacaan?.meteranSekarang?.toString() ?? '',
    );
    final ctlLalu = TextEditingController(
      text: (keadaan.bacaan?.meteranLalu ?? keadaan.meteranLalu)?.toString() ?? '',
    );
    final kunci = GlobalKey<FormState>();

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: const Text('Isi Meteran Air'),
        content: SizedBox(
          // Lebar tetap di dalam AlertDialog tidak menyusut di layar sempit;
          // dialognya meluber dan field-nya terjepit.
          width: lebarDialog(ctx, maksimal: 420),
          child: Form(
            key: kunci,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Periode ${keadaan.periode}',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: ctx.teksKedua,
                      ),
                ),
                const SizedBox(height: AppTheme.spasiM),
                if (keadaan.periodePertama) ...[
                  // Periode pertama satu-satunya kali warga mengisi angka
                  // pembanding. Sesudahnya server mengambilnya sendiri dari
                  // bacaan sebelumnya, dan kiriman dari sini diabaikan.
                  TextFormField(
                    controller: ctlLalu,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Meteran bulan lalu',
                      helperText: 'Hanya diisi pada periode pertama',
                    ),
                    validator: (v) => (int.tryParse(v ?? '') == null)
                        ? 'Isi angka meteran bulan lalu'
                        : null,
                  ),
                  const SizedBox(height: AppTheme.spasiM),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.spasiM),
                    child: _barisInfo(
                      ctx,
                      'Meteran bulan lalu',
                      '${keadaan.meteranLalu ?? '-'}',
                    ),
                  ),
                TextFormField(
                  controller: ctlSekarang,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Meteran sekarang',
                    helperText: 'Angka yang tertera di meteran rumah Anda',
                  ),
                  validator: (v) => (int.tryParse(v ?? '') == null)
                      ? 'Isi angka meteran sekarang'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (kunci.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (hasil != true || !mounted) return;

    setState(() => _sedangSimpan = true);
    final res = await context.read<MeteranProvider>().isi(
          meteranSekarang: int.parse(ctlSekarang.text),
          meteranLalu: keadaan.periodePertama ? int.tryParse(ctlLalu.text) : null,
        );
    if (!mounted) return;
    setState(() => _sedangSimpan = false);

    // Bacaan mundur tersimpan DAN dilaporkan sebagai anomali — keduanya
    // `success: true`. Pesannyalah yang membedakan, jadi ia ditampilkan apa
    // adanya alih-alih diganti "Berhasil".
    tampilkanPesan(
      context,
      res['message']?.toString() ?? 'Meteran tersimpan.',
      sukses: res['success'] == true,
      perilaku: SnackBarBehavior.floating,
      durasi: const Duration(seconds: 5),
    );
  }

  Future<void> _ubahSampah(bool nyala) async {
    setState(() => _sedangSampah = true);
    final res = await context.read<MeteranProvider>().ubahLanggananSampah(nyala);
    if (!mounted) return;
    setState(() => _sedangSampah = false);
    tampilkanPesan(
      context,
      res['message']?.toString() ??
          (res['success'] == true ? 'Tersimpan.' : 'Gagal mengubah langganan.'),
      sukses: res['success'] == true,
      perilaku: SnackBarBehavior.floating,
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MeteranProvider>();
    final keadaan = prov.saya;

    if (prov.isLoading && keadaan == null) {
      return _bingkai(
        context,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(AppTheme.spasiL),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (keadaan == null) {
      // Akun tanpa kartu keluarga bukan galat sistem, dan menampilkannya
      // sebagai kartu kosong akan terbaca "belum ada tagihan" — kesimpulan
      // yang salah. Sebutkan keadaannya.
      return _bingkai(
        context,
        child: _pesanKosong(
          context,
          Icons.link_off_rounded,
          prov.errorMessage ?? 'Data pelanggan air belum tersedia.',
        ),
      );
    }

    return _bingkai(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, keadaan),
          const Divider(height: AppTheme.spasiXl),
          _isiMeteran(context, keadaan),
          const SizedBox(height: AppTheme.spasiM),
          _saklarSampah(context, keadaan),
        ],
      ),
    );
  }

  // ── Bagian-bagian ────────────────────────────────────────────────

  Widget _header(BuildContext context, MeteranSaya k) {
    final teks = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.spasiS),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          child: const Icon(Icons.water_drop_rounded, color: AppTheme.primaryColor),
        ),
        const SizedBox(width: AppTheme.spasiM),
        // Expanded sendirian sudah mendorong sisanya ke tepi. Menambah Spacer
        // di sini akan membagi ruang sisa rata dua dan menghimpit namanya.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                k.namaPelanggan,
                style: teks.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                [
                  if (k.blok != null && k.blok!.isNotEmpty) 'Blok ${k.blok}',
                  if (k.noKk != null && k.noKk!.isNotEmpty) 'KK ${k.noKk}',
                ].join(' • '),
                style: teks.bodySmall?.copyWith(color: context.teksKedua),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _isiMeteran(BuildContext context, MeteranSaya k) {
    final teks = Theme.of(context).textTheme;
    final bacaan = k.bacaan;

    // Keadaan yang paling mudah terlewat: tanggalnya lewat dan warga belum
    // mengisi. Tanpa peringatan ini kartunya diam saja, dan warga baru tahu
    // ketika tagihannya terbit tanpa pemakaian air.
    if (!k.bolehIsi && !k.sudahDiisi) {
      return _pita(
        context,
        AppTheme.warningColor,
        Icons.schedule_rounded,
        'Batas input meteran (tanggal ${k.batasTanggal}) sudah lewat dan '
        'meteran periode ${k.periode} belum terisi. Hubungi pengurus RT bila '
        'ingin dicatatkan.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meteran Periode ${k.periode}',
          style: teks.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppTheme.spasiS),

        if (bacaan != null && bacaan.sudahDiisi) ...[
          _barisInfo(context, 'Meteran lalu', '${bacaan.meteranLalu ?? '-'}'),
          _barisInfo(context, 'Meteran sekarang', '${bacaan.meteranSekarang}'),
          _barisInfo(context, 'Pemakaian', '${bacaan.terpakai ?? 0} m³'),
          if (_tarif != null)
            _barisInfo(context, 'Abondement', rupiah(_tarif!.abondement)),
          if (_tarif != null && k.langgananSampah)
            _barisInfo(context, 'Layanan sampah', rupiah(_tarif!.biayaSampah)),
          if (_tarif != null)
            _barisInfo(
              context,
              k.terkunci ? 'Tagihan' : 'Perkiraan tagihan',
              rupiah(
                (bacaan.terpakai ?? 0) * _tarif!.tarifPerM3 +
                    _tarif!.abondement +
                    (k.langgananSampah ? _tarif!.biayaSampah : 0),
              ),
              tebal: true,
            ),
          if (bacaan.anomali)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spasiS),
              child: _pita(
                context,
                AppTheme.dangerColor,
                Icons.warning_amber_rounded,
                bacaan.catatan ??
                    'Angka meteran lebih kecil daripada bulan lalu. '
                        'Pengurus akan memeriksanya.',
              ),
            ),
        ] else
          Text(
            k.periodePertama
                ? 'Ini periode pertama Anda — isi angka meteran bulan lalu '
                    'dan meteran sekarang.'
                : 'Meteran bulan lalu: ${k.meteranLalu ?? '-'}. '
                    'Isi angka meteran rumah Anda sekarang.',
            style: teks.bodyMedium?.copyWith(color: context.teksKedua),
          ),

        const SizedBox(height: AppTheme.spasiM),

        if (k.terkunci)
          _pita(
            context,
            AppTheme.primaryColor,
            Icons.lock_outline_rounded,
            'Tagihan periode ini sudah terbit, jadi angkanya terkunci. '
            'Hubungi pengurus RT bila ada yang perlu dikoreksi.',
          )
        else if (k.bolehIsi)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sedangSimpan ? null : () => _bukaFormulir(k),
              icon: _sedangSimpan
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(k.sudahDiisi ? Icons.edit_rounded : Icons.add_rounded),
              label: Text(k.sudahDiisi ? 'Ubah Meteran' : 'Isi Meteran'),
            ),
          )
        else
          _pita(
            context,
            AppTheme.primaryColor,
            Icons.event_available_rounded,
            'Meteran sudah tercatat. Tagihan periode ini terbit otomatis '
            'pada tanggal 25.',
          ),
      ],
    );
  }

  Widget _saklarSampah(BuildContext context, MeteranSaya k) {
    final teks = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spasiM,
        vertical: AppTheme.spasiS,
      ),
      decoration: BoxDecoration(
        color: context.latarLembut,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Layanan sampah',
                  style: teks.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  _tarif == null
                      ? 'Ditagih bersama tagihan air'
                      : '${rupiah(_tarif!.biayaSampah)} / bulan, ditagih bersama air',
                  style: teks.bodySmall?.copyWith(color: context.teksKedua),
                ),
                if (!k.bolehIsi)
                  Text(
                    'Bisa diubah sampai tanggal ${k.batasTanggal}',
                    style: teks.labelSmall?.copyWith(color: context.teksTersier),
                  ),
              ],
            ),
          ),
          if (_sedangSampah)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: k.langgananSampah,
              // Batasnya sama dengan input meteran, dan itu disengaja: satu
              // tanggal untuk diingat. Tanpa batas, warga bisa mematikannya
              // tanggal 24 lalu menyalakannya lagi tanggal 26.
              onChanged: k.bolehIsi ? _ubahSampah : null,
            ),
        ],
      ),
    );
  }

  // ── Potongan bersama ─────────────────────────────────────────────

  Widget _bingkai(BuildContext context, {required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spasiL),
      padding: const EdgeInsets.all(AppTheme.spasiL),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: context.garis),
      ),
      child: child,
    );
  }

  Widget _barisInfo(BuildContext context, String label, String nilai,
      {bool tebal = false}) {
    final teks = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: teks.bodyMedium?.copyWith(color: context.teksKedua),
            ),
          ),
          Flexible(
            child: Text(
              nilai,
              textAlign: TextAlign.end,
              style: teks.bodyMedium?.copyWith(
                fontWeight: tebal ? FontWeight.w700 : FontWeight.w600,
                color: tebal ? AppTheme.primaryColor : context.teksUtama,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pita(BuildContext context, Color warna, IconData ikon, String teks) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spasiM),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: warna.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: warna),
          const SizedBox(width: AppTheme.spasiS),
          Expanded(
            child: Text(
              teks,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.teksUtama,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pesanKosong(BuildContext context, IconData ikon, String teks) {
    return Column(
      children: [
        Icon(ikon, size: 40, color: context.teksTersier),
        const SizedBox(height: AppTheme.spasiS),
        Text(
          teks,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.teksKedua,
              ),
        ),
      ],
    );
  }
}
