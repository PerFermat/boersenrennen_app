import 'dart:math' as math;

import 'inflation.dart';
import 'kursreihe.dart';
import 'rennen_engine.dart';
import 'spiel_konfiguration.dart';
import 'spieler_pfad.dart';
import 'trade.dart';

/// Ein einzelner Handelstag mit seiner Tagesrendite und dem daraus
/// entgangenen bzw. vermiedenen Euro-Betrag (siehe [RundenAuswertung.aus]).
class TopTag {
  final int tagIndex;
  final int epochTag;
  final double tagesrendite;
  final double betrag;

  const TopTag(this.tagIndex, this.epochTag, this.tagesrendite, this.betrag);
}

/// Kontrafaktische Wiederholung der Runde ohne genau einen Trade – alle
/// übrigen Entscheidungen bleiben an ihren ursprünglichen Handelstagen
/// bestehen. Ein durch das Auslassen ins Leere laufender späterer Verkauf
/// (z. B. wenn ein früher Kauf fehlt) ist unkritisch: Der zugrunde liegende
/// [simuliereSpielerpfad] addiert dann schlicht `0 * Kurs` zum Cash.
double simuliereOhneTrade(
  Kursreihe reihe,
  SpielKonfiguration cfg,
  List<Trade> trades,
  int ausgelassenerIndex,
) {
  final aktionen = <GeplanteAktion>[
    for (var i = 0; i < trades.length; i++)
      if (i != ausgelassenerIndex) GeplanteAktion(trades[i].tagIndex, trades[i].istKauf),
  ];
  final ergebnis =
      simuliereSpielerpfad(reihe: reihe, cfg: cfg, aktionen: aktionen, mitSlippage: true);
  return ergebnis.endwert(reihe.kurs(reihe.laenge - 1));
}

/// Alle Entscheidungen umgekehrt: aus jedem Kauf wird ein Verkauf und
/// umgekehrt, an denselben Handelstagen.
double simuliereUmgekehrt(Kursreihe reihe, SpielKonfiguration cfg, List<Trade> trades) {
  final aktionen = [for (final t in trades) GeplanteAktion(t.tagIndex, !t.istKauf)];
  final ergebnis =
      simuliereSpielerpfad(reihe: reihe, cfg: cfg, aktionen: aktionen, mitSlippage: true);
  return ergebnis.endwert(reihe.kurs(reihe.laenge - 1));
}

/// Alle Entscheidungen um [handelstage] Handelstage verschoben (positiv =
/// später). Trades, die dadurch vor Tag 0 oder über das Rundenende hinaus
/// fallen, fallen ersatzlos weg – ein Verkauf ohne Bestand ist in
/// [simuliereSpielerpfad] bereits ein No-op.
double simuliereMitVersatz(
  Kursreihe reihe,
  SpielKonfiguration cfg,
  List<Trade> trades,
  int handelstage,
) {
  final aktionen = <GeplanteAktion>[
    for (final t in trades)
      if (t.tagIndex + handelstage >= 0 && t.tagIndex + handelstage < reihe.laenge)
        GeplanteAktion(t.tagIndex + handelstage, t.istKauf),
  ]..sort((a, b) => a.tagIndex.compareTo(b.tagIndex));
  final ergebnis =
      simuliereSpielerpfad(reihe: reihe, cfg: cfg, aktionen: aktionen, mitSlippage: true);
  return ergebnis.endwert(reihe.kurs(reihe.laenge - 1));
}

/// Gar keine Entscheidung: der Zustand nach dem Countdown wird bis zum
/// Rundenende durchgehalten.
double simuliereOhneEntscheidungen(
    Kursreihe reihe, SpielKonfiguration cfg, List<Trade> trades) {
  final investiertAbStart = trades.isNotEmpty && trades.first.tagIndex == 0 && trades.first.istKauf;
  final aktionen = investiertAbStart ? const [GeplanteAktion(0, true)] : const <GeplanteAktion>[];
  final ergebnis =
      simuliereSpielerpfad(reihe: reihe, cfg: cfg, aktionen: aktionen, mitSlippage: true);
  return ergebnis.endwert(reihe.kurs(reihe.laenge - 1));
}

