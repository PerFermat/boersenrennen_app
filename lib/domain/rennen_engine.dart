import 'dart:math' as math;

import 'kursreihe.dart';
import 'spiel_konfiguration.dart';
import 'strategie.dart';

/// Die Simulation einer Rennrunde – wörtlicher Port der erprobten
/// JavaScript-Logik aus `rennen.js` der Web-Version.
///
/// Reines Dart, **kein Flutter-Import**: dadurch vollständig unit-testbar.
///
/// Wichtige Semantik (leicht zu verlieren beim Portieren):
///  * Die Verzinsung passiert **vor** dem Vorrücken auf den neuen Kurs und
///    rechnet mit **Kalendertagen** zwischen zwei Handelstagen (Fr→Mo = 3).
///  * Das Allzeithoch ist **rundenlokal** und startet beim ersten Kurs.
///  * Der Monatswechsel wird über `jahr*12 + monat` erkannt; der erste Tag
///    setzt nur den Startwert – an ihm gibt es **keine** Einzahlung.
///  * Die automatische Einzahlung des Spielers zahlt Slippage, die des
///    Investors nicht (er ist die Benchmark).
class RennenEngine {
  final Kursreihe reihe;
  final SpielKonfiguration cfg;

  /// Bis zu ein Kalenderjahr Historie **vor** [reihe] (siehe
  /// `RundenAuswahl.vorlauf`) – nur für Rendite-Rückgriffe nahe Rundenbeginn,
  /// wenn [reihe] selbst noch nicht weit genug zurückreicht. Nimmt nicht an
  /// der Simulation teil. Standardmäßig leer.
  final Kursreihe vorlauf;

  final Strategie spieler = Strategie('Du');
  final Strategie investor = Strategie('Investor');
  final Strategie sicherheit = Strategie('Sicherheit');

  /// Index des aktuellen Handelstags in [reihe].
  int i = 0;

  /// Kurs am aktuellen Tag.
  double kurs;

  /// Höchstkurs seit Rundenbeginn (Marktstimmung).
  double ath;

  /// Animationsphase der Läuferbeine – wird vom Controller fortgeschrieben.
  double phase = 0;

  bool fertig = false;

  int _letzterYM;

  /// Anzahl erfolgter Einzahlungen (für Tests und Statistik).
  int einzahlungen = 0;

  /// Schwelle für die Jahresrendite, ab der Rennstreifen gezeichnet werden.
  static const double starkSteigendSchwelle = 0.10;

  /// Schwelle für die Monatsrendite, unterhalb derer ein Stolpern ausgelöst wird.
  static const double stolperSchwelle = -0.10;

  /// Mindestabstand zwischen zwei Stolperern, in Kalendertagen – sonst würde
  /// eine länger anhaltende Abwärtsphase das Bild unruhig machen.
  static const int stolperKuehlzeitTage = 365;

  int? _letzterStolperTag;

  /// Einmaliger Auslöse-Puls: `true` genau in dem `schritt()`-Aufruf, der ein
  /// Stolpern auslöst, sonst `false`. Der Controller fragt dies **pro Schritt**
  /// ab (nicht nur einmal pro Frame), da bei hohem Tempo mehrere Schritte in
  /// einem Frame passieren können.
  bool stolpertJetzt = false;

  RennenEngine(this.reihe, this.cfg, {Kursreihe? vorlauf})
      : vorlauf = vorlauf ?? Kursreihe.ausListen(const [], const []),
        kurs = reihe.kurs(0),
        ath = reihe.kurs(0),
        _letzterYM = _ym(reihe.epochTag(0)) {
    // Spieler startet in Cash, entscheidet selbst.
    spieler.cash = cfg.startCash;
    // Sicherheit legt alles fest verzinst an.
    sicherheit.cash = cfg.startCash;
    // Investor ist von Beginn an voll investiert (ohne Slippage).
    investor.stueck = cfg.startCash / kurs;
    investor.investiert = true;
  }

  static int _ym(int epochTag) {
    final d = Kursreihe.zuDatum(epochTag);
    return d.year * 12 + d.month;
  }

  /// Aktuelles Datum als UTC-DateTime.
  DateTime get datum => Kursreihe.zuDatum(reihe.epochTag(i));

  /// Kurs relativ zum Allzeithoch (1.0 = am Hoch). Steuert das Lauftempo.
  double get stimmung => ath > 0 ? kurs / ath : 1.0;

