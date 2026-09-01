import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/responsive/master_detail_scaffold.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import 'simulacro_screen.dart';

/// Historial de simulacros.
///
/// Aquí solo aparecen los simulacros COMPLETADOS con al menos 50 preguntas:
/// es el criterio que valida el backend en `POST /api/simulacro/finish`, no
/// una decisión de esta pantalla. Sirve para repasar con calma la corrección
/// de un simulacro pasado, aunque en su momento no diera tiempo a mirarla.
class SimulacroHistorialScreen extends StatefulWidget {
  const SimulacroHistorialScreen({super.key});

  @override
  State<SimulacroHistorialScreen> createState() =>
      _SimulacroHistorialScreenState();
}

class _SimulacroHistorialScreenState extends State<SimulacroHistorialScreen> {
  static const _pageSize = 20;

  final List<SimSession> _sessions = [];
  List<SimCalendarDay> _calendar = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// Sesión abierta en el panel derecho, en maestro-detalle (tablet grande).
  SimSession? _selectedSession;

  /// La lista de la izquierda está plegada (detalle a pantalla completa).
  bool _masterCollapsed = false;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      // Un año natural hacia atrás, que es lo que pinta el mapa de calor.
      final results = await Future.wait([
        _api.getSimulacroHistory(limit: _pageSize + 1),
        _api.getSimulacroCalendar(
          from: DateTime(now.year - 1, now.month, now.day),
          to: now,
        ),
      ]);
      if (!mounted) return;
      // Se pide una de más para saber si hay página siguiente sin un COUNT
      // aparte; esa sobrante no se pinta.
      final page = results[0] as List<SimSession>;
      setState(() {
        _sessions
          ..clear()
          ..addAll(page.take(_pageSize));
        _hasMore = page.length > _pageSize;
        _calendar = results[1] as List<SimCalendarDay>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudo cargar el historial.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.getSimulacroHistory(
        limit: _pageSize + 1,
        offset: _sessions.length,
      );
      if (!mounted) return;
      setState(() {
        _sessions.addAll(page.take(_pageSize));
        _hasMore = page.length > _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(SimSession session) async {
    if (context.usesTwoPane) {
      setState(() => _selectedSession = session);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _SimReviewScreen(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = context.usesTwoPane;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: twoPane
            ? MasterDetailScaffold(
                masterTitle: 'Historial',
                masterCollapsed: _masterCollapsed,
                onToggleMaster: () =>
                    setState(() => _masterCollapsed = !_masterCollapsed),
                master: _list(),
                detail: _selectedSession == null
                    ? const MasterDetailEmpty(
                        icon: Icons.history_rounded,
                        title: 'Elige un simulacro',
                        subtitle:
                            'Selecciona uno de la lista para repasar su corrección.',
                      )
                    : _SimReviewScreen(
                        key: ValueKey(_selectedSession!.id),
                        session: _selectedSession!,
                        onClose: () => setState(() {
                          if (_masterCollapsed) {
                            _masterCollapsed = false;
                          } else {
                            _selectedSession = null;
                          }
                        }),
                      ),
              )
            : _list(),
      ),
    );
  }

  Widget _list() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics:
            const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          const StickerHero(
            badge: 'Simulacros',
            badgeIcon: Icons.history_rounded,
            title: 'Historial',
            subtitle: 'Repasa la corrección de los simulacros que terminaste.',
            accent: Color(0xFF6E8E6B),
          ),
          const SizedBox(height: 24),
          if (_loading) ...[
            const _HistorialSkeleton(),
          ] else if (_error != null) ...[
            _ErrorBox(message: _error!, onRetry: _load),
          ] else ...[
            if (_calendar.isNotEmpty) ...[
              const SectionLabel('Calendario'),
              _CalendarHeatmap(days: _calendar),
              const SizedBox(height: 24),
            ],
            SectionLabel('Simulacros guardados (${_sessions.length})'),
            if (_sessions.isEmpty)
              const _EmptyHistorial()
            else ...[
              for (final s in _sessions)
                _SessionCard(
                  session: s,
                  selected: s.id == _selectedSession?.id,
                  onTap: () => _open(s),
                ),
              if (_hasMore) ...[
                const SizedBox(height: 6),
                GhostButton(
                  label: _loadingMore ? 'Cargando…' : 'Ver más',
                  icon: Icons.expand_more_rounded,
                  expand: true,
                  onPressed: _loadingMore ? null : _loadMore,
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// Ficha de un simulacro guardado: cuándo fue, cómo salió y de qué iba.
class _SessionCard extends StatelessWidget {
  final SimSession session;
  final VoidCallback onTap;

  /// true cuando esta es la sesión abierta en el panel derecho (maestro-
  /// detalle). Fuera de ese modo siempre llega en false.
  final bool selected;

  const _SessionCard({
    required this.session,
    required this.onTap,
    this.selected = false,
  });

  static const _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  String get _when {
    final d = session.finishedAt;
    if (d == null) return 'Sin fecha';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year} · $hh:$mm';
  }

  String get _duration {
    final s = session.timeSpentSeconds;
    if (s <= 0) return '—';
    final m = s ~/ 60;
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${m % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final pct = (session.accuracy * 100).round();
    // El mismo degradado pastel que el mapa de calor de la web: rojo suave
    // abajo, verde suave arriba.
    final tone = Color.lerp(
      const Color(0xFFF3B7AE),
      const Color(0xFFB9DCB4),
      session.accuracy,
    )!;

    return StickerCard(
      margin: const EdgeInsets.only(bottom: 14),
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(16),
      // Resalta cuál está abierta en el panel derecho (maestro-detalle).
      background:
          selected ? AppColors.primary.withValues(alpha: 0.10) : Colors.white,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(3),
            ),
            child: Text(
              '$pct%',
              style: const TextStyle(
                color: kInk,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${session.correctCount} de ${session.totalQuestions} aciertos',
                  style: const TextStyle(
                    color: kInk,
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _when,
                  style: TextStyle(
                    color: kMuted.withOpacity(0.9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    DocChip(
                      label: _duration,
                      icon: Icons.schedule_rounded,
                    ),
                    if (session.blankCount > 0)
                      DocChip(label: '${session.blankCount} en blanco'),
                    if (session.subjects.isNotEmpty)
                      DocChip(
                        label: session.subjects.length == 1
                            ? session.subjects.first
                            : '${session.subjects.length} asignaturas',
                        tone: DocTone.accent,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_ios_rounded,
              color: kMuted.withOpacity(0.6), size: 15),
        ],
      ),
    );
  }
}

/// Mapa de calor: un cuadrito por día del último año, coloreado por acierto.
class _CalendarHeatmap extends StatelessWidget {
  final List<SimCalendarDay> days;

  const _CalendarHeatmap({required this.days});

  static const _empty = Color(0xFFEDE8E5);

  @override
  Widget build(BuildContext context) {
    final byDay = {
      for (final d in days)
        DateTime(d.day.year, d.day.month, d.day.day): d,
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Se arranca un lunes para que cada columna sea una semana entera.
    final start = today
        .subtract(const Duration(days: 364))
        .subtract(Duration(days: (today.weekday - 1) % 7));
    final weeks = (today.difference(start).inDays / 7).ceil() + 1;

    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Un cuadrito por día',
            style: TextStyle(
              color: kInk,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // arranca enseñando lo más reciente
            child: Row(
              children: [
                for (var w = 0; w < weeks; w++)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Builder(builder: (_) {
                            final date = start.add(Duration(days: w * 7 + d));
                            if (date.isAfter(today)) {
                              return const SizedBox(height: 13, width: 10);
                            }
                            final entry = byDay[date];
                            return Container(
                              height: 10,
                              width: 10,
                              margin: const EdgeInsets.only(bottom: 3),
                              decoration: BoxDecoration(
                                color: entry == null
                                    ? _empty
                                    : Color.lerp(
                                        const Color(0xFFF3B7AE),
                                        const Color(0xFFB9DCB4),
                                        (entry.accuracy / 100).clamp(0, 1),
                                      ),
                                borderRadius: BorderRadius.circular(2.5),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Menos acierto',
                  style: TextStyle(
                      color: kMuted.withOpacity(0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: kHairline, width: 1.5),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF3B7AE), Color(0xFFB9DCB4)],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('Más',
                  style: TextStyle(
                      color: kMuted.withOpacity(0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Repaso de un simulacro pasado: reutiliza la rejilla de la fase de
/// resultados, que es exactamente lo que hace la web.
class _SimReviewScreen extends StatefulWidget {
  final SimSession session;

  /// Cuando no es null, esta pantalla está embebida en el panel derecho de
  /// un maestro-detalle (tablet grande): tanto el botón de atrás del AppBar
  /// como "Volver al historial" deseleccionan en el maestro en vez de hacer
  /// pop (aquí no hay ninguna ruta propia que cerrar).
  final VoidCallback? onClose;

  const _SimReviewScreen({super.key, required this.session, this.onClose});

  @override
  State<_SimReviewScreen> createState() => _SimReviewScreenState();
}

class _SimReviewScreenState extends State<_SimReviewScreen> {
  SimHistoryDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await context
          .read<ApiService>()
          .getSimulacroHistoryDetail(widget.session.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudo cargar el repaso de este simulacro.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: widget.onClose == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onClose,
              ),
        title: const Text('Repaso'),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: _ErrorBox(message: _error!, onRetry: _load),
                  )
                : SimResultsView(
                    questions: _detail!.questions,
                    answers: _detail!.answers,
                    results: _detail!.results,
                    eyebrow: 'SIMULACRO GUARDADO',
                    restartLabel: 'Volver al historial',
                    restartIcon: Icons.arrow_back_rounded,
                    onRestart:
                        widget.onClose ?? () => Navigator.of(context).pop(),
                  ),
      ),
    );
  }
}

class _EmptyHistorial extends StatelessWidget {
  const _EmptyHistorial();

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF6E8E6B),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(4),
            ),
            child: const Icon(Icons.history_rounded,
                color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          const Text(
            'Todavía no hay simulacros guardados',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kInk,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Solo se guardan los simulacros que terminas y que tienen al '
            'menos 50 preguntas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMuted.withOpacity(0.9),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: kMuted, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kInk, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          GhostButton(
            label: 'Reintentar',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _HistorialSkeleton extends StatelessWidget {
  const _HistorialSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            height: 96,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(4),
            ),
          ),
      ],
    );
  }
}
