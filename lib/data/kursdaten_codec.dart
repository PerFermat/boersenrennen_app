import 'dart:typed_data';

import '../domain/kursreihe.dart';

/// Dekodiert das kompakte Binärformat aus `tools/export_kursdaten.py`.
///
/// Aufbau (little-endian):
/// ```
/// 'BRK1'                      4 B  Magic
/// uint32 basisEpochTag             Epochtag des ersten Kurses
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

    final basis = daten.getUint32(4, Endian.little);
    final anzahl = daten.getUint32(8, Endian.little);

    var offset = 12;
    final erwartet = offset + anzahl * 2;
    final padding = (4 - (anzahl * 2) % 4) % 4;
    if (daten.lengthInBytes < erwartet + padding + anzahl * 4) {
      throw const FormatException('Kursdatei unvollständig.');
    }

    final epochTage = Int32List(anzahl);
    for (var i = 0; i < anzahl; i++) {
      epochTage[i] = basis + daten.getUint16(offset + i * 2, Endian.little);
    }

    offset = erwartet + padding;
    final kurse = Float64List(anzahl);
    for (var i = 0; i < anzahl; i++) {
      // Explizite Schleife statt Float32List.view: unabhängig von der
      // Byte-Reihenfolge der Plattform und ohne Alignment-Annahmen.
      kurse[i] = daten.getFloat32(offset + i * 4, Endian.little);
    }

    return Kursreihe(epochTage, kurse);
  }
}
