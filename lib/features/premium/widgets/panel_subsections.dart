import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/models/analytics.dart';
import '../../../core/responsive/adaptive_grid.dart';
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

  /// Sube en cada carga. La precarga en curso lo compara con el suyo para
  /// saber si el usuario ha cambiado de ventana o de modo y debe abandonar.
  int _generation = 0;

  /// La precarga se lanza una sola vez por carga de datos.
  bool _prefetchArmed = false;
  ScrollPosition? _scrollPosition;
  VoidCallback _onScrollTick = () {};

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScrollTick);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final data =
          await context.read<ApiService>().getSubjectHeatmap(_window, _mode);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      _prefetchArmed = false;
      _armPrefetch(data.subjects, generation);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  /// Trae por adelantado el desglose de las asignaturas más pesadas, pero
  /// **solo cuando el mapa de calor se acerca a la pantalla**.
  ///
  /// El mapa vive al final de una página larga. Precargar nada más entrar en
  /// Premium le costaba 8 peticiones al backend a todo el mundo, incluida la
  /// mayoría que no baja hasta aquí. Ahora se espera a que el usuario
  /// demuestre que va en esta dirección: quien no baje, no gasta nada.
  void _armPrefetch(List<SubjectHeatmapCell> subjects, int generation) {
    if (_prefetchArmed) return;

    void intentar() {
      if (!mounted || generation != _generation || _prefetchArmed) return;
      if (!_cercaDePantalla()) {
        return;
      }
      _prefetchArmed = true;
      _scrollPosition?.removeListener(_onScrollTick);
      _scrollPosition = null;
      _DetailStore.prefetch(
        context.read<ApiService>(),
        subjects,
        _window,
        _mode,
        isStale: () => !mounted || generation != _generation,
      );
    }

    _onScrollTick = intentar;
    // Por si ya está a la vista al cargar (tablet apaisada, o el usuario ya
    // había bajado mientras llegaban los datos).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      intentar();
      if (_prefetchArmed) return;
      final pos = Scrollable.maybeOf(context)?.position;
      _scrollPosition = pos?..addListener(_onScrollTick);
    });
  }

  /// `true` si al mapa de calor le falta menos de media pantalla para entrar.
  bool _cercaDePantalla() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final alto = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy;
    return top < alto * 1.5;
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
          _SubjectGrid(
            subjects: subjects,
            openId: _openId,
            onTap: (s) {
              // Confirmación inmediata en el dedo, antes incluso de que se
              // pinte nada.
              HapticFeedback.selectionClick();
              setState(
                  () => _openId = _openId == s.subjectId ? null : s.subjectId);
            },
            detailBuilder: (s) => _SubjectDetail(
              key: ValueKey(s.subjectId),
              subject: s,
              window: _window,
              mode: _mode,
              onClose: () => setState(() => _openId = null),
            ),
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

/// Rejilla de asignaturas en acordeón.
///
/// Dos cosas que la `GridView` de antes hacía mal en tablet:
///
///  * Tenía `crossAxisCount: 3` fijo con `childAspectRatio: 1.15`. En un móvil
///    salían tres fichas de 110 px; en una tablet, tres LADRILLOS de 380x330
///    para enseñar un nombre y un porcentaje. Ahora las columnas salen del
///    ancho real (una ficha ronda los 175) y la altura es FIJA, así que la
///    ficha mide lo mismo en los dos sitios y solo cambia cuántas caben.
///
///  * El desglose se pintaba DESPUÉS de la rejilla entera. Con seis o más
///    asignaturas quedaba a una pantalla de distancia de la que acababas de
///    tocar, y parecía que el toque no hacía nada. Ahora se abre justo debajo
///    de la FILA de la asignatura tocada, que es lo que hace la web.
class _SubjectGrid extends StatelessWidget {
  final List<SubjectHeatmapCell> subjects;
  final int? openId;
  final ValueChanged<SubjectHeatmapCell> onTap;
  final Widget Function(SubjectHeatmapCell) detailBuilder;

  const _SubjectGrid({
    required this.subjects,
    required this.openId,
    required this.onTap,
    required this.detailBuilder,
  });

  /// Alto de la ficha. Fijo a propósito: es lo que impide que se estire hasta
  /// convertirse en un cartel al crecer el ancho.
  static const double _tileHeight = 78;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = adaptiveColumnCount(c.maxWidth, target: 175, max: 6);
        final rows = <Widget>[];

        for (var i = 0; i < subjects.length; i += cols) {
          final slice =
              subjects.sublist(i, math.min(i + cols, subjects.length));

          if (rows.isNotEmpty) rows.add(const SizedBox(height: _gap));
          rows.add(SizedBox(
            height: _tileHeight,
            child: Row(
              children: [
                for (var j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: j < slice.length
                        // Los huecos de la última fila van vacíos, no
                        // estirando la última ficha a lo ancho.
                        ? _SubjectCard(
                            subject: slice[j],
                            active: slice[j].subjectId == openId,
                            onTap: () => onTap(slice[j]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ));

          // El desglose, pegado a la fila de la que salió.
          final open = openId == null
              ? null
              : slice.where((s) => s.subjectId == openId).firstOrNull;
          if (open != null) {
            rows.add(const SizedBox(height: _gap));
            rows.add(_DetailReveal(
              // La clave lleva el id: al saltar de una asignatura a otra sin
              // cerrar, se rehace la entrada y se ve que ha cambiado.
              key: ValueKey('reveal-${open.subjectId}'),
              child: detailBuilder(open),
            ));
          }
        }

        return Column(children: rows);
      },
    );
  }
}

/// Entrada del desglose: aparece deslizándose desde la fila que lo abrió y se
/// desplaza solo hasta quedar a la vista.
///
/// Antes el desglose se materializaba de golpe, sin transición. En una tablet,
/// con la tarjeta tocada arriba del todo, no había ninguna señal de que el
/// toque hubiera hecho algo — que era la queja.
class _DetailReveal extends StatefulWidget {
  final Widget child;

  const _DetailReveal({super.key, required this.child});

  @override
  State<_DetailReveal> createState() => _DetailRevealState();
}

class _DetailRevealState extends State<_DetailReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  late final CurvedAnimation _curved =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.04),
    end: Offset.zero,
  ).animate(_curved);

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    // Traerlo a la vista es la señal más clara de que se ha abierto. Se hace
    // tras el primer fotograma, cuando ya tiene sitio en el árbol.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = context;
      if (!ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _curved.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // El `RepaintBoundary` le da capa propia: durante los 1,1 s de tweens de
    // entrada de sus gráficas, la GPU no vuelve a rasterizar el resto del
    // panel (rejilla de asignaturas, esfuerzo, puntos débiles).
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _curved,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}

/// Ficha de asignatura: nombre arriba, preguntas y porcentaje abajo. Compacta
/// a propósito — es una celda de un mapa de calor, no una tarjeta de portada.
class _SubjectCard extends StatelessWidget {
  final SubjectHeatmapCell subject;
  final bool active;
  final VoidCallback onTap;

  const _SubjectCard(
      {required this.subject, required this.active, required this.onTap});

  /// Sombra del texto SIN desenfoque. Con `blurRadius` eran 36 sombras
  /// difuminadas (3 textos x 12 asignaturas) que la GPU tenía que rasterizar
  /// cada vez que la rejilla se reconstruía — y se reconstruye en cada toque.
  /// Un desplazamiento duro de 1 px da el mismo contraste y no cuesta nada.
  static const _shadow = [
    Shadow(color: Colors.black26, offset: Offset(0, 1))
  ];

  @override
  Widget build(BuildContext context) {
    final acc = subject.accuracy;
    final bg = heatColor(acc);
    final bgDark = heatColorDark(acc);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          // El halo de la ficha activa era un `BoxShadow` con 12 px de
          // desenfoque: aparecía justo en el fotograma del toque y era parte
          // del tirón. El trazo de tinta marca igual de bien cuál está
          // abierta y no cuesta rasterizado.
          boxShadow: active
              ? const [BoxShadow(color: PanelColors.ink, offset: Offset(0, 3))]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                subject.name.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                  letterSpacing: 0.3,
                  color: Colors.white,
                  shadows: _shadow,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '${subject.total} preg.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                      shadows: _shadow,
                    ),
                  ),
                ),
                Text(
                  acc == null ? '--' : '${acc.round()}%',
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: _shadow,
                  ),
                ),
                // La flecha gira al abrir: confirma el toque en la propia
                // ficha, sin depender de que se vea el desglose.
                AnimatedRotation(
                  turns: active ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.9),
                    shadows: _shadow,
                  ),
                ),
              ],
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

