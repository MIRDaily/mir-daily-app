import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/analytics.dart';
import '../../../core/services/api_service.dart';
import 'panel_charts.dart';
import 'panel_section.dart';

const _windowOptions = <(AnalyticsWindow, String)>[
  (AnalyticsWindow.week, 'Semana'),
  (AnalyticsWindow.month, 'Mes'),
  (AnalyticsWindow.all, 'Global'),
];

const _modeLabels = <String, String>{
  'daily': 'Daily',
  'simulacro': 'Simulacros',
  'studio': 'Mazos',
};

// ===========================================================================
// TU ESFUERZO
// ===========================================================================
class EffortSubsection extends StatefulWidget {
  const EffortSubsection({super.key});

  @override
  State<EffortSubsection> createState() => _EffortSubsectionState();
}

class _EffortSubsectionState extends State<EffortSubsection> {
  AnalyticsWindow _window = AnalyticsWindow.all;
  EffortResponse? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ApiService>().getEffort(_window);
      if (mounted) setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _data?.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelSectionHeader(
          title: 'Tu esfuerzo',
          subtitle: 'Cuántas preguntas has hecho y cómo se reparten.',
          trailing: PanelSegmented<AnalyticsWindow>(
            options: _windowOptions,
            value: _window,
            onChanged: (w) {
              setState(() => _window = w);
              _load();
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const PanelLoadingCard(height: 180)
        else
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PREGUNTAS REALIZADAS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: PanelColors.muted)),
                const SizedBox(height: 4),
                Text('${totals?.questions ?? 0}',
                    style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: PanelColors.ink)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                        child: PanelStatChip(
                            value: totals?.correct ?? 0,
                            label: 'Aciertos',
                            color: PanelColors.correct)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: PanelStatChip(
                            value: totals?.wrong ?? 0,
                            label: 'Fallos',
                            color: PanelColors.wrong)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: PanelStatChip(
                            value: totals?.blank ?? 0,
                            label: 'En blanco',
                            color: PanelColors.blank)),
                  ],
                ),
                const SizedBox(height: 14),
                StackedBar(
                  correct: totals?.correct ?? 0,
                  wrong: totals?.wrong ?? 0,
                  blank: totals?.blank ?? 0,
                  height: 10,
                ),
                const SizedBox(height: 24),
                const Text('DISTRIBUCIÓN POR MODO',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: PanelColors.muted)),
                const SizedBox(height: 12),
                if ((_data?.byMode ?? const <EffortByMode>[]).isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('Aún no hay actividad en esta ventana.',
                          style: TextStyle(
                              fontSize: 13, color: PanelColors.muted)),
                    ),
                  )
                else
                  ...[
                    for (final row in _data!.byMode) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_modeLabels[row.mode] ?? row.mode,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: PanelColors.ink)),
                          Text('${row.questions} preg.',
                              style: const TextStyle(
                                  fontSize: 12.5, color: PanelColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      StackedBar(
                          correct: row.correct,
                          wrong: row.wrong,
                          blank: row.blank,
                          height: 10),
                      const SizedBox(height: 14),
                    ],
                  ],
                const PanelLegendRow(),
              ],
            ),
          ),
      ],
    );
  }
}

class PanelLegendRow extends StatelessWidget {
  const PanelLegendRow({super.key});
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 14,
        runSpacing: 6,
        children: const [
          _MiniLegend(color: PanelColors.correct, label: 'Aciertos'),
          _MiniLegend(color: PanelColors.wrong, label: 'Fallos'),
          _MiniLegend(color: PanelColors.blank, label: 'En blanco'),
        ],
      );
}

class _MiniLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _MiniLegend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 12, color: PanelColors.muted)),
        ],
      );
}

// ===========================================================================
// MAPA DE CALOR POR ASIGNATURAS (con drill-down por tema)
// ===========================================================================
class SubjectHeatmapSubsection extends StatefulWidget {
  const SubjectHeatmapSubsection({super.key});

  @override
  State<SubjectHeatmapSubsection> createState() =>
      _SubjectHeatmapSubsectionState();
}

class _SubjectHeatmapSubsectionState extends State<SubjectHeatmapSubsection> {
  AnalyticsWindow _window = AnalyticsWindow.all;
  AnalyticsMode _mode = AnalyticsMode.all;
  String _search = '';
  int? _openId;

