import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'breakpoints.dart';

/// Arrastre horizontal que SOLO reacciona hacia un lado. En cuanto el gesto
/// tira hacia el contrario cede el turno, para que un `PageView` de repaso o
/// unos chips horizontales del detalle sigan funcionando.
///
/// El detalle lo usa en las dos direcciones, nunca a la vez: con la lista
/// plegada escucha hacia la derecha (sacarla) y con la lista fuera escucha
/// hacia la izquierda (plegarla). Así en cada momento solo se le reserva el
/// sentido que ahí significa algo.
class _OneWayDragRecognizer extends HorizontalDragGestureRecognizer {
  _OneWayDragRecognizer({super.debugOwner});

  /// `1` para escuchar solo hacia la derecha, `-1` solo hacia la izquierda.
  ///
  /// No va en el constructor a propósito: `RawGestureDetector` crea el
  /// reconocedor UNA vez por tipo y luego solo vuelve a pasar por el
  /// inicializador, así que un campo de constructor se quedaría con el valor
  /// del primer build y el sentido no cambiaría nunca al plegar o desplegar.
  int sign = 1;

  bool _bailed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _bailed = false;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_bailed && event is PointerMoveEvent && event.delta.dx * sign < -2) {
      _bailed = true;
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      return;
    }
    if (_bailed) return;
    super.handleEvent(event);
  }
}

/// Layout de dos paneles para tablet grande (`context.usesTwoPane`): una
/// lista maestra a la izquierda —colapsable— y el detalle ocupando el resto.
///
/// La lista se pliega con el chevron de su cabecera, con el tirador "Lista"
/// cuando está plegada, o **deslizando a la izquierda desde cualquier punto de
/// la pantalla** — encima de la lista o del detalle, da igual. Sacarla es el
/// gesto simétrico: deslizar a la derecha desde donde sea. El detalle vive
/// siempre en el mismo `Expanded`, así que plegar no lo reconstruye y la
/// transición es fluida.
class MasterDetailScaffold extends StatefulWidget {
  const MasterDetailScaffold({
    super.key,
    required this.master,
    required this.detail,
    required this.masterCollapsed,
    required this.onToggleMaster,
    this.masterTitle,
    this.masterActions = const [],
    this.masterWidth = kMasterPaneWidth,
    this.onBack,
  });

  final Widget master;
  final Widget detail;

  final bool masterCollapsed;
  final VoidCallback onToggleMaster;

  final String? masterTitle;
  final List<Widget> masterActions;
  final double masterWidth;

  /// Si se pasa, la cabecera de la lista lleva una flecha "atrás" a su
  /// izquierda. Sirve para salir de la pantalla sin gastar una `AppBar`
  /// entera encima (en tablet ese hueco vacío se nota).
  final VoidCallback? onBack;

  @override
  State<MasterDetailScaffold> createState() => _MasterDetailScaffoldState();
}

class _MasterDetailScaffoldState extends State<MasterDetailScaffold>
    with SingleTickerProviderStateMixin {
  /// 0 = desplegada, 1 = plegada.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
    value: widget.masterCollapsed ? 1 : 0,
  );

  static const _curve = Curves.easeOutCubic;

  bool _dragging = false;

  @override
  void didUpdateWidget(MasterDetailScaffold old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.masterCollapsed != widget.masterCollapsed) {
      _c.animateTo(widget.masterCollapsed ? 1 : 0, curve: _curve);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _c.stop();
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Arrastrar a la izquierda (delta negativo) pliega.
    _c.value =
        (_c.value - (d.primaryDelta ?? 0) / widget.masterWidth).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    final v = d.primaryVelocity ?? 0;
    final bool collapse;
    if (v < -320) {
      collapse = true;
    } else if (v > 320) {
      collapse = false;
    } else {
      collapse = _c.value > 0.5;
    }
    // Si el resultado cambia el estado, se lo decimos al padre (que hará
    // animar desde didUpdateWidget). Si no, animamos aquí mismo.
    if (collapse != widget.masterCollapsed) {
      widget.onToggleMaster();
    } else {
      _c.animateTo(collapse ? 1 : 0, curve: _curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.masterWidth;
    final topPad = MediaQuery.paddingOf(context).top;

    final masterColumn = SizedBox(
      width: w,
      child: Column(
        children: [
          _MasterHeader(
            title: widget.masterTitle,
            actions: widget.masterActions,
            onBack: widget.onBack,
            onCollapse: () {
              if (!widget.masterCollapsed) widget.onToggleMaster();
            },
          ),
          Expanded(
            // El arrastre horizontal compite en la arena con el scroll
            // vertical de la lista: un gesto claramente horizontal gana aquí.
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: widget.master,
            ),
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRect(
                  child: SizedBox(
                    width: w * (1 - t),
                    child: OverflowBox(
                      alignment: Alignment.centerRight,
                      minWidth: w,
                      maxWidth: w,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: AppColors.hairline, width: 1),
                          ),
                        ),
                        child: masterColumn,
                      ),
                    ),
                  ),
                ),
                // El gesto va en los dos sentidos y desde cualquier punto del
                // detalle: plegada, un arrastre a la DERECHA la saca;
                // desplegada, uno a la IZQUIERDA la pliega. Antes solo existía
                // el primero, y para esconderla había que arrastrar encima de
                // la propia lista.
                //
                // No se usa el borde de la pantalla, que se lo queda el gesto
                // de "atrás" del sistema. Y en cada estado solo se escucha un
                // sentido, así que al detalle le queda libre el contrario para
                // lo suyo (PageView de repaso, chips horizontales).
                Expanded(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    gestures: <Type, GestureRecognizerFactory>{
                      _OneWayDragRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              _OneWayDragRecognizer>(
                        () => _OneWayDragRecognizer(debugOwner: this),
                        (r) => r
                          ..sign = widget.masterCollapsed ? 1 : -1
                          ..onStart = _onDragStart
                          ..onUpdate = _onDragUpdate
                          ..onEnd = _onDragEnd,
                      ),
                    },
                    child: widget.detail,
                  ),
                ),
              ],
            ),
            Positioned(
              top: topPad + 8,
              left: 8,
              child: IgnorePointer(
                ignoring: t < 0.6,
                child: Opacity(
                  opacity: (t * 1.6 - 0.6).clamp(0.0, 1.0),
                  child: FractionalTranslation(
                    translation: Offset(-1.2 * (1 - t), 0),
                    child: _ListHandle(
                      onTap: () {
                        if (widget.masterCollapsed) widget.onToggleMaster();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MasterHeader extends StatelessWidget {
  const _MasterHeader({
    required this.title,
    required this.actions,
    required this.onCollapse,
    this.onBack,
  });

  final String? title;
  final List<Widget> actions;
  final VoidCallback onCollapse;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 6,
        left: onBack != null ? 4 : 14,
        right: 4,
        bottom: 6,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Volver',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.textSecondary,
              onPressed: onBack,
            ),
          if (title != null)
            Expanded(
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            )
          else
            const Spacer(),
          ...actions,
          IconButton(
            tooltip: 'Ocultar la lista',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.textSecondary,
            onPressed: onCollapse,
          ),
        ],
      ),
    );
  }
}

/// Tirador que reaparece cuando la lista está plegada.
class _ListHandle extends StatelessWidget {
  const _ListHandle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_rounded, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Lista',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel derecho mientras no hay nada seleccionado en el maestro.
class MasterDetailEmpty extends StatelessWidget {
  const MasterDetailEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: AppColors.textLight),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textLight,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
