import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';

import '../domain/rennen_engine.dart';
import '../theme/arcade_theme.dart';
import 'kamera.dart';
import 'laeufer_daten.dart';
import 'weltkulisse.dart';

/// Die Werte, die als Text im HUD stehen. Als Record: strukturelle Gleichheit
/// gibt es gratis, damit unterdrückt der ValueNotifier No-op-Benachrichtigungen.
typedef HudDaten = ({
  String fortschritt,
  String kurs,
  String stimmung,
  String wertSpieler,
  String wertInvestor,
  String wertSicherheit,
  String? wertWuerfel,
  bool investiert,
});

/// Reiner Repaint-Auslöser für die CustomPainter.
class RepaintNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Treibt die Simulation und verteilt Änderungen auf zwei Kanäle:
///
///  * [repaint] – 60 Hz, löst **nur** ein Neuzeichnen der Canvas aus
///    (kein Widget-Rebuild).
///  * [hud] – auf ~10 Hz gedrosselt, aktualisiert die Textanzeigen.
///
/// Das ist der Kern der Performance-Strategie: Text 60-mal pro Sekunde neu zu
/// formatieren wäre Verschwendung für etwas, das kein Mensch so schnell liest.
class RennenController {
  final RennenEngine engine;
  final TickerProvider vsync;

  final RepaintNotifier repaint = RepaintNotifier();
  late final ValueNotifier<HudDaten> hud;
  final ValueNotifier<bool> pausiert = ValueNotifier(false);
  final ValueNotifier<bool> beendet = ValueNotifier(false);

  /// **Countdown vor Rundenbeginn.**
  ///
  /// Der Spieler sieht den Kursverlauf des letzten Jahres (der eigentliche
  /// Vorlauf, siehe [RundenAuswahl.vorlauf]) und kann sich entscheiden, sofort
  /// zu investieren oder abzuwarten. Ohne Reaktion läuft die Runde nach
  /// [countdownSekunden] automatisch los – dann bleibt der Spieler in Cash,
  /// genau wie beim bisherigen Rundenstart.
  static const int countdownSekunden = 10;
  final ValueNotifier<int> countdown = ValueNotifier(countdownSekunden);
  final ValueNotifier<bool> countdownLaeuft = ValueNotifier(true);
  double _countdownRest = countdownSekunden.toDouble();

  /// Handelstage pro Sekunde.
  double tempo = 30;

  Ticker? _ticker;
  Duration _letzte = Duration.zero;
  double _fortschritt = 0;
  Duration _letztesHud = Duration.zero;

  /// Sichtbares Euro-Fenster (Schwenk schnell, Zoom träge).
  final Kamera kamera = Kamera();

  /// Schilder, Bäume und Wolken mit eigenem Lebenszyklus.
  final Weltkulisse kulisse = Weltkulisse();

  /// Laufzeit in Sekunden – treibt die Eigendrift der Wolken.
  double laufzeit = 0;

  /// **Glättung der Läuferpositionen in Sekunden.**
  ///
  /// Die Depotwerte springen von Handelstag zu Handelstag; bei hohem Tempo sind
  /// das leicht 50 px pro Frame. Angezeigt wird deshalb ein nachgezogener Wert.
  /// Die Figur hinkt ihrem exakten Depotwert um diese Zeit hinterher, steht bei
  /// Pause aber genau richtig. Gewertet wird immer der echte Wert.
  static const double laeuferGlaettungSekunden = 0.30;

  static const double _restAnteil = 0.02;

  /// Anzahl aktiver Läufer: 3, oder 4, wenn der Würfel-Investor mitspielt.
  final int anzahlLaeufer;

  /// Geglättete Depotwerte in der Reihenfolge Spieler, Investor, Sicherheit
  /// (Würfel, falls aktiv). Aus diesen Werten wird auch die Kamera gespeist –
  /// so arbeitet das Sicherheitsnetz der Kamera nie gegen die Glättung.
  final List<double> angezeigteWerte;
  bool _werteInitialisiert = false;

  /// **Stolpern.** Dauer der Kipp-Animation je Läufer, ab dem Auslöse-Puls aus
  /// der Engine ([RennenEngine.stolpertJetzt]).
  static const double stolperDauerSekunden = 0.4;

  /// Verbleibende Stolper-Zeit je Läufer, in Sekunden. 0 = kein Stolpern gerade.
  final List<double> _stolperRest;