/// Ergebnis einer um [handelstage] verschobenen Wiedergabe (siehe
/// [simuliereMitVersatz]). `handelstage == 0` ist das tatsächliche Ergebnis.
class VersatzErgebnis {
  final int handelstage;
  final double endwert;
  const VersatzErgebnis(this.handelstage, this.endwert);
}

// ---------------------------------------------------------------------------
//  Behavior Gap (V10)
// ---------------------------------------------------------------------------

/// Bewusst dupliziert statt eine private Methode aus `rennen_engine.dart`
/// fremdzuimportieren – Dart-Sichtbarkeit mit führendem Unterstrich ist pro
/// Datei, nicht pro Klasse. Dasselbe 3-Zeiler-Muster wie in `spieler_pfad.dart`.
int _ym(int epochTag) {
  final d = Kursreihe.zuDatum(epochTag);
  return d.year * 12 + d.month;
}

/// Epochtage aller Monatswechsel innerhalb `[1, bisIndex]` – exakt die Tage,
/// an denen die Engine eine Einzahlung verbucht hätte.
List<int> _einzahlungsTage(Kursreihe reihe, int bisIndex) {
  final ergebnis = <int>[];
  var letzterYM = _ym(reihe.epochTag(0));
  for (var i = 1; i <= bisIndex; i++) {
    final ym = _ym(reihe.epochTag(i));
    if (ym != letzterYM) {
      letzterYM = ym;
      ergebnis.add(reihe.epochTag(i));
    }
  }
  return ergebnis;
}

/// Reine Bisektion über eine Liste von Zahlungsströmen (Tag, Betrag) –
/// unabhängig von der Engine testbar. Bisektion auf `[-0.99, 10.0]`,
/// 200 Iterationen, Abbruch bei `1e-9`. Newton ist hier ungeeignet, weil das
/// Vorzeichenmuster der Zahlungsströme mehrere Nullstellen erlauben kann.
/// `null`, wenn die Zahlungsströme keinen Vorzeichenwechsel haben (keine
/// eindeutige Lösung).
double? irrBisektion(List<({int tag, double betrag})> stroeme) {
  final basisTag = stroeme.first.tag;
  double kapitalwert(double r) => stroeme.fold(
      0.0, (s, z) => s + z.betrag / math.pow(1 + r, (z.tag - basisTag) / 365.25));

  var lo = -0.99, hi = 10.0;
  var fLo = kapitalwert(lo);
  final fHi = kapitalwert(hi);
  if (fLo == 0) return lo;
  if (fHi == 0) return hi;
  if (fLo.sign == fHi.sign) return null;

  for (var i = 0; i < 200; i++) {
    final mitte = (lo + hi) / 2;
    final fMitte = kapitalwert(mitte);
    if (fMitte.abs() < 1e-9) return mitte;
    if (fMitte.sign == fLo.sign) {
      lo = mitte;
      fLo = fMitte;
    } else {
      hi = mitte;
    }
  }
  return (lo + hi) / 2;
}

/// Interner Zinsfuß über alle Zahlungsströme des Spielers: Startkapital und
/// jede Monatseinzahlung negativ zum jeweiligen Datum, der Endwert positiv
/// zum letzten simulierten Tag. Annualisiert. `null` ohne Vorzeichenwechsel.
double? geldgewichteteRendite(RennenEngine engine) {
  final letzterTag = engine.reihe.epochTag(engine.i);
  final stroeme = [
    (tag: engine.reihe.ersterTag, betrag: -engine.cfg.startCash),
    for (final t in _einzahlungsTage(engine.reihe, engine.i))
      (tag: t, betrag: -engine.cfg.monatsEinzahlung),
    (tag: letzterTag, betrag: engine.wertSpieler),
  ];
  return irrBisektion(stroeme);
}

/// Zeitgewichtete (annualisierte) Rendite des gespielten Titels selbst –
/// unabhängig von Sparplan/Timing, reines Kurswachstum über die Runde.
double? zeitgewichteteRendite(RennenEngine engine) {
  final jahre = (engine.reihe.epochTag(engine.i) - engine.reihe.ersterTag) / 365.25;
  if (jahre <= 0 || engine.reihe.kurs(0) <= 0) return null;
  return math.pow(engine.kurs / engine.reihe.kurs(0), 1 / jahre).toDouble() - 1;
}

// ---------------------------------------------------------------------------
//  Verhaltensprofil (V11)
// ---------------------------------------------------------------------------

