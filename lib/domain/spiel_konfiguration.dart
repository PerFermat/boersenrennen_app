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

  /// Abgeltungsteuer inklusive Solidaritätszuschlag. 0.26375 = 25 % + 5,5 % Soli.
  /// Kirchensteuer bleibt außen vor.
  final double steuersatz;

  /// Teilfreistellung für Aktienfonds. 0.30 bei ETFs, 0 bei Einzelaktien,
  /// Indizes und Rohstoffen.
  final double teilfreistellung;

  /// Jährlicher Sparerpauschbetrag in Euro. Setzt sich zum 1. Januar zurück.
  final double sparerpauschbetrag;

  /// Schalter für den gesamten Steuerblock – erlaubt steuerfreie Runden
  /// und hält alle Bestandstests ohne Anpassung grün.
  ///
  /// Die Vorabpauschale auf thesaurierende Fonds wird bewusst NICHT
  /// modelliert (Vereinfachung).
  final bool steuernAktiv;

  const SpielKonfiguration({
    this.startCash = 1000.0,
    this.monatsEinzahlung = 100.0,
    this.slippage = 0.005,
    this.zinssatz = 3.0,
    this.steuersatz = 0.26375,
    this.teilfreistellung = 0.0,
    this.sparerpauschbetrag = 1000.0,
    this.steuernAktiv = false,
  });

  /// Teilfreistellung nach Aktienkatalog-Gruppe: ETFs/Fonds 30 %, sonst 0 %.
  static double teilfreistellungFuerGruppe(String gruppe) =>
      gruppe.contains('ETF') ? 0.30 : 0.0;

  SpielKonfiguration mitZinssatz(double z) => SpielKonfiguration(
        startCash: startCash,
        monatsEinzahlung: monatsEinzahlung,
        slippage: slippage,
        zinssatz: z,
        steuersatz: steuersatz,
        teilfreistellung: teilfreistellung,
        sparerpauschbetrag: sparerpauschbetrag,
        steuernAktiv: steuernAktiv,
      );
}
