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
}
