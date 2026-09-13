import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/domain/inflation.dart';
import 'package:boersenrennen_app/domain/kursreihe.dart';

void main() {
  group('Inflation.preisfaktor', () {
    test('über ein volles Jahr entspricht der Faktor exakt der Jahresrate', () {
      final von = Kursreihe.zuEpochTag(DateTime.utc(2020, 1, 1));
      final bis = Kursreihe.zuEpochTag(DateTime.utc(2021, 1, 1));
      final rate = Inflation.rateFuer(2020)!;

      expect(Inflation.preisfaktor(von, bis), closeTo(1 + rate / 100, 1e-9));
    });

    test('über 0 Tage ist der Faktor 1.0', () {
      final tag = Kursreihe.zuEpochTag(DateTime.utc(2015, 6, 1));
      expect(Inflation.preisfaktor(tag, tag), 1.0);
    });

    test('ein Zeitraum ganz ohne Datenabdeckung liefert 1.0 statt einer Exception', () {
      final von = Kursreihe.zuEpochTag(DateTime.utc(1980, 1, 1));
      final bis = Kursreihe.zuEpochTag(DateTime.utc(1985, 1, 1));
      expect(Inflation.preisfaktor(von, bis), 1.0);
    });

    test('taggenaue Interpolation über einen Jahreswechsel', () {
      final von = Kursreihe.zuEpochTag(DateTime.utc(2019, 12, 1));
      final mitte = Kursreihe.zuEpochTag(DateTime.utc(2020, 1, 1));
      final bis = Kursreihe.zuEpochTag(DateTime.utc(2020, 2, 1));

      final rate2019 = Inflation.rateFuer(2019)!;
      final rate2020 = Inflation.rateFuer(2020)!;

      // Erwartungswert unabhängig von der Implementierung per Hand über
      // Tagesdifferenzen berechnet: 2019 hat 365, 2020 (Schaltjahr) 366 Tage.
      final tageImAbschnitt2019 = mitte - von;
      final tageImAbschnitt2020 = bis - mitte;
      final erwartet = math.pow(1 + rate2019 / 100, tageImAbschnitt2019 / 365) *
          math.pow(1 + rate2020 / 100, tageImAbschnitt2020 / 366);

      expect(Inflation.preisfaktor(von, bis), closeTo(erwartet, 1e-9));
    });
  });

  group('Datenabdeckung (P5)', () {
    test('ein vollständig abgedeckter Zeitraum ist belastbar', () {
      final von = Kursreihe.zuEpochTag(DateTime.utc(2010, 1, 1));
      final bis = Kursreihe.zuEpochTag(DateTime.utc(2020, 1, 1));

      final p = Inflation.preisfaktorMitAbdeckung(von, bis);

      expect(p.abdeckung, closeTo(1.0, 1e-9));
      expect(p.istBelastbar, isTrue);
      expect(p.faktor, greaterThan(1.0));
    });

    test('ein Zeitraum ganz außerhalb der Tabelle ist nicht belastbar', () {
      // Vorher nicht von einer echten Nullteuerung unterscheidbar: der Faktor
      // ist in beiden Fällen 1.0.
      final von = Kursreihe.zuEpochTag(DateTime.utc(1980, 1, 1));
      final bis = Kursreihe.zuEpochTag(DateTime.utc(1985, 1, 1));

      final p = Inflation.preisfaktorMitAbdeckung(von, bis);

      expect(p.faktor, 1.0);
      expect(p.abdeckung, 0.0);
      expect(p.istBelastbar, isFalse);
    });

    test('eine Runde, die über das Tabellenende hinausläuft, ist nicht belastbar', () {
      // Der Alltagsfall: die Kursdaten reichen weiter als die Teuerungsreihe.
      final von = Kursreihe.zuEpochTag(DateTime.utc(Inflation.letztesJahr - 1, 1, 1));
      final bis = Kursreihe.zuEpochTag(DateTime.utc(Inflation.letztesJahr + 4, 1, 1));

      final p = Inflation.preisfaktorMitAbdeckung(von, bis);

      expect(p.abdeckung, lessThan(Preisfaktor.mindestAbdeckung));
      expect(p.istBelastbar, isFalse);
    });

    test('preisfaktor bleibt der Faktor aus preisfaktorMitAbdeckung', () {
      final von = Kursreihe.zuEpochTag(DateTime.utc(2005, 3, 7));
      final bis = Kursreihe.zuEpochTag(DateTime.utc(2018, 11, 2));

      expect(Inflation.preisfaktor(von, bis),
          Inflation.preisfaktorMitAbdeckung(von, bis).faktor);
    });
  });

  group('Tabellenumfang', () {
    test('deckt eine heutige Runde bis ans Ende der Kursdaten ab', () {
      // Der eigentliche Zweck der Einträge 2025/2026: Vorher endete die
      // Tabelle 2024, und weil die Kursdaten bis September 2026 reichen, fiel
      // praktisch *jede* Runde unter die Mindestabdeckung – die Kaufkraft
      // wurde also nie angezeigt.
      final p = Inflation.preisfaktorMitAbdeckung(
        Kursreihe.zuEpochTag(DateTime.utc(2016, 9, 11)),
        Kursreihe.zuEpochTag(DateTime.utc(2026, 9, 11)),
      );

      expect(p.abdeckung, 1.0);
      expect(p.istBelastbar, isTrue);
      expect(p.faktor, greaterThan(1.0));
    });

    test('ist von 1992 bis 2026 lückenlos', () {
      expect(Inflation.erstesJahr, 1992);
      expect(Inflation.letztesJahr, 2026);

      // Ein fehlendes Jahr mitten in der Tabelle senkte die Abdeckung, ohne
      // dass es beim Lesen der Map auffiele.
      final p = Inflation.preisfaktorMitAbdeckung(
        Kursreihe.zuEpochTag(DateTime.utc(1992, 1, 1)),
        Kursreihe.zuEpochTag(DateTime.utc(2027, 1, 1)),
      );
      expect(p.abdeckung, 1.0);
    });

    test('die Teuerung seit 1992 entspricht dem amtlichen Index', () {
      // Kettenprobe über die ganze Tabelle: Multipliziert man die Jahresraten
      // 1992 bis 2025, muss das Ergebnis der Quotient der amtlichen
      // Jahresdurchschnitte sein (Verbraucherpreisindex 2020 = 100).
      //
      // Bezugsjahr ist **1991** (61,9), nicht 1992: Die Rate für 1992 ist ja
      // schon die Veränderung von 1991 auf 1992. Enthält die Tabelle einen
      // Tippfehler, bricht diese Kette.
      final p = Inflation.preisfaktorMitAbdeckung(
        Kursreihe.zuEpochTag(DateTime.utc(1992, 1, 1)),
        Kursreihe.zuEpochTag(DateTime.utc(2026, 1, 1)),
      );

      expect(p.faktor, closeTo(121.9 / 61.9, 0.002));
    });
  });
}
