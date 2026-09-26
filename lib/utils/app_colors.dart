import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors — primary is #F4B624
  static const Color primary = Color(0xFFF4B624);
  static const Color secondary = Color(0xFF37383D);
  static const Color accent = Color.fromARGB(235, 236, 29, 36);
  /// Same red as menu card image gradient bottom stop — use for OFF badges / delete.
  static const Color discountRed = Color.fromARGB(255, 194, 60, 33);
  static const Color yellow = primary;
  static const Color matteBlack = Color(0xFF121212);

  // Neutral Colors — matte black theme
  static const Color background = Color(0xFF121212);
  static const Color scaffoldBackground = Color(0xFF121212);
  static const Color cardBackground = Color(0xFF1C1C1E);
  static const Color surfaceElevated = Color(0xFF242426);

  // Text Colors
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textOnDark = Colors.white;
  static const Color heading = primary;
  /// Text / icons on solid golden buttons.
  static const Color onPrimary = matteBlack;

  // Border & Divider
  static const Color border = Color(0xFF2E2E30);
  static const Color divider = Color(0xFF2E2E30);

  // Status Colors
  static const Color error = Colors.red;
  static const Color success = Colors.green;

  /// Menu / item image tile background — bottom → top soft blend.
  /// Portions: red, then more room for the two center oranges, then golden.
  static const LinearGradient menuItemImageGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xFFEE1C27),
      Color(0xFFF35E26),
      Color(0xFFF7881D),
      primary,
    ],
    stops: [0.0, 0.20, 0.58, 1.0],
  );

  /// Kept for existing `gradient:` / `createShader` call sites —
  /// both stops are the same so it renders as solid #F4B624.
  static const LinearGradient flameGradient = LinearGradient(
    colors: [yellow, yellow],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
