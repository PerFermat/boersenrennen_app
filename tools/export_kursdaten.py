#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# =====================================================================
#  Börsenrennen App – Export der Kursdaten als App-Assets
#
#  Lädt die historischen Tagesschlusskurse via yfinance und schreibt
#  je Aktie eine kompakte Binärdatei plus ein gemeinsames index.json
#  nach assets/kurse/.
#
#  Aufruf (im venv des Projekts):
#      ./.venv/bin/python tools/export_kursdaten.py
#
#  Warum auto_adjust=True:
#      yfinance liefert "Close" bereits split-bereinigt. auto_adjust=True
#      rechnet zusätzlich Dividenden ein – damit bildet die Buy-and-Hold-
#      Strategie (Investor) die echte Gesamtrendite ab.
# =====================================================================

import argparse
import json
import math
import os
import re
import struct
import sys
from datetime import date

import warnings
# Gezielt statt pauschal: ein globales filterwarnings("ignore") verschluckt
# auch Hinweise auf Datenlücken und auf Formatumstellungen von yfinance –
# genau die Warnungen, die diesen Export still kaputtgehen lassen würden.
warnings.filterwarnings("ignore", category=FutureWarning, module="yfinance")

import yfinance as yf


# Historie möglichst weit zurück, damit ein Startzeitpunkt
# "mind. 10 Jahre zurück" jederzeit erfüllbar ist.
START_DATUM = "1995-01-01"

# Reihen, die bewusst weiter zurückreichen als START_DATUM.
#
# Für Einzelaktien und ETFs bringt mehr Historie nichts – die Produkte gab es
# schlicht noch nicht. Die großen Indizes dagegen sind durchgerechnet bis weit
# vor die Nachkriegszeit verfügbar und öffnen damit Epochen, die man sonst nur
# aus Erzählungen kennt: Weltwirtschaftskrise, Ölkrise, japanische Blase.
#
# Wichtig: Das sind Preisindizes ohne Dividenden – wie die vier bereits
# enthaltenen Indexreihen auch. Die Gesamtrendite lag historisch mehrere
# Prozentpunkte pro Jahr darüber.
# Die Startdaten sind gemessen, nicht geschätzt: Anteil der Tage ohne jede
# Kursänderung je Jahrzehnt, plus Länge der eingefrorenen Strecken.
HISTORIE_AB = {
    # Verfügbar ab 1927-12-30, durchgehend brauchbar: keine einzige
    # eingefrorene Strecke >= 4 Tage über die gesamte Historie.
    "^GSPC": "1900-01-01",

    # Ab 1971-02-05, 0,27 % unveränderte Tage, keine Strecken.
    "^IXIC": "1900-01-01",

    # Yahoo liefert zwar ab 1965, die Jahre davor sind aber unbrauchbar:
    # 1960er 6,9 % / 1970er 4,2 % unveränderte Tage, darunter 21 Handelstage
    # am Stück eingefroren auf 3187,62 (April 1972) mit anschließendem
    # Nachholsprung von +5,2 %. Für die Simulation wäre das eine risikolose
    # Phase, die es nie gab. Ab 1980: 0,06 %, keine Strecken – und die
    # japanische Blase samt Hoch im Dezember 1989 ist vollständig enthalten.
    "^N225": "1980-01-01",
}

# Auffällige Tagesbewegung -> nur Hinweis, kein Abbruch.
# Echte Kursstürze (z. B. Apple -52 % am 29.09.2000) sind legitim.
AUFFAELLIG = 0.35

# Weniger Kurse als das ergibt keine spielbare Reihe.
MIN_TAGE = 250

# Handelspause in Kalendertagen, ab der ein Hinweis erscheint. Über
# Feiertagsbrücken hinaus deutet so etwas auf Delisting oder eine
# Handelsaussetzung hin -> die Reihe hat dann eine Lücke, die die Simulation
# stillschweigend als einen einzigen langen "Handelstag" behandeln würde.
#
# Zwei Treffer sind geprüft und echt, kein Datenfehler:
#   ^GSPC bis 1933-03-15 – das Bank Holiday, mit dem Roosevelt im März 1933
#                          sämtliche Banken und die Börse schloss.
#   ^N225 bis 2019-05-07 – die zehntägige Golden Week zum Thronwechsel
#                          (Ausrufung der Reiwa-Ära).
MAX_LUECKE_TAGE = 10

