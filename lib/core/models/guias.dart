// Guías de estudio de la Biblioteca: el modelo (src/types/studyGuide.ts de la web), las cifras de cada
// tema (src/lib/studyGuides/stats.ts), el orden de los temas (GuideSortToggle.tsx) y lo que calcula la
// página de la guía (src/app/library/[subjectId]/guia/page.tsx). Sin Flutter: se prueba aparte.
//
// Los datos vienen de assets/guides/*.json, generados desde los .ts de la web con
// tools/export_study_guides.mjs. NO se editan a mano.

import 'progreso_semana.dart' show numeroEs;

enum GuideTier { imprescindible, alta, media, baja }

enum GuideQuestionKind { bloque, reserva, frontera }

enum GuideTrend { sube, estable, baja }

T _enumDe<T extends Enum>(List<T> valores, Object? v, T porDefecto) {
  for (final x in valores) {
    if (x.name == v) return x;
  }
  return porDefecto;
}

List<int> _ints(Object? v) => v is List ? v.map((e) => e is num ? e.toInt() : 0).toList() : <int>[];
List<String> _strings(Object? v) => v is List ? v.map((e) => '$e').toList() : <String>[];

class GuideHotspot {
  final String name;

  /// 1 = sale a veces, 2 = sale a menudo, 3 = cae casi todos los años.
  final int heat;
  const GuideHotspot(this.name, this.heat);
}

class GuideTopic {
  final String id;
  final String code;
  final String name;
  final String shortName;
  final GuideTier tier;

  /// Preguntas por año, alineadas con [StudyGuide.perYear] (el último valor es el último MIR, SIN reservas).
  final List<int> perYear;
  final int lastExamReserve;
  final int pages;
  final String focus;
  final List<GuideHotspot> hotspots;
  final List<String> keys;
  final String? trap;

  const GuideTopic({
    required this.id,
    required this.code,
    required this.name,
    required this.shortName,
    required this.tier,
    required this.perYear,
    this.lastExamReserve = 0,
    this.pages = 0,
    this.focus = '',
    this.hotspots = const [],
    this.keys = const [],
    this.trap,
  });

  factory GuideTopic.fromJson(Map<String, dynamic> j) => GuideTopic(
        id: '${j['id']}',
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        shortName: '${j['shortName'] ?? j['name'] ?? ''}',
        tier: _enumDe(GuideTier.values, j['tier'], GuideTier.baja),
        perYear: _ints(j['perYear']),
        lastExamReserve: j['lastExamReserve'] is num ? (j['lastExamReserve'] as num).toInt() : 0,
        pages: j['pages'] is num ? (j['pages'] as num).toInt() : 0,
        focus: '${j['focus'] ?? ''}',
        hotspots: j['hotspots'] is List
            ? (j['hotspots'] as List)
                .whereType<Map>()
                .map((h) => GuideHotspot('${h['name'] ?? ''}', h['heat'] is num ? (h['heat'] as num).toInt().clamp(1, 3) : 1))
                .toList()
            : const [],
        keys: _strings(j['keys']),
        trap: j['trap'] is String && (j['trap'] as String).trim().isNotEmpty ? j['trap'] as String : null,
      );

  GuideTopic _conPerYear(List<int> p) => GuideTopic(
        id: id,
        code: code,
        name: name,
        shortName: shortName,
        tier: tier,
        perYear: p,
        lastExamReserve: lastExamReserve,
        pages: pages,
        focus: focus,
        hotspots: hotspots,
        keys: keys,
        trap: trap,
      );
}

class GuideQuestion {
  final int number;
  final GuideQuestionKind kind;
  final String? topicId;
  final String tag;
  final String stem;
  final List<String> options;

  /// 1-based.
  final int correct;
  final String explanation;
  final String? imageUrl;

  const GuideQuestion({
    required this.number,
    required this.kind,
    this.topicId,
    required this.tag,
    required this.stem,
    required this.options,
    required this.correct,
    required this.explanation,
    this.imageUrl,
  });