/// Mittlerer Abstand (in Handelstagen) zwischen jedem Trade in [trades] und
/// dem Extremum (Tief bei [tiefpunkt]=true, sonst Hoch) der folgenden 120
/// Handelstage – bzw. bis zum Rundenende, wenn die Runde vorher aufhört.
/// `null` bei 0 Trades.
double? _mittlererAbstandZuExtremum(
  List<Trade> trades,
  Kursreihe reihe, {
  required bool tiefpunkt,
}) {
  if (trades.isEmpty) return null;
  var summe = 0;
  for (final t in trades) {
    final ende = math.min(t.tagIndex + 120, reihe.laenge - 1);
    var extremIndex = t.tagIndex;
    var extremKurs = reihe.kurs(t.tagIndex);
    for (var i = t.tagIndex + 1; i <= ende; i++) {
      final k = reihe.kurs(i);
      if (tiefpunkt ? k < extremKurs : k > extremKurs) {
        extremKurs = k;
        extremIndex = i;
      }
    }
    summe += extremIndex - t.tagIndex;
  }
  return summe / trades.length;
}

/// „Der teuerste Klick" – der Trade, dessen Weglassen den Endwert am meisten
/// verbessert hätte. Ist [kosten] negativ (der Trade half tatsächlich am
/// meisten), wird stattdessen „Dein bester Klick" mit positivem Vorzeichen
/// angezeigt – siehe [istBesterKlick].
class TeuersterKlick {
  final Trade trade;
  final double endstandTatsaechlich;
  final double endstandOhneKlick;

  /// `endstandOhneKlick - endstandTatsaechlich`. Positiv = der Trade hat
  /// gekostet (teuerster Klick), negativ = er hat geholfen (bester Klick).
  final double kosten;

  bool get istBesterKlick => kosten < 0;

  const TeuersterKlick({
    required this.trade,
    required this.endstandTatsaechlich,
    required this.endstandOhneKlick,
    required this.kosten,
  });
}

/// Kennzahlen einer gespielten Runde – einmalig aus der fertigen (oder vorzeitig
/// beendeten) [RennenEngine] berechnet. Reines Dart, keine Flutter-Imports.
///
/// Konvention: Zahlenfelder, die eine Quote/einen Durchschnitt über eine
/// möglicherweise leere Grundgesamtheit ausdrücken, liefern `null` statt `0`
/// oder `NaN`, wenn diese Grundgesamtheit leer ist (z. B. kein einziger Trade).
/// Reine Zählfelder liefern in diesem Fall `0`.
class RundenAuswertung {
  final int tageInvestiert;
  final int tageAussen;

  final int anzahlKaeufe;
  final int anzahlVerkaeufe;

  /// Kalendertage je geschlossener Position, gemittelt. Eine am Rundenende
  /// noch offene Position zählt bis zum letzten gespielten Tag mit.
  /// `null`, wenn keine einzige Position (weder offen noch geschlossen) bestand.
  final double? durchschnittlicheHaltedauerTage;

  /// `null`, wenn nie verkauft wurde.
  final Trade? besterTrade;
  final Trade? schlechtesterTrade;

  /// Betragsgewichteter Durchschnittskurs (Σbetrag / Σstueck), `null` bei 0 Käufen/Verkäufen.
  final double? durchschnittlicherKaufkurs;
  final double? durchschnittlicherVerkaufskurs;

  final double endwertSpieler;
  final double endwertInvestor;
  final double endwertSicherheit;

  final double differenzZuInvestorEuro;
  final int differenzInMonatsEinzahlungen;

  /// So viele Handelstage nach einem Crash-Tag zählt ein verpasster Top-Tag
  /// noch als „im selben Cluster" (siehe [clusterAnteil]).
  static const int clusterFensterTage = 15;

  /// Tagesrendite, ab der ein Tag als „Crash-Tag" gilt (siehe [clusterAnteil]).
  static const double crashSchwelle = -0.03;

  /// Bis zu 5 Tage außerhalb des Marktes mit dem größten verpassten Gewinn.
  final List<TopTag> verpassteTopTage;

  /// Bis zu 5 Tage außerhalb des Marktes mit dem größten vermiedenen Verlust
  /// (negative Beträge).
  final List<TopTag> vermiedeneTopTage;

