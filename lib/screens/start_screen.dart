import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/kursdaten_repository.dart';
import '../domain/rennen_engine.dart';
import '../domain/runden_waehler.dart';
import '../domain/spiel_konfiguration.dart';
import '../theme/arcade_theme.dart';
import '../ui/candy_button.dart';
import 'bestenliste_screen.dart';
import 'profil_screen.dart';
import 'rennen_screen.dart';

/// Startbildschirm: Zinssatz, Name und Rundenlänge wählen, dann losrennen.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

/// `null` bedeutet "alle Gruppen gemeinsam" (Zufällig).
const _gruppen = <String?>[
  null,
  'Einzelaktien',
  'Welt-ETF',
  'Themen-Länder-ETF',
  'Index-Rohstoff',
  'Historisch',
];
const _gruppenLabel = <String?, String>{
  null: 'Zufällig',
  'Einzelaktien': 'Einzelaktien',
  'Welt-ETF': 'Welt-ETFs',
  'Themen-Länder-ETF': 'Themen/Länder-ETFs',
  'Index-Rohstoff': 'Indizes/Rohstoffe',
  'Historisch': 'Historisch',
};

/// Hinweise, die nur für einzelne Gruppen gelten.
///
/// Über "Zufällig" sind die historischen Reihen nur in rund 3–5 % der Runden
/// dabei; wer sie gezielt wählt, soll wissen, worin sie sich unterscheiden.
const _gruppenHinweis = <String?, String>{
  'Historisch': 'Reicht bis 1927 zurück: Weltwirtschaftskrise, Ölkrise, '
      'japanische Blase. Die Indizes sind Kursindizes ohne Dividenden; die '
      'Sektor-Reihen zeigen vor Auflage des ETF einen Vorgängerfonds. Der '
      'S&P 500 rechnet in Dollar – vor 1957 gibt es keinen Euro-Gegenwert. '
      'Die Kaufkraftrechnung bleibt in alten Runden aus (Inflationsdaten erst '
      'ab 1992), die Steuerlogik rechnet mit heutigem Recht.',
};

