#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tests für die Spleiß-Mechanik aus export_kursdaten.py.

Aufruf (kein Netz nötig, alle Reihen sind synthetisch):
    ./.venv/bin/python tools/test_spleiss.py
"""

import importlib.util
import math
import os
import sys
from datetime import date, timedelta

_spec = importlib.util.spec_from_file_location(
    "ex", os.path.join(os.path.dirname(__file__), "export_kursdaten.py")
)
ex = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ex)


def werktage(start, n):
    tage, d = [], start
    while len(tage) < n:
        if d.weekday() < 5:
            tage.append(d)
        d += timedelta(days=1)
    return tage


def reihe(start, tage, kurs_fuer):
    """Werktagsreihe ab [start] mit [tage] Punkten."""
    return [(d, kurs_fuer(i)) for i, d in enumerate(werktage(start, tage))]


def _pfad(n, seed=1):
    """
    Deterministischer Renditepfad mit echter Varianz.

    Nötig, weil `spleisse` über die Korrelation der **Tagesrenditen** urteilt:
    Eine Reihe mit konstanter Tagesrendite hat keine Varianz und wird – völlig
    korrekt – abgelehnt. Konstante Testreihen prüfen also nichts.
    """
    import random

    r = random.Random(seed)
    return [r.uniform(-0.02, 0.02) for _ in range(n)]


def paar(start, n, ab_index, level_alt, level_neu, stoerung=None):
    """
    Zwei Reihen auf denselben Tagen, die sich denselben Renditepfad teilen.

    [stoerung] mischt der neuen Reihe einen eigenen Pfad bei (0.0 = identisch,
    1.0 = unabhängig) – damit lässt sich die Korrelationsschwelle gezielt
    unterschreiten.
    """
    tage = werktage(start, n)
    r = _pfad(n)
    s = _pfad(n, seed=2)

    alt, k = [], level_alt
    for i, d in enumerate(tage):
        alt.append((d, k))
        k *= 1 + r[i]

    neu, k = [], level_neu
    for i in range(ab_index, n):
        rendite = r[i] if stoerung is None else (1 - stoerung) * r[i] + stoerung * s[i]
        neu.append((tage[i], k))
        k *= 1 + rendite

    return alt, neu


def test_umbasierung_ist_stetig():
    """Am Spleißpunkt darf kein künstlicher Sprung entstehen."""
    alt, neu = paar(date(1990, 1, 1), 900, 500, level_alt=50.0, level_neu=17.0)

    werte, ab, korr, td = ex.spleisse(neu, alt)

    assert ab == neu[0][0], ab
    i = [j for j, (d, _) in enumerate(werte) if d == ab][0]
    # Beide Reihen teilen sich den Renditepfad – der Übergang muss deshalb
    # exakt die Rendite dieses Tages zeigen, nicht einen Niveausprung.
    alt_map = dict(alt)
    erwartet = alt_map[ab] / alt_map[werte[i - 1][0]] - 1
    assert abs(werte[i][1] / werte[i - 1][1] - 1 - erwartet) < 1e-12
    assert abs(korr - 1.0) < 1e-9, korr
    assert abs(td) < 1e-6, td


def test_alte_werte_werden_skaliert_nicht_uebernommen():
    """Vor dem Spleißpunkt steht die alte Reihe mal einem festen Faktor."""
    alt, neu = paar(date(1990, 1, 1), 600, 300, level_alt=100.0, level_neu=25.0)

    werte, ab, _, _ = ex.spleisse(neu, alt)

    alt_map = dict(alt)
    faktoren = [k / alt_map[d] for d, k in werte if d < ab]
    assert faktoren, "keine Werte vor dem Spleißpunkt"
    # Ein einziger, über den ganzen alten Teil konstanter Faktor – keine
    # tagweise Anpassung, die die Renditen verfälschen würde.
    assert max(faktoren) - min(faktoren) < 1e-12, (min(faktoren), max(faktoren))


def test_zu_kurze_ueberlappung_wird_abgelehnt():
    alt, neu = paar(date(1990, 1, 1), 400, 350, level_alt=10.0, level_neu=10.0)

    try:
        ex.spleisse(neu, alt)
    except ValueError as err:
        assert "Überlappung zu kurz" in str(err), err
    else:
        raise AssertionError("zu kurze Überlappung wurde akzeptiert")


def test_unkorrelierte_reihen_werden_abgelehnt():
    """Der Wächter, der XLV <- FSPHX aussortiert hat."""
    alt, neu = paar(date(1990, 1, 1), 900, 0, level_alt=10.0, level_neu=10.0,
                    stoerung=1.0)

    try:
        ex.spleisse(neu, alt)
    except ValueError as err:
        assert "Renditekorrelation" in str(err), err
    else:
        raise AssertionError("unkorrelierte Reihen wurden gespleißt")


def test_die_korrelationsschwelle_trennt_an_der_richtigen_stelle():
    """
    Klemmt die Schwelle ein, statt nur den Extremfall zu prüfen.

    Ein Wächter, der alles ablehnt, bestünde jeden Test mit unkorrelierten
    Reihen. Hier liegt ein Paar knapp über und eines knapp unter 0,90 – nur
    wenn beide richtig einsortiert werden, trennt die Schwelle wirklich dort,
    wo sie soll. Das untere Paar entspricht in etwa dem real gemessenen
    XLV <- FSPHX (0,809), das deshalb nicht im SPLEISS_POOL steht.
    """
    knapp_drueber, _ = None, None
    alt, neu = paar(date(1990, 1, 1), 900, 0, 10.0, 10.0, stoerung=0.30)
    _, _, knapp_drueber, _ = ex.spleisse(neu, alt)
    assert knapp_drueber >= ex.MIN_KORRELATION, knapp_drueber
    assert knapp_drueber < 0.95, f"Testpaar zu ähnlich, prüft die Schwelle nicht: {knapp_drueber}"

    alt, neu = paar(date(1990, 1, 1), 900, 0, 10.0, 10.0, stoerung=0.33)
    try:
        _, _, korr, _ = ex.spleisse(neu, alt)
    except ValueError as err:
        assert "Renditekorrelation" in str(err), err
    else:
        raise AssertionError(f"Korrelation {korr:.3f} wurde akzeptiert")


def test_korrelation_kennt_die_randfaelle():
    assert ex._korrelation([], []) == 0.0
    assert ex._korrelation([1.0], [1.0]) == 0.0
    # Konstante Reihe hat keine Varianz -> 0 statt Division durch null.
    assert ex._korrelation([1.0, 1.0, 1.0], [1.0, 2.0, 3.0]) == 0.0
    assert abs(ex._korrelation([1.0, 2.0, 3.0], [2.0, 4.0, 6.0]) - 1.0) < 1e-12
    assert abs(ex._korrelation([1.0, 2.0, 3.0], [3.0, 2.0, 1.0]) + 1.0) < 1e-12


def test_negativer_basistag_ueberlebt_den_roundtrip():
    """Der S&P 500 beginnt vor der Unix-Epoche."""
    werte = reihe(date(1927, 12, 30), 300, lambda i: 20.0 + i * 0.01)
    daten = ex.baue_bin(werte)

    import struct
    basis, anzahl = struct.unpack_from("<iI", daten, 4)
    assert basis < 0, basis
    assert ex.EPOCHE + timedelta(days=basis) == werte[0][0]
    assert anzahl == len(werte)


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"  ok  {t.__name__}")
    print(f"\n{len(tests)} Tests bestanden.")


if __name__ == "__main__":
    main()
