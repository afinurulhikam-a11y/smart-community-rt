import 'package:flutter/foundation.dart';
import 'fullscreen_stub.dart'
    if (dart.library.html) 'fullscreen_web.dart' as impl;

/// Layanan untuk mengendalikan mode layar penuh (fullscreen) pada web/browser.
class FullscreenService {
  /// Memeriksa apakah browser/perangkat mendukung mode layar penuh.
  static bool get isSupported => impl.isSupportedFullscreen();

  /// Mengetahui apakah aplikasi sedang dalam mode layar penuh.
  static bool get isFullscreen => impl.isCurrentlyFullscreen();

  /// Mengaktifkan atau menonaktifkan mode layar penuh.
  static Future<void> toggleFullscreen() => impl.toggleFullscreen();

  /// Mendaftarkan pendengar perubahan status layar penuh (misal: saat pengguna menekan tombol Esc).
  static void addListener(VoidCallback callback) => impl.addFullscreenListener(callback);

  /// Menghapus pendengar perubahan status layar penuh.
  static void removeListener(VoidCallback callback) => impl.removeFullscreenListener(callback);
}
