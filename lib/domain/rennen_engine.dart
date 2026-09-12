import 'dart:math' as math;

import 'kursreihe.dart';
import 'spiel_konfiguration.dart';
import 'strategie.dart';
import 'trade.dart';

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
///  * Weder die automatische Einzahlung des Spielers noch die des Investors
///    zahlt Slippage – nur manuelle `kaufen()`/`verkaufen()`-Entscheidungen
///    tun das. Sonst läge ein Spieler, der sich exakt wie der Investor
///    verhält (einmalig kaufen, nie wieder handeln), strukturell und
///    unvermeidbar hinter ihm zurück – das widerspräche der Lernbotschaft.
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
  final Strategie wuerfel = Strategie('Würfel');

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

  /// Protokoll aller manuellen Kauf-/Verkaufsentscheidungen. Einzahlungen
  /// zählen nicht dazu – sie sind keine Entscheidung.
  final List<Trade> trades = [];

  /// Laufender Einstandswert der offenen Position. Da der Spieler immer
  /// vollständig kauft und verkauft, ist jede Position beim Verkauf exakt
  /// geschlossen – FIFO-Buchhaltung wäre hier unnötig.
  double _einstand = 0;

  /// Depotwert je gespieltem Tag, Index 0 = Tag der Countdown-Entscheidung.
  /// Wird vom `kurs_chart_painter.dart` gelesen (abschnittsweise Einfärbung).
  final List<double> depotwertProTag = [];

  /// Investitionsstatus je gespieltem Tag, parallel zu [depotwertProTag].
  final List<bool> investiertProTag = [];

  /// Kalenderjahr des zuletzt abgerechneten Steuerjahres – separat vom
  /// Monatswechsel-Zähler [_letzterYM], da die Steuer zum 1. Januar
  /// zurückgesetzt wird, nicht zu jedem Monatswechsel.
  int _letzterSteuerjahr;

  double gezahlteSteuerSpieler = 0;
  double gezahlteSteuerSicherheit = 0;

  /// Verlusttopf des Spielers – NICHT rundenübergreifend, mindert nur künftige
  /// Gewinne innerhalb dieser einen Runde.
  double _spielerVerlusttopf = 0;

  /// Genutzter Sparerpauschbetrag des Spielers im laufenden Kalenderjahr.
  double _spielerFreibetragGenutzt = 0;

  /// Im laufenden Kalenderjahr aufgelaufene Zinsen der Sicherheit – werden
  /// erst zum Jahreswechsel (bzw. Rundenende) versteuert.
  double _sicherheitZinsDiesesJahr = 0;
  double _sicherheitFreibetragGenutzt = 0;
  bool _sicherheitSteuerAmEndeAbgerechnet = false;

  static int _jahr(int epochTag) => Kursreihe.zuDatum(epochTag).year;

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

  /// Ob der Würfel-Investor mitspielt. Engine-Default `false` – bestehende
  /// direkte Konstruktionen (u. a. alle Tests) bleiben dadurch unverändert;
  /// der Spiel-Default „an" ist eine Entscheidung des StartScreens.
  final bool wuerfelAktiv;

  /// Injizierter Seed, damit Trade-Folgen reproduzierbar sind (Tests) und
  /// ein Ergebnis nachvollziehbar bleibt.
  final int wuerfelSeed;
  late final math.Random _wuerfelRandom = math.Random(wuerfelSeed);

  /// Wahrscheinlichkeit, bei jedem Monatswechsel den Investitionsstatus
  /// umzuschalten.
  static const double wuerfelUmschaltWahrscheinlichkeit = 0.15;

  bool wuerfelInvestiert = true;
  double _wuerfelEinstand = 0;
  double _wuerfelVerlusttopf = 0;
  double _wuerfelFreibetragGenutzt = 0;
  double gezahlteSteuerWuerfel = 0;

  /// `null`, solange der Würfel-Investor nicht mitspielt.
  double? get wertWuerfel => wuerfelAktiv ? wuerfel.depotwert(kurs) : null;

  RennenEngine(
    this.reihe,
    this.cfg, {
    Kursreihe? vorlauf,
    this.wuerfelAktiv = false,
    int? wuerfelSeed,
  })  : vorlauf = vorlauf ?? Kursreihe.ausListen(const [], const []),
        wuerfelSeed = wuerfelSeed ?? DateTime.now().microsecondsSinceEpoch,
        kurs = reihe.kurs(0),
        ath = reihe.kurs(0),
        _letzterYM = _ym(reihe.epochTag(0)),
        _letzterSteuerjahr = _jahr(reihe.epochTag(0)) {
    // Spieler startet in Cash, entscheidet selbst.
    spieler.cash = cfg.startCash;
    // Sicherheit legt alles fest verzinst an.
    sicherheit.cash = cfg.startCash;
    // Investor ist von Beginn an voll investiert (ohne Slippage).
    investor.stueck = cfg.startCash / kurs;
    investor.investiert = true;

    if (wuerfelAktiv) {
      // Würfel startet investiert, ohne Slippage (Anfangsposition, keine
      // manuelle Entscheidung).
      wuerfel.stueck = cfg.startCash / kurs;
      wuerfel.investiert = true;
      _wuerfelEinstand = cfg.startCash;
    }

    // Tag 0 = Vor-Entscheidungs-Zustand. Investiert der Spieler im Countdown,
    // korrigiert kaufen() (via investierenImCountdown()) genau diesen Eintrag,
    // bevor überhaupt ein schritt() passieren kann.
    depotwertProTag.add(wertSpieler);
    investiertProTag.add(spieler.investiert);
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

  /// Latente Steuer auf den unrealisierten Buchgewinn des Investors – rein
  /// informativ, wird NIE von [wertInvestor] abgezogen (sonst würde Score/
  /// Bestenliste rückwirkend verzerrt). Reine Funktion des aktuellen
  /// Zustands, darf beliebig oft ohne Seiteneffekt gelesen werden.
  double get latenteSteuerInvestor {
    if (!cfg.steuernAktiv) return 0;
    final eingezahlt = cfg.startCash + cfg.monatsEinzahlung * einzahlungen;
    final buchgewinn = wertInvestor - eingezahlt;
    if (buchgewinn <= 0) return 0;
    final steuerbasis = buchgewinn * (1 - cfg.teilfreistellung);
    final zuVersteuern = math.max(0.0, steuerbasis - cfg.sparerpauschbetrag);
    return zuVersteuern * cfg.steuersatz;
  }

  /// Steuer auf einen realisierten Verkaufsgewinn. Reihenfolge: Verlusttopf
  /// verrechnet sich zuerst gegen den rohen Gewinn, die Teilfreistellung
  /// wirkt auf den Rest, danach zehrt der Sparerpauschbetrag, was übrig
  /// bleibt. Wiederverwendet vom Spieler und vom Würfel-Investor.
  ({double steuer, double verlusttopf, double freibetragGenutzt}) _berechneVerkaufssteuer({
    required double gewinn,
    required double verlusttopf,
    required double freibetragGenutzt,
  }) {
    if (!cfg.steuernAktiv) {
      return (steuer: 0.0, verlusttopf: verlusttopf, freibetragGenutzt: freibetragGenutzt);
    }
    if (gewinn <= 0) {
      return (steuer: 0.0, verlusttopf: verlusttopf - gewinn, freibetragGenutzt: freibetragGenutzt);
    }
    final verrechnet = math.min(verlusttopf, gewinn);
    final steuerbasis = (gewinn - verrechnet) * (1 - cfg.teilfreistellung);
    final freibetragRest = math.max(0.0, cfg.sparerpauschbetrag - freibetragGenutzt);
    final genutztDiesmal = math.min(steuerbasis, freibetragRest);
    return (
      steuer: (steuerbasis - genutztDiesmal) * cfg.steuersatz,
      verlusttopf: verlusttopf - verrechnet,
      freibetragGenutzt: freibetragGenutzt + genutztDiesmal,
    );
  }

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
    var zinsBetrag = 0.0;
    if (tage > 0 && cfg.zinssatz > 0) {
      final cashVorher = sicherheit.cash;
      sicherheit.cash *= math.pow(1 + cfg.zinssatz / 100, tage / 365).toDouble();
      zinsBetrag = sicherheit.cash - cashVorher;
    }

    // 1a) Steuerjahr-Wechsel (zum 1. Januar, unabhängig vom Monatswechsel
    // unten): rechnet die Sicherheit-Zinsen des abgelaufenen Jahres ab und
    // setzt den Spieler-Freibetrag zurück.
    if (cfg.steuernAktiv) {
      final jahr = _jahr(neuerTag);
      if (jahr != _letzterSteuerjahr) {
        _verrechneSicherheitJahressteuer();
        _spielerFreibetragGenutzt = 0;
        _wuerfelFreibetragGenutzt = 0;
        _letzterSteuerjahr = jahr;
      }
      _sicherheitZinsDiesesJahr += zinsBetrag;
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

    depotwertProTag.add(wertSpieler);
    investiertProTag.add(spieler.investiert);

    if (i >= reihe.laenge - 1) beendeRunde();
  }

  /// Schließt die Runde ab (natürlich ODER vorzeitig über eine externe
  /// Beendigung) – muss statt eines direkten `fertig = true` benutzt werden,
  /// sonst bekäme die Sicherheit ihr laufendes Steuer-Teiljahr nie abgerechnet.
  void beendeRunde() {
    fertig = true;
    if (cfg.steuernAktiv && !_sicherheitSteuerAmEndeAbgerechnet) {
      _verrechneSicherheitJahressteuer();
      _sicherheitSteuerAmEndeAbgerechnet = true;
    }
  }

  void _verrechneSicherheitJahressteuer() {
    if (_sicherheitZinsDiesesJahr <= 0) {
      _sicherheitFreibetragGenutzt = 0;
      return;
    }
    final freibetragRest = math.max(0.0, cfg.sparerpauschbetrag - _sicherheitFreibetragGenutzt);
    final genutzt = math.min(_sicherheitZinsDiesesJahr, freibetragRest);
    final steuer = (_sicherheitZinsDiesesJahr - genutzt) * cfg.steuersatz; // ohne Teilfreistellung
    sicherheit.cash -= steuer;
    gezahlteSteuerSicherheit += steuer;
    _sicherheitZinsDiesesJahr = 0;
    _sicherheitFreibetragGenutzt = 0;
  }

  void _einzahlung() {
    final betrag = cfg.monatsEinzahlung;
    einzahlungen++;

    // Spieler: investiert automatisch nur, wenn er gerade investiert ist.
    if (spieler.investiert) {
      spieler.stueck += betrag / kurs;
      _einstand += betrag;
    } else {
      spieler.cash += betrag;
    }

    // Investor: sofort voll investiert, ohne Slippage.
    investor.stueck += betrag / kurs;
    investor.investiert = true;

    // Sicherheit: fließt in die Verzinsung.
    sicherheit.cash += betrag;

    // Würfel-Investor: Einzahlung nach aktuellem Status verbuchen, danach
    // mit fester Wahrscheinlichkeit den Status umschalten. Slippage UND
    // Steuer wie beim Spieler, sonst wäre der Vergleich unfair.
    if (wuerfelAktiv) {
      if (wuerfelInvestiert) {
        wuerfel.stueck += betrag / kurs;
        _wuerfelEinstand += betrag;
      } else {
        wuerfel.cash += betrag;
      }

      if (_wuerfelRandom.nextDouble() < wuerfelUmschaltWahrscheinlichkeit) {
        if (wuerfelInvestiert) {
          final ausfuehrungsKurs = kurs * (1 - cfg.slippage);
          final erloes = wuerfel.stueck * ausfuehrungsKurs;
          final gewinn = erloes - _wuerfelEinstand;
          final r = _berechneVerkaufssteuer(
            gewinn: gewinn,
            verlusttopf: _wuerfelVerlusttopf,
            freibetragGenutzt: _wuerfelFreibetragGenutzt,
          );
          _wuerfelVerlusttopf = r.verlusttopf;
          _wuerfelFreibetragGenutzt = r.freibetragGenutzt;
          gezahlteSteuerWuerfel += r.steuer;
          wuerfel.cash = erloes - r.steuer;
          wuerfel.stueck = 0;
          _wuerfelEinstand = 0;
        } else {
          final ausfuehrungsKurs = kurs * (1 + cfg.slippage);
          wuerfel.stueck += wuerfel.cash / ausfuehrungsKurs;
          _wuerfelEinstand += wuerfel.cash;
          wuerfel.cash = 0;
        }
        wuerfelInvestiert = !wuerfelInvestiert;
        wuerfel.investiert = wuerfelInvestiert;
      }
    }
  }

  /// „Alles kaufen" – schlechterer Ausführungskurs durch Slippage.
  void kaufen() {
    if (fertig || spieler.cash <= 0) return;
    final marktKurs = kurs;
    final ausfuehrungsKurs = kurs * (1 + cfg.slippage);
    final betrag = spieler.cash;
    final stueckGekauft = betrag / ausfuehrungsKurs;

    spieler.stueck += stueckGekauft;
    spieler.cash = 0;
    spieler.investiert = true;
    _einstand += betrag;

    trades.add(Trade(
      tagIndex: i,
      epochTag: reihe.epochTag(i),
      istKauf: true,
      marktKurs: marktKurs,
      ausfuehrungsKurs: ausfuehrungsKurs,
      betrag: betrag,
      stueck: stueckGekauft,
      depotwertDanach: wertSpieler,
    ));
    _korrigiereHeutigenEintrag();
  }

  /// „Alles verkaufen" – schlechterer Ausführungskurs durch Slippage.
  void verkaufen() {
    if (fertig || spieler.stueck <= 0) return;
    final marktKurs = kurs;
    final ausfuehrungsKurs = kurs * (1 - cfg.slippage);
    final stueckVerkauft = spieler.stueck;
    final erloes = stueckVerkauft * ausfuehrungsKurs;

    spieler.stueck = 0;
    spieler.investiert = false;
    final gewinn = erloes - _einstand;
    _einstand = 0;

    final r = _berechneVerkaufssteuer(
      gewinn: gewinn,
      verlusttopf: _spielerVerlusttopf,
      freibetragGenutzt: _spielerFreibetragGenutzt,
    );
    _spielerVerlusttopf = r.verlusttopf;
    _spielerFreibetragGenutzt = r.freibetragGenutzt;
    gezahlteSteuerSpieler += r.steuer;
    spieler.cash += erloes - r.steuer;

    trades.add(Trade(
      tagIndex: i,
      epochTag: reihe.epochTag(i),
      istKauf: false,
      marktKurs: marktKurs,
      ausfuehrungsKurs: ausfuehrungsKurs,
      betrag: erloes,
      stueck: stueckVerkauft,
      depotwertDanach: wertSpieler,
      gewinnBeiVerkauf: gewinn,
    ));
    _korrigiereHeutigenEintrag();
  }

  /// Die manuelle Entscheidung fällt am **heutigen** Tag – korrigiert deshalb
  /// den letzten (noch nicht abgeschlossenen) Eintrag statt einen neuen
  /// anzulegen. Analog zum früheren `RennenController._aktualisiereHeutigenVerlaufsEintrag()`.
  void _korrigiereHeutigenEintrag() {
    depotwertProTag[depotwertProTag.length - 1] = wertSpieler;
    investiertProTag[investiertProTag.length - 1] = spieler.investiert;
  }

  double get wertSpieler => spieler.depotwert(kurs);
  double get wertInvestor => investor.depotwert(kurs);
  double get wertSicherheit => sicherheit.depotwert(kurs);
}
