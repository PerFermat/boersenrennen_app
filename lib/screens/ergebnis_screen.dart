import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/aktien_katalog.dart';
import '../data/bestenliste.dart';
import '../data/erfolge_repository.dart';
import '../data/spielverlauf.dart';
import '../domain/auswertung.dart';
import '../domain/erfolge.dart';
import '../domain/kursreihe.dart';
import '../domain/monte_carlo.dart';
import '../domain/rennen_engine.dart';
import '../domain/score.dart';
import '../render/monte_carlo_painter.dart';
import '../theme/arcade_theme.dart';
import '../ui/candy_button.dart';
import 'bestenliste_screen.dart';

/// Zeigt den Endstand, löst die geheime Aktie auf und trägt in die
/// lokale Bestenliste ein.
class ErgebnisScreen extends StatefulWidget {
  final RennenEngine engine;
  final AktienEintrag aktie;
  final String spielername;

  const ErgebnisScreen({
    super.key,
    required this.engine,
    required this.aktie,
    this.spielername = '',
  });

  @override
  State<ErgebnisScreen> createState() => _ErgebnisScreenState();
}

class _ErgebnisScreenState extends State<ErgebnisScreen> {
  final _nameController = TextEditingController();
  bool _gespeichert = false;
  Future<MonteCarloErgebnis>? _monteCarlo;

  List<ErfolgId> _neuFreigeschaltet = [];
  bool _hatBisEndeGescrollt = false;

  /// Einmalig in initState() berechnet statt in build() – build() läuft bei
  /// jedem Rebuild (z. B. während der Monte-Carlo-FutureBuilder auflöst)
  /// erneut, eine erneute Berechnung wäre reine Verschwendung.
  late final RundenAuswertung auswertung;

  static final _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _datum = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.spielername;

