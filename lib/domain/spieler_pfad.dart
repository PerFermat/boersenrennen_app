import 'kursreihe.dart';
import 'spiel_konfiguration.dart';

/// Eine einzelne geplante Handelsaktion für [simuliereSpielerpfad]. Die Liste
/// muss aufsteigend nach [tagIndex] sortiert übergeben werden; **mehrere**
/// Aktionen am selben [tagIndex] sind erlaubt und werden in Listenreihenfolge
/// ausgeführt – der Spieler kann an einem Tag kaufen und wieder verkaufen.
class GeplanteAktion {
  final int tagIndex;
  final bool istKauf;

  const GeplanteAktion(this.tagIndex, this.istKauf);
}

/// Ergebnis der schlanken Wiedergabe – nur Cash/Stück des Spielers.
class SpielerPfadErgebnis {
  final double cash;
  final double stueck;

  const SpielerPfadErgebnis(this.cash, this.stueck);

  double endwert(double kurs) => cash + stueck * kurs;
}

int _ym(int epochTag) {
  final d = Kursreihe.zuDatum(epochTag);
  return d.year * 12 + d.month;
}

/// Schlanke Simulation **nur** des Spieler-Cash/Stück-Pfads über [reihe] – der
/// gemeinsame Kern für die Gegenfaktischen Referenzen der Rundenauswertung,
/// die Monte-Carlo-Einordnung und den „teuersten Klick". Bewusst ohne
/// Verzinsung, Allzeithoch, Stolpern und Investor-/Sicherheit-Buchhaltung:
/// für diese drei Anwendungsfälle wird ausschließlich der Spieler-Endwert
/// gebraucht, nie der Vergleich mit den anderen Strategien.
///
/// Startzustand ist implizit Cash ([SpielKonfiguration.startCash]) und nicht
/// investiert – eine Aktion bei `tagIndex == 0` entspricht der
/// Countdown-Entscheidung. Monatliche Einzahlungen folgen exakt der Regel aus
/// `RennenEngine._einzahlung()` (slippage-frei, nur wenn zu dem Zeitpunkt
/// investiert).
///
/// [mitSlippage]: `true` wendet `cfg.slippage` auf jede Aktion an – repliziert
/// `RennenEngine.kaufen()`/`verkaufen()` exakt, für Fälle, in denen echte
/// Ausführungskosten Teil der Fragestellung sind (Monte-Carlo, teuerster
/// Klick). `false` lässt Aktionen kostenfrei zu – für rein timing-bezogene
/// Gegenfaktische Referenzen, bei denen Slippage die Fragestellung nur
/// verzerren würde.
SpielerPfadErgebnis simuliereSpielerpfad({
  required Kursreihe reihe,
  required SpielKonfiguration cfg,
  required List<GeplanteAktion> aktionen,
  bool mitSlippage = true,
}) {
  var cash = cfg.startCash;
  var stueck = 0.0;
  var investiert = false;
  var letzterYM = _ym(reihe.epochTag(0));
  var aktionsIndex = 0;

  for (var i = 0; i < reihe.laenge; i++) {
    final kurs = reihe.kurs(i);

    if (i > 0) {
      final ym = _ym(reihe.epochTag(i));
      if (ym != letzterYM) {
        letzterYM = ym;
        if (investiert) {
          stueck += cfg.monatsEinzahlung / kurs;
        } else {
          cash += cfg.monatsEinzahlung;
        }
      }
    }

    // `while`, nicht `if`: bleiben mehrere Aktionen auf demselben Tag liegen,
    // würde ein `if` den Listenkopf dauerhaft auf einem bereits vergangenen
    // Tag stehen lassen – ab da wäre jede weitere Aktion still verworfen.
    while (aktionsIndex < aktionen.length && aktionen[aktionsIndex].tagIndex == i) {
      final aktion = aktionen[aktionsIndex++];
      if (aktion.istKauf) {
        final ausfuehrungsKurs = mitSlippage ? kurs * (1 + cfg.slippage) : kurs;
        stueck += cash / ausfuehrungsKurs;
        cash = 0;
        investiert = true;
      } else {
        final ausfuehrungsKurs = mitSlippage ? kurs * (1 - cfg.slippage) : kurs;
        cash += stueck * ausfuehrungsKurs;
        stueck = 0;
        investiert = false;
      }
    }
  }

  return SpielerPfadErgebnis(cash, stueck);
}
