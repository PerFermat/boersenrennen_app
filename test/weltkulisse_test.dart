import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/spiel/kamera.dart';
import 'package:boersenrennen_app/spiel/weltkulisse.dart';

const breitePx = 1080.0;

/// Bildschirmposition eines Schildes.
double schildX(Kamera k, double wert) =>
    (wert - k.von) / (k.bis - k.von) * breitePx;

/// Wie viele Schilder gerade wirklich im Bild stehen.
int imFenster(Kamera k, Weltkulisse w) => w.schilder
    .where((s) => !s.verschwindet && s.wert >= k.von && s.wert <= k.bis)
    .length;

/// Fährt eine Runde: Der Abstand zwischen Erstem und Letztem wächst und
/// schrumpft wieder, während die Depots insgesamt steigen.
/// [beiFrame] wird nach jedem Schritt aufgerufen.
void spiele(
  Kamera kamera,
  Weltkulisse kulisse, {
  required double sekunden,
  required List<double> Function(double t) werte,
  void Function(double t) beiFrame = _nichts,
}) {
  const dt = 1 / 60;
  kulisse.setzeBreite(breitePx);
  for (var t = 0.0; t < sekunden; t += dt) {
    kamera.aktualisiere(werte(t), dt);
    kulisse.aktualisiere(kamera, dt);
    beiFrame(t);
  }
}

void _nichts(double t) {}

/// Depots wachsen, der Abstand geht 0 % -> 60 % -> 0 %.
List<double> wachsendMitAtmung(double t) {
  final basis = 1000 * math.pow(1.6, t).toDouble();
  final spreizung = 0.6 * (0.5 - 0.5 * math.cos(t * 1.2));
  return [basis, basis * (1 + spreizung), basis * (1 + spreizung * 0.5)];
}

