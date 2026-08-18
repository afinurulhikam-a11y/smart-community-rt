import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/notification_intent.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/bantuan_sosial_provider.dart';
import '../../providers/bill_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/emergency_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/letter_provider.dart';
import '../../providers/polling_provider.dart';
import '../../providers/visitor_provider.dart';

/// Service penyegaran data bisnis terpusat ketika notification intent dibuka oleh pengguna.
///
/// Memetakan seluruh 11 tipe entitas ke provider bisnis terkait secara aman,
/// mencegah pemanggilan API ganda (deduplikasi dengan batas TTL 15 menit dan bounded cache),
/// serta menjamin kegagalan jaringan tidak merusak navigasi atau menjatuhkan aplikasi.
class NotificationDataRefresher {
  NotificationDataRefresher._();
  static final NotificationDataRefresher instance = NotificationDataRefresher._();

  final Map<String, DateTime> _refreshedEntries = {};
  static const int _maxRefreshedHistory = 100;
  static const Duration _refreshTTL = Duration(minutes: 15);

  /// Memeriksa apakah intent ini sudah memicu refresh data sebelumnya dalam jendela TTL.
  bool sudahDirefresh(NotificationIntent intent, {DateTime? now}) {
    _bersihkanStaleEntries(now: now);
    return _refreshedEntries.containsKey(intent.deduplicationKey);
  }

  /// Mencatat bahwa intent ini telah memicu refresh data.
  void catatRefreshed(NotificationIntent intent, {DateTime? now}) {
    _bersihkanStaleEntries(now: now);
    if (_refreshedEntries.length >= _maxRefreshedHistory) {
      _refreshedEntries.remove(_refreshedEntries.keys.first);
    }
    _refreshedEntries[intent.deduplicationKey] = now ?? DateTime.now();
  }

  void _bersihkanStaleEntries({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    _refreshedEntries.removeWhere((key, timestamp) {
      return currentTime.difference(timestamp) > _refreshTTL;
    });
  }

  /// Memicu penyegaran data bisnis secara aman sesuai [NotificationIntent].
  ///
  /// Mengembalikan `true` bila refresh berhasil dijalankan, atau `false` jika
  /// dilewati karena deduplikasi / tipe tidak dikenal / terjadi error.
  Future<bool> refreshDataUntukIntent(
    BuildContext context,
    NotificationIntent intent, {
    bool force = false,
  }) async {
    if (!force && sudahDirefresh(intent)) {
      debugPrint('NotificationDataRefresher: Refresh untuk intent ${intent.deduplicationKey} sudah pernah dilakukan, dilewati.');
      return false;
    }

    catatRefreshed(intent);

    try {
      final type = intent.entityType.toLowerCase();
      switch (type) {
        case 'announcement':
          await Future.wait([
            _aman(() => _providerAman<AgendaProvider>(context)?.fetchAgenda(silent: true)),
            _aman(() => _providerAman<AnnouncementProvider>(context)?.fetchAnnouncements()),
          ]);
          break;

        case 'emergency':
          await _aman(() => _providerAman<EmergencyProvider>(context)?.segarkanDarurat());
          break;

        case 'complaint':
          await _aman(() => _providerAman<ComplaintProvider>(context)?.fetchComplaints(silent: true));
          break;

        case 'letter':
          await _aman(() => _providerAman<LetterProvider>(context)?.fetchLetters(silent: true));
          break;

        case 'bill':
        case 'payment':
          await _aman(() => _providerAman<BillProvider>(context)?.fetchBills(silent: true));
          break;

        case 'agenda':
          await _aman(() => _providerAman<AgendaProvider>(context)?.fetchAgenda(silent: true));
          break;

        case 'inventory':
          await Future.wait([
            _aman(() => _providerAman<InventoryProvider>(context)?.fetchBorrowings(silent: true)),
            _aman(() => _providerAman<InventoryProvider>(context)?.fetchBarangTersedia()),
          ]);
          break;

        case 'visitor':
          await _aman(() => _providerAman<VisitorProvider>(context)?.fetchVisitors(silent: true));
          break;

        case 'polling':
          await _aman(() => _providerAman<PollingProvider>(context)?.fetchPolling(silent: true));
          break;

        case 'bansos':
          await _aman(() => _providerAman<BantuanSosialProvider>(context)?.fetchBantuanSosial(silent: true));
          break;

        default:
          debugPrint('NotificationDataRefresher: Tipe entitas $type tidak memerlukan refresh khusus.');
          return false;
      }
      return true;
    } catch (e) {
      debugPrint('NotificationDataRefresher: Kesalahan saat refresh data: $e');
      return false;
    }
  }

  T? _providerAman<T extends ChangeNotifier>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _aman(Future<dynamic>? Function() aksi) async {
    try {
      final res = aksi();
      if (res != null) {
        await res;
      }
    } catch (e) {
      debugPrint('NotificationDataRefresher: Sub-refresh gagal (aman): $e');
    }
  }

  /// Membersihkan cache riwayat intent yang sudah direfresh (saat logout / reset).
  void bersihkan() {
    _refreshedEntries.clear();
  }
}
