/// Score-Berechnung – Port von `SpielService.relativeOutperformance`.
///
/// Rankingrelevant ist die Outperformance gegenüber dem **Investor**, weil
/// Zufallsaktie und Zufallszeitraum absolute Endbeträge unvergleichbar machen.
///
/// Reines Dart – kein Flutter.
class Score {
  /// (spieler - referenz) / referenz * 100, auf 2 Nachkommastellen gerundet.
  /// Referenz 0 (oder nicht endlich) ergibt 0.00.
  static double relativeOutperformance(double spieler, double referenz) {
    if (referenz == 0 || !referenz.isFinite || !spieler.isFinite) return 0.0;
    final wert = (spieler - referenz) / referenz * 100.0;
    return double.parse(wert.toStringAsFixed(2));
  }

  static double vsInvestor(double spieler, double investor) =>
      relativeOutperformance(spieler, investor);

  static double vsSicherheit(double spieler, double sicherheit) =>
      relativeOutperformance(spieler, sicherheit);
}