  /// Summe **aller** Außenmarkt-Tage mit positivem entgangenem Betrag (nicht
  /// nur der Top 5).
  final double summeVerpasst;

  /// Summe **aller** Außenmarkt-Tage mit negativem (vermiedenem) Betrag.
  final double summeVermieden;

  double get nettoBilanz => summeVerpasst + summeVermieden;

  /// Von den [verpassteTopTage]: wie viele liegen innerhalb von
  /// [clusterFensterTage] Handelstagen nach einem Crash-Tag.
  final int clusterAnteil;

  /// Referenz: Endwert einer durchgehend investierten Strategie – das ist
  /// exakt der Investor, keine erneute Simulation nötig.
  final double endwertImmerInvestiert;

  /// Referenz: Endwert, wenn eine durchgehend investierte Strategie
  /// zusätzlich genau die 5 besten Einzeltage der ganzen Runde verpasst hätte.
  final double endwertOhneBesteFuenfTage;

  /// Referenz: Endwert, wenn eine durchgehend investierte Strategie
  /// zusätzlich genau die 5 schlechtesten Einzeltage der ganzen Runde
  /// vermieden hätte.
  final double endwertOhneSchlechtesteFuenfTage;

  /// `null` bei 0 Trades.
  final TeuersterKlick? teuersterKlick;

  /// Steuerlast des Spielers (gezahlt **plus** latent auf seine am Ende noch
  /// offene Position) minus latente Steuer des Investors – der Steuernachteil
  /// des Handelns gegenüber dem Stunden bis zum Rundenende. Die latente Seite
  /// des Spielers gehört zwingend dazu: ohne sie erschiene ein investiert
  /// endender Spieler als steuerlich günstiger, obwohl er dieselbe Stundung
  /// genießt wie der Investor. `0`, wenn Steuern deaktiviert sind.
  final double steuerNachteilGegenInvestor;

  /// Kumulierter Preisfaktor über die gesamte gespielte Zeit. Kaufkraft in
  /// Preisen des Rundenbeginns, nicht in heutigen Preisen.
  final double preisfaktorGesamt;

  final double endwertSpielerReal, endwertInvestorReal, endwertSicherheitReal;

  /// Ob die Inflationstabelle den gespielten Zeitraum weit genug abdeckt, um
  /// eine Kaufkraft-Aussage zu tragen (siehe [Preisfaktor.istBelastbar]).
  /// Ist das `false`, sind alle `…Real`-Werte zwar berechnet, aber zu
  /// optimistisch – die UI blendet den Block dann aus, statt eine
  /// Nullteuerung zu behaupten, die nur aus fehlenden Daten stammt.
  final bool kaufkraftIstBelastbar;

  /// Kern von V4: real (nach Kaufkraft) liegt die Sicherheit sogar unter der
  /// Summe der Einzahlungen – diese selbst ebenfalls auf Preise des
  /// Rundenbeginns zurückgerechnet, sonst verglichen sich zwei Preisstände.
  /// `false`, wenn die Kaufkraft-Aussage nicht belastbar ist.
  final bool sicherheitRealUnterEinzahlungen;

  final double endwertUmgekehrt;
  final double endwertOhneEntscheidungen;

  /// Für Handelstage-Versatz -60, -20, +20, +60, aufsteigend sortiert.
  final List<VersatzErgebnis> versatzErgebnisse;

  /// Nur `true`, wenn die Streuung der Versatz-Ergebnisse tatsächlich größer
  /// ist als der Abstand zum Investor – geprüft, nicht pauschal behauptet.
  bool get timingWarUeberwiegendRauschen {
    if (versatzErgebnisse.isEmpty) return false;
    final werte = versatzErgebnisse.map((v) => v.endwert);
    final streuung = werte.reduce((a, b) => a > b ? a : b) - werte.reduce((a, b) => a < b ? a : b);
    return streuung > (endwertSpieler - endwertInvestor).abs();
  }

  /// Geldgewichtete (IRR) Rendite des Spielers über alle seine Zahlungsströme.
  /// `null`, wenn die Zahlungsströme keinen Vorzeichenwechsel haben.
  final double? geldgewichteteRenditeSpieler;

  /// Zeitgewichtete Rendite des Titels selbst über denselben Zeitraum.
  final double? zeitgewichteteRenditeTitel;