  /// Stolper-Intensität je Läufer, 1.0 = gerade ausgelöst, 0.0 = vorbei.
  /// Wird vom Painter direkt gelesen (gleiches Muster wie [angezeigteWerte]).
  final List<double> stolperIntensitaet;

  static final _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
  static final _kursFormat = NumberFormat('#,##0.00', 'de_DE');

  RennenController({required this.engine, required this.vsync})
      : anzahlLaeufer = engine.wuerfelAktiv ? 4 : 3,
        angezeigteWerte = List.filled(engine.wuerfelAktiv ? 4 : 3, 0),
        _stolperRest = List.filled(engine.wuerfelAktiv ? 4 : 3, 0),
        stolperIntensitaet = List.filled(engine.wuerfelAktiv ? 4 : 3, 0) {
    hud = ValueNotifier(_baueHud());
  }

  /// Läufer-Stammdaten für den Renderpfad – ersetzt die früher fest
  /// verdrahtete Dreier-Liste. Bei deaktiviertem Würfel-Investor exakt 3
  /// Einträge mit identischen Werten wie vor dieser Erweiterung.
  List<LaeuferDaten> get laeufer => [
        LaeuferDaten(
          name: 'Du',
          farbe: ArcadeFarben.spieler,
          farbeDunkel: ArcadeFarben.spielerDunkel,
          investiert: engine.spieler.investiert,
        ),
        const LaeuferDaten(
          name: 'Investor',
          farbe: ArcadeFarben.investor,
          farbeDunkel: ArcadeFarben.investorDunkel,
          investiert: true,
        ),
        const LaeuferDaten(
          name: 'Sicherheit',
          farbe: ArcadeFarben.sicherheit,
          farbeDunkel: ArcadeFarben.sicherheitDunkel,
          investiert: false,
        ),
        if (engine.wuerfelAktiv)
          LaeuferDaten(
            name: 'Würfel',
            farbe: ArcadeFarben.wuerfel,
            farbeDunkel: ArcadeFarben.wuerfelDunkel,
            investiert: engine.wuerfel.investiert,
          ),
      ];

  void start() {
    _ticker = vsync.createTicker(_beiTick)..start();
  }

  void _beiTick(Duration verstrichen) {
    var dt = (verstrichen - _letzte).inMicroseconds / 1e6;
    _letzte = verstrichen;

    // Nach Hintergrund/GC-Pausen kann dt sehr groß werden. Ungedeckelt würde
    // die Runde in einem Frame um Monate springen.
    dt = dt.clamp(0.0, 1 / 30);

    if (countdownLaeuft.value) {
      // Auch der Countdown pausiert im Hintergrund – sonst könnte die
      // Bedenkzeit ablaufen, während niemand hinsieht.
      if (!pausiert.value) {
        _countdownRest -= dt;
        final rest = _countdownRest.ceil().clamp(0, countdownSekunden);
        if (rest != countdown.value) countdown.value = rest;
        if (_countdownRest <= 0) _beendeCountdown();
      }
      return;
    }

    if (!pausiert.value && !engine.fertig) {
      _fortschritt += tempo * dt;
      var schritte = _fortschritt.floor();
      if (schritte > 0) {
        _fortschritt -= schritte;
        // Obergrenze je Frame, damit ein langsamer Frame keine Kaskade auslöst.
        if (schritte > 40) schritte = 40;
        while (schritte-- > 0 && !engine.fertig) {
          engine.schritt();
          if (engine.stolpertJetzt) {
            _stolperRest[1] = stolperDauerSekunden; // Investor: immer im Markt.
            if (engine.spieler.investiert) {
              _stolperRest[0] = stolperDauerSekunden; // Spieler: nur wenn investiert.
            }
            // Sicherheit (Index 2): kein Kursrisiko -> stolpert nie.
            if (engine.wuerfelAktiv && engine.wuerfel.investiert) {
              _stolperRest[3] = stolperDauerSekunden; // Würfel: nur wenn investiert.
            }
          }
        }
      }
    }

    // Beinfrequenz aus der Marktstimmung – für alle drei gleich.
    engine.phase += dt * (2 + 8 * engine.stimmung);
    laufzeit += dt;

    for (var i = 0; i < anzahlLaeufer; i++) {
      if (_stolperRest[i] > 0) {
        _stolperRest[i] = (_stolperRest[i] - dt).clamp(0.0, stolperDauerSekunden);
      }
      stolperIntensitaet[i] = _stolperRest[i] / stolperDauerSekunden;
    }

    _aktualisierePositionen(dt);
    repaint.tick();

    if (verstrichen - _letztesHud >= const Duration(milliseconds: 100)) {
      _letztesHud = verstrichen;
      hud.value = _baueHud();
    }

    if (engine.fertig && !beendet.value) {
      hud.value = _baueHud();
      beendet.value = true;
    }
  }