    final engine = widget.engine;
    auswertung = RundenAuswertung.aus(engine);
    if (engine.trades.isNotEmpty) {
      _monteCarlo = compute(
        simuliereMonteCarlo,
        MonteCarloArgs(
          reihe: engine.reihe.materialisiert(),
          cfg: engine.cfg,
          anzahlTrades: engine.trades.length,
          ersteAktionIstKauf: engine.trades.first.istKauf,
          tatsaechlicherEndwert: engine.wertSpieler,
          laeufe: 1000,
          seed: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    _protokolliereVerlauf();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Schreibt diese Runde unabhängig von der Bestenliste ins rundenübergreifende
  /// Spielprotokoll (V11) – Grundlage für das Verhaltensprofil und die Erfolge.
  Future<void> _protokolliereVerlauf() async {
    final e = widget.engine;
    final ergebnis = _monteCarlo == null ? null : await _monteCarlo;
    final gesamtTage = auswertung.tageInvestiert + auswertung.tageAussen;
    final eintrag = SpielverlaufEintrag(
      erstelltAm: DateTime.now().toUtc(),
      startDatum: Kursreihe.zuDatum(e.reihe.ersterTag),
      ticker: widget.aktie.ticker,
      gruppe: widget.aktie.gruppe,
      rundenjahre: (e.reihe.epochTag(e.i) - e.reihe.ersterTag) / 365.25,
      anzahlKaeufe: auswertung.anzahlKaeufe,
      anzahlVerkaeufe: auswertung.anzahlVerkaeufe,
      anteilInvestierterTage: gesamtTage == 0 ? 0 : auswertung.tageInvestiert / gesamtTage,
      perzentil: ergebnis?.perzentil,
      scoreVsInvestor: Score.vsInvestor(e.wertSpieler, e.wertInvestor),
      marktRenditeRunde: e.reihe.kurs(e.i) / e.reihe.kurs(0) - 1,
      abstandVerkaufZuTiefTage: auswertung.abstandVerkaufZuTiefTage,
      abstandKaufZuHochTage: auswertung.abstandKaufZuHochTage,
      anteilVerkaeufeNachCrash: auswertung.anteilVerkaeufeNachCrash,
    );
    if (!mounted) return;
    final verlaufRepo = context.read<SpielverlaufRepository>();
    await verlaufRepo.hinzufuegen(eintrag);
    if (!mounted) return;

    final verlauf = verlaufRepo.eintraege;
    final neu = await context.read<ErfolgeRepository>().werteRundeAus(
          reihe: e.reihe,
          investiertProTag: e.investiertProTag,
          rundenjahre: eintrag.rundenjahre,
          anzahlVerkaeufe: eintrag.anzahlVerkaeufe,
          scoreVsInvestor: eintrag.scoreVsInvestor,
          perzentil: eintrag.perzentil,
          startDatenAllerRunden: verlauf.map((v) => v.startDatum).toList(),
          marktRenditenAllerRunden: verlauf.map((v) => v.marktRenditeRunde).toList(),
          anzahlRundenGesamt: verlauf.length,
        );
    if (mounted && neu.isNotEmpty) {
      setState(() => _neuFreigeschaltet = [..._neuFreigeschaltet, ...neu]);
    }
  }

  /// Einmal pro Bildschirmaufruf, sobald bis zum Ende der Auswertung gescrollt
  /// wurde – Grundlage für den „Selbsterkenntnis"-Erfolg (V14).
  Future<void> _vermerkeGescrollt() async {
    _hatBisEndeGescrollt = true;
    final neu = await context.read<ErfolgeRepository>().vermerkeAuswertungGescrollt();
    if (mounted && neu.isNotEmpty) {
      setState(() => _neuFreigeschaltet = [..._neuFreigeschaltet, ...neu]);
    }
  }

  Future<void> _eintragen() async {
    final e = widget.engine;
    final ergebnis = _monteCarlo == null ? null : await _monteCarlo;
    if (!mounted) return;
    final eintrag = BestenlisteEintrag(
      spielername: _nameController.text.trim().isEmpty ? 'Anonym' : _nameController.text.trim(),
      ticker: widget.aktie.ticker,
      aktieName: widget.aktie.name,
      startDatum: Kursreihe.zuDatum(e.reihe.ersterTag),
      endDatum: Kursreihe.zuDatum(e.reihe.letzterTag),
      endbetragSpieler: e.wertSpieler,
      endbetragInvestor: e.wertInvestor,
      endbetragSicherheit: e.wertSicherheit,
      zinssatzSicherheit: e.cfg.zinssatz,
      scoreVsInvestor: Score.vsInvestor(e.wertSpieler, e.wertInvestor),
      scoreVsSicherheit: Score.vsSicherheit(e.wertSpieler, e.wertSicherheit),
      erstelltAm: DateTime.now().toUtc(),
      endbetragWuerfel: e.wuerfelAktiv ? e.wertWuerfel : null,
      perzentil: ergebnis?.perzentil,
    );
    await context.read<BestenlisteRepository>().hinzufuegen(eintrag);
    if (mounted) setState(() => _gespeichert = true);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final vsInvestor = Score.vsInvestor(e.wertSpieler, e.wertInvestor);
    final vsSicherheit = Score.vsSicherheit(e.wertSpieler, e.wertSicherheit);
    final gewonnen = vsInvestor > 0;

    return Scaffold(
      body: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (!_hatBisEndeGescrollt &&
                notification.metrics.pixels >= notification.metrics.maxScrollExtent) {
              _vermerkeGescrollt();
            }
            return false;
          },
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(gewonnen ? '🏆' : '🏁',
                  style: const TextStyle(fontSize: 50), textAlign: TextAlign.center),
              Text(
                gewonnen ? 'Du hast den Investor geschlagen!' : 'Ziel erreicht',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              if (_neuFreigeschaltet.isNotEmpty) ...[
                const SizedBox(height: 12),
                _erfolgeBanner(),
              ],
              const SizedBox(height: 16),

              // Auflösung der geheimen Aktie
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ArcadeFarben.kursFlaeche.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text('Gespielt wurde',
                        style: TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell)),
                    const SizedBox(height: 2),
                    Text(widget.aktie.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    Text(
                      '${_datum.format(Kursreihe.zuDatum(e.reihe.ersterTag))}'
                      ' – ${_datum.format(Kursreihe.zuDatum(e.reihe.letzterTag))}',
                      style: const TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _zeile('Dein Depot', _euro.format(e.wertSpieler), ArcadeFarben.spielerDunkel, fett: true),
              _kaufkraftZeile(auswertung.endwertSpielerReal),
              _zeile('Investor', _euro.format(e.wertInvestor), ArcadeFarben.investorDunkel),
              _kaufkraftZeile(auswertung.endwertInvestorReal),
              _zeile('Sicherheit (${e.cfg.zinssatz.toStringAsFixed(2)} %)',
                  _euro.format(e.wertSicherheit), ArcadeFarben.sicherheitDunkel),
              _kaufkraftZeile(auswertung.endwertSicherheitReal,
                  hervorheben: auswertung.sicherheitRealUnterEinzahlungen),
              if (e.wuerfelAktiv)
                _zeile('Würfel-Investor', _euro.format(e.wertWuerfel!), ArcadeFarben.wuerfelDunkel),
              const SizedBox(height: 4),
              Text(
                'In diesem Zeitraum verlor der Euro '
                '${(100 * (1 - 1 / auswertung.preisfaktorGesamt)).toStringAsFixed(0)} % seiner Kaufkraft.',
                style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
              ),
              if (auswertung.sicherheitRealUnterEinzahlungen) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ArcadeFarben.verkaufen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Real – nach Kaufkraft – liegt die Sicherheit sogar unter der Summe '
                    'deiner Einzahlungen.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ArcadeFarben.verkaufenSchatten),
                  ),
                ),
              ],
              const Divider(height: 24),
              _zeile('Gegenüber Investor', '${vsInvestor.toStringAsFixed(2)} %',
                  gewonnen ? ArcadeFarben.spielerDunkel : ArcadeFarben.verkaufenSchatten,
                  fett: true),
              _zeile('Gegenüber Sicherheit', '${vsSicherheit.toStringAsFixed(2)} %',
                  ArcadeFarben.tinteHell),

              const Divider(height: 24),
              _zeile('Tage investiert',
                  '${auswertung.tageInvestiert} von ${auswertung.tageInvestiert + auswertung.tageAussen}',
                  ArcadeFarben.tinteHell),
              _zeile('Käufe / Verkäufe',
                  '${auswertung.anzahlKaeufe} / ${auswertung.anzahlVerkaeufe}',
                  ArcadeFarben.tinteHell),
              if (auswertung.durchschnittlicheHaltedauerTage != null)
                _zeile('Ø Haltedauer',
                    '${auswertung.durchschnittlicheHaltedauerTage!.round()} Tage',
                    ArcadeFarben.tinteHell),

              if (auswertung.durchschnittlicherKaufkurs != null ||
                  auswertung.durchschnittlicherVerkaufskurs != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ArcadeFarben.kursFlaeche.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Text('Ø Kaufkurs gegen Ø Verkaufskurs',
                          style: TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _kursSpalte('Gekauft für',
                              auswertung.durchschnittlicherKaufkurs, ArcadeFarben.verkaufenSchatten),
                          _kursSpalte('Verkauft für',
                              auswertung.durchschnittlicherVerkaufskurs, ArcadeFarben.spielerDunkel),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              if (auswertung.besterTrade != null)
                _zeile('Bester Trade',
                    _euro.format(auswertung.besterTrade!.gewinnBeiVerkauf),
                    ArcadeFarben.spielerDunkel),
              if (auswertung.schlechtesterTrade != null)
                _zeile('Schlechtester Trade',
                    _euro.format(auswertung.schlechtesterTrade!.gewinnBeiVerkauf),
                    ArcadeFarben.verkaufenSchatten),

              if (e.cfg.steuernAktiv) ...[
                const Divider(height: 24),
                const Text('Abgeltungsteuer',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                _zeile('Gezahlte Steuer (Du)', _euro.format(e.gezahlteSteuerSpieler),
                    ArcadeFarben.verkaufenSchatten),
                _zeile('Gezahlte Steuer (Sicherheit)', _euro.format(e.gezahlteSteuerSicherheit),
                    ArcadeFarben.tinteHell),
                _zeile('Latente Steuer (Investor, noch nicht gezahlt)',
                    _euro.format(e.latenteSteuerInvestor), ArcadeFarben.tinteHell),
                const SizedBox(height: 6),
                Text(
                  'Dein Handeln hat ${_euro.format(auswertung.steuerNachteilGegenInvestor.abs())} '
                  '${auswertung.steuerNachteilGegenInvestor >= 0 ? "mehr" : "weniger"} Steuer ausgelöst '
                  'als der Investor, der seine Steuer bis zum Schluss gestundet und in der Zeit '
                  'weiterverzinst bekommen hat.',
                  style: const TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell),
                ),
              ],

              const Divider(height: 24),
              if (auswertung.tageAussen == 0)
                const Text(
                  'Du warst die ganze Runde investiert – keinen einzigen Handelstag verpasst.',
                  style: TextStyle(fontSize: 13, color: ArcadeFarben.tinteHell),
                )
              else ...[
                const Text('Verpasste und vermiedene Börsentage',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _tageSpalte(
                          'Verpasst', auswertung.verpassteTopTage, ArcadeFarben.verkaufenSchatten),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _tageSpalte(
                          'Vermieden', auswertung.vermiedeneTopTage, ArcadeFarben.spielerDunkel),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _zeile('Nettobilanz', _euro.format(auswertung.nettoBilanz),
                    auswertung.nettoBilanz >= 0
                        ? ArcadeFarben.spielerDunkel
                        : ArcadeFarben.verkaufenSchatten),
                const SizedBox(height: 8),
                if (auswertung.verpassteTopTage.isNotEmpty)
                  Text(
                    '${auswertung.clusterAnteil} deiner ${auswertung.verpassteTopTage.length} '
                    'verpassten Top-Tage lagen innerhalb von '
                    '${RundenAuswertung.clusterFensterTage} Handelstagen nach einem Crash-Tag.',
                    style: const TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'Die besten und die schlechtesten Börsentage liegen häufig in denselben '
                  'Wochen – wer die Crashtage meiden will, verpasst meist auch die Erholung.',
                  style: TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell),
                ),
              ],

              const Divider(height: 24),
              const Text('Wie gut war dein Timing wirklich?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (_monteCarlo == null)
                const Text(
                  'Ohne Handelsentscheidung gibt es nichts einzuordnen.',
                  style: TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell),
                )
              else
                FutureBuilder<MonteCarloErgebnis>(
                  future: _monteCarlo,
                  builder: (context, snapshot) {
                    final ergebnis = snapshot.data;
                    if (ergebnis == null) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _zeile('Besser als', '${ergebnis.perzentil.toStringAsFixed(0)} % der Läufe',
                            ArcadeFarben.spielerDunkel, fett: true),
                        Text(
                          '${ergebnis.laeufe} Zufallsläufe mit gleich vielen Trades wie du',
                          style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 60,
                          child: CustomPaint(
                            painter: MonteCarloPainter(ergebnis, e.wertSpieler),
                            size: Size.infinite,
                          ),
                        ),
                      ],
                    );
                  },
                ),

              const Divider(height: 24),
              const Text('Wie viel davon war Timing, wie viel Zufall?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _zeile('Tatsächlich', _euro.format(e.wertSpieler), ArcadeFarben.spielerDunkel,
                  fett: true),
              for (final v in auswertung.versatzErgebnisse)
                _zeile(
                  '${v.handelstage > 0 ? "+" : ""}${v.handelstage} Handelstage verschoben',
                  _euro.format(v.endwert),
                  ArcadeFarben.tinteHell,
                ),
              if (auswertung.timingWarUeberwiegendRauschen) ...[
                const SizedBox(height: 6),
                const Text(
                  'Die Streuung durch reine Verschiebung ist größer als der Abstand zum '
                  'Investor – das Ergebnis war überwiegend Rauschen.',
                  style: TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell),
                ),
              ],

              if (auswertung.geldgewichteteRenditeSpieler != null &&
                  auswertung.zeitgewichteteRenditeTitel != null) ...[
                const Divider(height: 24),
                const Text('Behavior Gap',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _zeile('Marktrendite (p. a.)',
                    '${(auswertung.zeitgewichteteRenditeTitel! * 100).toStringAsFixed(1)} %',
                    ArcadeFarben.tinteHell),
                _zeile('Deine Rendite (p. a.)',
                    '${(auswertung.geldgewichteteRenditeSpieler! * 100).toStringAsFixed(1)} %',
                    ArcadeFarben.spielerDunkel),
                _zeile(
                  'Differenz',
                  '${((auswertung.geldgewichteteRenditeSpieler! - auswertung.zeitgewichteteRenditeTitel!) * 100).toStringAsFixed(1)} Prozentpunkte',
                  ArcadeFarben.tinteHell,
                  fett: true,
                ),
                if (auswertung.behaviorGapEuro != null) ...[
                  const SizedBox(height: 6),
                  _zeile('Lücke in Euro', _euro.format(auswertung.behaviorGapEuro!.abs()),
                      ArcadeFarben.verkaufenSchatten),
                  _zeile('Entspricht Monatseinzahlungen',
                      '${auswertung.behaviorGapInMonatsEinzahlungen!.abs()}',
                      ArcadeFarben.verkaufenSchatten),
                ],
              ],

              if (auswertung.teuersterKlick != null) ...[
                const SizedBox(height: 20),
                _teuersterKlickKarte(auswertung.teuersterKlick!),
              ],

              const SizedBox(height: 20),
              if (!_gespeichert) ...[
                TextField(
                  controller: _nameController,
                  maxLength: 50,
                  decoration: InputDecoration(
                    labelText: 'Name für die Bestenliste',
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                CandyButton(
                  text: 'In Bestenliste eintragen',
                  farbe: ArcadeFarben.kaufen,
                  schatten: ArcadeFarben.kaufenSchatten,
                  icon: Icons.emoji_events_rounded,
                  onTap: _eintragen,
                ),
              ] else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ArcadeFarben.spieler.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('✓ In der Bestenliste eingetragen',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              const SizedBox(height: 10),
              CandyButton(
                text: 'Bestenliste ansehen',
                farbe: ArcadeFarben.investor,
                schatten: ArcadeFarben.investorDunkel,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BestenlisteScreen()),
                ),
              ),
              const SizedBox(height: 10),
              CandyButton(
                text: 'Neue Runde',
                farbe: ArcadeFarben.sicherheit,
                schatten: ArcadeFarben.sicherheitDunkel,
                onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _erfolgeBanner() {
    final definitionen = {for (final d in Erfolge.alle) d.id: d};
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArcadeFarben.sicherheit.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArcadeFarben.sicherheitDunkel, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in _neuFreigeschaltet)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '🏅 Neuer Erfolg: ${definitionen[id]!.titel}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: ArcadeFarben.sicherheitDunkel),
              ),
            ),
        ],
      ),
    );
  }

  Widget _teuersterKlickKarte(TeuersterKlick k) {
    final titel = k.istBesterKlick ? 'Dein bester Klick' : 'Der teuerste Klick';
    final aktion = k.trade.istKauf ? 'Kauf' : 'Verkauf';
    final farbe = k.istBesterKlick ? ArcadeFarben.spielerDunkel : ArcadeFarben.verkaufenSchatten;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: farbe, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titel,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: farbe)),
          const SizedBox(height: 8),
          Text('$aktion am ${_datum.format(Kursreihe.zuDatum(k.trade.epochTag))}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _zeile('Depotwert in diesem Moment', _euro.format(k.trade.depotwertDanach),
              ArcadeFarben.tinteHell),
          _zeile('Dein Endstand', _euro.format(k.endstandTatsaechlich), ArcadeFarben.tinteHell),
          _zeile('Endstand ohne diesen einen Klick', _euro.format(k.endstandOhneKlick),
              ArcadeFarben.tinteHell),
          _zeile('Diese eine Entscheidung ${k.istBesterKlick ? "brachte" : "kostete"}',
              _euro.format(k.kosten.abs()), farbe, fett: true),
        ],
      ),
    );
  }

  // Beide Seiten in Expanded, sonst läuft ein langer Wert (z. B. "78 % von
  // 1000 Zufallsläufen …") über den Bildschirmrand hinaus statt umzubrechen.
  Widget _zeile(String links, String rechts, Color farbe, {bool fett = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(links, style: const TextStyle(fontSize: 14))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                rechts,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: fett ? 17 : 15,
                  fontWeight: fett ? FontWeight.w900 : FontWeight.w700,
                  color: farbe,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _kaufkraftZeile(double realerWert, {bool hervorheben = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Text(
              '≈ ${_euro.format(realerWert)} Kaufkraft von Rundenbeginn',
              style: TextStyle(
                fontSize: 11,
                color: hervorheben ? ArcadeFarben.verkaufenSchatten : ArcadeFarben.tinteHell,
                fontWeight: hervorheben ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ],
        ),
      );

  Widget _tageSpalte(String titel, List<TopTag> tage, Color farbe) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: farbe)),
          const SizedBox(height: 4),
          if (tage.isEmpty)
            const Text('–', style: TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell))
          else
            for (final t in tage)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_datum.format(Kursreihe.zuDatum(t.epochTag)),
                        style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell)),
                    Text(
                      '${(t.tagesrendite * 100).toStringAsFixed(1)} % · ${_euro.format(t.betrag)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: farbe),
                    ),
                  ],
                ),
              ),
        ],
      );

  Widget _kursSpalte(String titel, double? kurs, Color farbe) => Column(
        children: [
          Text(titel, style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell)),
          const SizedBox(height: 2),
          Text(
            kurs == null ? '–' : _euro.format(kurs),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: farbe),
          ),
        ],
      );
}