  factory GuideQuestion.fromJson(Map<String, dynamic> j) => GuideQuestion(
        number: j['number'] is num ? (j['number'] as num).toInt() : 0,
        kind: _enumDe(GuideQuestionKind.values, j['kind'], GuideQuestionKind.bloque),
        topicId: j['topicId'] is String ? j['topicId'] as String : null,
        tag: '${j['tag'] ?? ''}',
        stem: '${j['stem'] ?? ''}',
        options: _strings(j['options']),
        correct: j['correct'] is num ? (j['correct'] as num).toInt() : 1,
        explanation: '${j['explanation'] ?? ''}',
        imageUrl: j['imageUrl'] is String && (j['imageUrl'] as String).isNotEmpty ? j['imageUrl'] as String : null,
      );
}

class GuideInsight {
  final String icon;
  final String title;
  final String body;
  const GuideInsight(this.icon, this.title, this.body);
}

class GuidePlanStep {
  final String title;
  final String subtitle;
  final List<String> topicIds;
  final int days;
  const GuidePlanStep(this.title, this.subtitle, this.topicIds, this.days);
}

class StudyGuide {
  /// La clave de texto de la guía («reumatologia»): la de los reportes (`guide_ref`).
  final String subjectId;
  final String title;
  final String subtitle;
  final String targetExam;
  final String lastExam;
  final String historyRange;
  final List<({int year, int count})> perYear;
  final int lastExamTotal;
  final int lastExamReserveTotal;
  final List<GuideTopic> topics;
  final List<GuideInsight> insights;
  final List<GuidePlanStep> plan;
  final List<GuideQuestion> questions;
  final String sourcesNote;

  const StudyGuide({
    required this.subjectId,
    required this.title,
    required this.subtitle,
    required this.targetExam,
    required this.lastExam,
    required this.historyRange,
    required this.perYear,
    required this.lastExamTotal,
    required this.lastExamReserveTotal,
    required this.topics,
    required this.insights,
    required this.plan,
    required this.questions,
    required this.sourcesNote,
  });

  factory StudyGuide.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> mapas(Object? v) =>
        v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
    return StudyGuide(
      subjectId: '${j['subjectId']}',
      title: '${j['title'] ?? ''}',
      subtitle: '${j['subtitle'] ?? ''}',
      targetExam: '${j['targetExam'] ?? ''}',
      lastExam: '${j['lastExam'] ?? ''}',
      historyRange: '${j['historyRange'] ?? ''}',
      perYear: [
        for (final p in mapas(j['perYear']))
          (year: p['year'] is num ? (p['year'] as num).toInt() : 0, count: p['count'] is num ? (p['count'] as num).toInt() : 0),
      ],
      lastExamTotal: j['lastExamTotal'] is num ? (j['lastExamTotal'] as num).toInt() : 0,
      lastExamReserveTotal: j['lastExamReserveTotal'] is num ? (j['lastExamReserveTotal'] as num).toInt() : 0,
      topics: mapas(j['topics']).map(GuideTopic.fromJson).toList(),
      insights: [for (final m in mapas(j['insights'])) GuideInsight('${m['icon'] ?? ''}', '${m['title'] ?? ''}', '${m['body'] ?? ''}')],
      plan: [
        for (final m in mapas(j['plan']))
          GuidePlanStep('${m['title'] ?? ''}', '${m['subtitle'] ?? ''}', _strings(m['topicIds']), m['days'] is num ? (m['days'] as num).toInt() : 0),
      ],
      questions: mapas(j['questions']).map(GuideQuestion.fromJson).toList(),
      sourcesNote: '${j['sourcesNote'] ?? ''}',
    );
  }
}

/// El índice de assets/guides/index.json: qué guías hay y de qué asignatura del catálogo cuelga cada una.
class IndiceGuias {
  final String origen;
  final List<({String clave, int subjectId, String titulo, String examen})> guias;
  const IndiceGuias({required this.origen, required this.guias});

