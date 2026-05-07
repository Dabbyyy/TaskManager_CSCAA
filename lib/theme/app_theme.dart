import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF3F598F);
  static const Color secondaryMaroon = Color(0xFF700202);
  static const Color navyBlue = Color(0xFF0D1B3E);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      primary: primaryBlue,
      secondary: secondaryMaroon,
    ),
    // Corrected to CardThemeData
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100),
      ),
    ),
  );
}
