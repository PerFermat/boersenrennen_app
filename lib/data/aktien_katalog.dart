import '../domain/kursreihe.dart';

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

  /// Tag, ab dem die Reihe den namensgebenden Titel zeigt – `null`, wenn sie
  /// durchgehend aus einer Quelle stammt.
  ///
  /// **Davor** zeigt sie einen Vorgängerfonds derselben Anlageidee, auf diesen
  /// Tag umbasiert. Das ist eine synthetische Reihe: Den ETF gab es damals
  /// nicht. Ohne diese Kennzeichnung spielte jemand „Technologie-Sektor 1990"
  /// auf einem Produkt, das erst 1998 aufgelegt wurde, ohne es zu merken.
  final DateTime? spleissAb;

  /// Quellenkette von alt nach neu, leer bei ungespleißten Reihen.
  final List<String> quellen;

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
    this.spleissAb,
    this.quellen = const [],
  });

  /// Ob die Reihe vor [spleissAb] aus einer anderen Quelle stammt.
  bool get istGespleisst => spleissAb != null;

  /// Ob eine Runde, die am Epochtag [rundenStart] beginnt, in den gespleißten
  /// Teil der Reihe hineinreicht.
  ///
  /// Bewusst an die **Runde** gebunden, nicht an den Titel: Wer auf einer
  /// gespleißten Reihe einen Zeitraum komplett nach dem Spleißpunkt erwischt,
  /// hat den echten ETF gespielt und braucht keinen Hinweis. Ein Vermerk an
  /// jedem Titel wäre schnell Hintergrundrauschen, das niemand mehr liest.
  bool rundeZeigtVorgaenger(int rundenStart) =>
      spleissAb != null && rundenStart < Kursreihe.zuEpochTag(spleissAb!);

  /// Der Vorgängerfonds, aus dem der Teil vor [spleissAb] stammt.
  String? get vorgaenger => quellen.isEmpty ? null : quellen.first;

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
        spleissAb: j['spleissAb'] == null
            ? null
            : DateTime.parse(j['spleissAb'] as String),
        quellen: (j['quellen'] as List?)?.cast<String>() ?? const [],
      );

  /// Verfügbare Historie in Jahren.
  double get spanneJahre => letzterTag.difference(ersterTag).inDays / 365.25;
}
