import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/domain/auswertung.dart';
import 'package:boersenrennen_app/domain/inflation.dart';
import 'package:boersenrennen_app/domain/kursreihe.dart';
import 'package:boersenrennen_app/domain/rennen_engine.dart';
import 'package:boersenrennen_app/domain/spiel_konfiguration.dart';
import 'package:boersenrennen_app/domain/spieler_pfad.dart';
import 'package:boersenrennen_app/domain/trade.dart';

import 'rennen_engine_test.dart' show baueReihe;

/// Baut eine dichte, lückenlose Kursreihe über [tage] Kalendertage ab [start] –
/// bewusst innerhalb desselben Monats, damit keine Sparplan-Einzahlung die
/// Handrechnung verkompliziert.
Kursreihe baueDichteReihe(DateTime start, List<double> kurse) {
  final basis = Kursreihe.zuEpochTag(start);
  return Kursreihe.ausListen(
      List.generate(kurse.length, (d) => basis + d), kurse);
}

Trade baueTrade(int tagIndex, bool istKauf) => Trade(
      tagIndex: tagIndex,
      epochTag: 0,
      istKauf: istKauf,
      marktKurs: 0,
      ausfuehrungsKurs: 0,
      betrag: 0,
      stueck: 0,
      depotwertDanach: 0,
    );

