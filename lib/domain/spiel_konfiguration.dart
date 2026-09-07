/// Spielparameter einer Runde. Reines Dart – kein Flutter.
class SpielKonfiguration {
  /// Startkapital jeder Strategie.
  final double startCash;

  /// Neue Einzahlung bei jedem Monatswechsel.
  final double monatsEinzahlung;

  /// Slippage des Spielers (0.005 = 0,5 % schlechterer Ausführungskurs).
  final double slippage;

  /// Fester Zinssatz der Strategie „Sicherheit" in % p. a.
  final double zinssatz;

  const SpielKonfiguration({
    this.startCash = 1000.0,
    this.monatsEinzahlung = 100.0,
    this.slippage = 0.005,
    this.zinssatz = 3.0,
  });

  SpielKonfiguration mitZinssatz(double z) => SpielKonfiguration(
        startCash: startCash,
        monatsEinzahlung: monatsEinzahlung,
        slippage: slippage,
        zinssatz: z,
      );
}
