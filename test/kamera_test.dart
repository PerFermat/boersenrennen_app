import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/spiel/kamera.dart';

/// Wie viele Meilensteine im aktuellen Fenster sichtbar wären.
int sichtbareSchilder(Kamera k) {
  var wert = (k.von / k.schritt).ceil() * k.schritt;
  var n = 0;
  while (wert <= k.bis) {
    n++;
    wert += k.schritt;
  }
  return n;
}

void main() {
  group('huebscherSchritt', () {
    test('rundet auf 1/2/2.5/5 mal Zehnerpotenz auf', () {
      expect(Kamera.huebscherSchritt(1), 1);
      expect(Kamera.huebscherSchritt(70), 100);
      expect(Kamera.huebscherSchritt(45), 50);
      expect(Kamera.huebscherSchritt(21), 25);
      expect(Kamera.huebscherSchritt(120), 200);
      expect(Kamera.huebscherSchritt(5500), 10000);
    });

    test('bleibt bei unsinnigen Eingaben brauchbar', () {
      expect(Kamera.huebscherSchritt(0), 1);
      expect(Kamera.huebscherSchritt(-5), 1);
      expect(Kamera.huebscherSchritt(double.nan), 1);
    });
  });

  group('Kamera', () {
    test('zeigt auch beim Start mindestens 3 Meilensteine', () {
      final k = Kamera()..aktualisiere([1000, 1000, 1000], 0.016);
      expect(sichtbareSchilder(k), greaterThanOrEqualTo(3));
    });

    test('zeigt über die ganze Runde hinweg immer mindestens 3 Meilensteine', () {
      // Von 1000 € bis 500.000 €, mit wachsendem Abstand zwischen den Läufern.
      for (var basis = 1000.0; basis < 500000; basis *= 1.35) {
        for (final spreizung in [0.0, 0.03, 0.2, 0.8]) {
          final k = Kamera()
            ..aktualisiere([basis, basis * (1 + spreizung), basis * (1 + spreizung / 2)], 1.0);
          final n = sichtbareSchilder(k);
          expect(n, greaterThanOrEqualTo(3),
              reason: 'basis=$basis spreizung=$spreizung -> nur $n Schilder');
          expect(n, lessThanOrEqualTo(8),
              reason: 'basis=$basis spreizung=$spreizung -> zu viele ($n) Schilder');
        }
      }
    });

    test('alle Läufer liegen im sichtbaren Fenster', () {
      final werte = [4200.0, 5800.0, 3100.0];
      final k = Kamera()..aktualisiere(werte, 1.0);
      for (final w in werte) {
        final a = k.anteil(w);
        expect(a, greaterThan(0.0));
        expect(a, lessThan(1.0));
      }
    });

    test('größerer Abstand zoomt heraus und verkleinert die Läufer', () {
      final eng = Kamera()..aktualisiere([1000, 1010, 1005], 1.0);
      final weit = Kamera()..aktualisiere([1000, 2000, 1500], 1.0);

      expect(weit.groesseFaktor, lessThan(eng.groesseFaktor));
      expect(eng.groesseFaktor, closeTo(1.0, 0.05));
      expect(weit.bis - weit.von, greaterThan(eng.bis - eng.von));
    });

    test('Größenfaktor bleibt in sinnvollen Grenzen', () {
      final extrem = Kamera()..aktualisiere([100, 100000, 50000], 1.0);
      expect(extrem.groesseFaktor, greaterThanOrEqualTo(0.42));
      expect(extrem.groesseFaktor, lessThanOrEqualTo(1.0));
    });

    test('zieht gedämpft nach statt zu springen', () {
      final k = Kamera()..aktualisiere([1000, 1000, 1000], 1.0);
      final vorher = k.von;
      // Sprunghafte Wertänderung
      k.aktualisiere([5000, 5000, 5000], 0.016);
      expect(k.von, greaterThan(vorher));
      // nach einem einzelnen Frame darf die Kamera noch nicht am Ziel sein
      expect(k.von, lessThan(4000));
    });
  });

  group('Zoom-Übergang', () {
    /// Simuliert [sekunden] mit 60 fps auf konstante Zielwerte.
    Kamera laufeAn(Kamera k, List<double> ziel, double sekunden) {
      const dt = 1 / 60;
      for (var t = 0.0; t < sekunden; t += dt) {
        k.aktualisiere(ziel, dt);
      }
      return k;
    }

    test('ist nach der Übergangsdauer praktisch abgeschlossen', () {
      // Start eng beieinander, dann weit auseinander -> starkes Herauszoomen.
      final k = Kamera()..aktualisiere([1000, 1000, 1000], 1 / 60);
      final startBreite = k.bis - k.von;

      laufeAn(k, [1000, 3000, 2000], Kamera.standardZoomSekunden);

      // Zielzustand zum Vergleich (ohne Übergang, direkt initialisiert).
      final ziel = Kamera()..aktualisiere([1000, 3000, 2000], 1.0);

      final erreicht = (k.bis - k.von - startBreite) /
          (ziel.bis - ziel.von - startBreite);
      expect(erreicht, greaterThan(0.95),
          reason: 'nach 2 s sollte der Zoom fast vollständig sein');
      expect(k.groesseFaktor, closeTo(ziel.groesseFaktor, 0.02));
    });

    test('ist nach einem Bruchteil der Zeit deutlich unfertig', () {
      final k = Kamera()..aktualisiere([1000, 1000, 1000], 1 / 60);
      final startGroesse = k.groesseFaktor;

      laufeAn(k, [1000, 3000, 2000], Kamera.standardZoomSekunden * 0.15);

      final ziel = Kamera()..aktualisiere([1000, 3000, 2000], 1.0);
      final erreicht =
          (startGroesse - k.groesseFaktor) / (startGroesse - ziel.groesseFaktor);
      expect(erreicht, lessThan(0.5),
          reason: 'nach 15 % der Zeit darf der Zoom noch nicht halb fertig sein');
    });

    test('kürzere Übergangsdauer zoomt schneller', () {
      final schnell = Kamera(zoomSekunden: 0.5);
      final langsam = Kamera(zoomSekunden: 4.0);
      schnell.aktualisiere([1000, 1000, 1000], 1 / 60);
      langsam.aktualisiere([1000, 1000, 1000], 1 / 60);

      laufeAn(schnell, [1000, 3000, 2000], 0.5);
      laufeAn(langsam, [1000, 3000, 2000], 0.5);

      expect(schnell.bis - schnell.von, greaterThan(langsam.bis - langsam.von));
    });

    test('Schwenk folgt deutlich schneller als der Zoom', () {
      // Gleichtakt: alle drei verdoppeln sich, der Abstand bleibt gleich.
      // Die Bildmitte muss schnell nachziehen, die Breite nur langsam.
      final k = Kamera()..aktualisiere([1000, 1200, 1100], 1 / 60);
      final startBreite = k.bis - k.von;
      final startMitte = (k.von + k.bis) / 2;

      // Nach einem Bruchteil der Zoomdauer prüfen.
      laufeAn(k, [2000, 2400, 2200], Kamera.standardSchwenkSekunden * 2);

      final zielMitte = 2200.0;
      final mitteJetzt = (k.von + k.bis) / 2;
      final schwenkFortschritt =
          (mitteJetzt - startMitte) / (zielMitte - startMitte);
      final zoomFortschritt =
          ((k.bis - k.von) - startBreite) / (startBreite * 2 - startBreite);

      expect(schwenkFortschritt, greaterThan(0.85),
          reason: 'der Schwenk muss der Marktbewegung folgen können');
      expect(zoomFortschritt, lessThan(schwenkFortschritt),
          reason: 'der Zoom bleibt bewusst träger als der Schwenk');
    });

    test('kein Läufer fällt während des Übergangs aus dem Bild', () {
      final k = Kamera()..aktualisiere([1000, 1000, 1000], 1 / 60);
      const dt = 1 / 60;
      // Harter Sprung, wie er bei sehr schnellem Vorlauf entstehen kann.
      for (var t = 0.0; t < 2.0; t += dt) {
        final werte = [1000.0, 9000.0, 4000.0];
        k.aktualisiere(werte, dt);
        for (final w in werte) {
          final a = k.anteil(w);
          expect(a, inInclusiveRange(0.0, 1.0),
              reason: 'Wert $w liegt bei t=$t außerhalb des Fensters');
        }
      }
    });
  });
}