  /// Lücke zwischen dem, was der Markt lieferte, und dem, was das Geld des
  /// Spielers tatsächlich verdiente – in Euro. `null`, wenn eine der beiden
  /// Renditen nicht bestimmbar ist.
  final double? behaviorGapEuro;
  final int? behaviorGapInMonatsEinzahlungen;

  /// Mittlerer Abstand (Handelstage) zwischen einem Verkauf und dem
  /// darauffolgenden Tiefpunkt innerhalb von 120 Handelstagen. `null` bei
  /// 0 Verkäufen.
  final double? abstandVerkaufZuTiefTage;

  /// Mittlerer Abstand (Handelstage) zwischen einem Kauf und dem
  /// darauffolgenden Hochpunkt innerhalb von 120 Handelstagen. `null` bei
  /// 0 Käufen.
  final double? abstandKaufZuHochTage;

  /// Anteil der Verkäufe, die innerhalb von [clusterFensterTage] Handelstagen
  /// nach einem Crash-Tag ([crashSchwelle]) erfolgten. `null` bei 0 Verkäufen.
  final double? anteilVerkaeufeNachCrash;

  const RundenAuswertung._({
    required this.tageInvestiert,
    required this.tageAussen,
    required this.anzahlKaeufe,
    required this.anzahlVerkaeufe,
    required this.durchschnittlicheHaltedauerTage,
    required this.besterTrade,
    required this.schlechtesterTrade,
    required this.durchschnittlicherKaufkurs,
    required this.durchschnittlicherVerkaufskurs,
    required this.endwertSpieler,
    required this.endwertInvestor,
    required this.endwertSicherheit,
    required this.differenzZuInvestorEuro,
    required this.differenzInMonatsEinzahlungen,
    required this.verpassteTopTage,
    required this.vermiedeneTopTage,
    required this.summeVerpasst,
    required this.summeVermieden,
    required this.clusterAnteil,
    required this.endwertImmerInvestiert,
    required this.endwertOhneBesteFuenfTage,
    required this.endwertOhneSchlechtesteFuenfTage,
    required this.teuersterKlick,
    required this.steuerNachteilGegenInvestor,
    required this.preisfaktorGesamt,
    required this.kaufkraftIstBelastbar,
    required this.endwertSpielerReal,
    required this.endwertInvestorReal,
    required this.endwertSicherheitReal,
    required this.sicherheitRealUnterEinzahlungen,
    required this.endwertUmgekehrt,
    required this.endwertOhneEntscheidungen,
    required this.versatzErgebnisse,
    required this.geldgewichteteRenditeSpieler,
    required this.zeitgewichteteRenditeTitel,
    required this.behaviorGapEuro,
    required this.behaviorGapInMonatsEinzahlungen,
    required this.abstandVerkaufZuTiefTage,
    required this.abstandKaufZuHochTage,
    required this.anteilVerkaeufeNachCrash,
  });