  void _aktualisierePositionen(double dt) {
    final echt = <double>[
      engine.wertSpieler,
      engine.wertInvestor,
      engine.wertSicherheit,
      if (engine.wuerfelAktiv) engine.wertWuerfel!,
    ];

    if (!_werteInitialisiert) {
      for (var i = 0; i < anzahlLaeufer; i++) {
        angezeigteWerte[i] = echt[i];
      }
      _werteInitialisiert = true;
    } else {
      final f = 1 - math.exp(-dt * (-math.log(_restAnteil) / laeuferGlaettungSekunden));
      for (var i = 0; i < anzahlLaeufer; i++) {
        angezeigteWerte[i] += (echt[i] - angezeigteWerte[i]) * f;
      }
    }

    kamera.aktualisiere(angezeigteWerte, dt);
    // Wolken driften zusätzlich leicht von selbst, damit der Himmel auch bei
    // Stillstand lebt.
    kulisse.aktualisiere(kamera, dt, eigenDriftPx: 7.0 * dt);
  }

  /// Rundenfortschritt statt Kalenderdatum.
  ///
  /// Das echte Datum wird bewusst **nicht** angezeigt: Wer weiß, dass gerade
  /// 1999, 2008 oder 2020 läuft, kennt den kommenden Crash und könnte ihn
  /// abwarten. Der Fortschritt zeigt dasselbe Maß an Orientierung, ohne die
  /// Zukunft zu verraten.
  String _fortschrittText() {
    final start = engine.reihe.ersterTag;
    final ende = engine.reihe.letzterTag;
    final jetzt = engine.reihe.epochTag(engine.i);

    final gesamtJahre = ((ende - start) / 365.25).round().clamp(1, 99);
    final vergangen = (jetzt - start) / 365.25;
    final jahr = (vergangen.floor() + 1).clamp(1, gesamtJahre);
    return 'Jahr $jahr von $gesamtJahre';
  }

  HudDaten _baueHud() => (
        fortschritt: _fortschrittText(),
        kurs: _kursFormat.format(engine.kurs),
        stimmung: '${(engine.stimmung * 100).round()} %',
        wertSpieler: _euro.format(engine.wertSpieler),
        wertInvestor: _euro.format(engine.wertInvestor),
        wertSicherheit: _euro.format(engine.wertSicherheit),
        wertWuerfel: engine.wuerfelAktiv ? _euro.format(engine.wertWuerfel!) : null,
        investiert: engine.spieler.investiert,
      );

  void kaufen() {
    engine.kaufen();
    hud.value = _baueHud();
  }

  void verkaufen() {
    engine.verkaufen();
    hud.value = _baueHud();
  }

  /// Sofort investieren, noch während des Countdowns – beendet ihn vorzeitig.
  void investierenImCountdown() {
    engine.kaufen();
    hud.value = _baueHud();
    _beendeCountdown();
  }

  /// Bewusst abwarten – beendet den Countdown vorzeitig, ohne zu investieren.
  void abwartenImCountdown() => _beendeCountdown();

  void _beendeCountdown() {
    if (!countdownLaeuft.value) return;
    countdownLaeuft.value = false;
  }

  /// Beendet die Runde vorzeitig mit dem aktuellen Stand.
  void rundeBeenden() {
    if (beendet.value) return;
    engine.beendeRunde();
    hud.value = _baueHud();
    beendet.value = true;
  }

  void pauseUmschalten() => pausiert.value = !pausiert.value;

  /// Bei Wechsel in den Hintergrund pausieren – sonst läuft die Runde weiter,
  /// während niemand hinsieht.
  void beiLifecycle(AppLifecycleState zustand) {
    if (zustand != AppLifecycleState.resumed) {
      pausiert.value = true;
    }
  }

  void dispose() {
    _ticker?.dispose();
    repaint.dispose();
    hud.dispose();
    pausiert.dispose();
    beendet.dispose();
    countdown.dispose();
    countdownLaeuft.dispose();
  }
}
