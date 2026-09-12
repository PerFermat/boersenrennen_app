import 'dart:typed_data';

/// Eine Kursreihe als kompakte Typed Arrays, plus günstige Ausschnitte.
///
/// Datumsangaben sind **Epochtage** (Tage seit 1970-01-01, UTC) – bewusst als
/// int, nicht als DateTime: Differenzen bleiben so frei von Zeitzonen- und
/// Sommerzeit-Effekten, was für die taggenaue Verzinsung wichtig ist.
///
/// Reines Dart – kein Flutter.
class Kursreihe {
  final Int32List _epochTage;
  final Float64List _kurse;

  /// Sichtbarer Bereich [_von, _bis) in den obigen Arrays.
  final int _von;
  final int _bis;

  Kursreihe._(this._epochTage, this._kurse, this._von, this._bis);

  factory Kursreihe(Int32List epochTage, Float64List kurse) {
    assert(epochTage.length == kurse.length);
    return Kursreihe._(epochTage, kurse, 0, epochTage.length);
  }

  /// Bequemer Konstruktor für Tests.
  factory Kursreihe.ausListen(List<int> epochTage, List<double> kurse) =>
      Kursreihe(Int32List.fromList(epochTage), Float64List.fromList(kurse));

  int get laenge => _bis - _von;

  int epochTag(int i) => _epochTage[_von + i];

  double kurs(int i) => _kurse[_von + i];

  int get ersterTag => epochTag(0);

  int get letzterTag => epochTag(laenge - 1);

  /// Ausschnitt ohne Kopie – teilt sich die Arrays mit dem Original.
  /// [von] == [bis] ergibt eine leere Reihe (z. B. wenn kein Vorlauf existiert).
  Kursreihe ausschnitt(int von, int bis) {
    assert(von >= 0 && bis <= laenge && von <= bis);
    return Kursreihe._(_epochTage, _kurse, _von + von, _von + bis);
  }

  /// Unabhängige Kopie des **sichtbaren** Ausschnitts. Im Gegensatz zu
  /// [ausschnitt] werden die Daten tatsächlich kopiert – nötig, bevor eine
  /// Kursreihe eine Isolate-Grenze überquert (z. B. für `compute()`), weil
  /// sonst über die geteilten Arrays unnötig die komplette zugrunde liegende
  /// Historie mitkopiert/serialisiert würde.
  Kursreihe materialisiert() {
    final epochTage = Int32List(laenge);
    final kurse = Float64List(laenge);
    for (var i = 0; i < laenge; i++) {
      epochTage[i] = epochTag(i);
      kurse[i] = kurs(i);
    }
    return Kursreihe(epochTage, kurse);
  }

  /// Kleinster Index, dessen Epochtag >= [zielTag] ist; sonst [laenge].
  int binaereSuche(int zielTag) {
    var lo = 0, hi = laenge;
    while (lo < hi) {
      final mitte = (lo + hi) >> 1;
      if (epochTag(mitte) < zielTag) {
        lo = mitte + 1;
      } else {
        hi = mitte;
      }
    }
    return lo;
  }

  static final DateTime _epoche = DateTime.utc(1970, 1, 1);

  static DateTime zuDatum(int epochTag) =>
      _epoche.add(Duration(days: epochTag));

  static int zuEpochTag(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).difference(_epoche).inDays;
}
