import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/aktien_katalog.dart';
import '../domain/kursreihe.dart';
import '../domain/rennen_engine.dart';
import '../render/kurs_chart_painter.dart';
import '../render/rennstrecke_painter.dart';
import '../spiel/rennen_controller.dart';
import '../theme/arcade_theme.dart';
import '../theme/geld.dart';
import '../ui/candy_button.dart';
import '../ui/tempo_regler.dart';
import 'ergebnis_screen.dart';

/// Der Spielbildschirm.
///
/// Layout laut Vorgabe: das **obere Viertel** zeigt den Kursverlauf, darunter
/// liegt die Rennbahn, unten die Bedienelemente.
///
/// `build()` läuft genau einmal pro Runde – die Animation kommt ausschließlich
/// über die Painter (repaint-Listenable) und das gedrosselte HUD.
class RennenScreen extends StatefulWidget {
  final RennenEngine engine;
  final AktienEintrag aktie;
  final Kursreihe vorlauf;
  final String spielername;

  const RennenScreen({
    super.key,
    required this.engine,
    required this.aktie,
    required this.vorlauf,
    this.spielername = '',
  });

  @override
  State<RennenScreen> createState() => _RennenScreenState();
}

class _RennenScreenState extends State<RennenScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final RennenController _controller;
  late final KursChartPainter _chartPainter;
  late final RennstreckePainter _bahnPainter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = RennenController(
        engine: widget.engine, vsync: this, waehrung: widget.aktie.waehrung);
    // Painter einmalig bauen – nicht in build().
    _chartPainter = KursChartPainter(widget.engine,
        vorlauf: widget.vorlauf,
        investiertVerlauf: widget.engine.investiertProTag,
        repaint: _controller.repaint);
    _bahnPainter = RennstreckePainter(_controller, repaint: _controller.repaint);

    _controller.beendet.addListener(_beiEnde);
    _controller.start();

    // Während der Runde darf der Bildschirm nicht abdunkeln – sonst pausiert
    // man ständig ungewollt mitten im Spiel.
    WakelockPlus.enable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.beiLifecycle(state);
  }

  void _beiEnde() {
    if (!_controller.beendet.value || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ErgebnisScreen(
          engine: widget.engine,
          aktie: widget.aktie,
          spielername: widget.spielername,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.beendet.removeListener(_beiEnde);
    _controller.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            // Oberes Viertel für den Kurs – exakt wie gefordert.
            final chartHoehe = c.maxHeight * 0.25;
            return Column(
              children: [
                SizedBox(height: chartHoehe, child: _chartBereich()),
                Expanded(
                  child: Stack(
                    children: [
                      RepaintBoundary(
                          child: CustomPaint(painter: _bahnPainter, size: Size.infinite)),
                      ValueListenableBuilder<bool>(
                        valueListenable: _controller.countdownLaeuft,
                        builder: (context, laeuft, _) =>
                            laeuft ? _countdownOverlay() : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _controller.countdownLaeuft,
                  builder: (context, laeuft, _) =>
                      laeuft ? _countdownBedienung() : _standUndBedienung(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Dunkelt die Rennbahn ab und zeigt die verbleibende Countdown-Zeit groß
  /// über der Strecke – die Läufer stehen noch am Start.
  Widget _countdownOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: ValueListenableBuilder<int>(
            valueListenable: _controller.countdown,
            builder: (context, n, _) => Text(
              '$n',
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 10, color: Colors.black54)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ersetzt während des Countdowns die normale Bedienleiste: Der Spieler
  /// entscheidet, ob er sofort investiert – der Kursverlauf des letzten
  /// Jahres ist dafür schon im Chart darüber zu sehen.
  Widget _countdownBedienung() {
    return Container(
      color: ArcadeFarben.creme,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Gleich alles investieren – oder erst abwarten?',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CandyButton(
                  text: 'Investieren',
                  farbe: ArcadeFarben.kaufen,
                  schatten: ArcadeFarben.kaufenSchatten,
                  onTap: _controller.investierenImCountdown,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CandyButton(
                  text: 'Abwarten',
                  farbe: ArcadeFarben.neutral,
                  schatten: ArcadeFarben.tinteHell,
                  onTap: _controller.abwartenImCountdown,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartBereich() {
    return Container(
      color: ArcadeFarben.cremeHell,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _chartPainter)),
          ),
          Positioned(
            left: 12,
            top: 6,
            right: 12,
            child: ValueListenableBuilder<HudDaten>(
              valueListenable: _controller.hud,
              builder: (context, hud, kind) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${hud.kurs} ${Geld.symbol(widget.aktie.waehrung)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: hud.investiert
                              ? ArcadeFarben.kaufenSchatten
                              : ArcadeFarben.verkaufenSchatten,
                        ),
                      ),
                      Text(
                        hud.fortschritt,
                        style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ArcadeFarben.kursFlaeche.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${hud.stimmung} vom Hoch',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 2,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ArcadeFarben.creme,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Tempo der Läufer folgt der Kurshöhe',
                  style: TextStyle(fontSize: 9, color: ArcadeFarben.tinteHell),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _standUndBedienung() {
    return Container(
      color: ArcadeFarben.creme,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<HudDaten>(
            valueListenable: _controller.hud,
            builder: (context, hud, kind) => Row(
              children: [
                Expanded(
                  child: DepotKarte(
                    titel: 'DU',
                    wert: hud.wertSpieler,
                    farbe: ArcadeFarben.spieler,
                    textFarbe: ArcadeFarben.spielerDunkel,
                    hervorheben: true,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DepotKarte(
                    titel: 'INVESTOR',
                    wert: hud.wertInvestor,
                    farbe: ArcadeFarben.investor,
                    textFarbe: ArcadeFarben.investorDunkel,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DepotKarte(
                    titel: 'SICHER',
                    wert: hud.wertSicherheit,
                    farbe: ArcadeFarben.sicherheit,
                    textFarbe: ArcadeFarben.sicherheitDunkel,
                  ),
                ),
                if (hud.wertWuerfel != null) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: DepotKarte(
                      titel: 'WÜRFEL',
                      wert: hud.wertWuerfel!,
                      farbe: ArcadeFarben.wuerfel,
                      textFarbe: ArcadeFarben.wuerfelDunkel,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<HudDaten>(
            valueListenable: _controller.hud,
            builder: (context, hud, kind) => Row(
              children: [
                Expanded(
                  child: CandyButton(
                    text: 'Alles kaufen',
                    farbe: ArcadeFarben.kaufen,
                    schatten: ArcadeFarben.kaufenSchatten,
                    onTap: hud.investiert ? null : _controller.kaufen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CandyButton(
                    text: 'Alles verkaufen',
                    farbe: ArcadeFarben.verkaufen,
                    schatten: ArcadeFarben.verkaufenSchatten,
                    onTap: hud.investiert ? _controller.verkaufen : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _controller.pausiert,
                builder: (context, pausiert, kind) => IconButton(
                  onPressed: _controller.pauseUmschalten,
                  icon: Icon(pausiert ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: ArcadeFarben.neutral, width: 2),
                  ),
                ),
              ),
              Expanded(
                child: TempoRegler(
                  start: _controller.tempo,
                  onChanged: (v) => _controller.tempo = v,
                ),
              ),
              IconButton(
                onPressed: _rundeBeendenBestaetigen,
                icon: const Icon(Icons.flag_circle_rounded),
                tooltip: 'Runde beenden',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: ArcadeFarben.neutral, width: 2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rundeBeendenBestaetigen() async {
    _controller.pausiert.value = true;
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Runde wirklich beenden?'),
        content: const Text('Der Stand wird sofort ausgewertet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Weiterspielen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Beenden'),
          ),
        ],
      ),
    );
    if (bestaetigt == true) {
      _controller.rundeBeenden();
    } else {
      _controller.pausiert.value = false;
    }
  }
}
