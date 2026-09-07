import 'dart:math' as math;

import 'kamera.dart';

/// Ein Meilenstein-Schild an einem festen Euro-Wert.
class Schild {
  /// Euro-Wert – bestimmt Beschriftung **und** Position. Ändert sich nie.
  final double wert;

  /// 0..1, für weiches Ein- und Ausblenden.
  double sichtbarkeit;

  /// Wird ausgeblendet und danach entfernt (Ausdünnen). Endgültig.
  bool verschwindet = false;

  Schild(this.wert, {this.sichtbarkeit = 0});
}

/// Ein Element einer Parallax-Ebene (Baum oder Wolke).
///
/// Bildschirm-verankert: Die Position ist ein Pixelwert, der pro Frame nach
/// links wandert. Größe und Form werden **beim Spawn** festgelegt und ändern
/// sich nie – dadurch ist die Ebene immun gegen Zoom- und
/// Schrittweiten-Änderungen.
class Kulissenteil {
  double x;
  final double groesse;

  /// Zufallszahl 0..1 für Formvariationen (Kronenversatz, Wolkenhöhe …).
  final double variante;

  Kulissenteil(this.x, this.groesse, this.variante);
}

/// Verwaltet Schilder, Bäume und Wolken nach einer festen Regel:
///
/// **Nichts erscheint oder verschwindet mitten im Bild.**
///
/// Elemente betreten die Bühne ausschließlich am rechten Rand, behalten dabei
/// ihre beim Eintritt festgelegten Eigenschaften und verlassen sie links.
/// Einzige Ausnahme: Rücken Schilder beim Herauszoomen so dicht zusammen, dass
/// sie einander überdecken würden, wird jedes zweite ausgeblendet – und bleibt
/// dann weg, auch wenn später wieder Platz entstünde.
///
/// Reines Dart – kein Flutter, damit unit-testbar.
class Weltkulisse {
  /// Zielabstand neu einlaufender Schilder, als Anteil der Bildbreite.
  static const double zielSchildAbstand = 0.30;

  /// Darunter würden sich Schilder überdecken -> ausdünnen.
  ///
  /// Muss kleiner sein als der kleinstmögliche Spawn-Abstand
  /// ([zielSchildAbstand] halbiert, weil abgerundet wird), sonst würde ein
  /// frisch eingelaufenes Schild sofort wieder ausgedünnt.
  static const double minSchildAbstand = 0.13;

  /// So viele Schilder müssen mindestens im Bild sein. Unterschreitet die
  /// Bühne diese Zahl, darf ausnahmsweise auch innerhalb des Bildes
  /// nachgefüllt werden (weich eingeblendet).
  static const int mindestensSichtbar = 3;

  /// Ein-/Ausblenddauer in Sekunden.
  static const double blendSekunden = 0.35;

  /// Parallax-Anteile der Ebenen.
  static const double anteilBaeume = 0.45;
  static const double anteilWolken = 0.15;

  static const double baumAbstand = 0.16;
  static const double wolkenAbstand = 0.55;

  final List<Schild> schilder = [];
  final List<Kulissenteil> baeume = [];
  final List<Kulissenteil> wolken = [];

  /// Bereits ausgedünnte Euro-Werte. Sie werden nie wieder erzeugt – „einmal
  /// weg, bleibt weg". Wird regelmäßig auf die Umgebung des Fensters gestutzt,
  /// damit die Menge über eine lange Runde nicht unbegrenzt wächst.
  final Set<double> _ausgeduennt = {};

  final math.Random _zufall;

  /// Rand außerhalb des Bildes, in dem Elemente entstehen bzw. entfernt werden.
  static const double _rand = 0.12;

  /// Zählt, wie oft die Bühne notbefüllt werden musste, weil weniger als
  /// [mindestensSichtbar] Schilder im Bild waren. In diesen Frames gilt die
  /// Regel „nichts erscheint mitten im Bild" ausnahmsweise nicht.
  int notbefuellungen = 0;

  /// Aufsummierter Pixelversatz der vordersten Ebene (Parallax 1.0).
  ///
  /// Das Gras wird aus Kostengründen gekachelt statt als Entitäten geführt –
  /// es sind zu viele Halme. Weil der Versatz hier **inkrementell** aufaddiert
  /// wird (und nicht aus `schritt × pxProEuro` abgeleitet), springt die Textur
  /// bei Zoom- oder Schrittweitenwechsel trotzdem nicht.
  double grasVersatz = 0;

  double _breitePx = 0;

  Weltkulisse({math.Random? zufall}) : _zufall = zufall ?? math.Random();

  /// Muss vor der ersten Aktualisierung bekannt sein (kommt aus dem Painter).
  void setzeBreite(double breitePx) => _breitePx = breitePx;

