import 'dart:math' as math;

import 'package:flutter/material.dart';
// intl bringt ein eigenes TextDirection mit – hier ist das von Flutter gemeint.
import 'package:intl/intl.dart' hide TextDirection;

import '../spiel/rennen_controller.dart';
import '../theme/arcade_theme.dart';

/// Zeichnet die Rennstrecke als scrollende Welt.
///
/// Der Painter **rechnet nicht mehr**: Kamera und Kulisse werden im
/// [RennenController] fortgeschrieben, hier wird nur noch gemalt.
///
/// | Ebene            | Anteil | Wirkung                      |
/// |------------------|--------|------------------------------|
/// | Schilder, Bahnen | 1.00   | vorne, volle Geschwindigkeit |
/// | Bäume            | 0.45   | Mittelgrund, langsamer       |
/// | Wolken           | 0.15   | Hintergrund, am langsamsten  |
class RennstreckePainter extends CustomPainter {
  final RennenController controller;

  RennstreckePainter(this.controller, {required Listenable repaint})
      : super(repaint: repaint);

  static final _euroFormat = NumberFormat.decimalPattern('de_DE');

  /// Textlayout ist vergleichsweise teuer – die Beschriftungen ändern sich nur
  /// beim Überqueren eines Meilensteins, deshalb gecacht.
  final Map<String, TextPainter> _textCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final e = controller.engine;
    final k = controller.kamera;
    final kulisse = controller.kulisse;
    final laeufer = controller.laeufer;
    final w = size.width, h = size.height;

    kulisse.setzeBreite(w);

    final himmelH = h * 0.20;
    final schildH = h * 0.13;

    // Bahnen schrumpfen mit derselben Kurve wie die Figuren. Der
    // Schilderstreifen **wandert mit ihnen** – er bleibt direkt über der
    // Strecke. Der Block aus Schildern + Bahnen liegt bei vollem Zoom (100 %)
    // bündig zwischen Horizont und Bildunterkante; wird herausgezoomt, bleibt
    // er dabei **mittig in der Wiese** statt an einer Kante zu kleben – oben
    // und unten öffnet sich dann gleich viel offenes Feld.
    final basisBahnH = (h - himmelH - schildH) / laeufer.length;
    final bahnH = basisBahnH * k.groesseFaktor;
    final bahnBlockH = laeufer.length * bahnH;
    final wieseH = h - himmelH;
    final restRaum = wieseH - schildH - bahnBlockH;
    final schildOben = himmelH + restRaum / 2;
    final bahnOben = schildOben + schildH;
    final bahnUnten = bahnOben + bahnBlockH;

    final fenster = (k.bis - k.von).abs() < 1e-9 ? 1.0 : (k.bis - k.von);
    final pxProEuro = w / fenster;
    double xVon(double wert) => (wert - k.von) * pxProEuro;