/// Lo que hace falta para pintar el desglose de una asignatura, con la hora a
/// la que se trajo.
class _DetailData {
  final TopicHeatmapResponse topics;
  final SubjectTrendResponse trend;
  final DateTime fetchedAt;

  _DetailData(this.topics, this.trend) : fetchedAt = DateTime.now();
}

String _detailKey(int subjectId, AnalyticsWindow w, AnalyticsMode m) =>
    '$subjectId|${w.name}|${m.name}';

/// Almacén de los desgloses por asignatura + ventana + modo.
///
/// Resuelve tres cosas que se midieron en la tablet:
///
///  * **Caché.** El desglose se pedía a la red cada vez que se abría una
///    asignatura, aunque fuera la misma de hace dos segundos: 757 ms de espera
///    con el usuario mirando un spinner.
///  * **Peticiones duplicadas.** Si tocas una asignatura que se está
///    precargando, te enganchas a esa misma petición en vez de lanzar otra.
///  * **Precarga.** Las asignaturas con más preguntas son las que se abren, y
///    son justo las que más tardan. Se piden solas, en segundo plano, en
///    cuanto está la rejilla.
class _DetailStore {
  _DetailStore._();

  static final Map<String, _DetailData> _cache = {};
  static final Map<String, Future<_DetailData>> _inFlight = {};

