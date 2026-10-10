import 'package:flutter/material.dart';

class AdminColors {
  static const navy = Color(0xFF002654);
  static const lime = Color(0xFFC4D600);
  static const cyan = Color(0xFF008BBE);
  static const background = Color(0xFFF8F9FA);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE5EAF0);
  static const red = Color(0xFFB42318);
}

ThemeData adminTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Inter',
  colorScheme: ColorScheme.fromSeed(
    seedColor: AdminColors.navy,
    primary: AdminColors.navy,
    secondary: AdminColors.lime,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: AdminColors.background,
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      color: AdminColors.navy,
      letterSpacing: -.8,
    ),
    headlineSmall: TextStyle(
      fontSize: 23,
      fontWeight: FontWeight.w700,
      color: AdminColors.navy,
      letterSpacing: -.4,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AdminColors.navy,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AdminColors.navy,
    ),
    bodyMedium: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.45),
    bodySmall: TextStyle(fontSize: 11, color: AdminColors.muted, height: 1.4),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AdminColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AdminColors.border),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
);
