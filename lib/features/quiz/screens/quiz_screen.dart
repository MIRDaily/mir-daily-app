import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import 'package:provider/provider.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/daily_provider.dart';
import '../../daily/daily_quiz_screen.dart';
import '../../results/results_screen.dart';
import '../../../shared/widgets/goo_fission_loader.dart';
import '../game/pack_opening_game.dart';

/// Pestaña "Sobre": mantiene la animación Flame de apertura del sobre de
/// v10.6, pero alimentada por el daily REAL del backend (DailyProvider).
/// Al rasgar el sobre se entra al quiz de las 5 preguntas del día y, al
/// terminar, a la pantalla de resultados con puntuación y ranking.
class QuizScreen extends StatefulWidget {
  final Function(bool isOpening)? onPackStateChanged;
  final bool isVisible;

  /// Entrada especial (marcada y lenta) del sobre solo tras el onboarding.
  final bool justOnboarded;

  const QuizScreen({
    super.key,
    this.onPackStateChanged,
    this.isVisible = true,
    this.justOnboarded = false,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  PackOpeningGame? _game;

  // Animación de entrada del daily (fundido + escala) al abrir la app.
  late AnimationController _dailyEntry;

  bool _fetchTriggered = false;
  bool _quizPushed = false;
  bool _opening = false; // mostrando el goo a pantalla completa
  bool _examinedGoo = false; // ya se mostró la ventana del goo esta sesión
  bool? _lastPackState;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _dailyEntry = AnimationController(
      vsync: this,
      // Muy marcada y lenta solo tras el onboarding.
      duration: Duration(milliseconds: widget.justOnboarded ? 1800 : 650),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(
          Duration(milliseconds: widget.justOnboarded ? 420 : 150), () {
        if (mounted) _dailyEntry.forward();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetch());
  }

  void _maybeFetch() {
    if (_fetchTriggered) return;
    final daily = context.read<DailyProvider>();
    if (daily.status == DailyStatus.idle || daily.status == DailyStatus.error) {
      _fetchTriggered = true;
      daily.fetchDaily();
    }
  }

  /// Notifica a MainNavigation si la zona del sobre debe bloquear el swipe.
  /// Se hace fuera del build para no provocar setState durante el build.
  void _setPackState(bool opening) {
    if (_lastPackState == opening) return;
    _lastPackState = opening;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onPackStateChanged?.call(opening);
    });
  }

  void _ensureGame(DailyProvider daily) {
    if (_game != null || daily.questions.isEmpty) return;
    final specialties =
        daily.questions.map((q) => q.subject ?? 'General').toList();
    _game = PackOpeningGame(
      specialties: specialties,
      onComplete: _onPackOpeningComplete,
    );
    _game!.setVisible(widget.isVisible);
  }

  Future<void> _onPackOpeningComplete(List<String> specialties) async {
    if (!mounted || _quizPushed) return;
    _quizPushed = true;
    HapticFeedback.mediumImpact();
    _setPackState(false);

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DailyQuizScreen()),
    );

