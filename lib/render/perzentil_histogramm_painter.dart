import 'package:flutter/material.dart';

import '../theme/arcade_theme.dart';

/// Zeichnet ein einfaches Histogramm der Perzentile aus [SpielverlaufEintrag]s
/// über 10%-Buckets (0–10, 10–20, ..., 90–100).
///
/// Einmaliges Zeichnen bei fertiger Datenlage – **kein** Ticker-getriebener
/// Painter, deshalb kein `repaint:` (gleiches Muster wie [MonteCarloPainter]).
class PerzentilHistogrammPainter extends CustomPainter {
  /// Bereits auf 10 Buckets aggregierte Häufigkeiten (Index 0 = 0–10 %, ...).
  final List<int> buckets;

  PerzentilHistogrammPainter(this.buckets) : assert(buckets.length == 10);

  @override
  void paint(Canvas canvas, Size size) {
    final maxAnzahl = buckets.fold(0, (m, n) => n > m ? n : m);
    if (maxAnzahl == 0) return;

    final breitePerBucket = size.width / buckets.length;
    for (var i = 0; i < buckets.length; i++) {
      final h = size.height * (buckets[i] / maxAnzahl);
      final rect = Rect.fromLTWH(
        i * breitePerBucket + 2,
        size.height - h,
        breitePerBucket - 4,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = ArcadeFarben.investor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PerzentilHistogrammPainter old) => old.buckets != buckets;
}
