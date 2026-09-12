import 'package:flutter/material.dart';

/// Ein einzelner Läufer im Rennen – ersetzt die früher an mehreren Stellen
/// fest verdrahtete Dreier-Liste, damit sich ein vierter Läufer (der
/// Würfel-Investor) einreiht, ohne Sonderfälle im Renderpfad.
class LaeuferDaten {
  final String name;
  final Color farbe;
  final Color farbeDunkel;

  /// Steuert Sprint-vs-Trab-Gangart, Windlinien-Berechtigung und
  /// Stolper-Berechtigung – einheitlich für alle Läufer.
  final bool investiert;

  const LaeuferDaten({
    required this.name,
    required this.farbe,
    required this.farbeDunkel,
    required this.investiert,
  });
}