void main() {
  final start = DateTime.utc(2010, 1, 1);

  group('Trade-Log (V5)', () {
    test('Kauf und Verkauf erzeugen genau zwei Trades mit korrekten Kursen und Beträgen',
        () {
      final reihe = baueReihe(start: start, kalenderTage: 20, kursFuer: (_) => 50.0);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.kaufen();
      e.verkaufen();

      expect(e.trades.length, 2);

      final kauf = e.trades[0];
      expect(kauf.istKauf, isTrue);
      expect(kauf.marktKurs, closeTo(50.0, 1e-9));
      expect(kauf.ausfuehrungsKurs, closeTo(50.0 * 1.005, 1e-9));
      expect(kauf.betrag, closeTo(1000.0, 1e-9));
      expect(kauf.stueck, closeTo(1000.0 / (50.0 * 1.005), 1e-9));

      final verkauf = e.trades[1];
      expect(verkauf.istKauf, isFalse);
      expect(verkauf.ausfuehrungsKurs, closeTo(50.0 * 0.995, 1e-9));
      expect(verkauf.stueck, closeTo(kauf.stueck, 1e-9));
      expect(verkauf.betrag, closeTo(kauf.stueck * 50.0 * 0.995, 1e-9));
    });

    test('Einzahlungen erzeugen keine Trades', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 2,
        kursFuer: (_) => 30.0,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }

      expect(e.einzahlungen, greaterThan(0));
      expect(e.trades, isEmpty);
    });

    test('gewinnBeiVerkauf bei flachem Kurs entspricht exakt dem doppelten Slippage-Verlust',
        () {
      final reihe = baueReihe(start: start, kalenderTage: 20, kursFuer: (_) => 100.0);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.kaufen();
      e.verkaufen();

      final erwarteterVerlust = 1000.0 * 0.995 / 1.005 - 1000.0;
      expect(e.trades.last.gewinnBeiVerkauf, closeTo(erwarteterVerlust, 1e-9));
      expect(e.trades.first.gewinnBeiVerkauf, isNull);
    });

    test('depotwertProTag.length == reihe.laenge nach vollständigem Durchlauf', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 3,
        kursFuer: (t) => 40 + 20 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }

      expect(e.depotwertProTag.length, reihe.laenge);
      expect(e.investiertProTag.length, reihe.laenge);
    });

    test('ein Kauf am selben Tag überschreibt den letzten Eintrag statt einen neuen '
        'anzulegen', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365,
        kursFuer: (t) => 40 + 20 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.schritt();
      e.schritt();
      final laengeVorher = e.depotwertProTag.length;

      e.kaufen();
      e.verkaufen();
      e.kaufen();

      expect(e.depotwertProTag.length, laengeVorher);
      expect(e.investiertProTag.length, laengeVorher);
      expect(e.investiertProTag.last, isTrue);
    });
  });

  group('RundenAuswertung (V6)', () {
    test('tageInvestiert + tageAussen == reihe.laenge', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 2,
        kursFuer: (t) => 40 + 20 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen();
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.tageInvestiert + a.tageAussen, reihe.laenge);
    });

    test('Haltedauer: geschlossene Position korrekt gemittelt', () {
      final reihe = baueReihe(start: start, kalenderTage: 100, kursFuer: (_) => 50.0);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      final kaufTag = e.reihe.epochTag(e.i);
      e.kaufen();
      for (var i = 0; i < 10; i++) {
        e.schritt();
      }
      final verkaufTag = e.reihe.epochTag(e.i);
      e.verkaufen();
      while (!e.fertig) {
        e.schritt();
      }

      final a = RundenAuswertung.aus(e);
      expect(a.durchschnittlicheHaltedauerTage, closeTo(verkaufTag - kaufTag, 1e-9));
    });

    test('Haltedauer: eine am Rundenende offene Position zählt bis zum letzten Tag', () {
      final reihe = baueReihe(start: start, kalenderTage: 100, kursFuer: (_) => 50.0);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      final kaufTag = e.reihe.epochTag(e.i);
      e.kaufen(); // nie wieder verkauft
      while (!e.fertig) {
        e.schritt();
      }

      final a = RundenAuswertung.aus(e);
      final letzterTag = e.reihe.epochTag(e.i);
      expect(a.durchschnittlicheHaltedauerTage, closeTo(letzterTag - kaufTag, 1e-9));
    });

    test('Haltedauer ist null ohne einen einzigen Trade', () {
      final reihe = baueReihe(start: start, kalenderTage: 100, kursFuer: (_) => 50.0);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }

      final a = RundenAuswertung.aus(e);
      expect(a.durchschnittlicheHaltedauerTage, isNull);
      expect(a.besterTrade, isNull);
      expect(a.schlechtesterTrade, isNull);
      expect(a.durchschnittlicherKaufkurs, isNull);
      expect(a.durchschnittlicherVerkaufskurs, isNull);
    });

    test('besterTrade/schlechtesterTrade sind null, solange nie verkauft wurde', () {
      final reihe = baueReihe(start: start, kalenderTage: 100, kursFuer: (_) => 50.0);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen();
      while (!e.fertig) {
        e.schritt();
      }

      final a = RundenAuswertung.aus(e);
      expect(a.besterTrade, isNull);
      expect(a.schlechtesterTrade, isNull);
    });

    test('durchschnittlicher Kaufkurs ist betragsgewichtet über zwei unterschiedlich '
        'große Käufe', () {
      // Kurs steigt linear: 100 -> 200. Kauf, Verkauf, ungleich großer Kauf.
      final reihe = baueReihe(
        start: start,
        kalenderTage: 200,
        kursFuer: (t) => 100 + 100 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen(); // kleiner Betrag (nur Startkapital)
      final ersterKauf = e.trades.single;
      for (var i = 0; i < 20; i++) {
        e.schritt();
      }
      e.verkaufen();
      // Durch die Einzahlungen ist der Cash-Bestand jetzt größer als beim ersten Kauf.
      for (var i = 0; i < 40; i++) {
        e.schritt();
      }
      e.kaufen();
      final zweiterKauf = e.trades.last;

      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      final erwarteterDurchschnitt =
          (ersterKauf.betrag + zweiterKauf.betrag) / (ersterKauf.stueck + zweiterKauf.stueck);
      expect(a.durchschnittlicherKaufkurs, closeTo(erwarteterDurchschnitt, 1e-6));
    });
  });

  group('Verpasste und vermiedene Börsentage (V7)', () {
    test('von Hand nachgerechnetes Beispiel: nie investiert, 10 Tage ohne Einzahlung', () {
      // 10 Tage im selben Kalendermonat -> keine Einzahlung, Depotwert bleibt
      // exakt beim Startkapital, jeder Tag entspricht also 1:1 der Tagesrendite.
      final basis = Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 1));
      final kurse = [100.0, 105.0, 95.0, 100.0, 90.0, 110.0, 100.0, 97.0, 103.0, 100.0];
      final reihe = Kursreihe.ausListen(
          List.generate(kurse.length, (d) => basis + d), kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }
      expect(e.einzahlungen, 0); // Kontrolle: Testaufbau wie angenommen.

      final a = RundenAuswertung.aus(e);

      // Top-Tage sortiert nach Betrag (siehe Handrechnung im Kommentar).
      expect(a.verpassteTopTage.map((t) => t.tagIndex).toList(), [5, 8, 3, 1]);
      expect(a.vermiedeneTopTage.map((t) => t.tagIndex).toList(), [4, 2, 6, 7, 9]);

      const erwarteterSummeVerpasst = 50.0 + 1000 * (100 / 95 - 1) + 1000 * (110 / 90 - 1) +
          1000 * (103 / 97 - 1);
      expect(a.summeVerpasst, closeTo(erwarteterSummeVerpasst, 1e-6));

      const erwarteterSummeVermieden = 1000 * (95 / 105 - 1) +
          1000 * (90 / 100 - 1) +
          1000 * (100 / 110 - 1) +
          1000 * (97 / 100 - 1) +
          1000 * (100 / 103 - 1);
      expect(a.summeVermieden, closeTo(erwarteterSummeVermieden, 1e-6));

      // Crash-Tage (Tagesrendite <= -3%): 2, 4, 6, 7. Tag 1 liegt vor jedem
      // Crash-Tag -> nicht im Cluster. Tage 3/5/8 liegen jeweils danach.
      expect(a.clusterAnteil, 3);
    });

    test('nettoBilanz summiert alle Außenmarkt-Tage, nicht nur die Top 5', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 3,
        kursFuer: (t) => 60 + 40 * (0.5 - 0.5 * (t * 20).remainder(1) * 2).abs(),
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      // Nie investiert -> jeder Tag ist ein Außenmarkt-Tag; über 3 Jahre gibt
      // es garantiert mehr als 5 Gewinn- und mehr als 5 Verlusttage.
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      var summeVerpasstVonHand = 0.0;
      var summeVermiedenVonHand = 0.0;
      for (var d = 1; d < e.investiertProTag.length; d++) {
        if (e.investiertProTag[d - 1]) continue;
        final rendite = reihe.kurs(d) / reihe.kurs(d - 1) - 1;
        final betrag = e.depotwertProTag[d - 1] * rendite;
        if (betrag > 0) {
          summeVerpasstVonHand += betrag;
        } else if (betrag < 0) {
          summeVermiedenVonHand += betrag;
        }
      }

      expect(a.summeVerpasst, closeTo(summeVerpasstVonHand, 1e-6));
      expect(a.summeVermieden, closeTo(summeVermiedenVonHand, 1e-6));
      expect(a.verpassteTopTage.length, lessThanOrEqualTo(5));
      expect(a.vermiedeneTopTage.length, lessThanOrEqualTo(5));
    });

    test('endwertImmerInvestiert entspricht exakt dem Investor', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 4,
        kursFuer: (t) => 50 + 80 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 2.0));
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.endwertImmerInvestiert, a.endwertInvestor);
      expect(a.endwertImmerInvestiert, e.wertInvestor);
    });

    test('100 % investiert -> verpasste/vermiedene Listen sind leer, Summen sind 0', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 3,
        kursFuer: (t) => 40 + 20 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen(); // sofort und dauerhaft investiert
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.tageAussen, 0);
      expect(a.verpassteTopTage, isEmpty);
      expect(a.vermiedeneTopTage, isEmpty);
      expect(a.summeVerpasst, 0.0);
      expect(a.summeVermieden, 0.0);
      expect(a.clusterAnteil, 0);
    });

    test('das Verpassen der besten Tage schadet, das Vermeiden der schlechtesten hilft',
        () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 5,
        kursFuer: (t) => 60 + 40 * (0.5 - 0.5 * (t * 20).remainder(1) * 2).abs(),
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.endwertOhneBesteFuenfTage, lessThan(a.endwertImmerInvestiert));
      expect(a.endwertOhneSchlechtesteFuenfTage, greaterThan(a.endwertImmerInvestiert));
    });
  });

  group('„Der teuerste Klick" (V16)', () {
    test('drei Trades von Hand nachgerechnet: Verkauf vor einer Rally ist der '
        'teuerste Klick; ein ins Leere laufender Verkauf ist unkritisch', () {
      // 28 Tage im Februar (kein Monatswechsel -> keine Einzahlung). Kurs
      // bleibt bis Tag 13 bei 100, springt ab Tag 14 auf 200.
      final kurse = List.generate(28, (d) => d < 14 ? 100.0 : 200.0);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);
      final letzterKurs = reihe.kurs(reihe.laenge - 1);

      final trades = [
        baueTrade(0, true), // Kauf vor der Rally
        baueTrade(10, false), // Verkauf – noch vor der Rally
        baueTrade(18, true), // Wiedereinstieg – erst nach der Rally
      ];

      final endstandTatsaechlich = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: [
          for (final t in trades) GeplanteAktion(t.tagIndex, t.istKauf),
        ],
      ).endwert(letzterKurs);

      // Handrechnung: Kauf@0 -> 1000/(100·1,005) Stück; Verkauf@10 (Kurs noch
      // 100) -> Cash; Kauf@18 (Kurs bereits 200) -> deutlich weniger Stück.
      expect(endstandTatsaechlich, closeTo(985.1241306, 1e-4));

      // Ohne den Anfangskauf: der spätere Verkauf@10 läuft ins Leere
      // (stueck=0) – unkritisch, kein Auslöser für eine Exception.
      final ohneKauf = simuliereOhneTrade(reihe, cfg, trades, 0);
      expect(ohneKauf, closeTo(995.0248756, 1e-4));

      // Ohne den Verkauf@10: bleibt investiert und nimmt die volle Rally mit.
      final ohneVerkauf = simuliereOhneTrade(reihe, cfg, trades, 1);
      expect(ohneVerkauf, closeTo(1990.0497512, 1e-4));

      // Ohne den Wiedereinstieg@18: bleibt in Cash ab Tag 10.
      final ohneWiedereinstieg = simuliereOhneTrade(reihe, cfg, trades, 2);
      expect(ohneWiedereinstieg, closeTo(990.0497512, 1e-4));

      // Der Verkauf vor der Rally ist mit Abstand der teuerste Klick.
      final kosten = [
        ohneKauf - endstandTatsaechlich,
        ohneVerkauf - endstandTatsaechlich,
        ohneWiedereinstieg - endstandTatsaechlich,
      ];
      final teuersterIndex =
          kosten.indexOf(kosten.reduce((a, b) => a > b ? a : b));
      expect(teuersterIndex, 1);
      expect(kosten[1], greaterThan(1000)); // der Rückstand ist eklatant
    });

    test('einziger Trade, der geholfen hat -> Rahmung als „Dein bester Klick"', () {
      // 28 Tage im Februar, Kurs steigt linear von 100 auf 154.
      final kurse = List.generate(28, (d) => 100.0 + 2 * d);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);
      final letzterKurs = reihe.kurs(reihe.laenge - 1);

      final trades = [baueTrade(0, true)]; // einziger Trade: Kauf, nie verkauft

      final endstandTatsaechlich = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: [GeplanteAktion(trades[0].tagIndex, trades[0].istKauf)],
      ).endwert(letzterKurs);

      final ohneKauf = simuliereOhneTrade(reihe, cfg, trades, 0);
      final kosten = ohneKauf - endstandTatsaechlich;

      expect(kosten, lessThan(0)); // der Kauf hat geholfen -> "bester Klick"

      final teuersterKlick = TeuersterKlick(
        trade: trades[0],
        endstandTatsaechlich: endstandTatsaechlich,
        endstandOhneKlick: ohneKauf,
        kosten: kosten,
      );
      expect(teuersterKlick.istBesterKlick, isTrue);
    });

    test('RundenAuswertung.teuersterKlick ist null bei null Trades', () {
      final reihe = baueReihe(start: start, kalenderTage: 100, kursFuer: (_) => 50.0);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);
      expect(a.teuersterKlick, isNull);
    });
  });

  group('Kontrafaktische Vergleiche (V9)', () {
    test('simuliereUmgekehrt tauscht Kauf und Verkauf an denselben Tagen', () {
      // 20 Tage, flach bei 100 bis Tag 18, Sprung auf 200 am letzten Tag.
      final kurse = List<double>.generate(20, (d) => d < 19 ? 100.0 : 200.0);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);
      final trades = [baueTrade(0, true), baueTrade(10, false)];

      final endwert = simuliereUmgekehrt(reihe, cfg, trades);

      // Umgekehrt: Verkauf@0 (stueck=0 -> No-op), Kauf@10 bei Kurs 100,
      // gehalten bis Tag 19 bei Kurs 200.
      final erwartet = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: const [GeplanteAktion(10, true)],
      ).endwert(200.0);
      expect(endwert, closeTo(erwartet, 1e-9));
      expect(endwert, closeTo(1990.0497512437811, 1e-6));
    });

    test('simuliereMitVersatz: negativer Versatz vor Tag 0 lässt den Trade '
        'ersatzlos wegfallen', () {
      final kurse = List<double>.generate(20, (d) => 100.0 + d);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);
      final trades = [baueTrade(5, true)];

      final mitVersatz = simuliereMitVersatz(reihe, cfg, trades, -10);
      final ohneTrades =
          simuliereSpielerpfad(reihe: reihe, cfg: cfg, aktionen: const []).endwert(kurse.last);

      expect(mitVersatz, closeTo(ohneTrades, 1e-9));
    });

    test('simuliereMitVersatz: positiver Versatz verschiebt den Trade exakt', () {
      final kurse = List<double>.generate(20, (d) => 100.0 + d);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);
      final trades = [baueTrade(5, true)];

      final mitVersatz = simuliereMitVersatz(reihe, cfg, trades, 3);
      final erwartet = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: const [GeplanteAktion(8, true)],
      ).endwert(kurse.last);

      expect(mitVersatz, closeTo(erwartet, 1e-9));
    });

    test('simuliereOhneEntscheidungen hält den Countdown-Zustand durch', () {
      final kurse = List<double>.generate(20, (d) => 100.0 + d);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);

      // Countdown-Investition (Tag-0-Kauf) -> bleibt investiert bis zum Schluss.
      final investiert =
          simuliereOhneEntscheidungen(reihe, cfg, [baueTrade(0, true), baueTrade(10, false)]);
      final erwartetInvestiert = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: const [GeplanteAktion(0, true)],
      ).endwert(kurse.last);
      expect(investiert, closeTo(erwartetInvestiert, 1e-9));

      // Kein Tag-0-Kauf -> bleibt die ganze Runde in Cash.
      final abgewartet = simuliereOhneEntscheidungen(reihe, cfg, [baueTrade(5, true)]);
      final erwartetCash =
          simuliereSpielerpfad(reihe: reihe, cfg: cfg, aktionen: const []).endwert(kurse.last);
      expect(abgewartet, closeTo(erwartetCash, 1e-9));
    });

    test('timingWarUeberwiegendRauschen ist false, wenn der Spieler nie handelt', () {
      final reihe = baueReihe(start: start, kalenderTage: 365 * 3, kursFuer: (t) => 40 + 60 * t);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      // Ohne Trades sind alle Versatz-Ergebnisse identisch (immer Cash) ->
      // Streuung 0, während der Abstand zum voll investierten Investor groß ist.
      expect(a.timingWarUeberwiegendRauschen, isFalse);
    });

    test('timingWarUeberwiegendRauschen ist true bei stark schwankendem Kurs und '
        'einem einzigen, investorähnlichen Trade', () {
      // Stark oszillierender Kurs: eine Verschiebung des Einstiegstags um
      // wenige Tage landet auf einem komplett anderen Kursniveau.
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 4,
        kursFuer: (t) => 100 + 80 * math.sin(t * 2 * math.pi * 8),
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen(); // Tag 0 – wie der Investor, nur mit Slippage.
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      // Der Abstand zum Investor ist hier nur die Slippage auf das
      // Startkapital – winzig gegen die Streuung durch die Oszillation.
      expect(a.timingWarUeberwiegendRauschen, isTrue);
    });
  });

  group('Verhaltensprofil (V11)', () {
    test(
        'abstandKaufZuHochTage und abstandVerkaufZuTiefTage finden das jeweilige '
        'Extremum im 120-Tage-Fenster', () {
      // Hoch bei Tag 30 (nach dem Kauf an Tag 0), Tief bei Tag 120 (nach dem
      // Verkauf an Tag 50) – beide klar innerhalb des 120-Tage-Fensters und
      // jeweils das einzige Extremum in ihrem Fenster.
      final kurse = List<double>.generate(220, (d) {
        if (d <= 30) return 100 + (100 / 30) * d;
        if (d <= 50) return 200 - (50 / 20) * (d - 30);
        if (d <= 120) return 150 - (100 / 70) * (d - 50);
        if (d <= 170) return 50 + (50 / 50) * (d - 120);
        return 100.0;
      });
      final reihe = baueDichteReihe(start, kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.kaufen(); // Tag 0
      while (e.i < 50) {
        e.schritt();
      }
      e.verkaufen(); // Tag 50
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.abstandKaufZuHochTage, closeTo(30, 1e-9));
      expect(a.abstandVerkaufZuTiefTage, closeTo(70, 1e-9));
    });

    test(
        'liegt ein Verkauf in den letzten <120 Handelstagen der Runde, wird das '
        'Fenster auf das Rundenende verkürzt statt über das Ende hinauszulesen', () {
      // Tief bei Tag 75, 15 Tage nach dem Verkauf an Tag 60 – die Runde endet
      // aber schon bei Tag 79, das Fenster [61, reihe.laenge-1] ist also kürzer
      // als die vollen 120 Tage.
      final kurse = List<double>.generate(80, (d) {
        if (d <= 60) return 100.0;
        if (d <= 75) return 100 - (50 / 15) * (d - 60);
        return 50 + 5.0 * (d - 75);
      });
      final reihe = baueDichteReihe(start, kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.kaufen(); // Tag 0
      while (e.i < 60) {
        e.schritt();
      }
      e.verkaufen(); // Tag 60
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.abstandVerkaufZuTiefTage, closeTo(15, 1e-9));
    });

    test('alle drei Verhaltensmaße liefern null, wenn nie gehandelt wurde', () {
      final reihe = baueReihe(start: start, kalenderTage: 200, kursFuer: (t) => 100 + 50 * t);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.abstandKaufZuHochTage, isNull);
      expect(a.abstandVerkaufZuTiefTage, isNull);
      expect(a.anteilVerkaeufeNachCrash, isNull);
    });

    test(
        'anteilVerkaeufeNachCrash ist 1.0, wenn der einzige Verkauf innerhalb von '
        '15 Handelstagen nach einem Crash-Tag (-5 %) liegt', () {
      final kurse = List<double>.generate(25, (d) => d < 10 ? 100.0 : 95.0);
      final reihe = baueDichteReihe(start, kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.kaufen(); // Tag 0
      while (e.i < 20) {
        e.schritt();
      }
      e.verkaufen(); // Tag 20 – 10 Handelstage nach dem Crash an Tag 10
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.anteilVerkaeufeNachCrash, closeTo(1.0, 1e-9));
    });

    test(
        'anteilVerkaeufeNachCrash ist 0.0, wenn der einzige Verkauf weit außerhalb '
        'des 15-Handelstage-Fensters nach dem Crash-Tag liegt', () {
      final kurse = List<double>.generate(35, (d) => d < 10 ? 100.0 : 95.0);
      final reihe = baueDichteReihe(start, kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.kaufen(); // Tag 0
      while (e.i < 30) {
        e.schritt();
      }
      e.verkaufen(); // Tag 30 – weit außerhalb des Crash-Fensters (Crash an Tag 10)
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.anteilVerkaeufeNachCrash, closeTo(0.0, 1e-9));
    });
  });

  group('Kaufkraft und Nullteiler (P5)', () {
    test('ohne Monatseinzahlung ist die Behavior Gap bestimmbar, der Zähler aber null',
        () {
      // Genau die Kombination, an der der Ergebnis-Screen mit einem
      // Null-Check-Absturz gescheitert wäre: die Lücke in Euro existiert,
      // "entspricht X Monatseinzahlungen" kann es bei 0 € nicht geben.
      final reihe = baueReihe(start: start, kalenderTage: 365 * 3, kursFuer: (t) => 40 + 60 * t);
      final e = RennenEngine(
        reihe,
        const SpielKonfiguration(zinssatz: 0.0, monatsEinzahlung: 0.0),
      );
      e.kaufen();
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.behaviorGapEuro, isNotNull);
      expect(a.behaviorGapInMonatsEinzahlungen, isNull);
      expect(a.differenzInMonatsEinzahlungen, 0);
    });

    test('ein Zeitraum ohne Teuerungsdaten liefert keine Kaufkraft-Aussage', () {
      // Runde vollständig vor Beginn der Destatis-Reihe.
      final reihe = baueReihe(
        start: DateTime.utc(Inflation.erstesJahr - 6, 1, 1),
        kalenderTage: 365 * 3,
        kursFuer: (t) => 100 + 50 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.kaufkraftIstBelastbar, isFalse);
      // Ohne belastbare Kaufkraft darf auch der Kernsatz nicht behauptet werden.
      expect(a.sicherheitRealUnterEinzahlungen, isFalse);
    });

    test('in einem abgedeckten Zeitraum ist die Kaufkraft-Aussage belastbar', () {
      final reihe = baueReihe(start: start, kalenderTage: 365 * 5, kursFuer: (t) => 100 + 50 * t);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 3.0));
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.kaufkraftIstBelastbar, isTrue);
      expect(a.preisfaktorGesamt, greaterThan(1.0));
      expect(a.endwertSicherheitReal, lessThan(a.endwertSicherheit));
    });

    test('die Einzahlungssumme wird auf Preise des Rundenbeginns abgezinst', () {
      // Über verschiedene Zinssätze hinweg werden zwei Eigenschaften geprüft:
      //  1. Die neue Bedingung ist strenger als die alte (abgezinst < nominal),
      //     urteilt also nie großzügiger.
      //  2. Es gibt mindestens einen Zinssatz, bei dem beide unterschiedlich
      //     urteilen – sonst wäre die Änderung wirkungslos.
      final reihe = baueReihe(start: start, kalenderTage: 365 * 10, kursFuer: (_) => 100.0);
      var urteileWeichenAb = false;

      for (var zins = 0.0; zins <= 5.0; zins += 0.25) {
        final e = RennenEngine(reihe, SpielKonfiguration(zinssatz: zins));
        while (!e.fertig) {
          e.schritt();
        }
        final a = RundenAuswertung.aus(e);
        expect(a.kaufkraftIstBelastbar, isTrue);

        final nominalEingezahlt = e.cfg.startCash + e.cfg.monatsEinzahlung * e.einzahlungen;
        final altesUrteil = a.endwertSicherheitReal < nominalEingezahlt;

        if (a.sicherheitRealUnterEinzahlungen) {
          expect(altesUrteil, isTrue,
              reason: 'die strengere Bedingung muss die alte implizieren (Zins $zins)');
        }
        if (altesUrteil != a.sicherheitRealUnterEinzahlungen) urteileWeichenAb = true;
      }

      expect(urteileWeichenAb, isTrue,
          reason: 'ohne einen abweichenden Fall wäre die Abzinsung folgenlos');
    });
  });

  group('Steuer-Symmetrie (P2)', () {
    /// Kurs verdoppelt sich in der Mitte; der Spieler kauft zu Beginn.
    RennenEngine baueGewinnRunde({required bool steuernAktiv, required bool verkauftAmEnde}) {
      final kurse = List<double>.generate(28, (d) => d < 14 ? 100.0 : 200.0);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      final e = RennenEngine(
        reihe,
        SpielKonfiguration(
          zinssatz: 0.0,
          steuernAktiv: steuernAktiv,
          // Ohne Freibetrag, sonst schluckt er den ganzen Gewinn dieser
          // kleinen Beispielrunde.
          sparerpauschbetrag: 0.0,
        ),
      );
      e.kaufen();
      while (!e.fertig) {
        // Am vorletzten Tag verkaufen – nach `fertig` wäre verkaufen() ein No-op.
        if (verkauftAmEnde && e.i == reihe.laenge - 2) e.verkaufen();
        e.schritt();
      }
      return e;
    }

    test('bei deaktivierter Steuer bleibt der teuerste Klick unverändert', () {
      final e = baueGewinnRunde(steuernAktiv: false, verkauftAmEnde: false);
      final a = RundenAuswertung.aus(e);

      // gezahlteSteuerSpieler ist 0 -> Vergleichsbasis == Endwert.
      expect(e.gezahlteSteuerSpieler, 0.0);
      expect(a.teuersterKlick!.kosten,
          closeTo(a.teuersterKlick!.endstandOhneKlick - a.endwertSpieler, 1e-9));
      expect(a.steuerNachteilGegenInvestor, 0.0);
    });

    test('ein realisierter Gewinn verzerrt die Kosten des teuersten Klicks nicht', () {
      final e = baueGewinnRunde(steuernAktiv: true, verkauftAmEnde: true);
      final ohneSteuer = RundenAuswertung.aus(
          baueGewinnRunde(steuernAktiv: false, verkauftAmEnde: true));
      final mitSteuer = RundenAuswertung.aus(e);

      expect(e.gezahlteSteuerSpieler, greaterThan(0.0));
      // Der Vergleichslauf ist in beiden Fällen derselbe steuerfreie Pfad. Weil
      // der Ist-Wert entsteuert wird, müssen die Kosten exakt übereinstimmen –
      // vor dem Fix lagen sie um die gezahlte Steuer auseinander und ließen
      // jede Entscheidung teurer erscheinen, als sie war.
      expect(mitSteuer.teuersterKlick!.kosten,
          closeTo(ohneSteuer.teuersterKlick!.kosten, 1e-9));
      expect(mitSteuer.teuersterKlick!.trade.istKauf,
          ohneSteuer.teuersterKlick!.trade.istKauf);
    });

    test('ein investiert endender Spieler hat keinen Steuervorteil gegenüber dem Investor',
        () {
      final e = baueGewinnRunde(steuernAktiv: true, verkauftAmEnde: false);
      final a = RundenAuswertung.aus(e);

      // Nie verkauft -> keine gezahlte Steuer, aber dieselbe latente Last wie
      // der Investor. Der Nachteil muss ungefähr 0 sein, nicht stark negativ.
      expect(e.gezahlteSteuerSpieler, 0.0);
      expect(e.latenteSteuerSpieler, greaterThan(0.0));
      expect(a.steuerNachteilGegenInvestor.abs(),
          lessThan(e.latenteSteuerInvestor * 0.1));
    });

    test('nach einem Verkauf gibt es keine latente Last mehr, nur noch gezahlte', () {
      final e = baueGewinnRunde(steuernAktiv: true, verkauftAmEnde: true);

      expect(e.gezahlteSteuerSpieler, greaterThan(0.0));
      expect(e.latenteSteuerSpieler, 0.0);
    });
  });

  group('Mehrere Aktionen am selben Handelstag (P1)', () {
    // Regression: `simuliereSpielerpfad` konsumierte pro Tag nur eine Aktion.
    // Blieb eine zweite liegen, stand der Listenkopf danach dauerhaft auf einem
    // vergangenen Tag – ab da wurde jede weitere Aktion still verworfen.
    test('Kauf und Verkauf am selben Tag kosten exakt zweimal Slippage', () {
      final kurse = List<double>.generate(20, (d) => 100.0);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);

      final ergebnis = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: const [GeplanteAktion(5, true), GeplanteAktion(5, false)],
      );

      // 1000 € -> Kauf zu 100*1,005 -> Verkauf zu 100*0,995.
      expect(ergebnis.stueck, closeTo(0.0, 1e-12));
      expect(ergebnis.endwert(100.0), closeTo(1000.0 * 0.995 / 1.005, 1e-9));
    });

    test('nach einer Doppelaktion greifen spätere Aktionen weiterhin', () {
      // Flach bei 100, ab Tag 15 Sprung auf 200.
      final kurse = List<double>.generate(20, (d) => d < 15 ? 100.0 : 200.0);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);

      final mitDoppelaktion = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: const [
          GeplanteAktion(5, true),
          GeplanteAktion(5, false),
          GeplanteAktion(10, true), // muss den Sprung auf 200 noch mitnehmen
        ],
      ).endwert(200.0);

      // 1000 € -> Kauf@5 zu 100,50 -> Verkauf@5 zu 99,50 -> 990,0498 € Cash
      // -> Kauf@10 zu 100,50 -> 9,851241 Stück -> 1970,2483 € bei Kurs 200.
      expect(mitDoppelaktion, closeTo(1970.2482614, 1e-6));

      // Vor dem Fix blieb der Listenkopf auf Tag 5 stehen: der Verkauf fiel
      // weg, der Kauf an Tag 10 ebenfalls, und der Lauf blieb ab Tag 5
      // durchgehend investiert – das ergäbe 1990,0498 €.
      expect(mitDoppelaktion, lessThan(1985.0));
    });

    test('ein Trade-Paar am selben Tag verfälscht den teuersten Klick nicht', () {
      final kurse = List<double>.generate(28, (d) => d < 14 ? 100.0 : 200.0);
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      const cfg = SpielKonfiguration(zinssatz: 0.0);
      // Kauf und Verkauf an Tag 2, danach der eigentliche Einstieg an Tag 5.
      final trades = [baueTrade(2, true), baueTrade(2, false), baueTrade(5, true)];

      // Ohne den dritten Trade fehlt der Einstieg vor der Verdopplung.
      final ohneEinstieg = simuliereOhneTrade(reihe, cfg, trades, 2);
      final mitAllen = simuliereSpielerpfad(
        reihe: reihe,
        cfg: cfg,
        aktionen: [for (final t in trades) GeplanteAktion(t.tagIndex, t.istKauf)],
      ).endwert(200.0);

      expect(ohneEinstieg, lessThan(mitAllen));
      expect(ohneEinstieg, closeTo(1000.0 * 0.995 / 1.005, 1e-9));
    });
  });

  group('Referenz „ohne die besten/schlechtesten Tage" (P1)', () {
    // Tag 3 und Tag 4 bringen je +50 %. Beide auszulassen heißt: ab Ende Tag 2
    // draußen bleiben und erst an Tag 4 wieder einsteigen. Die frühere
    // Kauf-/Verkaufspaar-Konstruktion erzeugte dafür zwei Aktionen auf Tag 3
    // und ließ den Rest der Liste verhungern.
    test('zwei aufeinanderfolgende Ausschlusstage werden beide übersprungen', () {
      final kurse = <double>[100, 100, 100, 150, 225, 225, 225, 225];
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen();
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      // Buy-and-Hold verdoppelt sich auf 2250 €; ohne die beiden besten Tage
      // bleibt exakt das Startkapital übrig.
      expect(a.endwertImmerInvestiert, closeTo(2250.0, 1e-9));
      expect(a.endwertOhneBesteFuenfTage, closeTo(1000.0, 1e-9));
    });

    test('ein Ausschluss von Tag 1 verhindert den Anfangskauf', () {
      final kurse = <double>[100, 200, 200, 200, 200, 200];
      final reihe = baueDichteReihe(DateTime.utc(2010, 2, 1), kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen();
      while (!e.fertig) {
        e.schritt();
      }
      final a = RundenAuswertung.aus(e);

      expect(a.endwertOhneBesteFuenfTage, closeTo(1000.0, 1e-9));
    });
  });
}