# So viele identische Folgekurse gelten als eingefrorene Reihe.
MAX_IDENTISCHE_FOLGEKURSE = 5

# Reihe muss so aktuell sein, sonst Hinweis (Ticker eingestellt/umbenannt?).
MAX_ALTER_TAGE = 10

# Unter diesem Anteil erfolgreich geladener Titel wird index.json NICHT
# überschrieben – ein yfinance-Ausfall soll den Datenbestand nicht zerstören.
MIN_ERFOLGSQUOTE = 0.8

EPOCHE = date(1970, 1, 1)

# Kuratierter Pool: (Ticker, Name, Kategorie, Gruppe)
#
# Die Gruppe steuert die Auswahl im Startmenü ("welche Art Aktie will ich
# spielen?"), die Kategorie ist nur eine feinere Beschriftung innerhalb davon.
GRUPPE_EINZELAKTIEN = "Einzelaktien"
GRUPPE_WELT_ETF = "Welt-ETF"
GRUPPE_THEMEN_LAENDER_ETF = "Themen-Länder-ETF"
GRUPPE_INDEX_ROHSTOFF = "Index-Rohstoff"

# Eigene Gruppe, damit die alten Zeiträume *gezielt* wählbar sind. Über
# "Zufällig" landet man nur in rund 3-5 % der Runden vor 1995 – die
# Weltwirtschaftskrise wäre sonst reine Glückssache.
#
# Die Trennung hat einen zweiten Zweck: Für diese Reihen gelten Einschränkungen,
# die im Startmenü genannt werden können, weil die Wahl bewusst erfolgt –
# Preisindex ohne Dividenden, keine Kaufkraftrechnung (Destatis ab 1994),
# heutiges Steuerrecht auf historische Kurse.
GRUPPE_HISTORISCH = "Historisch"