  /// Tope de seguridad: 3 ventanas x 4 modos x unas 30 asignaturas daría
  /// muchas entradas si alguien se pone a cambiar filtros. Son objetos
  /// pequeños, pero no hace falta guardarlos todos para siempre.
  static const int _maxEntries = 80;

  /// Cuánto vale un desglose antes de volver a pedirlo.
  ///
  /// Sin esto la caché era para toda la sesión: haces un Daily, vuelves a
  /// Premium —donde la rejilla SÍ se recarga, porque el `PageView` desmonta la
  /// pestaña al alejarte— y el desglose seguía enseñando los números de antes.
  /// Dos minutos cubren de sobra una sesión de mirar asignaturas seguidas y
  /// garantizan que al volver de responder preguntas los datos están al día.
  static const Duration _ttl = Duration(minutes: 2);

  static bool _fresh(_DetailData d) =>
      DateTime.now().difference(d.fetchedAt) < _ttl;

  static _DetailData? cached(int subjectId, AnalyticsWindow w, AnalyticsMode m) {
    final key = _detailKey(subjectId, w, m);
    final hit = _cache[key];
    if (hit == null) return null;
    if (_fresh(hit)) return hit;
    _cache.remove(key);
    return null;
  }

  /// Devuelve el desglose, reaprovechando lo que ya haya en curso.
  static Future<_DetailData> fetch(
    ApiService api,
    int subjectId,
    AnalyticsWindow w,
    AnalyticsMode m,
  ) {
    final hit = cached(subjectId, w, m);
    if (hit != null) return Future.value(hit);
    final key = _detailKey(subjectId, w, m);
    return _inFlight[key] ??= _run(api, key, subjectId, w, m);
  }

