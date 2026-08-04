import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/responsif.dart';
import '../../widgets/tabel_responsif.dart';
import '../../core/services/auth_service.dart';
import '../../providers/letter_provider.dart';
import '../../widgets/responsive_layout.dart';
import 'package:intl/intl.dart';
import '../../models/letter_model.dart';
import '../../core/services/pdf_service.dart';
import '../../providers/permission_provider.dart';
import '../../core/theme/warna_konteks.dart';

/// Kode modul di tabel izin.
///
/// Ketua RT sengaja `view + update`: ia menandatangani surat, bukan
/// mengajukannya. Warga `view + create`: mengajukan, tanpa bisa menyetujui.
const String _kodeIzin = 'layanan.surat';

class SuratMenyuratScreen extends StatefulWidget {
  const SuratMenyuratScreen({super.key});

  @override
  State<SuratMenyuratScreen> createState() => _SuratMenyuratScreenState();
}

class _SuratMenyuratScreenState extends State<SuratMenyuratScreen> {
  bool get _bolehAjukan => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehSetujui => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);

  bool _isFormView = false;
  String? _selectedJenisSurat;
  final TextEditingController _keperluanController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LetterProvider>().fetchLetters();
    });
  }

  @override
  void dispose() {
    _keperluanController.dispose();
    super.dispose();
  }

  void _submitLetter() async {
    if (_selectedJenisSurat == null || _keperluanController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lengkapi form terlebih dahulu')));
      return;
    }

    final provider = context.read<LetterProvider>();
    final success = await provider.createLetter(
      jenisSurat: _selectedJenisSurat!,
      keperluan: _keperluanController.text,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permohonan berhasil diajukan')));
      setState(() => _isFormView = false);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Gagal mengajukan')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.read<AuthService>().userRole;
    final isPengurus = role != 'warga';

    if (_isFormView) return _buildFormView();

    if (isPengurus) {
      return _buildAdminView();
    } else {
      return _buildWargaView();
    }
  }

  // ================= ADMIN VIEW =================
  Widget _buildAdminView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.description_outlined, color: Color(0xFF1B7A6A), size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Layanan Warga / Surat Menyurat',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.teksKedua,
                  ),
                ),
              ],
            ),
            if (_bolehAjukan)
              ElevatedButton.icon(
                onPressed: () => setState(() => _isFormView = true),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Ajukan Surat Saya', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B7A6A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),

        const SizedBox(height: 24),

        // Table
        Consumer<LetterProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.letters.isEmpty) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: context.latarKartu,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.garis),
                ),
                child: const Center(child: Text('Belum ada permohonan surat')),
              );
            }

            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.latarKartu,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.garis),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                    child: TabelResponsif(
                      tinggiBarisMaks: 60,
                      kolom: const ['NO', 'TANGGAL', 'NAMA PEMOHON', 'JENIS SURAT', 'STATUS'],
                      baris: provider.letters.asMap().entries.map((entry) {
                        final index = entry.key + 1;
                        final data = entry.value;
                        final status = data.status.toLowerCase();
                        Color statusColor = const Color(0xFFF59E0B);
                        Color statusBg = const Color(0xFFFEF3C7);
                        String statusLabel = 'Menunggu';

                        if (status == 'disetujui') {
                          statusColor = const Color(0xFF10B981);
                          statusBg = const Color(0xFFD1FAE5);
                          statusLabel = 'Disetujui';
                        } else if (status == 'ditolak') {
                          statusColor = const Color(0xFFEF4444);
                          statusBg = const Color(0xFFFEE2E2);
                          statusLabel = 'Ditolak';
                        } else if (status == 'diajukan' ||
                            status == 'diproses' ||
                            status == 'pending') {
                          statusLabel = 'Diajukan';
                        }

                        return BarisTabel(
                          sel: [
                            SelTabel.teks(
                              'NO',
                              '$index',
                              sembunyiDiKartu: true,
                              gaya: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.teksKedua,
                              ),
                            ),
                            SelTabel.teks(
                              'TANGGAL',
                              DateFormat('dd MMM yyyy').format(data.tanggalPengajuan),
                              gaya: TextStyle(fontSize: 14, color: context.teksKedua),
                            ),
                            SelTabel.teks(
                              'NAMA PEMOHON',
                              data.namaPemohon ?? 'User ${data.userId}',
                              utama: true,
                              gaya: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.teksUtama,
                              ),
                            ),
                            SelTabel.teks(
                              'JENIS SURAT',
                              data.jenisSurat,
                              gaya: TextStyle(fontSize: 14, color: context.teksUtama),
                            ),
                            SelTabel(
                              'STATUS',
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          aksi: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_bolehSetujui &&
                                  (status == 'diajukan' ||
                                      status == 'diproses' ||
                                      status == 'pending')) ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    color: Color(0xFF10B981),
                                  ),
                                  tooltip: 'Setujui',
                                  onPressed: () =>
                                      provider.updateLetterStatus(data.id, 'disetujui'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444)),
                                  tooltip: 'Tolak',
                                  onPressed: () => provider.updateLetterStatus(
                                    data.id,
                                    'ditolak',
                                    responseNote: 'Ditolak admin',
                                  ),
                                ),
                              ] else if (status != 'diajukan' &&
                                  status != 'diproses' &&
                                  status != 'pending') ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    color: Color(0xFF3B82F6),
                                  ),
                                  tooltip: 'Download PDF',
                                  onPressed: () => PdfService.downloadLetterPdf(data),
                                ),
                              ],
                              IconButton(
                                icon: Icon(
                                  Icons.remove_red_eye_outlined,
                                  color: context.teksKedua,
                                ),
                                tooltip: 'Lihat Detail',
                                onPressed: () => _showDetailSurat(data),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ================= WARGA VIEW =================
  Widget _buildWargaView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 16,
            children: [
              if (!pakaiKartu(context))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B7A6A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.description_outlined, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Permohonan Surat',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: context.teksUtama,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Layanan Warga / Surat Menyurat / Permohonan',
                            style: TextStyle(fontSize: 12, color: context.teksKedua),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              // Ketua RT menandatangani surat, tidak mengajukannya — jadi
              // tombol ini menuntut `create`, bukan sekadar akses modul.
              if (_bolehAjukan)
                ElevatedButton.icon(
                  onPressed: () => setState(() => _isFormView = true),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Ajukan Surat',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Consumer<LetterProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.letters.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 100),
                decoration: BoxDecoration(
                  color: context.latarKartu,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.garis),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.description_outlined, size: 48, color: context.teksTersier),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada permohonan surat',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.teksUtama,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_bolehAjukan)
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _isFormView = true),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text(
                            'Ajukan Surat',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.latarKartu,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.garis),
              ),
              child: Padding(
                padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
                child: TabelResponsif(
                  tinggiBarisMaks: 60,
                  kolom: const ['NO', 'TANGGAL', 'JENIS SURAT', 'STATUS', 'KETERANGAN'],
                  baris: provider.letters.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final data = entry.value;
                    final status = data.status.toLowerCase();
                    Color statusColor = const Color(0xFFF59E0B);
                    Color statusBg = const Color(0xFFFEF3C7);
                    String statusLabel = 'Menunggu';

                    if (status == 'disetujui') {
                      statusColor = const Color(0xFF10B981);
                      statusBg = const Color(0xFFD1FAE5);
                      statusLabel = 'Disetujui';
                    } else if (status == 'ditolak') {
                      statusColor = const Color(0xFFEF4444);
                      statusBg = const Color(0xFFFEE2E2);
                      statusLabel = 'Ditolak';
                    } else if (status == 'diajukan' ||
                        status == 'diproses' ||
                        status == 'pending') {
                      statusLabel = 'Diajukan';
                    }

                    return BarisTabel(
                      sel: [
                        SelTabel.teks(
                          'NO',
                          '$index',
                          sembunyiDiKartu: true,
                          gaya: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: context.teksKedua,
                          ),
                        ),
                        SelTabel.teks(
                          'TANGGAL',
                          DateFormat('dd MMM yyyy').format(data.tanggalPengajuan),
                          gaya: TextStyle(fontSize: 14, color: context.teksKedua),
                        ),
                        SelTabel.teks(
                          'JENIS SURAT',
                          data.jenisSurat,
                          utama: true,
                          gaya: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.teksUtama,
                          ),
                        ),
                        SelTabel(
                          'STATUS',
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ),
                        SelTabel.teks(
                          'KETERANGAN',
                          data.responseNote ?? '-',
                          gaya: TextStyle(fontSize: 14, color: context.teksKedua),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFormView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7A6A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.description_outlined, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ajukan Permohonan Surat',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: context.teksUtama,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Layanan Warga / Surat Menyurat / Ajukan',
                    style: TextStyle(fontSize: 12, color: context.teksKedua),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        _buildResponsiveSplit(
          leftFlex: 2,
          rightFlex: 1,
          left: Container(
            decoration: BoxDecoration(
              color: context.latarKartu,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.garis),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Form Header
                Container(
                  padding: EdgeInsets.all(paddingKartu(context)),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description, size: 18, color: Color(0xFF1B7A6A)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Detail Permohonan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B7A6A),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Lengkapi data untuk mengajukan surat',
                              style: TextStyle(fontSize: 12, color: Color(0xFF0F766E)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Jenis Surat'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: context.garis),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedJenisSurat,
                            isExpanded: true,
                            hint: const Text('Pilih jenis surat'),
                            items:
                                [
                                  'Surat Keterangan Domisili',
                                  'Surat Pengantar KTP',
                                  'Surat Pengantar SKCK',
                                  'Surat Keterangan Usaha',
                                  'Surat Keterangan Tidak Mampu',
                                ].map((String value) {
                                  return DropdownMenuItem<String>(value: value, child: Text(value));
                                }).toList(),
                            onChanged: (newValue) {
                              setState(() => _selectedJenisSurat = newValue);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      _buildLabel('Keperluan / Keterangan'),
                      TextFormField(
                        controller: _keperluanController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Tuliskan rincian keperluan surat ini dibuat...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.garis),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: context.garis),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Blok "Dokumen Pendukung" dihapus: tidak ada endpoint
                      // unggah berkas, tidak ada kolom penyimpanannya, dan
                      // tombol Browse File memang tidak pernah berfungsi.
                      const SizedBox(height: 32),

                      // Actions
                      Consumer<LetterProvider>(
                        builder: (context, provider, _) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => setState(() => _isFormView = false),
                                child: Text(
                                  'Batal',
                                  style: TextStyle(color: context.teksKedua),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: provider.isLoading ? null : _submitLetter,
                                icon: provider.isLoading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send, size: 14),
                                label: Text(
                                  provider.isLoading ? 'Menyimpan...' : 'Ajukan Sekarang',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          right: _buildInfoCard(),
        ),
      ],
    );
  }

  void _showDetailSurat(LetterModel data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.description, color: Color(0xFF1B7A6A)),
            const SizedBox(width: 8),
            const Text(
              'Detail Permohonan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: lebarDialog(context, maksimal: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Tipe Surat', data.jenisSurat),
                _detailRow('Pemohon', data.namaPemohon ?? 'User ${data.userId}'),
                _detailRow('Alamat', data.alamat ?? '-'),
                _detailRow('No KK', data.noKk ?? '-'),
                _detailRow(
                  'Tanggal',
                  DateFormat('dd MMM yyyy, HH:mm').format(data.tanggalPengajuan),
                ),
                const Divider(height: 24),
                Text('Keperluan:', style: TextStyle(fontSize: 12, color: context.teksKedua)),
                const SizedBox(height: 4),
                Text(data.keperluan, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                if (data.responseNote != null) ...[
                  const Divider(height: 24),
                  Text('Catatan Respon:', style: TextStyle(fontSize: 12, color: context.teksKedua)),
                  const SizedBox(height: 4),
                  Text(
                    data.responseNote!,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () => PdfService.downloadLetterPdf(data),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download / Cetak PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 13, color: context.teksKedua)),
          ),
          Text(':', style: TextStyle(fontSize: 13, color: context.teksKedua)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.teksUtama),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(paddingKartu(context)),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
              SizedBox(width: 8),
              Text(
                'Informasi Pengajuan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoItem('Waktu Proses', 'Maksimal 1x24 jam hari kerja setelah disubmit.'),
          const SizedBox(height: 12),
          _buildInfoItem('Tanda Tangan', 'Surat akan ditandatangani secara digital oleh Ketua RT.'),
          const SizedBox(height: 12),
          _buildInfoItem(
            'Pengambilan',
            'Surat yang sudah selesai (PDF) dapat diunduh langsung dari aplikasi, tidak perlu cetak fisik kecuali diperlukan.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF92400E),
          ),
        ),
        const SizedBox(height: 4),
        Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFFB45309), height: 1.4)),
      ],
    );
  }

  Widget _buildResponsiveSplit({
    required int leftFlex,
    required int rightFlex,
    required Widget left,
    required Widget right,
  }) {
    if (ResponsiveLayout.isMobile(context)) {
      return Column(children: [left, const SizedBox(height: 24), right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        const SizedBox(width: 24),
        Expanded(flex: rightFlex, child: right),
      ],
    );
  }
}
