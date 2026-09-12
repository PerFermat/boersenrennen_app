import 'dart:math';

import 'kursreihe.dart';
import 'spiel_konfiguration.dart';
import 'spieler_pfad.dart';

/// Ergebnis von [simuliereMonteCarlo].
class MonteCarloErgebnis {
  final int laeufe;

  /// 0..100 – Anteil der Zufallsläufe, die schlechter abschnitten als der
  /// tatsächliche Spieler-Endwert.
  final double perzentil;

  final double median;
  final double p10;
  final double p90;
  final double besterLauf;
  final double schlechtesterLauf;

  const MonteCarloErgebnis({
    required this.laeufe,
    required this.perzentil,
    required this.median,
    required this.p10,
    required this.p90,
    required this.besterLauf,
    required this.schlechtesterLauf,
  });
}

/// Argument-Bündel für den Isolate-Aufruf über `compute()` – muss vollständig
/// serialisierbar sein. [reihe] muss bereits über [Kursreihe.materialisiert]
/// kopiert worden sein, bevor sie hierher übergeben wird.
class MonteCarloArgs {
  final Kursreihe reihe;
  final SpielKonfiguration cfg;

  /// Anzahl der Trades, die jeder Zufallslauf ebenfalls macht – kontrolliert
  /// für Handelsaktivität, damit das Perzentil TIMING isoliert statt bloßer
  /// Klickfreudigkeit.
  final int anzahlTrades;

  /// Richtung des ersten Trades des Spielers (Kauf oder Verkauf) – jeder
  /// Zufallslauf alterniert ab derselben Richtung.
  final bool ersteAktionIstKauf;

  final double tatsaechlicherEndwert;
  final int laeufe;
  final int seed;

  const MonteCarloArgs({
    required this.reihe,
    required this.cfg,
    required this.anzahlTrades,
    required this.ersteAktionIstKauf,
    required this.tatsaechlicherEndwert,
    required this.laeufe,
    required this.seed,
  });
}

/// Top-Level-Funktion, geeignet als `compute()`-Einstiegspunkt (reines Dart,
/// kein Flutter-Import). Führt [MonteCarloArgs.laeufe] Zufallsläufe mit
/// **derselben Handelsanzahl** wie der Spieler durch, an gleichverteilt
/// zufällig gezogenen, aufsteigend sortierten Handelstagen, abwechselnd in
/// derselben Kauf/Verkauf-Reihenfolge, mit der der Spieler begonnen hat.
///
/// Ohne diese Angleichung würde das Perzentil nur messen, wer öfter geklickt
/// hat, statt tatsächlich das Timing zu isolieren.
MonteCarloErgebnis simuliereMonteCarlo(MonteCarloArgs args) {
  if (args.anzahlTrades <= 0) {
    throw ArgumentError('Monte Carlo braucht mindestens einen Trade');
  }

  final random = Random(args.seed);
  final letzterKurs = args.reihe.kurs(args.reihe.laenge - 1);
  final endwerte = <double>[];

  for (var lauf = 0; lauf < args.laeufe; lauf++) {
    final tage = _zieheDistinkteTage(random, args.reihe.laenge, args.anzahlTrades);
    final aktionen = <GeplanteAktion>[];
    var istKauf = args.ersteAktionIstKauf;
    for (final t in tage) {
      aktionen.add(GeplanteAktion(t, istKauf));
      istKauf = !istKauf;
    }

    final ergebnis = simuliereSpielerpfad(
      reihe: args.reihe,
      cfg: args.cfg,
      aktionen: aktionen,
      mitSlippage: true,
    );
    endwerte.add(ergebnis.endwert(letzterKurs));
  }

  endwerte.sort();
  final schlechter = endwerte.where((w) => w < args.tatsaechlicherEndwert).length;
  final perzentil = schlechter / endwerte.length * 100;

  return MonteCarloErgebnis(
    laeufe: endwerte.length,
    perzentil: perzentil,
    median: endwerte[endwerte.length ~/ 2],
    p10: endwerte[(endwerte.length * 0.10).floor()],
    p90: endwerte[(endwerte.length * 0.90).floor()],
    besterLauf: endwerte.last,
    schlechtesterLauf: endwerte.first,
  );
}

/// Zieht [anzahl] verschiedene, aufsteigend sortierte Tagesindizes aus
/// `[0, laenge)`. Bei üblichen Handelszahlen (< 50) gegenüber tausenden
/// Handelstagen ist die Kollisionswahrscheinlichkeit vernachlässigbar –
/// simples Zurückweisungsverfahren genügt.
List<int> _zieheDistinkteTage(Random random, int laenge, int anzahl) {
  final tage = <int>{};
  while (tage.length < anzahl) {
    tage.add(random.nextInt(laenge));
  }
  final liste = tage.toList()..sort();
  return liste;
}
