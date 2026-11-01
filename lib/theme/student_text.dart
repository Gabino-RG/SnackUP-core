import 'package:flutter/material.dart';
import 'student_colors.dart';

class AppText {
  static const h1 = TextStyle(
    fontFamily: 'Lato',
    fontWeight: FontWeight.w700,
    fontSize: 28,
    height: 1.15,
    color: AppColors.textPrimary,
  );
  static const h3 = TextStyle(
    fontFamily: 'Lato',
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.2,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontFamily: 'Quicksand',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 1.4,
    color: AppColors.textPrimary,
  );
  static const notes = TextStyle(
    fontFamily: 'Quicksand',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 1.4,
    color: AppColors.textSecondary,
  );
}
