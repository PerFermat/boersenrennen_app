import 'dart:math' as math;

/// Das sichtbare Fenster der Rennstrecke – gemessen in **Euro**, nicht in Pixeln.
///
/// Die Läufer stehen an ihrem Depotwert; die Welt scrollt an ihnen vorbei.
///
/// **Schwenk und Zoom sind bewusst entkoppelt:**
/// * Die *Bildmitte* folgt schnell ([schwenkSekunden]). Steigt der Kurs, wandern
///   alle drei Depots gemeinsam nach rechts – schwenkt die Kamera flott mit,
///   bleiben die Läufer im Bild stehen und nur die Welt zieht vorbei. Genau das
///   verhindert das Hin- und Herspringen.
/// * Die *Fensterbreite* ändert sich träge ([zoomSekunden]), damit das Ein- und
///   Auszoomen ruhig wirkt.
///
/// Reines Dart – kein Flutter, damit unit-testbar.
class Kamera {
  /// Untere/obere Kante des sichtbaren Euro-Fensters.
  double von = 0;
  double bis = 1;

  /// Abstand zweier Meilensteine in Euro (immer ein „runder" Wert).
  /// Dient nur noch als *Vorschlag* für neu einlaufende Schilder.
  double schritt = 100;

  /// Skalierung von Läufern und Bahnhöhe: 1.0 wenn alle gleichauf,
  /// kleiner bei großem Abstand.
  double groesseFaktor = 1;

  /// Wie weit die Bildmitte seit dem letzten Frame gewandert ist – in Euro.
  /// Die Kulisse rechnet das in Pixel um und scrollt ihre Ebenen damit.
  double letzterVersatz = 0;

  double _mitte = 0;
  double _breite = 1;
  bool _initialisiert = false;

  /// So viele Meilensteine müssen mindestens ins Bild passen.
  static const double minSchilder = 3.2;

  /// Angestrebte Anzahl Meilensteine – bestimmt die Schrittweite.
  static const double zielSchilder = 4.5;

  /// **Dauer eines Zoom-Übergangs in Sekunden.**
  ///
  /// Nach dieser Zeit ist ein Wechsel der Fensterbreite zu praktisch 98 %
  /// vollzogen. Hier anpassen, um das Ein- und Auszoomen träger oder flotter
  /// zu machen.
  static const double standardZoomSekunden = 2.0;

  /// **Dauer eines Schwenks in Sekunden.**
  ///
  /// Deutlich kürzer als der Zoom: Der Schwenk muss der gemeinsamen
  /// Marktbewegung folgen können, sonst rutscht das ganze Feld über den Schirm.
  static const double standardSchwenkSekunden = 0.25;

  /// Rest, der nach der jeweiligen Dauer noch fehlen darf (2 %).
  static const double _restAnteil = 0.02;

  final double zoomSekunden;
  final double schwenkSekunden;

  Kamera({
    this.zoomSekunden = standardZoomSekunden,
    this.schwenkSekunden = standardSchwenkSekunden,
  });

  double get _zoomRate => -math.log(_restAnteil) / zoomSekunden;
  double get _schwenkRate => -math.log(_restAnteil) / schwenkSekunden;

  void aktualisiere(List<double> werte, double dt) {
    final minWert = werte.reduce(math.min);
    final maxWert = werte.reduce(math.max);
    final spanne = maxWert - minWert;

    // Fenster so breit, dass alle Läufer mit Rand hineinpassen. Der Anteil am
    // Depotwert sorgt dafür, dass es mitwächst, wenn die Depots größer werden.
    var zielBreite = math.max(spanne * 1.9, maxWert.abs() * 0.22);
    if (zielBreite <= 0) zielBreite = 100;

    final s = huebscherSchritt(zielBreite / zielSchilder);
    if (zielBreite < s * minSchilder) zielBreite = s * minSchilder;

    final zielMitte = (minWert + maxWert) / 2;
    final relativeSpanne = maxWert > 0 ? spanne / maxWert : 0.0;
    final zielGroesse = (1 / (1 + relativeSpanne * 4)).clamp(0.42, 1.0);

    final vorherigeMitte = _mitte;

    if (!_initialisiert) {
      _mitte = zielMitte;
      _breite = zielBreite;
      groesseFaktor = zielGroesse;
      _initialisiert = true;
    } else {
      // Schwenk schnell, Zoom träge – die Trennung ist der Kern des Fixes.
      final fSchwenk = 1 - math.exp(-dt * _schwenkRate);
      final fZoom = 1 - math.exp(-dt * _zoomRate);
      _mitte += (zielMitte - _mitte) * fSchwenk;
      _breite += (zielBreite - _breite) * fZoom;
      // Die Größe gehört zum Zoom und nutzt deshalb dessen Rate.
      groesseFaktor += (zielGroesse - groesseFaktor) * fZoom;
    }

    von = _mitte - _breite / 2;
    bis = _mitte + _breite / 2;
    schritt = s;

    // Notbremse für Extremfälle. Weil die Kamera aus den bereits geglätteten
    // Anzeigewerten gespeist wird und schnell schwenkt, greift sie im
    // Normalbetrieb nicht mehr.
    final rand = _breite * 0.06;
    if (minWert - rand < von) von = minWert - rand;
    if (maxWert + rand > bis) bis = maxWert + rand;

    letzterVersatz = _initialisiert ? _mitte - vorherigeMitte : 0;
  }

  /// Position eines Euro-Werts im Fenster, 0 = linke Kante, 1 = rechte Kante.
  double anteil(double wert) => (wert - von) / (bis - von);

  /// Nächstkleinerer „runder" Wert (1, 2, 2.5, 5 × 10^n) **unterhalb** von [roh].
  ///
  /// Für Schilderabstände: Aufrunden könnte den Abstand fast verdoppeln und
  /// damit weniger als drei Schilder übriglassen.
  static double huebscherSchrittAbwaerts(double roh) {
    if (!roh.isFinite || roh <= 0) return 1;
    final zehner =
        math.pow(10, (math.log(roh) / math.ln10).floor()).toDouble();
    var bester = zehner;
    for (final m in const [1.0, 2.0, 2.5, 5.0]) {
      if (zehner * m <= roh) bester = zehner * m;
    }
    return bester;
  }

  /// Nächstgrößerer „runder" Wert (1, 2, 2.5, 5 × 10^n) oberhalb von [roh].
  static double huebscherSchritt(double roh) {
    if (!roh.isFinite || roh <= 0) return 1;
    final zehner =
        math.pow(10, (math.log(roh) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0]) {
      if (zehner * m >= roh) return zehner * m;
    }
    return zehner * 10;
  }
}
