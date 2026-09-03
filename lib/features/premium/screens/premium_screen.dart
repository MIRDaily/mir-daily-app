import 'package:flutter/material.dart';

import '../../../core/responsive/adaptive_grid.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/content_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/widgets/misc_widgets.dart';
import '../widgets/panel_section.dart';
import '../widgets/premium_showcase.dart';

/// Pestaña Premium: el escaparate de lo que viene (que todavía no se puede
/// comprar) y, debajo, el Panel con la analítica real del usuario.
///
/// Mantiene las mismas piezas de siempre —medallón, "Próximamente", la
/// descripción, las tres ventajas, el aviso de lanzamiento y el Panel— pero
/// pintadas con el lenguaje de pegatina del resto de la app y con la entrada
/// escalonada de las demás pestañas. Sin `AppBar`, como las otras cuatro: el
/// título vive dentro del propio contenido.
///
/// En tablet las ventajas pasan a rejilla y el cuerpo se acota y centra, en
/// vez de estirar una columna con 20 px de gutter a lo ancho de la pantalla.
class PremiumScreen extends StatefulWidget {
  /// `false` mientras la pestaña está montada pero nunca se ha visto (el
  /// `PageView` construye las vecinas). El panel espera a que sea `true` para
  /// pedir nada: si no, la analítica se descargaba en cada arranque de la app
  /// aunque el usuario no entrara aquí.
  final bool isVisible;

  const PremiumScreen({super.key, this.isVisible = true});

  static const String _description =
      'Acceso ilimitado a todas las preguntas MIR, estadísticas avanzadas y '
      'mucho más.';

  static const List<_Feature> _features = [
    _Feature(
      title: 'Preguntas ilimitadas',
      description: 'Accede a todo el banco de preguntas',
      tag: 'Sin límite',
      accent: AppColors.primary,
      art: _Art.infinity,
    ),
    _Feature(
      title: 'Estadísticas avanzadas',
      description: 'Análisis detallado por especialidad',
      tag: 'Datos',
      accent: AppColors.secondary,
      art: _Art.bars,
    ),
    _Feature(
      title: 'Simulacros de examen',
      description: 'Practica en condiciones reales',
      tag: 'Examen',
      accent: AppColors.successDark,
      art: _Art.timer,
    ),
  ];

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  /// Para medir cuánto ocupa el escaparate y saber cuándo se ha ido del todo
  /// por arriba.
  final GlobalKey _headerKey = GlobalKey();

  /// `false` cuando el escaparate ya no está en pantalla. Es un
  /// `ValueNotifier` y no un `setState` a propósito: mover esto no debe
  /// reconstruir el panel entero que va debajo.
  final ValueNotifier<bool> _headerLive = ValueNotifier(true);

  double? _headerExtent;

  @override
  void dispose() {
    _headerLive.dispose();
    super.dispose();
  }

  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _headerExtent = box.size.height;
  }

  bool _onScroll(ScrollNotification n) {
    // `depth != 0` son los scrolls anidados (el de los filtros del mapa de
    // calor, que es horizontal); ese no dice nada de dónde está la cabecera.
    if (n.depth != 0) return false;
    final extent = _headerExtent;
    if (extent == null) return false;
    final live = n.metrics.pixels < extent;
    if (live != _headerLive.value) _headerLive.value = live;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    // El escaparate entero, agrupado para poder medirlo y silenciarlo de una
    // pieza.
    final header = Column(
      key: _headerKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SlideFadeIn(
          beginOffset: Offset(0, 0.12),
          child: PremiumHeroCard(
            badge: 'Premium',
            title: 'Próximamente',
            description: PremiumScreen._description,
          ),
        ),
        const SizedBox(height: 28),

        const SectionLabel('Qué incluye'),
        const SizedBox(height: 14),
        AdaptiveGrid(
          // 360 por tarjeta: dos columnas en tablet vertical y tres en
          // horizontal; una sola en móvil, donde `AdaptiveGrid` se comporta
          // exactamente como la columna de antes.
          targetItemWidth: 360,
          maxColumns: 3,
          children: [
            for (var i = 0; i < PremiumScreen._features.length; i++)
              SlideFadeIn(
                delay: Duration(milliseconds: 150 + i * 70),
                beginOffset: const Offset(0, 0.12),
                child: PremiumScreen._features[i].card(),
              ),
          ],
        ),
        const SizedBox(height: 20),

        const SlideFadeIn(
          delay: Duration(milliseconds: 380),
          beginOffset: Offset(0, 0.12),
          child: PremiumNoticeCard(
            message: 'Te avisaremos cuando esté disponible',
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            // El gutter centra el cuerpo en tablet y deja los 20 de siempre en
            // móvil. Los 100 de abajo son el hueco de la barra flotante.
            padding: centeringGutter(context, wide: true)
                .add(EdgeInsets.fromLTRB(0, wide ? 28 : 20, 0, 100)),
            children: [
              // El escaparate tiene ocho animaciones en bucle (los rayos del
              // medallón, su halo, las tres chispas, el barrido de brillo, las
              // tres ilustraciones y la campana). Medido en la tablet: con la
              // página quieta y la cabecera FUERA de pantalla se seguían
              // pintando 124 fotogramas por segundo, a 6,4 ms de trabajo cada
              // uno. `TickerMode` silencia los tickers de todo el subárbol, así
              // que al bajar al panel la página deja de repintarse del todo.
              ValueListenableBuilder<bool>(
                valueListenable: _headerLive,
                builder: (context, live, child) =>
                    TickerMode(enabled: live, child: child!),
                child: header,
              ),

              const SizedBox(height: 36),
              // Contenido del "Panel" web: analítica de rendimiento con datos
              // reales (progreso global, esfuerzo, mapa de calor y puntos
              // débiles), debajo del contenido Premium existente. No se monta
              // hasta que la pestaña se ve: es quien pide los datos.
              if (widget.isVisible) const PanelSection(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Art { infinity, bars, timer }

/// Los datos de una ventaja. Se guardan como dato y no como widget para que la
/// lista pueda ser `const`.
class _Feature {
  final String title;
  final String description;
  final String tag;
  final Color accent;
  final _Art art;

  const _Feature({
    required this.title,
    required this.description,
    required this.tag,
    required this.accent,
    required this.art,
  });

  Widget card() => PremiumFeatureCard(
        title: title,
        description: description,
        tag: tag,
        accent: accent,
        art: switch (art) {
          _Art.infinity => InfinityArt(accent: accent),
          _Art.bars => BarsArt(accent: accent),
          _Art.timer => TimerArt(accent: accent),
        },
      );
}
