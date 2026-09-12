import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ein einzelner protokollierter Rundenabschluss – unabhängig davon, ob der
/// Spieler die Runde auch in die Bestenliste eingetragen hat. Grundlage für
/// das rundenübergreifende Verhaltensprofil (V11) und die Erfolge (V14).
class SpielverlaufEintrag {
  final DateTime erstelltAm;

  /// Beginn der historisch gezogenen Periode, NICHT das reale Spieldatum –
  /// Grundlage für den „Zeitreisender"-Erfolg (V14), der sich auf das
  /// gespielte Jahrzehnt bezieht.
  final DateTime startDatum;

  final String ticker;
  final String gruppe;

  /// Länge der Runde in Jahren (kalendarisch, 365,25-Tage-Konvention).
  final double rundenjahre;

  final int anzahlKaeufe;
  final int anzahlVerkaeufe;
  final double anteilInvestierterTage;

  /// Monte-Carlo-Perzentil dieser Runde, `null` wenn nicht bestimmbar
  /// (z. B. Runde vor Einführung des Perzentils oder zu wenige Läufe).
  final double? perzentil;

  final double scoreVsInvestor;

  /// Gesamtrendite des gespielten Titels über die Runde (nicht annualisiert) –
  /// Grundlage für den „Alle Wetter"-Erfolg (V14).
  final double marktRenditeRunde;

  final double? abstandVerkaufZuTiefTage;
  final double? abstandKaufZuHochTage;
  final double? anteilVerkaeufeNachCrash;

  const SpielverlaufEintrag({
    required this.erstelltAm,
    required this.startDatum,
    required this.ticker,
    required this.gruppe,
    required this.rundenjahre,
    required this.anzahlKaeufe,
    required this.anzahlVerkaeufe,
    required this.anteilInvestierterTage,
    required this.perzentil,
    required this.scoreVsInvestor,
    required this.marktRenditeRunde,
    required this.abstandVerkaufZuTiefTage,
    required this.abstandKaufZuHochTage,
    required this.anteilVerkaeufeNachCrash,
  });

  Map<String, dynamic> zuJson() => {
        'erstelltAm': erstelltAm.toIso8601String(),
        'startDatum': startDatum.toIso8601String(),
        'ticker': ticker,
        'gruppe': gruppe,
        'rundenjahre': rundenjahre,
        'anzahlKaeufe': anzahlKaeufe,
        'anzahlVerkaeufe': anzahlVerkaeufe,
        'anteilInvestierterTage': anteilInvestierterTage,
        'perzentil': perzentil,
        'scoreVsInvestor': scoreVsInvestor,
        'marktRenditeRunde': marktRenditeRunde,
        'abstandVerkaufZuTiefTage': abstandVerkaufZuTiefTage,
        'abstandKaufZuHochTage': abstandKaufZuHochTage,
        'anteilVerkaeufeNachCrash': anteilVerkaeufeNachCrash,
      };

  factory SpielverlaufEintrag.vonJson(Map<String, dynamic> j) => SpielverlaufEintrag(
        erstelltAm: DateTime.parse(j['erstelltAm'] as String),
        startDatum: DateTime.parse(j['startDatum'] as String),
        ticker: j['ticker'] as String,
        gruppe: j['gruppe'] as String,
        rundenjahre: (j['rundenjahre'] as num).toDouble(),
        anzahlKaeufe: j['anzahlKaeufe'] as int,
        anzahlVerkaeufe: j['anzahlVerkaeufe'] as int,
        anteilInvestierterTage: (j['anteilInvestierterTage'] as num).toDouble(),
        perzentil: (j['perzentil'] as num?)?.toDouble(),
        scoreVsInvestor: (j['scoreVsInvestor'] as num).toDouble(),
        marktRenditeRunde: (j['marktRenditeRunde'] as num).toDouble(),
        abstandVerkaufZuTiefTage: (j['abstandVerkaufZuTiefTage'] as num?)?.toDouble(),
        abstandKaufZuHochTage: (j['abstandKaufZuHochTage'] as num?)?.toDouble(),
        anteilVerkaeufeNachCrash: (j['anteilVerkaeufeNachCrash'] as num?)?.toDouble(),
      );
}

/// Rundenübergreifendes Spielprotokoll in den SharedPreferences.
///
/// Abweichend vom Bestenlisten-Muster ([BestenlisteRepository]) **nicht**
/// score-sortiert abgeschnitten, sondern chronologisch FIFO: die älteste
/// Runde fällt heraus, sobald [maxEintraege] überschritten wird. Ein
/// Verhaltensprofil soll die zuletzt gespielten Runden zeigen, nicht die
/// besten – Erfolge, die die volle Historie scannen (Zeitreisender, Alle
/// Wetter), sehen dadurch nur die letzten 200 Runden.
class SpielverlaufRepository extends ChangeNotifier {
  static const String _schluessel = 'spielverlauf_v1';
  static const int maxEintraege = 200;

  final SharedPreferences _prefs;
  List<SpielverlaufEintrag> _eintraege = [];

  SpielverlaufRepository(this._prefs) {
    _laden();
  }

  /// Chronologisch (älteste zuerst).
  List<SpielverlaufEintrag> get eintraege => List.unmodifiable(_eintraege);

  void _laden() {
    final roh = _prefs.getString(_schluessel);
    if (roh == null || roh.isEmpty) return;
    try {
      _eintraege = (jsonDecode(roh) as List)
          .cast<Map<String, dynamic>>()
          .map(SpielverlaufEintrag.vonJson)
          .toList();
    } catch (_) {
      // Beschädigter Eintrag darf die App nicht blockieren.
      _eintraege = [];
    }
  }

  Future<void> hinzufuegen(SpielverlaufEintrag eintrag) async {
    _eintraege.add(eintrag);
    if (_eintraege.length > maxEintraege) {
      _eintraege = _eintraege.sublist(_eintraege.length - maxEintraege);
    }
    await _prefs.setString(
      _schluessel,
      jsonEncode(_eintraege.map((e) => e.zuJson()).toList()),
    );
    notifyListeners();
  }
}
