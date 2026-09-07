import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/kursreihe.dart';
import 'aktien_katalog.dart';
import 'kursdaten_codec.dart';

/// Lädt den Aktienkatalog und einzelne Kursreihen aus den App-Assets.
///
/// Bewusst faul: beim Start wird nur `index.json` (~2 KB) gelesen; die
/// eigentliche Kursdatei (~45 KB) erst beim Start einer Runde – und nur die
/// eine, die gespielt wird.
class KursdatenRepository {
  static const String _basis = 'assets/kurse';

  List<AktienEintrag>? _katalog;

  /// Liest index.json (einmalig, danach gecacht).
  Future<List<AktienEintrag>> katalog() async {
    if (_katalog != null) return _katalog!;
    final roh = await rootBundle.loadString('$_basis/index.json');
    final json = jsonDecode(roh) as Map<String, dynamic>;
    final liste = (json['aktien'] as List)
        .cast<Map<String, dynamic>>()
        .map(AktienEintrag.vonJson)
        .toList();
    _katalog = liste;
    return liste;
  }

  /// Lädt die Kursreihe einer Aktie.
  ///
  /// Aktuell ist nur der Pfad `quelle == "bundled"` implementiert. Für
  /// späteres Nachladen kommt hier ein `remote`-Zweig dazu, ohne dass sich
  /// Aufrufer ändern müssen.
  Future<Kursreihe> lade(AktienEintrag eintrag) async {
    switch (eintrag.quelle) {
      case 'bundled':
        final daten = await rootBundle.load('$_basis/${eintrag.datei}');
        return KursdatenCodec.dekodiere(daten);
      default:
        throw UnsupportedError(
          'Quelle "${eintrag.quelle}" wird noch nicht unterstützt.',
        );
    }
  }

  /// Zufällige Aktie mit mindestens [minJahre] Jahren Historie.
  ///
  /// Ist [gruppe] gesetzt (z. B. "Welt-ETF"), wird nur innerhalb dieser
  /// Gruppe gewählt. `null` bedeutet "alle Gruppen gemeinsam" (Standard).
  AktienEintrag zufall(List<AktienEintrag> katalog, Random random,
      {double minJahre = 10, String? gruppe}) {
    final passendeGruppe =
        gruppe == null ? katalog : katalog.where((a) => a.gruppe == gruppe).toList();
    final basis = passendeGruppe.isEmpty ? katalog : passendeGruppe;
    final geeignet = basis.where((a) => a.spanneJahre >= minJahre).toList();
    final quelle = geeignet.isEmpty ? basis : geeignet;
    return quelle[random.nextInt(quelle.length)];
  }
}