  factory IndiceGuias.fromJson(Map<String, dynamic> j) => IndiceGuias(
        origen: '${j['origen'] ?? ''}',
        guias: [
          for (final g in (j['guias'] is List ? j['guias'] as List : const []))
            if (g is Map && g['clave'] is String && g['subjectId'] is num)
              (clave: g['clave'] as String, subjectId: (g['subjectId'] as num).toInt(), titulo: '${g['titulo'] ?? ''}', examen: '${g['examen'] ?? ''}'),
        ],
      );

  /// La guía de una asignatura del catálogo, si la tiene.
  ({String clave, int subjectId, String titulo, String examen})? deAsignatura(int subjectId) {
    for (final g in guias) {
      if (g.subjectId == subjectId) return g;
    }
    return null;
  }
}

// ---- stats.ts --------------------------------------------------------------------------------

/// Número de convocatorias (incluido el último MIR) que cuentan como «recientes».
const recentWindow = 5;

class TopicStats {
  final int historyCount;
  final int lastExamCount;
  final int totalCount;
  final int recentCount;
  final double recentAvg;
  final double earlierAvg;
  final int recentHits;
  final GuideTrend trend;

  /// Media ponderada (70 % reciente, 30 % anterior): previsión orientativa por año.
  final double forecast;

  const TopicStats({
    required this.historyCount,
    required this.lastExamCount,
    required this.totalCount,
    required this.recentCount,
    required this.recentAvg,
    required this.earlierAvg,
    required this.recentHits,
    required this.trend,
    required this.forecast,
  });
}

int _suma(Iterable<int> v) => v.fold(0, (a, b) => a + b);

TopicStats computeTopicStats(List<int> values) {
  final n = values.length;
  final recent = values.sublist(n > recentWindow ? n - recentWindow : 0);
  final earlier = n > recentWindow ? values.sublist(0, n - recentWindow) : <int>[];
  final recentAvg = recent.isEmpty ? 0.0 : _suma(recent) / recent.length;
  final earlierAvg = earlier.isNotEmpty ? _suma(earlier) / earlier.length : recentAvg;
  final diff = recentAvg - earlierAvg;
  // Umbral doble (absoluto y relativo) para no llamar tendencia al ruido de temas con 0-1 preguntas.
  var trend = GuideTrend.estable;
  if (diff >= 0.4 && recentAvg >= earlierAvg * 1.3) {
    trend = GuideTrend.sube;
  } else if (diff <= -0.4 && recentAvg <= earlierAvg * 0.7) {
    trend = GuideTrend.baja;
  }
  return TopicStats(
    historyCount: n == 0 ? 0 : _suma(values.sublist(0, n - 1)),
    lastExamCount: n == 0 ? 0 : values.last,
    totalCount: _suma(values),
    recentCount: _suma(recent),
    recentAvg: recentAvg,
    earlierAvg: earlierAvg,
    recentHits: recent.where((v) => v > 0).length,
    trend: trend,
    forecast: recentAvg * 0.7 + earlierAvg * 0.3,
  );
}

class GuideTopicWithStats {
  final GuideTopic topic;
  final TopicStats stats;
  const GuideTopicWithStats(this.topic, this.stats);

  String get id => topic.id;
  String get shortName => topic.shortName;
  List<int> get perYear => topic.perYear;
}

/// Las reservas del último MIR cuentan como preguntas normales: se suman al último año del tema y de ahí salen
/// totales, previsión, tendencia y tablas. `lastExamReserve` queda solo para decir cuántas fueron de reserva.
List<GuideTopicWithStats> withStats(List<GuideTopic> topics) => [
      for (final t in topics)
        () {
          final conReserva = t.lastExamReserve == 0 || t.perYear.isEmpty
              ? t
              : t._conPerYear([...t.perYear.sublist(0, t.perYear.length - 1), t.perYear.last + t.lastExamReserve]);
          return GuideTopicWithStats(conReserva, computeTopicStats(conReserva.perYear));
        }(),
    ];

/// Preguntas por año de la asignatura con las reservas del último MIR sumadas.
List<({int year, int count})> subjectPerYear(StudyGuide g) => [
      for (var i = 0; i < g.perYear.length; i++)
        i == g.perYear.length - 1 ? (year: g.perYear[i].year, count: g.perYear[i].count + g.lastExamReserveTotal) : g.perYear[i],
    ];