  void aktualisiere(Kamera kamera, double dt, {double eigenDriftPx = 0}) {
    if (_breitePx <= 0) return;

    final fenster = (kamera.bis - kamera.von).abs();
    if (fenster < 1e-9) return;
    final pxProEuro = _breitePx / fenster;

    // Wie weit die Welt seit dem letzten Frame nach links gezogen ist.
    final versatzPx = kamera.letzterVersatz * pxProEuro;
    grasVersatz -= versatzPx;

    _aktualisiereSchilder(kamera, pxProEuro, dt);
    _aktualisiereEbene(baeume, versatzPx * anteilBaeume, baumAbstand, dt,
        minGroesse: 0.55, maxGroesse: 1.0);
    _aktualisiereEbene(wolken, versatzPx * anteilWolken + eigenDriftPx,
        wolkenAbstand, dt,
        minGroesse: 0.6, maxGroesse: 1.0);
  }

  // -----------------------------------------------------------------
  //  Schilder – welt-verankert in Euro
  // -----------------------------------------------------------------

  void _aktualisiereSchilder(Kamera kamera, double pxProEuro, double dt) {
    final randEuro = _rand * _breitePx / pxProEuro;

    // 1) Links hinausgelaufene entfernen.
    schilder.removeWhere((s) => s.wert < kamera.von - randEuro);

    // 2) Ausgeblendete entfernen.
    schilder.removeWhere((s) => s.verschwindet && s.sichtbarkeit <= 0.001);

    // 3) Von außen nachschieben. Der Abstand wird **jetzt** bestimmt und gilt
    //    für dieses Schild dauerhaft.
    final linkeKante = kamera.von - randEuro;
    final rechteKante = kamera.bis + randEuro;
    final abstand = _spawnAbstand(pxProEuro);

    // „Nichts erscheint mitten im Bild" gilt nur, solange genug Schilder da
    // sind. Sonst würde die Bühne verhungern: Nach dem Ausdünnen liegt das
    // äußerste Schild tief im Bild, und die Wache blockierte jeden Nachschub –
    // besonders bei fallenden Kursen, wo von rechts nichts nachkommt.
    // In dem Fall wird nachgefüllt; die Schilder blenden sich weich ein.
    final imFenster = schilder
        .where((s) => !s.verschwindet && s.wert >= kamera.von && s.wert <= kamera.bis)
        .length;
    final zuWenige = imFenster < mindestensSichtbar;
    final neuAufbau =
        schilder.isEmpty || schilder.last.wert < kamera.von || zuWenige;
    if (zuWenige && schilder.isNotEmpty) notbefuellungen++;

    if (schilder.isEmpty) {
      final start = (kamera.von / abstand).floor() * abstand;
      schilder.add(Schild(start, sichtbarkeit: 1));
    }

    // Nach außen auffüllen, **bis** das äußerste Schild jenseits des Randes
    // liegt – sonst bleibt am Bildrand eine Lücke stehen.
    var letzter = schilder.last.wert;
    var schutz = 0;
    while (letzter < rechteKante && schutz++ < 64) {
      // Auf ein Vielfaches des aktuellen Abstands runden, damit die
      // Beschriftungen runde Zahlen bleiben.
      var naechster = ((letzter + abstand) / abstand).round() * abstand;
      if (naechster <= letzter) naechster = letzter + abstand;
      // Würde es mitten im Bild erscheinen (z. B. weil sich die Schrittweite
      // gerade geändert hat), lieber gar nicht erzeugen.
      if (!neuAufbau && naechster < kamera.bis) break;
      letzter = naechster;
      // Merkliste bleibt erhalten; nur im Notfall darf darüber hinweggegangen
      // werden, sonst bliebe die Bühne leer.
      if (!neuAufbau && _ausgeduennt.contains(naechster)) continue;
      schilder.add(Schild(naechster));
    }

    // Fallende Kurse lassen die Kamera rückwärts schwenken – dann taucht links
    // echtes Neuland auf, das gefüllt werden muss. Läuft die Kamera dagegen
    // vorwärts, ist die Lücke am linken Rand einfach der normale
    // Schilderabstand – dort darf nichts nachwachsen.
    var erster = schilder.first.wert;
    schutz = 0;
    while (erster > linkeKante && schutz++ < 64) {
      var vorheriger = ((erster - abstand) / abstand).round() * abstand;
      if (vorheriger >= erster) vorheriger = erster - abstand;
      if (!neuAufbau && vorheriger > kamera.von) break; // läge im Bild
      erster = vorheriger;
      if (!neuAufbau && _ausgeduennt.contains(vorheriger)) continue;
      schilder.insert(0, Schild(vorheriger));
    }

    // 4) Ausdünnen, wenn zwei Nachbarn zu dicht beieinanderstehen.
    _duenneAus(pxProEuro, kamera.von, kamera.bis);

    // 5) Ein-/Ausblenden.
    final schrittBlend = dt / blendSekunden;
    for (final s in schilder) {
      final ziel = s.verschwindet ? 0.0 : 1.0;
      if (s.sichtbarkeit < ziel) {
        s.sichtbarkeit = math.min(ziel, s.sichtbarkeit + schrittBlend);
      } else if (s.sichtbarkeit > ziel) {
        s.sichtbarkeit = math.max(ziel, s.sichtbarkeit - schrittBlend);
      }
    }
  }

