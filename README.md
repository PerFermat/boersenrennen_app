# Börsenrennen – Handy-App

Ein Lernspiel für die Börse als Flutter-App (Android, iOS-kompatible Codebasis).
Drei Anlagestrategien treten auf **derselben**, dem Spieler verborgenen Zufallsaktie
über einen zufälligen historischen Zeitraum als Wettrennen gegeneinander an.

| Läufer | Verhalten |
|--------|-----------|
| 🟢 **Du** | handelst manuell („Alles kaufen" / „Alles verkaufen"), 0,5 % Slippage nur auf diese manuellen Entscheidungen – nicht auf die Sparplan-Einzahlungen. Neue Einzahlungen fließen in die Position, wenn du investiert bist – sonst bleiben sie Cash. |
| 🔵 **Investor** | kauft jede Einzahlung sofort, bleibt voll investiert (Buy-and-Hold, ohne Slippage – die Benchmark). |
| 🟡 **Sicherheit** | legt alles zu einem festen, vor der Runde gewählten Zins an. |
| 🟣 **Würfel-Investor** (optional, Default an) | schaltet bei jedem Monatswechsel mit 15 % Wahrscheinlichkeit zwischen investiert und Cash um – reiner Zufall, keine Strategie. Zahlt dieselbe Slippage und Steuer wie der Spieler, sonst wäre der Vergleich unfair. Gewinnt er gelegentlich, ist das der Punkt: es zerstört die Illusion, ein Sieg beweise Können. |

Alle starten mit 1000 €, monatlich kommen 100 € dazu. Im Startmenü lässt sich
wählen, aus welcher Gruppe die Zufallsaktie kommt: **Einzelaktien**, **Welt-ETFs**
(z. B. Vanguard Total World, MSCI ACWI/World) oder **Themen/Länder-ETFs**
(Länder wie Japan/Brasilien/Indien, Sektoren wie Technologie/Energie/Gesundheit) –
oder ganz zufällig aus allen Gruppen.

**Bildschirmaufbau:** Im oberen Viertel läuft der Kursverlauf mit. Darunter die
Rennbahn: die horizontale Position zeigt den Depotwert, die **Laufgeschwindigkeit
der Figuren folgt der Kurshöhe** relativ zum Allzeithoch (Marktstimmung – für alle
drei gleich). Wer nicht investiert ist, trabt statt zu sprinten. Der Kursverlauf ist
**grün für investierte, rot für nicht investierte Phasen** – dieselbe Farbsprache wie
die Kaufen-/Verkaufen-Knöpfe. Gefärbt wird **abschnittsweise nach Tageshistorie**:
war man im ersten Jahr investiert, bleibt dieser Teil des Charts dauerhaft grün, auch
wenn später verkauft wird – die Farbe eines vergangenen Abschnitts ändert sich nie
rückwirkend. Die Rennbahn selbst bleibt **immer mittig in der
Graslandschaft**, auch wenn beim Herauszoomen oben und unten mehr freies Feld
sichtbar wird.

Zwei weitere Kurs-Reaktionen: **Rennstreifen** hinter einem sprintenden Läufer
gibt es nur, wenn der Kurs zusätzlich im letzten Jahr um mehr als 10 % gestiegen
ist – nicht schon durch bloßes Investiertsein. Fällt der Kurs dagegen innerhalb
eines Monats um mehr als 10 %, **stolpert** der betroffene Läufer kurz (nur wer
zu dem Zeitpunkt tatsächlich investiert ist – die Sicherheit trägt kein
Kursrisiko und stolpert nie). Damit das Bild bei längeren Abwärtsphasen nicht
unruhig wird, passiert das höchstens einmal pro simuliertem Jahr
(`RennenEngine.stolperKuehlzeitTage`). Beide Effekte greifen bei Bedarf auf den
Countdown-Vorlauf zurück, damit sie auch gleich zu Rundenbeginn funktionieren.

