import 'dart:typed_data';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/data/aktien_katalog.dart';
import 'package:boersenrennen_app/data/kursdaten_codec.dart';
import 'package:boersenrennen_app/data/kursdaten_repository.dart';
import 'package:boersenrennen_app/domain/kursreihe.dart';
import 'package:boersenrennen_app/domain/runden_waehler.dart';
import 'package:boersenrennen_app/domain/score.dart';

/// Baut eine Binärdatei im Format von tools/export_kursdaten.py.
ByteData baueBin(int basis, List<int> offsets, List<double> kurse) {
  final anzahl = offsets.length;
  final padding = (4 - (anzahl * 2) % 4) % 4;
  final laenge = 12 + anzahl * 2 + padding + anzahl * 4;
  final b = ByteData(laenge);

  b.setUint8(0, 0x42); // 'B'
  b.setUint8(1, 0x52); // 'R'
  b.setUint8(2, 0x4B); // 'K'
  b.setUint8(3, 0x31); // '1'
  b.setUint32(4, basis, Endian.little);
  b.setUint32(8, anzahl, Endian.little);

  for (var i = 0; i < anzahl; i++) {
    b.setUint16(12 + i * 2, offsets[i], Endian.little);
  }
  final kursStart = 12 + anzahl * 2 + padding;
  for (var i = 0; i < anzahl; i++) {
    b.setFloat32(kursStart + i * 4, kurse[i], Endian.little);
  }
  return b;
}

