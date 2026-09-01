import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/daily_provider.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/services/api_service.dart';
import '../../core/services/haptics_service.dart';
import '../../core/theme/app_theme.dart';
import '../decks/widgets/save_to_deck.dart';
import '../../shared/widgets/confetti_overlay.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/zoomable_image.dart';

const Color _ink = Color(0xFF374151);

/// Progreso escalonado entre [a] y [b] a partir de un valor global [t] (0..1).
double _sub(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

/// easeOutCubic aplicado a un valor 0..1.
double _eio(double x) => Curves.easeOutCubic.transform(x.clamp(0.0, 1.0));

/// Aparición: fade + desplazamiento vertical según progreso [p].
Widget _fadeUp(double p, Widget child, {double dy = 22}) {
  final c = p.clamp(0.0, 1.0);
  return Opacity(
    opacity: c,
    child: Transform.translate(offset: Offset(0, (1 - c) * dy), child: child),
  );
}

// ============================================================
// RESULTADOS DEL DAILY — CARRUSEL ESTILO HISTORIAS
// ============================================================

/// Resultados del daily presentados como un carrusel a pantalla completa,
/// estilo historias de Instagram: barra de progreso segmentada, auto-avance
/// con pausa al mantener pulsado, navegación por swipe/tap y animaciones de
/// entrada por slide. Consume los mismos datos que la versión anterior
/// (submitResult + /api/results/today + ranking + stats + heatmap).
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _segCtrl; // relleno del segmento activo

  List<_StorySlide> _slides = const [];
  int _index = 0;
  bool _ready = false;
  bool _paused = false;
  bool _confettiPlayed = false;
  bool _confetti = false;
  int _heroCorrect = 0;

  @override
  void initState() {
    super.initState();
    _segCtrl = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            _index < _slides.length &&
            _slides[_index].duration != null) {
          _next();
        }
      });
    _prepare();
  }

  Future<void> _prepare() async {
    final daily = context.read<DailyProvider>();
    // Carga secuencial (results/today, ranking, distribución, stats). El
    // provider ignora los fallos, así que siempre completa aunque falte red.
    await daily.loadResults();
    if (!mounted) return;
    _slides = _composeSlides(daily, context.read<AuthProvider>());
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _activate(0));
  }

  @override
  void dispose() {
    _segCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ---------- Navegación ----------

  void _activate(int i) {
    if (!mounted || _slides.isEmpty) return;
    HapticsService.light();
    _startSegment();
    if (_slides[i].id == 'hero' && !_confettiPlayed && _heroCorrect >= 3) {
      _confettiPlayed = true;
      setState(() => _confetti = true);
      HapticsService.strong();
    }
  }

  void _startSegment() {
    _segCtrl.stop();
    if (_index >= _slides.length) return;
    final slide = _slides[_index];
    if (slide.duration != null) {
      _segCtrl.duration = slide.duration;
      if (_paused) {
        _segCtrl.value = 0;
      } else {
        _segCtrl.forward(from: 0);
      }
    } else {
      _segCtrl.value = 1.0; // slide manual: segmento lleno
    }
  }

  void _onPage(int i) {
    setState(() => _index = i);
    _activate(i);
  }

  void _goTo(int i) {
    if (i < 0 || i >= _slides.length || i == _index) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_index < _slides.length - 1) {
      _goTo(_index + 1);
    }
  }

  void _prev() => _goTo(_index - 1);

  void _pause() {
    if (_slides.isEmpty || _slides[_index].duration == null) return;
    _paused = true;
    _segCtrl.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    if (_index < _slides.length && _slides[_index].duration != null) {
      _segCtrl.forward();
    }
  }

  void _exitToHub() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ---------- Percentil desde z-score ----------

  double? _percentile(double? z) {
    if (z == null) return null;
    final x = z / math.sqrt2;
    final t = 1 / (1 + 0.3275911 * x.abs());
    final y = 1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                    0.284496736) *
                t +
            0.254829592) *
            t *
            math.exp(-x * x);
    final erf = x >= 0 ? y : -y;
    return ((0.5 * (1 + erf)) * 100).clamp(0, 100).toDouble();
  }

  // ---------- Composición de slides ----------

  List<_StorySlide> _composeSlides(DailyProvider daily, AuthProvider auth) {
    final results = daily.results;
    final submit = daily.submitResult;

    final score = results?.score ?? submit?.score ?? 0;
    final correct = results?.correctCount ?? submit?.correctCount ?? 0;
    final total = results?.totalQuestions ?? submit?.totalQuestions ?? 5;
    final breakdown = results?.breakdown ?? submit?.breakdown;
    final accuracyPct = total > 0 ? (correct / total * 100).round() : 0;
    final percentile = _percentile(results?.zScore);
    _heroCorrect = correct;

    final review = results?.reviewQuestions ?? const <ReviewQuestion>[];

    final slides = <_StorySlide>[
      _StorySlide(
        id: 'hero',
        accent: accuracyPct == 100 ? AppColors.gold : AppColors.primary,
        duration: const Duration(milliseconds: 6200),
        content: (ctx, intro) => _heroSlide(
            intro, accuracyPct, correct, total, score),
      ),
      _StorySlide(
        id: 'breakdown',
        accent: AppColors.success,
        duration: const Duration(milliseconds: 6800),
        content: (ctx, intro) => _breakdownSlide(
            intro, breakdown, correct, total, score, review),
      ),
    ];

    if (results != null) {
      slides.add(_StorySlide(
        id: 'comparative',
        accent: AppColors.primary,
        duration: const Duration(milliseconds: 7400),
        content: (ctx, intro) =>
            _comparativeSlide(intro, results, score, percentile),
      ));
    }

    if (daily.statsSummary != null) {
      slides.add(_StorySlide(
        id: 'progress',
        accent: AppColors.emerald,
        duration: const Duration(milliseconds: 5600),
        content: (ctx, intro) => _progressSlide(intro, daily.statsSummary!),
      ));
    }

    if (daily.scoreDistribution?.hasData ?? false) {
      slides.add(_StorySlide(
        id: 'distribution',
        accent: AppColors.slate,
        duration: const Duration(milliseconds: 6200),
        content: (ctx, intro) =>
            _distributionSlide(intro, daily.scoreDistribution!),
      ));
    }

    if (daily.ranking.isNotEmpty) {
      slides.add(_StorySlide(
        id: 'ranking',
        accent: AppColors.primaryDark,
        duration: null,
        content: (ctx, intro) => _RankingSlide(
          intro: intro,
          ranking: daily.ranking,
          userId: auth.profile?.id,
          userName: auth.profile?.shortName ?? 'Tú',
          userAvatarId: auth.profile?.avatarId ?? 1,
          userScore: score,
        ),
      ));
    }

    for (var i = 0; i < review.length; i++) {
      final q = review[i];
      slides.add(_StorySlide(
        id: 'review-$i',
        accent: q.isCorrect ? AppColors.success : AppColors.error,
        duration: null,
        content: (ctx, intro) => _ReviewSlide(
          intro: intro,
          question: q,
          index: i,
          total: review.length,
        ),
      ));
    }

    slides.add(_StorySlide(
      id: 'activity',
      accent: AppColors.primary,
      duration: null,
      content: (ctx, intro) => _ActivitySlide(
        intro: intro,
        api: context.read<ApiService>(),
        onExit: _exitToHub,
      ),
    ));

    return slides;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // Se reconstruye si llegan datos tarde, pero los slides ya son estables.
    context.watch<DailyProvider>();

    final accent = _slides.isNotEmpty && _index < _slides.length
        ? _slides[_index].accent
        : AppColors.primary;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            Positioned.fill(child: _LivingBackground(accent: accent)),
            if (!_ready)
              const Positioned.fill(child: _PreparingView())
            else ...[
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPage,
                  itemCount: _slides.length,
                  physics: const _StoryScrollPhysics(),
                  itemBuilder: (context, i) {
                    return _StoryPage(
                      active: i == _index,
                      onTapForward: _next,
                      onTapBackward: _prev,
                      onHoldStart: _pause,
                      onHoldEnd: _resume,
                      interactive: _slides[i].duration == null,
                      controller: _pageController,
                      pageIndex: i,
                      builder: _slides[i].content,
                    );
                  },
                ),
              ),
              _topBar(),
              _bottomControls(),
            ],
            Positioned.fill(
              child: IgnorePointer(child: ConfettiOverlay(play: _confetti)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Barra superior (progreso + cerrar) ----------

  Widget _topBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _segCtrl,
              builder: (context, _) {
                return Row(
                  children: List.generate(_slides.length, (i) {
                    final double fill = i < _index
                        ? 1.0
                        : i == _index
                            ? (_slides[i].duration == null
                                ? 1.0
                                : _segCtrl.value)
                            : 0.0;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _goTo(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.5),
                          child: _SegmentBar(fill: fill),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 6),
                const MirDailyLogo(fontSize: 18),
                const Spacer(),
                Pressable(
                  onTap: _exitToHub,
                  pressedScale: 0.9,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFEDE6E1)),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: _ink, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Controles inferiores (prev / siguiente) ----------

  Widget _bottomControls() {
    if (_slides.isEmpty) return const SizedBox.shrink();
    final slide = _slides[_index];
    if (slide.id == 'activity') return const SizedBox.shrink();
    final isLast = _index >= _slides.length - 1;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _index > 0 ? 1 : 0,
                child: Pressable(
                  onTap: _index > 0 ? _prev : null,
                  pressedScale: 0.9,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFEDE6E1)),
                      boxShadow: [
                        BoxShadow(
                          color: _ink.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: _ink, size: 26),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: !isLast
                      ? const FittedBox(
                          fit: BoxFit.scaleDown, child: _SwipeHint())
                      : const SizedBox.shrink(),
                ),
              ),
              Pressable(
                onTap: _next,
                pressedScale: 0.94,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.42),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Siguiente',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.white, size: 22),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CONTENIDO DE CADA SLIDE
  // ============================================================

  /// Cuerpo centrado y desplazable: se centra cuando el contenido cabe y
  /// permite scroll vertical cuando es más alto que la pantalla.
  Widget _centered(List<Widget> children,
      {CrossAxisAlignment cross = CrossAxisAlignment.center}) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 92, 24, 96),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: (cons.maxHeight - 188).clamp(0, double.infinity)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: cross,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- SLIDE 1: HERO (anillo + puntuación) ----------

  Widget _heroSlide(Animation<double> intro, int accuracyPct, int correct,
      int total, int score) {
    final perfect = accuracyPct == 100;
    final String title = perfect
        ? '¡Perfecto!'
        : correct >= 3
            ? '¡Excelente trabajo!'
            : correct >= 1
                ? '¡Buen intento!'
                : '¡Sigue así!';

    return AnimatedBuilder(
      animation: intro,
      builder: (context, _) {
        final t = intro.value;
        final ringP = _eio(_sub(t, 0.15, 1.0));
        final ringVal = (accuracyPct / 100) * ringP;
        final scoreShown = (score * _eio(_sub(t, 0.4, 1.0))).round();

        return _centered([
          _fadeUp(_eio(_sub(t, 0, 0.5)), const _FloatWrap(child: _HeroMedal())),
          const SizedBox(height: 22),
          _fadeUp(
            _eio(_sub(t, 0.12, 0.62)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _fadeUp(
            _eio(_sub(t, 0.2, 0.7)),
            const Text(
              'Resultados de tu daily de hoy',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 14.5,
              ),
            ),
          ),
          const SizedBox(height: 30),
          _fadeUp(
            _eio(_sub(t, 0.1, 0.75)),
            LayoutBuilder(builder: (ctx, cons) {
              final size = math.min(cons.maxWidth * 0.66, 236.0);
              return SizedBox(
                width: size,
                height: size,
                child: CustomPaint(
                  painter: _AccuracyRingPainter(
                      progress: ringVal, perfect: perfect),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(ringVal * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 50,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'ACIERTOS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$correct de $total',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          _fadeUp(
            _eio(_sub(t, 0.45, 1.0)),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '$scoreShown',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text(
                      'pts',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]);
      },
    );
  }

  // ---------- SLIDE 2: DESGLOSE DE PUNTUACIÓN ----------

  Widget _breakdownSlide(Animation<double> intro, ScoreBreakdown? breakdown,
      int correct, int total, int score, List<ReviewQuestion> review) {
    return AnimatedBuilder(
      animation: intro,
      builder: (context, _) {
        final t = intro.value;
        final totalShown = (score * _eio(_sub(t, 0.45, 1.0))).round();

        return _centered([
          _fadeUp(
            _eio(_sub(t, 0, 0.5)),
            _slideHeader(
              icon: Icons.calculate_rounded,
              title: 'Desglose de puntuación',
              subtitle: 'Cómo se compone tu total',
            ),
          ),
          const SizedBox(height: 22),
          _fadeUp(
            _eio(_sub(t, 0.15, 0.8)),
            CustomPaint(
              painter: _DashedBorderPainter(
                  color: const Color(0xFFE5DCD6), radius: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    _fadeUp(
                      _eio(_sub(t, 0.22, 0.5)),
                      _breakdownRow(
                          'PREGUNTAS',
                          '+${breakdown?.knowledgeScore ?? correct * 200} pts',
                          AppColors.success),
                    ),
                    const SizedBox(height: 12),
                    _fadeUp(
                      _eio(_sub(t, 0.3, 0.58)),
                      _breakdownRow(
                          'BONUS TIEMPO',
                          breakdown == null ? '—' : '+${breakdown.timeBonus} pts',
                          AppColors.success),
                    ),
                    const SizedBox(height: 12),
                    _fadeUp(
                      _eio(_sub(t, 0.38, 0.66)),
                      _breakdownRow(
                          'JUEZ MIRDAILY', '-0 pts', AppColors.error),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: CustomPaint(
                        painter: _DashedLineHPainter(
                            color: const Color(0xFFE5DCD6)),
                        child:
                            const SizedBox(width: double.infinity, height: 1),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$totalShown pts',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          // Puntos por pregunta (acierto / fallo)
          _fadeUp(
            _eio(_sub(t, 0.5, 0.9)),
            const Text(
              'TUS RESPUESTAS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(total, (i) {
              final isCorrect =
                  (i < review.length) ? review[i].isCorrect : i < correct;
              final color =
                  isCorrect ? AppColors.success : const Color(0xFFC4655A);
              final p = _eio(_sub(t, 0.55 + i * 0.07, 0.8 + i * 0.07));
              return Opacity(
                opacity: p,
                child: Transform.scale(
                  scale: 0.5 + 0.5 * p,
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      isCorrect ? Icons.check_rounded : Icons.close_rounded,
                      size: 20,
                      color: color,
                    ),
                  ),
                ),
              );
            }),
          ),
        ]);
      },
    );
  }

  // ---------- SLIDE 3: RENDIMIENTO COMPARATIVO ----------

  Widget _comparativeSlide(Animation<double> intro, DailyResults results,
      int score, double? percentile) {
    final z = results.zScore;
    return AnimatedBuilder(
      animation: intro,
      builder: (context, _) {
        final t = intro.value;
        final barP = _eio(_sub(t, 0.25, 0.9));
        final barVal = (percentile ?? 0) / 100 * barP;
        final reveal = _eio(_sub(t, 0.3, 1.0));

        return _centered([
          _fadeUp(
            _eio(_sub(t, 0, 0.5)),
            _slideHeader(
              icon: Icons.compare_arrows_rounded,
              title: 'Rendimiento comparativo',
              subtitle: 'vs. resto de opositores',
            ),
          ),
          const SizedBox(height: 26),
          _fadeUp(
            _eio(_sub(t, 0.15, 0.7)),
            Column(
              children: [
                Text(
                  percentile == null ? 'P--' : 'P${(barVal * 100).round()}',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 54,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'PERCENTIL DEL USUARIO',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _fadeUp(
            _eio(_sub(t, 0.2, 0.8)),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAEFF3),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: barVal.clamp(0.02, 1.0),
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.55),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _fadeUp(
            _eio(_sub(t, 0.25, 0.85)),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF0EBE8)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Z-SCORE',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _chip('$score pts', const Color(0xFFFFF8F6),
                                  const Color(0xFFC4655A)),
                              const SizedBox(width: 8),
                              _chip(
                                z == null
                                    ? 'z --'
                                    : 'z ${z.toStringAsFixed(2)}',
                                const Color(0xFFF1F5F9),
                                const Color(0xFF475569),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  CustomPaint(
                    size: const Size(double.infinity, 148),
                    painter:
                        _ZScoreCurvePainter(zScore: z, reveal: reveal),
                  ),
                ],
              ),
            ),
          ),
          if (results.mean != null) ...[
            const SizedBox(height: 12),
            _fadeUp(
              _eio(_sub(t, 0.4, 1.0)),
              Text(
                'Media de hoy: ${results.mean!.round()} pts'
                '${results.stdDev != null ? '  ·  σ ${results.stdDev!.round()}' : ''}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ]);
      },
    );
  }

  // ---------- SLIDE 4: PROGRESO ----------

  Widget _progressSlide(Animation<double> intro, StatsSummary s) {
    final insufficient = s.insufficientData || s.avgPercentage == null;
    final avg = s.avgPercentage ?? 0;
    final trend = s.trend;
    final trendUp = (trend ?? 0) > 0.05;
    final trendDown = (trend ?? 0) < -0.05;
    final trendColor = trendUp
        ? AppColors.success
        : trendDown
            ? AppColors.error
            : AppColors.textSecondary;
    final trendIcon = trendUp
        ? Icons.trending_up_rounded
        : trendDown
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;
    final trendBasis = s.trendType == 'full'
        ? 'últimos 7 días vs media'
        : s.trendType == 'partial'
            ? 'últimos 3 días vs media'
            : '';

    return AnimatedBuilder(
      animation: intro,
      builder: (context, _) {
        final t = intro.value;
        final avgShown = (avg * _eio(_sub(t, 0.25, 1.0))).round();

        return _centered([
          _fadeUp(
            _eio(_sub(t, 0, 0.5)),
            _slideHeader(
              icon: Icons.show_chart_rounded,
              title: 'Progreso',
              subtitle: 'Tu evolución reciente',
            ),
          ),
          const SizedBox(height: 30),
          if (insufficient)
            _fadeUp(
              _eio(_sub(t, 0.2, 0.8)),
              const Text(
                'Completa algunos dailys más para ver tu media de aciertos y tu tendencia.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            )
          else ...[
            _fadeUp(
              _eio(_sub(t, 0.15, 0.7)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$avgShown%',
                    style: const TextStyle(
                      fontSize: 68,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (trend != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: trendColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          children: [
                            Icon(trendIcon, color: trendColor, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${trend > 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: trendColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              ),
            ),
            const SizedBox(height: 10),
            _fadeUp(
              _eio(_sub(t, 0.3, 0.9)),
              Text(
                'Media de aciertos de tus últimos ${s.dailys30} daily${s.dailys30 == 1 ? '' : 's'}'
                '${trendBasis.isNotEmpty ? ' · $trendBasis' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ]);
      },
    );
  }

  // ---------- SLIDE 5: DISTRIBUCIÓN ----------

  Widget _distributionSlide(Animation<double> intro, ScoreDistribution d) {
    return AnimatedBuilder(
      animation: intro,
      builder: (context, _) {
        final t = intro.value;
        final reveal = _eio(_sub(t, 0.25, 1.0));

        return _centered([
          _fadeUp(
            _eio(_sub(t, 0, 0.5)),
            _slideHeader(
              icon: Icons.bar_chart_rounded,
              title: 'Distribución de hoy',
              subtitle: '${d.totalUsers} participantes',
            ),
          ),
          const SizedBox(height: 24),
          _fadeUp(
            _eio(_sub(t, 0.15, 0.8)),
            Container(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF0EBE8)),
              ),
              child: CustomPaint(
                size: const Size(double.infinity, 150),
                painter: _DistributionPainter(
                  scores: d.scores,
                  mean: d.mean,
                  userScore: d.userScore,
                  reveal: reveal,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _fadeUp(
            _eio(_sub(t, 0.35, 0.95)),
            Row(
              children: [
                if (d.userScore != null)
                  _statChip('Tú', '${d.userScore} pts', AppColors.primaryDark),
                if (d.userScore != null && d.mean != null)
                  const SizedBox(width: 8),
                if (d.mean != null)
                  _statChip('Media', '${d.mean!.round()} pts',
                      const Color(0xFF475569)),
                if (d.percentile != null) ...[
                  const SizedBox(width: 8),
                  _statChip('Percentil', 'P${d.percentile!.round()}',
                      AppColors.success),
                ],
              ],
            ),
          ),
        ]);
      },
    );
  }

  // ---------- Helpers de contenido ----------

  Widget _slideHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F6),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _breakdownRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODELO DE SLIDE + PÁGINA + GESTOS
// ============================================================

class _StorySlide {
  final String id;
  final Color accent;

  /// Duración de auto-avance. `null` = slide interactivo (avance manual).
  final Duration? duration;
  final Widget Function(BuildContext, Animation<double> intro) content;

  const _StorySlide({
    required this.id,
    required this.accent,
    required this.duration,
    required this.content,
  });
}

/// Página de una historia: gestiona la animación de entrada (que se relanza
/// al activarse) y, en slides no interactivos, el tap izquierda/derecha para
/// retroceder/avanzar y el mantener pulsado para pausar el auto-avance.
class _StoryPage extends StatefulWidget {
  final bool active;
  final bool interactive;
  final VoidCallback onTapForward;
  final VoidCallback onTapBackward;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final PageController controller;
  final int pageIndex;
  final Widget Function(BuildContext, Animation<double> intro) builder;

  const _StoryPage({
    required this.active,
    required this.interactive,
    required this.onTapForward,
    required this.onTapBackward,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.controller,
    required this.pageIndex,
    required this.builder,
  });

  @override
  State<_StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<_StoryPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    if (widget.active) _intro.forward();
  }

  @override
  void didUpdateWidget(covariant _StoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _intro.forward(from: 0);
    } else if (!widget.active && oldWidget.active) {
      _intro.value = 1; // deja el slide ya "montado" al salir
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Escala/opacidad muy sutiles según la distancia a la página activa. Sin
    // desplazamiento extra: la página sigue al dedo 1:1 para dar control.
    Widget page = AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        double delta = 0;
        if (widget.controller.hasClients &&
            widget.controller.position.haveDimensions) {
          delta = (widget.controller.page ?? widget.pageIndex.toDouble()) -
              widget.pageIndex;
        }
        final d = delta.abs().clamp(0.0, 1.0);
        return Opacity(
          opacity: (1 - d * 0.12).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 - d * 0.03,
            child: child,
          ),
        );
      },
      // En tablet el contenido de cada slide se centra en una columna
      // acotada (el fondo animado, detrás del PageView, sigue a pantalla
      // completa).
      child: context.isWide
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: widget.builder(context, _intro),
              ),
            )
          : widget.builder(context, _intro),
    );

    if (widget.interactive) return page;

    // Slides pasivos: tap para navegar + mantener pulsado para pausar.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final w = context.size?.width ?? MediaQuery.of(context).size.width;
        if (details.localPosition.dx < w * 0.32) {
          widget.onTapBackward();
        } else {
          widget.onTapForward();
        }
      },
      onLongPressStart: (_) => widget.onHoldStart(),
      onLongPressEnd: (_) => widget.onHoldEnd(),
      child: page,
    );
  }
}

/// Physics del carrusel: enganche ágil y firme (spring crítico, sin rebote)
/// para que el swipe se sienta controlado y pegado al dedo.
class _StoryScrollPhysics extends PageScrollPhysics {
  const _StoryScrollPhysics({super.parent});

  @override
  _StoryScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _StoryScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.4,
        stiffness: 240,
        ratio: 1.1, // ligeramente sobreamortiguado: asienta sin oscilar
      );
}

/// Segmento individual de la barra de progreso superior.
class _SegmentBar extends StatelessWidget {
  final double fill;
  const _SegmentBar({required this.fill});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 3.5,
        color: Colors.white.withValues(alpha: 0.55),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fill.clamp(0.0, 1.0),
            child: Container(color: AppColors.primaryDark),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FONDO VIVO + LOADING + PISTAS
// ============================================================

/// Fondo animado: degradado cálido con orbes difuminados que derivan
/// suavemente, tintados por el color de acento del slide actual.
class _LivingBackground extends StatefulWidget {
  final Color accent;
  const _LivingBackground({required this.accent});

  @override
  State<_LivingBackground> createState() => _LivingBackgroundState();
}

class _LivingBackgroundState extends State<_LivingBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.accent),
      duration: const Duration(milliseconds: 700),
      builder: (context, color, _) {
        final accent = color ?? widget.accent;
        return AnimatedBuilder(
          animation: _c,
          builder: (context, __) {
            return CustomPaint(
              painter: _BackgroundPainter(accent: accent, t: _c.value),
              size: Size.infinite,
            );
          },
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final Color accent;
  final double t;

  _BackgroundPainter({required this.accent, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Degradado base cálido con un ligero tinte del acento.
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(AppColors.background, accent, 0.06)!,
          AppColors.background,
          Color.lerp(AppColors.background, accent, 0.10)!,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    void orb(double baseX, double baseY, double r, Color c, double phase) {
      final angle = 2 * math.pi * (t + phase);
      final dx = math.cos(angle) * size.width * 0.08;
      final dy = math.sin(angle * 0.8) * size.height * 0.05;
      final paint = Paint()
        ..color = c
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
      canvas.drawCircle(
        Offset(baseX * size.width + dx, baseY * size.height + dy),
        r,
        paint,
      );
    }

    orb(0.18, 0.16, size.width * 0.34,
        accent.withValues(alpha: 0.22), 0.0);
    orb(0.85, 0.28, size.width * 0.30,
        AppColors.gold.withValues(alpha: 0.16), 0.33);
    orb(0.72, 0.82, size.width * 0.38,
        accent.withValues(alpha: 0.16), 0.66);
    orb(0.12, 0.78, size.width * 0.26,
        AppColors.success.withValues(alpha: 0.12), 0.5);
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) =>
      old.t != t || old.accent != accent;
}

/// Pantalla breve mientras se preparan los datos de resultados.
class _PreparingView extends StatefulWidget {
  const _PreparingView();

  @override
  State<_PreparingView> createState() => _PreparingViewState();
}

class _PreparingViewState extends State<_PreparingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.06).animate(
              CurvedAnimation(parent: _c, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(Icons.emoji_events_rounded,
                  color: AppColors.primary, size: 34),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Preparando tus resultados…',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pista animada "Desliza" con chevrones que laten hacia la derecha.
class _SwipeHint extends StatefulWidget {
  const _SwipeHint();

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Desliza',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 4),
            ...List.generate(3, (i) {
              final phase = (_c.value * 3 - i).clamp(0.0, 1.0);
              final op = (math.sin(phase * math.pi)).clamp(0.0, 1.0);
              return Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.primary.withValues(alpha: 0.35 + op * 0.55),
              );
            }),
          ],
        );
      },
    );
  }
}

/// Envoltorio con leve flotación continua (para el medallón del hero).
class _FloatWrap extends StatefulWidget {
  final Widget child;
  const _FloatWrap({required this.child});

  @override
  State<_FloatWrap> createState() => _FloatWrapState();
}

class _FloatWrapState extends State<_FloatWrap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final y = math.sin(_c.value * math.pi) * 6;
        return Transform.translate(offset: Offset(0, -y), child: child);
      },
      child: widget.child,
    );
  }
}

/// Medallón del hero: círculo con trofeo y anillo coral.
class _HeroMedal extends StatelessWidget {
  const _HeroMedal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F6),
        shape: BoxShape.circle,
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(Icons.emoji_events_rounded,
          color: AppColors.primary, size: 32),
    );
  }
}

// ============================================================
// SLIDE: RANKING (interactivo)
// ============================================================

class _RankingSlide extends StatefulWidget {
  final Animation<double> intro;
  final List<RankingEntry> ranking;
  final String? userId;
  final String userName;
  final int userAvatarId;
  final int userScore;

  const _RankingSlide({
    required this.intro,
    required this.ranking,
    required this.userId,
    required this.userName,
    required this.userAvatarId,
    required this.userScore,
  });

  @override
  State<_RankingSlide> createState() => _RankingSlideState();
}

/// Avatar circular con la foto de perfil real (por `avatarId`). Mientras carga
/// o si falla la descarga, muestra el avatar de iniciales como respaldo.
class _AvatarImage extends StatelessWidget {
  final int avatarId;
  final String name;
  final double size;

  const _AvatarImage({
    required this.avatarId,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.network(
        AppConfig.avatarUrl(avatarId),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : UserAvatar(name: name, size: size),
        errorBuilder: (_, __, ___) => UserAvatar(name: name, size: size),
      ),
    );
  }
}

/// El ranking se presenta en dos fases:
///  A) revela el nombre del usuario y, con suspense, el puesto en el que ha
///     quedado (cuenta ascendente + pop).
///  B) transiciona a la clasificación completa.
/// La fase A arranca cuando el slide se activa (al empezar la animación
/// [intro] que le pasa el carrusel) y salta a B automáticamente tras unos
/// segundos o al tocar la pantalla.
class _RankingSlideState extends State<_RankingSlide>
    with TickerProviderStateMixin {
  static const _colHeaderStyle = TextStyle(
    color: Color(0xFF4B5563),
    fontWeight: FontWeight.w800,
    fontSize: 9,
    letterSpacing: 1.4,
  );

  late final AnimationController _reveal; // entrada de la fase A
  late final AnimationController _toList; // transición A → B
  Timer? _autoTimer;
  bool _started = false;
  bool _showList = false;
  int _userRank = 1;

  @override
  void initState() {
    super.initState();
    _userRank = _computeRank();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _toList = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    widget.intro.addStatusListener(_onIntro);
    if (widget.intro.value > 0 ||
        widget.intro.status == AnimationStatus.forward) {
      _startReveal();
    }
  }

  /// Puesto del usuario: por userId, si no por nombre, si no por puntuación
  /// (nº de opositores con más puntos + 1). Siempre hay clasificación aquí.
  int _computeRank() {
    for (final e in widget.ranking) {
      if (e.userId != null && e.userId == widget.userId) return e.position;
    }
    for (final e in widget.ranking) {
      if (e.displayName == widget.userName) return e.position;
    }
    final higher =
        widget.ranking.where((e) => e.score > widget.userScore).length;
    return higher + 1;
  }

  void _onIntro(AnimationStatus status) {
    if (status == AnimationStatus.forward) _startReveal();
  }

  void _startReveal() {
    if (_started) return;
    _started = true;
    _reveal.forward(from: 0);
    // Tras la revelación + un compás de espera, pasa a la tabla.
    _autoTimer = Timer(const Duration(milliseconds: 3100), _goToList);
  }

  void _goToList() {
    if (_showList || !mounted) return;
    _autoTimer?.cancel();
    setState(() => _showList = true);
    _toList.forward(from: 0);
  }

  @override
  void dispose() {
    widget.intro.removeStatusListener(_onIntro);
    _autoTimer?.cancel();
    _reveal.dispose();
    _toList.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_reveal, _toList]),
      builder: (context, _) {
        final tl = _toList.value;
        return Stack(
          children: [
            if (_showList)
              Opacity(
                opacity: tl,
                child: Transform.translate(
                  offset: Offset(0, (1 - tl) * 26),
                  child: _buildList(),
                ),
              ),
            if (tl < 1)
              IgnorePointer(
                ignoring: _showList,
                child: Opacity(
                  opacity: (1 - tl).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1 - 0.06 * tl,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _goToList,
                      child: _buildReveal(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------- FASE A: revelación del puesto ----------

  Widget _buildReveal() {
    final t = _reveal.value;
    final rankT = _eio(_sub(t, 0.45, 1.0));
    final shownRank =
        (_userRank * rankT).round().clamp(1, _userRank);
    final pop = Curves.elasticOut.transform(_sub(t, 0.45, 1.0));
    final numOpacity = _eio(_sub(t, 0.42, 0.6));
    final podium = _userRank <= 3;
    final medal = podium ? ['🥇', '🥈', '🥉'][_userRank - 1] : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 84, 28, 84),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fadeUp(
                    _eio(_sub(t, 0, 0.22)),
                    const Text(
                      'TU POSICIÓN DE HOY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Avatar con anillo suave
                  Opacity(
                    opacity: _eio(_sub(t, 0.05, 0.42)),
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * _eio(_sub(t, 0.05, 0.42)),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.14),
                        ),
                        child: _AvatarImage(
                          avatarId: widget.userAvatarId,
                          name: widget.userName,
                          size: 78,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _fadeUp(
                    _eio(_sub(t, 0.2, 0.5)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        widget.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Número de puesto con glow y rebote
                  Opacity(
                    opacity: numOpacity,
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * pop.clamp(0.0, 1.3),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ImageFiltered(
                            imageFilter:
                                ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                            child: Container(
                              width: 128,
                              height: 128,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary
                                    .withValues(alpha: 0.45 * numOpacity),
                              ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '#$shownRank',
                              style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w900,
                                fontSize: 86,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (podium) ...[
                    const SizedBox(height: 16),
                    _fadeUp(
                      _eio(_sub(t, 0.75, 1.0)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(medal,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 6),
                            const Text(
                              '¡Estás en el podio!',
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _fadeUp(
            _eio(_sub(t, 0.85, 1.0)),
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_rounded,
                      size: 15, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Text(
                    'Toca para ver la clasificación',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- FASE B: clasificación completa ----------

  Widget _buildList() {
    final top = widget.ranking.take(25).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 92, 18, 78),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.military_tech_rounded,
                  color: Color(0xFF4B5563), size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ranking Global',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                    Text(
                      'TOP 25',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              _LiveBadge(),
            ],
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                    width: 44, child: Text('PUESTO', style: _colHeaderStyle)),
                Expanded(
                  child:
                      Center(child: Text('USUARIO', style: _colHeaderStyle)),
                ),
                SizedBox(
                  width: 56,
                  child: Text('PUNTOS',
                      style: _colHeaderStyle, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE7DFDA), height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: top.length,
                itemBuilder: (context, i) {
                  final entry = top[i];
                  final isUser = _isUser(entry);
                  return _rankingRow(entry, isUser);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                const Text(
                  'TU PUESTO ACTUAL',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        '$_userRank.',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                    _AvatarImage(
                      avatarId: widget.userAvatarId,
                      name: widget.userName,
                      size: 32,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.userScore} pts',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isUser(RankingEntry entry) =>
      (entry.userId != null && entry.userId == widget.userId) ||
      (widget.userId == null && entry.position == _userRank);

  Widget _rankingRow(RankingEntry entry, bool isUser) {
    final isPodium = entry.position <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: isUser
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
            : Border.all(color: const Color(0xFFF0EAE6)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              isPodium
                  ? ['🥇', '🥈', '🥉'][entry.position - 1]
                  : '${entry.position}',
              style: TextStyle(
                fontSize: isPodium ? 17 : 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          _AvatarImage(
            avatarId: entry.avatarId,
            name: entry.displayName,
            size: 26,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ink,
                fontWeight: isUser ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            '${entry.score}',
            style: TextStyle(
              color: isUser ? AppColors.primary : _ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip "LIVE" con punto pulsante.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EF),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFC4655A),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Color(0xFFC4655A),
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SLIDE: REVISIÓN DE PREGUNTA (interactivo)
// ============================================================

class _ReviewSlide extends StatefulWidget {
  final Animation<double> intro;
  final ReviewQuestion question;
  final int index;
  final int total;

  const _ReviewSlide({
    required this.intro,
    required this.question,
    required this.index,
    required this.total,
  });

  @override
  State<_ReviewSlide> createState() => _ReviewSlideState();
}

class _ReviewSlideState extends State<_ReviewSlide> {
  bool _expanded = false;
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final correctIndex = q.correctIndex;
    final selectedIndex = q.selectedIndex;
    final blank = selectedIndex < 0;

    return FadeTransition(
      opacity: CurvedAnimation(parent: widget.intro, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: widget.intro, curve: Curves.easeOutCubic),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 88, 18, 82),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabecera: revisión N/total + estado
              Row(
                children: [
                  const Icon(Icons.menu_book_rounded,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Revisión · ${widget.index + 1}/${widget.total}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: q.isCorrect
                          ? AppColors.success.withValues(alpha: 0.14)
                          : const Color(0xFFFFF1EC),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          q.isCorrect
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 14,
                          color: q.isCorrect
                              ? AppColors.successDark
                              : const Color(0xFFC45B4B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          q.isCorrect
                              ? 'Correcta'
                              : (blank ? 'En blanco' : 'Fallada'),
                          style: TextStyle(
                            color: q.isCorrect
                                ? AppColors.successDark
                                : const Color(0xFFC45B4B),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Guardar la pregunta en un mazo desde la propia revisión:
                  // es justo el momento en que uno decide que quiere volver a
                  // verla.
                  SaveToDeckButton(questionId: q.questionId),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x297D8A96),
                        blurRadius: 30,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q.statement,
                          style: const TextStyle(
                            color: Color(0xFF1F2937),
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(q.options.length, (idx) {
                          final isCorrectOpt = idx == correctIndex;
                          final isWrongSel = idx == selectedIndex &&
                              selectedIndex != correctIndex;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isCorrectOpt
                                  ? AppColors.success.withValues(alpha: 0.10)
                                  : isWrongSel
                                      ? const Color(0xFFFFF1EC)
                                      : Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isCorrectOpt
                                    ? AppColors.success.withValues(alpha: 0.4)
                                    : isWrongSel
                                        ? AppColors.primary
                                            .withValues(alpha: 0.45)
                                        : const Color(0xFFF0EAE6),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 27,
                                  height: 27,
                                  decoration: BoxDecoration(
                                    color: isCorrectOpt
                                        ? AppColors.success
                                        : AppColors.background,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isCorrectOpt
                                          ? AppColors.success
                                          : AppColors.primary
                                              .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    idx < _letters.length
                                        ? _letters[idx]
                                        : '${idx + 1}',
                                    style: TextStyle(
                                      color: isCorrectOpt
                                          ? Colors.white
                                          : const Color(0xFFC45B4B),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      q.options[idx],
                                      style: TextStyle(
                                        color: (isCorrectOpt || isWrongSel)
                                            ? const Color(0xFF2D3748)
                                            : AppColors.textSecondary,
                                        fontSize: 13.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                                if (isCorrectOpt)
                                  _tag('CORRECTA', AppColors.successDark),
                                if (isWrongSel)
                                  _tag('TU RESPUESTA',
                                      const Color(0xFFC45B4B)),
                              ],
                            ),
                          );
                        }),
                        if (q.hasImage && q.imageUrl != null) ...[
                          const SizedBox(height: 6),
                          ZoomableImage(url: q.imageUrl!),
                          const SizedBox(height: 6),
                        ],
                        const SizedBox(height: 8),
                        Pressable(
                          onTap: () =>
                              setState(() => _expanded = !_expanded),
                          pressedScale: 0.98,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8F6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Ver explicación',
                                    style: TextStyle(
                                      color: Color(0xFFC45B4B),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: _expanded ? 0.5 : 0,
                                  duration:
                                      const Duration(milliseconds: 250),
                                  child: const Icon(
                                    Icons.expand_more_rounded,
                                    color: Color(0xFFC45B4B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          sizeCurve: Curves.easeOutCubic,
                          crossFadeState: _expanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: const SizedBox(width: double.infinity),
                          secondChild: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFE9E4E1)),
                            ),
                            child: Text(
                              (q.explanation?.isNotEmpty ?? false)
                                  ? q.explanation!
                                  : 'No hay explicación disponible para esta pregunta.',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13.5,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 8.5,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SLIDE: ACTIVIDAD / RACHA (final)
// ============================================================

class _ActivitySlide extends StatefulWidget {
  final Animation<double> intro;
  final ApiService api;
  final VoidCallback onExit;

  const _ActivitySlide({
    required this.intro,
    required this.api,
    required this.onExit,
  });

  @override
  State<_ActivitySlide> createState() => _ActivitySlideState();
}

class _ActivitySlideState extends State<_ActivitySlide> {
  late final Future<ActivityHeatmap> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getActivityHeatmap();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: widget.intro, curve: Curves.easeOut),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 84, 24, 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const _FloatWrap(
                child: Text('🔥', style: TextStyle(fontSize: 40)),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tu actividad',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Últimos 30 días',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              FutureBuilder<ActivityHeatmap>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 34),
                      child: CircularProgressIndicator(
                          color: AppColors.primary),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.days.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No se pudo cargar tu actividad ahora mismo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13.5),
                      ),
                    );
                  }
                  final data = snapshot.data!;
                  return Column(
                    children: [
                      _HeatGrid(days: data.days),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _streakChip(
                            '🔥 Racha',
                            '${data.currentStreak} día${data.currentStreak == 1 ? '' : 's'}',
                            AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          _streakChip(
                            '🏆 Récord',
                            '${data.longestStreak} día${data.longestStreak == 1 ? '' : 's'}',
                            AppColors.gold,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const Spacer(),
              Pressable(
                onTap: widget.onExit,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 9),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.home_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Volver al Hub',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _streakChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rejilla de 30 celdas que aparecen escalonadamente, con fuego en hoy.
class _HeatGrid extends StatefulWidget {
  final List<HeatDay> days;
  const _HeatGrid({required this.days});

  @override
  State<_HeatGrid> createState() => _HeatGridState();
}

class _HeatGridState extends State<_HeatGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _levelColor(int level) => switch (level) {
        2 => AppColors.primary,
        1 => AppColors.primary.withValues(alpha: 0.32),
        _ => AppColors.surfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final n = days.length;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          alignment: WrapAlignment.center,
          children: List.generate(n, (i) {
            final start = (i / n) * 0.6;
            final t = ((_controller.value - start) / 0.4).clamp(0.0, 1.0);
            final eased = Curves.easeOutBack.transform(t);
            final isToday = i == n - 1;

            return Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.4 + 0.6 * eased,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _levelColor(days[i].level),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: (isToday && t > 0.5)
                      ? const Text('🔥', style: TextStyle(fontSize: 13))
                      : null,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ============================================================
// PAINTERS
// ============================================================

/// Anillo de aciertos: pista coral, progreso verde salvia y degradado dorado
/// giratorio cuando es un 100%.
class _AccuracyRingPainter extends CustomPainter {
  final double progress;
  final bool perfect;

  _AccuracyRingPainter({required this.progress, required this.perfect});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 14;
    final stroke = size.width * 0.105;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = perfect ? const Color(0xFFF0EBE8) : const Color(0xFFC4655A);
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    if (perfect) {
      fill.shader = const SweepGradient(
        colors: [
          Color(0xFFD4AF37),
          Color(0xFFFFD700),
          Color(0xFFFFF4B0),
          Color(0xFFFFD700),
          Color(0xFFD4AF37),
        ],
      ).createShader(rect);
    } else {
      fill.color = AppColors.success;
    }

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, fill);
  }

  @override
  bool shouldRepaint(covariant _AccuracyRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.perfect != perfect;
}

/// Borde discontinuo (panel "Desglose de puntuación").
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

class _DashedLineHPainter extends CustomPainter {
  final Color color;

  _DashedLineHPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + 6, 0), paint);
      x += 11;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLineHPainter oldDelegate) => false;
}

/// Campana de Gauss con marcadores σ y línea "Tú" en el z del usuario.
class _ZScoreCurvePainter extends CustomPainter {
  final double? zScore;
  final double reveal;

  _ZScoreCurvePainter({required this.zScore, required this.reveal});

  @override
  void paint(Canvas canvas, Size size) {
    const marginTop = 18.0;
    const marginBottom = 30.0;
    const marginSide = 12.0;
    final innerW = size.width - marginSide * 2;
    final innerH = size.height - marginTop - marginBottom;

    final domain = math.max(3, (zScore?.abs() ?? 0).ceil() + 1).toDouble();

    double xToPx(double x) =>
        marginSide + (x + domain) / (2 * domain) * innerW;
    double yToPx(double y) => marginTop + innerH - y * innerH;

    double pdf(double x) => math.exp(-0.5 * x * x);

    final path = Path();
    const samples = 90;
    final visibleSamples = (samples * reveal).round();
    for (var i = 0; i <= visibleSamples; i++) {
      final x = -domain + (i / samples) * (2 * domain);
      final px = xToPx(x);
      final py = yToPx(pdf(x));
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    if (visibleSamples > 0) {
      final area = Path.from(path)
        ..lineTo(xToPx(-domain + (visibleSamples / samples) * 2 * domain),
            yToPx(0))
        ..lineTo(xToPx(-domain), yToPx(0))
        ..close();
      canvas.drawPath(
        area,
        Paint()..color = AppColors.success.withValues(alpha: 0.16),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.success
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }

    final refPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1;
    for (final ref in [-1.0, 0.0, 1.0]) {
      _dashedVLine(canvas, xToPx(ref), marginTop, size.height - marginBottom,
          refPaint, ref == 0 ? 4 : 2);
    }

    canvas.drawLine(
      Offset(marginSide, size.height - marginBottom),
      Offset(size.width - marginSide, size.height - marginBottom),
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..strokeWidth = 1,
    );

    final textStyle = ui.TextStyle(
      color: const Color(0xFF7D8A96),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    for (var tk = -domain.toInt(); tk <= domain.toInt(); tk++) {
      final label = tk == -1 ? '-1σ' : (tk == 1 ? '+1σ' : '$tk');
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 10,
      ))
        ..pushStyle(textStyle)
        ..addText(label);
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 30));
      canvas.drawParagraph(
        paragraph,
        Offset(xToPx(tk.toDouble()) - 15, size.height - marginBottom + 6),
      );
    }

    if (zScore != null && reveal > 0.75) {
      final clamped = zScore!.clamp(-domain, domain);
      final px = xToPx(clamped);
      final markerOpacity = ((reveal - 0.75) / 0.25).clamp(0.0, 1.0);
      final marker = Paint()
        ..color = const Color(0xFFC4655A).withValues(alpha: markerOpacity)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(px, marginTop),
        Offset(px, size.height - marginBottom),
        marker,
      );

      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ))
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFFC4655A).withValues(alpha: markerOpacity),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ))
        ..addText('Tú');
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 30));
      canvas.drawParagraph(paragraph, Offset(px - 15, 0));
    }
  }

  void _dashedVLine(Canvas canvas, double x, double top, double bottom,
      Paint paint, double dash) {
    var y = top;
    while (y < bottom) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dash), paint);
      y += dash + 4;
    }
  }

  @override
  bool shouldRepaint(covariant _ZScoreCurvePainter oldDelegate) =>
      oldDelegate.reveal != reveal || oldDelegate.zScore != zScore;
}

/// Histograma de la distribución de puntuaciones de hoy.
class _DistributionPainter extends CustomPainter {
  final List<int> scores;
  final double? mean;
  final int? userScore;
  final double reveal;

  _DistributionPainter({
    required this.scores,
    required this.mean,
    required this.userScore,
    required this.reveal,
  });

  static const _bins = 16;

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    const marginTop = 16.0;
    const marginBottom = 24.0;
    const marginSide = 8.0;
    final innerW = size.width - marginSide * 2;
    final innerH = size.height - marginTop - marginBottom;

    final minScore = scores.reduce(math.min).toDouble();
    final maxScore = scores.reduce(math.max).toDouble();
    final span = maxScore - minScore;
    final lo = minScore - span * 0.08 - 1;
    final hi = maxScore + span * 0.08 + 1;
    final range = (hi - lo) == 0 ? 1.0 : (hi - lo);

    final counts = List<int>.filled(_bins, 0);
    for (final s in scores) {
      var idx = (((s - lo) / range) * _bins).floor();
      idx = idx.clamp(0, _bins - 1);
      counts[idx]++;
    }
    final maxCount = counts.reduce(math.max).toDouble();
    if (maxCount == 0) return;

    double xToPx(double v) => marginSide + ((v - lo) / range) * innerW;

    int? userBin;
    if (userScore != null) {
      userBin =
          (((userScore! - lo) / range) * _bins).floor().clamp(0, _bins - 1);
    }

    final barW = innerW / _bins;
    for (var i = 0; i < _bins; i++) {
      final h = (counts[i] / maxCount) * innerH * reveal;
      if (h <= 0) continue;
      final left = marginSide + i * barW + 1.2;
      final top = marginTop + innerH - h;
      final isUser = userBin == i;
      final paint = Paint()
        ..color = isUser
            ? AppColors.primaryDark
            : AppColors.primary.withValues(alpha: 0.35);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barW - 2.4, h),
          const Radius.circular(3),
        ),
        paint,
      );
    }

    canvas.drawLine(
      Offset(marginSide, marginTop + innerH),
      Offset(size.width - marginSide, marginTop + innerH),
      Paint()
        ..color = const Color(0xFFE7DFDA)
        ..strokeWidth = 1,
    );

    if (mean != null) {
      final mx = xToPx(mean!);
      final p = Paint()
        ..color = const Color(0xFF94A3B8)
        ..strokeWidth = 1.4;
      var y = marginTop;
      while (y < marginTop + innerH) {
        canvas.drawLine(Offset(mx, y), Offset(mx, y + 4), p);
        y += 8;
      }
      _label(canvas, 'media', mx, marginTop + innerH + 6,
          const Color(0xFF7D8A96), 9);
    }

    if (userScore != null && reveal > 0.55) {
      final ux = xToPx(userScore!.toDouble());
      final op = ((reveal - 0.55) / 0.45).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(ux, marginTop),
        Offset(ux, marginTop + innerH),
        Paint()
          ..color = AppColors.primaryDark.withValues(alpha: op)
          ..strokeWidth = 2.4,
      );
      _label(canvas, 'Tú', ux, 0,
          AppColors.primaryDark.withValues(alpha: op), 11,
          bold: true);
    }
  }

  void _label(Canvas canvas, String text, double cx, double y, Color color,
      double fontSize,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, y));
  }

  @override
  bool shouldRepaint(covariant _DistributionPainter oldDelegate) =>
      oldDelegate.reveal != reveal ||
      oldDelegate.userScore != userScore ||
      oldDelegate.scores != scores;
}
