import 'dart:math';

import 'kursreihe.dart';

/// Ergebnis der Rundenauswahl: welcher Ausschnitt gespielt wird.
class RundenAuswahl {
  final Kursreihe ausschnitt;
  final int vonIndex;
  final int bisIndex;

  /// Bis zu ein Kalenderjahr **vor** [ausschnitt] – reine Anzeige für den
  /// Countdown, damit der Spieler vor der Investitionsentscheidung einen
  /// Vorlauf sieht. Kürzer, wenn die Kursreihe nicht so weit zurückreicht.
  /// Fließt nicht in die Simulation oder Wertung ein.
  final Kursreihe vorlauf;

  const RundenAuswahl(this.ausschnitt, this.vonIndex, this.bisIndex, this.vorlauf);
}

/// Wählt den (dem Spieler verborgenen) Zeitraum einer Runde.
/// Port von `SpielService.waehleStartdatum` / `berechneEnddatum`.
///
/// Reines Dart – kein Flutter. [Random] wird injiziert, damit Tests
/// mit festem Seed reproduzierbar sind.
class RundenWaehler {
  /// So weit muss der Startzeitpunkt mindestens zurückliegen.
  static const int minJahreZurueck = 10;

  /// Eine Runde braucht mindestens so viele Handelstage.
  static const int minHandelstage = 250;

  final Random random;

  RundenWaehler([Random? random]) : random = random ?? Random();

  /// Wählt einen Ausschnitt mit [rundenJahre] Länge, dessen Start so liegt,
  /// dass danach noch genügend Historie folgt.
  /// Liefert null, wenn die Reihe zu kurz ist.
  RundenAuswahl? waehle(Kursreihe reihe, {int rundenJahre = 10}) {
    if (reihe.laenge < minHandelstage) return null;

    final spaetesterStart = reihe.letzterTag - (rundenJahre * 365.25).round();
    if (spaetesterStart < reihe.ersterTag) return null;

    final spanne = spaetesterStart - reihe.ersterTag;
    final startTag = reihe.ersterTag + (spanne <= 0 ? 0 : random.nextInt(spanne + 1));

    final von = reihe.binaereSuche(startTag);
    final zielEnde = reihe.epochTag(von) + (rundenJahre * 365.25).round();
    var bis = reihe.binaereSuche(zielEnde);
    if (bis > reihe.laenge) bis = reihe.laenge;
    if (bis - von < minHandelstage) return null;

    final vorlaufStartTag = reihe.epochTag(von) - 365;
    final vorlaufVon = reihe.binaereSuche(vorlaufStartTag).clamp(0, von);
    final vorlauf = reihe.ausschnitt(vorlaufVon, von);

    return RundenAuswahl(reihe.ausschnitt(von, bis), von, bis, vorlauf);
  }
}
