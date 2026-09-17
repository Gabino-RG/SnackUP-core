import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'; // <--- IMPORTANTE: Agregué esto para usar kIsWeb

// Tus imports originales
import 'features/auth/auth_gate.dart';
import 'firebase_options.dart';
import 'theme/app_colors.dart';
import 'theme/app_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- AQUÍ ESTÁ LA MAGIA ---
  // Si es Web, usamos las llaves manuales. Si es Android, usa el archivo generado.
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDK5N-TA3bA7VKv5TJQqUXICA617wOywzU",
        authDomain: "snackup-8fe96.firebaseapp.com",
        projectId: "snackup-8fe96",
        storageBucket: "snackup-8fe96.firebasestorage.app",
        messagingSenderId: "685155856831",
        appId: "1:685155856831:web:8047d0df9ed1522ff5b10a",
        measurementId: "G-PE33SNB39W",
      ),
    );
  } else {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  // ---------------------------

  // Configuración de notificaciones (solo intentamos si ya se inicializó)
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
  } catch (e) {
    print('Nota: Las notificaciones pueden no estar configuradas en Web o dieron error: $e');
  }
  
  runApp(const SnackUpApp());
}

class SnackUpApp extends StatelessWidget {
  const SnackUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SnackUp UTSJR',
      debugShowCheckedModeBanner: false,

      // --- TEMA GLOBAL OPTIMIZADO ---
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Quicksand',

        // COLOR SCHEME MEJORADO
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          
          // Primarios
          primary: AppColors.primary,
          onPrimary: Colors.white,
          
          // Secundarios
          secondary: AppColors.accent,
          onSecondary: Colors.white,
          
          // Terciarios
          tertiary: AppColors.tertiary,
          onTertiary: Colors.white,
          
          // Fondos y superficies
          background: AppColors.background,
          onBackground: AppColors.textPrimary,
          surface: AppColors.componentBase,
          onSurface: AppColors.textPrimary,
          
          // Variantes modernas
          surfaceVariant: AppColors.componentBase.withOpacity(0.6),
          outline: AppColors.borders,
        ),

        // TEXT THEME COMPLETO
        textTheme: TextTheme(
          // Display (Pantallas principales)
          displayLarge: AppText.h1,
          displayMedium: AppText.h1.copyWith(fontSize: 24), // H2
          
          // Headlines
          headlineMedium: AppText.h3,
          headlineSmall: AppText.h3.copyWith(fontSize: 18), // H4
          
          // Titles
          titleLarge: AppText.h3.copyWith(fontWeight: FontWeight.w700),
          titleMedium: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleSmall: AppText.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          
          // Body
          bodyLarge: AppText.body,
          bodyMedium: AppText.body.copyWith(fontSize: 14),
          bodySmall: AppText.notes,
          
          // Labels (Botones, Chips)
          labelLarge: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          labelMedium: AppText.notes.copyWith(fontWeight: FontWeight.w500),
          labelSmall: AppText.notes.copyWith(fontSize: 12),
        ),

        // COMPONENTES PRINCIPALES

        // AppBar Moderno
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: AppText.h3.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
          centerTitle: false,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),

        // Botones Elevados (Primarios)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            textStyle: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            shadowColor: AppColors.primary.withOpacity(0.3),
          ),
        ),

        // Botones Rellenados (Acento)
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            textStyle: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Botones de Texto
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // Tarjetas Modernas
        cardTheme: const CardThemeData(
          color: AppColors.componentBase,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),

        // Campos de Texto Mejorados
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.componentBase,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          labelStyle: AppText.notes.copyWith(color: AppColors.textSecondary),
          hintStyle: AppText.notes.copyWith(
            color: AppColors.textSecondary.withOpacity(0.7),
          ),
          floatingLabelStyle: const TextStyle(color: AppColors.primary),
          errorStyle: AppText.notes.copyWith(color: AppColors.error),
        ),

        // ListTiles Modernas
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          tileColor: AppColors.componentBase,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          titleTextStyle: AppText.body.copyWith(
            fontWeight: FontWeight.w500,
          ),
          subtitleTextStyle: AppText.notes,
        ),

        // Chips Estilizados
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.componentBase,
          selectedColor: AppColors.primary,
          labelStyle: AppText.notes,
          secondaryLabelStyle: AppText.notes.copyWith(color: Colors.white),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: const StadiumBorder(side: BorderSide.none),
          checkmarkColor: Colors.white,
        ),

        // Navigation Bar Mejorado
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.background,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: AppText.notes.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: AppText.notes,
          showUnselectedLabels: true,
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),

        // Dividers Consistente
        dividerTheme: const DividerThemeData(
          color: AppColors.borders,
          thickness: 1,
          space: 0,
        ),
      ),

      home: const AuthWrapper(), // Asegúrate de que AuthWrapper esté en auth_gate.dart
    );
  }
}