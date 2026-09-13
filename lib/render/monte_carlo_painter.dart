import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../domain/monte_carlo.dart';
import '../theme/arcade_theme.dart';
import '../theme/geld.dart';

/// Zeichnet einen horizontalen Balken mit p10/Median/p90-Markierungen und der
/// Position des Spielers – die visuelle Einordnung zur Monte-Carlo-Verteilung.
///
/// Einmaliges Zeichnen, sobald das [MonteCarloErgebnis] vorliegt – **kein**
/// Ticker-getriebener Painter wie die Renn-Painter, deshalb kein `repaint:`.
class MonteCarloPainter extends CustomPainter {
  final MonteCarloErgebnis ergebnis;
  final double spielerEndwert;

  /// Währung der Runde – die Achsenbeschriftung muss dieselbe zeigen wie der
  /// Rest des Ergebnis-Screens.
  final String waehrung;

  MonteCarloPainter(this.ergebnis, this.spielerEndwert,
      {this.waehrung = Geld.standard});

  NumberFormat get _euroFormat => Geld.kompakt(waehrung);

  /// Textlayout ist vergleichsweise teuer, deshalb gecacht (gleiches Muster
  /// wie in den übrigen Painters dieser App).
  final Map<String, TextPainter> _textCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final von = ergebnis.schlechtesterLauf;
    final bis = ergebnis.besterLauf;
    final spanne = bis - von;
    if (spanne <= 0) return;

    final w = size.width;
    final mitteY = size.height * 0.42;
    double xVon(double wert) => ((wert - von) / spanne * w).clamp(0.0, w);

    // Balken-Grundlinie zwischen p10 und p90.
    final p10x = xVon(ergebnis.p10);
    final p90x = xVon(ergebnis.p90);
    canvas.drawLine(
      Offset(p10x, mitteY),
      Offset(p90x, mitteY),
      Paint()
        ..color = ArcadeFarben.neutral
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    _markierung(canvas, xVon(ergebnis.p10), mitteY, 'p10', ArcadeFarben.tinteHell, oben: false);
    _markierung(
        canvas, xVon(ergebnis.median), mitteY, 'Median', ArcadeFarben.tinte, oben: false);
    _markierung(canvas, xVon(ergebnis.p90), mitteY, 'p90', ArcadeFarben.tinteHell, oben: false);

    // Spielerposition – deutlich größer und in der Spieler-Farbe.
    final spielerX = xVon(spielerEndwert);
    canvas.drawCircle(Offset(spielerX, mitteY), 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(spielerX, mitteY),
      9,
      Paint()
        ..color = ArcadeFarben.spielerDunkel
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(Offset(spielerX, mitteY), 5, Paint()..color = ArcadeFarben.spieler);
    _text('Du: ${_euroFormat.format(spielerEndwert)}', 12, ArcadeFarben.spielerDunkel,
            FontWeight.w900)
        .paint(canvas, Offset((spielerX - 30).clamp(0, w - 60), mitteY + 16));
  }

  void _markierung(Canvas canvas, double x, double y, String label, Color farbe,
      {required bool oben}) {
    canvas.drawLine(
      Offset(x, y - 10),
      Offset(x, y + 10),
      Paint()
        ..color = farbe
        ..strokeWidth = 2,
    );
    final tp = _text(label, 10, farbe, FontWeight.w700);
    tp.paint(canvas, Offset(x - tp.width / 2, y - 26));
  }

  TextPainter _text(String text, double groesse, Color farbe, FontWeight gewicht) {
    final schluessel = '$text|$groesse|${farbe.toARGB32()}';
    return _textCache.putIfAbsent(schluessel, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: groesse, fontWeight: gewicht, color: farbe),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  bool shouldRepaint(covariant MonteCarloPainter old) => false;
}
