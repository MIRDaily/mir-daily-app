import 'package:flutter/widgets.dart';

/// Tamaños de ventana con los que la app decide su forma.
///
/// La app nació phone-first (una columna, barra inferior). Estas categorías
/// son lo que le permite crecer a tablet sin reescribir cada pantalla: el
/// contenido se acota, las listas pasan a rejilla y la navegación se va al
/// lateral cuando hay sitio.
enum WindowSize {
  /// Móvil (y tablet muy pequeña). Layout original, intacto.
  compact,

  /// Tablet en vertical / tablet pequeña.
  medium,

  /// Tablet en horizontal / tablet grande. Aquí caben dos paneles.
  expanded,
}

/// Umbrales en píxeles lógicos sobre el ANCHO de la ventana. Se mide el ancho
/// (no `shortestSide`) a propósito: así girar la tablet cambia de categoría y
/// la navegación se reacomoda, que es justo lo que se pidió.
const double kMediumMinWidth = 600;
const double kExpandedMinWidth = 1024;

/// Ancho de lectura cómodo para texto corrido y formularios.
const double kReadableMaxWidth = 720;

/// Ancho máximo para contenido en rejilla (galerías de tarjetas, paneles).
const double kWideContentMaxWidth = 1160;

/// Ancho del panel maestro en el layout de dos paneles.
const double kMasterPaneWidth = 380;

extension BreakpointX on BuildContext {
  Size get _win => MediaQuery.sizeOf(this);

  WindowSize get windowSize {
    final w = _win.width;
    if (w >= kExpandedMinWidth) return WindowSize.expanded;
    if (w >= kMediumMinWidth) return WindowSize.medium;
    return WindowSize.compact;
  }

  /// `true` en tablet (medium o expanded).
  bool get isWide => windowSize != WindowSize.compact;

  /// Raíl lateral cuando hay ancho de sobra Y la ventana está apaisada.
  /// Al girar la tablet a vertical, vuelve la barra inferior con los mismos
  /// iconos. En móvil (bloqueado a vertical) siempre es `false`.
  bool get usesNavRail {
    final s = _win;
    return s.width >= kMediumMinWidth && s.width > s.height;
  }

  /// Raíl extendido (icono + etiqueta) frente a raíl compacto (solo icono).
  bool get usesExtendedNavRail => _win.width >= kExpandedMinWidth;

  /// Dos paneles (maestro-detalle) en vez de navegación por push.
  bool get usesTwoPane => _win.width >= kExpandedMinWidth;

  /// Ancho máximo recomendado para el cuerpo de una pantalla normal.
  /// En rejilla conviene pasar `wide: true`.
  double contentMaxWidth({bool wide = false}) {
    switch (windowSize) {
      case WindowSize.compact:
        return double.infinity;
      case WindowSize.medium:
        return wide ? 900 : 820;
      case WindowSize.expanded:
        // Con el raíl a la izquierda, un ancho de lectura corto deja el
        // contenido descolgado hacia la derecha; se da algo más de aire.
        return wide ? kWideContentMaxWidth : 880;
    }
  }

  /// Padding horizontal del cuerpo según el tamaño de ventana. El compacto
  /// mantiene los 20 de siempre.
  double get bodyGutter {
    switch (windowSize) {
      case WindowSize.compact:
        return 20;
      case WindowSize.medium:
        return 28;
      case WindowSize.expanded:
        return 40;
    }
  }
}
