import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/notification_intent.dart';
import '../providers/notification_provider.dart';

/// Banner notifikasi in-app yang muncul ketika aplikasi sedang aktif di foreground.
///
/// Dirancang non-intrusif (tidak menghalangi dialog/modal kritis yang sedang terbuka),
/// selaras dengan panduan visual Smart Community RT, dan menyertakan aksi "Buka"
/// untuk menavigasi langsung ke menu & tab terkait.
class InAppNotificationBanner extends StatelessWidget {
  const InAppNotificationBanner({super.key});

  IconData _dapatkanIkon(String entityType) {
    switch (entityType.toLowerCase()) {
      case 'emergency':
        return Icons.warning_amber_rounded;
      case 'complaint':
        return Icons.chat_bubble_outline_rounded;
      case 'letter':
        return Icons.description_outlined;
      case 'bill':
      case 'payment':
        return Icons.receipt_long_outlined;
      case 'agenda':
        return Icons.calendar_month_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'visitor':
        return Icons.badge_outlined;
      case 'polling':
        return Icons.how_to_vote_outlined;
      case 'bansos':
        return Icons.volunteer_activism_outlined;
      case 'announcement':
      default:
        return Icons.campaign_outlined;
    }
  }

  Color _dapatkanWarna(String entityType, bool gelap) {
    switch (entityType.toLowerCase()) {
      case 'emergency':
        return gelap ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
      case 'complaint':
        return gelap ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
      case 'letter':
        return gelap ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
      case 'bill':
      case 'payment':
        return gelap ? const Color(0xFF34D399) : const Color(0xFF0D9488);
      case 'agenda':
      case 'announcement':
        return gelap ? const Color(0xFF2DD4BF) : const Color(0xFF1B7A6A);
      case 'inventory':
        return gelap ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
      case 'visitor':
        return gelap ? const Color(0xFFC084FC) : const Color(0xFF9333EA);
      case 'polling':
        return gelap ? const Color(0xFF22D3EE) : const Color(0xFF0891B2);
      case 'bansos':
        return gelap ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
      default:
        return gelap ? const Color(0xFF2DD4BF) : const Color(0xFF1B7A6A);
    }
  }

  @override
  Widget build(BuildContext context) {
    NotificationProvider? notif;
    try {
      notif = context.watch<NotificationProvider>();
    } catch (_) {}

    if (notif == null || !notif.hasForegroundNotification) {
      return const SizedBox.shrink();
    }

    final intent = notif.foregroundNotification!;
    final gelap = Theme.of(context).brightness == Brightness.dark;
    final warnaAksen = _dapatkanWarna(intent.entityType, gelap);
    final ikon = _dapatkanIkon(intent.entityType);

    final judul = intent.title.isNotEmpty
        ? intent.title
        : NotificationIntent.generateFallbackTitle(intent.entityType, intent.action);

    final deskripsi = intent.body.isNotEmpty
        ? intent.body
        : NotificationIntent.generateFallbackBody(intent.entityType, intent.action, intent.rawPayload);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppTheme.spasiM,
        AppTheme.spasiS,
        AppTheme.spasiM,
        AppTheme.spasiS,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spasiM,
        vertical: AppTheme.spasiS + 2,
      ),
      decoration: BoxDecoration(
        color: gelap
            ? const Color(0xFF1E293B)
            : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(
          color: warnaAksen.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: gelap ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Badge Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: warnaAksen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(ikon, size: 20, color: warnaAksen),
          ),
          const SizedBox(width: AppTheme.spasiM),

          // Teks Judul & Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  judul,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: gelap ? Colors.white : const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  deskripsi,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: gelap ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spasiS),

          // Tombol Buka
          FilledButton.tonal(
            key: const Key('in_app_notif_open_btn'),
            style: FilledButton.styleFrom(
              backgroundColor: warnaAksen.withValues(alpha: 0.18),
              foregroundColor: warnaAksen,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusS),
              ),
            ),
            onPressed: () {
              context.read<NotificationProvider>().bukaForegroundNotification();
            },
            child: const Text(
              'Buka',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),

          // Tombol Tutup
          IconButton(
            key: const Key('in_app_notif_close_btn'),
            icon: const Icon(Icons.close_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            splashRadius: 16,
            color: gelap ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            tooltip: 'Tutup',
            onPressed: () {
              context.read<NotificationProvider>().tutupForegroundNotification();
            },
          ),
        ],
      ),
    );
  }
}