    // ---------- Himmel ----------
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, himmelH), Paint()..color = ArcadeFarben.himmel);
    canvas.drawCircle(Offset(w * 0.13, himmelH * 0.42), himmelH * 0.28,
        Paint()..color = ArcadeFarben.sonne);

    for (final wolke in kulisse.wolken) {
      _wolke(canvas, wolke.x, himmelH, wolke.groesse, wolke.variante);
    }
    for (final baum in kulisse.baeume) {
      _baum(canvas, baum.x, himmelH, baum.groesse, baum.variante);
    }

    // ---------- Offenes Feld zwischen Horizont und Strecke ----------
    canvas.drawRect(Rect.fromLTWH(0, himmelH, w, h - himmelH),
        Paint()..color = ArcadeFarben.wiese);
    _feldTextur(canvas, w, himmelH, schildOben, k.groesseFaktor);

    // ---------- Schilderstreifen (wandert mit den Bahnen) ----------
    canvas.drawRect(Rect.fromLTWH(0, schildOben, w, schildH),
        Paint()..color = ArcadeFarben.wieseDunkel);

    // ---------- Bahnen ----------
    for (var i = 0; i < laeufer.length; i++) {
      final oben = bahnOben + i * bahnH;
      _bahnTextur(canvas, w, oben, bahnH, i, k.groesseFaktor);
      if (i < laeufer.length - 1) _trennlinie(canvas, oben + bahnH, w, k.groesseFaktor);
    }

    // ---------- Meilensteine ----------
    // Die Markierungslinie reicht nur bis zum unteren Rand des Bahnblocks,
    // nicht bis zur Bildkante – darunter ist jetzt offenes Feld.
    for (final schild in kulisse.schilder) {
      if (schild.sichtbarkeit <= 0.001) continue;
      _meilenstein(canvas, xVon(schild.wert), bahnUnten, schildOben, schildH,
          schild.wert, schild.sichtbarkeit);
    }

    // ---------- Offenes Feld unterhalb der Bahnen ----------
    _feldTextur(canvas, w, bahnUnten, h, k.groesseFaktor);

    // ---------- Bahnbeschriftung (hinter den Läufern) ----------
    if (bahnH > 30) {
      for (var i = 0; i < laeufer.length; i++) {
        _label(canvas, laeufer[i].name, Offset(8, bahnOben + i * bahnH + 3),
            (bahnH * 0.22).clamp(8.0, 12.0));
      }
    }

    // ---------- Läufer ----------
    final radius = (basisBahnH * 0.26).clamp(10.0, 34.0) * k.groesseFaktor;
    // Nur bei klar steigendem Jahrestrend gibt's Rennstreifen – einmal pro
    // Frame bestimmt, gilt für alle Läufer gleich.
    final starkSteigend = e.starkSteigend;
    for (var i = 0; i < laeufer.length; i++) {
      final bodenY = bahnOben + i * bahnH + bahnH - radius * 0.55;
      final x = xVon(controller.angezeigteWerte[i])
          .clamp(radius * 1.2, w - radius * 1.2);

      _laeufer(canvas, Offset(x, bodenY), laeufer[i].farbe, laeufer[i].farbeDunkel,
          laeufer[i].investiert, starkSteigend, controller.stolperIntensitaet[i], radius);
    }
  }

  // =================================================================
  //  Kulisse
  // =================================================================

  void _wolke(Canvas canvas, double x, double himmelH, double groesse, double v) {
    final farbe = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final y = himmelH * (0.18 + v * 0.34);
    final b = himmelH * 0.62 * groesse;
    canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: b, height: b * 0.42), farbe);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x + b * 0.28, y + b * 0.1),
            width: b * 0.66,
            height: b * 0.34),
        farbe);
  }

  void _baum(Canvas canvas, double x, double himmelH, double groesse, double v) {
    final stamm = Paint()..color = const Color(0xFF8A6240);
    final krone = Paint()..color = const Color(0xFF4E9E5A);
    final kroneHell = Paint()..color = const Color(0xFF5CB268);

    final hoehe = himmelH * 0.5 * groesse;
    final fuss = himmelH; // stehen auf dem Horizont
    final breite = hoehe * 0.72;

    canvas.drawRect(
        Rect.fromLTWH(x - hoehe * 0.06, fuss - hoehe * 0.34, hoehe * 0.12, hoehe * 0.34),
        stamm);
    canvas.drawCircle(Offset(x, fuss - hoehe * 0.55), breite * 0.42, krone);
    canvas.drawCircle(Offset(x - breite * (0.18 + v * 0.1), fuss - hoehe * 0.42),
        breite * 0.3, kroneHell);
    canvas.drawCircle(Offset(x + breite * (0.2 + v * 0.1), fuss - hoehe * 0.44),
        breite * 0.28, krone);
  }

  // =================================================================
  //  Bahn: Textur, Trennlinien, Meilensteine
  // =================================================================

  /// Feine Textur für das offene Feld zwischen Horizont und Strecke.
  /// Ohne sie wirkt die beim Herauszoomen frei werdende Fläche wie eine
  /// leere grüne Platte. Läuft mit derselben Geschwindigkeit wie die Strecke.
  void _feldTextur(
      Canvas canvas, double w, double oben, double unten, double zoom) {
    final hoehe = unten - oben;
    if (hoehe < 20) return;

    final periode = w * 0.085 * zoom;
    if (periode < 6) return;

    final halm = Paint()
      ..color = ArcadeFarben.wieseDunkel.withValues(alpha: 0.35)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final versatz = controller.kulisse.grasVersatz % periode;
    final reihen = (hoehe / (periode * 0.75)).clamp(1, 14).toInt();

    for (var reihe = 0; reihe < reihen; reihe++) {
      final y = oben + hoehe * (reihe + 0.5) / reihen;
      // Ungerade Reihen versetzt, damit kein Gittermuster entsteht.
      final reihenVersatz = reihe.isEven ? 0.0 : periode * 0.5;
      for (var i = -1;; i++) {
        final x = i * periode + versatz + reihenVersatz;
        if (x > w + periode) break;
        final r = math.Random(i * 17 + reihe * 613);
        final laenge = 4 + r.nextDouble() * 5;
        canvas.drawLine(
            Offset(x, y), Offset(x + (r.nextDouble() - 0.5) * 3, y - laenge), halm);
      }
    }
  }

  /// Grasbüschel als mitlaufende Textur. Abstand **und** Größe skalieren mit
  /// dem Zoom, damit die Textur beim Herauszoomen feiner wird.
  void _bahnTextur(
      Canvas canvas, double w, double oben, double bahnH, int bahn, double zoom) {
    if (bahnH < 6) return;

    canvas.drawRect(
        Rect.fromLTWH(0, oben + bahnH - bahnH * 0.09, w, bahnH * 0.09),
        Paint()..color = ArcadeFarben.wieseDunkel);

    final periode = w * 0.055 * zoom;
    if (periode < 5) return;

    final buschel = Paint()
      ..color = ArcadeFarben.wieseDunkel
      ..strokeWidth = math.max(1.0, bahnH * 0.035)
      ..strokeCap = StrokeCap.round;

    final versatz = controller.kulisse.grasVersatz % periode;

    for (var i = -1;; i++) {
      final x = i * periode + versatz;
      if (x > w + periode) break;
      final r = math.Random(i * 31 + bahn * 977);
      final y = oben + bahnH * (0.30 + r.nextDouble() * 0.5);
      final hoehe = bahnH * (0.07 + r.nextDouble() * 0.07);
      final neigung = (r.nextDouble() - 0.5) * hoehe * 0.7;
      canvas.drawLine(Offset(x, y), Offset(x + neigung, y - hoehe), buschel);
      canvas.drawLine(Offset(x + hoehe * 0.4, y),
          Offset(x + hoehe * 0.4 + neigung, y - hoehe * 0.7), buschel);
    }
  }

  void _trennlinie(Canvas canvas, double y, double w, double zoom) {
    final periode = w * 0.075 * zoom;
    if (periode < 4) return;

    final farbe = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = math.max(1.2, 2.5 * zoom)
      ..strokeCap = StrokeCap.round;

    final versatz = controller.kulisse.grasVersatz % periode;
    for (var i = -1;; i++) {
      final x = i * periode + versatz;
      if (x > w + periode) break;
      canvas.drawLine(Offset(x, y), Offset(x + periode * 0.45, y), farbe);
    }
  }

  /// Schild mit Euro-Betrag plus dünner Markierungslinie durch die Bahnen.
  void _meilenstein(Canvas canvas, double x, double unten, double schildOben,
      double schildH, double wert, double sicht) {
    canvas.drawLine(
      Offset(x, schildOben + schildH * 0.72),
      Offset(x, unten),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45 * sicht)
        ..strokeWidth = 1.5,
    );

    final tp = _text('${_euroFormat.format(wert.round())} €',
        (schildH * 0.30).clamp(9.0, 15.0));

    final pfostenOben = schildOben + schildH * 0.34;
    canvas.drawLine(
      Offset(x, pfostenOben),
      Offset(x, schildOben + schildH * 0.78),
      Paint()
        ..color = const Color(0xFF8A6240).withValues(alpha: sicht)
        ..strokeWidth = math.max(2.0, schildH * 0.06),
    );

    // Polsterung an der Schriftgröße festmachen, nicht an der Streifenhöhe –
    // sonst werden die Plaketten unnötig breit und überdecken einander.
    final b = tp.width + tp.height * 0.9;
    final hoehe = tp.height * 1.5;
    final mitte = Offset(x, pfostenOben - hoehe * 0.36);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: mitte, width: b, height: hoehe),
      Radius.circular(hoehe * 0.28),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: sicht));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = ArcadeFarben.kursLinie.withValues(alpha: sicht)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final textPos = Offset(x - tp.width / 2, mitte.dy - tp.height / 2);
    if (sicht > 0.99) {
      tp.paint(canvas, textPos);
    } else {
      // Beim Ausblenden muss auch die Schrift mitverblassen.
      canvas.saveLayer(rect.outerRect.inflate(4),
          Paint()..color = Colors.white.withValues(alpha: sicht));
      tp.paint(canvas, textPos);
      canvas.restore();
    }
  }

  TextPainter _text(String text, double groesse) {
    final schluessel = '$text|${groesse.toStringAsFixed(1)}';
    return _textCache.putIfAbsent(schluessel, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: groesse,
            fontWeight: FontWeight.w800,
            color: ArcadeFarben.tinte,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  // =================================================================
  //  Läufer
  // =================================================================

  /// Eine Cartoon-Figur mit Radius [r].
  /// [investiert] steuert die Amplitude: voll investiert = sprinten,
  /// in Cash = traben (deutlich ruhigere Bewegung).
  /// [starkSteigend] schaltet zusätzlich zu [investiert] die Rennstreifen frei
  /// (nur bei klar steigendem Jahrestrend).
  /// [stolperIntensitaet] (0..1, 1 = gerade ausgelöst) lässt die Figur beim
  /// Kurscrash kurz aus dem Tritt geraten – ohne neue Zeichen-Elemente wird
  /// die gesamte Figur dafür kurz um ihren Fußpunkt gekippt.
  void _laeufer(Canvas canvas, Offset fuss, Color farbe, Color dunkel, bool investiert,
      bool starkSteigend, double stolperIntensitaet, double r) {
    final stolperWinkel = stolperIntensitaet > 0
        ? stolperIntensitaet * 0.5 * math.sin(stolperIntensitaet * math.pi * 2.5)
        : 0.0;
    if (stolperWinkel != 0) {
      canvas.save();
      canvas.translate(fuss.dx, fuss.dy);
      canvas.rotate(stolperWinkel);
      canvas.translate(-fuss.dx, -fuss.dy);
    }

    final phase = controller.engine.phase;
    final huepf = math.sin(phase) *
        (investiert ? r * 0.45 : r * 0.14) *
        (1 - stolperIntensitaet * 0.6);
    final mitte = Offset(fuss.dx, fuss.dy - r * 1.45 + huepf);

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(fuss.dx, fuss.dy + r * 0.18), width: r * 1.9, height: r * 0.45),
      Paint()..color = Colors.black.withValues(alpha: 0.13),
    );

    final schwung = math.cos(phase) * (investiert ? r * 0.55 : r * 0.18);
    final bein = Paint()
      ..color = dunkel
      ..strokeWidth = r * 0.26
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        mitte + Offset(-r * 0.2, r * 0.75), Offset(mitte.dx - schwung, fuss.dy), bein);
    canvas.drawLine(
        mitte + Offset(r * 0.2, r * 0.75), Offset(mitte.dx + schwung, fuss.dy), bein);

    canvas.drawCircle(mitte, r, Paint()..color = farbe);
    canvas.drawCircle(
      mitte,
      r,
      Paint()
        ..color = dunkel
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.17,
    );

    if (investiert && starkSteigend) {
      final wind = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = r * 0.15
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          mitte + Offset(-r * 1.35, -r * 0.35), mitte + Offset(-r * 2.2, -r * 0.35), wind);
      canvas.drawLine(
          mitte + Offset(-r * 1.3, r * 0.15), mitte + Offset(-r * 2.5, r * 0.15), wind);
    }

    final weiss = Paint()..color = Colors.white;
    final pupille = Paint()..color = const Color(0xFF22303F);
    canvas.drawCircle(mitte + Offset(-r * 0.33, -r * 0.18), r * 0.19, weiss);
    canvas.drawCircle(mitte + Offset(r * 0.33, -r * 0.18), r * 0.19, weiss);
    canvas.drawCircle(mitte + Offset(-r * 0.28, -r * 0.18), r * 0.09, pupille);
    canvas.drawCircle(mitte + Offset(r * 0.38, -r * 0.18), r * 0.09, pupille);

    final mund = Paint()
      ..color = const Color(0xFF22303F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.13
      ..strokeCap = StrokeCap.round;
    if (investiert) {
      canvas.drawArc(
        Rect.fromCenter(
            center: mitte + Offset(0, r * 0.32), width: r * 0.72, height: r * 0.55),
        0.15,
        math.pi - 0.3,
        false,
        mund,
      );
    } else {
      canvas.drawLine(
          mitte + Offset(-r * 0.27, r * 0.36), mitte + Offset(r * 0.27, r * 0.36), mund);
    }

    if (stolperWinkel != 0) canvas.restore();
  }

  void _label(Canvas canvas, String text, Offset pos, double groesse) {
    final tp = _text(text, groesse);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - 3, pos.dy - 1, tp.width + 6, tp.height + 2),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant RennstreckePainter old) => false;
}
