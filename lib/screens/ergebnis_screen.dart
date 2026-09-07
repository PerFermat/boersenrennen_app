import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/aktien_katalog.dart';
import '../data/bestenliste.dart';
import '../domain/kursreihe.dart';
import '../domain/rennen_engine.dart';
import '../domain/score.dart';
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

  static final _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _datum = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.spielername;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _eintragen() async {
    final e = widget.engine;
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
              _zeile('Investor', _euro.format(e.wertInvestor), ArcadeFarben.investorDunkel),
              _zeile('Sicherheit (${e.cfg.zinssatz.toStringAsFixed(2)} %)',
                  _euro.format(e.wertSicherheit), ArcadeFarben.sicherheitDunkel),
              const Divider(height: 24),
              _zeile('Gegenüber Investor', '${vsInvestor.toStringAsFixed(2)} %',
                  gewonnen ? ArcadeFarben.spielerDunkel : ArcadeFarben.verkaufenSchatten,
                  fett: true),
              _zeile('Gegenüber Sicherheit', '${vsSicherheit.toStringAsFixed(2)} %',
                  ArcadeFarben.tinteHell),

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
    );
  }

  Widget _zeile(String links, String rechts, Color farbe, {bool fett = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(links, style: const TextStyle(fontSize: 14)),
            Text(
              rechts,
              style: TextStyle(
                fontSize: fett ? 17 : 15,
                fontWeight: fett ? FontWeight.w900 : FontWeight.w700,
                color: farbe,
              ),
            ),
          ],
        ),
      );
}
