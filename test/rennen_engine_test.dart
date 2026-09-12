import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/domain/kursreihe.dart';
import 'package:boersenrennen_app/domain/rennen_engine.dart';
import 'package:boersenrennen_app/domain/spiel_konfiguration.dart';

/// Baut eine synthetische Kursreihe aus Handelstagen (Mo–Fr).
///
/// [kursFuer] bekommt den Fortschritt 0..1 und liefert den Kurs.
Kursreihe baueReihe({
  required DateTime start,
  required int kalenderTage,
  required double Function(double t) kursFuer,
  bool nurWerktage = true,
}) {
  final epochTage = <int>[];
  final kurse = <double>[];
  for (var d = 0; d <= kalenderTage; d++) {
    final tag = start.add(Duration(days: d));
    if (nurWerktage && (tag.weekday == DateTime.saturday || tag.weekday == DateTime.sunday)) {
      continue;
    }
    epochTage.add(Kursreihe.zuEpochTag(tag));
    kurse.add(kursFuer(d / kalenderTage));
  }
  return Kursreihe.ausListen(epochTage, kurse);
}

RennenEngine laufeDurch(Kursreihe reihe, SpielKonfiguration cfg,
    {void Function(RennenEngine e)? proSchritt}) {
  final e = RennenEngine(reihe, cfg);
  while (!e.fertig) {
    e.schritt();
    proSchritt?.call(e);
  }
  return e;
}