void main() {
  group('KursdatenCodec', () {
    test('dekodiert Datum und Kurs korrekt', () {
      final basis = Kursreihe.zuEpochTag(DateTime.utc(2000, 1, 3));
      final daten = baueBin(basis, [0, 1, 4], [100.0, 101.5, 99.25]);

      final reihe = KursdatenCodec.dekodiere(daten);

      expect(reihe.laenge, 3);
      expect(Kursreihe.zuDatum(reihe.epochTag(0)), DateTime.utc(2000, 1, 3));
      expect(Kursreihe.zuDatum(reihe.epochTag(2)), DateTime.utc(2000, 1, 7));
      expect(reihe.kurs(0), closeTo(100.0, 1e-4));
      expect(reihe.kurs(1), closeTo(101.5, 1e-4));
      expect(reihe.kurs(2), closeTo(99.25, 1e-4));
    });

    test('lehnt eine Datei mit falschem Magic ab', () {
      final daten = baueBin(0, [0], [1.0]);
      daten.setUint8(0, 0x58); // 'X'
      expect(() => KursdatenCodec.dekodiere(daten), throwsFormatException);
    });

    test('lehnt eine zu kurze Datei ab', () {
      expect(() => KursdatenCodec.dekodiere(ByteData(6)), throwsFormatException);
    });

    // P4: Ohne diese Prüfungen liefert eine beschädigte oder halb geschriebene
    // Datei keinen Absturz, sondern still falsche Kurse – die Binärsuche setzt
    // streng aufsteigende Epochtage voraus.
    test('lehnt nicht streng aufsteigende Epochtage ab', () {
      final rueckwaerts = baueBin(0, [0, 5, 3], [1.0, 2.0, 3.0]);
      expect(() => KursdatenCodec.dekodiere(rueckwaerts), throwsFormatException);

      final doppelt = baueBin(0, [0, 5, 5], [1.0, 2.0, 3.0]);
      expect(() => KursdatenCodec.dekodiere(doppelt), throwsFormatException);
    });

    test('lehnt eine Datei ohne Kurse ab', () {
      expect(() => KursdatenCodec.dekodiere(baueBin(0, [], [])), throwsFormatException);
    });

    test('lehnt unbrauchbare Kurse ab', () {
      expect(() => KursdatenCodec.dekodiere(baueBin(0, [0, 1], [10.0, 0.0])),
          throwsFormatException);
      expect(() => KursdatenCodec.dekodiere(baueBin(0, [0, 1], [10.0, -5.0])),
          throwsFormatException);
      expect(() => KursdatenCodec.dekodiere(baueBin(0, [0, 1], [10.0, double.nan])),
          throwsFormatException);
    });
  });

  group('Kursreihe', () {
    test('Binärsuche findet den ersten Tag >= Ziel', () {
      final reihe = Kursreihe.ausListen([10, 20, 30, 40], [1, 2, 3, 4]);
      expect(reihe.binaereSuche(10), 0);
      expect(reihe.binaereSuche(21), 2);
      expect(reihe.binaereSuche(40), 3);
      expect(reihe.binaereSuche(99), 4);
    });

    test('Ausschnitt teilt sich die Daten ohne Kopie', () {
      final reihe = Kursreihe.ausListen([1, 2, 3, 4, 5], [10, 20, 30, 40, 50]);
      final teil = reihe.ausschnitt(1, 4);
      expect(teil.laenge, 3);
      expect(teil.kurs(0), 20);
      expect(teil.ersterTag, 2);
      expect(teil.letzterTag, 4);
    });

    test('Epochtag-Umrechnung ist verlustfrei', () {
      final d = DateTime.utc(2016, 3, 12);
      expect(Kursreihe.zuDatum(Kursreihe.zuEpochTag(d)), d);
    });
  });

  group('RundenWaehler', () {
    Kursreihe langeReihe(int jahre) {
      final tage = <int>[];
      final kurse = <double>[];
      final start = Kursreihe.zuEpochTag(DateTime.utc(1996, 1, 1));
      for (var d = 0; d < jahre * 365; d++) {
        tage.add(start + d);
        kurse.add(100 + d * 0.01);
      }
      return Kursreihe.ausListen(tage, kurse);
    }

    test('gewählter Ausschnitt hat die gewünschte Länge', () {
      final auswahl = RundenWaehler(Random(42)).waehle(langeReihe(30), rundenJahre: 10);
      expect(auswahl, isNotNull);
      final jahre = (auswahl!.ausschnitt.letzterTag - auswahl.ausschnitt.ersterTag) / 365.25;
      expect(jahre, closeTo(10, 0.2));
    });

    test('zu kurze Reihe liefert null', () {
      expect(RundenWaehler(Random(1)).waehle(langeReihe(3), rundenJahre: 10), isNull);
    });

    test('gleicher Seed ergibt dieselbe Runde', () {
      final reihe = langeReihe(30);
      final a = RundenWaehler(Random(7)).waehle(reihe, rundenJahre: 10)!;
      final b = RundenWaehler(Random(7)).waehle(reihe, rundenJahre: 10)!;
      expect(a.vonIndex, b.vonIndex);
      expect(a.bisIndex, b.bisIndex);
    });

    test('Vorlauf zeigt bis zu ein Jahr vor Rundenbeginn, endet am Start', () {
      final auswahl = RundenWaehler(Random(3)).waehle(langeReihe(30), rundenJahre: 10)!;
      expect(auswahl.vorlauf.letzterTag, lessThan(auswahl.ausschnitt.ersterTag));
      final vorlaufJahre =
          (auswahl.ausschnitt.ersterTag - auswahl.vorlauf.ersterTag) / 365.25;
      expect(vorlaufJahre, closeTo(1, 0.05));
    });

    test('Vorlauf ist leer, wenn die Runde am Anfang der Reihe startet', () {
      // Reihe exakt so lang wie eine Runde -> es gibt nur einen möglichen
      // Start, nämlich Index 0. Davor existiert keine Historie.
      const rundenJahre = 10;
      final rTage = (rundenJahre * 365.25).round();
      final start = Kursreihe.zuEpochTag(DateTime.utc(1996, 1, 1));
      final reihe = Kursreihe.ausListen(
        List.generate(rTage + 1, (i) => start + i),
        List.generate(rTage + 1, (i) => 100 + i * 0.01),
      );

      final auswahl = RundenWaehler(Random(1)).waehle(reihe, rundenJahre: rundenJahre)!;
      expect(auswahl.vonIndex, 0);
      expect(auswahl.vorlauf.laenge, 0);
    });
  });

  group('Score', () {
    test('Outperformance gegenüber dem Investor', () {
      expect(Score.vsInvestor(1100, 1000), 10.0);
      expect(Score.vsInvestor(900, 1000), -10.0);
      expect(Score.vsInvestor(1000, 1000), 0.0);
    });

    test('rundet auf zwei Nachkommastellen', () {
      expect(Score.vsInvestor(1234.5678, 1000), 23.46);
    });

    test('Referenz 0 ergibt 0 statt unendlich', () {
      expect(Score.vsInvestor(1000, 0), 0.0);
      expect(Score.vsSicherheit(1000, 0), 0.0);
    });
  });

  group('KursdatenRepository.zufall (P3)', () {
    AktienEintrag baueAktie(String ticker, String gruppe, double jahre) => AktienEintrag(
          ticker: ticker,
          name: ticker,
          kategorie: gruppe,
          gruppe: gruppe,
          datei: '$ticker.bin',
          anzahl: 1000,
          ersterTag: DateTime.utc(2020, 1, 1).subtract(Duration(days: (jahre * 365.25).round())),
          letzterTag: DateTime.utc(2020, 1, 1),
          quelle: 'bundled',
        );

    final katalog = [
      baueAktie('LANG', 'Einzelaktien', 25),
      baueAktie('KURZ', 'Welt-ETF', 12),
    ];

    test('liefert null statt eines zu kurzen Titels, wenn die Gruppe keinen langen hat',
        () {
      // Genau der Fall "Welt-ETFs + 20 Jahre": vorher fiel die Auswahl still
      // auf den zu kurzen Titel zurück, den RundenWaehler.waehle danach
      // verwarf – der Startknopf tat wortlos nichts.
      final gewaehlt = KursdatenRepository()
          .zufall(katalog, Random(1), minJahre: 20, gruppe: 'Welt-ETF');

      expect(gewaehlt, isNull);
    });

    test('weicht nicht auf eine fremde Gruppe aus', () {
      final gewaehlt = KursdatenRepository()
          .zufall(katalog, Random(1), minJahre: 10, gruppe: 'Themen-Länder-ETF');

      expect(gewaehlt, isNull);
    });

    test('wählt innerhalb der Gruppe, wenn ein Titel lang genug ist', () {
      final gewaehlt = KursdatenRepository()
          .zufall(katalog, Random(1), minJahre: 20, gruppe: 'Einzelaktien');

      expect(gewaehlt?.ticker, 'LANG');
    });

    test('hatSpielbareAktie deckt sich mit dem Ergebnis von zufall', () {
      final repo = KursdatenRepository();
      for (final gruppe in [null, 'Einzelaktien', 'Welt-ETF']) {
        for (final jahre in [10.0, 20.0]) {
          expect(
            repo.hatSpielbareAktie(katalog, minJahre: jahre, gruppe: gruppe),
            repo.zufall(katalog, Random(1), minJahre: jahre, gruppe: gruppe) != null,
            reason: 'Gruppe $gruppe, $jahre Jahre',
          );
        }
      }
    });
  });
}
