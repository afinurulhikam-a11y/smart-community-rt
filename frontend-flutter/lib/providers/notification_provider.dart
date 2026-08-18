import 'package:flutter/foundation.dart';
import '../models/notification_intent.dart';

/// Provider dan router terpusat untuk memproses, memvalidasi, dan mengarahkan
/// notifikasi FCM ke menu/layar target di dalam aplikasi.
///
/// Dirancang bersih tanpa dependensi pada `BuildContext` dan sepenuhnya
/// dapat diuji (testable) secara terisolasi.
class NotificationProvider extends ChangeNotifier {
  NotificationIntent? _pendingIntent;
  NotificationIntent? _activeIntent;

  /// Cache deduplikasi berbasis signature pesan yang baru saja diproses.
  final Set<String> _processedKeys = {};

  /// Batas ukuran cache deduplikasi agar penggunaan memori tetap terkendali.
  static const int _maxDeduplicationHistory = 100;

  NotificationIntent? get pendingIntent => _pendingIntent;
  NotificationIntent? get activeIntent => _activeIntent;
  bool get hasPendingIntent => _pendingIntent != null;
  bool get hasActiveIntent => _activeIntent != null;

  /// Mem-parse dan memvalidasi `RemoteMessage.data` menjadi [NotificationIntent].
  ///
  /// Mengembalikan `null` secara aman jika payload tidak valid, tipe entitas
  /// tidak dikenal, atau struktur data rusak.
  NotificationIntent? parsePayload(
    Map<String, dynamic>? data, {
    String? messageId,
    DateTime? now,
  }) {
    if (data == null || data.isEmpty) return null;

    final rawType = data['entity_type']?.toString().trim().toLowerCase();
    if (rawType == null || rawType.isEmpty) return null;

    final rawAction = data['action']?.toString().trim();
    final rawEntityId = data['entity_id']?.toString().trim();
    final entityId = (rawEntityId != null && rawEntityId.isNotEmpty && rawEntityId != 'null')
        ? rawEntityId
        : null;
    final action = (rawAction != null && rawAction.isNotEmpty && rawAction != 'null')
        ? rawAction
        : null;

    final int targetMenuIndex;
    int? targetTabIndex;

    switch (rawType) {
      case 'announcement':
        // Menu 50: Agenda & Kegiatan (Tab 0: Semua Agenda / Pengumuman)
        targetMenuIndex = 50;
        targetTabIndex = 0;
        break;

      case 'emergency':
        // Menu 60: Status Darurat
        targetMenuIndex = 60;
        break;

      case 'complaint':
        // Menu 61: Pengaduan (Warga & Pengurus)
        targetMenuIndex = 61;
        break;

      case 'letter':
        // Menu 44: Pengajuan Surat (Warga) / Surat Menyurat (Pengurus)
        targetMenuIndex = 44;
        break;

      case 'bill':
        // Menu 21: Tagihan Saya (Warga, Tab 0: Belum Lunas) / Iuran Warga (Pengurus)
        targetMenuIndex = 21;
        if (action == 'NEW_BILL') {
          targetTabIndex = 0; // Belum Lunas
        }
        break;

      case 'payment':
        // Menu 21: Tagihan Saya (Warga, Tab 1: Riwayat Lunas) / Laporan Keuangan
        targetMenuIndex = 21;
        if (action == 'PAYMENT_SUCCESS') {
          targetTabIndex = 1; // Riwayat Lunas
        }
        break;

      case 'agenda':
        // Menu 50: Agenda & Kegiatan (Tab 1: Akan Datang)
        targetMenuIndex = 50;
        if (action == 'NEW_AGENDA') {
          targetTabIndex = 1; // Akan Datang
        }
        break;

      case 'inventory':
        // Menu 32: Pinjam Barang (Warga) / Peminjaman (Pengurus)
        targetMenuIndex = 32;
        break;

      case 'visitor':
        // Menu 43: Buku Tamu Saya (Warga) / E-Visitor (Pengurus)
        targetMenuIndex = 43;
        break;

      case 'polling':
        // Menu 62: Polling Warga
        targetMenuIndex = 62;
        break;

      case 'bansos':
        // Menu 13: Bantuan Sosial
        targetMenuIndex = 13;
        break;

      default:
        // Tipe entitas di luar kontrak resmi diabaikan demi keamanan
        debugPrint('NotificationProvider: Tipe entitas tidak dikenal: $rawType');
        return null;
    }

    return NotificationIntent(
      entityType: rawType,
      action: action,
      entityId: entityId,
      targetMenuIndex: targetMenuIndex,
      targetTabIndex: targetTabIndex,
      messageId: messageId,
      rawPayload: Map<String, dynamic>.from(data),
      timestamp: now ?? DateTime.now(),
    );
  }

  /// Memeriksa apakah intent ini sudah pernah diproses sebelumnya.
  bool isDuplicate(NotificationIntent intent) {
    return _processedKeys.contains(intent.deduplicationKey);
  }

  /// Mencatat key intent ke cache deduplikasi.
  void recordProcessed(NotificationIntent intent) {
    if (_processedKeys.length >= _maxDeduplicationHistory) {
      _processedKeys.remove(_processedKeys.first);
    }
    _processedKeys.add(intent.deduplicationKey);
  }

  /// Menangani payload notifikasi FCM dari berbagai siklus hidup (Foreground,
  /// Background Tap `onMessageOpenedApp`, Terminated `getInitialMessage`).
  ///
  /// [isLoggedIn] menentukan apakah intent langsung diarahkan ke layar aktif
  /// atau ditahan sebagai pending intent hingga proses login/bootstrap selesai.
  NotificationIntent? handleNotificationPayload(
    Map<String, dynamic>? data, {
    String? messageId,
    required bool isLoggedIn,
    bool bypassDeduplication = false,
  }) {
    final intent = parsePayload(data, messageId: messageId);
    if (intent == null) return null;

    if (!bypassDeduplication && isDuplicate(intent)) {
      debugPrint('NotificationProvider: Pesan duplikat diabaikan: ${intent.deduplicationKey}');
      return null;
    }

    recordProcessed(intent);

    if (isLoggedIn) {
      _activeIntent = intent;
      _pendingIntent = null;
      notifyListeners();
    } else {
      _pendingIntent = intent;
      _activeIntent = null;
      notifyListeners();
    }

    return intent;
  }

  /// Mengonsumsi dan mengeksekusi pending intent setelah pengguna berhasil masuk (login).
  NotificationIntent? consumePendingIntent() {
    final pending = _pendingIntent;
    if (pending == null) return null;

    _pendingIntent = null;
    _activeIntent = pending;
    notifyListeners();
    return pending;
  }

  /// Menetapkan active intent secara langsung (misal untuk navigasi terprogram atau pengujian).
  void dispatchIntent(NotificationIntent intent) {
    _activeIntent = intent;
    notifyListeners();
  }

  /// Membersihkan active intent setelah navigasi selesai dieksekusi oleh MainDashboard.
  void clearActiveIntent() {
    if (_activeIntent != null) {
      _activeIntent = null;
      notifyListeners();
    }
  }

  /// Membersihkan seluruh state saat sesi pengguna berakhir (logout).
  void bersihkan() {
    _pendingIntent = null;
    _activeIntent = null;
    _processedKeys.clear();
    notifyListeners();
  }
}
