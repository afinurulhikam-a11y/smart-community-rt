import 'package:flutter/foundation.dart';

/// Model intent notifikasi FCM yang telah divalidasi dan siap dirutekan.
@immutable
class NotificationIntent {
  /// Tipe entitas (misal: 'announcement', 'emergency', 'complaint', 'letter',
  /// 'bill', 'payment', 'agenda', 'inventory', 'visitor', 'polling', 'bansos').
  final String entityType;

  /// Aksi spesifik dari backend (misal: 'ALARM_TRIGGERED', 'NEW_COMPLAINT',
  /// 'COMPLAINT_REPLIED', 'NEW_LETTER_REQUEST', 'LETTER_STATUS_CHANGED',
  /// 'NEW_BILL', 'PAYMENT_SUCCESS', 'NEW_AGENDA', 'BORROWING_STATUS_CHANGED',
  /// 'VISITOR_ARRIVED', 'NEW_POLLING', 'BANSOS_STATUS_UPDATE').
  final String? action;

  /// ID entitas (misal ID tagihan, ID surat, ID aduan, ID alarm, dsb.).
  final String? entityId;

  /// Indeks menu target pada MainDashboard (misal: 0, 13, 21, 32, 43, 44, 50, 60, 61, 62).
  final int targetMenuIndex;

  /// Indeks tab target pada layar tujuan (bila layar mendukung multi-tab seperti Agenda / Bill).
  final int? targetTabIndex;

  /// ID unik pesan FCM (bila ada) untuk keperluan deduplikasi.
  final String? messageId;

  /// Judul notifikasi untuk tampilan in-app UI.
  final String title;

  /// Isi pesan/deskripsi notifikasi untuk tampilan in-app UI.
  final String body;

  /// Payload data mentah dari FCM.
  final Map<String, dynamic> rawPayload;

  /// Waktu pembuatan intent di sisi klien.
  final DateTime timestamp;

  const NotificationIntent({
    required this.entityType,
    this.action,
    this.entityId,
    required this.targetMenuIndex,
    this.targetTabIndex,
    this.messageId,
    this.title = '',
    this.body = '',
    this.rawPayload = const {},
    required this.timestamp,
  });

  /// Signature unik untuk mencegah eksekusi ganda pada payload yang sama.
  String get deduplicationKey {
    if (messageId != null && messageId!.isNotEmpty) {
      return messageId!;
    }
    final act = action ?? '';
    final id = entityId ?? '';
    final timeStr = rawPayload['created_at']?.toString() ??
        rawPayload['updated_at']?.toString() ??
        rawPayload['settled_at']?.toString() ??
        timestamp.millisecondsSinceEpoch.toString();
    return '$entityType:$act:$id:$timeStr';
  }

  /// Membuat judul default yang ramah bagi pengguna jika notification block tidak disertakan.
  static String generateFallbackTitle(String entityType, String? action) {
    switch (entityType.toLowerCase()) {
      case 'emergency':
        return action == 'ALARM_CANCELLED'
            ? 'Peringatan Darurat Selesai'
            : 'Peringatan Darurat Warga';
      case 'complaint':
        return action == 'COMPLAINT_REPLIED'
            ? 'Tanggapan Pengaduan Warga'
            : 'Pengaduan Warga Baru';
      case 'letter':
        return action == 'LETTER_STATUS_CHANGED'
            ? 'Status Surat Diperbarui'
            : 'Pengajuan Surat Warga';
      case 'bill':
        return 'Tagihan Iuran Baru';
      case 'payment':
        return 'Pembayaran Iuran Berhasil';
      case 'agenda':
        return 'Agenda Kegiatan Baru';
      case 'inventory':
        return 'Peminjaman Inventaris';
      case 'visitor':
        return 'Buku Tamu / Kunjungan';
      case 'polling':
        return 'Polling Warga Baru';
      case 'bansos':
        return 'Bantuan Sosial Diperbarui';
      case 'announcement':
      default:
        return 'Pengumuman Warga';
    }
  }