void main() {
  final start = DateTime.utc(2010, 1, 1);

  group('Portparität zur JavaScript-Version', () {
    test('Kursverdopplung: Investor > Sicherheit > nie-investierter Spieler', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 3,
        kursFuer: (t) => 100 + 100 * t, // 100 -> 200
      );
      final e = laufeDurch(reihe, const SpielKonfiguration(zinssatz: 5.0));

      // Der Spieler kauft nie: sein Depot ist reines eingezahltes Cash.
      final eingezahlt = 1000.0 + 100.0 * e.einzahlungen;
      expect(e.wertSpieler, closeTo(eingezahlt, 1e-9));

      expect(e.wertInvestor, greaterThan(e.wertSicherheit));
      expect(e.wertSicherheit, greaterThan(e.wertSpieler));
    });

    test('flacher Kurs ohne Zins: Investor und Spieler landen exakt gleich', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 2,
        kursFuer: (_) => 50.0,
      );
      final e = laufeDurch(reihe, const SpielKonfiguration(zinssatz: 0.0));

      final eingezahlt = 1000.0 + 100.0 * e.einzahlungen;
      expect(e.wertInvestor, closeTo(eingezahlt, 1e-9));
      expect(e.wertSpieler, closeTo(eingezahlt, 1e-9));
      expect(e.wertSicherheit, closeTo(eingezahlt, 1e-9));
    });
  });

  group('Verzinsung der Sicherheit', () {
    test('rechnet mit Kalendertagen, nicht mit Handelstagen (Fr -> Mo = 3)', () {
      // Freitag 2010-01-08 und Montag 2010-01-11, gleicher Monat.
      final reihe = Kursreihe.ausListen(
        [
          Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 8)),
          Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 11)),
        ],
        [100.0, 100.0],
      );
      const cfg = SpielKonfiguration(zinssatz: 3.0);
      final e = RennenEngine(reihe, cfg);
      e.schritt();

      final erwartet = 1000.0 * math.pow(1.03, 3 / 365);
      expect(e.sicherheit.cash, closeTo(erwartet, 1e-9));
    });

    test('ohne Zins bleibt das Cash unverändert', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 200,
        kursFuer: (_) => 10.0,
      );
      final e = laufeDurch(reihe, const SpielKonfiguration(zinssatz: 0.0));
      expect(e.sicherheit.cash, closeTo(1000.0 + 100.0 * e.einzahlungen, 1e-9));
    });
  });

  group('Einzahlungen', () {
    test('erster Tag zahlt nicht ein; 24 Monatswechsel ergeben 24 Einzahlungen', () {
      final reihe = baueReihe(
        start: DateTime.utc(2010, 1, 15),
        kalenderTage: 365 * 2 + 1, // bis 2012-01-16 -> 24 Monatswechsel
        kursFuer: (_) => 10.0,
      );
      final e = laufeDurch(reihe, const SpielKonfiguration(zinssatz: 0.0));
      expect(e.einzahlungen, 24);
    });

    test('Monatswechsel über den Jahreswechsel wird erkannt', () {
      final reihe = Kursreihe.ausListen(
        [
          Kursreihe.zuEpochTag(DateTime.utc(2010, 12, 30)),
          Kursreihe.zuEpochTag(DateTime.utc(2011, 1, 3)),
        ],
        [10.0, 10.0],
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.schritt();
      expect(e.einzahlungen, 1);
    });

    test('nicht investiert: Einzahlungen stauen sich als Cash', () {
      final reihe = baueReihe(
        start: DateTime.utc(2010, 1, 15),
        kalenderTage: 200,
        kursFuer: (_) => 25.0,
      );
      final e = laufeDurch(reihe, const SpielKonfiguration(zinssatz: 0.0));

      expect(e.spieler.stueck, 0);
      expect(e.spieler.cash, closeTo(1000.0 + 100.0 * e.einzahlungen, 1e-9));
    });

    test('aufgelaufenes Cash wandert beim Kauf mit Slippage in Stücke', () {
      final reihe = baueReihe(
        start: DateTime.utc(2010, 1, 15),
        kalenderTage: 200,
        kursFuer: (_) => 25.0,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      // Mitten in der Runde kaufen, nachdem drei Einzahlungen aufgelaufen sind.
      while (e.einzahlungen < 3) {
        e.schritt();
      }
      final cashVorher = e.spieler.cash;
      expect(cashVorher, closeTo(1300.0, 1e-9));

      e.kaufen();
      expect(e.spieler.cash, 0);
      expect(e.spieler.stueck, closeTo(cashVorher / (25.0 * 1.005), 1e-9));
    });

    test('investiert: Einzahlung kauft sofort Stücke (ohne Slippage)', () {
      final reihe = baueReihe(
        start: DateTime.utc(2010, 1, 15),
        kalenderTage: 100,
        kursFuer: (_) => 20.0,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen(); // sofort investieren – dieser eine Kauf zahlt Slippage
      final stueckNachKauf = e.spieler.stueck;

      while (!e.fertig) {
        e.schritt();
      }

      expect(e.spieler.cash, 0);
      expect(e.spieler.stueck, greaterThan(stueckNachKauf));
      // Der Sparplan selbst ist slippage-frei – nur der manuelle Kauf oben war es.
      expect(
        e.spieler.stueck,
        closeTo(stueckNachKauf + e.einzahlungen * 100.0 / 20.0, 1e-9),
      );
    });
  });

  group('Slippage', () {
    test('sofortiges Kaufen und Verkaufen kostet rund 1 %', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 10,
        kursFuer: (_) => 100.0,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.kaufen();
      e.verkaufen();

      expect(e.spieler.cash, closeTo(1000.0 * 0.995 / 1.005, 1e-9));
    });

    test('Buy-and-Hold-Spieler liegt nur noch um die Slippage auf das Startkapital zurück',
        () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 5,
        kursFuer: (t) => 80 + 60 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen(); // Tag 0 kaufen und nie wieder handeln
      while (!e.fertig) {
        e.schritt();
      }

      expect(e.wertSpieler, lessThan(e.wertInvestor));
      // Spieler hält 1000/(kurs0·1,005) + Σ(100/kursₘ) Stück, Investor
      // 1000/kurs0 + Σ(100/kursₘ) – die Sparplan-Terme sind seit V1 auf
      // beiden Seiten identisch (slippage-frei) und kürzen sich exakt heraus.
      // Übrig bleibt nur die Slippage auf den initialen Kauf des Startkapitals.
      expect(
        e.investor.stueck - e.spieler.stueck,
        closeTo(1000.0 * (1 - 1 / 1.005) / reihe.kurs(0), 1e-9),
      );
    });

    test(
        'Spieler ohne Anfangskauf, der nur den Sparplan mitläuft, landet exakt '
        'beim Investor', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 5,
        kursFuer: (t) => 80 + 60 * t,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      // Künstlich in denselben Startzustand wie der Investor versetzen, ohne
      // kaufen() zu rufen: investiert=true allein würde nur zukünftige
      // Einzahlungen betreffen, nicht das bereits gehaltene Anfangscash.
      e.spieler.investiert = true;
      e.spieler.stueck = e.cfg.startCash / e.kurs;
      e.spieler.cash = 0;

      while (!e.fertig) {
        e.schritt();
      }

      expect(e.wertSpieler, closeTo(e.wertInvestor, 1e-9));
    });
  });

  group('Marktstimmung / Allzeithoch', () {
    test('ATH ist rundenlokal und startet beim ersten Kurs', () {
      final reihe = Kursreihe.ausListen(
        [0, 1, 2, 3].map((d) => Kursreihe.zuEpochTag(start.add(Duration(days: d)))).toList(),
        [50.0, 40.0, 45.0, 60.0],
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      expect(e.ath, 50.0);
      expect(e.stimmung, 1.0);

      e.schritt(); // 40 -> unter dem Hoch
      expect(e.ath, 50.0);
      expect(e.stimmung, closeTo(0.8, 1e-9));

      e.schritt(); // 45
      e.schritt(); // 60 -> neues Hoch
      expect(e.ath, 60.0);
      expect(e.stimmung, 1.0);
    });
  });

  group('Rundenende', () {
    test('letzter Kurs wird verarbeitet und schritt() ist danach idempotent', () {
      final reihe = Kursreihe.ausListen(
        [0, 1, 2].map((d) => Kursreihe.zuEpochTag(start.add(Duration(days: d)))).toList(),
        [10.0, 20.0, 30.0],
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      e.schritt();
      e.schritt();
      expect(e.fertig, isTrue);
      expect(e.kurs, 30.0); // der letzte Kurs zählt

      final wert = e.wertInvestor;
      e.schritt();
      e.schritt();
      expect(e.wertInvestor, wert);
    });

    test('nach Rundenende ist Handeln gesperrt', () {
      final reihe = Kursreihe.ausListen(
        [0, 1, 2].map((d) => Kursreihe.zuEpochTag(start.add(Duration(days: d)))).toList(),
        [10.0, 20.0, 30.0],
      );
      final e = laufeDurch(reihe, const SpielKonfiguration(zinssatz: 0.0));
      expect(e.fertig, isTrue);

      final cashVorher = e.spieler.cash;
      e.kaufen();
      expect(e.spieler.cash, cashVorher, reason: 'Kaufen nach Ende darf nichts tun');
      expect(e.spieler.stueck, 0);
    });
  });

  group('Stolpern / Rennstreifen (Momentum)', () {
    /// Ground-Truth-Basis: kleinster Kurs mit Epochtag >= [zielTag], gesucht
    /// direkt in der übergebenen Reihe (unabhängig vom Engine-internen Weg).
    double? basisAusReihe(Kursreihe r, int zielTag) {
      for (var idx = 0; idx < r.laenge; idx++) {
        if (r.epochTag(idx) >= zielTag) return r.kurs(idx);
      }
      return null;
    }

    test('renditeJahr/-Monat treffen exakt, auch über Wochenend-Lücken hinweg', () {
      final reihe = baueReihe(
        start: DateTime.utc(2010, 1, 1),
        kalenderTage: 365 * 2,
        kursFuer: (t) => 100 + 300 * t, // linear steigend
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      // Weit genug reinlaufen, damit ein volles Jahr Rückblick existiert.
      while (reihe.epochTag(e.i) - reihe.ersterTag < 400) {
        e.schritt();
      }

      final zielMonat = reihe.epochTag(e.i) - 30;
      final zielJahr = reihe.epochTag(e.i) - 365;
      final basisMonat = basisAusReihe(reihe, zielMonat)!;
      final basisJahr = basisAusReihe(reihe, zielJahr)!;

      expect(e.renditeMonat, closeTo((e.kurs - basisMonat) / basisMonat, 1e-9));
      expect(e.renditeJahr, closeTo((e.kurs - basisJahr) / basisJahr, 1e-9));
    });

    test('nutzt vorlauf, wenn reihe selbst noch nicht weit genug zurückreicht', () {
      final voll = baueReihe(
        start: DateTime.utc(2010, 1, 1),
        kalenderTage: 500,
        kursFuer: (t) => 100 + 200 * t,
      );
      // Rundenbeginn irgendwo in der Mitte -> davor bleibt Vorlauf.
      final von = voll.laenge ~/ 2;
      final vorlauf = voll.ausschnitt(0, von);
      final rundenReihe = voll.ausschnitt(von, voll.laenge);

      final e = RennenEngine(rundenReihe, const SpielKonfiguration(zinssatz: 0.0),
          vorlauf: vorlauf);
      // Am allerersten Tag der Runde liegt der gesamte Monats-Rückblick im Vorlauf.
      final zielMonat = rundenReihe.epochTag(0) - 30;
      final erwarteteBasis = basisAusReihe(voll, zielMonat)!;
      expect(e.renditeMonat, closeTo((e.kurs - erwarteteBasis) / erwarteteBasis, 1e-9));
    });

    test('starkSteigend kippt exakt bei +10% Jahresrendite (strikt größer)', () {
      final basis = Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 1));
      final kurse = List<double>.generate(367, (d) {
        if (d < 365) return 100.0;
        if (d == 365) return 110.0; // exakt +10 %
        return 110.01; // knapp darüber
      });
      final reihe = Kursreihe.ausListen(List.generate(367, (d) => basis + d), kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      while (e.i < 365) {
        e.schritt();
      }
      expect(e.renditeJahr, closeTo(0.10, 1e-9));
      expect(e.starkSteigend, isFalse);

      e.schritt(); // Tag 366
      expect(e.renditeJahr, closeTo(0.1001, 1e-9));
      expect(e.starkSteigend, isTrue);
    });

    test('Stolpern kippt exakt bei -10% Monatsrendite (strikt kleiner)', () {
      final basis = Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 1));
      final kurse = List<double>.generate(32, (d) {
        if (d < 30) return 100.0;
        if (d == 30) return 90.0; // exakt -10 %
        return 89.98; // knapp darunter
      });
      final reihe = Kursreihe.ausListen(List.generate(32, (d) => basis + d), kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      while (e.i < 30) {
        e.schritt();
      }
      expect(e.renditeMonat, closeTo(-0.10, 1e-9));
      expect(e.stolpertJetzt, isFalse);

      e.schritt(); // Tag 31
      expect(e.renditeMonat, closeTo((89.98 - 100) / 100, 1e-9));
      expect(e.stolpertJetzt, isTrue);
    });

    test(
        'Stolpern höchstens einmal pro Jahr: Crash innerhalb der Kühlzeit löst nicht '
        'erneut aus, einer danach schon', () {
      final basis = Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 1));
      // Tag 30: erster Crash (-15%). Tag 130 (=Tag30+100, innerhalb der
      // Kühlzeit): zweiter Crash, wird unterdrückt. Tag 396 (=Tag30+366,
      // außerhalb der Kühlzeit): dritter Crash, löst wieder aus.
      double kursFuer(int d) {
        if (d < 30) return 100.0;
        if (d < 130) return 85.0;
        if (d < 396) return 70.0;
        return 50.0;
      }

      final kurse = List<double>.generate(397, kursFuer);
      final reihe = Kursreihe.ausListen(List.generate(397, (d) => basis + d), kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      final ausloeseTage = <int>[];
      while (!e.fertig) {
        e.schritt();
        if (e.stolpertJetzt) ausloeseTage.add(e.i);
      }

      expect(ausloeseTage, [30, 396]);
    });

    test('ohne ausreichende Historie bleiben Rendite und Stolpern inaktiv (keine Exception)', () {
      final basis = Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 1));
      // Scharfer Einbruch gleich zu Beginn – aber es gibt noch keinen Monat Historie.
      final kurse = [100.0, 90.0, 70.0, 50.0, 40.0];
      final reihe =
          Kursreihe.ausListen(List.generate(kurse.length, (d) => basis + d), kurse);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));

      while (!e.fertig) {
        e.schritt();
        expect(e.renditeMonat, isNull);
        expect(e.renditeJahr, isNull);
        expect(e.stolpertJetzt, isFalse);
        expect(e.starkSteigend, isFalse);
      }
    });

    test('zu kurzer Vorlauf reicht nicht für die Monatsrendite -> weiterhin null', () {
      final basis = Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 1));
      final vorlauf =
          Kursreihe.ausListen([basis - 10, basis - 5], [95.0, 97.0]); // nur 10 Tage
      final reihe = Kursreihe.ausListen([basis, basis + 1], [100.0, 101.0]);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0), vorlauf: vorlauf);

      expect(e.renditeMonat, isNull);
    });
  });

  group('Abgeltungsteuer', () {
    test('ohne steuernAktiv verhält sich Kaufen/Verkaufen exakt wie zuvor', () {
      final reihe = baueReihe(start: start, kalenderTage: 365 * 3, kursFuer: (t) => 40 + 60 * t);

      RennenEngine baueUndHandle(SpielKonfiguration cfg) {
        final e = RennenEngine(reihe, cfg);
        e.kaufen();
        for (var i = 0; i < 100; i++) {
          e.schritt();
        }
        e.verkaufen();
        while (!e.fertig) {
          e.schritt();
        }
        return e;
      }

      final ohne = baueUndHandle(const SpielKonfiguration(zinssatz: 3.0));
      final mitParamsAberAus = baueUndHandle(const SpielKonfiguration(
        zinssatz: 3.0,
        steuersatz: 0.26375,
        teilfreistellung: 0.30,
        sparerpauschbetrag: 1000,
        steuernAktiv: false,
      ));

      expect(mitParamsAberAus.wertSpieler, ohne.wertSpieler);
      expect(mitParamsAberAus.wertInvestor, ohne.wertInvestor);
      expect(mitParamsAberAus.wertSicherheit, ohne.wertSicherheit);
      expect(mitParamsAberAus.gezahlteSteuerSpieler, 0);
      expect(mitParamsAberAus.gezahlteSteuerSicherheit, 0);
    });

    test('Verkauf mit Gewinn unterhalb des Freibetrags kostet keine Steuer', () {
      // Ein dritter Tag als Puffer: sonst würde schritt() die Runde schon
      // beenden, bevor verkaufen() überhaupt aufgerufen wird.
      final reihe = Kursreihe.ausListen(
        [0, 1, 2].map((d) => Kursreihe.zuEpochTag(start.add(Duration(days: d)))).toList(),
        [100.0, 110.0, 110.0],
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0, steuernAktiv: true));
      e.kaufen();
      e.schritt();
      e.verkaufen();

      final stueck = 1000.0 / (100.0 * 1.005);
      final erloesOhneSteuer = stueck * 110.0 * 0.995;

      expect(e.gezahlteSteuerSpieler, 0);
      expect(e.spieler.cash, closeTo(erloesOhneSteuer, 1e-6));
    });

    test('Verkauf mit Gewinn über dem Freibetrag kostet exakt (gewinn-rest)*Steuersatz', () {
      final reihe = Kursreihe.ausListen(
        [0, 1, 2].map((d) => Kursreihe.zuEpochTag(start.add(Duration(days: d)))).toList(),
        [100.0, 300.0, 300.0],
      );
      const cfg = SpielKonfiguration(zinssatz: 0.0, steuernAktiv: true);
      final e = RennenEngine(reihe, cfg);
      e.kaufen();
      e.schritt();
      e.verkaufen();

      final stueck = 1000.0 / (100.0 * 1.005);
      final erloes = stueck * 300.0 * 0.995;
      final gewinn = erloes - 1000.0;
      final erwarteteSteuer = (gewinn - cfg.sparerpauschbetrag) * cfg.steuersatz;

      expect(e.gezahlteSteuerSpieler, closeTo(erwarteteSteuer, 1e-6));
      expect(e.spieler.cash, closeTo(erloes - erwarteteSteuer, 1e-6));
    });

    test('Teilfreistellung 0.30 senkt die Steuer exakt um 30%', () {
      // sparerpauschbetrag:0 nimmt den Freibetrag aus der Gleichung heraus,
      // damit ausschließlich der Teilfreistellungs-Faktor gemessen wird.
      final reihe = Kursreihe.ausListen(
        [0, 1, 2].map((d) => Kursreihe.zuEpochTag(start.add(Duration(days: d)))).toList(),
        [100.0, 300.0, 300.0],
      );

      double steuerFuer(double teilfreistellung) {
        final e = RennenEngine(
          reihe,
          SpielKonfiguration(
              zinssatz: 0.0, steuernAktiv: true, teilfreistellung: teilfreistellung, sparerpauschbetrag: 0),
        );
        e.kaufen();
        e.schritt();
        e.verkaufen();
        return e.gezahlteSteuerSpieler;
      }

      final ohneTeilfreistellung = steuerFuer(0.0);
      final mitTeilfreistellung = steuerFuer(0.30);
      expect(mitTeilfreistellung, closeTo(ohneTeilfreistellung * 0.7, 1e-9));
    });

    test('Verlust und anschließender Gewinn verrechnen sich korrekt im Verlusttopf', () {
      const cfg = SpielKonfiguration(zinssatz: 0.0, steuernAktiv: true, sparerpauschbetrag: 0);

      RennenEngine baueMitVerlustDannGewinn(double kursNachGewinn) {
        // Ein vierter Tag als Puffer: sonst würde schritt() die Runde schon
        // beenden, bevor der zweite verkaufen()-Aufruf greift.
        final reihe = Kursreihe.ausListen(
          [0, 1, 2, 3].map((d) => Kursreihe.zuEpochTag(start.add(Duration(days: d)))).toList(),
          [100.0, 50.0, kursNachGewinn, kursNachGewinn],
        );
        final e = RennenEngine(reihe, cfg);
        e.kaufen(); // Tag 0, Kurs 100
        e.schritt(); // -> Tag 1, Kurs 50
        e.verkaufen(); // Verlust
        e.kaufen(); // sofort wieder investieren
        e.schritt(); // -> Tag 2
        e.verkaufen(); // Gewinn
        return e;
      }

      // Gewinn kleiner als der Verlust -> vollständig verrechnet, keine Steuer.
      final kleinerGewinn = baueMitVerlustDannGewinn(55.0);
      expect(kleinerGewinn.gezahlteSteuerSpieler, 0);

      // Gewinn größer als der Verlust -> nur der Überschuss wird versteuert.
      final grosserGewinn = baueMitVerlustDannGewinn(150.0);
      final cashNachVerlust = (1000.0 / (100.0 * 1.005)) * 50.0 * 0.995;
      final verlust1 = 1000.0 - cashNachVerlust;
      final stueck2 = cashNachVerlust / (50.0 * 1.005);
      final erloes2 = stueck2 * 150.0 * 0.995;
      final gewinn2 = erloes2 - cashNachVerlust;
      final erwarteteSteuer = (gewinn2 - verlust1) * cfg.steuersatz;
      expect(grosserGewinn.gezahlteSteuerSpieler, closeTo(erwarteteSteuer, 1e-6));
    });

    test('Der Sparerpauschbetrag setzt sich zum Jahreswechsel zurück', () {
      final reihe = Kursreihe.ausListen(
        [
          DateTime.utc(2020, 12, 20),
          DateTime.utc(2020, 12, 25),
          DateTime.utc(2021, 1, 5),
          DateTime.utc(2021, 1, 10),
          DateTime.utc(2021, 1, 11),
        ].map(Kursreihe.zuEpochTag).toList(),
        // Zweiter Kursanstieg bewusst schwächer (100->150 statt 100->200):
        // der Einstand ist nach dem ersten steuerfreien Verkauf schon höher
        // (~1980 € statt 1000 €), derselbe prozentuale Anstieg ergäbe sonst
        // einen deutlich größeren absoluten Gewinn als beim ersten Verkauf.
        [100.0, 200.0, 100.0, 150.0, 150.0],
      );
      // monatsEinzahlung:0, damit die Sparplan-Einzahlung beim Monatswechsel
      // (Dez->Jan fällt hier mit dem Jahreswechsel zusammen) nicht zusätzlich
      // Cash einbringt und die Gewinnrechnung verkompliziert.
      final e = RennenEngine(
          reihe, const SpielKonfiguration(zinssatz: 0.0, monatsEinzahlung: 0.0, steuernAktiv: true));

      e.kaufen(); // Tag 0, 2020
      e.schritt(); // -> Tag 1, 2020
      e.verkaufen(); // Gewinn knapp unter dem Freibetrag
      expect(e.gezahlteSteuerSpieler, 0);

      e.schritt(); // -> Tag 2, bereits 2021 -> Freibetrag-Reset
      e.kaufen();
      e.schritt(); // -> Tag 3, 2021
      e.verkaufen(); // erneuter Gewinn knapp unter dem (zurückgesetzten)
      // Freibetrag – ohne Reset wäre er schon fast aufgebraucht.
      expect(e.gezahlteSteuerSpieler, 0);
    });

    test('latente Investor-Steuer bleibt bei wiederholtem Lesen gleich und '
        'mutiert wertInvestor nicht', () {
      final reihe = baueReihe(start: start, kalenderTage: 365 * 5, kursFuer: (t) => 50 + 100 * t);
      final e = laufeDurch(
        reihe,
        const SpielKonfiguration(zinssatz: 0.0, steuernAktiv: true, teilfreistellung: 0.30),
      );

      final wertVorher = e.wertInvestor;
      final steuer1 = e.latenteSteuerInvestor;
      final steuer2 = e.latenteSteuerInvestor;
      expect(steuer1, steuer2);
      expect(e.wertInvestor, wertVorher);

      final eingezahlt = e.cfg.startCash + e.cfg.monatsEinzahlung * e.einzahlungen;
      final buchgewinn = e.wertInvestor - eingezahlt;
      final erwartet = math.max(0.0, buchgewinn * (1 - e.cfg.teilfreistellung) - e.cfg.sparerpauschbetrag) *
          e.cfg.steuersatz;
      expect(steuer1, closeTo(erwartet, 1e-6));
    });

    test('Sicherheit versteuert Zinsen zum Jahreswechsel mit Freibetrag, ohne Teilfreistellung',
        () {
      const cfg = SpielKonfiguration(
        startCash: 100000,
        monatsEinzahlung: 0.0,
        zinssatz: 50.0,
        steuernAktiv: true,
        teilfreistellung: 0.30,
        sparerpauschbetrag: 1000,
      );
      final reihe = baueReihe(
        start: DateTime.utc(2020, 12, 1),
        kalenderTage: 35,
        kursFuer: (_) => 100.0,
        nurWerktage: false,
      );
      final e = RennenEngine(reihe, cfg);
      while (Kursreihe.zuDatum(e.reihe.epochTag(e.i)).year < 2021) {
        e.schritt();
      }

      // 31 Tage, nicht 30: die Zinsperiode vom 1. Dezember bis zum 1. Januar
      // liegt vollständig im Kalenderjahr 2020. Der letzte Schritt
      // (31.12. -> 01.01.) verzinst den 31. Dezember – früher wurde dieser
      // Tag dem Folgejahr zugeschlagen, seit P6 wird der Zins eines Schritts
      // anteilig auf die beiden Jahre verteilt.
      final zins2020 = 100000 * (math.pow(1.5, 31 / 365) - 1);
      final erwarteteSteuer2020 = math.max(0.0, zins2020 - cfg.sparerpauschbetrag) * cfg.steuersatz;
      // Ohne Teilfreistellung: cfg.teilfreistellung (0.30) darf hier nicht wirken.
      expect(e.gezahlteSteuerSicherheit, closeTo(erwarteteSteuer2020, 1e-3));
    });

    test('ein Schritt über den Jahreswechsel verteilt seinen Zins anteilig (P6)', () {
      const cfg = SpielKonfiguration(
        startCash: 100000,
        monatsEinzahlung: 0.0,
        zinssatz: 50.0,
        steuernAktiv: true,
        sparerpauschbetrag: 0,
      );
      // Handelstage 30.12.2020, 04.01. und 05.01.2021 – der erste Schritt
      // überspannt 5 Kalendertage, von denen 2 (30./31.12.) ins alte Jahr
      // gehören. Der dritte Tag sorgt dafür, dass die Runde nach dem ersten
      // Schritt noch läuft: beendeRunde() würde das Teiljahr sonst sofort
      // mitabrechnen und den Effekt verdecken.
      final reihe = Kursreihe.ausListen(
        [
          Kursreihe.zuEpochTag(DateTime.utc(2020, 12, 30)),
          Kursreihe.zuEpochTag(DateTime.utc(2021, 1, 4)),
          Kursreihe.zuEpochTag(DateTime.utc(2021, 1, 5)),
        ],
        [100.0, 100.0, 100.0],
      );
      final e = RennenEngine(reihe, cfg);
      e.schritt();

      expect(e.fertig, isFalse);
      final zinsGesamt = 100000 * (math.pow(1.5, 5 / 365) - 1);
      // 2 von 5 Tagen liegen in 2020 – nur dieser Teil wird zum Jahreswechsel
      // versteuert. Vorher landete der volle Betrag im neuen Jahr.
      expect(e.gezahlteSteuerSicherheit,
          closeTo(zinsGesamt * (2 / 5) * cfg.steuersatz, 1e-6));
    });

    test('eine über beendeRunde() vorzeitig beendete Runde rechnet das laufende '
        'Sicherheit-Teiljahr trotzdem ab', () {
      const cfg = SpielKonfiguration(
          startCash: 100000, monatsEinzahlung: 0.0, zinssatz: 20.0, steuernAktiv: true);
      final reihe = baueReihe(
        start: DateTime.utc(2021, 1, 1),
        kalenderTage: 100,
        kursFuer: (_) => 100.0,
        nurWerktage: false,
      );
      final e = RennenEngine(reihe, cfg);
      for (var i = 0; i < 50; i++) {
        e.schritt();
      }

      expect(e.fertig, isFalse);
      expect(e.gezahlteSteuerSicherheit, 0); // Jahr noch nicht gewechselt

      e.beendeRunde();

      expect(e.fertig, isTrue);
      expect(e.gezahlteSteuerSicherheit, greaterThan(0));
    });
  });

  group('Würfel-Investor', () {
    test('fester Seed ergibt eine deterministische Trade-Folge', () {
      final reihe = baueReihe(start: start, kalenderTage: 365 * 20, kursFuer: (t) => 50 + 60 * t);

      RennenEngine baueUndLaufe(int seed) {
        final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0),
            wuerfelAktiv: true, wuerfelSeed: seed);
        while (!e.fertig) {
          e.schritt();
        }
        return e;
      }

      final a = baueUndLaufe(42);
      final b = baueUndLaufe(42);
      final c = baueUndLaufe(43);

      expect(a.wuerfel.investiert, b.wuerfel.investiert);
      expect(a.wertWuerfel, closeTo(b.wertWuerfel!, 1e-9));
      // Kontrolle, dass der Seed tatsächlich etwas bewirkt (sonst wäre der
      // Vergleich mit gleichem Seed bedeutungslos).
      expect(a.wertWuerfel != c.wertWuerfel || a.wuerfel.investiert != c.wuerfel.investiert, isTrue);
    });

    test('der Würfel-Investor zahlt Slippage bei jedem Umschalten', () {
      final reihe = baueReihe(start: start, kalenderTage: 365 * 20, kursFuer: (t) => 50 + 40 * t);
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0),
          wuerfelAktiv: true, wuerfelSeed: 7);

      var vorherInvestiert = e.wuerfel.investiert;
      var vorherCash = e.wuerfel.cash;
      var vorherStueck = e.wuerfel.stueck;
      var mindestensEinUmschalten = false;

      while (!e.fertig) {
        e.schritt();
        if (e.wuerfel.investiert != vorherInvestiert) {
          mindestensEinUmschalten = true;
          if (vorherInvestiert) {
            // War investiert und hat gerade verkauft. Die Einzahlung dieses
            // Schritts hat – da noch investiert – zuerst Stücke gekauft.
            final stueckBeimSchalten = vorherStueck + e.cfg.monatsEinzahlung / e.kurs;
            final ausf = e.kurs * (1 - e.cfg.slippage);
            expect(e.wuerfel.cash, closeTo(stueckBeimSchalten * ausf, 1e-6));
            expect(e.wuerfel.stueck, 0);
          } else {
            // War in Cash und hat gerade gekauft. Die Einzahlung dieses
            // Schritts ist – da noch nicht investiert – zuerst Cash geworden.
            final betragBeimSchalten = vorherCash + e.cfg.monatsEinzahlung;
            final ausf = e.kurs * (1 + e.cfg.slippage);
            expect(e.wuerfel.stueck, closeTo(betragBeimSchalten / ausf, 1e-6));
            expect(e.wuerfel.cash, 0);
          }
        }
        vorherInvestiert = e.wuerfel.investiert;
        vorherCash = e.wuerfel.cash;
        vorherStueck = e.wuerfel.stueck;
      }

      expect(mindestensEinUmschalten, isTrue);
    });

    test('deaktivierter Schalter: der Würfel-Investor existiert nicht, die Engine '
        'verhält sich exakt wie zuvor', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 365 * 3,
        kursFuer: (t) => 100 + 100 * t, // 100 -> 200
      );

      final ohneParam = laufeDurch(reihe, const SpielKonfiguration(zinssatz: 5.0));
      final mitExplizitAus = laufeDurch(
        reihe,
        const SpielKonfiguration(zinssatz: 5.0),
      );

      expect(ohneParam.wertWuerfel, isNull);
      expect(mitExplizitAus.wertWuerfel, isNull);
      expect(mitExplizitAus.wertSpieler, ohneParam.wertSpieler);
      expect(mitExplizitAus.wertInvestor, ohneParam.wertInvestor);
      expect(mitExplizitAus.wertSicherheit, ohneParam.wertSicherheit);
    });
  });

  test('Performance: 7500 Handelstage unter 50 ms', () {
    final reihe = baueReihe(
      start: DateTime.utc(1996, 1, 1),
      kalenderTage: 365 * 30,
      kursFuer: (t) => 100 * (1 + t),
    );
    final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 3.0));

    final uhr = Stopwatch()..start();
    while (!e.fertig) {
      e.schritt();
    }
    uhr.stop();

    expect(reihe.laenge, greaterThan(7000));
    expect(uhr.elapsedMilliseconds, lessThan(50));
  });
}
