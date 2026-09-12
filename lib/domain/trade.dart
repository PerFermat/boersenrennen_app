/// Eine manuelle Handelsentscheidung des Spielers.
/// Sparplan-Einzahlungen sind **keine** Trades – sie sind keine Entscheidung.
class Trade {
  /// Index in der Rundenreihe (`RennenEngine.i` zum Zeitpunkt des Trades).
  final int tagIndex;

  final int epochTag;

  final bool istKauf;

  /// Kurs ohne Slippage.
  final double marktKurs;

  /// Tatsächlicher Ausführungskurs mit Slippage.
  final double ausfuehrungsKurs;

  /// Bewegtes Euro-Volumen.
  final double betrag;

  /// Bewegte Stückzahl.
  final double stueck;

  final double depotwertDanach;

  /// Nur bei Verkauf gesetzt: Erlös minus Einstand der geschlossenen Position.
  final double? gewinnBeiVerkauf;

  const Trade({
    required this.tagIndex,
    required this.epochTag,
    required this.istKauf,
    required this.marktKurs,
    required this.ausfuehrungsKurs,
    required this.betrag,
    required this.stueck,
    required this.depotwertDanach,
    this.gewinnBeiVerkauf,
  });
}
