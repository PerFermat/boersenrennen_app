import 'package:flutter/material.dart';

import '../domain/kursreihe.dart';
import '../domain/rennen_engine.dart';
import '../theme/arcade_theme.dart';

/// Zeichnet den mitwachsenden Kursverlauf im oberen Viertel.
///
/// Der Pfad wird pro Frame neu aufgebaut, aber über eine Min/Max-Hüllkurve
/// auf maximal zwei Punkte je Bildschirmspalte reduziert. Ein Cachen wäre
/// ohnehin sinnlos, weil sich die y-Skala bei jedem neuen Hoch ändert.
///
/// [vorlauf] ist die (dem Spieler bereits vor Rundenbeginn gezeigte) Historie
/// des letzten Jahres – während des Countdowns ist sie der gesamte Inhalt,
/// danach wächst der Verlauf der eigentlichen Runde rechts daran an.
///
/// [investiertVerlauf] hält für jeden bereits gespielten Tag fest, ob an
/// diesem Tag investiert war. Der Kursverlauf wird **abschnittsweise** in
/// dieser historischen Farbe gezeichnet – grün für investierte, rot für
/// nicht investierte Phasen – und bleibt so dauerhaft, statt sich rückwirkend
/// zu ändern, wenn später ge- oder verkauft wird.
class KursChartPainter extends CustomPainter {
  final RennenEngine engine;
  final Kursreihe vorlauf;
  final List<bool> investiertVerlauf;

  KursChartPainter(
    this.engine, {
    required this.vorlauf,
    required this.investiertVerlauf,
    required Listenable repaint,
  }) : super(repaint: repaint);

  double _kurs(int i) =>
      i < vorlauf.laenge ? vorlauf.kurs(i) : engine.reihe.kurs(i - vorlauf.laenge);

  /// War an Tag [i] (Vorlauf + Runde gemeinsam gezählt) investiert?
  ///
  /// Der Vorlauf liegt vor der Investitionsentscheidung und wird deshalb
  /// einheitlich in der **ersten** Runden-Farbe gezeigt (der Entscheidung aus
  /// dem Countdown) – erst ab Rundenbeginn gibt es eine echte Tageshistorie.
  bool _investiertAn(int i) {
    if (investiertVerlauf.isEmpty) return engine.spieler.investiert;
    if (i < vorlauf.laenge) return investiertVerlauf.first;
    final idx = i - vorlauf.laenge;
    return idx < investiertVerlauf.length ? investiertVerlauf[idx] : investiertVerlauf.last;
  }

  Color _farbe(bool investiert) => investiert ? ArcadeFarben.kaufen : ArcadeFarben.verkaufen;

  @override
  void paint(Canvas canvas, Size size) {
    final bis = vorlauf.laenge + engine.i;
    if (bis < 1) return;

    // Sichtbarer y-Bereich aus dem bisherigen Verlauf (Vorlauf + Runde).
    var min = double.infinity, max = -double.infinity;
    for (var i = 0; i <= bis; i++) {
      final k = _kurs(i);
      if (k < min) min = k;
      if (k > max) max = k;
    }
    if (max - min < 1e-9) {
      min -= 1;
      max += 1;
    }
    final polster = (max - min) * 0.12;
    min -= polster;
    max += polster;

    final breite = size.width;
    final hoehe = size.height;
    double xVon(int i) => bis == 0 ? 0 : i / bis * breite;
    double yVon(double k) => hoehe - (k - min) / (max - min) * hoehe;

    // Hüllkurve: pro Pixelspalte nur Extremwerte übernehmen. Parallel dazu
    // wird für jeden Punkt vermerkt, in welcher Investitionsphase seine
    // Spalte liegt – daraus ergeben sich später die Farbabschnitte.
    final punkte = <Offset>[];
    final investiert = <bool>[];
    final proSpalte = (bis / breite).ceil().clamp(1, 1 << 30);
    for (var i = 0; i <= bis; i += proSpalte) {
      var lo = _kurs(i), hi = lo;
      final ende = (i + proSpalte).clamp(0, bis);
      for (var j = i; j <= ende; j++) {
        final k = _kurs(j);
        if (k < lo) lo = k;
        if (k > hi) hi = k;
      }
      final x = xVon(i);
      final inv = _investiertAn(i);
      if (proSpalte == 1) {
        punkte.add(Offset(x, yVon(lo)));
        investiert.add(inv);
      } else {
        punkte.add(Offset(x, yVon(hi)));
        investiert.add(inv);
        punkte.add(Offset(x, yVon(lo)));
        investiert.add(inv);
      }
    }
    // Der aktuelle Kurs muss exakt am Ende sitzen.
    final aktuellerKurs = _kurs(bis);
    punkte.add(Offset(breite, yVon(aktuellerKurs)));
    investiert.add(_investiertAn(bis));

    // In zusammenhängende Abschnitte gleicher Investitionsphase zerlegen und
    // jeden separat zeichnen. Der Grenzpunkt gehört zu beiden Abschnitten,
    // damit die Linie ohne Lücke durchläuft.
    var start = 0;
    for (var i = 1; i <= punkte.length; i++) {
      final ende = i == punkte.length || investiert[i] != investiert[start];
      if (!ende) continue;
      _zeichneAbschnitt(canvas, punkte.sublist(start, i), hoehe, breite, _farbe(investiert[start]));
      start = i - 1;
    }

    // Kopfpunkt
    final farbeAmEnde = _farbe(investiert.last);
    final kopf = Offset(breite, yVon(aktuellerKurs));
    canvas.drawCircle(kopf, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(kopf, 4, Paint()..color = farbeAmEnde);
  }

  void _zeichneAbschnitt(
      Canvas canvas, List<Offset> punkte, double hoehe, double breite, Color farbe) {
    if (punkte.length < 2) return;

    final linie = Path()..moveTo(punkte.first.dx, punkte.first.dy);
    for (final p in punkte.skip(1)) {
      linie.lineTo(p.dx, p.dy);
    }

    final flaeche = Path.from(linie)
      ..lineTo(punkte.last.dx, hoehe)
      ..lineTo(punkte.first.dx, hoehe)
      ..close();
    canvas.drawPath(flaeche, Paint()..color = farbe.withValues(alpha: 0.22));

    canvas.drawPath(
      linie,
      Paint()
        ..color = farbe
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant KursChartPainter old) => false;
}
