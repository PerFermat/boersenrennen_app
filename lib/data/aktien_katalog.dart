/// Ein Eintrag aus assets/kurse/index.json.
class AktienEintrag {
  final String ticker;
  final String name;
  final String kategorie;
  final String gruppe;
  final String datei;
  final int anzahl;
  final DateTime ersterTag;
  final DateTime letzterTag;

  /// "bundled" = im App-Paket. Für späteres Nachladen ist "remote" vorgesehen.
  final String quelle;

  const AktienEintrag({
    required this.ticker,
    required this.name,
    required this.kategorie,
    required this.gruppe,
    required this.datei,
    required this.anzahl,
    required this.ersterTag,
    required this.letzterTag,
    required this.quelle,
  });

  factory AktienEintrag.vonJson(Map<String, dynamic> j) => AktienEintrag(
        ticker: j['ticker'] as String,
        name: j['name'] as String,
        kategorie: j['kategorie'] as String,
        gruppe: (j['gruppe'] as String?) ?? j['kategorie'] as String,
        datei: j['datei'] as String,
        anzahl: j['anzahl'] as int,
        ersterTag: DateTime.parse(j['ersterTag'] as String),
        letzterTag: DateTime.parse(j['letzterTag'] as String),
        quelle: (j['quelle'] as String?) ?? 'bundled',
      );

  /// Verfügbare Historie in Jahren.
  double get spanneJahre => letzterTag.difference(ersterTag).inDays / 365.25;
}
