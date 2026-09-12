import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/domain/auswertung.dart';
import 'package:boersenrennen_app/domain/kursreihe.dart';
import 'package:boersenrennen_app/domain/rennen_engine.dart';
import 'package:boersenrennen_app/domain/spiel_konfiguration.dart';

import 'rennen_engine_test.dart' show baueReihe;

void main() {
  final start = DateTime.utc(2010, 1, 1);

  group('irrBisektion', () {
    test('ohne Vorzeichenwechsel im Kapitalwert liefert null', () {
      final stroeme = [
        (tag: 0, betrag: 100.0),
        (tag: 365, betrag: 50.0),
      ];

      expect(irrBisektion(stroeme), isNull);
    });

    test(
        'Einzahlung 1000 am Tag 0, Rückfluss 1100 nach 365 Tagen ergibt die auf '
        '365,25-Tage-Jahre annualisierte 10 %-Rendite', () {
      final stroeme = [
        (tag: 0, betrag: -1000.0),
        (tag: 365, betrag: 1100.0),
      ];

      // Die Bisektion rechnet mit 365,25-Tage-Jahren; 365 Tage sind also
      // geringfügig weniger als ein volles Jahr, die annualisierte Rendite
      // liegt daher etwas über 10 %.
      final erwartet = math.pow(1.1, 365.25 / 365).toDouble() - 1;
      expect(irrBisektion(stroeme), closeTo(erwartet, 1e-9));
    });

    test('eine Nullstelle exakt bei r=0 wird gefunden', () {
      final stroeme = [
        (tag: 0, betrag: -500.0),
        (tag: 200, betrag: 500.0),
      ];

      expect(irrBisektion(stroeme), closeTo(0.0, 1e-6));
    });
  });

  group('Behavior Gap – volles Engine-Szenario (V10)', () {
    test(
        'Kauf am Tag 0, Halten bis Rundenende ohne weitere Einzahlungen: '
        'geldgewichtete Rendite entspricht der von Hand berechneten CAGR '
        'des Spielerdepots, zeitgewichtete Rendite der CAGR des Titels', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 730,
        kursFuer: (t) => 100.0 * math.pow(2, t),
      );
      final cfg = const SpielKonfiguration(zinssatz: 0.0, monatsEinzahlung: 0.0);
      final e = RennenEngine(reihe, cfg);

      e.kaufen();
      while (!e.fertig) {
        e.schritt();
      }

      final auswertung = RundenAuswertung.aus(e);

      final letzterTag = reihe.epochTag(e.i);
      final jahre = (letzterTag - reihe.ersterTag) / 365.25;
      final erwarteteSpielerCagr =
          math.pow(e.wertSpieler / cfg.startCash, 1 / jahre).toDouble() - 1;
      final erwarteteTitelCagr =
          math.pow(reihe.kurs(e.i) / reihe.kurs(0), 1 / jahre).toDouble() - 1;

      expect(auswertung.geldgewichteteRenditeSpieler, isNotNull);
      expect(auswertung.geldgewichteteRenditeSpieler,
          closeTo(erwarteteSpielerCagr, 1e-6));
      expect(auswertung.zeitgewichteteRenditeTitel, isNotNull);
      expect(auswertung.zeitgewichteteRenditeTitel,
          closeTo(erwarteteTitelCagr, 1e-6));

      final erwarteteBeiMarktrendite =
          cfg.startCash * math.pow(1 + erwarteteTitelCagr, jahre);
      expect(auswertung.behaviorGapEuro,
          closeTo(erwarteteBeiMarktrendite - e.wertSpieler, 1e-6));
      expect(
        auswertung.behaviorGapInMonatsEinzahlungen,
        isNull,
      );
    });

    test(
        'ein Spieler, der nie kauft, liefert für die geldgewichtete Rendite '
        'einen Wert (Cash bleibt Cash, keine Nullstellen-Ausnahme)', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 400,
        kursFuer: (t) => 100.0 * (1 + t),
      );
      final cfg = const SpielKonfiguration(zinssatz: 0.0, monatsEinzahlung: 0.0);
      final e = RennenEngine(reihe, cfg);

      while (!e.fertig) {
        e.schritt();
      }

      final auswertung = RundenAuswertung.aus(e);

      expect(auswertung.geldgewichteteRenditeSpieler, closeTo(0.0, 1e-6));
      expect(auswertung.behaviorGapEuro, isNotNull);
    });

    test(
        'für eine mehrjährige Runde mit Standard-Monatseinzahlung stimmt die '
        'Anzahl der von Hand ermittelten Monatswechsel-Tage mit engine.einzahlungen '
        'überein, und die geldgewichtete Rendite entspricht der IRR über genau '
        'diese von Hand gebaute Zahlungsreihe', () {
      final reihe = baueReihe(
        start: start,
        kalenderTage: 900,
        kursFuer: (t) => 100.0 * (1 + t),
      );
      final cfg = const SpielKonfiguration(zinssatz: 0.0);
      final e = RennenEngine(reihe, cfg);

      while (!e.fertig) {
        e.schritt();
      }

      // Von Hand ermittelte Monatswechsel-Tage – bewusst unabhängig von der
      // privaten _einzahlungsTage()-Implementierung in auswertung.dart neu
      // berechnet, um deren Ergebnis unabhängig zu prüfen.
      final handEinzahlungsTage = <int>[];
      var letzterYM = 0;
      for (var i = 0; i <= e.i; i++) {
        final d = Kursreihe.zuDatum(reihe.epochTag(i));
        final ym = d.year * 12 + d.month;
        if (i == 0) {
          letzterYM = ym;
        } else if (ym != letzterYM) {
          letzterYM = ym;
          handEinzahlungsTage.add(reihe.epochTag(i));
        }
      }

      expect(handEinzahlungsTage.length, e.einzahlungen);

      final handStroeme = [
        (tag: reihe.ersterTag, betrag: -cfg.startCash),
        for (final t in handEinzahlungsTage) (tag: t, betrag: -cfg.monatsEinzahlung),
        (tag: reihe.epochTag(e.i), betrag: e.wertSpieler),
      ];

      expect(geldgewichteteRendite(e), closeTo(irrBisektion(handStroeme)!, 1e-9));
    });
  });
}
