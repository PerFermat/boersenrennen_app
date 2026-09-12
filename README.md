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

### Inflation und reale Kaufkraft (`lib/domain/inflation.dart`)

Neben jedem nominalen Endbetrag steht eine kleinere Zeile mit der realen
Kaufkraft – in Preisen des Rundenbeginns, nicht in heutigen Preisen. Die
Jahresteuerungsraten stammen vom Statistischen Bundesamt (Destatis); da die
App durchgängig in Euro anzeigt, auch für US-Titel, wird bewusst eine einzelne
deutsche Reihe verwendet statt länderspezifischer Inflation. Die **Wertung
bleibt nominal** – `Score.vsInvestor` ist ein Verhältnis zweier Werte desselben
Zeitraums, die Inflation kürzt sich heraus.

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
- **Vollständig offline**: 48 Titel (Einzelaktien, Welt-ETFs, Themen-/Länder-ETFs,
  Indizes, Rohstoffe) liegen als kompakte Binärdateien im App-Paket (~1,9 MB
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

**Binärformat** (little-endian): Magic `BRK1`, `uint32` Basis-Epochtag,
`uint32` Anzahl, dann `uint16[]` Tages-Offsets und `float32[]` Schlusskurse.
Absolute Offsets statt Deltas – dadurch bleibt die Suche nach dem Startdatum eine
Binärsuche in O(log n). 6 Byte pro Kurs statt ~23 Byte als JSON.

Auffällige Tagesbewegungen (≥ 35 %) werden als **Hinweis** gemeldet, nicht als
Fehler – im Pool sind das echte Ereignisse (Apple −52 % am 29.09.2000,
Öl-Crash April 2020), keine Datenfehler.

## Entwickeln

```bash
flutter pub get
flutter test        # 153 Tests: Simulation, Kamera, Kulisse, Codec, Rundenwahl, Scores,
                    # Rundenauswertung, Monte-Carlo, Trade-Log, Abgeltungsteuer,
                    # Inflation, Würfel-Investor, Bestenliste, kontrafaktische
                    # Vergleiche, Behavior Gap, Verhaltensprofil, Erfolge
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

## Später

`index.json` kennt bereits ein Feld `quelle`. Aktuell ist nur `bundled`
implementiert; ein `remote`-Zweig für nachladbare Aktien lässt sich im
`KursdatenRepository` ergänzen, ohne UI oder Domain anzufassen.
