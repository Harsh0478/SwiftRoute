import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primaryOrange = Color(0xFFF99A4F);
  static const Color secondaryCream = Color(0xFFF9EDE8);
  static const Color background = Color(0xFFF3F3F3);
  static const Color white = Color(0xFFFFFFFF);
  static const Color primaryText = Color(0xFF242424);
  static const Color darkSurface = Color(0xFF242424);
  static const Color darkSurfaceElevated = Color(0xFF2E2E2E);
  static const Color secondaryText = Color(0xFF888888);
  static const Color success = Color(0xFF42B883);
  static const Color error = Color(0xFFE85D5D);
}

class AppTheme {
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.poppinsTextTheme();
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryOrange,
        primary: AppColors.primaryOrange,
        secondary: AppColors.secondaryCream,
        surface: AppColors.white,
        error: AppColors.error,
      ),
      textTheme: baseTextTheme.copyWith(
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          height: 1.2,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: AppColors.primaryText, fontSize: 14),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: AppColors.secondaryText, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryOrange,
          foregroundColor: AppColors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        hintStyle: GoogleFonts.poppins(color: AppColors.secondaryText, fontSize: 14),
      ),
    );
  }
}
