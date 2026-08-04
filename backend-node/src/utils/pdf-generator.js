const PDFDocument = require('pdfkit');

function generatePaymentPDF(payment, outputStream) {
  const doc = new PDFDocument({ size: 'A5', margin: 40 });
  doc.pipe(outputStream);

  // Header
  doc.fontSize(18).font('Helvetica-Bold').text('KWITANSI PEMBAYARAN', { align: 'center' });
  doc.fontSize(10).font('Helvetica').text('Smart Community Management Platform RT', { align: 'center' });
  doc.moveDown(0.5);
  doc.moveTo(40, doc.y).lineTo(360, doc.y).stroke();
  doc.moveDown(1);

  // Invoice info
  doc.fontSize(10).font('Helvetica-Bold').text(`No. Invoice: ${payment.invoice_number}`);
  doc.font('Helvetica').text(`Tanggal: ${new Date(payment.paid_at).toLocaleDateString('id-ID', { day: 'numeric', month: 'long', year: 'numeric' })}`);
  doc.moveDown(1);

  // Detail
  doc.font('Helvetica-Bold').text('Detail Pembayaran:');
  doc.moveDown(0.3);
  doc.font('Helvetica');
  doc.text(`Nama Warga   : ${payment.nama_warga || '-'}`);
  doc.text(`Alamat        : ${payment.alamat || '-'}`);
  doc.text(`No. KK        : ${payment.no_kk || '-'}`);
  doc.moveDown(0.5);
  doc.text(`Jenis Tagihan : ${payment.jenis_tagihan}`);
  doc.text(`Periode       : ${payment.bulan}`);
  doc.text(`Metode Bayar  : ${payment.metode_bayar}`);
  doc.moveDown(0.5);

  // Amount
  doc.moveTo(40, doc.y).lineTo(360, doc.y).stroke();
  doc.moveDown(0.5);
  const formattedAmount = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', minimumFractionDigits: 0 }).format(payment.jumlah_bayar);
  doc.fontSize(14).font('Helvetica-Bold').text(`Total: ${formattedAmount}`, { align: 'right' });
  doc.moveDown(0.5);
  doc.moveTo(40, doc.y).lineTo(360, doc.y).stroke();
  doc.moveDown(1);

  // Footer
  doc.fontSize(8).font('Helvetica').text('Dokumen ini digenerate secara otomatis oleh sistem Smart Community RT.', { align: 'center' });
  doc.text('Kwitansi ini sah tanpa tanda tangan.', { align: 'center' });

  doc.end();
}

module.exports = { generatePaymentPDF };