/// Un decimal como mucho, con coma (es-ES).
String formatAvg(num value) => numeroEs(value);

/// «0», «≈0,6» o «≈3». Por debajo de 1, un decimal: «<1» igualaba 0,6 preguntas al año con un tema que no sale.
String formatForecast(double forecast) {
  if (forecast < 0.05) return '0';
  if (forecast < 0.95) return '≈${formatAvg((forecast * 10).round() / 10)}';
  return '≈${forecast.round()}';
}

// ---- GuideSortToggle.tsx -----------------------------------------------------------------------

enum GuideSortKey { prevision, historico, tendencia }

const kNombreOrdenGuia = {
  GuideSortKey.prevision: 'Previsión',
  GuideSortKey.historico: 'Histórico',
  GuideSortKey.tendencia: 'Tendencia',
};

List<GuideTopicWithStats> sortGuideTopics(List<GuideTopicWithStats> topics, GuideSortKey key) {
  int byHistory(GuideTopicWithStats a, GuideTopicWithStats b) => b.stats.totalCount.compareTo(a.stats.totalCount);
  int byForecast(GuideTopicWithStats a, GuideTopicWithStats b) => b.stats.forecast.compareTo(a.stats.forecast);
  const rank = {GuideTrend.sube: 0, GuideTrend.estable: 1, GuideTrend.baja: 2};
  return ordenEstable(
    topics,
    (a, b) => switch (key) {
      GuideSortKey.historico => _primero([byHistory(a, b), byForecast(a, b)]),
      GuideSortKey.tendencia => _primero([rank[a.stats.trend]!.compareTo(rank[b.stats.trend]!), byForecast(a, b), byHistory(a, b)]),
      GuideSortKey.prevision => _primero([byForecast(a, b), byHistory(a, b)]),
    },
  );
}