Das **Kalenderdatum wird bewusst nicht angezeigt** – wer weiß, dass gerade 1999,
2008 oder 2020 läuft, kennt den kommenden Crash. Stattdessen steht dort der
Rundenfortschritt („Jahr 3 von 10").

**Countdown vor dem Start:** Bevor die Runde beginnt, läuft 10 Sekunden ein
Countdown, während dessen bereits der Kursverlauf des **letzten Jahres vor
Rundenbeginn** zu sehen ist. In dieser Zeit lässt sich sofort investieren oder
bewusst abwarten; reagiert niemand, startet die Runde wie gewohnt in Cash. Diese
Vorgeschichte ist reine Anzeige – sie zählt nicht zur Simulation oder Wertung.
Ein **„Runde beenden"**-Knopf wertet die Runde jederzeit vorzeitig mit dem
aktuellen Stand aus, und während gespielt wird, verhindert `wakelock_plus`, dass
der Bildschirm abdunkelt.

### Die scrollende Welt

Die Strecke ist eine Welt in **Euro-Koordinaten** (`lib/spiel/kamera.dart`): Die
Läufer stehen an ihrem Depotwert, die Welt scrollt an ihnen vorbei. Daraus ergibt
sich alles Weitere von selbst:

- **Meilenstein-Schilder** (1.000 €, 1.100 € …) stehen an festen Euro-Positionen und
  laufen dadurch mit. Von jedem Schild führt eine dünne Markierung durch alle Bahnen.
- **Zoom**: Je weiter Erster und Letzter auseinanderliegen, desto breiter das
  Fenster – und desto **kleiner die Figuren und schmaler die Bahnen**
  (Faktor 1.0 bis 0.42). Die frei werdende Fläche öffnet sich als Feld zwischen
  Horizont und Strecke; der Schilderstreifen wandert mit den Bahnen nach unten.
- **Parallax** über unterschiedliche Scroll-Anteile: Schilder und Bahntextur 1.0,
  Bäume 0.45, Wolken 0.15 (plus leichte Eigendrift).

### Schwenk und Zoom sind entkoppelt

Das ist der Kern der ruhigen Darstellung. Beide Zeiten stehen als Konstanten in
`Kamera`:

| Konstante | Wert | Wirkt auf |
|---|---|---|
| `standardZoomSekunden` | 2.0 s | Fensterbreite **und** Figurengröße |
| `standardSchwenkSekunden` | 0.25 s | Bildmitte |
| `RennenController.laeuferGlaettungSekunden` | 0.30 s | Anzeigeposition je Läufer |

Nach der jeweiligen Zeit ist ein Übergang zu 98 % vollzogen; die Glättungsrate wird
daraus berechnet, die Werte sind also direkt in Sekunden ablesbar.

Warum die Trennung nötig ist: Steigt der Kurs, wandern alle drei Depots **gemeinsam**
nach rechts. Schwenkt die Kamera flott mit, bleiben die Läufer stehen und nur die Welt
zieht vorbei. Hing der Schwenk dagegen am trägen Zoom, rutschte das ganze Feld über
den Schirm – und das Sicherheitsnetz der Kamera riss es periodisch zurück, was als
Sägezahn sichtbar wurde. Zusätzlich wird die Anzeigeposition jedes Läufers geglättet:
Bei Tempo 30 rückt ein Frame ~0,5 Handelstage vor, was ungefiltert leicht 50 px
Sprung bedeutet. Die Kamera wird aus den **geglätteten** Werten gespeist, damit ihr
Sicherheitsnetz nie gegen die Glättung arbeitet.

### Kulisse mit Lebenszyklus

Schilder, Bäume und Wolken sind Entitäten (`lib/spiel/weltkulisse.dart`), keine
Modulo-Kacheln. Leitregel: **Nichts erscheint oder verschwindet mitten im Bild.**

- Elemente betreten die Bühne nur außerhalb des Bildrands – rechts bei steigenden,
  links bei fallenden Kursen – und behalten ihre beim Eintritt gewürfelten
  Eigenschaften bis zum Verlassen.
- Rücken Schilder beim Herauszoomen zu dicht zusammen, wird jedes zweite
  ausgeblendet und **bleibt weg** (`_ausgeduennt`), auch wenn später wieder Platz wäre.
- **Ausnahme:** Sinkt die Zahl sichtbarer Schilder unter `mindestensSichtbar` (3),
  wird auch innerhalb des Bildes nachgefüllt – sonst verhungert die Bühne, wenn nach
  dem Ausdünnen kein Nachschub von außen mehr kommt. Die Schilder blenden sich dabei
  weich ein. Wie oft das nötig war, zählt `notbefuellungen`.
- Die Schrittweite hat eine **Hysterese**: Ohne sie änderte sie sich bei jeder
  Zoom-Regung, und weil jedes Schild auf dem Raster seiner Entstehungszeit sitzt,
  standen krumme Reihen wie 2.400 / 3.250 / 4.000 im Bild.

Bäume und Wolken sind bildschirm-verankert und wandern pro Frame um einen Bruchteil
des Kameraversatzes – dadurch immun gegen Zoom- und Schrittweitenwechsel. Nur das
Gras bleibt gekachelt (zu viele Halme für Entitäten), scrollt aber über einen
**inkrementell aufsummierten** Versatz und springt deshalb ebenfalls nicht.

**Wertung:** Rankingrelevant ist die Outperformance gegenüber dem Investor
(`(spieler − investor) / investor × 100`), weil Zufallsaktie und Zufallszeitraum
absolute Endbeträge unvergleichbar machen. Der Vergleich mit der Sicherheit wird
zusätzlich informativ angezeigt.

### Rundenauswertung

Der Ergebnis-Screen zeigt nach jeder Runde mehr als nur die drei Endbeträge
(`lib/domain/auswertung.dart`, `RundenAuswertung.aus(engine)`):

- **Kennzahlen**: Tage investiert/außen, Anzahl Käufe/Verkäufe, durchschnittliche
  Haltedauer, bester/schlechtester Trade, betragsgewichteter Ø Kauf- und
  Verkaufskurs.
- **Verpasste und vermiedene Börsentage – symmetrisch**: Für jeden Tag außerhalb
  des Marktes wird gezeigt, ob er ein verpasster Gewinn- oder ein vermiedener
  Verlusttag war (nur die verpassten Gewinntage zu zeigen wäre Rosinenpickerei).
  Dazu eine Cluster-Analyse (verpasste Top-Tage liegen oft kurz nach einem
  Crash-Tag) und eine Gegenrechnung gegen eine durchgehend investierte Referenz.
- **Monte-Carlo-Einordnung** (`lib/domain/monte_carlo.dart`): 1000 Zufallsläufe mit
  derselben Kursreihe und **derselben Anzahl Trades** wie der Spieler zeigen, wie
  gut das Timing im Vergleich zu zufälligem Handeln war. Läuft über `compute()`
  in einem Isolate, damit die Oberfläche nicht blockiert.
- **„Der teuerste Klick"** (`lib/domain/auswertung.dart`, `simuliereOhneTrade`):
  Für jeden Trade wird die Runde ohne genau diese eine Entscheidung neu
  simuliert – die größte Verschlechterung ist der teuerste Klick, hat keine
  Entscheidung geschadet, wird stattdessen „Dein bester Klick" gezeigt.

Alle drei zusätzlichen Berechnungen (Gegenrechnungen in V7, Monte-Carlo, teuerster
Klick) teilen sich einen gemeinsamen, schlanken Kern in `lib/domain/spieler_pfad.dart`
(`simuliereSpielerpfad`): nur Spieler-Cash/-Stück anhand einer Liste geplanter
Kauf-/Verkaufstage, ohne Investor/Sicherheit/Zinsen/Stolpern – das reicht für alle
drei Fragestellungen und spart, Investor/Sicherheit tausendfach mitzurechnen.

Zwei Eigenschaften dieses Kerns sind nicht offensichtlich und deshalb durch Tests
festgenagelt:

- Er verarbeitet **mehrere Aktionen am selben Handelstag** in Listenreihenfolge.
  Der Spieler kann an einem Tag kaufen und wieder verkaufen; wurde pro Tag nur
  eine Aktion konsumiert, blieb der Listenkopf danach dauerhaft auf einem
  vergangenen Tag stehen und jede weitere Entscheidung fiel still unter den Tisch.
- Er kennt **keine Abgeltungsteuer**. Wo sein Ergebnis gegen den echten Endwert
  gestellt wird (Monte-Carlo-Perzentil, teuerster Klick), wird der echte Endwert
  deshalb um die gezahlte Steuer bereinigt – sonst hätte der Vergleichslauf einen
  Vorteil, den er nur der fehlenden Modellierung verdankt. Bei `steuernAktiv:
  false` (Default) ist diese Korrektur exakt 0.

### Wie viel war Timing, wie viel Zufall? (kontrafaktische Vergleiche)

Drei weitere Was-wäre-wenn-Simulationen, alle über denselben `simuliereSpielerpfad`-Kern:

- **Umgekehrt gehandelt** (`simuliereUmgekehrt`): jeder Kauf wird zu einem Verkauf
  und umgekehrt, an denselben Tagen.
- **Um X Handelstage verschoben** (`simuliereMitVersatz`, ±20/±60 Tage): dieselben
  Entscheidungen, nur zeitlich versetzt. Trades, die dadurch vor Rundenbeginn fallen
  oder über das Rundenende hinausrutschen, fallen ersatzlos weg.
- **Ohne eigene Entscheidungen** (`simuliereOhneEntscheidungen`): nur der
  Anfangszustand (investiert oder nicht) wird bis zum Schluss durchgehalten.

`RundenAuswertung.timingWarUeberwiegendRauschen` vergleicht die Streuung dieser
Verschiebungs-Ergebnisse mit dem tatsächlichen Abstand zum Investor – nur wenn die
Streuung größer ist, war das Ergebnis überwiegend Zufall und nicht Timing-Qualität.

### Behavior Gap: Marktrendite gegen die eigene Rendite

`lib/domain/auswertung.dart` (`geldgewichteteRendite`, `zeitgewichteteRendite`)
vergleicht zwei Renditebegriffe über dieselbe Runde:

- **Zeitgewichtete Rendite des Titels** (CAGR der rohen Kursreihe) – wie der Markt
  sich entwickelt hat, unabhängig vom Timing.
- **Geldgewichtete Rendite des Spielers** (interner Zinsfuß/IRR über Startkapital
  und alle Einzahlungen, per Bisektion auf `[-0,99; 10,0]` – Newton ist hier
  ungeeignet, da das Vorzeichenmuster der Zahlungsströme mehrere Nullstellen
  zulassen kann) – was das eigene Geld tatsächlich verdient hat.

Die Differenz ist die **Behavior Gap**: jede Kapitalzufuhr (Start + jede Einzahlung)
wird mit der Marktrendite auf den letzten simulierten Tag aufgezinst und mit dem
tatsächlichen Endwert verglichen. Der ganze Block bleibt ausgeblendet, wenn keine
der beiden Renditen bestimmbar ist (z. B. eine reine Cash-Runde ohne Zahlungsstrom-
Vorzeichenwechsel).

### Abgeltungsteuer (optionaler Schalter, Default aus)

Der stärkste Hebel gegen Market Timing: Jeder Verkauf des Spielers löst Steuer auf
den realisierten Gewinn aus (25 % + 5,5 % Soli = 26,375 %, Teilfreistellung 30 %
bei ETFs, Sparerpauschbetrag 1.000 €/Jahr, Verlusttopf innerhalb der Runde). Der
Investor zahlt während der Runde nichts – am Ende steht seine **latente** Steuer
nur informativ daneben, wird aber nie von seinem Endwert abgezogen, sonst würde
Score und Bestenliste rückwirkend verzerrt. Die Sicherheit versteuert ihre Zinsen
zum Jahreswechsel. Bewusst **nicht** modelliert: die Vorabpauschale auf
thesaurierende Fonds (`lib/domain/spiel_konfiguration.dart`).

Der ausgewiesene Steuernachteil gegenüber dem Investor zählt auf der Spielerseite
**gezahlte plus latente** Steuer (`RennenEngine.latenteSteuerSpieler`). Nur die
gezahlte zu nehmen wäre asymmetrisch: wer investiert ins Ziel läuft, genießt
dieselbe Stundung wie der Investor und stünde sonst als steuerlich günstiger da,
als er ist.

### Inflation und reale Kaufkraft (`lib/domain/inflation.dart`)

Neben jedem nominalen Endbetrag steht eine kleinere Zeile mit der realen
Kaufkraft – in Preisen des Rundenbeginns, nicht in heutigen Preisen. Die
Jahresteuerungsraten stammen vom Statistischen Bundesamt (Destatis); da die
App durchgängig in Euro anzeigt, auch für US-Titel, wird bewusst eine einzelne
deutsche Reihe verwendet statt länderspezifischer Inflation. Die **Wertung
bleibt nominal** – `Score.vsInvestor` ist ein Verhältnis zweier Werte desselben
Zeitraums, die Inflation kürzt sich heraus.

Die Tabelle endet früher als die Kursdaten. `Inflation.preisfaktorMitAbdeckung`
liefert deshalb neben dem Faktor auch den **Anteil abgedeckter Tage**; unter 95 %
blendet der Ergebnis-Screen den ganzen Kaufkraft-Block aus, statt eine zu niedrige
Teuerung – im Extremfall „0 %" – als Tatsache zu behaupten, die nur aus fehlenden
Daten stammt. Der Satz „real liegt die Sicherheit unter der Summe deiner
Einzahlungen" vergleicht außerdem gegen die **abgezinste** Einzahlungssumme: die
Beiträge fielen über zehn Jahre verteilt an und hatten nicht alle die Kaufkraft
des Rundenbeginns.

### Der Würfel-Investor (`RennenEngine.wuerfelAktiv`)

Technisch der aufwendigste Teil: Läufer-Anzahl und -Farben waren früher an
mehreren Stellen im Renderpfad fest auf drei verdrahtet. `lib/spiel/laeufer_daten.dart`
führt eine `LaeuferDaten`-Liste ein, über die `rennstrecke_painter.dart` und
`RennenController` jetzt generisch iterieren – bei deaktiviertem Schalter ist die
Liste exakt drei Elemente lang mit identischen Werten wie zuvor, die Darstellung
bleibt dadurch strukturell pixelgleich. Der Zufallsgenerator wird injiziert und
sein Seed in der Engine gespeichert, damit eine Trade-Folge reproduzierbar bleibt.

### Verhaltensprofil über alle Runden (`lib/data/spielverlauf.dart`, „Mein Profil")

Jede abgeschlossene Runde wird unabhängig von der Bestenliste in einem
rundenübergreifenden Protokoll erfasst (`SpielverlaufRepository`, Schlüssel
`spielverlauf_v1`, max. 200 Einträge). Abweichend von der Bestenliste – die nach
Punktzahl abschneidet – fällt hier bei Überschreiten der Grenze **chronologisch**
die älteste Runde heraus (FIFO): ein Verhaltensprofil soll die zuletzt gespielten
Runden zeigen, nicht die besten.

Drei zusätzliche Verhaltensmaße pro Runde (`RundenAuswertung`, `lib/domain/auswertung.dart`):
mittlerer Abstand zwischen einem Verkauf und dem folgenden Tiefpunkt bzw. einem
Kauf und dem folgenden Hochpunkt (je im 120-Handelstage-Fenster, am Rundenende
verkürzt), sowie der Anteil der Verkäufe kurz nach einem Crash-Tag.

Der **„Mein Profil"**-Screen aggregiert das über alle protokollierten Runden –
mit einer bewussten Ehrlichkeitsregel: Aggregate (Ø Perzentil, Sieg-Quote,
Perzentil-Histogramm) erscheinen erst ab 5 Runden, Verhaltenssätze erst ab
kumuliert 10 Verkäufen bzw. Käufen. Darunter liegt jeweils ein Hinweistext statt
einer statistisch nicht belastbaren Aussage.

### Erfolge – Prozess statt Ergebnis (`lib/domain/erfolge.dart`)

Sieben Erfolge, bewusst auf **Verhalten** statt auf einen guten Endstand
ausgelegt – wer den Investor schlägt, aber nur weil der Titel selbst gut lief,
verdient dafür keinen zusätzlichen Erfolg (siehe „Der Glückliche" unten):

| Erfolg | Kriterium |
|---|---|
| Eiserne Hand | Investiert geblieben, während der Kurs ≥30 % unter sein bisheriges Rundenhoch fiel. |
| Ruhe bewahrt | ≥10 Jahre gespielt, ohne ein einziges Mal zu verkaufen. |
| Der Glückliche | Investor geschlagen, obwohl das eigene Timing schlechter war als 80 % der Zufallsläufe mit gleich vielen Trades (Monte-Carlo-Perzentil <20). |
| Selbsterkenntnis | Zehnmal bis zum Ende der Auswertung gescrollt. |
| Zeitreisender | In ≥5 verschiedenen Jahrzehnten der Kursgeschichte gespielt. |
| Allwetter | Sowohl in einer Runde mit steigendem als auch mit fallendem Markt gespielt. |
| Vielspieler | ≥25 Runden gespielt. |

„Zeitreisender" und „Allwetter" beziehen sich auf die **gespielte historische
Periode** (das gezogene Startdatum bzw. die Marktentwicklung der Kursreihe), nicht
auf das reale Kalenderdatum des Spielens – passend zum „geheimer Zeitraum"-Kern
des Spiels. Die Kriterien selbst liegen in reinem Dart (`lib/domain/erfolge.dart`,
ohne Flutter-Import) und sind unabhängig von der SharedPreferences-Schicht
(`lib/data/erfolge_repository.dart`) testbar. Bewusste Scope-Entscheidung: kein
eigener Erfolge-Galerie-Screen – die Liste hängt kompakt unten am „Mein
Profil"-Screen.

### Bestenliste sortiert nach Perzentil statt Outperformance

Die Outperformance gegenüber dem Investor allein macht Runden über verschiedene
Titel und Zeiträume nicht fair vergleichbar – eine Verdopplung des Kurses ist in
manchen Zeiträumen trivial, in anderen fast unmöglich. Die Bestenliste sortiert
deshalb absteigend nach dem Monte-Carlo-**Perzentil** der Runde (normiert
innerhalb der eigenen Kursreihe/Trade-Anzahl). Einträge von vor diesem Update ohne
Perzentil stehen hinten, untereinander weiterhin nach der rohen Outperformance
sortiert.

## Technik

- **Flutter 3.47** / Dart 3.13, Rendering mit `CustomPainter` (kein Game-Engine-Overhead).
- **Vollständig offline**: 54 Titel (Einzelaktien, Welt-ETFs, Themen-/Länder-ETFs,
  Indizes, Rohstoffe) liegen als kompakte Binärdateien im App-Paket (~2,4 MB
  gesamt). Kein Server, kein Internet.
- **Lokale Bestenliste** in `shared_preferences`, max. 100 Einträge (score-sortiert
  abgeschnitten); daneben ein **Spielprotokoll** für das Verhaltensprofil, max. 200
  Einträge, aber chronologisch statt score-sortiert abgeschnitten.
- Laufzeit-Abhängigkeiten: `provider`, `shared_preferences`, `intl`,
  `wakelock_plus` (hält den Bildschirm während einer Runde wach).

### 60 fps ohne teure Rebuilds

Die Simulation ist ein reines Dart-Objekt ohne Flutter-Bezug. Pro Frame laufen
**zwei getrennte Kanäle**:

- `RepaintNotifier` → als `CustomPainter(repaint:)` übergeben. Das RenderObject
  zeichnet neu, **der Widget-Baum wird nicht gebaut**.
- HUD-Texte hängen an einem separaten, auf **~10 Hz gedrosselten** `ValueNotifier` –
  Währungsstrings 60-mal pro Sekunde zu formatieren wäre Verschwendung.

`build()` des Spielbildschirms läuft genau **einmal pro Runde**.

Weitere Vorkehrungen: `dt` ist auf 1/30 s gedeckelt und die Schritte pro Frame sind
begrenzt (sonst springt die Runde nach einer GC- oder Hintergrund-Pause um Monate);
die App pausiert automatisch beim Wechsel in den Hintergrund; gerechnet wird mit
**Epochtagen als Integer**, nicht mit `DateTime`-Differenzen (Zeitzonen/Sommerzeit).

## Struktur

```
lib/
├── domain/     reines Dart, keine Flutter-Imports -> unit-testbar
│   ├── rennen_engine.dart      Simulation (Port der erprobten rennen.js-Logik)
│   ├── kursreihe.dart          Typed Arrays, Ausschnitte ohne Kopie, Binärsuche
│   ├── runden_waehler.dart     Zufallszeitraum (Random injizierbar -> testbar)
│   ├── score.dart              die beiden Score-Formeln
│   ├── trade.dart              Protokoll einer manuellen Handelsentscheidung
│   ├── spieler_pfad.dart       schlanke Wiedergabe: Spieler-Pfad anhand Aktionsliste
│   ├── auswertung.dart         RundenAuswertung, verpasste/vermiedene Tage, teuerster Klick
│   ├── monte_carlo.dart        1000-Läufe-Einordnung, isolate-tauglich
│   ├── inflation.dart          Destatis-Jahresteuerung, taggenauer Kaufkraft-Faktor
│   ├── erfolge.dart            sieben Erfolgs-Kriterien, reine Funktionen
│   └── strategie.dart / spiel_konfiguration.dart
├── data/       Assets laden, Binärformat dekodieren; bestenliste/spielverlauf/erfolge_repository
├── spiel/      RennenController: Ticker, Tempo, Pause, Repaint/HUD-Kanäle; laeufer_daten.dart
├── render/     CustomPainter für Kurs-Chart, Rennbahn, Monte-Carlo- und Perzentil-Balken
├── screens/    Start, Rennen, Ergebnis, Bestenliste, Profil
├── ui/         CandyButton, DepotKarte, TempoRegler
└── theme/      Arcade-Farbpalette
tools/
└── export_kursdaten.py         yfinance -> assets/kurse/
```

## Kursdaten erzeugen

Die Assets liegen bereits im Projekt. Neu erzeugen (z. B. für aktuellere Kurse):

```bash
python3 -m venv .venv
./.venv/bin/pip install yfinance
./.venv/bin/python tools/export_kursdaten.py
```

Das Skript lädt ab 1995-01-01 mit `auto_adjust=True` (Dividenden eingerechnet, damit
Buy-and-Hold die echte Gesamtrendite abbildet) und schreibt je Aktie eine `.bin`
plus ein gemeinsames `index.json`. Der `AKTIEN_POOL` in
[`export_kursdaten.py`](tools/export_kursdaten.py) trägt für jeden Titel neben dem
Ticker auch eine **Gruppe** ein (`Einzelaktien` / `Welt-ETF` / `Themen-Länder-ETF` /
`Index-Rohstoff`) – darüber filtert das Startmenü.

### Historische Indexreihen vor 1995

Drei Indizes reichen bewusst weiter zurück als `START_DATUM`; die Ausnahmen stehen
in `HISTORIE_AB`. Sie bilden im Startmenü die eigene Gruppe **„Historisch"** –
über „Zufällig" landet man nur in 3–5 % der Runden vor 1995, die
Weltwirtschaftskrise wäre sonst Glückssache. Die eigene Gruppe ist zugleich der
Ort, an dem die Einschränkungen dieser Reihen benannt werden können, weil die
Wahl bewusst erfolgt.

| Reihe | ab | öffnet |
|---|---|---|
| S&P 500 (`^GSPC`) | 1927-12-30 | Weltwirtschaftskrise, Schwarzer Donnerstag |
| Nasdaq Composite (`^IXIC`) | 1971-02-05 | Ölkrise, Dotcom-Blase von Anfang an |
| Nikkei 225 (`^N225`) | 1980-01-01 | japanische Blase samt Hoch 12/1989 |

Die Startdaten sind **gemessen, nicht geschätzt**: Maßstab ist der Anteil der Tage
ohne jede Kursänderung. Yahoo liefert den Nikkei zwar ab 1965, die 1960er (6,9 %)
und 1970er (4,2 %) sind aber unbrauchbar – darunter 21 Handelstage am Stück
eingefroren auf 3187,62 im April 1972 mit anschließendem Nachholsprung von +5,2 %.
Für die Simulation wäre das eine risikolose Phase, die es nie gab. Ab 1980 liegt der
Wert bei 0,06 % ohne eine einzige Strecke ≥ 4 Tage. Der S&P 500 hat über die
gesamte Historie keine solche Strecke und bleibt deshalb ungekürzt.

Zwei Handelspausen lösen einen Hinweis aus und sind **echt**: das Bank Holiday
vom März 1933 (`^GSPC`) und die zehntägige Golden Week zum Thronwechsel 2019
(`^N225`).

Zwei Grenzen dieser Reihen: Es sind **Preisindizes ohne Dividenden** (wie die
bereits enthaltenen Indexreihen auch), und die Kaufkraftrechnung schaltet sich für
so alte Runden über `kaufkraftIstBelastbar` selbst ab – die Destatis-Tabelle
beginnt 1994. Die Abgeltungsteuer-Logik bildet durchgehend heutiges Recht ab; auf
eine Runde in den 1930ern angewandt ist sie ein bewusster Anachronismus.

### Gespleißte ETF-Reihen (`SPLEISS_POOL`)

Ein ETF lässt sich nicht in eine Zeit zurückrechnen, in der es ihn nicht gab. Der
übliche Ausweg – den zugrunde liegenden Index verlängern – scheitert hier daran,
dass die frei verfügbaren Indexreihen **Kursindizes ohne Dividenden** sind, die App
aber durchgängig mit Gesamtrendite rechnet. Man müsste eine Dividendenrendite
annehmen und hätte ein Modell statt einer Messung.

Deshalb der andere Weg: Viele ETFs haben einen **Publikumsfonds** derselben
Anlageidee, der Jahrzehnte älter ist. yfinance liefert dessen NAV-Reihe mit
`auto_adjust` als echte Gesamtrendite nach Kosten. Die ältere Reihe wird
multiplikativ auf den ersten gemeinsamen Tag umbasiert (`alt × neu[t0] / alt[t0]`) –
da beide Gesamtrendite sind, ist das reine Umbasierung ohne Annahme.

| Titel | Kette | ab | Korrelation | Trackingdifferenz |
|---|---|---|---|---|
| Welt ohne USA | VGTSX → VXUS | 1996 | 0,986 | +0,07 pp |
| Technologie-Sektor | FSPTX → XLK | 1983 | 0,950 | −2,79 pp |
| Energie-Sektor | FSENX → XLE | 1985 | 0,970 | −0,56 pp |
| Finanz-Sektor | FIDSX → XLF | 1985 | 0,964 | −0,83 pp |

Zwei Wächter entscheiden, nicht das Wunschdenken: mindestens
`MIN_UEBERLAPP_TAGE` (250) gemeinsame Handelstage und eine Korrelation der
**Tagesrenditen** im Überlapp von mindestens `MIN_KORRELATION` (0,90). Wer das
reißt, fliegt raus – so geschehen bei **XLV ← FSPHX** mit 0,809: Der aktiv
gemanagte Fidelity-Fonds hielt etwas deutlich anderes als der Health-Care-Index.
Ohne diese Prüfung wären dort zwei verschiedene Anlagen aneinandergeklebt worden.

Die Startdaten der Vorgängerfonds sind wie bei `HISTORIE_AB` gemessen: Die
Fidelity-Fonds gibt es ab 1981, ihre NAV-Reihen sind in den ersten Jahren aber
eingefroren (15,5 % / 42,7 % / 38,0 % unveränderte Tage in den 1980ern, Strecken
bis 34 Tage am Stück). Nach den gesetzten Startdaten bleibt keine Strecke
≥ 5 Tage übrig.

**Das Ergebnis ist synthetisch** und wird als solches ausgewiesen: `index.json`
trägt `spleissAb`, `quellen`, `spleissKorrelation` und `spleissTrackdiffPp`;
`AktienEintrag.istGespleisst` macht das in der App verfügbar. Der Ergebnis-Screen
blendet einen Hinweis ein – aber **nur**, wenn die tatsächlich gespielte Runde in
den gespleißten Teil reicht. Ein Vermerk an jedem Titel wäre schnell
Hintergrundrauschen, das niemand mehr liest.

**Binärformat** (little-endian): Magic `BRK1`, `int32` Basis-Epochtag,
`uint32` Anzahl, dann `uint16[]` Tages-Offsets und `float32[]` Schlusskurse.
Absolute Offsets statt Deltas – dadurch bleibt die Suche nach dem Startdatum eine
Binärsuche in O(log n). 6 Byte pro Kurs statt ~23 Byte als JSON.

Der Basis-Epochtag ist **vorzeichenbehaftet**, weil der S&P 500 vor dem
1970-01-01 beginnt (`-15343`). Die `uint16`-Offsets reichen für 65535 Tage ab
Basis, also 179 Jahre – die längste Reihe belegt davon 36050. Nur der Exporter
war auf positive Basistage festgelegt (`struct.pack("<I", …)` wirft bei negativen
Werten); der Codec kam durch die 32-Bit-Truncation des `Int32List` schon vorher
zum richtigen Ergebnis und liest jetzt zusätzlich explizit `getInt32`.

Die Tages-Offsets müssen **streng aufsteigend** sein – darauf beruht die
Binärsuche. `KursdatenCodec` prüft das beim Laden und lehnt eine Datei sonst mit
`FormatException` ab, ebenso eine leere Reihe und Kurse ≤ 0 oder `NaN`. Ohne
diese Prüfung gäbe eine beschädigte Datei keinen Fehler, sondern still falsche
Kurse und damit falsche Renditen.

Auffällige Tagesbewegungen (≥ 35 %) werden als **Hinweis** gemeldet, nicht als
Fehler – im Pool sind das echte Ereignisse (Apple −52 % am 29.09.2000,
Öl-Crash April 2020), keine Datenfehler. Zusätzlich gemeldet werden
Handelspausen über 10 Kalendertage, ≥ 5 identische Folgekurse und ein Reihenende,
das älter als 10 Tage ist – die drei Muster, hinter denen Delistings,
Handelsaussetzungen und eingestellte Ticker stecken.

**Der Export ist ganz oder gar nicht.** Erst werden alle Titel geladen und im
Speicher kodiert, dann wird geschrieben; jede Datei landet über eine `.tmp` plus
`os.replace` atomar. Werden weniger als 80 % der Titel geladen, bricht das Skript
mit Exit-Code 1 ab und rührt `assets/` nicht an – vorher überschrieb ein
yfinance-Ausfall das `index.json` klaglos mit einer leeren Liste und endete
trotzdem mit Exit-Code 0.

## Entwickeln

```bash
flutter pub get
flutter test        # 195 Tests: Simulation, Kamera, Kulisse, Codec, Rundenwahl, Scores,
                    # Rundenauswertung, Monte-Carlo, Trade-Log, Abgeltungsteuer,
                    # Inflation, Würfel-Investor, Bestenliste, kontrafaktische
                    # Vergleiche, Behavior Gap, Verhaltensprofil, Erfolge,
                    # historische Reihen vor 1970 und die Menü-Auswahl
                    # (beides gegen die echten Assets)

./.venv/bin/python tools/test_spleiss.py   # 7 Tests der Spleiß-Mechanik
                                           # (synthetische Reihen, kein Netz)
flutter analyze
flutter run         # Emulator oder angestecktes Gerät
flutter build apk --release --split-per-abi
```

Die Simulation ist gegen dieselben Invarianten abgesichert wie die Web-Version:
bei verdoppeltem Kurs gilt Investor > Sicherheit > nie-investierter Spieler;
ein Spieler, der nie kauft, endet exakt bei der Summe seiner Einzahlungen;
Kaufen+Verkaufen zum selben Kurs kostet exakt die doppelte Slippage;
verzinst wird über **Kalender**tage (Fr→Mo = 3), nicht über Handelstage.

Seit der Rundenauswertung gilt zusätzlich: Slippage fällt **nur noch auf manuelle
Kauf-/Verkaufsentscheidungen** an, nicht mehr auf die automatische Sparplan-
Einzahlung. Dadurch bleibt ein Spieler, der einmalig zu Rundenbeginn kauft und
danach nie wieder handelt, exakt um die Slippage auf sein Startkapital hinter dem
Investor zurück – nicht mehr kumulativ über jede einzelne Einzahlung. Die
`compute()`-Aufrufe für Monte-Carlo sitzen bewusst außerhalb von `lib/domain/`
(im `ErgebnisScreen`); die eigentliche Rechenlogik bleibt reines, isolate-taugliches
Dart.

Seit der Abgeltungsteuer (Paket 2) gilt zusätzlich: bei deaktiviertem Schalter
(`steuernAktiv: false`, Default) verhält sich die Engine exakt wie zuvor – das ist
selbst dann garantiert, wenn `steuersatz`/`teilfreistellung`/`sparerpauschbetrag`
explizit gesetzt wurden. Eine vorzeitig über `RennenEngine.beendeRunde()` beendete
Runde rechnet die noch offene Sicherheit-Jahressteuer trotzdem ab – ein direktes
`fertig = true` von außen tut das nicht mehr und wird deshalb nicht mehr benutzt.
Der Würfel-Investor (`wuerfelAktiv`, Engine-Default `false`) ändert bei
Deaktivierung ebenfalls nichts am Bestandsverhalten.

Seit Paket 3 (V9–V15) gilt zusätzlich: `RundenAuswertung.aus(engine)` wird im
`ErgebnisScreen` nur noch einmal in `initState()` berechnet statt bei jedem
`build()` neu – funktional identisch, aber ohne wiederholte Neuberechnung während
der Monte-Carlo-`FutureBuilder` auflöst. Alle neuen Felder (kontrafaktische
Vergleiche, Behavior Gap, Verhaltensmaße) sind `nullable` und blenden ihren
UI-Block vollständig aus, wenn nicht bestimmbar (z. B. eine reine Cash-Runde) –
keines davon ändert das Verhalten einer Runde ohne diese Werte. Bei der
Gelegenheit wurde ein latenter Division-durch-Null-Fehler in
`RundenAuswertung.aus` behoben: `differenzInMonatsEinzahlungen` (V6) und das neue
`behaviorGapInMonatsEinzahlungen` (V10) rechneten beide mit `.../ cfg.monatsEinzahlung`,
was bei einer Runde mit `monatsEinzahlung: 0.0` zu `NaN.round()` und damit zu einer
Exception geführt hätte – bislang deckte kein bestehender Test diesen Fall ab.

Seit dem Review-Paket P1–P3 gilt zusätzlich:

- `simuliereSpielerpfad` arbeitet **alle** Aktionen eines Tages ab (vorher genau
  eine, wodurch der Rest der Liste still verloren ging, sobald der Spieler an
  einem Tag kaufte **und** verkaufte).
- Die Referenz „ohne die besten/schlechtesten fünf Tage" wird über den
  Soll-Investitionszustand je Tag konstruiert statt über Kauf-/Verkaufspaare.
  Nur so stimmt sie auch für **benachbarte** Ausschlusstage – und die
  Extremtage einer Runde liegen typischerweise dicht beieinander.
- Monte-Carlo-Perzentil und teuerster Klick vergleichen gegen den um die
  gezahlte Steuer bereinigten Endwert (siehe oben).
- Eine Runde wird **vor** der Monte-Carlo-Rechnung protokolliert und bekommt ihr
  Perzentil über `SpielverlaufRepository.ergaenzePerzentilDesLetzten`
  nachgetragen. Vorher hing beides am selben `await`: warf das Isolate, wurde die
  Runde weder protokolliert noch auf Erfolge geprüft.
- `KursdatenRepository.zufall` liefert `null`, statt still auf einen zu kurzen
  Titel zurückzufallen. Der Startbildschirm meldet das – „Welt-ETFs + 20 Jahre"
  gab es im Pool nie, der Startknopf tat dann wortlos nichts.
- Der Monte-Carlo-Seed wird aus dem Rundenzustand abgeleitet statt aus der Uhr:
  das Perzentil ist der Sortierschlüssel der Bestenliste und darf für dieselbe
  Runde nicht schwanken.
- Der Bestenlisten-Eintrag speichert den zuletzt **simulierten** Tag als
  `endDatum`, nicht das Ende des gezogenen Ausschnitts – bei einer vorzeitig
  beendeten Runde stand dort sonst ein nie gespielter Zeitraum.
- Der Zins eines Schritts über den Jahreswechsel wird **anteilig** auf beide
  Jahre verteilt, statt komplett ins neue zu fallen.
- `RennenEngine.schritt()` beendet auch im Frühausstieg über `beendeRunde()`.

## Später

`index.json` kennt bereits ein Feld `quelle`. Aktuell ist nur `bundled`
implementiert; ein `remote`-Zweig für nachladbare Aktien lässt sich im
`KursdatenRepository` ergänzen, ohne UI oder Domain anzufassen.
