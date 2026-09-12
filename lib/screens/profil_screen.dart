import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/erfolge_repository.dart';
import '../data/spielverlauf.dart';
import '../domain/erfolge.dart';
import '../render/perzentil_histogramm_painter.dart';
import '../theme/arcade_theme.dart';

/// Rundenübergreifendes Verhaltensprofil (V11).
///
/// Statistische Ehrlichkeit ist hier wichtiger als ein volles Bild: Aggregate
/// (mittleres Perzentil, Sieg-Quote, Histogramm) erscheinen erst ab
/// [_minRundenFuerAggregate] gespielten Runden, Verhaltenssätze erst ab
/// kumuliert [_minTradesFuerVerhaltenssaetze] Verkäufen bzw. Käufen – sonst
/// jeweils ein Hinweistext statt einer (statistisch nicht belastbaren) Aussage.
class ProfilScreen extends StatelessWidget {
  const ProfilScreen({super.key});

  static const _minRundenFuerAggregate = 5;
  static const _minTradesFuerVerhaltenssaetze = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Mein Profil'),
        backgroundColor: ArcadeFarben.creme,
      ),
      body: Consumer<SpielverlaufRepository>(
        builder: (context, repo, kind) {
          final eintraege = repo.eintraege;
          if (eintraege.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                  'Noch keine Runden gespielt –\nspiel die erste Runde!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: ArcadeFarben.tinteHell),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _abschnittGespielteRunden(eintraege.length),
              const SizedBox(height: 16),
              if (eintraege.length < _minRundenFuerAggregate)
                _hinweis(
                  'Noch ${_minRundenFuerAggregate - eintraege.length} Runde(n) bis zu einer '
                  'belastbaren Auswertung deiner Treffsicherheit.',
                )
              else
                _abschnittAggregate(eintraege),
              const SizedBox(height: 16),
              _abschnittVerhaltenssaetze(eintraege),
              const SizedBox(height: 16),
              _abschnittErfolge(context),
            ],
          );
        },
      ),
    );
  }

  /// Bewusste Scope-Entscheidung (V14): kein eigener Erfolge-Galerie-Screen –
  /// die Liste hängt hier als kompakter Abschnitt an, statt einen weiteren,
  /// redundanten Screen zu bauen.
  Widget _abschnittErfolge(BuildContext context) {
    final freigeschaltet = context.watch<ErfolgeRepository>().freigeschaltet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Erfolge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final def in Erfolge.alle)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(freigeschaltet.contains(def.id) ? '🏅' : '🔒',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(def.titel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: freigeschaltet.contains(def.id)
                                ? ArcadeFarben.sicherheitDunkel
                                : ArcadeFarben.tinteHell,
                          )),
                      Text(def.beschreibung,
                          style: const TextStyle(fontSize: 11, color: ArcadeFarben.tinteHell)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _abschnittGespielteRunden(int anzahl) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ArcadeFarben.kursFlaeche.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '$anzahl gespielte Runde${anzahl == 1 ? '' : 'n'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      );

  Widget _abschnittAggregate(List<SpielverlaufEintrag> eintraege) {
    final mitPerzentil = eintraege.where((e) => e.perzentil != null).toList();
    final siege = eintraege.where((e) => e.scoreVsInvestor > 0).length;
    final siegQuote = siege / eintraege.length;

    final buckets = List<int>.filled(10, 0);
    for (final e in mitPerzentil) {
      final bucket = (e.perzentil! / 10).floor().clamp(0, 9);
      buckets[bucket]++;
    }
    final mittleresPerzentil = mitPerzentil.isEmpty
        ? null
        : mitPerzentil.fold(0.0, (s, e) => s + e.perzentil!) / mitPerzentil.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _zeile('Sieg-Quote gegen den Investor', '${(siegQuote * 100).toStringAsFixed(0)} %'),
        if (mittleresPerzentil != null) ...[
          _zeile('Ø Perzentil (Timing-Qualität)', mittleresPerzentil.toStringAsFixed(0)),
          if (mitPerzentil.length >= _minRundenFuerAggregate) ...[
            const SizedBox(height: 10),
            const Text('Verteilung deiner Perzentile',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            SizedBox(
              height: 70,
              child: CustomPaint(
                painter: PerzentilHistogrammPainter(buckets),
                size: Size.infinite,
              ),
            ),
          ],
        ] else
          _hinweis('Noch keine Runde mit bestimmbarem Perzentil.'),
      ],
    );
  }

  Widget _abschnittVerhaltenssaetze(List<SpielverlaufEintrag> eintraege) {
    final kaeufeGesamt = eintraege.fold(0, (s, e) => s + e.anzahlKaeufe);
    final verkaeufeGesamt = eintraege.fold(0, (s, e) => s + e.anzahlVerkaeufe);

    double? gewichtetesMittel(
        double? Function(SpielverlaufEintrag) wert, int Function(SpielverlaufEintrag) gewicht) {
      var summeGewicht = 0.0;
      var summeWert = 0.0;
      for (final e in eintraege) {
        final w = wert(e);
        if (w == null) continue;
        summeWert += w * gewicht(e);
        summeGewicht += gewicht(e);
      }
      return summeGewicht == 0 ? null : summeWert / summeGewicht;
    }

    final children = <Widget>[
      const Text('Verhaltensmuster', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
    ];

    if (verkaeufeGesamt < _minTradesFuerVerhaltenssaetze) {
      children.add(_hinweis(
          'Noch ${_minTradesFuerVerhaltenssaetze - verkaeufeGesamt} Verkäufe bis zu einer '
          'belastbaren Aussage über dein Verkaufsverhalten.'));
    } else {
      final abstandTief = gewichtetesMittel((e) => e.abstandVerkaufZuTiefTage, (e) => e.anzahlVerkaeufe);
      final anteilNachCrash =
          gewichtetesMittel((e) => e.anteilVerkaeufeNachCrash, (e) => e.anzahlVerkaeufe);
      if (abstandTief != null) {
        children.add(_zeile('Ø Abstand Verkauf zum folgenden Tief', '${abstandTief.round()} Handelstage'));
      }
      if (anteilNachCrash != null) {
        children.add(_zeile(
            'Verkäufe kurz nach einem Crash-Tag', '${(anteilNachCrash * 100).toStringAsFixed(0)} %'));
      }
    }

    if (kaeufeGesamt < _minTradesFuerVerhaltenssaetze) {
      children.add(_hinweis(
          'Noch ${_minTradesFuerVerhaltenssaetze - kaeufeGesamt} Käufe bis zu einer '
          'belastbaren Aussage über dein Kaufverhalten.'));
    } else {
      final abstandHoch = gewichtetesMittel((e) => e.abstandKaufZuHochTage, (e) => e.anzahlKaeufe);
      if (abstandHoch != null) {
        children.add(_zeile('Ø Abstand Kauf zum folgenden Hoch', '${abstandHoch.round()} Handelstage'));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _zeile(String links, String rechts) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(links, style: const TextStyle(fontSize: 14))),
            const SizedBox(width: 8),
            Text(rechts,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ArcadeFarben.investorDunkel)),
          ],
        ),
      );

  Widget _hinweis(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: const TextStyle(fontSize: 12, color: ArcadeFarben.tinteHell)),
      );
}