  /// Kurs ungefähr [tage] Kalendertage vor dem aktuellen Handelstag, oder
  /// `null`, wenn nicht einmal [vorlauf] so weit zurückreicht.
  ///
  /// Sucht zuerst im laufenden Rundenausschnitt [reihe]; reicht der nicht
  /// weit genug zurück (Rundenbeginn liegt näher als [tage] Tage), wird der
  /// bis zu ein Jahr vor Rundenbeginn reichende [vorlauf] herangezogen –
  /// dieselben zugrunde liegenden Daten, lückenlos direkt vor [reihe].
  double? _kursVor(int tage) {
    final zielTag = reihe.epochTag(i) - tage;

    if (zielTag >= reihe.ersterTag) {
      return reihe.kurs(reihe.binaereSuche(zielTag));
    }

    if (vorlauf.laenge == 0) return null;
    final idx = vorlauf.binaereSuche(zielTag);
    if (idx >= vorlauf.laenge) {
      // Ziel fällt in eine Handelslücke zwischen Vorlauf-Ende und
      // Rundenbeginn (z. B. Wochenende) – nächstliegender Kurs ist Tag 0.
      return reihe.kurs(0);
    }
    if (idx == 0 && vorlauf.ersterTag > zielTag) {
      return null; // selbst der Vorlauf reicht nicht so weit zurück.
    }
    return vorlauf.kurs(idx);
  }

  double? _renditeUeber(int tage) {
    final basis = _kursVor(tage);
    if (basis == null || basis == 0) return null;
    return (kurs - basis) / basis;
  }

  /// Rendite der letzten 365 Kalendertage. `null` ohne ausreichende Historie.
  double? get renditeJahr => _renditeUeber(365);

  /// Rendite der letzten 30 Kalendertage. `null` ohne ausreichende Historie.
  double? get renditeMonat => _renditeUeber(30);

  /// Ob Rennstreifen gezeichnet werden dürfen (zusätzlich zu „investiert").
  bool get starkSteigend => (renditeJahr ?? 0) > starkSteigendSchwelle;

  /// Ein Handelstag weiter.
  void schritt() {
    stolpertJetzt = false;

    if (i >= reihe.laenge - 1) {
      fertig = true;
      return;
    }

    final vorherTag = reihe.epochTag(i);
    i++;
    final neuerTag = reihe.epochTag(i);
    final neuerKurs = reihe.kurs(i);

    // 1) Zinsen über die tatsächlich vergangenen Kalendertage.
    final tage = neuerTag - vorherTag;
    if (tage > 0 && cfg.zinssatz > 0) {
      sicherheit.cash *= math.pow(1 + cfg.zinssatz / 100, tage / 365).toDouble();
    }

    kurs = neuerKurs;
    if (neuerKurs > ath) ath = neuerKurs;

    // 1b) Crash-Erkennung fürs Stolpern der Läufer, höchstens einmal pro
    // stolperKuehlzeitTage – sonst würde eine längere Abwärtsphase das Bild
    // unruhig machen.
    final renditeMonat = _renditeUeber(30);
    if (renditeMonat != null && renditeMonat < stolperSchwelle) {
      final abgekuehlt = _letzterStolperTag == null ||
          neuerTag - _letzterStolperTag! >= stolperKuehlzeitTage;
      if (abgekuehlt) {
        stolpertJetzt = true;
        _letzterStolperTag = neuerTag;
      }
    }

    // 2) Monatswechsel -> neue Einzahlung.
    final ym = _ym(neuerTag);
    if (ym != _letzterYM) {
      _letzterYM = ym;
      _einzahlung();
    }

    if (i >= reihe.laenge - 1) fertig = true;
  }

  void _einzahlung() {
    final betrag = cfg.monatsEinzahlung;
    einzahlungen++;

    // Spieler: investiert automatisch nur, wenn er gerade investiert ist.
    if (spieler.investiert) {
      spieler.stueck += betrag / (kurs * (1 + cfg.slippage));
    } else {
      spieler.cash += betrag;
    }

    // Investor: sofort voll investiert, ohne Slippage.
    investor.stueck += betrag / kurs;
    investor.investiert = true;

    // Sicherheit: fließt in die Verzinsung.
    sicherheit.cash += betrag;
  }

  /// „Alles kaufen" – schlechterer Ausführungskurs durch Slippage.
  void kaufen() {
    if (fertig || spieler.cash <= 0) return;
    spieler.stueck += spieler.cash / (kurs * (1 + cfg.slippage));
    spieler.cash = 0;
    spieler.investiert = true;
  }

  /// „Alles verkaufen" – schlechterer Ausführungskurs durch Slippage.
  void verkaufen() {
    if (fertig || spieler.stueck <= 0) return;
    spieler.cash += spieler.stueck * (kurs * (1 - cfg.slippage));
    spieler.stueck = 0;
    spieler.investiert = false;
  }

  double get wertSpieler => spieler.depotwert(kurs);
  double get wertInvestor => investor.depotwert(kurs);
  double get wertSicherheit => sicherheit.depotwert(kurs);
}
