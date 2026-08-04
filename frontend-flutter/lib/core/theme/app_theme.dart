import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistem desain aplikasi — satu-satunya sumber warna, tipografi, jarak, dan
/// radius.
///
/// Sebelum berkas ini dibenahi, tema Material 3 di sini sudah lengkap tetapi
/// hampir tidak dipakai: layar menulis sendiri 1.065 warna (96 warna berbeda),
/// `Theme.of(context)` hanya muncul 7 kali, dan `Card` tidak dipakai sama
/// sekali — digantikan 231 `Container + BoxDecoration` buatan tangan.
///
/// Bukti paling jelas bahwa keduanya tidak pernah tersambung: [primaryColor]
/// dulu bernilai `#1B5E20` (hijau tua), sedangkan SELURUH layar memakai
/// `#1B7A6A` (teal). Nilai di bawah kini mengikuti warna yang benar-benar
/// dipakai aplikasi, bukan sebaliknya.
class AppTheme {
  // ===========================================================================
  // Warna
  // ===========================================================================

  /// Teal RT — warna yang memang dipakai di seluruh layar.
  static const Color primaryColor = Color(0xFF1B7A6A);
  static const Color primaryDark = Color(0xFF0F5347);
  static const Color primaryLight = Color(0xFF14B8A6);

