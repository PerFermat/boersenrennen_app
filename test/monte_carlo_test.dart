import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/domain/monte_carlo.dart';
import 'package:boersenrennen_app/domain/spiel_konfiguration.dart';

import 'rennen_engine_test.dart' show baueReihe;

void main() {
  group('Monte-Carlo-Einordnung (V8)', () {
    test('Perzentil liegt plausibel zwischen 0 und 100 und p10 <= Median <= p90', () {
      final reihe = baueReihe(
        start: DateTime.utc(2005, 1, 1),
        kalenderTage: 365 * 8,
        kursFuer: (t) => 60 + 40 * (0.5 - 0.5 * (t * 15).remainder(1) * 2).abs(),
      );
      final ergebnis = simuliereMonteCarlo(MonteCarloArgs(
        reihe: reihe.materialisiert(),
        cfg: const SpielKonfiguration(zinssatz: 0.0),
        anzahlTrades: 6,
        ersteAktionIstKauf: true,
        tatsaechlicherEndwert: 5000.0,
        laeufe: 200,
        seed: 42,
      ));

      expect(ergebnis.laeufe, 200);
      expect(ergebnis.perzentil, inInclusiveRange(0.0, 100.0));
      expect(ergebnis.p10, lessThanOrEqualTo(ergebnis.median));
      expect(ergebnis.median, lessThanOrEqualTo(ergebnis.p90));
      expect(ergebnis.schlechtesterLauf, lessThanOrEqualTo(ergebnis.p10));
      expect(ergebnis.besterLauf, greaterThanOrEqualTo(ergebnis.p90));
    });

    test('gleicher Seed ergibt dasselbe Ergebnis (reproduzierbar)', () {
      final reihe = baueReihe(
        start: DateTime.utc(2005, 1, 1),
        kalenderTage: 365 * 5,
        kursFuer: (t) => 60 + 40 * t,
      );
      final args = MonteCarloArgs(
        reihe: reihe.materialisiert(),
        cfg: const SpielKonfiguration(zinssatz: 0.0),
        anzahlTrades: 4,
        ersteAktionIstKauf: true,
        tatsaechlicherEndwert: 3000.0,
        laeufe: 100,
        seed: 7,
      );

      final a = simuliereMonteCarlo(args);
      final b = simuliereMonteCarlo(args);
      expect(a.median, b.median);
      expect(a.perzentil, b.perzentil);
    });

    test('wirft bei null Trades', () {
      final reihe = baueReihe(
        start: DateTime.utc(2005, 1, 1),
        kalenderTage: 365 * 5,
        kursFuer: (t) => 60 + 40 * t,
      );
      expect(
        () => simuliereMonteCarlo(MonteCarloArgs(
          reihe: reihe.materialisiert(),
          cfg: const SpielKonfiguration(zinssatz: 0.0),
          anzahlTrades: 0,
          ersteAktionIstKauf: true,
          tatsaechlicherEndwert: 1000.0,
          laeufe: 100,
          seed: 1,
        )),
        throwsArgumentError,
      );
    });

    test('Performance: 1000 Läufe über ~2500 Handelstage unter 2000 ms', () {
      final reihe = baueReihe(
        start: DateTime.utc(1996, 1, 1),
        kalenderTage: 365 * 10,
        kursFuer: (t) => 100 * (1 + t),
      );
      expect(reihe.laenge, greaterThan(2000));

      final uhr = Stopwatch()..start();
      simuliereMonteCarlo(MonteCarloArgs(
        reihe: reihe.materialisiert(),
        cfg: const SpielKonfiguration(zinssatz: 3.0),
        anzahlTrades: 10,
        ersteAktionIstKauf: true,
        tatsaechlicherEndwert: 5000.0,
        laeufe: 1000,
        seed: 99,
      ));
      uhr.stop();

      expect(uhr.elapsedMilliseconds, lessThan(2000));
    });
  });
}
