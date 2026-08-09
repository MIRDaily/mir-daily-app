import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/analytics.dart';
import '../../../core/models/models.dart';
import '../../../core/services/api_service.dart';
import 'panel_charts.dart';
import 'panel_subsections.dart';

/// Réplica móvil del Panel de la web (/panel): progreso global, esfuerzo,
/// mapa de calor por asignaturas (con drill-down por tema) y puntos débiles.
///
/// Todos los datos salen del backend real de MIRDaily (mismos endpoints que la
/// web). Se pinta debajo del contenido "Premium" existente.
class PanelSection extends StatefulWidget {
  const PanelSection({super.key});

  @override
  State<PanelSection> createState() => _PanelSectionState();
}

class _PanelSectionState extends State<PanelSection> {
  ApiService get _api => context.read<ApiService>();

  TimeSeriesResponse? _timeSeries;
  ActivityHeatmap? _heatmap;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait([
        _api.getTimeSeries(),
        _api.getActivityHeatmap(),
      ]);
      if (!mounted) return;
      setState(() {
        _timeSeries = results[0] as TimeSeriesResponse;
        _heatmap = results[1] as ActivityHeatmap;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelDivider(),
        const SizedBox(height: 8),
        // ===== PROGRESO GLOBAL =====
        _GlobalProgress(
          timeSeries: _timeSeries,
          heatmap: _heatmap,
          loading: _loading,
          error: _error,
          onRetry: _load,
        ),
        const SizedBox(height: 32),
        // ===== TU ESFUERZO =====
        const EffortSubsection(),
        const SizedBox(height: 32),
        // ===== MAPA DE CALOR POR ASIGNATURAS =====
        const SubjectHeatmapSubsection(),
        const SizedBox(height: 32),
        // ===== PUNTOS DÉBILES =====
        const WeakPointsSubsection(),
      ],
    );
  }
}

// ===========================================================================
// PROGRESO GLOBAL
// ===========================================================================
class _GlobalProgress extends StatelessWidget {
  final TimeSeriesResponse? timeSeries;
  final ActivityHeatmap? heatmap;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;

  const _GlobalProgress({
    required this.timeSeries,
    required this.heatmap,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final ts = timeSeries;
    final hasPoints = ts?.hasPoints ?? false;
    final scoreValue = hasPoints && ts?.avgScore30 != null
        ? '${ts!.avgScore30!.round()}'
        : '--';
    final dailysValue = hasPoints ? '${ts!.totalPoints}' : '--';
    final timeValue = hasPoints && ts?.avgTime30 != null
        ? '${ts!.avgTime30!.round()}s'
        : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelSectionHeader(
          title: 'Tu Progreso Global',
          subtitle: 'Análisis consolidado de tu rendimiento.',
        ),
        const SizedBox(height: 16),
        if (loading)
          const PanelLoadingCard(height: 320)
        else if (error)
          PanelErrorCard(onRetry: onRetry)
        else
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                          title: 'Puntuación', value: scoreValue, subtitle: 'Últimos 30'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                          title: 'Dailys', value: dailysValue, subtitle: 'Realizados'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                          title: 'Tiempo', value: timeValue, subtitle: 'Medio'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _ProgressLegend(),
                const SizedBox(height: 8),
                ProgressLineChart(
                  points: (ts?.points ?? const <TimeSeriesPoint>[])
                      .map((p) => ProgressPoint(
                            date: p.date,
                            score: p.score,
                            avgTime: p.avgTime,
                            correct: p.correct,
                          ))
                      .toList(),
                  avgScore: ts?.avgScore30,
                ),
                if (heatmap != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: const [
                      Icon(Icons.calendar_month_rounded,
                          size: 18, color: PanelColors.accent),
                      SizedBox(width: 8),
                      Text('Mapa de Actividad',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: PanelColors.ink)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ActivityHeatmapGrid(heatmap: heatmap!),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ProgressLegend extends StatelessWidget {
  const _ProgressLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: const [
        _LegendDot(color: PanelColors.correct, label: 'Score'),
        _LegendDot(color: PanelColors.accent, label: 'Tiempo medio'),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _MetricCard(
      {required this.title, required this.value, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F4),
        border: Border.all(color: PanelColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: PanelColors.muted)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: PanelColors.ink)),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: PanelColors.muted)),
        ],
      ),
    );
  }
}

