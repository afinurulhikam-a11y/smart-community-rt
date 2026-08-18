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

  @override
  String toString() {
    return 'NotificationIntent(entityType: $entityType, action: $action, entityId: $entityId, menuIndex: $targetMenuIndex, tabIndex: $targetTabIndex)';
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
        other.messageId == messageId;
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
    );
  }
}
