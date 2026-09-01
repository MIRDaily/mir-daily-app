import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// Centra y acota el ancho del contenido de una pantalla.
///
/// En móvil (`compact`) es transparente: deja pasar el hijo tal cual, con el
/// mismo gutter de 20 de siempre. En tablet limita el ancho para que el texto
/// y las tarjetas no se estiren de borde a borde, y añade un gutter mayor.
///
/// Uso típico, envolviendo lo que antes tenía `padding: EdgeInsets.fromLTRB(
/// 20, top, 20, bottom)`:
/// ```dart
/// ListView(
///   children: [
///     ContentShell(child: ...),
///   ],
/// )
/// ```
/// o directamente como padre del `ListView`/`Column`.
class ContentShell extends StatelessWidget {
  const ContentShell({
    super.key,
    required this.child,
    this.wide = false,
    this.maxWidth,
    this.padTop = 0,
    this.padBottom = 0,
    this.applyGutter = true,
  });

  final Widget child;

  /// `true` para contenido en rejilla (galerías, paneles): permite un ancho
  /// mayor que el de lectura.
  final bool wide;

  /// Sobrescribe el ancho máximo calculado por el breakpoint.
  final double? maxWidth;

  final double padTop;
  final double padBottom;

  /// Añade el gutter horizontal del breakpoint. Desactívalo si el hijo ya
  /// gestiona su propio padding lateral.
  final bool applyGutter;

  @override
  Widget build(BuildContext context) {
    final gutter = applyGutter ? context.bodyGutter : 0.0;
    final limit = maxWidth ?? context.contentMaxWidth(wide: wide);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: limit),
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, padTop, gutter, padBottom),
          child: child,
        ),
      ),
    );
  }
}

/// Padding horizontal que centra un contenido de ancho `limit` dentro del
/// ancho de ventana actual, sin bajar nunca del gutter del breakpoint. Útil
/// para `SliverPadding` en los `CustomScrollView` que no se pueden envolver
/// enteros (galería de mazos, apuntes, simulacro).
EdgeInsets centeringGutter(BuildContext context, {bool wide = false, double? maxWidth}) {
  final gutter = context.bodyGutter;
  final limit = maxWidth ?? context.contentMaxWidth(wide: wide);
  if (limit == double.infinity) {
    return EdgeInsets.symmetric(horizontal: gutter);
  }
  final screen = MediaQuery.sizeOf(context).width;
  final side = ((screen - limit) / 2).clamp(gutter, double.infinity);
  return EdgeInsets.symmetric(horizontal: side);
}
