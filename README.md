# Börsenrennen – Handy-App

Ein Lernspiel für die Börse als Flutter-App (Android, iOS-kompatible Codebasis).
Drei Anlagestrategien treten auf **derselben**, dem Spieler verborgenen Zufallsaktie
über einen zufälligen historischen Zeitraum als Wettrennen gegeneinander an.

| Läufer | Verhalten |
|--------|-----------|
| 🟢 **Du** | handelst manuell („Alles kaufen" / „Alles verkaufen"), 0,5 % Slippage. Neue Einzahlungen fließen in die Position, wenn du investiert bist – sonst bleiben sie Cash. |
| 🔵 **Investor** | kauft jede Einzahlung sofort, bleibt voll investiert (Buy-and-Hold, ohne Slippage – die Benchmark). |
| 🟡 **Sicherheit** | legt alles zu einem festen, vor der Runde gewählten Zins an. |

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

## Technik

- **Flutter 3.47** / Dart 3.13, Rendering mit `CustomPainter` (kein Game-Engine-Overhead).
- **Vollständig offline**: 48 Titel (Einzelaktien, Welt-ETFs, Themen-/Länder-ETFs,
  Indizes, Rohstoffe) liegen als kompakte Binärdateien im App-Paket (~1,9 MB
  gesamt). Kein Server, kein Internet.
- **Lokale Bestenliste** in `shared_preferences`, max. 100 Einträge.
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
│   └── strategie.dart / spiel_konfiguration.dart
├── data/       Assets laden, Binärformat dekodieren, Bestenliste speichern
├── spiel/      RennenController: Ticker, Tempo, Pause, Repaint/HUD-Kanäle
├── render/     CustomPainter für Kurs-Chart und Rennbahn
├── screens/    Start, Rennen, Ergebnis, Bestenliste
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
flutter test        # 51 Tests: Simulation, Kamera, Kulisse, Codec, Rundenwahl, Scores
flutter analyze
flutter run         # Emulator oder angestecktes Gerät
flutter build apk --release --split-per-abi
```

Die Simulation ist gegen dieselben Invarianten abgesichert wie die Web-Version:
bei verdoppeltem Kurs gilt Investor > Sicherheit > nie-investierter Spieler;
ein Spieler, der nie kauft, endet exakt bei der Summe seiner Einzahlungen;
Kaufen+Verkaufen zum selben Kurs kostet exakt die doppelte Slippage;
verzinst wird über **Kalender**tage (Fr→Mo = 3), nicht über Handelstage.

## Später

`index.json` kennt bereits ein Feld `quelle`. Aktuell ist nur `bundled`
implementiert; ein `remote`-Zweig für nachladbare Aktien lässt sich im
`KursdatenRepository` ergänzen, ohne UI oder Domain anzufassen.
