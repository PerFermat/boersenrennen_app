import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/bestenliste.dart';
import '../theme/arcade_theme.dart';
import '../theme/geld.dart';

/// Lokale Bestenliste, absteigend nach der Outperformance gegenüber dem
/// Investor – dem rankingrelevanten Wert.
class BestenlisteScreen extends StatelessWidget {
  const BestenlisteScreen({super.key});

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
            itemCount: eintraege.length + 1,
            separatorBuilder: (context, i) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Sortiert nach Perzentil – normiert innerhalb jeder Runde, dadurch über '
                    'verschiedene Aktien hinweg vergleichbar. Einträge ohne Perzentil (vor '
                    'diesem Update gespielt) stehen hinten.',
                    style: TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell),
                  ),
                );
              }
              return _karte(eintraege[i - 1], i);
            },
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
                  'Du ${Geld.betrag(e.waehrung, nachkomma: 0).format(e.endbetragSpieler)} · '
                  'Investor ${Geld.betrag(e.waehrung, nachkomma: 0).format(e.endbetragInvestor)} · '
                  'Sicher ${Geld.betrag(e.waehrung, nachkomma: 0).format(e.endbetragSicherheit)}',
                  style: const TextStyle(fontSize: 10, color: ArcadeFarben.tinteHell),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                e.perzentil == null ? '–' : '${e.perzentil!.toStringAsFixed(0)}. Perzentil',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: e.perzentil == null ? ArcadeFarben.tinteHell : ArcadeFarben.investorDunkel,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${e.scoreVsInvestor > 0 ? '+' : ''}${e.scoreVsInvestor.toStringAsFixed(2)} % vs. Investor',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gewonnen ? ArcadeFarben.spielerDunkel : ArcadeFarben.verkaufenSchatten,
                ),
              ),
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
