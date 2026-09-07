/// Eine der drei Anlagestrategien im Rennen. Reines Dart – kein Flutter.
class Strategie {
  final String name;

  /// Nicht investiertes Geld.
  double cash;

  /// Gehaltene Aktienanteile (fraktional).
  double stueck;

  /// Ob die Strategie gerade im Markt ist. Steuert bei „Spieler", ob neue
  /// Einzahlungen investiert werden, und in der Darstellung Rennen vs. Traben.
  bool investiert;

  Strategie(this.name, {this.cash = 0, this.stueck = 0, this.investiert = false});

  /// Depotwert = Cash + Aktienwert. Entscheidet über die Position im Rennen.
  double depotwert(double kurs) => cash + stueck * kurs;
}
