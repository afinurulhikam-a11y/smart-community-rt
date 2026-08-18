import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/format.dart';
import '../core/pesan.dart';
import '../core/responsif.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/warna_konteks.dart';
import '../models/meteran_model.dart';
import '../providers/meteran_provider.dart';
import '../providers/permission_provider.dart';
import 'keadaan_daftar.dart';

/// Panel bacaan meteran untuk pengurus — memantau siapa sudah melapor, dan
/// mengoreksi yang perlu dikoreksi.
///
/// Ini **bukan** daftar tagihan. Antara tanggal 1 dan 25 tabel tagihan periode
/// berjalan masih kosong sementara bacaan-bacaannya sudah masuk; kalau pengurus
/// hanya punya layar tagihan, selama tiga minggu itu ia tidak bisa melihat
/// apa pun — termasuk anomali yang justru paling berguna ditemukan sebelum
/// tagihannya terbit.
///
/// Koreksi di sini **menuntut alasan**. Baris yang sudah dikoreksi tidak
/// menyimpan jejak apa pun tentang kenapa, dan koreksi meteran mengubah berapa
/// yang harus dibayar warga — tanpa alasan, jejak auditnya hanya mencatat
/// bahwa sesuatu berubah.
class DialogBacaanMeteran extends StatefulWidget {
  const DialogBacaanMeteran({super.key});

  @override
  State<DialogBacaanMeteran> createState() => _DialogBacaanMeteranState();
}

