import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/data/kursdaten_codec.dart';
import 'package:boersenrennen_app/domain/auswertung.dart';
import 'package:boersenrennen_app/domain/inflation.dart';
import 'package:boersenrennen_app/domain/kursreihe.dart';
import 'package:boersenrennen_app/domain/rennen_engine.dart';
import 'package:boersenrennen_app/domain/spiel_konfiguration.dart';

/// Prüft die ausgelieferte S&P-500-Datei selbst, nicht nur den Codec.
///
/// Die Reihe beginnt 1927 und hat damit als einzige einen **negativen**
/// Basis-Epochtag. Sie ist der Beleg dafür, dass die gesamte Kette –
/// Exporter, Binärformat, Kursreihe, Engine, Auswertung – mit Daten vor der
/// Unix-Epoche umgeht, ohne dass irgendwo still ein Vorzeichen verloren geht.
void main() {
  final datei = File('assets/kurse/gspc.bin');

  group('S&P 500 ab 1927 (Asset-Ebene)', () {
    late Kursreihe reihe;

    setUpAll(() {
      final bytes = datei.readAsBytesSync();
      reihe = KursdatenCodec.dekodiere(
        ByteData.view(Uint8List.fromList(bytes).buffer),
      );
    });

    test('beginnt vor der Unix-Epoche und bleibt durchgehend monoton', () {
      expect(reihe.ersterTag, lessThan(0));
      expect(Kursreihe.zuDatum(reihe.ersterTag), DateTime.utc(1927, 12, 30));

      for (var i = 1; i < reihe.laenge; i++) {
        expect(reihe.epochTag(i), greaterThan(reihe.epochTag(i - 1)),
            reason: 'Bruch der Monotonie an Index $i');
      }
    });

    test('enthält den Schwarzen Donnerstag mit plausibler Tagesbewegung', () {
      final i = reihe.binaereSuche(Kursreihe.zuEpochTag(DateTime.utc(1929, 10, 28)));
      expect(Kursreihe.zuDatum(reihe.epochTag(i)), DateTime.utc(1929, 10, 28));

      final aenderung = reihe.kurs(i) / reihe.kurs(i - 1) - 1;
      expect(aenderung, lessThan(-0.10));
      expect(aenderung, greaterThan(-0.20));
    });

    test('bildet den Absturz von 1929 bis 1932 in voller Tiefe ab', () {
      final hoch = _hoechsterKurs(reihe, DateTime.utc(1929, 1, 1), DateTime.utc(1929, 9, 30));
      final tief = _tiefsterKurs(reihe, DateTime.utc(1932, 1, 1), DateTime.utc(1932, 12, 31));

      expect(tief / hoch - 1, lessThan(-0.80));
    });
  });

  group('Eine Runde durch die Weltwirtschaftskrise', () {
    test('läuft vollständig durch und liefert endliche Kennzahlen', () {
      final bytes = datei.readAsBytesSync();
      final voll = KursdatenCodec.dekodiere(
        ByteData.view(Uint8List.fromList(bytes).buffer),
      );

      final von = voll.binaereSuche(Kursreihe.zuEpochTag(DateTime.utc(1929, 1, 2)));
      final bis = voll.binaereSuche(Kursreihe.zuEpochTag(DateTime.utc(1939, 1, 2)));
      final reihe = voll.ausschnitt(von, bis);

      expect(reihe.laenge, greaterThan(2000));

      // Ohne Sparplan, um den reinen Buy-and-Hold-Effekt zu isolieren.
      const cfg = SpielKonfiguration(monatsEinzahlung: 0.0);
      final e = RennenEngine(reihe, cfg);
      e.kaufen();
      var schritte = 0;
      while (!e.fertig && schritte++ < reihe.laenge + 10) {
        e.schritt();
      }

      expect(e.fertig, isTrue);

      final a = RundenAuswertung.aus(e);
      expect(a.endwertSpieler.isFinite, isTrue);
      expect(a.endwertInvestor.isFinite, isTrue);
      expect(a.endwertSpieler, greaterThan(0));

      // Wer Anfang 1929 investierte, lag zehn Jahre später noch immer rund
      // die Hälfte im Minus. Die Runde zeigt also die Krise und nicht deren
      // Erholung – die kam erst in den 1950ern.
      expect(a.endwertInvestor, lessThan(0.7 * cfg.startCash));
      expect(a.endwertInvestor, greaterThan(0.3 * cfg.startCash));
    });

    test('mit Sparplan trägt der Zukauf im Tief die Runde ins Plus', () {
      // Derselbe Zeitraum, nur mit den voreingestellten 100 € im Monat. Das
      // ist die Lektion, für die sich die 1929er Daten überhaupt lohnen:
      // dieselbe Katastrophe, anderes Ergebnis, weil weiter eingezahlt wurde.
      final bytes = datei.readAsBytesSync();
      final voll = KursdatenCodec.dekodiere(
        ByteData.view(Uint8List.fromList(bytes).buffer),
      );
      final reihe = voll.ausschnitt(
        voll.binaereSuche(Kursreihe.zuEpochTag(DateTime.utc(1929, 1, 2))),
        voll.binaereSuche(Kursreihe.zuEpochTag(DateTime.utc(1939, 1, 2))),
      );

      const cfg = SpielKonfiguration();
      final e = RennenEngine(reihe, cfg);
      e.kaufen();
      var schritte = 0;
      while (!e.fertig && schritte++ < reihe.laenge + 10) {
        e.schritt();
      }

      final a = RundenAuswertung.aus(e);
      final eingezahlt = cfg.startCash + 120 * cfg.monatsEinzahlung;

      expect(a.endwertInvestor, greaterThan(eingezahlt));
    });

    test('meldet die Kaufkraft als nicht belastbar, statt sie zu erfinden', () {
      // Die Destatis-Tabelle beginnt Jahrzehnte nach 1929. Eine Runde dort
      // darf keine Realwerte ausweisen – der Abdeckungsmechanismus aus P5
      // muss ohne Sonderfall für negative Epochtage greifen.
      final p = Inflation.preisfaktorMitAbdeckung(
        Kursreihe.zuEpochTag(DateTime.utc(1929, 1, 2)),
        Kursreihe.zuEpochTag(DateTime.utc(1939, 1, 2)),
      );

      expect(p.abdeckung, 0.0);
      expect(p.faktor, 1.0);
      expect(p.istBelastbar, isFalse);
      expect(Inflation.erstesJahr, greaterThan(1939));
    });
  });
}

double _hoechsterKurs(Kursreihe r, DateTime von, DateTime bis) =>
    _spanne(r, von, bis).reduce((a, b) => a > b ? a : b);

double _tiefsterKurs(Kursreihe r, DateTime von, DateTime bis) =>
    _spanne(r, von, bis).reduce((a, b) => a < b ? a : b);

List<double> _spanne(Kursreihe r, DateTime von, DateTime bis) {
  final a = r.binaereSuche(Kursreihe.zuEpochTag(von));
  final b = r.binaereSuche(Kursreihe.zuEpochTag(bis));
  return [for (var i = a; i < b; i++) r.kurs(i)];
}
