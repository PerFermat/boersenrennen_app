import 'dart:math' as math;

import 'kursreihe.dart';

/// Jährliche deutsche Inflationsrate (Verbraucherpreisindex ggü. Vorjahr, in %).
/// Quelle: Statistisches Bundesamt (Destatis), Genesis-Tabelle 61111-0001.
///
/// WICHTIG vor Festschreibung: Diese Tabelle stammt aus einer Web-Recherche
/// (Destatis-abgeleitete Sekundärquelle, Abruf September 2026, gegen bekannte
/// Eckwerte 2021–2024 plausibilisiert) – vor dem endgültigen Commit noch
/// einmal direkt gegen die Destatis-Originaltabelle abgleichen, nicht
/// ungeprüft übernehmen.
///
/// Die Kursdaten dieser App sind gemischt deutsch/US-amerikanisch, die
/// Anzeige erfolgt aber durchgängig in Euro. Eine einzige deutsche Reihe ist
/// deshalb die konsistente Wahl (bewusste Vereinfachung) – eine US-Aktie wird
/// also mit deutscher, nicht amerikanischer Inflation auf Kaufkraft gerechnet.
const Map<int, double> _jahresteuerungDE = {
  1994: 2.651,
  1995: 1.865,
  1996: 1.408,
  1997: 1.944,
  1998: 0.817,
  1999: 0.676,
  2000: 1.342,
  2001: 1.987,
  2002: 1.429,
  2003: 1.024,
  2004: 1.648,
  2005: 1.621,
  2006: 1.595,
  2007: 2.295,
  2008: 2.597,
  2009: 0.345,
  2010: 1.032,
  2011: 2.157,
  2012: 1.889,
  2013: 1.527,
  2014: 0.967,
  2015: 0.532,
  2016: 0.529,
  2017: 1.474,
  2018: 1.763,
  2019: 1.427,
  2020: 0.503,
  2021: 3.100,
  2022: 6.887,
  2023: 5.898,
  2024: 2.228,
};

/// Ergebnis von [Inflation.preisfaktorMitAbdeckung].
class Preisfaktor {
  /// Kumulierter Faktor über den abgedeckten Teil des Zeitraums.
  final double faktor;

  /// Anteil der Tage des Zeitraums, für die eine Teuerungsrate vorlag (0..1).
  /// Jahre ohne Eintrag tragen Faktor 1.0 bei – ohne diesen Wert wäre nicht
  /// unterscheidbar, ob der Euro seine Kaufkraft tatsächlich behalten hat oder
  /// ob schlicht die Daten fehlen. Genau das ist der Normalfall: die Tabelle
  /// endet bei [Inflation.letztesJahr], die Kursdaten reichen weiter.
  final double abdeckung;

  const Preisfaktor(this.faktor, this.abdeckung);

  /// Ab dieser Abdeckung gilt die Kaufkraft-Aussage als belastbar genug, um
  /// sie überhaupt anzuzeigen.
  static const double mindestAbdeckung = 0.95;

  bool get istBelastbar => abdeckung >= mindestAbdeckung;
}

/// Umrechnung nominaler Endbeträge in reale Kaufkraft. Reines Dart.
class Inflation {
  static double? rateFuer(int jahr) => _jahresteuerungDE[jahr];

  /// Frühestes und spätestes Jahr der Tabelle – damit Hinweise und Tests nicht
  /// auf feste Jahreszahlen festgenagelt sind.
  static int get erstesJahr => _jahresteuerungDE.keys.reduce(math.min);
  static int get letztesJahr => _jahresteuerungDE.keys.reduce(math.max);

  /// Taggenau interpolierter Kaufkraft-Faktor zwischen zwei Epochtagen, plus
  /// dem Anteil des Zeitraums, für den überhaupt Daten vorlagen.
  ///
  /// Jahre ohne Datenabdeckung tragen Faktor 1.0 bei (still übersprungen,
  /// keine Exception) – sie senken aber [Preisfaktor.abdeckung], damit der
  /// Aufrufer eine unvollständige Aussage von einer echten Nullteuerung
  /// unterscheiden kann.
  static Preisfaktor preisfaktorMitAbdeckung(int vonEpochTag, int bisEpochTag) {
    if (bisEpochTag <= vonEpochTag) return const Preisfaktor(1.0, 1.0);
    var faktor = 1.0;
    var abgedeckteTage = 0;
    var tag = vonEpochTag;
    while (tag < bisEpochTag) {
      final jahr = Kursreihe.zuDatum(tag).year;
      final jahresStart = Kursreihe.zuEpochTag(DateTime.utc(jahr, 1, 1));
      final jahresEnde = Kursreihe.zuEpochTag(DateTime.utc(jahr + 1, 1, 1));
      final abschnittEnde = math.min(jahresEnde, bisEpochTag);
      final tageImAbschnitt = abschnittEnde - tag;
      final rate = _jahresteuerungDE[jahr];
      if (rate != null) {
        final tageImJahr = jahresEnde - jahresStart;
        faktor *= math.pow(1 + rate / 100, tageImAbschnitt / tageImJahr).toDouble();
        abgedeckteTage += tageImAbschnitt;
      }
      tag = abschnittEnde;
    }
    return Preisfaktor(faktor, abgedeckteTage / (bisEpochTag - vonEpochTag));
  }

  /// Nur der Faktor – für Aufrufer, denen die Vollständigkeit egal ist.
  static double preisfaktor(int vonEpochTag, int bisEpochTag) =>
      preisfaktorMitAbdeckung(vonEpochTag, bisEpochTag).faktor;
}
