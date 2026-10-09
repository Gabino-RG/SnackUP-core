import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppText {
  // H1, H2: Lato Bold 28px
  static const TextStyle h1 = TextStyle(
    fontFamily: 'Lato',
    fontWeight: FontWeight.w700, // Bold
    fontSize: 28,
    color: AppColors.textPrimary,
  );

  // H3, Títulos de Tarjeta: Quicksand Bold/SemiBold 20px
  static const TextStyle h3 = TextStyle(
    fontFamily: 'Quicksand',
    fontWeight: FontWeight.w600, // SemiBold
    fontSize: 20,
    color: AppColors.textPrimary,
  );

  // Cuerpo: Quicksand Regular 16px
  static const TextStyle body = TextStyle(
    fontFamily: 'Quicksand',
    fontWeight: FontWeight.w400, // Regular
    fontSize: 16,
    color: AppColors.textPrimary,
  );

  // Notas, Secundario: Quicksand Light 14px
  static const TextStyle notes = TextStyle(
    fontFamily: 'Quicksand',
    fontWeight: FontWeight.w300, // Light
    fontSize: 14,
    color: AppColors.textSecondary,
  );
}