void main() {
  group('Schilder – Spawn nur von rechts', () {
    test('kein Schild taucht mitten im Bild auf, solange genug da sind', () {
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(1));
      final bekannt = <double>{};
      final verstoesse = <String>[];
      var anzahlVorFrame = 99;

      spiele(
        kamera,
        kulisse,
        sekunden: 12,
        werte: wachsendMitAtmung,
        beiFrame: (t) {
          for (final s in kulisse.schilder) {
            if (!bekannt.add(s.wert)) continue;
            // Die Erstbefüllung der Bühne ist naturgemäß über das ganze Bild
            // verteilt – erst danach gilt die Regel.
            if (t < 0.05) continue;
            // Ausnahme: Waren zu wenige Schilder im Bild, darf nachgefüllt
            // werden (sie blenden sich weich ein).
            if (anzahlVorFrame < Weltkulisse.mindestensSichtbar) continue;
            // Sonst muss Neues **außerhalb** des Bildes starten:
            // rechts beim Steigen, links beim Fallen.
            final x = schildX(kamera, s.wert);
            if (x > breitePx * 0.02 && x < breitePx * 0.98) {
              verstoesse.add('t=${t.toStringAsFixed(2)} '
                  'Wert=${s.wert.toStringAsFixed(0)} x=${x.toStringAsFixed(0)}');
            }
          }
          anzahlVorFrame = imFenster(kamera, kulisse);
        },
      );

      expect(verstoesse, isEmpty,
          reason: 'Schilder dürfen nur von außen einlaufen:\n'
              '${verstoesse.take(5).join('\n')}');
    });

    test('Schilder überdecken sich nie', () {
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(2));
      var schlimmster = double.infinity;

      spiele(
        kamera,
        kulisse,
        sekunden: 12,
        werte: wachsendMitAtmung,
        beiFrame: (_) {
          final sichtbar = kulisse.schilder
              .where((s) => !s.verschwindet && s.sichtbarkeit > 0.5)
              .map((s) => schildX(kamera, s.wert))
              .where((x) => x > 0 && x < breitePx)
              .toList()
            ..sort();
          for (var i = 0; i + 1 < sichtbar.length; i++) {
            final d = sichtbar[i + 1] - sichtbar[i];
            if (d < schlimmster) schlimmster = d;
          }
        },
      );

      // Zugesichert ist der Ausdünn-Schwellwert; die Plaketten sind schmaler.
      expect(schlimmster,
          greaterThan(breitePx * Weltkulisse.minSchildAbstand * 0.95),
          reason: 'engster Abstand war ${schlimmster.toStringAsFixed(0)} px');
    });

    test('ausgedünntes Schild kehrt nicht zurück, solange genug da sind', () {
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(3));
      final entfernteWerte = <double>{};
      final bekannt = <Schild>{};
      final rueckkehrer = <double>[];
      var notbefuellungenVorher = 0;

      spiele(
        kamera,
        kulisse,
        sekunden: 12,
        werte: wachsendMitAtmung,
        beiFrame: (_) {
          final notfall = kulisse.notbefuellungen != notbefuellungenVorher;
          notbefuellungenVorher = kulisse.notbefuellungen;

          for (final s in kulisse.schilder) {
            // Jedes Schild nur **einmal**, nämlich bei seiner Entstehung,
            // bewerten – sonst zählt dasselbe Objekt in jedem Frame erneut.
            if (!bekannt.add(s)) continue;
            // Ausnahme: In einem Frame mit Notbefüllung darf nachgelegt werden.
            if (notfall) continue;
            if (!s.verschwindet && entfernteWerte.contains(s.wert)) {
              rueckkehrer.add(s.wert);
            }
          }

          for (final s in kulisse.schilder) {
            if (s.verschwindet) entfernteWerte.add(s.wert);
          }
          bekannt.removeWhere((s) => !kulisse.schilder.contains(s));
        },
      );

      expect(rueckkehrer, isEmpty,
          reason: 'einmal ausgedünnte Schilder bleiben weg');
    });

    test('bei wachsendem Abstand kommt Nachschub von rechts', () {
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(4));
      kulisse.setzeBreite(breitePx);

      // Enge Aufstellung
      const dt = 1 / 60;
      for (var t = 0.0; t < 3; t += dt) {
        kamera.aktualisiere([1000, 1020, 1010], dt);
        kulisse.aktualisiere(kamera, dt);
      }
      final hoechsterVorher =
          kulisse.schilder.map((s) => s.wert).reduce(math.max);

      // Weit auseinander -> Fenster wird breiter -> rechts kommt Neues herein
      for (var t = 0.0; t < 6; t += dt) {
        kamera.aktualisiere([1000, 2600, 1800], dt);
        kulisse.aktualisiere(kamera, dt);
      }
      final hoechsterNachher =
          kulisse.schilder.map((s) => s.wert).reduce(math.max);

      // Die Gesamtzahl darf durchs Ausdünnen sinken – entscheidend ist, dass
      // rechts neue, höhere Meilensteine eingelaufen sind.
      expect(hoechsterNachher, greaterThan(hoechsterVorher));
      expect(kulisse.schilder.where((s) => !s.verschwindet).length,
          greaterThanOrEqualTo(3));
    });

    test('es sind immer mindestens 3 Schilder unterwegs', () {
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(5));
      var minimum = 999;

      spiele(
        kamera,
        kulisse,
        sekunden: 12,
        werte: wachsendMitAtmung,
        beiFrame: (t) {
          if (t < 0.5) return; // Einschwingen
          final n = kulisse.schilder.where((s) => !s.verschwindet).length;
          if (n < minimum) minimum = n;
        },
      );

      expect(minimum, greaterThanOrEqualTo(3));
    });
  });

  group('Bäume und Wolken', () {
    test('behalten Größe und Form von Spawn bis Despawn', () {
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(6));
      final gesehen = <Kulissenteil, double>{};
      final aenderungen = <String>[];

      spiele(
        kamera,
        kulisse,
        sekunden: 10,
        werte: wachsendMitAtmung,
        beiFrame: (_) {
          for (final b in kulisse.baeume) {
            final alt = gesehen[b];
            if (alt == null) {
              gesehen[b] = b.groesse;
            } else if (alt != b.groesse) {
              aenderungen.add('Baum änderte Größe: $alt -> ${b.groesse}');
            }
          }
        },
      );

      expect(aenderungen, isEmpty);
      expect(gesehen, isNotEmpty, reason: 'es sollten Bäume entstanden sein');
    });

    test('Bäume erscheinen nur außerhalb des Bildes', () {
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(7));
      final bekannt = <Kulissenteil>{};
      final verstoesse = <String>[];

      spiele(
        kamera,
        kulisse,
        sekunden: 10,
        werte: wachsendMitAtmung,
        beiFrame: (t) {
          for (final b in kulisse.baeume) {
            if (!bekannt.add(b)) continue;
            if (t < 0.05) continue; // Erstbefüllung der Bühne
            if (b.x > 0 && b.x < breitePx) {
              verstoesse.add('t=${t.toStringAsFixed(2)} '
                  'Baum erschien bei x=${b.x.toStringAsFixed(0)}');
            }
          }
          bekannt.removeWhere((b) => !kulisse.baeume.contains(b));
        },
      );

      expect(verstoesse, isEmpty, reason: verstoesse.take(3).join('\n'));
    });

    test('auch bei fallenden Kursen bleibt die Kulisse lückenlos', () {
      // Crash-Szenario: Die Depots halbieren sich, die Kamera schwenkt
      // rückwärts, die Kulisse zieht nach rechts -> links darf keine Lücke
      // entstehen.
      final kamera = Kamera();
      final kulisse = Weltkulisse(zufall: math.Random(8));
      var luecken = 0;

      spiele(
        kamera,
        kulisse,
        sekunden: 8,
        werte: (t) {
          final f = math.max(0.35, 1 - t * 0.09);
          return [5000 * f, 6000 * f, 5500 * f];
        },
        beiFrame: (t) {
          if (t < 0.5) return;
          // Nur die dichte Kulisse prüfen: Bei den Schildern ist eine Lücke
          // am Rand einfach der normale Meilensteinabstand.
          final linkester = kulisse.baeume.map((b) => b.x).reduce(math.min);
          if (linkester > 0) luecken++;
        },
      );

      expect(luecken, 0, reason: 'links klaffte $luecken mal eine Lücke');
    });
  });

  group('Gleichtakt – der Kern des Sprung-Fixes', () {
    test('steigen alle Depots gleich stark, stehen die Läufer nahezu still', () {
      final kamera = Kamera();
      const dt = 1 / 60;

      // Einschwingen
      for (var t = 0.0; t < 3; t += dt) {
        kamera.aktualisiere([1000, 1200, 1100], dt);
      }

      double xVon(double wert) => (wert - kamera.von) / (kamera.bis - kamera.von);
      final vorher = [xVon(1000), xVon(1200), xVon(1100)];

      // Alle drei +20 % (reine Gleichtaktbewegung), langsam eingeblendet.
      for (var t = 0.0; t < 3; t += dt) {
        final f = 1 + 0.2 * (t / 3);
        kamera.aktualisiere([1000 * f, 1200 * f, 1100 * f], dt);
      }
      final f = 1.2;
      final nachher = [xVon(1000 * f), xVon(1200 * f), xVon(1100 * f)];

      for (var i = 0; i < 3; i++) {
        expect((nachher[i] - vorher[i]).abs(), lessThan(0.06),
            reason: 'Läufer $i wanderte um ${(nachher[i] - vorher[i]).abs()}');
      }
    });
  });
}