AKTIEN_POOL = [
    # ---- Einzelaktien: DAX ----
    ("SAP.DE",  "SAP SE",                       "DAX", GRUPPE_EINZELAKTIEN),
    ("SIE.DE",  "Siemens AG",                   "DAX", GRUPPE_EINZELAKTIEN),
    ("ALV.DE",  "Allianz SE",                   "DAX", GRUPPE_EINZELAKTIEN),
    ("BMW.DE",  "BMW AG",                       "DAX", GRUPPE_EINZELAKTIEN),
    ("VOW3.DE", "Volkswagen AG (Vz.)",          "DAX", GRUPPE_EINZELAKTIEN),
    ("DTE.DE",  "Deutsche Telekom AG",          "DAX", GRUPPE_EINZELAKTIEN),
    ("MBG.DE",  "Mercedes-Benz Group AG",       "DAX", GRUPPE_EINZELAKTIEN),
    ("BAS.DE",  "BASF SE",                      "DAX", GRUPPE_EINZELAKTIEN),
    ("ADS.DE",  "Adidas AG",                    "DAX", GRUPPE_EINZELAKTIEN),
    # ---- Einzelaktien: US-Tech ----
    ("AAPL",    "Apple Inc.",                   "US-Tech", GRUPPE_EINZELAKTIEN),
    ("MSFT",    "Microsoft Corp.",              "US-Tech", GRUPPE_EINZELAKTIEN),
    ("GOOGL",   "Alphabet Inc.",                "US-Tech", GRUPPE_EINZELAKTIEN),
    ("AMZN",    "Amazon.com Inc.",              "US-Tech", GRUPPE_EINZELAKTIEN),
    ("NVDA",    "NVIDIA Corp.",                 "US-Tech", GRUPPE_EINZELAKTIEN),
    ("META",    "Meta Platforms Inc.",          "US-Tech", GRUPPE_EINZELAKTIEN),
    ("NFLX",    "Netflix Inc.",                 "US-Tech", GRUPPE_EINZELAKTIEN),
    # ---- Einzelaktien: US-Sonstige ----
    ("TSLA",    "Tesla Inc.",                   "US-Sonstige", GRUPPE_EINZELAKTIEN),
    ("JNJ",     "Johnson & Johnson",            "US-Sonstige", GRUPPE_EINZELAKTIEN),
    ("JPM",     "JPMorgan Chase & Co.",         "US-Sonstige", GRUPPE_EINZELAKTIEN),
    ("KO",      "The Coca-Cola Company",        "US-Sonstige", GRUPPE_EINZELAKTIEN),
    ("DIS",     "The Walt Disney Company",      "US-Sonstige", GRUPPE_EINZELAKTIEN),
    ("XOM",     "Exxon Mobil Corp.",            "US-Sonstige", GRUPPE_EINZELAKTIEN),
    ("WMT",     "Walmart Inc.",                 "US-Sonstige", GRUPPE_EINZELAKTIEN),
    # ---- Weltweit gestreute ETFs ----
    ("VT",      "Vanguard Total World Stock ETF",     "Welt-ETF", GRUPPE_WELT_ETF),
    ("ACWI",    "iShares MSCI ACWI ETF",               "Welt-ETF", GRUPPE_WELT_ETF),
    ("URTH",    "iShares MSCI World ETF",              "Welt-ETF", GRUPPE_WELT_ETF),
    ("VEU",     "Vanguard FTSE All-World ex-US ETF",   "Welt-ETF", GRUPPE_WELT_ETF),
    ("VXUS",    "Vanguard Total International Stock ETF", "Welt-ETF", GRUPPE_WELT_ETF),
    # ---- Länder-ETFs ----
    ("EWJ",     "iShares MSCI Japan ETF",       "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("EWZ",     "iShares MSCI Brazil ETF",      "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("INDA",    "iShares MSCI India ETF",       "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("MCHI",    "iShares MSCI China ETF",       "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("EWG",     "iShares MSCI Germany ETF",     "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("EWU",     "iShares MSCI United Kingdom ETF", "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("EWC",     "iShares MSCI Canada ETF",      "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("EWA",     "iShares MSCI Australia ETF",   "Länder-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    # ---- Themen-ETFs ----
    ("XLK",     "Technology Select Sector SPDR",   "Themen-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("XLE",     "Energy Select Sector SPDR",       "Themen-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("XLV",     "Health Care Select Sector SPDR",  "Themen-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("XLF",     "Financial Select Sector SPDR",    "Themen-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    ("ICLN",    "iShares Global Clean Energy ETF", "Themen-ETF", GRUPPE_THEMEN_LAENDER_ETF),
    # ---- Indizes & Rohstoffe ----
    ("^GDAXI",  "DAX",                          "Index", GRUPPE_INDEX_ROHSTOFF),
    ("^DJI",    "Dow Jones Industrial Average", "Index", GRUPPE_INDEX_ROHSTOFF),
    ("^NDX",    "Nasdaq 100",                   "Index", GRUPPE_INDEX_ROHSTOFF),
    # ---- Historisch: Reihen, die weit vor 1995 beginnen (siehe HISTORIE_AB) ----
    ("^GSPC",   "S&P 500 (ab 1927)",            "Index", GRUPPE_HISTORISCH),
    ("^IXIC",   "Nasdaq Composite (ab 1971)",   "Index", GRUPPE_HISTORISCH),
    ("^N225",   "Nikkei 225 (ab 1980)",         "Index", GRUPPE_HISTORISCH),
    ("GC=F",    "Gold",                         "Rohstoff", GRUPPE_INDEX_ROHSTOFF),
    ("SI=F",    "Silber",                       "Rohstoff", GRUPPE_INDEX_ROHSTOFF),
    ("CL=F",    "Rohöl WTI",                    "Rohstoff", GRUPPE_INDEX_ROHSTOFF),
]


# ---------------------------------------------------------------------------
#  Gespleißte Reihen: ETF + Vorgängerfonds derselben Anlageidee
# ---------------------------------------------------------------------------
#
# Ein ETF lässt sich nicht in eine Zeit zurückrechnen, in der es ihn nicht gab.
# Der übliche Ausweg – den Index zurückrechnen – hat hier einen Haken: Die
# frei verfügbaren Indexreihen sind Kursindizes ohne Dividenden, die App rechnet
# aber durchgängig mit Gesamtrendite. Man müsste also eine Dividendenrendite
# annehmen und hätte ein Modell statt einer Messung.
#
# Deshalb der andere Weg: Viele ETFs haben einen **Publikumsfonds** derselben
# Anlageidee, der Jahrzehnte älter ist. yfinance liefert dessen NAV-Reihe mit
# auto_adjust als echte Gesamtrendite nach Kosten – ohne jede Annahme.
#
# Die ältere Reihe wird multiplikativ auf den Starttag der jüngeren umbasiert
# (alt * neu[t0] / alt[t0]). Da beide Gesamtrendite sind, ist das reine
# Umbasierung und kein Modell.
#
# WICHTIG: Das Ergebnis ist eine **synthetische** Reihe. Vor dem Spleißpunkt
# zeigt sie den Vorgängerfonds, nicht den ETF. Deshalb tragen die Einträge
# "spleissAb" und "quellen" im index.json, und die App weist das aus.
MIN_UEBERLAPP_TAGE = 250
MIN_KORRELATION = 0.90

# (Ticker, Vorgänger, Vorgänger-Start, Name, Kategorie, Dateiname-Kürzel)
#
# Der Vorgänger-Start ist wie bei HISTORIE_AB gemessen, nicht geschätzt. Die
# Fidelity-Fonds gibt es zwar ab 1981, ihre NAV-Reihen sind in den ersten
# Jahren aber eingefroren: 15,5 % (FSPTX), 42,7 % (FSENX) und 38,0 % (FIDSX)
# unveränderte Tage in den 1980ern, mit Strecken bis zu 34 Tagen am Stück. Nach
# den unten gesetzten Startdaten bleibt keine Strecke >= 5 Tage übrig.
#
# Bewusst **nicht** dabei: XLV <- FSPHX. Korrelation der Tagesrenditen im
# Überlapp nur 0,809 – der aktiv gemanagte Fidelity-Fonds hielt offenbar etwas
# deutlich anderes als der Health-Care-Sektorindex. Der Wächter unten fängt das
# ohnehin ab; hier steht es, damit niemand den Eintrag "versehentlich vergessen"
# wieder ergänzt.
SPLEISS_POOL = [
    ("VXUS", "VGTSX", "1996-01-01", "Welt ohne USA (ab 1996)",      "Welt-ETF",   "vxus_lang"),
    ("XLK",  "FSPTX", "1983-01-01", "Technologie-Sektor (ab 1983)", "Themen-ETF", "xlk_lang"),
    ("XLE",  "FSENX", "1985-01-01", "Energie-Sektor (ab 1985)",     "Themen-ETF", "xle_lang"),
    ("XLF",  "FIDSX", "1985-01-01", "Finanz-Sektor (ab 1985)",      "Themen-ETF", "xlf_lang"),
]


def _korrelation(xs, ys):
    """Pearson-Korrelation, ohne numpy – der Export soll leichtgewichtig bleiben."""
    n = len(xs)
    if n < 2:
        return 0.0
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if sxx <= 0 or syy <= 0:
        return 0.0
    return sxy / math.sqrt(sxx * syy)


def spleisse(neu, alt):
    """
    Hängt [alt] vor [neu] und basiert es auf den Starttag von [neu] um.

    Liefert (werte, spleiss_ab, korrelation, trackdiff_pp). Wirft ValueError,
    wenn Überlappung oder Korrelation nicht reichen – lieber gar keine Reihe
    als eine, die zwei verschiedene Anlagen aneinanderklebt.
    """
    neu_map, alt_map = dict(neu), dict(alt)
    gemeinsam = sorted(set(neu_map) & set(alt_map))
    if len(gemeinsam) < MIN_UEBERLAPP_TAGE:
        raise ValueError(
            f"Überlappung zu kurz: {len(gemeinsam)} < {MIN_UEBERLAPP_TAGE} Tage"
        )

    # Tagesrenditen auf den gemeinsamen Tagen -> halten die beiden Reihen
    # überhaupt dasselbe?
    rn = [neu_map[gemeinsam[i]] / neu_map[gemeinsam[i - 1]] - 1
          for i in range(1, len(gemeinsam))]
    ra = [alt_map[gemeinsam[i]] / alt_map[gemeinsam[i - 1]] - 1
          for i in range(1, len(gemeinsam))]
    korr = _korrelation(rn, ra)
    if korr < MIN_KORRELATION:
        raise ValueError(f"Renditekorrelation nur {korr:.3f} < {MIN_KORRELATION}")

    # Umbasierung am ersten gemeinsamen Tag.
    t0 = gemeinsam[0]
    faktor = neu_map[t0] / alt_map[t0]

    jahre = (gemeinsam[-1] - t0).days / 365.25
    cn = (neu_map[gemeinsam[-1]] / neu_map[t0]) ** (1 / jahre) - 1
    ca = (alt_map[gemeinsam[-1]] / alt_map[t0]) ** (1 / jahre) - 1

    werte = [(d, k * faktor) for d, k in alt if d < t0] + [
        (d, k) for d, k in neu if d >= t0
    ]
    werte.sort(key=lambda p: p[0])
    return werte, t0, korr, (cn - ca) * 100


def slug(ticker):
    """^GDAXI -> gdaxi, GC=F -> gc_f, VOW3.DE -> vow3_de"""
    s = re.sub(r"[^a-z0-9]+", "_", ticker.lower())
    return s.strip("_")


def epochtag(d):
    return (d - EPOCHE).days


def lade_kurse(ticker, ab=None):
    """
    Liefert eine sortierte Liste (datum, kurs) ohne Lücken und Ausreißer.

    [ab] überschreibt das Startdatum. Vorgängerfonds aus dem SPLEISS_POOL
    brauchen ihre **volle** Historie – ohne das lieferte der Spleiß eine Reihe
    ab 1995 statt ab 1981, also genau keine Verlängerung.
    """
    df = yf.download(ticker, start=ab or HISTORIE_AB.get(ticker, START_DATUM),
                     progress=False, auto_adjust=True)
    if df is None or df.empty:
        return []

    reihe = df["Close"].squeeze().dropna()
    werte = []
    for idx, kurs in reihe.items():
        k = float(kurs)
        if not math.isfinite(k) or k <= 0:
            continue
        d = idx.date() if hasattr(idx, "date") else idx
        werte.append((d, k))

    werte.sort(key=lambda p: p[0])

    # Duplikate nach Datum entfernen (letzter Wert gewinnt)
    entdoppelt = []
    for d, k in werte:
        if entdoppelt and entdoppelt[-1][0] == d:
            entdoppelt[-1] = (d, k)
        else:
            entdoppelt.append((d, k))
    return entdoppelt


def pruefe_auffaellige(ticker, werte):
    """Meldet ungewöhnliche Tagesbewegungen als Hinweis."""
    treffer = []
    for i in range(len(werte) - 1):
        aenderung = werte[i + 1][1] / werte[i][1] - 1
        if abs(aenderung) >= AUFFAELLIG:
            treffer.append((werte[i + 1][0], aenderung * 100))
    for d, p in treffer[:4]:
        print(f"   Hinweis: {ticker} {d} {p:+.0f} % an einem Tag")
    return len(treffer)


def pruefe_reihenqualitaet(ticker, werte):
    """
    Meldet Lücken, eingefrorene Kurse und ein zu altes Reihenende.

    Anders als `pruefe_auffaellige` geht es hier nicht um einzelne Ausreißer,
    sondern um die Fälle, die die Simulation still verfälschen: eine
    Handelspause erscheint dort als ein einziger langer Handelstag, ein
    eingefrorener Kurs als ein Zeitraum ohne jedes Risiko.
    """
    hinweise = []

    luecken = [
        (werte[i + 1][0], (werte[i + 1][0] - werte[i][0]).days)
        for i in range(len(werte) - 1)
        if (werte[i + 1][0] - werte[i][0]).days > MAX_LUECKE_TAGE
    ]
    for d, tage in luecken[:3]:
        hinweise.append(f"Handelspause von {tage} Tagen bis {d}")
    if len(luecken) > 3:
        hinweise.append(f"... und {len(luecken) - 3} weitere Lücken")

    lauf, bester_lauf, bis = 1, 1, werte[0][0]
    for i in range(1, len(werte)):
        if werte[i][1] == werte[i - 1][1]:
            lauf += 1
            if lauf > bester_lauf:
                bester_lauf, bis = lauf, werte[i][0]
        else:
            lauf = 1
    if bester_lauf >= MAX_IDENTISCHE_FOLGEKURSE:
        hinweise.append(f"{bester_lauf} identische Folgekurse bis {bis}")

    alter = (date.today() - werte[-1][0]).days
    if alter > MAX_ALTER_TAGE:
        hinweise.append(f"Reihe endet bereits am {werte[-1][0]} ({alter} Tage alt)")

    for h in hinweise:
        print(f"   Hinweis: {ticker} – {h}")
    return len(hinweise)


def baue_bin(werte):
    """
    Binärformat (little-endian):
      'BRK1'                      4 B  Magic
      int32  basisEpochTag             Epochtag des ersten Kurses (ggf. negativ)
      uint32 anzahl
      uint16[anzahl] tagOffset         Tage seit Basistag, streng aufsteigend
      (Padding auf 4-Byte-Grenze)
      float32[anzahl] schlusskurs

    Absolute Offsets (statt Deltas) erlauben in der App eine Binärsuche
    nach dem Startdatum in O(log n).
    """
    basis = epochtag(werte[0][0])
    anzahl = len(werte)
    offsets = [epochtag(d) - basis for d, _ in werte]

    if offsets[-1] > 65535:
        raise ValueError(f"Zeitraum zu lang für uint16-Offsets: {offsets[-1]} Tage")

    # Die App verlässt sich auf streng aufsteigende Offsets (Binärsuche) –
    # hier abzubrechen ist billiger, als es dem Codec zu überlassen.
    if any(offsets[i] <= offsets[i - 1] for i in range(1, anzahl)):
        raise ValueError("Epochtage nicht streng aufsteigend")

    # "<i" statt "<I" für den Basistag: Reihen vor 1970 haben einen negativen
    # Epochtag (S&P 500 ab 1927-12-30 = -15343). Mit "<I" wirft struct hier
    # einen Fehler – laut, aber eben auch: unmöglich zu exportieren.
    kopf = b"BRK1" + struct.pack("<iI", basis, anzahl)
    off_bytes = struct.pack(f"<{anzahl}H", *offsets)
    padding = b"\x00" * ((4 - len(off_bytes) % 4) % 4)
    kurs_bytes = struct.pack(f"<{anzahl}f", *[k for _, k in werte])

    return kopf + off_bytes + padding + kurs_bytes


def schreibe_atomar(pfad, daten):
    """
    Erst vollständig danebenschreiben, dann umbenennen.

    Ein Abbruch mitten im Schreiben hinterlässt sonst eine abgeschnittene
    Datei in assets/ – und seit der Codec-Prüfung startet die App damit gar
    nicht mehr.
    """
    tmp = pfad + ".tmp"
    with open(tmp, "wb") as f:
        f.write(daten)
    os.replace(tmp, pfad)


def main():
    p = argparse.ArgumentParser(description="Exportiert Kursdaten als App-Assets.")
    p.add_argument("--out", default="assets/kurse", help="Zielverzeichnis")
    args = p.parse_args()

    os.makedirs(args.out, exist_ok=True)

    # Erst alles einsammeln, dann in einem Rutsch schreiben. Würde jede .bin
    # sofort landen, hinterließe ein Abbruch nach der Hälfte einen Mischbestand
    # aus neuen Kursdateien und altem index.json.
    fertig = []          # (dateiname, bytes, index-eintrag)
    auffaellig_gesamt = 0
    qualitaet_gesamt = 0

    def verarbeite(ticker, name, kategorie, gruppe, werte, datei, zusatz=None):
        """Prüfen, kodieren, für den späteren Schreibvorgang vormerken."""
        nonlocal auffaellig_gesamt, qualitaet_gesamt

        if len(werte) < MIN_TAGE:
            print(f"   Nur {len(werte)} Kurse – übersprungen.")
            return
        spanne_jahre = (werte[-1][0] - werte[0][0]).days / 365.25
        if spanne_jahre < 10:
            print(f"   Nur {spanne_jahre:.1f} Jahre Historie – übersprungen.")
            return

        auffaellig_gesamt += pruefe_auffaellige(ticker, werte)
        qualitaet_gesamt += pruefe_reihenqualitaet(ticker, werte)

        try:
            daten = baue_bin(werte)
        except ValueError as err:
            print(f"   FEHLER beim Kodieren: {err} – übersprungen.")
            return

        eintrag = {
            "ticker": ticker,
            "name": name,
            "kategorie": kategorie,
            "gruppe": gruppe,
            "datei": datei,
            "anzahl": len(werte),
            "ersterTag": werte[0][0].isoformat(),
            "letzterTag": werte[-1][0].isoformat(),
            "quelle": "bundled",
        }
        eintrag.update(zusatz or {})
        fertig.append((datei, daten, eintrag))
        print(f"   {len(werte)} Kurse, {werte[0][0]} – {werte[-1][0]}, "
              f"{len(daten)/1024:.0f} KB")

    for ticker, name, kategorie, gruppe in AKTIEN_POOL:
        print(f"-> {ticker} ({name}) ...", flush=True)
        try:
            werte = lade_kurse(ticker)
        except Exception as err:
            print(f"   FEHLER beim Laden: {err}")
            continue
        verarbeite(ticker, name, kategorie, gruppe, werte, f"{slug(ticker)}.bin")

    for ticker, vorgaenger, vorgaenger_ab, name, kategorie, kuerzel in SPLEISS_POOL:
        print(f"-> {ticker} + {vorgaenger} ({name}) ...", flush=True)
        try:
            neu = lade_kurse(ticker)
            alt = lade_kurse(vorgaenger, ab=vorgaenger_ab)
        except Exception as err:
            print(f"   FEHLER beim Laden: {err}")
            continue
        if not neu or not alt:
            print("   Eine der beiden Reihen ist leer – übersprungen.")
            continue

        try:
            werte, spleiss_ab, korr, trackdiff = spleisse(neu, alt)
        except ValueError as err:
            print(f"   SPLEISS ABGELEHNT: {err}")
            continue

        print(f"   Spleiß ab {spleiss_ab}: Korrelation {korr:.3f}, "
              f"Trackingdifferenz {trackdiff:+.2f} pp/Jahr")
        verarbeite(
            ticker, name, kategorie, GRUPPE_HISTORISCH, werte, f"{kuerzel}.bin",
            zusatz={
                "spleissAb": spleiss_ab.isoformat(),
                "quellen": [vorgaenger, ticker],
                "spleissKorrelation": round(korr, 4),
                "spleissTrackdiffPp": round(trackdiff, 3),
            },
        )

    # Abbruch-Guard: ein yfinance-Ausfall darf den vorhandenen Datenbestand
    # nicht durch ein leeres oder halbes index.json ersetzen. Ohne diese
    # Prüfung endete der Export auch bei 0 geladenen Titeln mit Exit-Code 0.
    #
    # Gespleißte Reihen zählen mit: Sie können auch durch den Qualitätswächter
    # abgelehnt werden, und dann ist ein Fehlbestand genauso ernst.
    mindestens = int((len(AKTIEN_POOL) + len(SPLEISS_POOL)) * MIN_ERFOLGSQUOTE)
    if len(fertig) < mindestens:
        sys.exit(
            f"\nABBRUCH: nur {len(fertig)} von "
            f"{len(AKTIEN_POOL) + len(SPLEISS_POOL)} Titeln geladen "
            f"(mindestens {mindestens} nötig). assets/ bleibt unverändert."
        )

    for datei, daten, _ in fertig:
        schreibe_atomar(os.path.join(args.out, datei), daten)

    index = {
        "schemaVersion": 1,
        "erzeugtAm": date.today().isoformat(),
        "quelle": "yfinance",
        "kursAnpassung": "auto_adjust",
        "aktien": [eintrag for _, _, eintrag in fertig],
    }
    schreibe_atomar(
        os.path.join(args.out, "index.json"),
        json.dumps(index, ensure_ascii=False, indent=2).encode("utf-8"),
    )

    gesamt_bytes = sum(len(daten) for _, daten, _ in fertig)
    print(f"\n=== {len(fertig)} Aktien exportiert, {gesamt_bytes/1024:.0f} KB gesamt ===")
    if auffaellig_gesamt:
        print(f"({auffaellig_gesamt} auffällige Tagesbewegungen – meist echte "
              f"Kursstürze, siehe Hinweise oben.)")
    if qualitaet_gesamt:
        print(f"({qualitaet_gesamt} Hinweise zu Lücken/Aktualität – bitte prüfen, "
              f"bevor die Assets committet werden.)")


if __name__ == "__main__":
    main()
