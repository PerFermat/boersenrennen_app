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
import re
import struct
import sys
from datetime import date, timedelta

import warnings
warnings.filterwarnings("ignore")

import yfinance as yf


# Historie möglichst weit zurück, damit ein Startzeitpunkt
# "mind. 10 Jahre zurück" jederzeit erfüllbar ist.
START_DATUM = "1995-01-01"

# Auffällige Tagesbewegung -> nur Hinweis, kein Abbruch.
# Echte Kursstürze (z. B. Apple -52 % am 29.09.2000) sind legitim.
AUFFAELLIG = 0.35

# Eine Runde braucht mindestens 10 Jahre Historie.
MIN_TAGE = 250

EPOCHE = date(1970, 1, 1)

# Kuratierter Pool: (Ticker, Name, Kategorie, Gruppe)
#
# Die Gruppe steuert die Auswahl im Startmenü ("welche Art Aktie will ich
# spielen?"), die Kategorie ist nur eine feinere Beschriftung innerhalb davon.
GRUPPE_EINZELAKTIEN = "Einzelaktien"
GRUPPE_WELT_ETF = "Welt-ETF"
GRUPPE_THEMEN_LAENDER_ETF = "Themen-Länder-ETF"
GRUPPE_INDEX_ROHSTOFF = "Index-Rohstoff"

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
    ("^GSPC",   "S&P 500",                      "Index", GRUPPE_INDEX_ROHSTOFF),
    ("^DJI",    "Dow Jones Industrial Average", "Index", GRUPPE_INDEX_ROHSTOFF),
    ("^NDX",    "Nasdaq 100",                   "Index", GRUPPE_INDEX_ROHSTOFF),
    ("GC=F",    "Gold",                         "Rohstoff", GRUPPE_INDEX_ROHSTOFF),
    ("SI=F",    "Silber",                       "Rohstoff", GRUPPE_INDEX_ROHSTOFF),
    ("CL=F",    "Rohöl WTI",                    "Rohstoff", GRUPPE_INDEX_ROHSTOFF),
]


def slug(ticker):
    """^GDAXI -> gdaxi, GC=F -> gc_f, VOW3.DE -> vow3_de"""
    s = re.sub(r"[^a-z0-9]+", "_", ticker.lower())
    return s.strip("_")


def epochtag(d):
    return (d - EPOCHE).days


def lade_kurse(ticker):
    """Liefert eine sortierte Liste (datum, kurs) ohne Lücken und Ausreißer."""
    df = yf.download(ticker, start=START_DATUM, progress=False, auto_adjust=True)
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


def schreibe_bin(pfad, werte):
    """
    Binärformat (little-endian):
      'BRK1'                      4 B  Magic
      uint32 basisEpochTag             Epochtag des ersten Kurses
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

    kopf = b"BRK1" + struct.pack("<II", basis, anzahl)
    off_bytes = struct.pack(f"<{anzahl}H", *offsets)
    padding = b"\x00" * ((4 - len(off_bytes) % 4) % 4)
    kurs_bytes = struct.pack(f"<{anzahl}f", *[k for _, k in werte])

    with open(pfad, "wb") as f:
        f.write(kopf + off_bytes + padding + kurs_bytes)

    return len(kopf) + len(off_bytes) + len(padding) + len(kurs_bytes)


def main():
    p = argparse.ArgumentParser(description="Exportiert Kursdaten als App-Assets.")
    p.add_argument("--out", default="assets/kurse", help="Zielverzeichnis")
    args = p.parse_args()

    import os
    os.makedirs(args.out, exist_ok=True)

    eintraege = []
    gesamt_bytes = 0
    auffaellig_gesamt = 0

    for ticker, name, kategorie, gruppe in AKTIEN_POOL:
        print(f"-> {ticker} ({name}) ...", flush=True)
        try:
            werte = lade_kurse(ticker)
        except Exception as err:
            print(f"   FEHLER beim Laden: {err}")
            continue

        if len(werte) < MIN_TAGE:
            print(f"   Nur {len(werte)} Kurse – übersprungen.")
            continue

        spanne_jahre = (werte[-1][0] - werte[0][0]).days / 365.25
        if spanne_jahre < 10:
            print(f"   Nur {spanne_jahre:.1f} Jahre Historie – übersprungen.")
            continue

        auffaellig_gesamt += pruefe_auffaellige(ticker, werte)

        datei = f"{slug(ticker)}.bin"
        groesse = schreibe_bin(os.path.join(args.out, datei), werte)
        gesamt_bytes += groesse

        eintraege.append({
            "ticker": ticker,
            "name": name,
            "kategorie": kategorie,
            "gruppe": gruppe,
            "datei": datei,
            "anzahl": len(werte),
            "ersterTag": werte[0][0].isoformat(),
            "letzterTag": werte[-1][0].isoformat(),
            "quelle": "bundled",
        })
        print(f"   {len(werte)} Kurse, {werte[0][0]} – {werte[-1][0]}, {groesse/1024:.0f} KB")

    index = {
        "schemaVersion": 1,
        "erzeugtAm": date.today().isoformat(),
        "quelle": "yfinance",
        "kursAnpassung": "auto_adjust",
        "aktien": eintraege,
    }
    with open(os.path.join(args.out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    print(f"\n=== {len(eintraege)} Aktien exportiert, "
          f"{gesamt_bytes/1024:.0f} KB gesamt ===")
    if auffaellig_gesamt:
        print(f"({auffaellig_gesamt} auffällige Tagesbewegungen – meist echte "
              f"Kursstürze, siehe Hinweise oben.)")


if __name__ == "__main__":
    main()
