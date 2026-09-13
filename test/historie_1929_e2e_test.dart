import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:boersenrennen_app/data/aktien_katalog.dart';
import 'package:boersenrennen_app/data/kursdaten_codec.dart';
import 'package:boersenrennen_app/data/kursdaten_repository.dart';
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

  group('Auswahl im Startmenü', _menueTests);
}

/// Deckt die im Startmenü angebotenen Auswahlen gegen den echten Katalog ab.
///
/// Der Fall „Gruppe angeboten, aber kein Titel mit genug Historie" ist genau
/// der, den P3 sichtbar gemacht hat. Hier wird festgehalten, **welche**
/// Kombinationen das betrifft – neue Daten dürfen die Liste verkürzen, aber
/// nicht unbemerkt verlängern.
void _menueTests() {
  const gruppen = [
    null,
    'Einzelaktien',
    'Welt-ETF',
    'Themen-Länder-ETF',
    'Index-Rohstoff',
    'Historisch',
  ];
  const dauern = [5, 10, 20];

  late List<AktienEintrag> katalog;

  setUpAll(() {
    final json =
        jsonDecode(File('assets/kurse/index.json').readAsStringSync()) as Map<String, dynamic>;
    katalog = (json['aktien'] as List)
        .cast<Map<String, dynamic>>()
        .map(AktienEintrag.vonJson)
        .toList();
  });

  test('die Gruppe „Historisch" ist für jede angebotene Rundenlänge spielbar', () {
    final repo = KursdatenRepository();
    for (final jahre in dauern) {
      expect(
        repo.hatSpielbareAktie(katalog, minJahre: jahre.toDouble(), gruppe: 'Historisch'),
        isTrue,
        reason: 'Historisch + $jahre Jahre hat keinen Titel',
      );
    }
  });

  test('unspielbar sind genau die bekannten Kombinationen', () {
    final repo = KursdatenRepository();
    final unspielbar = <String>[
      for (final g in gruppen)
        for (final j in dauern)
          if (!repo.hatSpielbareAktie(katalog, minJahre: j.toDouble(), gruppe: g))
            '${g ?? "Zufällig"} + $j',
    ];

    // Der älteste Welt-ETF im Pool (VEU) startet 2007 – 20 Jahre gibt die
    // Gruppe schlicht nicht her. Der Startbildschirm meldet das seit P3.
    expect(unspielbar, ['Welt-ETF + 20']);
  });

  test('jeder Titel der Gruppe „Historisch" beginnt deutlich vor 1995', () {
    final hist = katalog.where((a) => a.gruppe == 'Historisch').toList();

    expect(hist, hasLength(7));
    for (final a in hist) {
      expect(a.ersterTag.year, lessThan(1997), reason: a.ticker);
    }
  });

  test('gespleißte Reihen tragen Spleißpunkt und Quellenkette', () {
    final gespleisst = katalog.where((a) => a.istGespleisst).toList();

    expect(gespleisst.map((a) => a.ticker),
        ['VGTSX+VXUS', 'FSPTX+XLK', 'FSENX+XLE', 'FIDSX+XLF']);
    for (final a in gespleisst) {
      // Der Spleißpunkt muss *innerhalb* der Reihe liegen – läge er davor
      // oder dahinter, wäre der Hinweis im Ergebnis-Screen entweder immer
      // oder nie sichtbar, statt genau bei betroffenen Runden.
      expect(a.spleissAb!.isAfter(a.ersterTag), isTrue, reason: a.ticker);
      expect(a.spleissAb!.isBefore(a.letzterTag), isTrue, reason: a.ticker);

      // Kette von alt nach neu; der Ticker ist genau diese Kette.
      expect(a.quellen, hasLength(2), reason: a.ticker);
      expect(a.quellen.join('+'), a.ticker);
    }
  });

  test('alles bis auf den S&P 500 ab 1927 liegt in Euro vor', () {
    final nichtEuro = katalog.where((a) => a.waehrung != 'EUR').toList();

    // Die Wechselkurskette reicht bis 1957 zurück. Über die Währungsreform
    // von 1948 hinweg gibt es keinen sinnvollen Euro-Gegenwert, deshalb
    // bleibt genau diese eine Reihe in Dollar.
    expect(nichtEuro.map((a) => a.ticker), ['^GSPC']);
    expect(nichtEuro.single.waehrung, 'USD');
    expect(nichtEuro.single.umgerechnet, isFalse);
  });

  test('umgerechnet ist genau dann gesetzt, wenn die Notierung abweicht', () {
    for (final a in katalog) {
      if (a.umgerechnet) {
        // Umgerechnet wird immer nach Euro, und nur aus einer Fremdwährung.
        expect(a.waehrung, 'EUR', reason: a.ticker);
        expect(a.notierung, isNot('EUR'), reason: a.ticker);
      } else {
        // Nicht umgerechnet heißt: Anzeige- und Notierungswährung sind gleich.
        expect(a.waehrung, a.notierung, reason: a.ticker);
      }
    }

    // Die deutschen Titel notieren ohnehin in Euro und werden nicht angefasst.
    final sap = katalog.firstWhere((a) => a.ticker == 'SAP.DE');
    expect(sap.notierung, 'EUR');
    expect(sap.umgerechnet, isFalse);

    // Der Nikkei ist der einzige Yen-Titel.
    final n225 = katalog.firstWhere((a) => a.ticker == '^N225');
    expect(n225.notierung, 'JPY');
    expect(n225.umgerechnet, isTrue);
    expect(n225.waehrung, 'EUR');
  });

  test('Ticker sind im ganzen Katalog eindeutig', () {
    // Die gespleißten Reihen liegen neben der kurzen Reihe desselben ETF –
    // "XLK" allein wäre also doppelt vergeben. Der Ticker ist der Schlüssel,
    // unter dem Bestenliste und Spielprotokoll eine Runde ablegen.
    final ticker = katalog.map((a) => a.ticker).toList();
    expect(ticker.toSet(), hasLength(ticker.length));

    final dateien = katalog.map((a) => a.datei).toList();
    expect(dateien.toSet(), hasLength(dateien.length));
  });

  test('der Vorgänger-Hinweis hängt an der Runde, nicht am Titel', () {
    final xlk = katalog.firstWhere((a) => a.ticker == 'FSPTX+XLK');
    final ab = Kursreihe.zuEpochTag(xlk.spleissAb!);

    // Runde beginnt vor dem Spleißpunkt -> zeigt den Vorgängerfonds.
    expect(xlk.rundeZeigtVorgaenger(ab - 1), isTrue);
    // Runde beginnt genau am oder nach dem Spleißpunkt -> echter ETF.
    expect(xlk.rundeZeigtVorgaenger(ab), isFalse);
    expect(xlk.rundeZeigtVorgaenger(ab + 1), isFalse);

    expect(xlk.vorgaenger, 'FSPTX');

    // Eine ungespleißte Reihe darf den Hinweis nie auslösen – auch nicht für
    // einen Rundenstart weit in der Vergangenheit.
    final gspc = katalog.firstWhere((a) => a.ticker == '^GSPC');
    expect(gspc.rundeZeigtVorgaenger(gspc.ersterTag.millisecondsSinceEpoch), isFalse);
    expect(gspc.rundeZeigtVorgaenger(-99999), isFalse);
    expect(gspc.vorgaenger, isNull);
  });

  test('ungespleißte Reihen tragen keinen Spleißpunkt', () {
    for (final a in katalog.where((a) => !a.istGespleisst)) {
      expect(a.spleissAb, isNull, reason: a.ticker);
      expect(a.quellen, isEmpty, reason: a.ticker);
    }
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
