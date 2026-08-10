import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../providers/family_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/banner_lihat_saja.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

const String _kodeIzin = 'kependudukan.warga';
const double _ukuranHoverAksi = 30;
const double _geserAksiTabel = -(kMinInteractiveDimension - _ukuranHoverAksi) / 2;

ButtonStyle _gayaAksiTabel(Color warnaIkon) => IconButton.styleFrom(
  alignment: Alignment.center,
  minimumSize: const Size(_ukuranHoverAksi, _ukuranHoverAksi),
  maximumSize: const Size(_ukuranHoverAksi, _ukuranHoverAksi),
  padding: EdgeInsets.zero,
  shape: const CircleBorder(),
  hoverColor: warnaIkon.withValues(alpha: 0.12),
);

class DataKkScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const DataKkScreen({super.key, this.onBack});

  @override
  State<DataKkScreen> createState() => _DataKkScreenState();
}

class _DataKkScreenState extends State<DataKkScreen> {
  final TextEditingController _ctlCari = TextEditingController();
  int _halaman = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _muatData();
    });
  }

  @override
  void dispose() {
    _ctlCari.dispose();
    super.dispose();
  }

  void _muatData() {
    context.read<FamilyProvider>().fetchFamilies(
          search: _ctlCari.text.trim().isEmpty ? null : _ctlCari.text.trim(),
          page: _halaman,
          limit: 10,
        );
  }

  void _resetFilter() {
    _ctlCari.clear();
    _halaman = 1;
    _muatData();
  }

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses);
  }

  Future<void> _bukaFormTambah(BuildContext context) async {
    final ctlNoKk = TextEditingController();
    final ctlKepala = TextEditingController();
    final ctlAlamat = TextEditingController();
    final ctlRt = TextEditingController(text: '001');
    final ctlRw = TextEditingController(text: '001');
    final ctlKelurahan = TextEditingController(text: '-');
    final ctlKecamatan = TextEditingController(text: '-');
    String statusRumah = 'Milik Sendiri';
    final kunciForm = GlobalKey<FormState>();

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusL)),
          title: const Row(
            children: [
              Icon(Icons.house_rounded, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('Tambah Kartu Keluarga Baru'),
            ],
          ),
          content: SizedBox(
            width: lebarDialog(ctx, maksimal: 500),
            child: SingleChildScrollView(
              child: Form(
                key: kunciForm,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: ctlNoKk,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(16),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Nomor Kartu Keluarga (16 Digit) *',
                        hintText: 'Contoh: 3181512312312312',
                        prefixIcon: Icon(Icons.credit_card_rounded),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'No KK wajib diisi.';
                        if (v.trim().length != 16) return 'No KK harus 16 digit angka.';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    TextFormField(
                      controller: ctlKepala,
                      decoration: const InputDecoration(
                        labelText: 'Nama Kepala Keluarga *',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama Kepala Keluarga wajib diisi.' : null,
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    TextFormField(
                      controller: ctlAlamat,
                      decoration: const InputDecoration(
                        labelText: 'Alamat / Blok & Nomor Rumah',
                        hintText: 'Contoh: Jl. Kapten Yusuf Blok A No. 12',
                        prefixIcon: Icon(Icons.location_on_rounded),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: ctlRt,
                            decoration: const InputDecoration(labelText: 'RT'),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spasiM),
                        Expanded(
                          child: TextFormField(
                            controller: ctlRw,
                            decoration: const InputDecoration(labelText: 'RW'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    DropdownButtonFormField<String>(
                      initialValue: statusRumah,
                      decoration: const InputDecoration(
                        labelText: 'Status Kepemilikan Rumah',
                        prefixIcon: Icon(Icons.home_work_rounded),
                      ),
                      items: ['Milik Sendiri', 'Sewa', 'Kontrak', 'Kos', 'Menumpang']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => statusRumah = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                if (!kunciForm.currentState!.validate()) return;
                final success = await context.read<FamilyProvider>().createFamily(
                      noKk: ctlNoKk.text.trim(),
                      kepalaKeluarga: ctlKepala.text.trim(),
                      alamat: ctlAlamat.text.trim().isEmpty ? '-' : ctlAlamat.text.trim(),
                      rt: ctlRt.text.trim(),
                      rw: ctlRw.text.trim(),
                      kelurahan: ctlKelurahan.text.trim(),
                      kecamatan: ctlKecamatan.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx, success);
              },
              child: const Text('Simpan KK'),
            ),
          ],
        ),
      ),
    );

    if (hasil == true) {
      _pesan('Kartu Keluarga berhasil ditambahkan.', sukses: true);
    }
  }

  Future<void> _bukaFormEdit(BuildContext context, Map<String, dynamic> kk) async {
    final ctlKepala = TextEditingController(text: kk['kepala_keluarga']?.toString() ?? '');
    final ctlAlamat = TextEditingController(text: kk['alamat']?.toString() ?? '');
    final ctlRt = TextEditingController(text: kk['rt']?.toString() ?? '001');
    final ctlRw = TextEditingController(text: kk['rw']?.toString() ?? '001');
    String statusRumah = kk['status_rumah']?.toString() ?? 'Milik Sendiri';
    if (!['Milik Sendiri', 'Sewa', 'Kontrak', 'Kos', 'Menumpang'].contains(statusRumah)) {
      statusRumah = 'Milik Sendiri';
    }
    final kunciForm = GlobalKey<FormState>();
    final id = kk['id'] as int;

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusL)),
          title: Text('Edit Data KK #${kk['no_kk']}'),
          content: SizedBox(
            width: lebarDialog(ctx, maksimal: 500),
            child: SingleChildScrollView(
              child: Form(
                key: kunciForm,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: ctlKepala,
                      decoration: const InputDecoration(
                        labelText: 'Nama Kepala Keluarga *',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama Kepala Keluarga wajib diisi.' : null,
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    TextFormField(
                      controller: ctlAlamat,
                      decoration: const InputDecoration(
                        labelText: 'Alamat / Blok & Nomor Rumah',
                        prefixIcon: Icon(Icons.location_on_rounded),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: ctlRt,
                            decoration: const InputDecoration(labelText: 'RT'),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spasiM),
                        Expanded(
                          child: TextFormField(
                            controller: ctlRw,
                            decoration: const InputDecoration(labelText: 'RW'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    DropdownButtonFormField<String>(
                      initialValue: statusRumah,
                      decoration: const InputDecoration(
                        labelText: 'Status Kepemilikan Rumah',
                        prefixIcon: Icon(Icons.home_work_rounded),
                      ),
                      items: ['Milik Sendiri', 'Sewa', 'Kontrak', 'Kos', 'Menumpang']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => statusRumah = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                if (!kunciForm.currentState!.validate()) return;
                final success = await context.read<FamilyProvider>().updateFamily(id, {
                  'kepala_keluarga': ctlKepala.text.trim(),
                  'alamat': ctlAlamat.text.trim(),
                  'rt': ctlRt.text.trim(),
                  'rw': ctlRw.text.trim(),
                  'status_rumah': statusRumah,
                });
                if (ctx.mounted) Navigator.pop(ctx, success);
              },
              child: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );

    if (hasil == true) {
      _pesan('Data Kartu Keluarga diperbarui.', sukses: true);
    }
  }

  Future<void> _bukaDetailKk(BuildContext context, int id, String noKk) async {
    final prov = context.read<FamilyProvider>();
    await prov.fetchFamilyDetail(id);

    if (!context.mounted) return;
    final detail = prov.selectedFamily;
    if (detail == null) {
      _pesan('Gagal memuat detail Kartu Keluarga.', sukses: false);
      return;
    }

    final anggota = List<Map<String, dynamic>>.from(detail['anggota'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusL)),
        title: Row(
          children: [
            const Icon(Icons.family_restroom_rounded, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Detail KK: $noKk',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: lebarDialog(ctx, maksimal: 700),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppTheme.spasiM),
                  decoration: BoxDecoration(
                    color: ctx.latarLembut,
                    borderRadius: BorderRadius.circular(AppTheme.radiusM),
                    border: Border.all(color: ctx.garis),
                  ),
                  child: Column(
                    children: [
                      _barisDetail(ctx, 'Kepala Keluarga', detail['kepala_keluarga']?.toString() ?? '-'),
                      _barisDetail(ctx, 'Alamat', detail['alamat']?.toString() ?? '-'),
                      _barisDetail(ctx, 'RT / RW', '001 / 001'),
                      _barisDetail(ctx, 'Status Rumah', detail['status_rumah']?.toString() ?? 'Milik Sendiri'),
                      _barisDetail(
                        ctx,
                        'Langganan Sampah',
                        detail['langganan_sampah'] != false ? 'Berlangganan (Ya)' : 'Tidak',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.spasiL),
                Text(
                  'Anggota Keluarga (${anggota.length} Orang)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: ctx.teksUtama),
                ),
                const SizedBox(height: AppTheme.spasiM),
                if (anggota.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('Belum ada anggota keluarga terdaftar.', style: TextStyle(color: ctx.teksKedua)),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: anggota.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final a = anggota[idx];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                          child: Icon(
                            a['status_keluarga'] == 'Kepala Keluarga'
                                ? Icons.person_pin_rounded
                                : Icons.person_outline_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          a['nama']?.toString() ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('NIK: ${a['nik'] ?? '-'} • ${a['status_keluarga'] ?? 'Anggota'}'),
                        trailing: Chip(
                          label: Text(a['jenis_kelamin']?.toString() == 'L' ? 'Laki-laki' : 'Perempuan'),
                          backgroundColor: ctx.latarLembut,
                          labelStyle: TextStyle(fontSize: 11, color: ctx.teksUtama),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _barisDetail(BuildContext ctx, String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: ctx.teksKedua, fontSize: 13)),
          Text(nilai, style: TextStyle(fontWeight: FontWeight.w600, color: ctx.teksUtama, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _hapusKk(BuildContext context, int id, String noKk) async {
    final prov = context.read<FamilyProvider>();
    final setuju = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kartu Keluarga?'),
        content: Text('Apakah Anda yakin ingin menghapus KK $noKk? Data keluarga ini akan dinonaktifkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (setuju == true) {
      final ok = await prov.deleteFamily(id);
      if (!mounted) return;
      if (ok) {
        _pesan('Kartu Keluarga $noKk berhasil dihapus.', sukses: true);
      } else {
        _pesan('Gagal menghapus Kartu Keluarga.', sukses: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<FamilyProvider>();
    final permission = context.watch<PermissionProvider>();
    final isBolehUbah = permission.bolehUbah(_kodeIzin);
    final isAdmin = permission.isAdmin;

    final daftarKK = prov.families;

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onBack != null) ...[
                      TombolKembali(onPressed: widget.onBack),
                      const SizedBox(width: 10),
                    ],
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.house_rounded, color: AppTheme.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Kependudukan / Data KK',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.teksKedua,
                      ),
                    ),
                  ],
                ),
                if (isBolehUbah)
                  ElevatedButton.icon(
                    onPressed: () => _bukaFormTambah(context),
                    icon: const Icon(Icons.add_home_rounded, size: 18),
                    label: const Text('Tambah KK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusM)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spasiL),

          BannerLihatSaja(kode: _kodeIzin),

          // Search Card
          Container(
            padding: const EdgeInsets.all(AppTheme.spasiL),
            decoration: BoxDecoration(
              color: context.latarKartu,
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
              border: Border.all(color: context.garis),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ctlCari,
                    onFieldSubmitted: (_) {
                      _halaman = 1;
                      _muatData();
                    },
                    decoration: InputDecoration(
                      hintText: 'Cari berdasarkan No KK, Kepala Keluarga, Alamat...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusM)),
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spasiM),
                ElevatedButton.icon(
                  onPressed: () {
                    _halaman = 1;
                    _muatData();
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Cari'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusM)),
                  ),
                ),
                const SizedBox(width: AppTheme.spasiS),
                OutlinedButton(
                  onPressed: _resetFilter,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusM)),
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spasiL),

          // Tabel Responsif KK
          TabelResponsif(
            kolom: const [
              'NO',
              'NO KK',
              'KEPALA KELUARGA',
              'ALAMAT & BLOK',
              'ANGGOTA',
              'STATUS RUMAH',
            ],
            labelAksi: 'AKSI',
            currentPage: prov.currentPage,
            totalPages: prov.totalPages,
            totalData: prov.totalData,
            perPage: 10,
            onPageChanged: (h) {
              setState(() => _halaman = h);
              _muatData();
            },
            baris: daftarKK.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final id = item['id'] as int;
              final noKk = item['no_kk']?.toString() ?? '-';
              final kepala = item['kepala_keluarga']?.toString() ?? '-';
              final alamat = item['alamat']?.toString() ?? '-';
              final jumlahAnggota = item['jumlah_anggota'] ?? 0;
              final statusRumah = item['status_rumah']?.toString() ?? 'Milik Sendiri';
              final terkonfirmasi = item['kepala_terkonfirmasi'] == true;

              return BarisTabel(
                sel: [
                  SelTabel.teks('NO', '${((prov.currentPage - 1) * 10) + idx + 1}', sembunyiDiKartu: true),
                  SelTabel.teks(
                    'NO KK',
                    noKk,
                    utama: true,
                    gaya: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: context.teksUtama,
                    ),
                  ),
                  SelTabel(
                    'KEPALA KELUARGA',
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            kepala,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (!terkonfirmasi)
                          Tooltip(
                            message: 'Nama Kepala Keluarga belum terkonfirmasi',
                            child: Icon(Icons.info_outline_rounded, size: 14, color: Colors.amber[700]),
                          ),
                      ],
                    ),
                  ),
                  SelTabel.teks('ALAMAT & BLOK', alamat),
                  SelTabel(
                    'ANGGOTA',
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$jumlahAnggota Orang',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                      ),
                    ),
                  ),
                  SelTabel(
                    'STATUS RUMAH',
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusRumah == 'Milik Sendiri'
                            ? const Color(0xFF10B981).withValues(alpha: 0.1)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusRumah,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusRumah == 'Milik Sendiri' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ),
                ],
                aksi: Transform.translate(
                  offset: const Offset(_geserAksiTabel, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Lihat Detail & Anggota KK',
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        color: AppTheme.primaryColor,
                        style: _gayaAksiTabel(AppTheme.primaryColor),
                        onPressed: () => _bukaDetailKk(context, id, noKk),
                      ),
                      if (isBolehUbah) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Edit KK',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: Colors.blue[600],
                          style: _gayaAksiTabel(Colors.blue[600]!),
                          onPressed: () => _bukaFormEdit(context, item),
                        ),
                      ],
                      if (isAdmin) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Hapus KK',
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          color: Colors.red[600],
                          style: _gayaAksiTabel(Colors.red[600]!),
                          onPressed: () => _hapusKk(context, id, noKk),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
