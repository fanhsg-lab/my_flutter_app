import 'package:flutter/material.dart';

class AppColors {
  // 1. The Main Colors
  static const Color primary = Color(0xFFFF9800); // Bright Orange
  static const Color accent = Color(0xFFFFB74D);  // Lighter Orange
  
  // 2. Backgrounds (The "Black" part)
  static const Color background = Color(0xFF121212); // Very dark grey (almost black)
  static const Color cardColor = Color(0xFF1E1E1E);  // Slightly lighter for cards
  
  // 3. Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70; // Greyish white
  
  // 4. Status Colors
  static const Color success = Color(0xFF4CAF50); // Green
  static const Color error = Color(0xFFEF5350);   // Red
}

// A ready-to-use Theme Data for your main.dart
final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
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

  // Text Style
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: AppColors.textPrimary),
    bodyMedium: TextStyle(color: AppColors.textSecondary),
    headlineMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
  ), colorScheme: ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.background,
  ),
);