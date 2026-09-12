import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/erfolge.dart';
import '../domain/kursreihe.dart';

/// Flutter/SharedPreferences-Schicht über der reinen Domain-Logik in
/// `lib/domain/erfolge.dart` – bewusst getrennt, damit die Kriterien selbst
/// ohne Flutter-Abhängigkeit testbar bleiben.
class ErfolgeRepository extends ChangeNotifier {
  static const String _freigeschaltetSchluessel = 'erfolge_freigeschaltet_v1';
  static const String _scrollzaehlerSchluessel = 'erfolge_scrollzaehler_v1';

  final SharedPreferences _prefs;
  final Set<ErfolgId> _freigeschaltet = {};
  int _scrollZaehler = 0;

  ErfolgeRepository(this._prefs) {
    _laden();
  }

  Set<ErfolgId> get freigeschaltet => Set.unmodifiable(_freigeschaltet);

  void _laden() {
    final roh = _prefs.getStringList(_freigeschaltetSchluessel);
    if (roh != null) {
      for (final name in roh) {
        try {
          _freigeschaltet.add(ErfolgId.values.byName(name));
        } catch (_) {
          // Unbekannter/veralteter Erfolgsname -> ignorieren, App nicht blockieren.
        }
      }
    }
    _scrollZaehler = _prefs.getInt(_scrollzaehlerSchluessel) ?? 0;
  }

  Future<void> _speichereFreigeschaltet() =>
      _prefs.setStringList(_freigeschaltetSchluessel, _freigeschaltet.map((e) => e.name).toList());

  /// Einmal pro Bildschirmaufruf, wenn bis zum Ende der Auswertung gescrollt
  /// wurde. Gibt die in diesem Aufruf neu freigeschalteten Erfolge zurück.
  Future<List<ErfolgId>> vermerkeAuswertungGescrollt() async {
    _scrollZaehler++;
    await _prefs.setInt(_scrollzaehlerSchluessel, _scrollZaehler);

    final neu = <ErfolgId>[];
    if (!_freigeschaltet.contains(ErfolgId.selbsterkenntnis) &&
        Erfolge.selbsterkenntnis(_scrollZaehler)) {
      _freigeschaltet.add(ErfolgId.selbsterkenntnis);
      neu.add(ErfolgId.selbsterkenntnis);
    }
    if (neu.isNotEmpty) {
      await _speichereFreigeschaltet();
      notifyListeners();
    }
    return neu;
  }

  /// Einmal pro abgeschlossener Runde, direkt nach dem neuen
  /// [SpielverlaufEintrag] (V11). Gibt die in diesem Aufruf neu
  /// freigeschalteten Erfolge zurück.
  Future<List<ErfolgId>> werteRundeAus({
    required Kursreihe reihe,
    required List<bool> investiertProTag,
    required double rundenjahre,
    required int anzahlVerkaeufe,
    required double scoreVsInvestor,
    required double? perzentil,
    required List<DateTime> startDatenAllerRunden,
    required List<double> marktRenditenAllerRunden,
    required int anzahlRundenGesamt,
  }) async {
    final kandidaten = <ErfolgId, bool>{
      ErfolgId.eisernehand: Erfolge.eiserneHand(reihe, investiertProTag),
      ErfolgId.nichtstun: Erfolge.nichtstun(rundenjahre, anzahlVerkaeufe),
      ErfolgId.derGlueckliche: Erfolge.derGlueckliche(scoreVsInvestor, perzentil),
      ErfolgId.zeitreisender: Erfolge.zeitreisender(startDatenAllerRunden),
      ErfolgId.alleWetter: Erfolge.alleWetter(marktRenditenAllerRunden),
      ErfolgId.vielspieler: Erfolge.vielspieler(anzahlRundenGesamt),
    };

    final neu = <ErfolgId>[];
    for (final entry in kandidaten.entries) {
      if (entry.value && !_freigeschaltet.contains(entry.key)) {
        _freigeschaltet.add(entry.key);
        neu.add(entry.key);
      }
    }
    if (neu.isNotEmpty) {
      await _speichereFreigeschaltet();
      notifyListeners();
    }
    return neu;
  }
}
