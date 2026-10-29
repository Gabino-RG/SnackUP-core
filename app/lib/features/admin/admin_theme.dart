import 'package:flutter/material.dart';
import 'panel_motion.dart';

class AdminColors {
  static const navy = Color(0xFF002855);
  static const teal = Color(0xFF00A788);
  static const cyan = Color(0xFF007C66);
  static const background = Color(0xFFF8F9FA);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE5EAF0);
  static const red = Color(0xFFB42318);
}

class PanelPalette {
  PanelPalette.of(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get ink => dark ? const Color(0xFFF0F6FF) : AdminColors.navy;
  Color get muted => dark ? const Color(0xFFB4C7DF) : AdminColors.muted;
  Color get accent => dark ? const Color(0xFF48DCC2) : AdminColors.cyan;
  Color get danger => dark ? const Color(0xFFFFA49E) : AdminColors.red;
  Color get border => dark ? const Color(0xFF365A80) : AdminColors.border;
  Color get surface => dark ? const Color(0xFF10345B) : Colors.white;
  Color get layer => dark ? const Color(0xFF173F69) : const Color(0xFFEEF2F6);
  Color get background =>
      dark ? const Color(0xFF05274C) : AdminColors.background;
  Color get pending => dark ? const Color(0xFFFFD48A) : const Color(0xFF946000);
}

ThemeData adminDarkTheme() {
  final base = adminTheme();
  const surface = Color(0xFF10345B), layer = Color(0xFF173F69);
  const ink = Color(0xFFF0F6FF), muted = Color(0xFFB4C7DF);
  const border = Color(0xFF365A80), accent = Color(0xFF48DCC2);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF3478E5),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF99C2FF),
        onPrimary: const Color(0xFF05274C),
        secondary: accent,
        onSecondary: const Color(0xFF05274C),
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerLowest: const Color(0xFF05274C),
        surfaceContainerLow: surface,
        surfaceContainer: layer,
        surfaceContainerHigh: const Color(0xFF1D4774),
        surfaceContainerHighest: const Color(0xFF255582),
        surfaceTint: Colors.transparent,
        secondaryContainer: const Color(0xFF17596A),
        onSecondaryContainer: ink,
        outline: const Color(0xFF7894B5),
        outlineVariant: border,
        error: const Color(0xFFFFA49E),
        onError: const Color(0xFF521C26),
      );
  return ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: scheme, fontFamily: 'Inter').copyWith(
    splashFactory: base.splashFactory,
    pageTransitionsTheme: base.pageTransitionsTheme,
    tooltipTheme: base.tooltipTheme,
    textButtonTheme: base.textButtonTheme,
    iconButtonTheme: base.iconButtonTheme,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF05274C),
    cardColor: surface,
    dividerColor: border,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: const IconThemeData(color: muted),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: Color(0xFF17596A),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: Color(0xFF17596A),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: const Color(0xFF0A2C50),
      labelStyle: const TextStyle(color: muted),
      hintStyle: const TextStyle(color: muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style!.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? layer
              : const Color(0xFF2865C6),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? muted : Colors.white,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style!.copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color:
                states.contains(WidgetState.focused) ||
                    states.contains(WidgetState.hovered)
                ? accent
                : border,
          ),
        ),
      ),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: layer,
      contentTextStyle: const TextStyle(color: ink),
    ),
  );
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
  splashFactory: InkRipple.splashFactory,
  pageTransitionsTheme: PageTransitionsTheme(
    builders: {
      for (final platform in TargetPlatform.values)
        platform: const PanelPageTransitions(),
    },
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 400),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: AdminColors.navy,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
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
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AdminColors.cyan, width: 2),
    ),
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
    style:
        FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ).copyWith(
          animationDuration: const Duration(milliseconds: 160),
          foregroundBuilder: panelButtonFeedback,
          shadowColor: const WidgetStatePropertyAll(Color(0x40002855)),
          elevation: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.disabled) ||
                    states.contains(WidgetState.pressed)
                ? 0
                : states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                ? 5
                : 1,
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? const Color(0x3300A788)
                : states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                ? const Color(0x2600A788)
                : null,
          ),
        ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: ButtonStyle(
      animationDuration: const Duration(milliseconds: 160),
      foregroundBuilder: panelButtonFeedback,
      side: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? const BorderSide(color: AdminColors.cyan, width: 2)
            : null,
      ),
    ),
  ),
  textButtonTheme: const TextButtonThemeData(
    style: ButtonStyle(foregroundBuilder: panelButtonFeedback),
  ),
  iconButtonTheme: const IconButtonThemeData(
    style: ButtonStyle(foregroundBuilder: panelButtonFeedback),
  ),
);
