const PDFDocument = require('pdfkit');

function rupiah(num) {
  const n = Math.round(Number(num) || 0);
  return `Rp ${new Intl.NumberFormat('id-ID').format(n)}`;
}

function formatTanggal(d) {
  if (!d) return '-';
  const t = new Date(d);
  if (isNaN(t.getTime())) return '-';
  return t.toLocaleDateString('id-ID', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }) + ' WIB';
}

function generatePaymentPDF(payment, outputStream) {
  // Ukuran A5 (419.53 x 595.28 pt)
  const doc = new PDFDocument({
    size: 'A5',
    margin: 0,
  });

  doc.pipe(outputStream);

  const PAGE_WIDTH = 419.53;
  const MARGIN_X = 25;
  const CONTENT_WIDTH = PAGE_WIDTH - (MARGIN_X * 2); // 369.53

  // 1. Header Banner
  doc.rect(0, 0, PAGE_WIDTH, 55).fill('#1B7A6A');
  doc.fillColor('#FFFFFF')
    .fontSize(14)
    .font('Helvetica-Bold')
    .text('KUITANSI PEMBAYARAN RESMI', 0, 14, { align: 'center', width: PAGE_WIDTH });
  doc.fillColor('#E6F4F1')
    .fontSize(8)
    .font('Helvetica')
    .text('Sistem Manajemen RT Terintegrasi', 0, 33, { align: 'center', width: PAGE_WIDTH });

  let y = 68;

  // 2. Subheader Bar (Invoice Info & Badge Status Lunas)
  doc.fillColor('#1E293B')
    .fontSize(10)
    .font('Helvetica-Bold')
    .text(`INVOICE: ${payment.invoice_number || '-'}`, MARGIN_X, y);

  // Badge Status LUNAS (Kanan)
  const badgeW = 60;
  const badgeH = 16;
  const badgeX = MARGIN_X + CONTENT_WIDTH - badgeW;
  doc.roundedRect(badgeX, y - 2, badgeW, badgeH, 4)
    .fillAndStroke('#DCFCE7', '#86EFAC');
  doc.fillColor('#166534')
    .fontSize(8)
    .font('Helvetica-Bold')
    .text('LUNAS', badgeX, y + 2, { align: 'center', width: badgeW });

  y += 24;

  // Line separator
  doc.moveTo(MARGIN_X, y).lineTo(MARGIN_X + CONTENT_WIDTH, y).strokeColor('#E2E8F0').lineWidth(1).stroke();
  y += 10;

  // 3. Info Warga & Info Transaksi (Dua Kolom)
  const boxW = (CONTENT_WIDTH - 15) / 2; // 177 pt
  const boxH = 65;

  // Box Warga (Kiri)
  doc.roundedRect(MARGIN_X, y, boxW, boxH, 6).fillAndStroke('#F8FAFC', '#E2E8F0');
  doc.fillColor('#0F172A').fontSize(8).font('Helvetica-Bold').text('PENERIMA TAGIHAN', MARGIN_X + 8, y + 8);
  doc.fillColor('#334155').fontSize(8).font('Helvetica');
  doc.text(`Nama    : ${payment.nama_warga || '-'}`, MARGIN_X + 8, y + 20, { width: boxW - 16 });
  doc.text(`No. KK  : ${payment.no_kk || '-'}`, MARGIN_X + 8, y + 32, { width: boxW - 16 });
  const lokasi = [
    payment.blok ? `Blok ${payment.blok}` : null,
    payment.rt ? `RT ${payment.rt}` : null,
    payment.rw ? `RW ${payment.rw}` : null,
    payment.alamat,
  ].filter(Boolean).join(', ');
  doc.text(`Alamat  : ${lokasi || '-'}`, MARGIN_X + 8, y + 44, { width: boxW - 16, height: 16, ellipsis: true });

  // Box Transaksi (Kanan)
  const rightX = MARGIN_X + boxW + 15;
  doc.roundedRect(rightX, y, boxW, boxH, 6).fillAndStroke('#F8FAFC', '#E2E8F0');
  doc.fillColor('#0F172A').fontSize(8).font('Helvetica-Bold').text('RINCIAN TRANSAKSI', rightX + 8, y + 8);
  doc.fillColor('#334155').fontSize(8).font('Helvetica');
  doc.text(`Periode   : ${payment.bulan || '-'}`, rightX + 8, y + 20);
  doc.text(`Metode   : ${(payment.metode_bayar || 'Online').toUpperCase()}`, rightX + 8, y + 32);
  doc.text(`Waktu     : ${formatTanggal(payment.paid_at)}`, rightX + 8, y + 44, { width: boxW - 16, ellipsis: true });

  y += boxH + 15;

  // 4. Tabel Rincian Pembayaran
  doc.fillColor('#0F172A').fontSize(9).font('Helvetica-Bold').text('RINCIAN BIAYA', MARGIN_X, y);
  y += 14;

  // Header Tabel
  const col1W = 160;
  const col2W = 110;
  const col3W = CONTENT_WIDTH - col1W - col2W; // 99 pt

  doc.rect(MARGIN_X, y, CONTENT_WIDTH, 18).fill('#F1F5F9');
  doc.fillColor('#475569').fontSize(8).font('Helvetica-Bold');
  doc.text('POS PEMBAYARAN', MARGIN_X + 6, y + 5, { width: col1W - 6 });
  doc.text('RINCIAN PEMAKAIAN', MARGIN_X + col1W, y + 5, { width: col2W });
  doc.text('JUMLAH', MARGIN_X + col1W + col2W, y + 5, { width: col3W - 6, align: 'right' });
  y += 18;

  // Baris-baris rincian
  const meteranLalu = payment.meteran_lalu;
  const meteranKini = payment.meteran_sekarang;
  const tarifM3 = payment.tarif_per_m3 || 0;
  const terpakai = (meteranLalu != null && meteranKini != null) ? Math.max(0, meteranKini - meteranLalu) : 0;
  const biayaAir = terpakai * tarifM3;
  const abondement = payment.abondement || 0;
  const biayaSampah = (payment.langganan_sampah === true && payment.biaya_sampah) ? payment.biaya_sampah : 0;

  const items = [];
  if (meteranLalu != null || meteranKini != null || tarifM3 > 0) {
    items.push({
      pos: 'Air Artesis (Pemakaian)',
      rincian: `${meteranLalu ?? '-'} → ${meteranKini ?? '-'} (${terpakai} m³ × ${rupiah(tarifM3)})`,
      total: rupiah(biayaAir),
    });
    items.push({
      pos: 'Biaya Abondement',
      rincian: 'Tarif Tetap',
      total: rupiah(abondement),
    });
    if (biayaSampah > 0) {
      items.push({
        pos: 'Layanan Sampah',
        rincian: 'Layanan Kebersihan',
        total: rupiah(biayaSampah),
      });
    }
  } else {
    items.push({
      pos: payment.jenis_tagihan || 'Iuran RT',
      rincian: `Periode ${payment.bulan}`,
      total: rupiah(payment.jumlah_bayar || payment.nominal),
    });
  }

  doc.font('Helvetica').fontSize(8);
  items.forEach((item, idx) => {
    const rowBg = idx % 2 === 0 ? '#FFFFFF' : '#F8FAFC';
    doc.rect(MARGIN_X, y, CONTENT_WIDTH, 18).fill(rowBg);
    doc.fillColor('#1E293B');
    doc.text(item.pos, MARGIN_X + 6, y + 5, { width: col1W - 6 });
    doc.text(item.rincian, MARGIN_X + col1W, y + 5, { width: col2W });
    doc.text(item.total, MARGIN_X + col1W + col2W, y + 5, { width: col3W - 6, align: 'right' });
    y += 18;
  });

  // Line separator
  doc.moveTo(MARGIN_X, y).lineTo(MARGIN_X + CONTENT_WIDTH, y).strokeColor('#CBD5E1').lineWidth(0.5).stroke();
  y += 6;

  // Total Row Highlight
  const totalBoxH = 24;
  doc.roundedRect(MARGIN_X, y, CONTENT_WIDTH, totalBoxH, 4).fillAndStroke('#F0FDF4', '#1B7A6A');
  doc.fillColor('#166534').fontSize(9).font('Helvetica-Bold').text('TOTAL PEMBAYARAN LUNAS', MARGIN_X + 10, y + 7);
  doc.fillColor('#1B7A6A').fontSize(11).font('Helvetica-Bold').text(rupiah(payment.jumlah_bayar || payment.nominal), MARGIN_X, y + 6, {
    width: CONTENT_WIDTH - 10,
    align: 'right',
  });

  y += totalBoxH + 20;

  // 5. Catatan & Stempel Digital
  doc.fillColor('#64748B').fontSize(7).font('Helvetica');
  doc.text('Catatan:', MARGIN_X, y);
  doc.text('1. Bukti pembayaran ini diterbitkan secara otomatis dan sah tanpa tanda tangan fisik.', MARGIN_X, y + 9);
  doc.text('2. Harap simpan dokumen digital ini sebagai bukti pelunasan iuran RT yang sah.', MARGIN_X, y + 17);

  // Stempel Digital (Watermark/Cap di kanan bawah)
  const stampX = MARGIN_X + CONTENT_WIDTH - 100;
  const stampY = y - 5;
  doc.roundedRect(stampX, stampY, 95, 30, 4).lineWidth(1).strokeColor('#10B981').stroke();
  doc.fillColor('#059669').fontSize(7).font('Helvetica-Bold').text('SELESAI & LUNAS', stampX, stampY + 6, { align: 'center', width: 95 });
  doc.fillColor('#10B981').fontSize(6).font('Helvetica').text('SISTEM MANAJEMEN RT', stampX, stampY + 16, { align: 'center', width: 95 });

  doc.end();
}

module.exports = { generatePaymentPDF };
