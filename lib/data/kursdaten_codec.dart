import 'dart:typed_data';

import '../domain/kursreihe.dart';

/// Dekodiert das kompakte Binärformat aus `tools/export_kursdaten.py`.
///
/// Aufbau (little-endian):
/// ```
/// 'BRK1'                      4 B  Magic
/// int32  basisEpochTag             Epochtag des ersten Kurses (ggf. negativ)
/// uint32 anzahl
/// uint16[anzahl] tagOffset         Tage seit Basistag, streng aufsteigend
/// (Padding auf 4-Byte-Grenze)
/// float32[anzahl] schlusskurs
/// ```
///
/// Absolute Offsets statt Deltas – dadurch bleibt die Suche nach dem
/// Startdatum eine Binärsuche in O(log n).
///
/// Reines Dart – kein Flutter.
class KursdatenCodec {
  static const int _magic = 0x314B5242; // 'BRK1' little-endian

  static Kursreihe dekodiere(ByteData daten) {
    if (daten.lengthInBytes < 12) {
      throw const FormatException('Kursdatei zu kurz.');
    }
    if (daten.getUint32(0, Endian.little) != _magic) {
      throw const FormatException('Ungültige Kursdatei (Magic erwartet BRK1).');
    }

    // Signed, weil Reihen vor dem 1970-01-01 (S&P 500 ab 1927) einen negativen
    // Basis-Epochtag haben.
    //
    // Mit getUint32 käme hier dasselbe heraus: der Wert landet unten in einem
    // Int32List, und dessen Abschneiden auf 32 Bit ist arithmetisch genau die
    // Vorzeichen-Interpretation. Darauf soll sich aber niemand verlassen
    // müssen, der die Stelle liest – das Feld *ist* vorzeichenbehaftet, also
    // wird es auch so gelesen.
    final basis = daten.getInt32(4, Endian.little);
    final anzahl = daten.getUint32(8, Endian.little);

    // Eine leere Reihe ließe `RennenEngine` sofort über `reihe.kurs(0)`
    // stolpern – hier abzubrechen benennt die Ursache statt eines RangeError
    // tief in der Simulation.
    if (anzahl == 0) {
      throw const FormatException('Kursdatei enthält keine Kurse.');
    }

    var offset = 12;
    final erwartet = offset + anzahl * 2;
    final padding = (4 - (anzahl * 2) % 4) % 4;
    if (daten.lengthInBytes < erwartet + padding + anzahl * 4) {
      throw const FormatException('Kursdatei unvollständig.');
    }

    // Streng aufsteigende Epochtage sind die Invariante, auf der
    // `Kursreihe.binaereSuche` beruht. Ohne Prüfung liefert eine beschädigte
    // oder halb geschriebene Datei keinen Absturz, sondern still falsche
    // Kurse – und damit falsche Renditen. Der Durchlauf kostet nichts
    // Zusätzliches, die Schleife läuft ohnehin.
    final epochTage = Int32List(anzahl);
    for (var i = 0; i < anzahl; i++) {
      epochTage[i] = basis + daten.getUint16(offset + i * 2, Endian.little);
      if (i > 0 && epochTage[i] <= epochTage[i - 1]) {
        throw FormatException(
          'Epochtage nicht streng aufsteigend an Index $i '
          '(${epochTage[i - 1]} -> ${epochTage[i]}).',
        );
      }
    }

    offset = erwartet + padding;
    final kurse = Float64List(anzahl);
    for (var i = 0; i < anzahl; i++) {
      // Explizite Schleife statt Float32List.view: unabhängig von der
      // Byte-Reihenfolge der Plattform und ohne Alignment-Annahmen.
      final kurs = daten.getFloat32(offset + i * 4, Endian.little);
      // Ein Kurs <= 0 (oder NaN) würde in der Simulation zu Division durch
      // null bzw. NaN-Depotwerten führen, die sich lautlos fortpflanzen.
      if (!(kurs > 0)) {
        throw FormatException('Unbrauchbarer Kurs $kurs an Index $i.');
      }
      kurse[i] = kurs;
    }

    return Kursreihe(epochTage, kurse);
  }
}
