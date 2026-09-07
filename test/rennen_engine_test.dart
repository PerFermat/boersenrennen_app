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

    test('investiert: Einzahlung kauft sofort Stücke (mit Slippage)', () {
      final reihe = baueReihe(
        start: DateTime.utc(2010, 1, 15),
        kalenderTage: 100,
        kursFuer: (_) => 20.0,
      );
      final e = RennenEngine(reihe, const SpielKonfiguration(zinssatz: 0.0));
      e.kaufen(); // sofort investieren
      final stueckNachKauf = e.spieler.stueck;

      while (!e.fertig) {
        e.schritt();
      }

      expect(e.spieler.cash, 0);
      expect(e.spieler.stueck, greaterThan(stueckNachKauf));
      expect(
        e.spieler.stueck,
        closeTo(stueckNachKauf + e.einzahlungen * 100.0 / (20.0 * 1.005), 1e-9),
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

    test('Buy-and-Hold-Spieler bleibt unter dem Investor', () {
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
      // Der Rückstand ist genau die Slippage auf jeden investierten Euro.
      expect(e.wertSpieler / e.wertInvestor, closeTo(1 / 1.005, 1e-9));
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