    // De vuelta del quiz: el estado pasa a "completed" y la propia pantalla
    // de completado lanza la ventana del goo antes de "¡Daily completado!".
    if (mounted) {
      setState(() {
        _game = null;
        _quizPushed = false;
      });
    }
  }

  /// Cierra la ventana del goo tras 10s y muestra "¡Daily completado!".
  Future<void> _closeGooAfterDelay() async {
    await Future.delayed(const Duration(seconds: 10));
    if (mounted) setState(() => _opening = false);
  }

  @override
  void didUpdateWidget(QuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      _game?.setVisible(widget.isVisible);
    }
  }

  @override
  void dispose() {
    _dailyEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // requerido por AutomaticKeepAliveClientMixin
    return FadeTransition(
      opacity: CurvedAnimation(parent: _dailyEntry, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(
                begin: widget.justOnboarded ? 0.55 : 0.97, end: 1.0)
            .animate(CurvedAnimation(
                parent: _dailyEntry,
                curve: widget.justOnboarded
                    ? Curves.easeOutBack
                    : Curves.easeOutCubic)),
        child: _buildCurrent(context),
      ),
    );
  }

  Widget _buildCurrent(BuildContext context) {
    // Transición tras abrir el sobre: goo a pantalla completa.
    if (_opening) {
      _setPackState(false);
      return _buildGooScreen();
    }

    final daily = context.watch<DailyProvider>();

    switch (daily.status) {
      case DailyStatus.idle:
      case DailyStatus.checking:
        _setPackState(false);
        return _buildLoading('Cargando tu sobre de hoy...');

      case DailyStatus.error:
        _setPackState(false);
        return _buildError(daily);

      case DailyStatus.completed:
        _setPackState(false);
        // Antes de "¡Daily completado!" mostramos el goo 10s (una sola vez).
        // Marcamos _opening de forma síncrona para que ningún rebuild
        // intermedio cuele la pantalla de completado.
        if (!_examinedGoo) {
          _examinedGoo = true;
          _opening = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _closeGooAfterDelay());
          return _buildGooScreen();
        }
        return _buildCompleted();

      case DailyStatus.ready:
      case DailyStatus.playing:
      case DailyStatus.submitting:
        _ensureGame(daily);
        if (_game == null) {
          return _buildLoading('Preparando las preguntas...');
        }
        _setPackState(true);
        return _buildPackOpeningScreen();
    }
  }

  // ==========================
  // ESTADOS NO-JUEGO
  // ==========================

  Widget _buildLoading(String message) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 18),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pantalla del efecto goo, mostrada al volver del quiz (ventana de 10s
  /// para examinar la animación) antes de "¡Daily completado!".
  Widget _buildGooScreen() {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: GooFissionLoader(size: 200, label: 'Guardando tu resultado...'),
      ),
    );
  }

  Widget _buildError(DailyProvider daily) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 64, color: AppColors.textLight),
              const SizedBox(height: 18),
              Text(
                daily.error ?? 'No se pudo cargar el sobre de hoy.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  _fetchTriggered = false;
                  context.read<DailyProvider>().fetchDaily();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompleted() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.envelopeTop, AppColors.envelopeBottom],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                '¡Daily completado!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ya abriste tu sobre de hoy.\nVuelve mañana a por uno nuevo ✨',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ResultsScreen()),
                  );
                },
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('Ver resultados'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================
  // SOBRE (ANIMACIÓN FLAME)
  // ==========================

  Widget _buildPackOpeningScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        // La animación del sobre está calibrada para una pantalla de móvil
        // (vertical, estrecha). En tablet se centra en una columna de ese
        // ancho y el resto queda de fondo, en vez de estirar el sobre y las
        // cartas por todo el ancho.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.isWide ? 460 : double.infinity,
          ),
          child: Stack(
            children: [
              // El fondo lo pone el propio juego
              // (PackOpeningGame.backgroundColor), que es lo único que se
              // pinta mientras carga.
              GameWidget(game: _game!),
              _buildOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return StatefulBuilder(
      builder: (context, setOverlayState) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && _game != null && !_quizPushed) {
            setOverlayState(() {});
          }
        });

        final tearProgress = _game?.tearProgress ?? 0.0;
        final tearComplete = _game?.tearComplete ?? false;

        return Stack(
          children: [
            // El gesto lo enseña la tijera que recorre la línea de corte
            // (CutLineIndicatorComponent), no un cartel.

            // Barra de progreso del rasgado
            if (tearProgress > 0 && !tearComplete)
              Positioned(
                bottom: 100,
                left: 50,
                right: 50,
                child: Column(
                  children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: tearProgress,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color.lerp(
                                AppColors.primary, Colors.green, tearProgress)!,
                          ),
                          minHeight: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(tearProgress * 100).toInt()}%',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