// ===========================================================================
// MAPA DE ACTIVIDAD (30 días) + rachas
// ===========================================================================
class _ActivityHeatmapGrid extends StatelessWidget {
  final ActivityHeatmap heatmap;
  const _ActivityHeatmapGrid({required this.heatmap});

  static const _labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  Color _cellColor(int level) {
    if (level == 2) return PanelColors.correct;
    if (level == 1) return PanelColors.accent;
    return const Color(0xFFEDE8E5);
  }

  @override
  Widget build(BuildContext context) {
    final days = heatmap.days;
    final cells = List<HeatDay?>.generate(
        30, (i) => i < days.length ? days[i] : null);

    return Column(
      children: [
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.4,
          children: [
            for (final l in _labels)
              Center(
                child: Text(l,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: PanelColors.muted)),
              ),
            for (final day in cells)
              Container(
                decoration: BoxDecoration(
                  color: _cellColor(day?.level ?? 0),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
                child: _StreakBadge(
                    icon: Icons.local_fire_department_rounded,
                    color: PanelColors.wrong,
                    value: heatmap.currentStreak,
                    label: 'Racha')),
            const SizedBox(width: 8),
            Expanded(
                child: _StreakBadge(
                    icon: Icons.military_tech_rounded,
                    color: PanelColors.accent,
                    value: heatmap.longestStreak,
                    label: 'Récord')),
            const SizedBox(width: 8),
            Expanded(
                child: _StreakBadge(
                    icon: Icons.calendar_month_rounded,
                    color: PanelColors.muted,
                    value: heatmap.totalActiveDays,
                    label: 'Activos')),
            const SizedBox(width: 8),
            Expanded(
                child: _StreakBadge(
                    icon: Icons.check_circle_rounded,
                    color: PanelColors.correct,
                    value: heatmap.totalDailyDays,
                    label: 'Dailys')),
          ],
        ),
      ],
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;

  const _StreakBadge(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F4),
        border: Border.all(color: PanelColors.accent.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text('$value',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: PanelColors.ink)),
          Text(label,
              style: const TextStyle(fontSize: 9, color: PanelColors.muted)),
        ],
      ),
    );
  }
}

// ===========================================================================
// WIDGETS COMPARTIDOS DEL PANEL
// ===========================================================================
class PanelDivider extends StatelessWidget {
  const PanelDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: PanelColors.border,
      );
}

class PanelSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const PanelSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: PanelColors.ink,
                      letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 13, color: PanelColors.muted)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class PanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PanelCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PanelColors.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class PanelLoadingCard extends StatelessWidget {
  final double height;
  const PanelLoadingCard({super.key, this.height = 200});
  @override
  Widget build(BuildContext context) => PanelCard(
        child: SizedBox(
          height: height,
          child: const Center(
            child: CircularProgressIndicator(color: PanelColors.accent),
          ),
        ),
      );
}

class PanelErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const PanelErrorCard({super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => PanelCard(
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: PanelColors.wrong, size: 32),
            const SizedBox(height: 10),
            const Text('No se pudieron cargar tus estadísticas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: PanelColors.muted)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                  backgroundColor: PanelColors.accent,
                  foregroundColor: Colors.white),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, color: PanelColors.muted)),
        ],
      );
}

/// Control segmentado (pestañas tipo "pill").
class PanelSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  const PanelSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PanelColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (val, label) in options)
            GestureDetector(
              onTap: () => onChanged(val),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: val == value ? PanelColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: val == value ? Colors.white : PanelColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PanelStatChip extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const PanelStatChip(
      {super.key,
      required this.value,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900, color: color)),
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: PanelColors.muted)),
        ],
      ),
    );
  }
}