  static Future<_DetailData> _run(
    ApiService api,
    String key,
    int subjectId,
    AnalyticsWindow w,
    AnalyticsMode m,
  ) async {
    try {
      final results = await Future.wait([
        api.getTopicHeatmap(subjectId, w, m),
        api.getSubjectTrend(subjectId, w),
      ]);
      final data = _DetailData(
        results[0] as TopicHeatmapResponse,
        results[1] as SubjectTrendResponse,
      );
      _cache[key] = data;
      _evict();
      return data;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Tira lo caducado y, si aun así sobra, lo más antiguo. Antes vaciaba el
  /// mapa entero al llegar al tope, con lo que se podía cargar el desglose que
  /// se acababa de precargar.
  static void _evict() {
    _cache.removeWhere((_, d) => !_fresh(d));
    if (_cache.length <= _maxEntries) return;
    final byAge = _cache.entries.toList()
      ..sort((a, b) => a.value.fetchedAt.compareTo(b.value.fetchedAt));
    for (final e in byAge.take(_cache.length - _maxEntries)) {
      _cache.remove(e.key);
    }
  }

  /// Se trae por adelantado el desglose de las [count] asignaturas con más
  /// preguntas hechas.
  ///
  /// De una en una a propósito: la precarga es trabajo de fondo y no debe
  /// competir por el ancho de banda con la asignatura que el usuario acaba de
  /// tocar. [isStale] corta el bucle si mientras tanto cambia la ventana o el
  /// modo, para no seguir pidiendo datos de un filtro que ya no está puesto.
  static Future<void> prefetch(
    ApiService api,
    List<SubjectHeatmapCell> subjects,
    AnalyticsWindow w,
    AnalyticsMode m, {
    required bool Function() isStale,
    int count = 4,
  }) async {
    final targets = subjects.where((s) => s.total > 0).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    for (final s in targets.take(count)) {
      if (isStale()) return;
      // `cached` ya descarta lo caducado, así que al volver a Premium tras
      // responder preguntas la precarga sí refresca en vez de darse por
      // satisfecha con lo viejo.
      if (cached(s.subjectId, w, m) != null) continue;
      if (_inFlight.containsKey(_detailKey(s.subjectId, w, m))) continue;
      try {
        await fetch(api, s.subjectId, w, m);
      } catch (_) {
        // La precarga es un extra: si falla, la apertura normal lo reintenta.
      }
    }
  }
}

class _SubjectDetailState extends State<_SubjectDetail> {
  TopicHeatmapResponse? _topics;
  SubjectTrendResponse? _trend;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Si ya está descargado —porque se abrió antes o porque lo trajo la
    // precarga— se pinta entero en el primer fotograma: ni spinner ni salto
    // de altura al llegar los datos.
    final cached = _DetailStore.cached(
        widget.subject.subjectId, widget.window, widget.mode);
    if (cached != null) {
      _topics = cached.topics;
      _trend = cached.trend;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Por el almacén, no a pelo: si la precarga ya tiene esta asignatura en
      // vuelo, esto espera a ESA petición en vez de lanzar una segunda.
      final data = await _DetailStore.fetch(
        context.read<ApiService>(),
        widget.subject.subjectId,
        widget.window,
        widget.mode,
      );
      if (mounted) setState(() {
        _topics = data.topics;
        _trend = data.trend;
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
        // Sin sombra difuminada. Era la más cara de todas: un desenfoque de
        // 12 px sobre una caja de más de mil píxeles de ancho, que la GPU
        // estrenaba en el mismo fotograma en que se abría el desglose.
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
                  // Esqueleto en vez de un spinner suelto: la tarjeta ya
                  // tiene la forma que va a tener, así que al llegar los
                  // datos no da el salto de altura que hacía dudar de si
                  // había pasado algo.
                  const _DetailSkeleton()
                else ...[
                  // En tablet la evolución y el desglose van en paralelo. En
                  // columna, cada uno era una banda de 190 px de alto por más
                  // de mil de ancho, casi siempre vacía.
                  LayoutBuilder(
                    builder: (context, c) {
                      final evolucion = _DetailBlock(
                        title: 'Evolución de la precisión',
                        child: TrendLineChart(values: trendValues, color: tone),
                      );
                      final desglose = _DetailBlock(
                        title: 'Desglose por tema',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (byVolume.isEmpty)
                              const Text('Sin datos de temas en esta ventana.',
                                  style: TextStyle(
                                      fontSize: 13, color: PanelColors.muted))
                            else
                              _TopicColumns(
                                  topics: byVolume.take(6).toList()),
                            const SizedBox(height: 16),
                            const PanelLegendRow(),
                          ],
                        ),
                      );

                      if (c.maxWidth < 720) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            evolucion,
                            const SizedBox(height: 20),
                            desglose,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: evolucion),
                          const SizedBox(width: 20),
                          Expanded(flex: 6, child: desglose),
                        ],
                      );
                    },
                  ),
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
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      );
}

