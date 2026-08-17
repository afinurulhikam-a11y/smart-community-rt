import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../providers/family_provider.dart';
import '../../providers/warga_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/banner_lihat_saja.dart';
import '../../widgets/tabel_responsif.dart';
import '../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

const String _kodeIzin = 'kependudukan.warga';
const double _ukuranHoverAksi = 30;
const double _geserAksiTabel =
    -(kMinInteractiveDimension - _ukuranHoverAksi) / 2;

const List<String> _opsiStatusHubungan = [
  'Istri',
  'Anak',
  'Kepala Keluarga',
  'Suami',
  'Orang Tua',
  'Mertua',
  'Menantu',
  'Cucu',
  'Famili Lain',
  'Lainnya',
];

const List<String> _opsiStatusPerkawinan = [
  'Belum Menikah',
  'Menikah',
  'Cerai Hidup',
  'Cerai Mati',
];

const List<String> _opsiAgama = [
  'Islam',
  'Kristen',
  'Katolik',
  'Hindu',
  'Buddha',
  'Konghucu',
  'Lainnya',
];

const List<String> _opsiPendidikan = [
  'Tidak Sekolah',
  'SD',
  'SMP',
  'SMA/SMK',
  'D3',
  'S1',
  'S2',
  'S3',
];

const List<String> _opsiPekerjaan = [
  'PNS',
  'TNI/Polri',
  'Karyawan Swasta',
  'Wiraswasta',
  'Petani',
  'Buruh',
  'Ibu Rumah Tangga',
  'Pelajar/Mahasiswa',
  'Pensiunan',
  'Pekerja Lepas',
  'Belum/Tidak Bekerja',
];

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
    setState(() {
      _ctlCari.clear();
      _halaman = 1;
    });
    _muatData();
  }

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(context, teks, sukses: sukses);
  }

  Future<void> _bukaFormEdit(
    BuildContext context,
    Map<String, dynamic> kk,
  ) async {
    final ctlKepala = TextEditingController(
      text: kk['kepala_keluarga']?.toString() ?? '',
    );
    final ctlAlamat = TextEditingController(
      text: kk['alamat']?.toString() ?? '',
    );
    String statusRumah = kk['status_rumah']?.toString() ?? 'Milik Sendiri';
    if (![
      'Milik Sendiri',
      'Sewa',
      'Kontrak',
      'Kos',
      'Menumpang',
    ].contains(statusRumah)) {
      statusRumah = 'Milik Sendiri';
    }
    bool langgananSampah = kk['langganan_sampah'] == true;
    final kunciForm = GlobalKey<FormState>();
    final id = int.tryParse(kk['id']?.toString() ?? '0') ?? 0;
    final noKk = kk['no_kk']?.toString() ?? '-';

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ctx.latarKartu,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.edit_note_rounded, color: Color(0xFF1B7A6A)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Edit Data KK',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: ctx.teksUtama,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No KK: $noKk',
                      style: TextStyle(
                        fontSize: 12,
                        color: ctx.teksKedua,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
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
                      controller: ctlKepala,
                      decoration: const InputDecoration(
                        labelText: 'Nama Kepala Keluarga *',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nama Kepala Keluarga wajib diisi.'
                          : null,
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    TextFormField(
                      controller: ctlAlamat,
                      decoration: const InputDecoration(
                        labelText: 'Alamat / Blok & Nomor Rumah *',
                        prefixIcon: Icon(Icons.location_on_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Alamat wajib diisi.'
                          : null,
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    DropdownButtonFormField<String>(
                      initialValue: statusRumah,
                      dropdownColor: ctx.latarKartu,
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        labelText: 'Status Kepemilikan Rumah',
                        prefixIcon: Icon(Icons.home_work_rounded),
                      ),
                      items:
                          [
                                'Milik Sendiri',
                                'Sewa',
                                'Kontrak',
                                'Kos',
                                'Menumpang',
                              ]
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => statusRumah = v);
                      },
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ctx.latarLembut,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ctx.garis),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Langganan Pengangkutan Sampah',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ctx.teksUtama,
                          ),
                        ),
                        subtitle: Text(
                          langgananSampah
                              ? '✓ Berlangganan Sampah'
                              : '✗ Tidak Berlangganan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: langgananSampah
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                        value: langgananSampah,
                        activeTrackColor: const Color(0xFF1B7A6A),
                        onChanged: (val) {
                          setDialogState(() => langgananSampah = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                foregroundColor: ctx.teksKedua,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B7A6A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                if (!kunciForm.currentState!.validate()) return;
                final success = await context
                    .read<FamilyProvider>()
                    .updateFamily(id, {
                      'kepala_keluarga': ctlKepala.text.trim(),
                      'alamat': ctlAlamat.text.trim(),
                      'status_rumah': statusRumah,
                      'langganan_sampah': langgananSampah,
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
    if (prov.selectedFamily == null) {
      _pesan('Gagal memuat detail Kartu Keluarga.', sukses: false);
      return;
    }

    final permission = context.read<PermissionProvider>();
    final isBolehUbah =
        permission.bolehUbah(_kodeIzin) || permission.bolehTambah(_kodeIzin);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDetailState) {
          final detail = prov.selectedFamily ?? {};
          final anggota =
              List<Map<String, dynamic>>.from(detail['anggota'] ?? []);

          return AlertDialog(
            backgroundColor: ctx.latarKartu,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.family_restroom_rounded,
                    color: Color(0xFF1B7A6A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Detail KK: $noKk',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ctx.teksUtama,
                    ),
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
                          _barisDetail(
                            ctx,
                            'Kepala Keluarga',
                            detail['kepala_keluarga']?.toString() ?? '-',
                          ),
                          _barisDetail(
                            ctx,
                            'Alamat',
                            detail['alamat']?.toString() ?? '-',
                          ),
                          _barisDetail(
                            ctx,
                            'Status Rumah',
                            detail['status_rumah']?.toString() ?? 'Milik Sendiri',
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Langganan Sampah',
                                  style: TextStyle(
                                    color: ctx.teksKedua,
                                    fontSize: 13,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: detail['langganan_sampah'] == true
                                        ? const Color(0xFFD1FAE5)
                                        : const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    detail['langganan_sampah'] == true
                                        ? '✓ Berlangganan Sampah'
                                        : '✗ Tidak Berlangganan',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: detail['langganan_sampah'] == true
                                          ? const Color(0xFF065F46)
                                          : const Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spasiL),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Anggota Keluarga (${anggota.length} Orang)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: ctx.teksUtama,
                            ),
                          ),
                        ),
                        if (isBolehUbah)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.person_add_rounded, size: 16),
                            label: const Text(
                              'Tambah Anggota',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B7A6A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _bukaFormTambahAnggota(
                              context,
                              id,
                              detail,
                              () async {
                                await prov.fetchFamilyDetail(id);
                                if (ctx.mounted) setDetailState(() {});
                                _muatData();
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spasiM),
                    if (anggota.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'Belum ada anggota keluarga terdaftar.',
                            style: TextStyle(color: ctx.teksKedua),
                          ),
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
                              backgroundColor: const Color(0xFF1B7A6A).withValues(
                                alpha: 0.1,
                              ),
                              child: Icon(
                                a['status_keluarga'] == 'Kepala Keluarga'
                                    ? Icons.person_pin_rounded
                                    : Icons.person_outline_rounded,
                                color: const Color(0xFF1B7A6A),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              a['nama']?.toString() ?? '-',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: ctx.teksUtama,
                              ),
                            ),
                            subtitle: Text(
                              'NIK: ${a['nik'] ?? '-'} • ${a['status_keluarga'] ?? 'Anggota'}',
                              style: TextStyle(color: ctx.teksKedua),
                            ),
                            trailing: Chip(
                              label: Text(
                                a['jenis_kelamin']?.toString() == 'L'
                                    ? 'Laki-laki'
                                    : 'Perempuan',
                              ),
                              backgroundColor: ctx.latarLembut,
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: ctx.teksUtama,
                              ),
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
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  foregroundColor: ctx.teksKedua,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Tutup',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _bukaFormTambahAnggota(
    BuildContext context,
    int keluargaId,
    Map<String, dynamic> detailKk,
    VoidCallback onSukses,
  ) async {
    final noKk = detailKk['no_kk']?.toString() ?? '';
    final alamatKk = detailKk['alamat']?.toString() ?? '';
    final statusRumahKk =
        detailKk['status_rumah']?.toString() ?? 'Milik Sendiri';

    final ctlNik = TextEditingController();
    final ctlNama = TextEditingController();
    final ctlHp = TextEditingController();
    final ctlTanggalLahir = TextEditingController();
    String jk = 'L';
    String statusHubungan = 'Anak';
    String statusPerkawinan = 'Belum Menikah';
    String agama = 'Islam';
    String pendidikan = 'SMA/SMK';
    String pekerjaan = 'Belum/Tidak Bekerja';
    bool hasKtp = true;
    final formKey = GlobalKey<FormState>();
    bool sedangSimpan = false;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: ctx.latarKartu,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Color(0xFF1B7A6A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tambah Anggota Keluarga',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: ctx.teksUtama,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No KK: $noKk',
                      style: TextStyle(
                        fontSize: 12,
                        color: ctx.teksKedua,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: lebarDialog(ctx, maksimal: 520),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ctx.latarLembut,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ctx.garis),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Color(0xFF1B7A6A),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Anggota ini akan otomatis terhubung ke KK #$noKk ($alamatKk)',
                              style: TextStyle(
                                fontSize: 12,
                                color: ctx.teksKedua,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: ctlNik,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(16),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Nomor Induk Kependudukan (NIK) *',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'NIK wajib diisi';
                        }
                        if (v.trim().length != 16) {
                          return 'NIK harus 16 digit angka';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: ctlNama,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nama Lengkap *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: jk,
                            dropdownColor: ctx.latarKartu,
                            borderRadius: BorderRadius.circular(12),
                            decoration: const InputDecoration(
                              labelText: 'Jenis Kelamin *',
                              prefixIcon: Icon(Icons.wc_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'L',
                                child: Text(
                                  'Laki-laki',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'P',
                                child: Text(
                                  'Perempuan',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) setModalState(() => jk = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: ctlHp,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(15),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Nomor HP / WA *',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (v) {
                              final teks = v?.trim() ?? '';
                              if (teks.isEmpty) return 'Wajib diisi';
                              if (teks.length < 10) return 'Minimal 10 digit';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: statusHubungan,
                      dropdownColor: ctx.latarKartu,
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        labelText: 'Status Hubungan Keluarga *',
                        prefixIcon: Icon(Icons.family_restroom_outlined),
                      ),
                      items: _opsiStatusHubungan
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => statusHubungan = v);
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.insights_outlined,
                          size: 16,
                          color: Color(0xFF1B7A6A),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'DATA DEMOGRAFI (WAJIB DIISI)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B7A6A),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: ctlTanggalLahir,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Tanggal Lahir *',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Tanggal lahir wajib diisi'
                          : null,
                      onTap: () async {
                        final kini = DateTime.now();
                        final dipilih = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime(kini.year - 20),
                          firstDate: DateTime(1900),
                          lastDate: kini,
                          helpText: 'Pilih Tanggal Lahir',
                        );
                        if (dipilih != null) {
                          ctlTanggalLahir.text =
                              '${dipilih.year.toString().padLeft(4, '0')}-${dipilih.month.toString().padLeft(2, '0')}-${dipilih.day.toString().padLeft(2, '0')}';
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: statusPerkawinan,
                      dropdownColor: ctx.latarKartu,
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        labelText: 'Status Perkawinan *',
                        prefixIcon: Icon(Icons.favorite_outline),
                      ),
                      items: _opsiStatusPerkawinan
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() => statusPerkawinan = v);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: agama,
                      dropdownColor: ctx.latarKartu,
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        labelText: 'Agama *',
                        prefixIcon: Icon(Icons.mosque_outlined),
                      ),
                      items: _opsiAgama
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => agama = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: pendidikan,
                      dropdownColor: ctx.latarKartu,
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        labelText: 'Pendidikan Terakhir *',
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                      items: _opsiPendidikan
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => pendidikan = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: pekerjaan,
                      dropdownColor: ctx.latarKartu,
                      borderRadius: BorderRadius.circular(12),
                      decoration: const InputDecoration(
                        labelText: 'Pekerjaan *',
                        prefixIcon: Icon(Icons.work_outline),
                      ),
                      items: _opsiPekerjaan
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => pekerjaan = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Sudah punya e-KTP?',
                        style: TextStyle(fontSize: 14, color: ctx.teksKedua),
                      ),
                      value: hasKtp,
                      activeTrackColor: const Color(0xFF1B7A6A),
                      onChanged: (val) => setModalState(() => hasKtp = val),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sedangSimpan ? null : () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                foregroundColor: ctx.teksKedua,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Batal',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B7A6A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: sedangSimpan
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setModalState(() => sedangSimpan = true);
                      final provWarga = context.read<WargaProvider>();
                      final result = await provWarga.tambahWargaLengkap({
                        'nik': ctlNik.text.trim(),
                        'nama': ctlNama.text.trim(),
                        'no_kk': noKk,
                        'no_hp': ctlHp.text.trim(),
                        'alamat': alamatKk,
                        'jenis_kelamin': jk,
                        'status_keluarga': statusHubungan,
                        'has_ktp': hasKtp,
                        'tanggal_lahir': ctlTanggalLahir.text.trim(),
                        'status_pernikahan': statusPerkawinan,
                        'agama': agama,
                        'pendidikan': pendidikan,
                        'pekerjaan': pekerjaan,
                        'status_rumah': statusRumahKk,
                      });

                      if (!ctx.mounted) return;
                      setModalState(() => sedangSimpan = false);

                      if (result['success'] == true) {
                        Navigator.pop(ctx, true);
                        onSukses();
                        _pesan(
                          'Anggota keluarga berhasil ditambahkan ke KK.',
                          sukses: true,
                        );
                      } else {
                        _pesan(
                          result['message']?.toString() ??
                              'Gagal menambahkan anggota keluarga.',
                          sukses: false,
                        );
                      }
                    },
              child: sedangSimpan
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Simpan Anggota'),
            ),
          ],
        ),
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
          Text(
            nilai,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: ctx.teksUtama,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _hapusKk(BuildContext context, int id, String noKk) async {
    final prov = context.read<FamilyProvider>();
    final setuju = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.latarKartu,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Hapus Kartu Keluarga?',
          style: TextStyle(
            color: ctx.teksUtama,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus KK $noKk? Data keluarga ini akan dinonaktifkan.',
          style: TextStyle(color: ctx.teksKedua),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              foregroundColor: ctx.teksKedua,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
        _halaman = prov.currentPage;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BannerLihatSaja(kode: _kodeIzin),

        // Top Header and Breadcrumb
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!pakaiKartu(context))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TombolKembali(onPressed: widget.onBack),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.house_outlined,
                        color: Color(0xFF1B7A6A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Kependudukan / Data KK',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
              Wrap(
                spacing: AppTheme.spasiS,
                runSpacing: AppTheme.spasiS,
                children: [
                  _buildActionButton(
                    Icons.description,
                    'Export Excel',
                    const Color(0xFF059669),
                    onTap: () {
                      context.read<FamilyProvider>().downloadExcel();
                    },
                  ),
                  _buildActionButton(
                    Icons.picture_as_pdf,
                    'Export PDF',
                    const Color(0xFFDC2626),
                    onTap: () {
                      context.read<FamilyProvider>().downloadPdf();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spasiM),

        // SECTION: DATA TABLE KK
        Container(
          padding: EdgeInsets.all(paddingKartu(context)),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.garis),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Icon(Icons.list_alt, color: Color(0xFF1B7A6A)),
                    Text(
                      'Detail Data KK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.teksUtama,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${prov.totalData} KK',
                        style: const TextStyle(
                          color: Color(0xFF065F46),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Search bar
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Pencarian',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.teksKedua,
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _ctlCari,
                        style: TextStyle(color: context.teksUtama, fontSize: 13),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          _halaman = 1;
                          _muatData();
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: context.latarLembut,
                          hintStyle: TextStyle(
                            color: context.teksTersier,
                            fontSize: 12,
                          ),
                          hintText: 'Cari No KK, Kepala Keluarga, Alamat...',
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: context.teksKedua,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            onPressed: () {
                              _halaman = 1;
                              _muatData();
                            },
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.garis),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.garis),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF1B7A6A),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _resetFilter,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.teksKedua,
                        side: BorderSide(color: context.garis),
                        visualDensity: VisualDensity.standard,
                        minimumSize: const Size(0, AppTheme.sasaranSentuh),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tabel di dalam container bergaris (seragam dengan Data Warga)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.latarKartu,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.garis),
                ),
                child: Column(
                  children: [
                    Container(
                      constraints: pakaiKartu(context)
                          ? const BoxConstraints()
                          : const BoxConstraints(minHeight: 560),
                      child: prov.isLoading && daftarKK.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _buildKkTable(prov, daftarKK, isBolehUbah, isAdmin),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKkTable(
    FamilyProvider prov,
    List<Map<String, dynamic>> daftarKK,
    bool isBolehUbah,
    bool isAdmin,
  ) {
    return Padding(
      padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
      child: TabelResponsif(
        tinggiBarisMin: 50,
        tinggiBarisMaks: 50,
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
        perPage: prov.perPage,
        onPageChanged: (hal) {
          _halaman = hal;
          _muatData();
        },
        baris: daftarKK.asMap().entries.map((ent) {
          final idx = ent.key;
          final item = ent.value;
          final noKk = item['no_kk']?.toString() ?? '-';
          final id = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
          final alamat = item['alamat']?.toString() ?? '-';
          final kepala = item['kepala_keluarga']?.toString() ?? '-';
          final statusRumah =
              item['status_rumah']?.toString() ?? 'Milik Sendiri';
          final jumlahAnggota =
              int.tryParse(item['jumlah_anggota']?.toString() ?? '0') ?? 0;
          final terkonfirmasi =
              item['kepala_terkonfirmasi'] == true ||
              item['terkonfirmasi'] == true;

          return BarisTabel(
            sel: [
              SelTabel.teks(
                'NO',
                (((_halaman - 1) * prov.perPage) + idx + 1).toString(),
                sembunyiDiKartu: true,
                gaya: TextStyle(color: context.teksUtama, fontSize: 13),
              ),
              SelTabel.teks(
                'NO KK',
                noKk,
                gaya: const TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SelTabel(
                'KEPALA KELUARGA',
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kepala,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.teksUtama,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (!terkonfirmasi)
                      Tooltip(
                        message:
                            'Nama Kepala Keluarga belum terkonfirmasi',
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: Colors.amber[700],
                        ),
                      ),
                  ],
                ),
                utama: true,
              ),
              SelTabel.teks(
                'ALAMAT & BLOK',
                alamat,
                gaya: TextStyle(color: context.teksUtama, fontSize: 13),
              ),
              SelTabel(
                'ANGGOTA',
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: jumlahAnggota == 0
                        ? const Color(0xFFFEF3C7)
                        : AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    jumlahAnggota == 0
                        ? '0 Orang (KK Kosong)'
                        : '$jumlahAnggota Orang',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: jumlahAnggota == 0
                          ? const Color(0xFFD97706)
                          : AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
              SelTabel(
                'STATUS RUMAH',
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                      color: statusRumah == 'Milik Sendiri'
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
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
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 20,
                    ),
                    color: const Color(0xFF3B82F6),
                    style: _gayaAksiTabel(const Color(0xFF3B82F6)),
                    onPressed: () => _bukaDetailKk(context, id, noKk),
                  ),
                  if (isBolehUbah) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Edit KK',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      color: const Color(0xFF0F766E),
                      style: _gayaAksiTabel(const Color(0xFF0F766E)),
                      onPressed: () => _bukaFormEdit(context, item),
                    ),
                  ],
                  if (isAdmin) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Hapus KK',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                      ),
                      color: const Color(0xFFEF4444),
                      style: _gayaAksiTabel(const Color(0xFFEF4444)),
                      onPressed: () => _hapusKk(context, id, noKk),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    final tombol = ElevatedButton.icon(
      onPressed: onTap ?? () {},
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spasiL),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusS),
      ),
    );

    if (!pakaiKartu(context)) return tombol;

    final lebarLayar = MediaQuery.of(context).size.width;
    final lebarTombol = (lebarLayar - paddingKonten(context) * 2 - AppTheme.spasiS) / 2;
    return SizedBox(width: lebarTombol, child: tombol);
  }
}
