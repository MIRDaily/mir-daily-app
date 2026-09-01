import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/notification_service.dart';
import 'widgets/nav_rail.dart';
import '../biblioteca/biblioteca_hub_screen.dart';
import '../quiz/screens/quiz_screen.dart';
import '../focus/providers/focus_provider.dart';
import '../premium/screens/premium_screen.dart';
import '../profile/screens/profile_screen.dart';
import '../versus/screens/versus_screen.dart';

class MainNavigation extends StatefulWidget {
  /// true cuando se llega justo tras completar el onboarding: la barra inferior
  /// y el sobre del daily hacen una entrada más marcada y lenta, solo esa vez.
  final bool justOnboarded;

  const MainNavigation({super.key, this.justOnboarded = false});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with TickerProviderStateMixin {
  /// Posición del daily dentro de la barra. Versus se metió a su izquierda, así
  /// que ya no es la 1; tenerlo en una constante evita que se descuadren el
  /// PageView, la pastilla y los booleanos de visibilidad del sobre.
  static const int _quizIndex = 2;

  late PageController _pageController;

  // Lo único que hace falta de la posición del PageView, ya destilado a
  // booleanos: cambian un par de veces por gesto, mientras que la posición
  // cambia en cada frame. Guardar el derivado (y no la posición) es lo que
  // evita reconstruir las cuatro pantallas 120 veces por segundo al deslizar.
  bool _isQuizVisible = true;
  bool _isOnQuizPage = true;

  bool _isPackOpening = true;

  // Índice de la pestaña seleccionada (destino), independiente del scroll
  // continuo del PageView. Arranca en el daily, que es la pestaña central.
  int _selectedIndex = _quizIndex;
  // Verdadero mientras corre la animación de un toque de pestaña, para ignorar
  // los onPageChanged intermedios que dispara animateToPage al pasar páginas.
  bool _tapNavigating = false;

  // Animación propia de la "pastilla" (destacador): posición bouncy + una
  // envolvente tipo "ola" (crece al viajar, cresta en el medio, y baja al
  // llegar). Va directa de un extremo a otro sin barrer las intermedias.
  late AnimationController _pillCtrl;
  double _pillFrom = 1;
  double _pillTo = 1;

  // Animación de entrada de la barra inferior al abrir la app.
  late AnimationController _barEntry;

  /// Posición actual de la pastilla (en índices, p. ej. 1.7), con rebote.
  double get _pillPos {
    final from = _pillFrom;
    final to = _pillTo;
    final delta = (to - from).abs();
    final v = _pillCtrl.value;
    final eased = delta < 0.05 ? v : _backOut(v, _tensionFor(delta));
    final raw = from + (to - from) * eased;
    final maxIdx = (_navItems.length - 1).toDouble();
    // Tope de seguridad para no salirse de la barra (el rebote ya es pequeño
    // y ~constante, así que casi nunca llega a activarse).
    return raw.clamp(-0.16, maxIdx + 0.16);
  }

  // Tensión del rebote INVERSA a la distancia: así el "overshoot" en píxeles es
  // aproximadamente constante, y un salto corto o de extremo a extremo rebotan
  // igual de pulido (ni poco ni demasiado).
  double _tensionFor(double delta) => (1.4 / delta).clamp(0.4, 2.2);

  // Ease "back out" con tensión configurable (s mayor = más rebote). Termina
  // exactamente en 1 en t=1; el pico de sobrepaso ocurre algo antes.
  static double _backOut(double t, double s) {
    final u = t - 1;
    return u * u * ((s + 1) * u + s) + 1;
  }

  void _movePillTo(int index) {
    _pillFrom = _pillPos; // arranca desde donde esté (permite interrumpir)
    _pillTo = index.toDouble();
    // Duración PROPORCIONAL a la distancia => velocidad ~constante. Antes era
    // fija, así que los saltos de extremo a extremo se sentían acelerados y el
    // rebote salía cortado.
    final delta = (_pillTo - _pillFrom).abs();
    _pillCtrl.duration = Duration(
      milliseconds: (300 + 150 * delta).round().clamp(300, 850),
    );
    _pillCtrl.forward(from: 0);
  }

  final List<NavItem> _navItems = const [
    NavItem(icon: Icons.style_outlined, activeIcon: Icons.style, label: 'Studio'),
    NavItem(icon: Icons.bolt_outlined, activeIcon: Icons.bolt, label: 'Versus'),
    NavItem(icon: Icons.quiz_outlined, activeIcon: Icons.quiz, label: 'Quiz'),
    NavItem(icon: Icons.workspace_premium_outlined, activeIcon: Icons.workspace_premium, label: 'Premium'),
    NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Perfil'),
  ];

  /// Último ancho del área de páginas, para detectar rotaciones / cambios de
  /// layout (aparece/desaparece el raíl) y recolocar el PageView.
  double? _lastPageAreaWidth;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _quizIndex);
    _pillFrom = _selectedIndex.toDouble();
    _pillTo = _selectedIndex.toDouble();
    _pillCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
      value: 1, // en reposo (ya asentada)
    );
    _barEntry = AnimationController(
      vsync: this,
      // Muy marcada y lenta solo tras el onboarding.
      duration: Duration(milliseconds: widget.justOnboarded ? 1500 : 700),
    );
    // Retardo mayor tras el onboarding (deja respirar tras la transición).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(
          Duration(milliseconds: widget.justOnboarded ? 340 : 120), () {
        if (mounted) _barEntry.forward();
      });
    });

    _pageController.addListener(_onPageScroll);

    // La primera vez, ofrecer activar el recordatorio diario del daily.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptNotifications();
    });
  }

  /// Corre en cada frame del scroll, así que solo repinta si alguno de los dos
  /// booleanos ha cambiado de verdad (una o dos veces por gesto, al cruzar el
  /// medio entre dos páginas).
  void _onPageScroll() {
    final page = _pageController.page ?? _quizIndex.toDouble();
    final isQuizVisible = (page - _quizIndex).abs() < 0.5;
    final isOnQuizPage = page.round() == _quizIndex;

    if (isQuizVisible == _isQuizVisible && isOnQuizPage == _isOnQuizPage) return;

    setState(() {
      _isQuizVisible = isQuizVisible;
      _isOnQuizPage = isOnQuizPage;
    });
  }

  Future<void> _maybePromptNotifications() async {
    final service = NotificationService();
    if (await service.wasPrompted() || await service.isEnabled()) return;
    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Activar recordatorios?'),
        content: const Text(
          'Te avisaremos cada día cuando tu sobre del daily esté listo, para que no pierdas tu racha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (accept == true) {
      final ok = await service.enableDailyReminder(await service.reminderTime());
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Activa el permiso de notificaciones desde los ajustes del sistema.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // Marcar como preguntado (y dejarlo desactivado) para no volver a insistir.
      await service.disableDailyReminder();
    }
  }
  
  List<Widget> _buildScreens() {
    return [
      const BibliotecaHubScreen(key: ValueKey('biblioteca')),
      const VersusScreen(key: ValueKey('versus')),
      QuizScreen(
        key: const ValueKey('quiz'),
        onPackStateChanged: (isOpening) {
          setState(() {
            _isPackOpening = isOpening;
          });
        },
        isVisible: _isQuizVisible,
        justOnboarded: widget.justOnboarded,
      ),
      const PremiumScreen(key: ValueKey('premium')),
      const ProfileScreen(key: ValueKey('profile')),
    ];
  }

  @override
  void dispose() {
    _pillCtrl.dispose();
    _barEntry.dispose();
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    super.dispose();
  }

  /// Al rotar (o al aparecer/desaparecer el raíl) cambia el ancho del área de
  /// páginas y el `PageView` no reajusta su offset: se queda en blanco (entre
  /// dos páginas) hasta que se vuelve a tocar. `jumpToPage` no bastaba.
  ///
  /// Se recrea el `PageController` sembrado con la página actual: un
  /// controller nuevo calcula su offset contra el viewport nuevo y pinta la
  /// página correcta de inmediato. El viejo se tira tras el frame, cuando el
  /// PageView ya se ha desenganchado de él.
  void _keepPageOnResize(double pageAreaWidth) {
    final prev = _lastPageAreaWidth;
    _lastPageAreaWidth = pageAreaWidth;
    if (prev == null || (prev - pageAreaWidth).abs() < 1) return;

    final target = _pageController.hasClients
        ? (_pageController.page?.round() ?? _selectedIndex)
        : _selectedIndex;
    final old = _pageController;
    old.removeListener(_onPageScroll);
    _pageController = PageController(initialPage: target)
      ..addListener(_onPageScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _onNavItemTapped(int index) {
    if (index != _selectedIndex) {
      // La pastilla arranca YA hacia el destino (deslizamiento directo + ola).
      setState(() => _selectedIndex = index);
      _movePillTo(index);
    }
    _tapNavigating = true;
    _pageController
        .animateToPage(
          index,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _tapNavigating = false);
  }

  // Al arrastrar entre páginas, cuando el PageView se asienta en otra, la
  // pastilla viaja (con ola) a la nueva. Se ignora durante los toques.
  void _onPageSettled(int index) {
    if (_tapNavigating) return;
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
      _movePillTo(index);
    }
  }
  
  Rect _getPackZone(Size screenSize) {
    final packCenterX = screenSize.width / 2;
    final packCenterY = screenSize.height / 2 - 30;
    return Rect.fromCenter(
      center: Offset(packCenterX, packCenterY),
      width: 300,
      height: 400,
    );
  }

  /// Envolvente "ola" (0..1) mientras la pastilla viaja. Compartida por la
  /// barra inferior y el raíl lateral.
  double get _wave {
    if (_pillFrom == _pillTo) return 0.0;
    return math.sin(_pillCtrl.value * math.pi).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // Detectar si está en modo focus activo
    final isInFocusMode = context.watch<FocusProvider>().isInFocusMode;

    // Estilo de navegación elegido por el usuario (Perfil > Preferencias).
    // - clásica: raíl lateral en tablet horizontal, barra inferior en el resto.
    // - flotante: siempre el bocadillo flotante, también en tablet horizontal
    //   (el raíl se desactiva).
    final navStyle = context.watch<SettingsProvider>().navBarStyle;
    final wantsFloating = navStyle == NavBarStyle.floating;

    // Raíl lateral cuando la tablet está en horizontal, fuera del focus y con
    // el estilo clásico. Al girar a vertical se cae a la barra inferior.
    final useRail =
        !isInFocusMode && !wantsFloating && context.usesNavRail;
    final railWidth = useRail ? kNavRailWidth : 0.0;

    final floatingBar = !isInFocusMode && wantsFloating;

    final pageAreaWidth = screenSize.width - railWidth;
    _keepPageOnResize(pageAreaWidth);

    final showPackZoneBlocker = _isOnQuizPage && _isPackOpening;
    // La zona del sobre se centra en el ÁREA DE CONTENIDO (a la derecha del
    // raíl), no en la pantalla entera.
    final packZone = _getPackZone(
      Size(pageAreaWidth, screenSize.height),
    ).shift(Offset(railWidth, 0));

    final pageArea = _ZonedPageView(
      controller: _pageController,
      blockZone: showPackZoneBlocker ? packZone : null,
      allowImplicitScrolling: true,
      onPageChanged: _onPageSettled,
      children: _buildScreens(),
    );

    final Widget body = useRail
        ? Row(
            // stretch: el raíl se estira a todo el alto y su borde derecho
            // recorre el lateral entero (si no, quedaba un rectángulo
            // flotante centrado a media altura).
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_pillCtrl, _barEntry]),
                builder: (context, _) => NavRail(
                  items: _navItems,
                  selectedIndex: _selectedIndex,
                  pillPos: _pillPos,
                  wave: _wave,
                  entry: _barEntry.value,
                  onTap: _onNavItemTapped,
                ),
              ),
              Expanded(child: pageArea),
            ],
          )
        : pageArea;

    return Scaffold(
      body: floatingBar
          // La barra flotante va SOBRE el contenido (Stack), no en el slot
          // bottomNavigationBar: así el contenido pasa por detrás como en
          // Apple Music. Las pantallas ya reservan hueco abajo (~90-100).
          ? Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildFloatingBar(context),
                ),
              ],
            )
          : body,
      bottomNavigationBar: (isInFocusMode || useRail || floatingBar)
          ? null
          : _buildBottomBar(context),
    );
  }

  /// La "tira" de navegación: pastilla deslizante + iconos. Es idéntica en la
  /// barra clásica y en la flotante; solo cambia el contenedor.
  Widget _navStrip() {
    return AnimatedBuilder(
      animation: _pillCtrl,
      builder: (context, _) {
        final n = _navItems.length;
        final pos = _pillPos; // posición (en índices), con rebote
        // Envolvente "ola": 0 en reposo, sube a 1 a mitad de viaje y vuelve a
        // 0 al llegar. Hace crecer icono + pastilla + barra a la vez.
        final bool moving = _pillFrom != _pillTo;
        final double wave = moving
            ? math.sin(_pillCtrl.value * math.pi).clamp(0.0, 1.0)
            : 0.0;

        final double barHeight = 58 + 8 * wave;
        final double alignX = n == 1 ? 0 : (2 * pos / (n - 1) - 1);
        final double pillScale = 1 + 0.16 * wave;

        return SizedBox(
          height: barHeight,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment(alignX, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / n,
                  heightFactor: 1,
                  child: Transform.scale(
                    scale: pillScale,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary
                              .withOpacity(0.12 + 0.06 * wave),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(n, (index) {
                  final double sel =
                      (1 - (pos - index).abs()).clamp(0.0, 1.0);
                  return Expanded(
                    child: _NavItem(
                      item: _navItems[index],
                      selectedness: sel,
                      wave: wave * sel,
                      onTap: () => _onNavItemTapped(index),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Envuelve un hijo con la animación de entrada de la barra (slide + scale
  /// + fade), más marcada tras el onboarding.
  Widget _barEntrance({required Widget child}) {
    final curve = widget.justOnboarded
        ? Curves.easeOutBack
        : Curves.easeOutCubic;
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, widget.justOnboarded ? 1.6 : 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _barEntry, curve: curve)),
      child: ScaleTransition(
        scale: Tween<double>(begin: widget.justOnboarded ? 0.8 : 1.0, end: 1.0)
            .animate(CurvedAnimation(parent: _barEntry, curve: curve)),
        child: FadeTransition(opacity: _barEntry, child: child),
      ),
    );
  }

  /// Barra clásica: pegada al borde, de lado a lado, sombra arriba. En tablet
  /// vertical se acota y centra.
  Widget _buildBottomBar(BuildContext context) {
    Widget bar = _barEntrance(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: _navStrip(),
          ),
        ),
      ),
    );

    if (context.isWide) {
      bar = Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: bar,
        ),
      );
    }
    return bar;
  }

  /// Barra flotante estilo Apple Music: un bocadillo despegado del borde, con
  /// esquinas redondeadas y sombra a todo alrededor. El contenido pasa por
  /// detrás (va en un `Stack`, no en el slot `bottomNavigationBar`).
  Widget _buildFloatingBar(BuildContext context) {
    return _barEntrance(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: context.isWide ? 520 : double.infinity,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppColors.border, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondary.withOpacity(0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: _navStrip(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _NavItem extends StatelessWidget {
  final NavItem item;

  /// 0 = inactivo, 1 = seleccionado. Controla color y escala del icono.
  final double selectedness;

  /// Cresta de la "ola" que afecta a este item (0..1). Hace crecer el icono un
  /// extra mientras el destacador lo cruza. Se usa Transform.scale (neutro para
  /// el layout), así el crecimiento no descuadra la fila.
  final double wave;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.selectedness,
    required this.wave,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = Color.lerp(
      AppColors.navInactive,
      AppColors.primary,
      selectedness,
    )!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1.0 + (0.12 * selectedness) + (0.28 * wave),
            child: Icon(
              selectedness > 0.5 ? item.activeIcon : item.icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  selectedness > 0.5 ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// PageView personalizado que ignora gestos horizontales en una zona específica
class _ZonedPageView extends StatefulWidget {
  final PageController controller;
  final Rect? blockZone;
  final bool allowImplicitScrolling;
  final List<Widget> children;
  final ValueChanged<int>? onPageChanged;

  const _ZonedPageView({
    required this.controller,
    required this.blockZone,
    required this.allowImplicitScrolling,
    required this.children,
    this.onPageChanged,
  });

  @override
  State<_ZonedPageView> createState() => _ZonedPageViewState();
}

class _ZonedPageViewState extends State<_ZonedPageView> {
  Offset? _pointerDownPosition;
  bool _blockThisGesture = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerDownPosition = event.position;
        if (widget.blockZone != null && widget.blockZone!.contains(event.position)) {
          _blockThisGesture = true;
        } else {
          _blockThisGesture = false;
        }
        // Forzar rebuild para aplicar la nueva física
        setState(() {});
      },
      onPointerUp: (_) {
        _pointerDownPosition = null;
        _blockThisGesture = false;
      },
      onPointerCancel: (_) {
        _pointerDownPosition = null;
        _blockThisGesture = false;
      },
      child: PageView(
        controller: widget.controller,
        physics: _blockThisGesture
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        allowImplicitScrolling: widget.allowImplicitScrolling,
        onPageChanged: widget.onPageChanged,
        children: widget.children,
      ),
    );
  }
}