/// Silueta del desglose mientras llega de la red: dos bloques con los mismos
/// títulos y unas barras grises donde irán las gráficas.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  static const _bone = Color(0xFFF0EAE6);

  Widget _bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: _bone,
          borderRadius: BorderRadius.circular(6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columna = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(150, 14),
            const SizedBox(height: 12),
            _bar(double.infinity, 120),
          ],
        );
        if (c.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [columna, const SizedBox(height: 20), columna],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: columna),
            const SizedBox(width: 20),
            Expanded(flex: 6, child: columna),
          ],
        );
      },
    );
  }
}

/// Un bloque titulado del desglose de asignatura.
class _DetailBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailBlock({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: PanelColors.ink)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _TopicColumns extends StatelessWidget {
  final List<TopicHeatmapCell> topics;
  const _TopicColumns({required this.topics});

  @override
  Widget build(BuildContext context) {
    // El ancho sale del hueco REAL, no de restarle a mano a la pantalla los
    // paddings del móvil: esa cuenta (40 + 32 + 20) daba columnas de 370 en
    // una tablet, con lo que solo cabía una y el resto del ancho se quedaba
    // en blanco.
    return LayoutBuilder(
      builder: (context, c) {
        final cols = adaptiveColumnCount(c.maxWidth, target: 150, max: 6);
        final width = (c.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in topics)
              SizedBox(width: width, child: _TopicColumn(topic: t)),
          ],
        );
      },
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
              // Las dos listas van una al lado de la otra y su porcentaje
              // significa lo contrario en cada una: sin decirlo, un mismo
              // tema aparece con un 0 % a la izquierda y un 100 % a la
              // derecha y parece un error de la app.
              Text(showFail ? '% fallos' : '% aciertos',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: PanelColors.muted)),
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
          // A dos columnas en cuanto hay sitio (tablet en vertical, donde
          // esta sección ocupa el ancho entero). En una sola, la fila medía
          // 778 px: el nombre del tema quedaba a la izquierda y su
          // porcentaje a medio metro, al otro extremo.
          LayoutBuilder(
            builder: (context, c) {
              // 340 y no 380: en tablet vertical el hueco es de ~700 px, y con
              // 380 seguía saliendo una sola columna estirada.
              final cols = adaptiveColumnCount(c.maxWidth, target: 340, max: 2);
              final rows = <Widget>[];
              for (var i = 0; i < topics.length; i += cols) {
                if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
                rows.add(Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var j = 0; j < cols; j++) ...[
                      if (j > 0) const SizedBox(width: 10),
                      Expanded(
                        child: i + j < topics.length
                            ? _WeakRow(topic: topics[i + j], rank: i + j)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ));
              }
              return Column(children: rows);
            },
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
              color: PanelColors.wrong.withOpacity(0.1),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(topic.name,
                              // Dos líneas: en móvil, con el porcentaje a la
                              // derecha, un nombre como "Generalidades de las
                              // lesiones óseas traumáticas" se quedaba en
                              // "Generalidades de las lesiones ó…" y no había
                              // forma de saber de qué tema hablaba.
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.25,
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
                    // La cifra va etiquetada. Sin el "FALLOS", este 100% se
                    // lee igual que el 100% del mapa de calor de arriba, que
                    // es justo lo contrario: allí es acierto y aquí, fallo.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${fail.round()}%',
                            style: const TextStyle(
                                fontSize: 17,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                                color: PanelColors.wrong)),
                        const Text('FALLOS',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.6,
                                color: PanelColors.muted)),
                      ],
                    ),
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