  SubjectHeatmapResponse? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await context.read<ApiService>().getSubjectHeatmap(_window, _mode);
      if (mounted) setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SubjectHeatmapCell> get _filtered {
    final rows = _data?.subjects ?? const <SubjectHeatmapCell>[];
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _filtered;
    SubjectHeatmapCell? open;
    for (final s in subjects) {
      if (s.subjectId == _openId) {
        open = s;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelSectionHeader(
          title: 'Mapa de Calor',
          subtitle: 'Toca una asignatura para ver su desglose por temas.',
        ),
        const SizedBox(height: 12),
        // Buscador.
        TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar asignatura...',
            hintStyle: const TextStyle(color: PanelColors.muted, fontSize: 14),
            prefixIcon:
                const Icon(Icons.search, color: PanelColors.muted, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: PanelColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: PanelColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: PanelColors.accent)),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              PanelSegmented<AnalyticsWindow>(
                options: _windowOptions,
                value: _window,
                onChanged: (w) {
                  setState(() {
                    _window = w;
                    _openId = null;
                  });
                  _load();
                },
              ),
              const SizedBox(width: 8),
              PanelSegmented<AnalyticsMode>(
                options: const [
                  (AnalyticsMode.all, 'Todos'),
                  (AnalyticsMode.daily, 'Daily'),
                  (AnalyticsMode.simulacro, 'Simulacros'),
                  (AnalyticsMode.studio, 'Mazos'),
                ],
                value: _mode,
                onChanged: (m) {
                  setState(() {
                    _mode = m;
                    _openId = null;
                  });
                  _load();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const _HeatLegend(),
        const SizedBox(height: 14),
        if (_loading)
          const PanelLoadingCard(height: 200)
        else if (subjects.isEmpty)
          PanelCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: const [
                  Icon(Icons.bubble_chart_rounded,
                      size: 34, color: Color(0xFFCFC5BB)),
                  SizedBox(height: 8),
                  Text('Aún no hay datos en esta ventana.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: PanelColors.muted)),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.15,
                ),
                itemCount: subjects.length,
                itemBuilder: (context, i) {
                  final s = subjects[i];
                  return _SubjectCard(
                    subject: s,
                    active: _openId == s.subjectId,
                    onTap: () => setState(() =>
                        _openId = _openId == s.subjectId ? null : s.subjectId),
                  );
                },
              ),
              if (open != null) ...[
                const SizedBox(height: 14),
                _SubjectDetail(
                  key: ValueKey(open.subjectId),
                  subject: open,
                  window: _window,
                  mode: _mode,
                  onClose: () => setState(() => _openId = null),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Menos',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: PanelColors.muted)),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                colors: [
                  for (final s in [0, 20, 38, 52, 64, 70, 100])
                    heatColor(s.toDouble()),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text('Más',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: PanelColors.muted)),
      ],
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final SubjectHeatmapCell subject;
  final bool active;
  final VoidCallback onTap;

  const _SubjectCard(
      {required this.subject, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final acc = subject.accuracy;
    final bg = heatColor(acc);
    final bgDark = heatColorDark(acc);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bg, bgDark],
          ),
          border: active
              ? Border.all(color: Colors.white, width: 2.5)
              : Border.all(color: Colors.transparent, width: 2.5),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: bg.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              subject.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.15,
                letterSpacing: 0.3,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))
                ],
              ),
            ),
            Text(
              acc == null ? '--' : '${acc.round()}%',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Detalle de asignatura (drill-down) ----
class _SubjectDetail extends StatefulWidget {
  final SubjectHeatmapCell subject;
  final AnalyticsWindow window;
  final AnalyticsMode mode;
  final VoidCallback onClose;

  const _SubjectDetail({
    super.key,
    required this.subject,
    required this.window,
    required this.mode,
    required this.onClose,
  });

  @override
  State<_SubjectDetail> createState() => _SubjectDetailState();
}

class _SubjectDetailState extends State<_SubjectDetail> {
  TopicHeatmapResponse? _topics;
  SubjectTrendResponse? _trend;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      final results = await Future.wait([
        api.getTopicHeatmap(widget.subject.subjectId, widget.window, widget.mode),
        api.getSubjectTrend(widget.subject.subjectId, widget.window),
      ]);
      if (mounted) setState(() {
        _topics = results[0] as TopicHeatmapResponse;
        _trend = results[1] as SubjectTrendResponse;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final tone = heatColor(s.accuracy);
    final allTopics = _topics?.topics ?? const <TopicHeatmapCell>[];
    final topics = allTopics.where((t) => t.total > 0).toList()
      ..sort((a, b) => (a.accuracy ?? 0).compareTo(b.accuracy ?? 0));
    final weak = topics.take(3).toList();
    final strong = topics.reversed.take(3).toList();
    final byVolume = [...allTopics]
      ..sort((a, b) => b.total.compareTo(a.total));
    final trendValues =
        (_trend?.points ?? const <TrendPoint>[]).map((p) => p.accuracy).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PanelColors.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: tone,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AccuracyRing(accuracy: s.accuracy, size: 92, stroke: 9),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: PanelColors.ink)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _chip('${s.correct} aciertos',
                                  PanelColors.correct),
                              _chip('${s.wrong} fallos', PanelColors.wrong),
                              _chip('${s.blank} blanco', PanelColors.blank),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded,
                          size: 20, color: PanelColors.muted),
                    ),
                  ],
                ),
                const Divider(height: 28, color: PanelColors.border),
                if (_loading)
                  const SizedBox(
                    height: 160,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: PanelColors.accent)),
                  )
                else ...[
                  const Text('Evolución de la precisión',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: PanelColors.ink)),
                  const SizedBox(height: 8),
                  TrendLineChart(values: trendValues, color: tone),
                  const SizedBox(height: 20),
                  const Text('Desglose por tema',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: PanelColors.ink)),
                  const SizedBox(height: 10),
                  if (byVolume.isEmpty)
                    const Text('Sin datos de temas en esta ventana.',
                        style:
                            TextStyle(fontSize: 13, color: PanelColors.muted))
                  else
                    _TopicColumns(topics: byVolume.take(6).toList()),
                  const SizedBox(height: 16),
                  const PanelLegendRow(),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _TopicList(
                          title: 'Temas fuertes',
                          icon: Icons.emoji_events_rounded,
                          accent: PanelColors.correct,
                          topics: strong,
                          showFail: false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TopicList(
                          title: 'Temas débiles',
                          icon: Icons.warning_amber_rounded,
                          accent: PanelColors.wrong,
                          topics: weak,
                          showFail: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StackedBar(
                      correct: s.correct,
                      wrong: s.wrong,
                      blank: s.blank,
                      height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      );
}

class _TopicColumns extends StatelessWidget {
  final List<TopicHeatmapCell> topics;
  const _TopicColumns({required this.topics});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in topics)
          SizedBox(
            // Ancho de 3 columnas dentro del detalle (padding premium 40 +
            // padding tarjeta 32 + 2 huecos de 10).
            width: (MediaQuery.of(context).size.width - 40 - 32 - 20) / 3,
            child: _TopicColumn(topic: t),
          ),
      ],
    );
  }
}

