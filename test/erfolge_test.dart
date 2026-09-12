import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/domain/erfolge.dart';
import 'package:boersenrennen_app/domain/kursreihe.dart';

void main() {
  group('Erfolge.eiserneHand', () {
    test('kippt exakt bei -30 % gegenüber dem bisherigen Rundenhoch (strikt kleinergleich)', () {
      final reihe = Kursreihe.ausListen([0, 1, 2], [100.0, 100.0, 70.0]); // exakt -30%
      expect(Erfolge.eiserneHand(reihe, [true, true, true]), isTrue);
    });

    test('bei nur -29,9 % wird der Erfolg NICHT ausgelöst', () {
      final reihe = Kursreihe.ausListen([0, 1, 2], [100.0, 100.0, 70.1]); // -29,9%
      expect(Erfolge.eiserneHand(reihe, [true, true, true]), isFalse);
    });

    test('ist der Spieler am Crash-Tag NICHT investiert, löst der Erfolg nicht aus', () {
      final reihe = Kursreihe.ausListen([0, 1, 2], [100.0, 100.0, 70.0]);
      expect(Erfolge.eiserneHand(reihe, [true, true, false]), isFalse);
    });

    test('ohne einen einzigen gespielten Tag ist der Erfolg false (keine Exception)', () {
      final reihe = Kursreihe.ausListen([0], [100.0]);
      expect(Erfolge.eiserneHand(reihe, []), isFalse);
    });

    test('ein durchgehend steigender Kurs löst den Erfolg nie aus', () {
      final reihe = Kursreihe.ausListen([0, 1, 2, 3], [100.0, 110.0, 120.0, 130.0]);
      expect(Erfolge.eiserneHand(reihe, [true, true, true, true]), isFalse);
    });
  });

  group('Erfolge.nichtstun', () {
    test('genau 10 Jahre ohne einen einzigen Verkauf löst aus', () {
      expect(Erfolge.nichtstun(10.0, 0), isTrue);
    });

    test('9,99 Jahre lösen NICHT aus, auch ohne Verkauf', () {
      expect(Erfolge.nichtstun(9.99, 0), isFalse);
    });

    test('10 Jahre mit einem einzigen Verkauf lösen NICHT aus', () {
      expect(Erfolge.nichtstun(10.0, 1), isFalse);
    });
  });

  group('Erfolge.derGlueckliche', () {
    test('positiver Score und Perzentil knapp unter 20 löst aus', () {
      expect(Erfolge.derGlueckliche(5.0, 19.9), isTrue);
    });

    test('positiver Score, aber Perzentil genau 20 löst NICHT aus (strikt kleiner)', () {
      expect(Erfolge.derGlueckliche(5.0, 20.0), isFalse);
    });

    test('ohne Monte-Carlo-Perzentil (null) wird konservativ mit 100 gerechnet -> false', () {
      expect(Erfolge.derGlueckliche(5.0, null), isFalse);
    });

    test('negativer Score löst trotz niedrigem Perzentil nicht aus', () {
      expect(Erfolge.derGlueckliche(-5.0, 10.0), isFalse);
    });
  });

  group('Erfolge.selbsterkenntnis', () {
    test('genau 10 mal bis zum Ende gescrollt löst aus', () {
      expect(Erfolge.selbsterkenntnis(10), isTrue);
    });

    test('9 mal löst NICHT aus', () {
      expect(Erfolge.selbsterkenntnis(9), isFalse);
    });
  });

  group('Erfolge.zeitreisender', () {
    test('5 verschiedene Jahrzehnte lösen aus', () {
      final startDaten = [
        DateTime.utc(1975, 1, 1),
        DateTime.utc(1988, 1, 1),
        DateTime.utc(1994, 1, 1),
        DateTime.utc(2005, 1, 1),
        DateTime.utc(2019, 1, 1),
      ];
      expect(Erfolge.zeitreisender(startDaten), isTrue);
    });

    test('nur 4 verschiedene Jahrzehnte lösen NICHT aus', () {
      final startDaten = [
        DateTime.utc(1988, 1, 1),
        DateTime.utc(1994, 1, 1),
        DateTime.utc(2005, 1, 1),
        DateTime.utc(2019, 1, 1),
      ];
      expect(Erfolge.zeitreisender(startDaten), isFalse);
    });

    test('mehrere Runden im selben Jahrzehnt zählen nur einmal', () {
      final startDaten = [
        DateTime.utc(1994, 1, 1),
        DateTime.utc(1996, 6, 1),
        DateTime.utc(1999, 12, 31),
      ];
      expect(Erfolge.zeitreisender(startDaten), isFalse);
    });
  });

  group('Erfolge.alleWetter', () {
    test('sowohl positive als auch negative Marktrendite löst aus', () {
      expect(Erfolge.alleWetter([0.2, -0.1, 0.05]), isTrue);
    });

    test('ausschließlich positive Marktrenditen lösen NICHT aus', () {
      expect(Erfolge.alleWetter([0.2, 0.05, 0.3]), isFalse);
    });

    test('ausschließlich negative Marktrenditen lösen NICHT aus', () {
      expect(Erfolge.alleWetter([-0.2, -0.05]), isFalse);
    });

    test('eine Marktrendite von exakt 0 zählt für keine der beiden Seiten', () {
      expect(Erfolge.alleWetter([0.0, 0.0]), isFalse);
    });
  });

  group('Erfolge.vielspieler', () {
    test('genau 25 gespielte Runden löst aus', () {
      expect(Erfolge.vielspieler(25), isTrue);
    });

    test('24 gespielte Runden lösen NICHT aus', () {
      expect(Erfolge.vielspieler(24), isFalse);
    });
  });

  group('Erfolge.alle', () {
    test('enthält für jeden ErfolgId genau eine Definition', () {
      final ids = Erfolge.alle.map((d) => d.id).toSet();
      expect(ids.length, ErfolgId.values.length);
      expect(ids, ErfolgId.values.toSet());
    });

    test('kein Titel oder Beschreibungstext ist leer', () {
      for (final def in Erfolge.alle) {
        expect(def.titel, isNotEmpty);
        expect(def.beschreibung, isNotEmpty);
      }
    });
  });
}