/// Ordenación estable, como `Array.prototype.sort` de JS (la de Dart no lo garantiza): a igualdad, se
/// queda el orden de entrada, que es el de la guía. Sin esto, dos temas empatados podían salir en otro
/// orden que en la web.
List<T> ordenEstable<T>(List<T> lista, int Function(T a, T b) comparar) {
  final conIndice = [for (var i = 0; i < lista.length; i++) (i, lista[i])];
  conIndice.sort((x, y) {
    final c = comparar(x.$2, y.$2);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  return [for (final e in conIndice) e.$2];
}

int _primero(List<int> v) => v.firstWhere((x) => x != 0, orElse: () => 0);

// ---- La página de la guía -------------------------------------------------------------------------

/// Lo que la página calcula a partir de la guía, para la cabecera y los apartados.
class ResumenGuia {
  final StudyGuide guia;
  final List<({int year, int count})> perYear;
  final List<int> years;
  final int lastYear;
  final int lastExamCount;

  /// Media por año del periodo histórico (sin el último MIR).
  final double average;
  final int minCount;
  final int maxYearCount;
  final List<GuideTopicWithStats> topics;
  final List<GuideTopicWithStats> topicsByPriority;
  final List<GuideTopicWithStats> topicsByForecast;
  final int maxTopicYearCount;
  final String earlierLabel;
  final String recentLabel;
  final String periodLabel;
  final int planDays;
  final List<GuideTopicWithStats> topThree;
  final int topThreeShare;

  ResumenGuia._({
    required this.guia,
    required this.perYear,
    required this.years,
    required this.lastYear,
    required this.lastExamCount,
    required this.average,
    required this.minCount,
    required this.maxYearCount,
    required this.topics,
    required this.topicsByPriority,
    required this.topicsByForecast,
    required this.maxTopicYearCount,
    required this.earlierLabel,
    required this.recentLabel,
    required this.periodLabel,
    required this.planDays,
    required this.topThree,
    required this.topThreeShare,
  });

  factory ResumenGuia.de(StudyGuide g) {
    final perYear = subjectPerYear(g);
    final lastYear = g.perYear.isEmpty ? 0 : g.perYear.last.year;
    final history = perYear.where((p) => p.year != perYear.last.year).toList();
    final average = history.isEmpty ? 0.0 : _suma(history.map((p) => p.count)) / history.length;
    final years = [for (final p in g.perYear) p.year];
    final topics = withStats(g.topics);
    final byPriority = ordenEstable(topics, (a, b) {
      final c = b.stats.totalCount.compareTo(a.stats.totalCount);
      return c != 0 ? c : b.stats.forecast.compareTo(a.stats.forecast);
    });
    final byForecast = ordenEstable(topics, (a, b) {
      final c = b.stats.forecast.compareTo(a.stats.forecast);
      return c != 0 ? c : b.stats.totalCount.compareTo(a.stats.totalCount);
    });
    final top = byPriority.take(3).toList();
    final totalTemas = _suma(topics.map((t) => t.stats.totalCount));
    String rango(int a, int b) => '$a–$b';
    return ResumenGuia._(
      guia: g,
      perYear: perYear,
      years: years,
      lastYear: lastYear,
      lastExamCount: g.lastExamTotal + g.lastExamReserveTotal,
      average: average,
      minCount: history.isEmpty ? 0 : history.map((p) => p.count).reduce((a, b) => a < b ? a : b),
      maxYearCount: history.isEmpty ? 0 : history.map((p) => p.count).reduce((a, b) => a > b ? a : b),
      topics: topics,
      topicsByPriority: byPriority,
      topicsByForecast: byForecast,
      maxTopicYearCount: topics.expand((t) => t.perYear).fold(0, (a, b) => a > b ? a : b),
      earlierLabel: years.length > recentWindow ? rango(years.first, years[years.length - recentWindow - 1]) : '',
      recentLabel: years.length >= recentWindow ? rango(years[years.length - recentWindow], lastYear) : '',
      periodLabel: years.isEmpty ? '' : rango(years.first, lastYear),
      planDays: _suma(g.plan.map((p) => p.days)),
      topThree: top,
      topThreeShare: totalTemas == 0 ? 0 : (_suma(top.map((t) => t.stats.totalCount)) / totalTemas * 100).round(),
    );
  }

  /// «1 de N preguntas del MIR es de esta asignatura» (200: las que puntúan).
  int get unaDeCada => average <= 0 ? 0 : (200 / average).round();

  /// La frase del gráfico de años: «Peso estable, entre 11 y 21 preguntas al año.»
  String get fraseAnios =>
      '${maxYearCount - minCount <= average ? 'Peso estable, entre' : 'Entre'} $minCount y $maxYearCount preguntas al año.';

  /// El último MIR se quedó más de un 15 % por debajo de la media.
  bool get ultimoPorDebajo => lastExamCount < average * 0.85;

  /// «Qué sube y qué baja»: los temas con algo que decir, del que más sube al que más baja.
  List<GuideTopicWithStats> filasTendencia({double minAvg = 0.5}) {
    final rows = topics
        .where((t) => t.stats.trend != GuideTrend.estable || t.stats.recentAvg >= minAvg || t.stats.earlierAvg >= minAvg)
        .toList();
    return ordenEstable(rows, (a, b) => (b.stats.recentAvg - b.stats.earlierAvg).compareTo(a.stats.recentAvg - a.stats.earlierAvg));
  }

  /// Las preguntas del último MIR de un tema.
  List<GuideQuestion> preguntasDeTema(String topicId) => [for (final q in guia.questions) if (q.topicId == topicId) q];
}

/// «Suele caer y no cayó»: tema con 10+ preguntas, que no baja, y 0 en el último MIR.
bool esSorpresa(GuideTopicWithStats t) => t.stats.lastExamCount == 0 && t.stats.totalCount >= 10 && t.stats.trend != GuideTrend.baja;

/// La «ref» con la que se reporta una pregunta o la guía entera: `<clave>/q12` o `<clave>/general`.
String refGuia(String clave, [int? pregunta]) => pregunta == null ? '$clave/general' : '$clave/q$pregunta';
