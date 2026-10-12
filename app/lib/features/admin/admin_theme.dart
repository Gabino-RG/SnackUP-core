import 'package:flutter/material.dart';

class AdminColors {
  static const navy = Color(0xFF002855);
  static const teal = Color(0xFF00A788);
  static const cyan = Color(0xFF007C66);
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
    secondary: AdminColors.teal,
    surface: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: const Color(0xFFF3F6F8),
    surfaceContainerHigh: const Color(0xFFEBF0F4),
    surfaceContainerHighest: const Color(0xFFE2EAEE),
    surfaceTint: Colors.transparent,
    secondaryContainer: const Color(0xFFDDF3ED),
    onSecondaryContainer: AdminColors.navy,
  ),
  scaffoldBackgroundColor: AdminColors.background,
  cardColor: Colors.white,
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xFFDDF3ED),
  ),
  navigationRailTheme: const NavigationRailThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xFFDDF3ED),
  ),
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
