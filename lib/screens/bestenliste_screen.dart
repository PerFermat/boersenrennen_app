import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/bestenliste.dart';
import '../theme/arcade_theme.dart';

/// Lokale Bestenliste, absteigend nach der Outperformance gegenüber dem
/// Investor – dem rankingrelevanten Wert.
class BestenlisteScreen extends StatelessWidget {
  const BestenlisteScreen({super.key});

  static final _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
  static final _datum = DateFormat('MM/yyyy', 'de_DE');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏆 Bestenliste'),
        backgroundColor: ArcadeFarben.creme,
      ),
      body: Consumer<BestenlisteRepository>(
        builder: (context, repo, kind) {
          final eintraege = repo.eintraege;
          if (eintraege.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                  'Noch keine Einträge –\nspiel die erste Runde!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: ArcadeFarben.tinteHell),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: eintraege.length,
            separatorBuilder: (context, i) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _karte(eintraege[i], i + 1),
          );
        },
      ),
    );
  }

  Widget _karte(BestenlisteEintrag e, int platz) {
    final gewonnen = e.scoreVsInvestor > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: gewonnen ? ArcadeFarben.spieler : ArcadeFarben.neutral,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$platz',
              style: TextStyle(
                fontSize: platz <= 3 ? 22 : 17,
                fontWeight: FontWeight.w900,
                color: platz == 1 ? ArcadeFarben.sicherheitDunkel : ArcadeFarben.tinteHell,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.spielername,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                  '${e.aktieName} · ${_datum.format(e.startDatum)}–${_datum.format(e.endDatum)}',
                  style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
                ),
                const SizedBox(height: 3),
                Text(
                  'Du ${_euro.format(e.endbetragSpieler)} · '
                  'Investor ${_euro.format(e.endbetragInvestor)} · '
                  'Sicher ${_euro.format(e.endbetragSicherheit)}',
                  style: const TextStyle(fontSize: 10, color: ArcadeFarben.tinteHell),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${e.scoreVsInvestor > 0 ? '+' : ''}${e.scoreVsInvestor.toStringAsFixed(2)} %',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: gewonnen ? ArcadeFarben.spielerDunkel : ArcadeFarben.verkaufenSchatten,
                ),
              ),
              const Text('vs. Investor',
                  style: TextStyle(fontSize: 9, color: ArcadeFarben.tinteHell)),
              const SizedBox(height: 2),
              Text(
                '${e.scoreVsSicherheit > 0 ? '+' : ''}${e.scoreVsSicherheit.toStringAsFixed(2)} % vs. Sicher',
                style: const TextStyle(fontSize: 9, color: ArcadeFarben.tinteHell),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
