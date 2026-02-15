import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // 1. The Main Colors
  static const Color primary = Color(0xFFFF9800); // Bright Orange
  static const Color accent = Color(0xFFFF6A00);  // Deep Orange

  // 2. Backgrounds
  static const Color background = Color(0xFF0A0A0A); // Near-black
  static const Color cardColor = Color(0xFF111214);   // Dark grey with hint of blue

  // 3. Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;

  // 4. Status Colors
  static const Color success = Color(0xFF266226); // Dark Green
  static const Color error = Color(0xFFEF5350);   // Red
}

// A ready-to-use Theme Data for your main.dart
final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
  primaryColor: AppColors.primary,
  scaffoldBackgroundColor: AppColors.background,
  
  // AppBar Style
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.primary, // Orange Text/Icons
    elevation: 0,
    centerTitle: true,
  ),
  
  // Button Style
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.black, // Text on button
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
    ),
  ),
  
  // Input Field Style
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.cardColor,
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
  ),

  colorScheme: ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.background,
  ),
);