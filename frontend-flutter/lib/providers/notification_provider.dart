import 'package:flutter/foundation.dart';
import '../models/notification_intent.dart';

/// Provider dan router terpusat untuk memproses, memvalidasi, dan mengarahkan
/// notifikasi FCM ke menu/layar target di dalam aplikasi, serta mengelola
/// in-app foreground notification banner yang konsisten dengan desain UI.
///
/// Dirancang bersih tanpa dependensi pada `BuildContext`, dilengkapi proteksi
/// deduplikasi berbasis TTL dan bounded FIFO cache, serta sepenuhnya dapat
/// diuji (testable) secara terisolasi.
class NotificationProvider extends ChangeNotifier {
  NotificationIntent? _pendingIntent;
  NotificationIntent? _activeIntent;
  NotificationIntent? _foregroundNotification;

  /// Cache deduplikasi berbasis signature pesan dan waktu pemrosesan.
  final Map<String, DateTime> _processedEntries = {};

  /// Batas ukuran cache deduplikasi agar penggunaan memori tetap terkendali.
  static const int _maxDeduplicationHistory = 100;

  /// Masa berlaku deduplikasi (Time-To-Live) 15 menit.
  static const Duration _deduplicationTTL = Duration(minutes: 15);

  NotificationIntent? get pendingIntent => _pendingIntent;
  NotificationIntent? get activeIntent => _activeIntent;
  NotificationIntent? get foregroundNotification => _foregroundNotification;

  bool get hasPendingIntent => _pendingIntent != null;
  bool get hasActiveIntent => _activeIntent != null;
  bool get hasForegroundNotification => _foregroundNotification != null;

  /// Mem-parse dan memvalidasi `RemoteMessage.data` (serta optional notification block)
  /// menjadi [NotificationIntent].
  ///
  /// Mengembalikan `null` secara aman jika payload tidak valid, tipe entitas
  /// tidak dikenal, atau struktur data rusak.
  NotificationIntent? parsePayload(
    Map<String, dynamic>? data, {
    String? messageId,
    String? title,
    String? body,
    DateTime? now,
  }) {
    if (data == null || data.isEmpty) return null;

    final rawType = data['entity_type']?.toString().trim().toLowerCase();
    if (rawType == null || rawType.isEmpty) return null;

    final rawAction = data['action']?.toString().trim();
    final rawEntityId = data['entity_id']?.toString().trim();
    final entityId = (rawEntityId != null &&
            rawEntityId.isNotEmpty &&
            rawEntityId != 'null' &&
            rawEntityId != 'undefined')
        ? rawEntityId
        : null;
    final action = (rawAction != null &&
            rawAction.isNotEmpty &&
            rawAction != 'null' &&
            rawAction != 'undefined')
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

    final finalTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : (data['title']?.toString().trim().isNotEmpty == true
            ? data['title'].toString().trim()
            : NotificationIntent.generateFallbackTitle(rawType, action));

    final finalBody = (body != null && body.trim().isNotEmpty)
        ? body.trim()
        : (data['body']?.toString().trim().isNotEmpty == true
            ? data['body'].toString().trim()
            : NotificationIntent.generateFallbackBody(rawType, action, data));

    return NotificationIntent(
      entityType: rawType,
      action: action,
      entityId: entityId,
      targetMenuIndex: targetMenuIndex,
      targetTabIndex: targetTabIndex,
      messageId: messageId,
      title: finalTitle,
      body: finalBody,
      rawPayload: Map<String, dynamic>.from(data),
      timestamp: now ?? DateTime.now(),
    );
  }

  /// Memeriksa apakah intent ini sudah pernah diproses sebelumnya dalam jendela TTL.
  bool isDuplicate(NotificationIntent intent, {DateTime? now}) {
    _bersihkanStaleEntries(now: now);
    return _processedEntries.containsKey(intent.deduplicationKey);
  }

  /// Mencatat key intent ke cache deduplikasi dengan timestamp terkini.
  void recordProcessed(NotificationIntent intent, {DateTime? now}) {
    _bersihkanStaleEntries(now: now);
    if (_processedEntries.length >= _maxDeduplicationHistory) {
      _processedEntries.remove(_processedEntries.keys.first);
    }
    _processedEntries[intent.deduplicationKey] = now ?? DateTime.now();
  }

  /// Membersihkan entri deduplikasi yang sudah melewati batas TTL 15 menit.
  void _bersihkanStaleEntries({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    _processedEntries.removeWhere((key, timestamp) {
      return currentTime.difference(timestamp) > _deduplicationTTL;
    });
  }

  /// Menangani payload notifikasi FCM dari berbagai siklus hidup (Background Tap `onMessageOpenedApp`,
  /// Terminated `getInitialMessage`).
  ///
  /// [isLoggedIn] menentukan apakah intent langsung diarahkan ke layar aktif
  /// atau ditahan sebagai pending intent hingga proses login/bootstrap selesai.
  NotificationIntent? handleNotificationPayload(
    Map<String, dynamic>? data, {
    String? title,
    String? body,
    String? messageId,
    required bool isLoggedIn,
    bool bypassDeduplication = false,
  }) {
    final intent = parsePayload(data, messageId: messageId, title: title, body: body);
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

  /// Menangani pesan FCM yang masuk saat aplikasi sedang dibuka/aktif (Foreground Notification).
  ///
  /// Menampilkan in-app notification banner dan tidak langsung menavigasi paksa,
  /// agar user tidak kehilangan konteks pekerjaan yang sedang dibuka.
  NotificationIntent? handleForegroundMessage(
    Map<String, dynamic>? data, {
    String? title,
    String? body,
    String? messageId,
    required bool isLoggedIn,
    bool bypassDeduplication = false,
  }) {
    final intent = parsePayload(data, messageId: messageId, title: title, body: body);
    if (intent == null) return null;

    if (!bypassDeduplication && isDuplicate(intent)) {
      debugPrint('NotificationProvider: Pesan foreground duplikat diabaikan: ${intent.deduplicationKey}');
      return null;
    }

    recordProcessed(intent);

    if (isLoggedIn) {
      _foregroundNotification = intent;
      notifyListeners();
    } else {
      _pendingIntent = intent;
      notifyListeners();
    }

    return intent;
  }

  /// Menanggapi aksi "Buka" dari in-app notification banner:
  /// Menghilangkan banner dan memicu navigasi terpusat ke target menu dan tab.
  void bukaForegroundNotification() {
    final intent = _foregroundNotification;
    if (intent != null) {
      _foregroundNotification = null;
      _activeIntent = intent;
      notifyListeners();
    }
  }

  /// Menutup in-app notification banner saat pengguna menekan tombol tutup atau timer habis.
  void tutupForegroundNotification() {
    if (_foregroundNotification != null) {
      _foregroundNotification = null;
      notifyListeners();
    }
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

  /// Membersihkan seluruh state saat sesi pengguna berakhir (logout) atau pergantian akun.
  void bersihkan() {
    _foregroundNotification = null;
    _pendingIntent = null;
    _activeIntent = null;
    _processedEntries.clear();
    notifyListeners();
  }
}
