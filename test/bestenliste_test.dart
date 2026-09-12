import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boersenrennen_app/data/bestenliste.dart';

BestenlisteEintrag baueEintrag({
  double? endbetragWuerfel,
  double? perzentil,
  double scoreVsInvestor = -20.0,
}) =>
    BestenlisteEintrag(
      spielername: 'Michael',
      ticker: 'AAPL',
      aktieName: 'Apple Inc.',
      startDatum: DateTime.utc(2010, 1, 1),
      endDatum: DateTime.utc(2020, 1, 1),
      endbetragSpieler: 1200.0,
      endbetragInvestor: 1500.0,
      endbetragSicherheit: 1100.0,
      zinssatzSicherheit: 3.0,
      scoreVsInvestor: scoreVsInvestor,
      scoreVsSicherheit: 9.0,
      erstelltAm: DateTime.utc(2020, 1, 1),
      endbetragWuerfel: endbetragWuerfel,
      perzentil: perzentil,
    );

void main() {
  group('BestenlisteEintrag – JSON und Rückwärtskompatibilität (V12)', () {
    test('ein Eintrag im alten Format ohne endbetragWuerfel-Schlüssel liefert null', () {
      // Simuliert einen Bestandseintrag von vor der Einführung des
      // Würfel-Investors – der Schlüssel fehlt im JSON komplett.
      final altesFormat = baueEintrag().zuJson()..remove('endbetragWuerfel');

      final eintrag = BestenlisteEintrag.vonJson(altesFormat);

      expect(eintrag.endbetragWuerfel, isNull);
      expect(eintrag.spielername, 'Michael');
      expect(eintrag.endbetragSpieler, 1200.0);
    });

    test('ein Eintrag mit gesetztem endbetragWuerfel überlebt den Rundtrip', () {
      final original = baueEintrag(endbetragWuerfel: 1333.33);

      final wiederhergestellt = BestenlisteEintrag.vonJson(original.zuJson());

      expect(wiederhergestellt.endbetragWuerfel, closeTo(1333.33, 1e-9));
    });

    test('ein Eintrag ohne Würfel-Investor serialisiert und deserialisiert korrekt zu null', () {
      final original = baueEintrag(); // endbetragWuerfel bleibt null

      final json = original.zuJson();
      expect(json['endbetragWuerfel'], isNull);

      final wiederhergestellt = BestenlisteEintrag.vonJson(json);
      expect(wiederhergestellt.endbetragWuerfel, isNull);
    });
  });

  group('BestenlisteEintrag – Perzentil und Rückwärtskompatibilität (V15)', () {
    test('ein Eintrag im alten Format ohne perzentil-Schlüssel liefert null', () {
      final altesFormat = baueEintrag().zuJson()..remove('perzentil');

      final eintrag = BestenlisteEintrag.vonJson(altesFormat);

      expect(eintrag.perzentil, isNull);
    });

    test('ein Eintrag mit gesetztem Perzentil überlebt den Rundtrip', () {
      final original = baueEintrag(perzentil: 87.5);

      final wiederhergestellt = BestenlisteEintrag.vonJson(original.zuJson());

      expect(wiederhergestellt.perzentil, closeTo(87.5, 1e-9));
    });
  });

  group('BestenlisteRepository – Sortierung nach Perzentil (V15)', () {
    test(
        'Einträge mit Perzentil stehen absteigend sortiert vor Einträgen ohne '
        'Perzentil', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = BestenlisteRepository(prefs);

      await repo.hinzufuegen(baueEintrag(perzentil: 40.0));
      await repo.hinzufuegen(baueEintrag()); // kein Perzentil
      await repo.hinzufuegen(baueEintrag(perzentil: 90.0));

      final perzentile = repo.eintraege.map((e) => e.perzentil).toList();
      expect(perzentile, [90.0, 40.0, null]);
    });

    test(
        'unter mehreren Einträgen ohne Perzentil entscheidet scoreVsInvestor als '
        'Tiebreaker', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = BestenlisteRepository(prefs);

      await repo.hinzufuegen(baueEintrag(scoreVsInvestor: -5.0));
      await repo.hinzufuegen(baueEintrag(perzentil: 60.0, scoreVsInvestor: -99.0));
      await repo.hinzufuegen(baueEintrag(scoreVsInvestor: 12.0));

      final scores = repo.eintraege.map((e) => e.scoreVsInvestor).toList();
      // Der Eintrag mit Perzentil steht trotz schlechtestem Score vorne,
      // die beiden ohne Perzentil sind untereinander nach Score sortiert.
      expect(scores, [-99.0, 12.0, -5.0]);
    });

    test(
        'ein manuell im alten Format eingefügter Bestandseintrag ohne Perzentil-Schlüssel '
        'landet nach dem Laden korrekt am Ende', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo1 = BestenlisteRepository(prefs);
      await repo1.hinzufuegen(baueEintrag(perzentil: 30.0));

      // Simuliert einen von Hand in die SharedPreferences geschriebenen
      // Alteintrag ohne den perzentil-Schlüssel.
      final altesFormat = baueEintrag(scoreVsInvestor: 999.0).zuJson()..remove('perzentil');
      final roh = prefs.getString('bestenliste_v1')!;
      final liste = (jsonDecode(roh) as List).cast<Map<String, dynamic>>()..add(altesFormat);
      await prefs.setString('bestenliste_v1', jsonEncode(liste));

      final repo2 = BestenlisteRepository(prefs);

      expect(repo2.eintraege.length, 2);
      expect(repo2.eintraege.first.perzentil, closeTo(30.0, 1e-9));
      expect(repo2.eintraege.last.perzentil, isNull);
    });
  });
}
