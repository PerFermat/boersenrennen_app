import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ein Ergebnis-Eintrag der lokalen Bestenliste.
/// Felder wie in der `bestenliste`-Tabelle der Web-Version, nur mit Ticker
/// statt Fremdschlüssel (auf dem Gerät gibt es keine `aktien`-Tabelle).
class BestenlisteEintrag {
  final String spielername;
  final String ticker;
  final String aktieName;
  final DateTime startDatum;
  final DateTime endDatum;
  final double endbetragSpieler;
  final double endbetragInvestor;
  final double endbetragSicherheit;
  final double zinssatzSicherheit;
  final double scoreVsInvestor;
  final double scoreVsSicherheit;
  final DateTime erstelltAm;

  /// Endbetrag des Würfel-Investors, falls er mitgespielt hat. `null` bei
  /// Einträgen ohne Würfel-Investor (auch vor Einführung dieses Features).
  final double? endbetragWuerfel;

  /// Monte-Carlo-Perzentil dieser Runde – normiert innerhalb der Runde,
  /// dadurch über verschiedene Titel/Zeiträume hinweg vergleichbar. `null`
  /// bei Einträgen von vor Einführung des Perzentils oder ohne einen
  /// einzigen Trade (siehe [RundenAuswertung]/Monte-Carlo).
  final double? perzentil;

  const BestenlisteEintrag({
    required this.spielername,
    required this.ticker,
    required this.aktieName,
    required this.startDatum,
    required this.endDatum,
    required this.endbetragSpieler,
    required this.endbetragInvestor,
    required this.endbetragSicherheit,
    required this.zinssatzSicherheit,
    required this.scoreVsInvestor,
    required this.scoreVsSicherheit,
    required this.erstelltAm,
    this.endbetragWuerfel,
    this.perzentil,
  });

  Map<String, dynamic> zuJson() => {
        'spielername': spielername,
        'ticker': ticker,
        'aktieName': aktieName,
        'startDatum': startDatum.toIso8601String(),
        'endDatum': endDatum.toIso8601String(),
        'endbetragSpieler': endbetragSpieler,
        'endbetragInvestor': endbetragInvestor,
        'endbetragSicherheit': endbetragSicherheit,
        'zinssatzSicherheit': zinssatzSicherheit,
        'scoreVsInvestor': scoreVsInvestor,
        'scoreVsSicherheit': scoreVsSicherheit,
        'erstelltAm': erstelltAm.toIso8601String(),
        'endbetragWuerfel': endbetragWuerfel,
        'perzentil': perzentil,
      };

  factory BestenlisteEintrag.vonJson(Map<String, dynamic> j) => BestenlisteEintrag(
        spielername: j['spielername'] as String,
        ticker: j['ticker'] as String,
        aktieName: j['aktieName'] as String,
        startDatum: DateTime.parse(j['startDatum'] as String),
        endDatum: DateTime.parse(j['endDatum'] as String),
        endbetragSpieler: (j['endbetragSpieler'] as num).toDouble(),
        endbetragInvestor: (j['endbetragInvestor'] as num).toDouble(),
        endbetragSicherheit: (j['endbetragSicherheit'] as num).toDouble(),
        zinssatzSicherheit: (j['zinssatzSicherheit'] as num).toDouble(),
        scoreVsInvestor: (j['scoreVsInvestor'] as num).toDouble(),
        scoreVsSicherheit: (j['scoreVsSicherheit'] as num).toDouble(),
        erstelltAm: DateTime.parse(j['erstelltAm'] as String),
        // Fehlt bei Einträgen aus der Zeit vor dem Würfel-Investor -> null.
        endbetragWuerfel: (j['endbetragWuerfel'] as num?)?.toDouble(),
        // Fehlt bei Einträgen aus der Zeit vor Einführung des Perzentils -> null.
        perzentil: (j['perzentil'] as num?)?.toDouble(),
      );
}

/// Lokale Bestenliste in den SharedPreferences – ein JSON-Array unter einem
/// Schlüssel. Bei ~200 Byte je Eintrag und maximal 100 Einträgen sind das
/// ~20 KB; eine Datenbank wäre dafür überdimensioniert.
class BestenlisteRepository extends ChangeNotifier {
  static const String _schluessel = 'bestenliste_v1';
  static const int maxEintraege = 100;

  final SharedPreferences _prefs;
  List<BestenlisteEintrag> _eintraege = [];

  BestenlisteRepository(this._prefs) {
    _laden();
  }

  /// Absteigend nach [BestenlisteEintrag.perzentil] sortiert (V15) – normiert
  /// über verschiedene Titel/Zeiträume hinweg vergleichbar, anders als die
  /// rohe Outperformance. Einträge ohne Perzentil stehen hinten, unter sich
  /// nach [BestenlisteEintrag.scoreVsInvestor] sortiert.
  List<BestenlisteEintrag> get eintraege => List.unmodifiable(_eintraege);

  void _laden() {
    final roh = _prefs.getString(_schluessel);
    if (roh == null || roh.isEmpty) return;
    try {
      _eintraege = (jsonDecode(roh) as List)
          .cast<Map<String, dynamic>>()
          .map(BestenlisteEintrag.vonJson)
          .toList();
      _sortieren();
    } catch (_) {
      // Beschädigter Eintrag darf die App nicht blockieren.
      _eintraege = [];
    }
  }

  void _sortieren() {
    _eintraege.sort((a, b) {
      if (a.perzentil == null && b.perzentil == null) {
        // Tiebreaker unter Alteinträgen ohne Perzentil.
        return b.scoreVsInvestor.compareTo(a.scoreVsInvestor);
      }
      if (a.perzentil == null) return 1;
      if (b.perzentil == null) return -1;
      return b.perzentil!.compareTo(a.perzentil!);
    });
  }

  Future<void> hinzufuegen(BestenlisteEintrag eintrag) async {
    _eintraege.add(eintrag);
    _sortieren();
    if (_eintraege.length > maxEintraege) {
      _eintraege = _eintraege.sublist(0, maxEintraege);
    }
    await _prefs.setString(
      _schluessel,
      jsonEncode(_eintraege.map((e) => e.zuJson()).toList()),
    );
    notifyListeners();
  }

  /// Platz (1-basiert) eines Eintrags, oder null.
  int? platzVon(BestenlisteEintrag eintrag) {
    final i = _eintraege.indexOf(eintrag);
    return i < 0 ? null : i + 1;
  }
}