class _StartScreenState extends State<StartScreen> {
  double _zinssatz = 3.0;
  int _rundenJahre = 10;
  String? _gruppe;
  bool _steuernAktiv = false;
  bool _wuerfelAn = true;
  final _nameController = TextEditingController();
  bool _laedt = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Zeigt einen Hinweis, statt den Startknopf wortlos wieder freizugeben.
  void _melde(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _rundeStarten() async {
    setState(() => _laedt = true);
    final repo = context.read<KursdatenRepository>();
    final random = Random();
    var gestartet = false;

    try {
      final katalog = await repo.katalog();
      // Mehrere Versuche, falls der gezogene Titel zwar lang genug ist, der
      // gezogene Startzeitpunkt aber keinen vollen Ausschnitt mehr hergibt.
      for (var versuch = 0; versuch < 12; versuch++) {
        final aktie = repo.zufall(katalog, random,
            minJahre: _rundenJahre.toDouble(), gruppe: _gruppe);
        if (aktie == null) {
          _melde('Für $_rundenJahre Jahre gibt es in dieser Gruppe keinen Titel '
              'mit genug Historie. Wähle eine kürzere Runde oder eine andere Gruppe.');
          return;
        }
        final reihe = await repo.lade(aktie);
        final auswahl = RundenWaehler(random).waehle(reihe, rundenJahre: _rundenJahre);
        if (auswahl == null) continue;

        final engine = RennenEngine(
          auswahl.ausschnitt,
          SpielKonfiguration(
            zinssatz: _zinssatz,
            steuernAktiv: _steuernAktiv,
            teilfreistellung: SpielKonfiguration.teilfreistellungFuerGruppe(aktie.gruppe),
          ),
          vorlauf: auswahl.vorlauf,
          wuerfelAktiv: _wuerfelAn,
          wuerfelSeed: random.nextInt(1 << 32),
        );
        if (!mounted) return;
        gestartet = true;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RennenScreen(
              engine: engine,
              aktie: aktie,
              vorlauf: auswahl.vorlauf,
              spielername: _nameController.text.trim(),
            ),
          ),
        );
        break;
      }
      if (!gestartet) {
        _melde('Es ließ sich kein passender Zeitraum von $_rundenJahre Jahren '
            'ziehen. Versuch es noch einmal oder wähle eine kürzere Runde.');
      }
    } catch (fehler) {
      // Bewusst ohne `on`-Klausel: die relevanten Fälle sind teils Exception
      // (FormatException aus dem Codec), teils Error (UnsupportedError bei
      // unbekannter Quelle, FlutterError bei fehlendem Asset). Ohne diesen
      // Zweig verschwand nur der Ladeindikator und der Nutzer stand ohne
      // jede Erklärung wieder vor dem Startmenü.
      _melde('Die Kursdaten konnten nicht geladen werden: $fehler');
    } finally {
      if (mounted) setState(() => _laedt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text('🏁', style: TextStyle(fontSize: 46), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              const Text(
                'Börsenrennen',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ArcadeFarben.neutral, width: 2),
                ),
                child: const Text(
                  'Drei Strategien, dieselbe Aktie:\n'
                  '🟢 Du – kaufst und verkaufst selbst\n'
                  '🔵 Investor – immer voll investiert\n'
                  '🟡 Sicherheit – fester Zins\n\n'
                  'Welche Aktie und welcher Zeitraum gespielt werden, '
                  'bleibt bis zum Ziel geheim.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
              ),
              const SizedBox(height: 18),
              _feldTitel('Zinssatz der Sicherheit'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _zinssatz,
                      min: 0,
                      max: 10,
                      divisions: 40,
                      onChanged: (v) => setState(() => _zinssatz = v),
                    ),
                  ),
                  SizedBox(
                    width: 62,
                    child: Text(
                      '${_zinssatz.toStringAsFixed(2)} %',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _feldTitel('Rundenlänge'),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('5 Jahre')),
                  ButtonSegment(value: 10, label: Text('10 Jahre')),
                  ButtonSegment(value: 20, label: Text('20 Jahre')),
                ],
                selected: {_rundenJahre},
                onSelectionChanged: (s) => setState(() => _rundenJahre = s.first),
              ),
              const SizedBox(height: 16),
              _feldTitel('Welche Art Aktie?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in _gruppen)
                    ChoiceChip(
                      label: Text(_gruppenLabel[g]!),
                      selected: _gruppe == g,
                      onSelected: (_) => setState(() => _gruppe = g),
                    ),
                ],
              ),
              if (_gruppenHinweis[_gruppe] != null) ...[
                const SizedBox(height: 8),
                Text(
                  _gruppenHinweis[_gruppe]!,
                  style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Steuern berücksichtigen', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Abgeltungsteuer auf realisierte Gewinne – der Investor zahlt erst am Schluss.',
                  style: TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
                ),
                value: _steuernAktiv,
                onChanged: (v) => setState(() => _steuernAktiv = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Würfel-Investor', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Ein vierter Läufer, der zufällig ein- und aussteigt – manchmal gewinnt er.',
                  style: TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
                ),
                value: _wuerfelAn,
                onChanged: (v) => setState(() => _wuerfelAn = v),
              ),
              const SizedBox(height: 16),
              _feldTitel('Dein Name (für die Bestenliste)'),
              TextField(
                controller: _nameController,
                maxLength: 50,
                decoration: InputDecoration(
                  hintText: 'z. B. Michael',
                  filled: true,
                  fillColor: Colors.white,
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              _laedt
                  ? const Center(child: CircularProgressIndicator())
                  : CandyButton(
                      text: 'Runde starten',
                      farbe: ArcadeFarben.kaufen,
                      schatten: ArcadeFarben.kaufenSchatten,
                      icon: Icons.flag_rounded,
                      onTap: _rundeStarten,
                    ),
              const SizedBox(height: 10),
              CandyButton(
                text: 'Bestenliste',
                farbe: ArcadeFarben.investor,
                schatten: ArcadeFarben.investorDunkel,
                icon: Icons.emoji_events_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BestenlisteScreen()),
                ),
              ),
              const SizedBox(height: 10),
              CandyButton(
                text: 'Mein Profil',
                farbe: ArcadeFarben.sicherheit,
                schatten: ArcadeFarben.sicherheitDunkel,
                icon: Icons.insights_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfilScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feldTitel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: ArcadeFarben.tinteHell,
          ),
        ),
      );
}