  factory RundenAuswertung.aus(RennenEngine engine) {
    var tageInvestiert = 0;
    for (final investiert in engine.investiertProTag) {
      if (investiert) tageInvestiert++;
    }
    final tageAussen = engine.investiertProTag.length - tageInvestiert;

    final kaeufe = engine.trades.where((t) => t.istKauf).toList();
    final verkaeufe = engine.trades.where((t) => !t.istKauf).toList();

    final haltedauern = <int>[];
    int? offenerKaufTag;
    for (final t in engine.trades) {
      if (t.istKauf) {
        offenerKaufTag = t.epochTag;
      } else if (offenerKaufTag != null) {
        haltedauern.add(t.epochTag - offenerKaufTag);
        offenerKaufTag = null;
      }
    }
    if (offenerKaufTag != null) {
      final letzterTag = engine.reihe.epochTag(engine.i);
      haltedauern.add(letzterTag - offenerKaufTag);
    }
    final durchschnittlicheHaltedauerTage = haltedauern.isEmpty
        ? null
        : haltedauern.reduce((a, b) => a + b) / haltedauern.length;

    Trade? bester;
    Trade? schlechtester;
    for (final t in verkaeufe) {
      if (bester == null || t.gewinnBeiVerkauf! > bester.gewinnBeiVerkauf!) bester = t;
      if (schlechtester == null || t.gewinnBeiVerkauf! < schlechtester.gewinnBeiVerkauf!) {
        schlechtester = t;
      }
    }

    double? volumenGewichteterKurs(List<Trade> handel) {
      if (handel.isEmpty) return null;
      final summeBetrag = handel.fold(0.0, (s, t) => s + t.betrag);
      final summeStueck = handel.fold(0.0, (s, t) => s + t.stueck);
      return summeStueck == 0 ? null : summeBetrag / summeStueck;
    }

    final endwertSpieler = engine.wertSpieler;
    final endwertInvestor = engine.wertInvestor;
    final differenz = endwertSpieler - endwertInvestor;

    // ---- Verpasste/vermiedene Börsentage (symmetrisch) ----
    final reihe = engine.reihe;
    final tagesrendite = List<double>.filled(reihe.laenge, 0);
    for (var d = 1; d < reihe.laenge; d++) {
      tagesrendite[d] = reihe.kurs(d) / reihe.kurs(d - 1) - 1;
    }

    final ausserhalb = <TopTag>[];
    for (var d = 1; d < engine.investiertProTag.length; d++) {
      if (engine.investiertProTag[d - 1]) continue; // war investiert -> kein Außenmarkt-Tag
      final betrag = engine.depotwertProTag[d - 1] * tagesrendite[d];
      ausserhalb.add(TopTag(d, reihe.epochTag(d), tagesrendite[d], betrag));
    }

    final verpasst = ausserhalb.where((t) => t.betrag > 0).toList()
      ..sort((a, b) => b.betrag.compareTo(a.betrag));
    final vermieden = ausserhalb.where((t) => t.betrag < 0).toList()
      ..sort((a, b) => a.betrag.compareTo(b.betrag));

    final verpassteTopTage = verpasst.take(5).toList();
    final vermiedeneTopTage = vermieden.take(5).toList();
    final summeVerpasst = verpasst.fold(0.0, (s, t) => s + t.betrag);
    final summeVermieden = vermieden.fold(0.0, (s, t) => s + t.betrag);

    // Crash-Tage über die volle Kursreihe, unabhängig vom Investitionsstatus.
    final crashTage = <int>[
      for (var d = 1; d < reihe.laenge; d++)
        if (tagesrendite[d] <= crashSchwelle) d,
    ];
    var clusterAnteil = 0;
    for (final top in verpassteTopTage) {
      final imCluster = crashTage.any(
          (c) => c < top.tagIndex && top.tagIndex <= c + clusterFensterTage);
      if (imCluster) clusterAnteil++;
    }

    // ---- Gegenfaktische Referenzen: durchgehend investiert, minus/ohne die
    // 5 besten bzw. schlechtesten Einzeltage der ganzen Runde. ----
    final alleTage = List<TopTag>.generate(
        reihe.laenge - 1, (k) => TopTag(k + 1, reihe.epochTag(k + 1), tagesrendite[k + 1], 0));
    final besteTage = [...alleTage]..sort((a, b) => b.tagesrendite.compareTo(a.tagesrendite));
    final schlechtesteTage = [...alleTage]
      ..sort((a, b) => a.tagesrendite.compareTo(b.tagesrendite));

    // Aktionsliste für „durchgehend investiert, aber ohne die Tagesrendite der
    // ausgeschlossenen Tage". Konstruiert über den Soll-Zustand je Tag statt
    // über Kauf-/Verkaufspaare: Die Rendite von Tag d fällt genau dem zu, der
    // am Ende von Tag d-1 Stücke hält. Tag d auszulassen heißt also: an d-1
    // draußen sein. Aus dieser einen Regel ergibt sich alles Übrige von selbst
    // – auch benachbarte Ausschlusstage (die Extremtage einer Runde liegen
    // typischerweise dicht beieinander), für die die frühere Paarbildung zwei
    // Aktionen auf denselben Tag legte und damit den Rest der Liste verlor,
    // sowie der frühere Sonderfall d == 1.
    List<GeplanteAktion> ohneTageAktionen(List<TopTag> ausgeschlossen) {
      final aus = ausgeschlossen.take(5).map((t) => t.tagIndex - 1).toSet();
      final aktionen = <GeplanteAktion>[];
      var investiert = false;
      for (var d = 0; d < reihe.laenge; d++) {
        final soll = !aus.contains(d);
        if (soll != investiert) {
          aktionen.add(GeplanteAktion(d, soll));
          investiert = soll;
        }
      }
      return aktionen;
    }

    final letzterKurs = reihe.kurs(reihe.laenge - 1);
    final endwertOhneBesteFuenfTage = simuliereSpielerpfad(
      reihe: reihe,
      cfg: engine.cfg,
      aktionen: ohneTageAktionen(besteTage),
      mitSlippage: false,
    ).endwert(letzterKurs);
    final endwertOhneSchlechtesteFuenfTage = simuliereSpielerpfad(
      reihe: reihe,
      cfg: engine.cfg,
      aktionen: ohneTageAktionen(schlechtesteTage),
      mitSlippage: false,
    ).endwert(letzterKurs);

    // ---- „Der teuerste Klick" ----
    // `simuliereSpielerpfad` kennt keine Abgeltungsteuer. Der Ist-Wert wird
    // deshalb für den Vergleich entsteuert, sonst erschiene bei aktiver Steuer
    // *jeder* Trade als teuer – der Vergleichslauf hätte einen Vorteil, den er
    // nur der fehlenden Modellierung verdankt. Bewusste Näherung: die gezahlte
    // Steuer war während der Runde nicht mitverzinst. Bei `steuernAktiv: false`
    // (Default) ist der Summand exakt 0, das Verhalten also unverändert.
    final vergleichsbasisSpieler = endwertSpieler + engine.gezahlteSteuerSpieler;

    TeuersterKlick? teuersterKlick;
    for (var i = 0; i < engine.trades.length; i++) {
      final endstandOhne =
          simuliereOhneTrade(reihe, engine.cfg, engine.trades, i);
      final kosten = endstandOhne - vergleichsbasisSpieler;
      if (teuersterKlick == null || kosten > teuersterKlick.kosten) {
        teuersterKlick = TeuersterKlick(
          trade: engine.trades[i],
          endstandTatsaechlich: endwertSpieler,
          endstandOhneKlick: endstandOhne,
          kosten: kosten,
        );
      }
    }

    // ---- Inflation / reale Kaufkraft ----
    // Basiert auf dem tatsächlich zuletzt simulierten Tag, nicht auf
    // reihe.letzterTag – korrekt auch bei vorzeitig beendeten Runden.
    final letzterSimulierterTag = reihe.epochTag(engine.i);
    final preisfaktor =
        Inflation.preisfaktorMitAbdeckung(reihe.ersterTag, letzterSimulierterTag);
    final preisfaktorGesamt = preisfaktor.faktor;

    // Jede Einzahlung auf Preise des Rundenbeginns zurückgerechnet. Den realen
    // Endwert gegen die *nominale* Einzahlungssumme zu stellen wäre ein
    // Vergleich zweier verschiedener Preisstände und würde den Effekt
    // überzeichnen – und genau dieser Satz ist die Kernaussage des Blocks.
    var eingezahltReal = engine.cfg.startCash;
    for (final t in _einzahlungsTage(reihe, engine.i)) {
      eingezahltReal +=
          engine.cfg.monatsEinzahlung / Inflation.preisfaktor(reihe.ersterTag, t);
    }

    // ---- Kontrafaktische Vergleiche (V9) ----
    final endwertUmgekehrt = simuliereUmgekehrt(reihe, engine.cfg, engine.trades);
    final endwertOhneEntscheidungen =
        simuliereOhneEntscheidungen(reihe, engine.cfg, engine.trades);
    final versatzErgebnisse = [
      for (final h in [-60, -20, 20, 60])
        VersatzErgebnis(h, simuliereMitVersatz(reihe, engine.cfg, engine.trades, h)),
    ];

    // ---- Behavior Gap (V10) ----
    final geldgewichteteRenditeSpieler = geldgewichteteRendite(engine);
    final zeitgewichteteRenditeTitel = zeitgewichteteRendite(engine);
    double? behaviorGapEuro;
    int? behaviorGapInMonatsEinzahlungen;
    if (zeitgewichteteRenditeTitel != null) {
      // Jede Kapitalzufuhr (Start + jede Einzahlung) mit der Marktrendite auf
      // den letzten Tag aufgezinst, minus dem tatsächlichen Endwert.
      var beiMarktrendite = 0.0;
      final letzterTag = reihe.epochTag(engine.i);
      void aufzinsen(int tag, double betrag) {
        final jahre = (letzterTag - tag) / 365.25;
        beiMarktrendite += betrag * math.pow(1 + zeitgewichteteRenditeTitel, jahre);
      }

      aufzinsen(reihe.ersterTag, engine.cfg.startCash);
      for (final t in _einzahlungsTage(reihe, engine.i)) {
        aufzinsen(t, engine.cfg.monatsEinzahlung);
      }
      behaviorGapEuro = beiMarktrendite - endwertSpieler;
      behaviorGapInMonatsEinzahlungen = engine.cfg.monatsEinzahlung == 0
          ? null
          : (behaviorGapEuro / engine.cfg.monatsEinzahlung).round();
    }

    // ---- Verhaltensprofil (V11) ----
    final abstandVerkaufZuTiefTage =
        _mittlererAbstandZuExtremum(verkaeufe, reihe, tiefpunkt: true);
    final abstandKaufZuHochTage =
        _mittlererAbstandZuExtremum(kaeufe, reihe, tiefpunkt: false);
    final anteilVerkaeufeNachCrash = verkaeufe.isEmpty
        ? null
        : verkaeufe
                .where((v) =>
                    crashTage.any((c) => c < v.tagIndex && v.tagIndex <= c + clusterFensterTage))
                .length /
            verkaeufe.length;

    return RundenAuswertung._(
      tageInvestiert: tageInvestiert,
      tageAussen: tageAussen,
      anzahlKaeufe: kaeufe.length,
      anzahlVerkaeufe: verkaeufe.length,
      durchschnittlicheHaltedauerTage: durchschnittlicheHaltedauerTage,
      besterTrade: bester,
      schlechtesterTrade: schlechtester,
      durchschnittlicherKaufkurs: volumenGewichteterKurs(kaeufe),
      durchschnittlicherVerkaufskurs: volumenGewichteterKurs(verkaeufe),
      endwertSpieler: endwertSpieler,
      endwertInvestor: endwertInvestor,
      endwertSicherheit: engine.wertSicherheit,
      differenzZuInvestorEuro: differenz,
      differenzInMonatsEinzahlungen: engine.cfg.monatsEinzahlung == 0
          ? 0
          : (differenz / engine.cfg.monatsEinzahlung).round(),
      verpassteTopTage: verpassteTopTage,
      vermiedeneTopTage: vermiedeneTopTage,
      summeVerpasst: summeVerpasst,
      summeVermieden: summeVermieden,
      clusterAnteil: clusterAnteil,
      endwertImmerInvestiert: endwertInvestor,
      endwertOhneBesteFuenfTage: endwertOhneBesteFuenfTage,
      endwertOhneSchlechtesteFuenfTage: endwertOhneSchlechtesteFuenfTage,
      teuersterKlick: teuersterKlick,
      steuerNachteilGegenInvestor: engine.gezahlteSteuerSpieler +
          engine.latenteSteuerSpieler -
          engine.latenteSteuerInvestor,
      preisfaktorGesamt: preisfaktorGesamt,
      endwertSpielerReal: endwertSpieler / preisfaktorGesamt,
      endwertInvestorReal: endwertInvestor / preisfaktorGesamt,
      endwertSicherheitReal: engine.wertSicherheit / preisfaktorGesamt,
      kaufkraftIstBelastbar: preisfaktor.istBelastbar,
      sicherheitRealUnterEinzahlungen:
          preisfaktor.istBelastbar && engine.wertSicherheit / preisfaktorGesamt < eingezahltReal,
      endwertUmgekehrt: endwertUmgekehrt,
      endwertOhneEntscheidungen: endwertOhneEntscheidungen,
      versatzErgebnisse: versatzErgebnisse,
      geldgewichteteRenditeSpieler: geldgewichteteRenditeSpieler,
      zeitgewichteteRenditeTitel: zeitgewichteteRenditeTitel,
      behaviorGapEuro: behaviorGapEuro,
      behaviorGapInMonatsEinzahlungen: behaviorGapInMonatsEinzahlungen,
      abstandVerkaufZuTiefTage: abstandVerkaufZuTiefTage,
      abstandKaufZuHochTage: abstandKaufZuHochTage,
      anteilVerkaeufeNachCrash: anteilVerkaeufeNachCrash,
    );
  }
}