  static const Color successColor = Color(0xFF059669);
  static const Color warningColor = Color(0xFFD97706);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF3B82F6);

  static const Color surfaceColor = Color(0xFFF1F5F9);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color dividerColor = Color(0xFFE2E8F0);

  // ===========================================================================
  // Jarak — kelipatan 4, kisi baku Material
  // ===========================================================================
  //
  // Sebelumnya ada 14 nilai jarak vertikal yang dipakai acak (2, 5, 6, 10, 14,
  // 36, …). Kisi 4dp membuat jarak antarunsur terasa disengaja, bukan kebetulan.

  static const double spasiXs = 4;
  static const double spasiS = 8;
  static const double spasiM = 12;
  static const double spasiL = 16;
  static const double spasiXl = 24;
  static const double spasiXxl = 32;

  // ===========================================================================
  // Radius — tiga saja
  // ===========================================================================
  //
  // Dulu 11 radius berbeda (2, 3, 4, 6, 8, 10, 12, 14, 16, 20, 24). Mata
  // menangkap ketidakteraturan itu sebagai "tidak presisi" walau tiap
  // widget-nya sendiri rapi.

  /// Lencana, chip, kolom isian.
  static const double radiusS = 8;

  /// Tombol dan kartu biasa.
  static const double radiusM = 12;

  /// Kartu besar, lembar bawah, dialog.
  static const double radiusL = 16;

  static BorderRadius get borderRadiusS => BorderRadius.circular(radiusS);
  static BorderRadius get borderRadiusM => BorderRadius.circular(radiusM);
  static BorderRadius get borderRadiusL => BorderRadius.circular(radiusL);

  /// Sisi terkecil sebuah sasaran sentuh di Android.
  ///
  /// 216 ikon di aplikasi ini berukuran di bawah 24dp dan banyak yang bisa
  /// ditekan — di bawah 48dp, jari orang dewasa sering meleset.
  static const double sasaranSentuh = 48;

  // ===========================================================================
  // Tipografi
  // ===========================================================================

  /// Skala tipe Material 3, disetel untuk bahasa Indonesia.
  ///
  /// Yang paling menentukan: **badan teks 14sp**. Aplikasi ini sebelumnya
  /// memakai 11–13px pada 405 dari sekitar 580 pemakaian — kerapatan khas
  /// dasbor web di layar 24 inci, dan itulah sumber utama kesan sempit serta
  /// berdesakan ketika dibuka di ponsel.
  static TextTheme _textTheme(Color utama, Color kedua) {
    return TextTheme(
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: utama,
        height: 1.3,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: utama,
        height: 1.3,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: utama,
        height: 1.4,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: utama,
        height: 1.4,
      ),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: utama, height: 1.5),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: utama, height: 1.5),
      bodySmall: GoogleFonts.inter(fontSize: 12, color: kedua, height: 1.4),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: utama),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kedua),
      // Terkecil yang diizinkan. Di bawah 11sp teks tidak lagi terbaca nyaman
      // di ponsel, jadi tidak ada langkah di bawah ini.
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: kedua,
        letterSpacing: 0.4,
      ),
    );
  }

  // ===========================================================================
  // Tema
  // ===========================================================================

  static ThemeData get lightTheme => _bangun(Brightness.light);
  static ThemeData get darkTheme => _bangun(Brightness.dark);

  static ThemeData _bangun(Brightness kecerahan) {
    final gelap = kecerahan == Brightness.dark;

    final permukaan = gelap ? const Color(0xFF0F172A) : surfaceColor;
    final kartu = gelap ? const Color(0xFF1E293B) : cardColor;
    final teksUtama = gelap ? Colors.white : textPrimary;
    final teksKedua = gelap ? const Color(0xFF94A3B8) : textSecondary;
    final garis = gelap ? const Color(0xFF334155) : dividerColor;

    final skema = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: kecerahan,
      primary: primaryColor,
      error: dangerColor,
      surface: kartu,
    );

    final teks = _textTheme(teksUtama, teksKedua);

    return ThemeData(
      useMaterial3: true,
      brightness: kecerahan,
      colorScheme: skema,
      scaffoldBackgroundColor: permukaan,
      textTheme: teks,

      // AppBar bawaan Android: judul di kiri, tanpa bayangan sampai digulir.
      // `centerTitle: false` disengaja — judul di tengah adalah gaya iOS.
      appBarTheme: AppBarTheme(
        backgroundColor: kartu,
        foregroundColor: teksUtama,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: teks.titleLarge,
        iconTheme: IconThemeData(color: teksUtama),
      ),

      cardTheme: CardThemeData(
        color: kartu,
        elevation: 0,
        margin: EdgeInsets.zero,
        // Garis tepi, bukan bayangan: aplikasi ini punya banyak kartu
        // bertumpuk, dan bayangan berlapis membuat layar terlihat keruh.
        shape: RoundedRectangleBorder(
          borderRadius: borderRadiusL,
          side: BorderSide(color: garis),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kartu,
        indicatorColor: primaryColor.withValues(alpha: 0.14),
        elevation: 3,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => teks.labelSmall!.copyWith(
            color: s.contains(WidgetState.selected) ? primaryColor : teksKedua,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? primaryColor : teksKedua,
          ),
        ),
      ),

      // Tinggi 48 adalah sasaran sentuh minimum Android, bukan angka estetika.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, sasaranSentuh),
          padding: const EdgeInsets.symmetric(horizontal: spasiXl),
          shape: RoundedRectangleBorder(borderRadius: borderRadiusM),
          textStyle: teks.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, sasaranSentuh),
          padding: const EdgeInsets.symmetric(horizontal: spasiXl),
          shape: RoundedRectangleBorder(borderRadius: borderRadiusM),
          textStyle: teks.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: garis),
          minimumSize: const Size(0, sasaranSentuh),
          padding: const EdgeInsets.symmetric(horizontal: spasiL),
          shape: RoundedRectangleBorder(borderRadius: borderRadiusM),
          textStyle: teks.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          minimumSize: const Size(0, sasaranSentuh),
          textStyle: teks.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(sasaranSentuh, sasaranSentuh)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: gelap ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: spasiL, vertical: spasiM),
        // Tinggi MINIMUM, bukan tetap. Dua alasan, keduanya hanya terasa di
        // ponsel: kolom isian harus cukup besar untuk disentuh jari (48dp), dan
        // harus ikut tumbuh saat pengguna memperbesar font sistem Android —
        // kotak bertinggi tetap justru memotong teksnya sendiri.
        constraints: const BoxConstraints(minHeight: sasaranSentuh),
        border: OutlineInputBorder(
          borderRadius: borderRadiusM,
          borderSide: BorderSide(color: garis),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadiusM,
          borderSide: BorderSide(color: garis),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadiusM,
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadiusM,
          borderSide: const BorderSide(color: dangerColor),
        ),
        labelStyle: teks.bodyMedium?.copyWith(color: teksKedua),
        hintStyle: teks.bodyMedium?.copyWith(color: textTertiary),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: borderRadiusL),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: gelap ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        selectedColor: primaryColor.withValues(alpha: 0.14),
        labelStyle: teks.labelMedium,
        side: BorderSide(color: garis),
        shape: RoundedRectangleBorder(borderRadius: borderRadiusS),
        padding: const EdgeInsets.symmetric(horizontal: spasiM, vertical: spasiS),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: kartu,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: borderRadiusL),
        titleTextStyle: teks.titleMedium,
        contentTextStyle: teks.bodyMedium,
      ),

      listTileTheme: ListTileThemeData(
        minVerticalPadding: spasiM,
        titleTextStyle: teks.titleSmall,
        subtitleTextStyle: teks.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: borderRadiusM),
      ),

      dividerTheme: DividerThemeData(color: garis, thickness: 1, space: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: borderRadiusM),
        contentTextStyle: teks.bodyMedium?.copyWith(color: Colors.white),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryColor),

      // Android memakai ripple; tanpa ini kartu yang bisa ditekan terasa mati.
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