  /// Membuat isi pesan fallback yang aman berdasarkan data payload jika notification block kosong.
  static String generateFallbackBody(
    String entityType,
    String? action,
    Map<String, dynamic> data,
  ) {
    switch (entityType.toLowerCase()) {
      case 'emergency':
        final location = data['location']?.toString() ?? data['lokasi']?.toString();
        if (location != null && location.isNotEmpty) {
          return 'Peringatan darurat aktif di $location.';
        }
        return action == 'ALARM_CANCELLED'
            ? 'Status darurat lingkungan telah dinonaktifkan.'
            : 'Peringatan darurat aktif di lingkungan RT.';
      case 'complaint':
        final judul = data['judul']?.toString() ?? data['title']?.toString();
        if (judul != null && judul.isNotEmpty) {
          return 'Pengaduan: "$judul"';
        }
        return action == 'COMPLAINT_REPLIED'
            ? 'Pengaduan Anda telah ditanggapi oleh pengurus.'
            : 'Laporan pengaduan warga baru membutuhkan tindak lanjut.';
      case 'letter':
        final jenis = data['jenis_surat']?.toString() ?? data['letter_type']?.toString();
        if (jenis != null && jenis.isNotEmpty) {
          return 'Pengajuan surat $jenis telah diperbarui.';
        }
        return 'Status permohonan surat administrasi warga telah diperbarui.';
      case 'bill':
        final periode = data['periode']?.toString() ?? data['nama_iuran']?.toString();
        if (periode != null && periode.isNotEmpty) {
          return 'Tagihan iuran untuk $periode siap dibayar.';
        }
        return 'Tagihan iuran RT baru telah diterbitkan.';
      case 'payment':
        return 'Pembayaran iuran telah berhasil diverifikasi oleh sistem.';
      case 'agenda':
        final judul = data['judul']?.toString() ?? data['title']?.toString();
        if (judul != null && judul.isNotEmpty) {
          return 'Kegiatan: "$judul"';
        }
        return 'Agenda kegiatan lingkungan baru telah dijadwalkan.';
      case 'inventory':
        return 'Status peminjaman barang inventaris RT telah diperbarui.';
      case 'visitor':
        final nama = data['nama_tamu']?.toString() ?? data['visitor_name']?.toString();
        if (nama != null && nama.isNotEmpty) {
          return 'Kunjungan tamu: $nama';
        }
        return 'Tamu baru tercatat pada sistem buku tamu lingkungan.';
      case 'polling':
        final judul = data['judul']?.toString() ?? data['title']?.toString();
        if (judul != null && judul.isNotEmpty) {
          return 'Polling: "$judul"';
        }
        return 'Musyawarah / polling suara warga baru telah dibuka.';
      case 'bansos':
        return 'Informasi penerima atau alokasi bantuan sosial telah diperbarui.';
      case 'announcement':
      default:
        final judul = data['judul']?.toString() ?? data['title']?.toString();
        if (judul != null && judul.isNotEmpty) {
          return judul;
        }
        return 'Pengumuman baru telah diterbitkan untuk warga RT.';
    }
  }

  @override
  String toString() {
    return 'NotificationIntent(entityType: $entityType, action: $action, entityId: $entityId, menuIndex: $targetMenuIndex, tabIndex: $targetTabIndex, title: $title)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationIntent &&
        other.entityType == entityType &&
        other.action == action &&
        other.entityId == entityId &&
        other.targetMenuIndex == targetMenuIndex &&
        other.targetTabIndex == targetTabIndex &&
        other.messageId == messageId &&
        other.title == title &&
        other.body == body;
  }

  @override
  int get hashCode {
    return Object.hash(
      entityType,
      action,
      entityId,
      targetMenuIndex,
      targetTabIndex,
      messageId,
      title,
      body,
    );
  }
}
