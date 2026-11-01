import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'features/auth/auth_gate.dart';
import 'student/student_api.dart';
import 'theme/student_colors.dart';
import 'theme/student_text.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnackUpApp());
}

class SnackUpApp extends StatelessWidget {
  const SnackUpApp({super.key, this.api});
  final StudentApi? api;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<StudentApi>(
    create: (_) => (api ?? StudentApi())..restore(),
    child: MaterialApp(
      title: 'SnackUP · Alumnos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Quicksand',
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary)
            .copyWith(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              secondary: AppColors.accent,
              onSecondary: AppColors.primary,
              tertiary: AppColors.tertiary,
              surface: Colors.white,
              onSurface: AppColors.primary,
              error: AppColors.error,
              outline: AppColors.borders,
            ),
        textTheme: const TextTheme(
          headlineMedium: AppText.h1,
          headlineSmall: AppText.h3,
          titleLarge: AppText.h3,
          titleMedium: AppText.body,
          bodyLarge: AppText.body,
          bodyMedium: AppText.body,
          bodySmall: AppText.notes,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: AppText.h3,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.borders),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.borders,
            textStyle: const TextStyle(
              fontFamily: 'Lato',
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            minimumSize: const Size(48, 50),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.primary,
            elevation: 0,
            minimumSize: const Size(48, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(48, 46),
            side: const BorderSide(color: AppColors.borders),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.tertiary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          labelStyle: AppText.notes,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: AppColors.borders),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: AppColors.borders),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: AppColors.tertiary, width: 1.5),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.paleBlue,
          selectedColor: AppColors.accent,
          labelStyle: AppText.notes.copyWith(color: AppColors.primary),
          side: BorderSide.none,
          shape: const StadiumBorder(),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: TextStyle(fontSize: 12),
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(color: AppColors.borders),
      ),
      home: const AuthWrapper(),
    ),
  );
}