class _TopicColumn extends StatelessWidget {
  final TopicHeatmapCell topic;
  const _TopicColumn({required this.topic});

  @override
  Widget build(BuildContext context) {
    final total = (topic.correct + topic.wrong + topic.blank)
        .clamp(1, 1 << 30)
        .toDouble();
    Widget bar(int n, Color c) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (n / total)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, f, _) => Container(
                height: 70 * f + 2,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PanelColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                bar(topic.correct, PanelColors.correct),
                const SizedBox(width: 3),
                bar(topic.wrong, PanelColors.wrong),
                const SizedBox(width: 3),
                bar(topic.blank, PanelColors.blank),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(topic.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: PanelColors.ink)),
          Text('${topic.total} preg.',
              style: const TextStyle(fontSize: 9, color: PanelColors.muted)),
        ],
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<TopicHeatmapCell> topics;
  final bool showFail;

  const _TopicList({
    required this.title,
    required this.icon,
    required this.accent,
    required this.topics,
    required this.showFail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PanelColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: PanelColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (topics.isEmpty)
            const Text('Sin datos suficientes.',
                style: TextStyle(fontSize: 11, color: PanelColors.muted))
          else
            for (final t in topics) ...[
              _row(t),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _row(TopicHeatmapCell t) {
    final acc = t.accuracy ?? 0;
    final shown = showFail ? (100 - acc) : acc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: PanelColors.ink)),
            ),
            const SizedBox(width: 6),
            Text('${shown.round()}%',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: accent)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (shown / 100).clamp(0.03, 1.0)),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) => Stack(
              children: [
                Container(height: 6, color: PanelColors.track),
                FractionallySizedBox(
                  widthFactor: f,
                  child: Container(height: 6, color: accent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// PUNTOS DÉBILES
// ===========================================================================
class WeakPointsSubsection extends StatefulWidget {
  const WeakPointsSubsection({super.key});

  @override
  State<WeakPointsSubsection> createState() => _WeakPointsSubsectionState();
}

class _WeakPointsSubsectionState extends State<WeakPointsSubsection> {
  AnalyticsWindow _window = AnalyticsWindow.all;
  WeakPointsResponse? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ApiService>().getWeakPoints();
      if (mounted) setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = _data?.forWindow(_window) ?? const <WeakTopic>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelSectionHeader(
          title: 'Puntos débiles',
          subtitle: 'Los temas donde más fallas (los blancos cuentan).',
          trailing: PanelSegmented<AnalyticsWindow>(
            options: _windowOptions,
            value: _window,
            onChanged: (w) => setState(() => _window = w),
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const PanelLoadingCard(height: 160)
        else if (topics.isEmpty)
          PanelCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: const [
                  Icon(Icons.verified_rounded,
                      size: 34, color: PanelColors.correct),
                  SizedBox(height: 8),
                  Text('Aún no hay suficientes datos. ¡Sigue practicando!',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: PanelColors.muted)),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < topics.length; i++) ...[
                _WeakRow(topic: topics[i], rank: i),
                const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }
}

class _WeakRow extends StatelessWidget {
  final WeakTopic topic;
  final int rank;
  const _WeakRow({required this.topic, required this.rank});

  @override
  Widget build(BuildContext context) {
    final fail = topic.failRate ?? 0;
    return PanelCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PanelColors.wrong.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${rank + 1}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: PanelColors.wrong)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(topic.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: PanelColors.ink)),
                          Text('${topic.subjectName} · ${topic.total} preg.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: PanelColors.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${fail.round()}%',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: PanelColors.wrong)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween:
                        Tween(begin: 0, end: (fail / 100).clamp(0.03, 1.0)),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, f, _) => Stack(
                      children: [
                        Container(height: 7, color: PanelColors.track),
                        FractionallySizedBox(
                          widthFactor: f,
                          child: Container(height: 7, color: PanelColors.wrong),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
