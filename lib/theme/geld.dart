import 'package:intl/intl.dart';

/// Geldformatierung für die Währung, in der eine Runde notiert.
///
/// Fast alle Titel liegen als Euro im App-Paket – der Exporter rechnet USD-
/// und Yen-Reihen beim Erzeugen der Assets um. Die Ausnahme ist der S&P 500
/// ab 1927: Die Wechselkurskette reicht nur bis 1957 zurück, und über die
/// Währungsreform von 1948 hinweg gibt es keinen sinnvollen Euro-Gegenwert –
/// die Reichsmark-Guthaben wurden dabei weitgehend entwertet. Diese Reihe
/// bleibt deshalb in Dollar und wird auch so beschriftet.
///
/// Die [NumberFormat]-Objekte werden zwischengespeichert: Die Painter rufen
/// sie pro Frame auf, und ein `NumberFormat` neu zu bauen ist nicht billig.
class Geld {
  static const String standard = 'EUR';

  static const Map<String, String> _symbole = {
    'EUR': '€',
    'USD': '\$',
    'JPY': '¥',
  };

  static String symbol(String waehrung) => _symbole[waehrung] ?? waehrung;

  static final Map<String, NumberFormat> _betrag = {};
  static final Map<String, NumberFormat> _kompakt = {};

  /// „1.234,56 €" – [nachkomma] 0 für Listen und Schilder, 2 für Endbeträge.
  static NumberFormat betrag(String waehrung, {int nachkomma = 2}) =>
      _betrag.putIfAbsent(
        '$waehrung/$nachkomma',
        () => NumberFormat.currency(
            locale: 'de_DE', symbol: symbol(waehrung), decimalDigits: nachkomma),
      );

  /// „12 Tsd. €" – für die Achsen des Monte-Carlo-Diagramms.
  static NumberFormat kompakt(String waehrung) => _kompakt.putIfAbsent(
        waehrung,
        () => NumberFormat.compactCurrency(
            locale: 'de_DE', symbol: symbol(waehrung), decimalDigits: 0),
      );
}
