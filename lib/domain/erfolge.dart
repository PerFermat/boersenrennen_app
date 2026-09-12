import 'dart:math' as math;

import 'kursreihe.dart';

/// Erfolge sind bewusst auf **Prozess statt Ergebnis** ausgelegt – sie prämieren
/// ein Verhalten (Ruhe bewahren, ehrlich hinschauen, Vielfalt suchen), nicht den
/// Ausgang einer einzelnen Runde. Reines Dart, keine Flutter-Imports; die
/// Persistenz liegt in `lib/data/erfolge_repository.dart`.
enum ErfolgId {
  eisernehand,
  nichtstun,
  derGlueckliche,
  selbsterkenntnis,
  zeitreisender,
  alleWetter,
  vielspieler,
}

class ErfolgDefinition {
  final ErfolgId id;
  final String titel;
  final String beschreibung;

  const ErfolgDefinition({required this.id, required this.titel, required this.beschreibung});
}

class Erfolge {
  /// So oft muss bis zum Ende der Auswertung gescrollt worden sein, bevor
  /// „Selbsterkenntnis" freigeschaltet wird.
  static const int selbsterkenntnisSchwelle = 10;

  /// Ab dieser prozentualen Distanz zum rundenlokalen Allzeithoch gilt ein Tag
  /// als „Crash-Tiefpunkt" für die „Eiserne Hand".
  static const double eiserneHandSchwelle = 0.30;

  static const List<ErfolgDefinition> alle = [
    ErfolgDefinition(
      id: ErfolgId.eisernehand,
      titel: 'Eiserne Hand',
      beschreibung:
          'Investiert geblieben, während der Kurs mindestens 30 % unter sein bisheriges '
          'Hoch der Runde fiel.',
    ),
    ErfolgDefinition(
      id: ErfolgId.nichtstun,
      titel: 'Ruhe bewahrt',
      beschreibung:
          'Eine Runde von mindestens 10 Jahren durchgehalten, ohne ein einziges Mal zu verkaufen.',
    ),
    ErfolgDefinition(
      id: ErfolgId.derGlueckliche,
      titel: 'Der Glückliche',
      beschreibung:
          'Den Investor geschlagen, obwohl dein Timing schlechter war als bei 80 % der '
          'Zufallsläufe mit gleich vielen Trades – der Markt hat dich getragen, nicht dein Timing.',
    ),
    ErfolgDefinition(
      id: ErfolgId.selbsterkenntnis,
      titel: 'Selbsterkenntnis',
      beschreibung: 'Zehnmal bis zum Ende der Auswertung gescrollt und ehrlich hingeschaut.',
    ),
    ErfolgDefinition(
      id: ErfolgId.zeitreisender,
      titel: 'Zeitreisender',
      beschreibung: 'In mindestens 5 verschiedenen Jahrzehnten der Kursgeschichte gespielt.',
    ),
    ErfolgDefinition(
      id: ErfolgId.alleWetter,
      titel: 'Allwetter',
      beschreibung: 'Sowohl in einer Runde mit steigendem als auch mit fallendem Markt gespielt.',
    ),
    ErfolgDefinition(
      id: ErfolgId.vielspieler,
      titel: 'Vielspieler',
      beschreibung: 'Mindestens 25 Runden gespielt.',
    ),
  ];

  /// Vereinfachung: prüft nur, ob an irgendeinem investierten Tag der Kurs
  /// mindestens [eiserneHandSchwelle] unter dem bis dahin höchsten Kurs der
  /// Runde lag – NICHT, ob seit dem vorherigen Hoch durchgehend gehalten wurde.
  /// Vollständige Pfadverfolgung wäre für ein Achievement unverhältnismäßig
  /// komplex.
  static bool eiserneHand(Kursreihe reihe, List<bool> investiertProTag) {
    if (investiertProTag.isEmpty) return false;
    var ath = reihe.kurs(0);
    for (var d = 0; d < investiertProTag.length; d++) {
      final kurs = reihe.kurs(d);
      if (investiertProTag[d] && kurs <= ath * (1 - eiserneHandSchwelle)) return true;
      ath = math.max(ath, kurs);
    }
    return false;
  }

  static bool nichtstun(double rundenjahre, int anzahlVerkaeufe) =>
      rundenjahre >= 10 && anzahlVerkaeufe == 0;

  static bool derGlueckliche(double scoreVsInvestor, double? perzentil) =>
      scoreVsInvestor > 0 && (perzentil ?? 100) < 20;

  static bool selbsterkenntnis(int scrollZaehler) => scrollZaehler >= selbsterkenntnisSchwelle;

  /// Bezieht sich auf das Jahrzehnt der **gespielten historischen Periode**
  /// (das gezogene Startdatum der Kursreihe), nicht auf das reale Kalenderdatum
  /// des Spielens – passend zum „geheimer Zeitraum"-Kern des Spiels.
  static bool zeitreisender(List<DateTime> startDatenAllerRunden) =>
      startDatenAllerRunden.map((d) => d.year ~/ 10).toSet().length >= 5;

  /// [marktRenditenProRunde]: Gesamtrendite des gespielten Titels je Runde
  /// (nicht annualisiert), bezogen auf die gespielte historische Periode.
  static bool alleWetter(List<double> marktRenditenProRunde) =>
      marktRenditenProRunde.any((r) => r > 0) && marktRenditenProRunde.any((r) => r < 0);

  static bool vielspieler(int anzahlRundenGesamt) => anzahlRundenGesamt >= 25;
}
