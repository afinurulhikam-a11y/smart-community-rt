import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../models/letter_model.dart';

class PdfService {
  static Future<void> downloadLetterPdf(LetterModel letter) async {
    final pdf = pw.Document();

    final dateStr = DateFormat('dd MMMM yyyy').format(letter.tanggalPengajuan);
    final responseDateStr = letter.tanggalRespon != null
        ? DateFormat('dd MMMM yyyy').format(letter.tanggalRespon!)
        : dateStr;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header / Kop Surat
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'PEMERINTAH KOTA MALANG',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'KECAMATAN BLIMBING - KELURAHAN PURWANTORO',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'RUKUN TETANGGA 05 / RUKUN WARGA 02',
                      style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Jl. Purwantoro No. 05 Malang - Jawa Timur 65122',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 16),

              // Title
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      letter.jenisSurat.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Nomor: 005/RT05-RW02/SURAT/${letter.id.substring(0, 6).toUpperCase()}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Body
              pw.Text(
                'Yang bertanda tangan di bawah ini, Ketua RT 05 RW 02 Kelurahan Purwantoro, Kecamatan Blimbing, Kota Malang, menerangkan dengan sebenarnya bahwa:',
                style: const pw.TextStyle(fontSize: 11, height: 1.5),
              ),
              pw.SizedBox(height: 16),

              // Table / Detail
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildFieldRow('Nama Pemohon', letter.namaPemohon ?? 'Warga RT 05'),
                    pw.SizedBox(height: 6),
                    _buildFieldRow('Jenis Surat', letter.jenisSurat),
                    pw.SizedBox(height: 6),
                    _buildFieldRow('Keperluan', letter.keperluan),
                    pw.SizedBox(height: 6),
                    _buildFieldRow('Tanggal Pengajuan', dateStr),
                    pw.SizedBox(height: 6),
                    _buildFieldRow('Status Surat', letter.status.toUpperCase()),
                    if (letter.responseNote != null && letter.responseNote!.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      _buildFieldRow('Catatan Pengurus', letter.responseNote!),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Text(
                'Demikian surat pengantar ini dibuat dengan sebenarnya untuk dapat dipergunakan sebagaimana mestinya.',
                style: const pw.TextStyle(fontSize: 11, height: 1.5),
              ),
              pw.SizedBox(height: 40),

              // Footer / Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Pemohon,', style: const pw.TextStyle(fontSize: 11)),
                      pw.SizedBox(height: 50),
                      pw.Text(
                        letter.namaPemohon ?? 'Pemohon',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Malang, $responseDateStr', style: const pw.TextStyle(fontSize: 11)),
                      pw.Text('Ketua RT 05 RW 02,', style: const pw.TextStyle(fontSize: 11)),
                      pw.SizedBox(height: 50),
                      pw.Text(
                        '( H. Sugianto )',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Surat_${letter.jenisSurat.replaceAll(' ', '_')}_${letter.id.substring(0, 4)}.pdf',
    );
  }

  static pw.Widget _buildFieldRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 130, child: pw.Text(label, style: const pw.TextStyle(fontSize: 11))),
        pw.Text(':  ', style: const pw.TextStyle(fontSize: 11)),
        pw.Expanded(
          child: pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    );
  }
}
