import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boersenrennen_app/data/spielverlauf.dart';

SpielverlaufEintrag baueEintrag({
  DateTime? erstelltAm,
  double? perzentil,
  double? abstandVerkaufZuTiefTage,
  double? abstandKaufZuHochTage,
  double? anteilVerkaeufeNachCrash,
}) =>
    SpielverlaufEintrag(
      erstelltAm: erstelltAm ?? DateTime.utc(2020, 1, 1),
      startDatum: DateTime.utc(2010, 1, 1),
      ticker: 'AAPL',
      gruppe: 'Einzelaktien',
      rundenjahre: 5.0,
      anzahlKaeufe: 3,
      anzahlVerkaeufe: 2,
      anteilInvestierterTage: 0.7,
      perzentil: perzentil,
      scoreVsInvestor: -12.5,
      marktRenditeRunde: 0.35,
      abstandVerkaufZuTiefTage: abstandVerkaufZuTiefTage,
      abstandKaufZuHochTage: abstandKaufZuHochTage,
      anteilVerkaeufeNachCrash: anteilVerkaeufeNachCrash,
    );

void main() {
  group('SpielverlaufEintrag – JSON-Rundtrip', () {
    test('alle Felder inklusive nullable Verhaltensmaße überleben den Rundtrip', () {
      final original = baueEintrag(
        perzentil: 42.0,
        abstandVerkaufZuTiefTage: 12.5,
        abstandKaufZuHochTage: 8.0,
        anteilVerkaeufeNachCrash: 0.5,
      );

      final wiederhergestellt = SpielverlaufEintrag.vonJson(original.zuJson());

      expect(wiederhergestellt.ticker, 'AAPL');
      expect(wiederhergestellt.gruppe, 'Einzelaktien');
      expect(wiederhergestellt.rundenjahre, closeTo(5.0, 1e-9));
      expect(wiederhergestellt.anzahlKaeufe, 3);
      expect(wiederhergestellt.anzahlVerkaeufe, 2);
      expect(wiederhergestellt.perzentil, closeTo(42.0, 1e-9));
      expect(wiederhergestellt.abstandVerkaufZuTiefTage, closeTo(12.5, 1e-9));
      expect(wiederhergestellt.abstandKaufZuHochTage, closeTo(8.0, 1e-9));
      expect(wiederhergestellt.anteilVerkaeufeNachCrash, closeTo(0.5, 1e-9));
    });

    test('fehlende Verhaltensmaße (nie gehandelt) serialisieren und deserialisieren zu null', () {
      final original = baueEintrag(); // alle nullable Felder bleiben null

      final json = original.zuJson();
      expect(json['perzentil'], isNull);
      expect(json['abstandVerkaufZuTiefTage'], isNull);

      final wiederhergestellt = SpielverlaufEintrag.vonJson(json);
      expect(wiederhergestellt.perzentil, isNull);
      expect(wiederhergestellt.abstandVerkaufZuTiefTage, isNull);
      expect(wiederhergestellt.abstandKaufZuHochTage, isNull);
      expect(wiederhergestellt.anteilVerkaeufeNachCrash, isNull);
    });
  });

  group('SpielverlaufRepository – chronologisches FIFO (V11)', () {
    test(
        'bleibt die maxEintraege-Grenze unterschritten, sind alle Einträge in '
        'Einfügereihenfolge vorhanden', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SpielverlaufRepository(prefs);

      for (var i = 0; i < 5; i++) {
        await repo.hinzufuegen(baueEintrag(erstelltAm: DateTime.utc(2020, 1, 1 + i)));
      }

      expect(repo.eintraege.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(repo.eintraege[i].erstelltAm, DateTime.utc(2020, 1, 1 + i));
      }
    });

    test(
        'wird die maxEintraege-Grenze überschritten, fällt die älteste Runde heraus '
        '– NICHT die mit dem schlechtesten Score (abweichend von der Bestenliste)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SpielverlaufRepository(prefs);

      for (var i = 0; i < SpielverlaufRepository.maxEintraege + 3; i++) {
        await repo.hinzufuegen(baueEintrag(erstelltAm: DateTime.utc(2000, 1, 1).add(Duration(days: i))));
      }

      expect(repo.eintraege.length, SpielverlaufRepository.maxEintraege);
      // Die ersten 3 (ältesten) müssen weg sein, der Rest bleibt chronologisch.
      expect(repo.eintraege.first.erstelltAm, DateTime.utc(2000, 1, 1).add(const Duration(days: 3)));
      expect(
        repo.eintraege.last.erstelltAm,
        DateTime.utc(2000, 1, 1).add(Duration(days: SpielverlaufRepository.maxEintraege + 2)),
      );
    });

    test('ein Rundenabschluss wird persistiert und überlebt einen frischen Repository-Load',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo1 = SpielverlaufRepository(prefs);
      await repo1.hinzufuegen(baueEintrag(perzentil: 77.0));

      final repo2 = SpielverlaufRepository(prefs);

      expect(repo2.eintraege.length, 1);
      expect(repo2.eintraege.first.perzentil, closeTo(77.0, 1e-9));
    });
  });
}
