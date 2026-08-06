import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/responsif.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/letter_provider.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

class LetterRequestScreen extends StatefulWidget {
  const LetterRequestScreen({super.key});
  @override
  State<LetterRequestScreen> createState() => _LetterRequestScreenState();
}

class _LetterRequestScreenState extends State<LetterRequestScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LetterProvider>().fetchLetters();
  }

  void _showCreateDialog() {
    final jenisSuratController = TextEditingController();
    final keperluanController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.mark_email_unread_rounded, color: Color(0xFF1B7A6A), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ajukan Surat Pengantar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.teksUtama),
                  ),
                  Text(
                    'Isi formulir berikut untuk mengajukan surat ke RT',
                    style: TextStyle(fontSize: 12, color: context.teksKedua),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: lebarDialog(context, maksimal: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Jenis Surat',
                    prefixIcon: Icon(Icons.description),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Surat Pengantar Umum',
                      child: Text('Surat Pengantar Umum'),
                    ),
                    DropdownMenuItem(
                      value: 'Surat Keterangan Domisili',
                      child: Text('Surat Keterangan Domisili'),
                    ),
                    DropdownMenuItem(
                      value: 'Surat Keterangan Tidak Mampu',
                      child: Text('Surat Keterangan Tidak Mampu'),
                    ),
                    DropdownMenuItem(
                      value: 'Surat Keterangan Usaha',
                      child: Text('Surat Keterangan Usaha'),
                    ),
                    DropdownMenuItem(
                      value: 'Surat Pengantar KTP/KK',
                      child: Text('Surat Pengantar KTP/KK'),
                    ),
                    DropdownMenuItem(
                      value: 'Surat Pengantar Nikah',
                      child: Text('Surat Pengantar Nikah'),
                    ),
                    DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
                  ],
                  onChanged: (v) => jenisSuratController.text = v ?? '',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: keperluanController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Keperluan / Keterangan *',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (jenisSuratController.text.isEmpty || keperluanController.text.isEmpty) {
                pesanGagal(context, 'Jenis surat dan keperluan wajib diisi');
                return;
              }
              final provider = context.read<LetterProvider>();
              final success = await provider.createLetter(
                jenisSurat: jenisSuratController.text,
                keperluan: keperluanController.text,
              );
              if (success) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  pesanSukses(context, 'Pengajuan surat berhasil dikirim!');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B7A6A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('KIRIM PENGAJUAN'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'diajukan':
        return AppTheme.warningColor;
      case 'diproses':
        return AppTheme.infoColor;
      case 'disetujui':
        return AppTheme.successColor;
      case 'ditolak':
        return AppTheme.dangerColor;
      default:
        return AppTheme.textSecondary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'diajukan':
        return Icons.schedule;
      case 'diproses':
        return Icons.hourglass_top;
      case 'disetujui':
        return Icons.check_circle;
      case 'ditolak':
        return Icons.cancel;
      default:
        return Icons.mail;
    }
  }

  @override
  Widget build(BuildContext context) {
    final letterProvider = context.watch<LetterProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Riwayat & Status Surat',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.teksKedua,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajukan Surat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B7A6A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Content
        letterProvider.isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            : letterProvider.letters.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mail_outline,
                        size: 64,
                        color: AppTheme.textSecondary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Belum ada pengajuan surat',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: letterProvider.letters.length,
                itemBuilder: (ctx, i) {
                  final letter = letterProvider.letters[i];
                  final color = _statusColor(letter.status);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.latarKartu,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_statusIcon(letter.status), color: color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    letter.jenisSurat,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    DateFormat(
                                      'dd MMM yyyy HH:mm',
                                    ).format(letter.tanggalPengajuan),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                letter.statusLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keperluan: ${letter.keperluan}',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (letter.responseNote != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Catatan: ${letter.responseNote}',
                            style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }
}