  /// Aktuell gültige Schrittweite. Wird nur neu bestimmt, wenn sie wirklich
  /// unbrauchbar geworden ist – siehe [_spawnAbstand].
  double _aktuellerAbstand = 0;

  /// Bestimmt den Euro-Abstand neu einlaufender Schilder.
  ///
  /// Mit **Hysterese**: Ohne sie würde sich die Schrittweite bei jeder
  /// Zoom-Regung ändern, und weil jedes Schild auf dem Raster seiner
  /// Entstehungszeit sitzt, stünden am Ende krumme Reihen wie
  /// 2.400 / 3.250 / 4.000 im Bild. So bleibt eine Schrittweite über einen
  /// weiten Zoom-Bereich gültig und die Abstände wirken regelmäßig.
  double _spawnAbstand(double pxProEuro) {
    final px = _aktuellerAbstand * pxProEuro;
    final zuEng = px < _breitePx * 0.14;
    final zuWeit = px > _breitePx * 0.33; // sonst passen keine drei mehr
    if (_aktuellerAbstand <= 0 || zuEng || zuWeit) {
      final zielEuro = zielSchildAbstand * _breitePx / pxProEuro;
      // Bewusst **abrunden**: Aufrunden könnte den Abstand fast verdoppeln und
      // damit weniger als drei Schilder im Bild lassen.
      _aktuellerAbstand = Kamera.huebscherSchrittAbwaerts(zielEuro);
    }
    return _aktuellerAbstand;
  }

  /// Entfernt jedes zweite Schild, sobald der Pixelabstand zu klein wird.
  /// Endgültig – ausgedünnte Schilder kehren nicht zurück.
  void _duenneAus(double pxProEuro, double von, double bis) {
    final minEuro = minSchildAbstand * _breitePx / pxProEuro;
    final aktiv = schilder.where((s) => !s.verschwindet).toList();
    for (var i = 0; i + 1 < aktiv.length; i++) {
      final a = aktiv[i], b = aktiv[i + 1];
      if (b.wert - a.wert < minEuro) {
        b.verschwindet = true;
        _ausgeduennt.add(b.wert);
        i++; // den übernächsten stehen lassen
      }
    }

    // Merkliste beschränken: weit entfernte Werte können ohnehin nicht
    // zurückkehren.
    if (_ausgeduennt.length > 400) {
      final fenster = bis - von;
      _ausgeduennt.removeWhere(
          (w) => w < von - fenster * 3 || w > bis + fenster * 3);
    }
  }

  // -----------------------------------------------------------------
  //  Bäume und Wolken – bildschirm-verankert
  // -----------------------------------------------------------------

  void _aktualisiereEbene(List<Kulissenteil> teile, double versatzPx,
      double abstandAnteil, double dt,
      {required double minGroesse, required double maxGroesse}) {
    // Bewegen.
    for (final t in teile) {
      t.x -= versatzPx;
    }

    final randPx = _rand * _breitePx;
    teile.removeWhere((t) => t.x < -randPx);

    final abstandPx = abstandAnteil * _breitePx;
    if (abstandPx < 8) return;

    Kulissenteil neu(double x) => Kulissenteil(
          x,
          minGroesse + _zufall.nextDouble() * (maxGroesse - minGroesse),
          _zufall.nextDouble(),
        );

    // Rechts auffüllen. Größe und Variante werden hier einmalig gewürfelt und
    // ändern sich danach nie wieder.
    var rechtester =
        teile.isEmpty ? -randPx : teile.map((t) => t.x).reduce(math.max);
    var schutz = 0;
    while (rechtester < _breitePx + randPx && schutz++ < 64) {
      final jitter = (_zufall.nextDouble() - 0.5) * abstandPx * 0.45;
      final x = rechtester + abstandPx + jitter;
      teile.add(neu(x));
      rechtester = x;
    }

    // Links auffüllen – nötig, wenn die Kamera bei fallenden Kursen
    // rückwärts schwenkt und die Kulisse nach rechts zieht.
    var linkester = teile.map((t) => t.x).reduce(math.min);
    schutz = 0;
    while (linkester > -randPx && schutz++ < 64) {
      final jitter = (_zufall.nextDouble() - 0.5) * abstandPx * 0.45;
      final x = linkester - abstandPx + jitter;
      teile.add(neu(x));
      linkester = x;
    }
  }
}