/// Periode `YYYY-MM` dari komponen waktu LOKAL.
///
/// `toIso8601String()` mengonversi ke UTC lebih dulu, sehingga 1 Agustus di
/// WIB terkirim sebagai 31 Juli — dan seluruh periode bergeser sebulan pada
/// tanggal 1. Jebakan yang sama sudah tercatat di CLAUDE.md.
String periodeSekarang([DateTime? saat]) {
  final d = saat ?? DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

class _DialogBacaanMeteranState extends State<DialogBacaanMeteran> {
  static const _kodeIzin = 'keuangan.iuran';

  late String _periode = periodeSekarang();
  String? _status;
  final _searchCtrl = TextEditingController();
  String? _searchQuery;

  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _muat() {
    if (!mounted) return;
    context.read<MeteranProvider>().muatDaftar(periode: _periode, status: _status, search: _searchQuery);
  }

  Future<void> _gantiPeriode(int langkah) async {
    final bagian = _periode.split('-');
    final d = DateTime(int.parse(bagian[0]), int.parse(bagian[1]) + langkah);
    setState(() => _periode = periodeSekarang(d));
    _muat();
  }

  Future<void> _koreksi(MeteranModel m) async {
    final ctlLalu = TextEditingController(text: m.meteranLalu?.toString() ?? '');
    final ctlKini = TextEditingController(text: m.meteranSekarang?.toString() ?? '');
    final ctlAlasan = TextEditingController();
    final kunci = GlobalKey<FormState>();
    bool langgananSampah = m.langgananSampah == true;

    final setuju = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Koreksi Meteran — ${m.kepalaKeluarga ?? '-'}'),
        content: SizedBox(
          width: lebarDialog(ctx, maksimal: 420),
          child: Form(
            key: kunci,
            child: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (ctx, setDialogState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Periode ${m.periode}',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: ctx.teksKedua,
                            ),
                      ),
                      const SizedBox(height: AppTheme.spasiM),
                      TextFormField(
                        controller: ctlLalu,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Meteran lalu'),
                      ),
                      const SizedBox(height: AppTheme.spasiM),
                      TextFormField(
                        controller: ctlKini,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Meteran sekarang'),
                      ),
                      const SizedBox(height: AppTheme.spasiM),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spasiM,
                          vertical: AppTheme.spasiS,
                        ),
                        decoration: BoxDecoration(
                          color: ctx.latarLembut,
                          borderRadius: BorderRadius.circular(AppTheme.radiusM),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Langganan Sampah',
                                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  Text(
                                    'Layanan pengangkutan sampah warga',
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                          color: ctx.teksKedua,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: langgananSampah,
                              onChanged: (val) {
                                setDialogState(() => langgananSampah = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.spasiM),
                      TextFormField(
                        controller: ctlAlasan,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Alasan koreksi *',
                          helperText: 'Tercatat di Log Aktivitas bersama angka lama dan baru',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Alasan koreksi wajib diisi'
                            : null,
                      ),
                      if (m.sudahJadiTagihan)
                        Padding(
                          padding: const EdgeInsets.only(top: AppTheme.spasiM),
                          child: _pita(
                            ctx,
                            AppTheme.warningColor,
                            Icons.info_outline_rounded,
                            'Tagihan periode ini sudah terbit. Nominal tagihan akan otomatis disinkronkan.',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: ctx.gelap ? Colors.white : Colors.black,
            ),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (kunci.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Simpan Koreksi'),
          ),
        ],
      ),
    );

    if (setuju != true || !mounted) return;

    final res = await context.read<MeteranProvider>().koreksi(
          m.id,
          alasan: ctlAlasan.text.trim(),
          meteranLalu: int.tryParse(ctlLalu.text),
          meteranSekarang: int.tryParse(ctlKini.text),
          keluargaId: m.keluargaId,
          periode: m.periode,
          langgananSampah: langgananSampah,
        );
    if (!mounted) return;

    // `catatan` dari backend memberi tahu bahwa tagihannya perlu dikoreksi
    // terpisah. Ia hanya ada bila memang relevan, jadi ditampilkan apa adanya.
    final catatan = res['catatan']?.toString();
    tampilkanPesan(
      context,
      [res['message']?.toString() ?? 'Selesai.', if (catatan != null) catatan].join(' '),
      sukses: res['success'] == true,
      perilaku: SnackBarBehavior.floating,
      durasi: const Duration(seconds: 5),
    );
    if (res['success'] == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MeteranProvider>();

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
      ),
      title: const Text('Bacaan Meteran Air'),
      content: SizedBox(
        width: lebarDialog(context, maksimal: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pemilihPeriode(context),
            const SizedBox(height: AppTheme.spasiS),
            _penyaringStatus(context),
            const SizedBox(height: AppTheme.spasiS),
            TextField(
              controller: _searchCtrl,
              onSubmitted: (v) {
                setState(() => _searchQuery = v.trim().isEmpty ? null : v.trim());
                _muat();
              },
              decoration: InputDecoration(
                hintText: 'Cari nama, no KK, alamat, atau blok...',
                hintStyle: TextStyle(fontSize: 12, color: context.teksTersier),
                prefixIcon: Icon(Icons.search, size: 18, color: context.teksKedua),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = null);
                          _muat();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        onPressed: () {
                          setState(() => _searchQuery = _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim());
                          _muat();
                        },
                      ),
                filled: true,
                fillColor: context.latarLembut,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: BorderSide(color: context.garis),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: BorderSide(color: context.garis),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spasiS),
            _ringkasan(context, prov.list),
            const Divider(height: AppTheme.spasiXl),
            // `Flexible` sendirian tidak cukup: ia longgar, jadi anaknya boleh
            // lebih tinggi daripada ruang sisanya dan meluber. Terbukti di
            // 320×568 — tiga baris bacaan meluber 196px, dan keadaan kosong
            // (padding 40 + ikon + dua kalimat) meluber 113px. Scroll di sini
            // membuat tinggi berapa pun aman, sedangkan daftarnya sendiri
            // memakai NeverScrollableScrollPhysics supaya tidak ada dua
            // penggulir bersarang yang saling berebut gestur.
            Flexible(child: SingleChildScrollView(child: _daftar(context, prov))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: context.gelap ? Colors.white : Colors.black,
          ),
          child: const Text('Tutup'),
        ),
      ],
    );
  }

  Widget _pemilihPeriode(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Periode sebelumnya',
          onPressed: () => _gantiPeriode(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            _periode,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          tooltip: 'Periode berikutnya',
          onPressed: () => _gantiPeriode(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _penyaringStatus(BuildContext context) {
    const pilihan = <String?, String>{
      null: 'Semua',
      'menunggu': 'Menunggu',
      'terisi': 'Terisi',
      'anomali': 'Anomali',
    };
    // Menggulir mendatar, tidak membungkus: Wrap menyesuaikan tiap chip ke
    // labelnya sendiri sehingga tepi kanannya selalu bergerigi di layar sempit.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: pilihan.entries.map((e) {
          final aktif = _status == e.key;
          return Padding(
            padding: const EdgeInsets.only(right: AppTheme.spasiS),
            child: ChoiceChip(
              label: Text(e.value),
              selected: aktif,
              onSelected: (_) {
                setState(() => _status = e.key);
                _muat();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _ringkasan(BuildContext context, List<MeteranModel> list) {
    final anomali = list.where((e) => e.anomali).length;
    final terisi = list.where((e) => e.status == 'terisi').length;
    final teks = Theme.of(context).textTheme.bodySmall;
    return Text(
      '$terisi terisi • $anomali anomali • ${list.length} baris',
      style: teks?.copyWith(
        color: anomali > 0 ? AppTheme.dangerColor : context.teksKedua,
        fontWeight: anomali > 0 ? FontWeight.w700 : null,
      ),
    );
  }

  Widget _daftar(BuildContext context, MeteranProvider prov) {
    if (prov.isLoading && prov.list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.spasiXl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Permintaan yang gagal TIDAK boleh tampil sebagai daftar kosong: pengurus
    // akan menyimpulkan tidak ada yang melapor, padahal servernya tak terjangkau.
    if (prov.list.isEmpty) {
      return KeadaanDaftar(
        galat: prov.errorMessage,
        offline: prov.offline,
        kosong: 'Belum ada bacaan meteran periode $_periode.\n'
            'Warga mengisi meterannya sendiri pada tanggal 1–5.',
        ikonKosong: Icons.water_drop_outlined,
        onCobaLagi: _muat,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: prov.list.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spasiS),
      itemBuilder: (_, i) => _baris(context, prov.list[i]),
    );
  }

  Widget _baris(BuildContext context, MeteranModel m) {
    final teks = Theme.of(context).textTheme;
    final warna = switch (m.status) {
      'anomali' => AppTheme.dangerColor,
      'terisi' => AppTheme.successColor,
      _ => AppTheme.warningColor,
    };

    return Container(
      padding: const EdgeInsets.all(AppTheme.spasiM),
      decoration: BoxDecoration(
        color: context.latarLembut,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: m.anomali ? warna.withValues(alpha: 0.5) : context.garis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.kepalaKeluarga ?? '-',
                      style: teks.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (m.blok != null && m.blok!.isNotEmpty) 'Blok ${m.blok}',
                        if (m.noKk != null && m.noKk!.isNotEmpty) m.noKk!,
                      ].join(' • '),
                      style: teks.bodySmall?.copyWith(color: context.teksKedua),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: warna.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusS),
                ),
                child: Text(
                  m.statusLabel,
                  style: teks.labelSmall?.copyWith(
                    color: warna,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spasiS),
          Text(
            m.sudahDiisi
                ? '${m.meteranLalu ?? '-'} → ${m.meteranSekarang} = ${m.terpakai} m³'
                : 'Belum diisi warga',
            style: teks.bodyMedium,
          ),
          if (m.nominal != null)
            Text(
              'Tagihan ${rupiah(m.nominal)}'
              '${m.statusTagihan == 'paid' ? ' — lunas' : ''}',
              style: teks.bodySmall?.copyWith(color: context.teksKedua),
            ),
          if (m.catatan != null && m.catatan!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spasiS),
              child: Text(
                m.catatan!,
                style: teks.bodySmall?.copyWith(color: warna),
              ),
            ),
          if (_bolehUbah)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _koreksi(m),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Koreksi'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pita(BuildContext context, Color warna, IconData ikon, String isi) {
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
              isi,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.teksUtama,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
