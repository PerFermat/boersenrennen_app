import 'package:flutter/material.dart';

/// Farbpalette und Theme der Arcade-Cartoon-Optik.
class ArcadeFarben {
  static const creme = Color(0xFFFFF6E6);
  static const cremeHell = Color(0xFFFFFDF7);
  static const tinte = Color(0xFF3B2D1E);
  static const tinteHell = Color(0xFFA8916F);

  static const kursLinie = Color(0xFFF4802F);
  static const kursFlaeche = Color(0xFFFFE1A8);

  static const himmel = Color(0xFFBFE6FF);
  static const wiese = Color(0xFF8FD694);
  static const wieseDunkel = Color(0xFF7CC482);
  static const sonne = Color(0xFFFFE066);

  static const spieler = Color(0xFF57C85A);
  static const spielerDunkel = Color(0xFF2F8F41);
  static const investor = Color(0xFF4D9BF5);
  static const investorDunkel = Color(0xFF2C6FC4);
  static const sicherheit = Color(0xFFF2B544);
  static const sicherheitDunkel = Color(0xFFC98D1C);
  static const wuerfel = Color(0xFFB569E8);
  static const wuerfelDunkel = Color(0xFF7C3FA6);

  static const kaufen = Color(0xFF3FBF50);
  static const kaufenSchatten = Color(0xFF2A8F38);
  static const verkaufen = Color(0xFFFF6B6B);
  static const verkaufenSchatten = Color(0xFFC94747);
  static const neutral = Color(0xFFE0CFAE);
}

ThemeData arcadeTheme() {
  final basis = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ArcadeFarben.kursLinie,
      surface: ArcadeFarben.creme,
    ),
    scaffoldBackgroundColor: ArcadeFarben.creme,
  );

  return basis.copyWith(
    textTheme: basis.textTheme.apply(
      bodyColor: ArcadeFarben.tinte,
      displayColor: ArcadeFarben.tinte,
    ),
    sliderTheme: basis.sliderTheme.copyWith(
      activeTrackColor: ArcadeFarben.kursLinie,
      inactiveTrackColor: const Color(0xFFF0E2C8),
      thumbColor: Colors.white,
      trackHeight: 6,
    ),
  );
}
