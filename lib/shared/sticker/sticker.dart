/* ════════════════════════════════════════════════════════════════════════
   Primitivas del lenguaje visual de MIRDaily, portadas desde la web
   (`src/components/ui/sticker.tsx`): borde de tinta, sombra dura y
   tipografía de marca.

   Nacieron en la Academia de Electros y las comparten flashcards, el creador
   de simulacros y el perfil, para no acabar con tres copias del mismo botón.
   Los valores son los mismos que en la web a propósito: si allí cambia el
   grosor del trazo o el coral, aquí también, y así las dos superficies siguen
   pareciendo el mismo producto.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Trazo de tinta: casi negro, nunca gris suave. Es la firma del sistema.
const Color kInk = Color(0xFF2C3E50);

/// Coral de marca (el del chrome de la app, no el de la landing).
const Color kAccent = Color(0xFFE8A598);

/// Gris azulado de los textos secundarios.
const Color kMuted = Color(0xFF7D8A96);

/// Borde suave para lo que no lleva trazo de tinta (fichas, campos en reposo).
const Color kHairline = Color(0xFFEAE4E2);

/// Curva de salida de la web (`cubic-bezier(0.22, 1, 0.36, 1)`): arranca
/// rápido y llega suave. Es la que usan todas las entradas de pantalla.
const Cubic kEaseOut = Cubic(0.22, 1, 0.36, 1);

/// Sombra dura desplazada: el `Npx Npx 0 0` de la web. Sin desenfoque, que es
/// justo lo que da el efecto de pegatina recortada.
///
/// **El relleno de la caja tiene que ser OPACO.** Flutter pinta la sombra
/// detrás de la caja, así que un relleno con alpha la deja pasar y la tarjeta
/// entera se ve del color de la sombra —azul marino— en vez del pastel que se
/// pretendía. Para teñir un fondo, [tinted] en vez de `withOpacity`.
List<BoxShadow> inkShadow([double depth = 5, Color color = kInk]) => [
      BoxShadow(color: color, offset: Offset(depth, depth), blurRadius: 0),
    ];

/// Tinte OPACO: [color] mezclado con blanco en la proporción [amount].
///
/// Se ve igual que `color.withOpacity(amount)` sobre fondo blanco, pero sin
/// dejar pasar lo que haya detrás. Es lo que hay que usar en cualquier caja
/// que lleve [inkShadow].
Color tinted(Color color, double amount) =>
    Color.alphaBlend(color.withOpacity(amount), Colors.white);

/// Tarjeta con borde de tinta y sombra dura. El equivalente de `StickerCard`.
///
/// Si lleva [onTap] se comporta como un botón: al tocarla se hunde los mismos
/// píxeles que mide su sombra, así que parece que se aplasta contra el papel.
/// Es el mismo gesto del [StickerButton], y aprovecha la profundidad que ya
/// da la sombra en vez de añadir un destello encima.
class StickerCard extends StatefulWidget {
  final Widget child;
  final double depth;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color background;

  /// Decoración de textura opcional (papel rayado, guilloche…). Si se pasa,
  /// pinta por debajo del contenido y respeta el radio de la tarjeta.
  final Decoration? texture;
  final VoidCallback? onTap;

  /// Cuánto tiempo se queda hundida como MÍNIMO antes de ejecutar [onTap].
  ///
  /// No es un retardo a secas: es una garantía de que el gesto se ve. Dentro de
  /// un scrollable, el reconocedor de toque compite con el de arrastre y no
  /// avisa del `onTapDown` hasta que gana la puja, que en un toque corto es al
  /// levantar el dedo — así que el hundimiento y la vuelta caían en el mismo
  /// fotograma y no se pintaba nunca.
  ///
  /// Por defecto cero: en una lista larga, retener cada toque se siente lento.
  /// Lo piden las tarjetas que abren una sección.
  final Duration pressDelay;

  /// Recorte del contenido. Por defecto **no** se recorta: recortar contra el
  /// radio exterior hacía que el hijo pintara por encima de la mitad interior
  /// del trazo y las esquinas se quedaran sin línea. Solo lo piden las
  /// tarjetas cuyo contenido se sale de verdad (una imagen a sangre).
  final Clip clipBehavior;

  /// Margen exterior. Lo lleva la propia tarjeta para no tener que envolver
  /// cada una en un `Padding` al pintarlas en lista.
  final EdgeInsetsGeometry? margin;

  const StickerCard({
    super.key,
    required this.child,
    this.depth = 5,
    this.radius = 24,
    this.padding,
    this.background = Colors.white,
    this.texture,
    this.onTap,
    this.margin,
    this.pressDelay = Duration.zero,
    this.clipBehavior = Clip.none,
  });

  @override
  State<StickerCard> createState() => _StickerCardState();
}

class _StickerCardState extends State<StickerCard> {
  bool _down = false;

  /// Cuándo se hundió, para saber cuánto lleva ya a la vista.
  Duration? _downAt;

  Duration get _now => Duration(
        milliseconds: DateTime.now().millisecondsSinceEpoch,
      );

  void _press() {
    if (widget.onTap == null || _down) return;
    _downAt = _now;
    setState(() => _down = true);
  }

  void _release() {
    if (!_down) return;
    setState(() => _down = false);
  }

  Future<void> _handleTap() async {
    final action = widget.onTap;
    if (action == null) return;

    if (widget.pressDelay > Duration.zero) {
      // El `onTapDown` puede no haber llegado todavía (ver [pressDelay]), así
      // que aquí se fuerza el hundimiento y se sostiene lo que falte para que
      // dé tiempo a pintarlo.
      _press();
      final visto = _now - (_downAt ?? _now);
      final falta = widget.pressDelay - visto;
      if (falta > Duration.zero) {
        await Future<void>.delayed(falta);
        if (!mounted) return;
      }
    }

    _release();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(widget.radius);
    final pressable = widget.onTap != null;
    final sunk = _down && pressable;

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      // Viaja justo hasta donde estaba su sombra.
      transform: Matrix4.translationValues(
        sunk ? widget.depth : 0,
        sunk ? widget.depth : 0,
        0,
      ),
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: border,
        border: Border.all(color: kInk, width: 2),
        boxShadow: sunk ? const [] : inkShadow(widget.depth),
      ),
      clipBehavior: widget.clipBehavior,
      child: Stack(
        // `passthrough`: el contenido recibe las MISMAS restricciones que la
        // tarjeta. Por defecto un Stack las afloja, así que un hijo centrado
        // se encogía a su texto más ancho y quedaba pegado arriba a la
        // izquierda — que es como se descentraron las tarjetas de racha.
        fit: StackFit.passthrough,
        children: [
          if (widget.texture != null)
            Positioned.fill(
              // El `Container` ya mete al hijo 2 px hacia dentro (el grosor
              // del borde), así que la textura se recorta contra el radio
              // INTERIOR. Con el radio exterior se comía la curva del trazo y
              // las esquinas salían sin línea.
              //
              // El límite de repintado es lo que hace que la trama se rasterice
              // una vez y no en cada fotograma: sin él, cualquier animación de
              // al lado —o un simple scroll— obliga a repintar las decenas de
              // líneas de la textura.
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(math.max(0, widget.radius - 2)),
                  child: DecoratedBox(decoration: widget.texture!),
                ),
              ),
            ),
          Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.child,
          ),
        ],
      ),
    );

    if (widget.margin != null) {
      content = Padding(padding: widget.margin!, child: content);
    }

    if (!pressable) return content;

    return GestureDetector(
      onTapDown: (_) => _press(),
      // `onTapUp` NO suelta: en un toque corto levantaría la tarjeta antes de
      // que se hubiera llegado a ver hundida. Suelta `_handleTap`, que corre
      // justo después. `onTapCancel` sí, porque ahí gana el scroll y no habrá
      // `onTap` que lo haga.
      onTapCancel: _release,
      onTap: _handleTap,
      // La zona de toque es todo el rectángulo, también donde no hay pintura.
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

/// Cabecera de pantalla: distintivo, título grande, subtítulo y acciones.
///
/// A diferencia del `Hero` de la web, aquí va **sin caja**: en una pantalla de
/// móvil, donde todo lo de debajo son tarjetas con trazo, meter el título en
/// otra tarjeta lo convertía en un botón más y se perdía la jerarquía. Se
/// queda el distintivo, el titular grande y la entrada; se va el marco.
class StickerHero extends StatefulWidget {
  /// Opcional: si la pantalla ya se explica sola, el distintivo sobra.
  final String? badge;
  final IconData? badgeIcon;
  final String title;
  final String? subtitle;
  final Color accent;
  final List<Widget> actions;
  final Widget? aside;
  final Widget? child;

  const StickerHero({
    super.key,
    this.badge,
    this.badgeIcon,
    required this.title,
    this.subtitle,
    this.accent = kAccent,
    this.actions = const [],
    this.aside,
    this.child,
  });

  @override
  State<StickerHero> createState() => _StickerHeroState();
}

class _StickerHeroState extends State<StickerHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  // La curva se crea UNA vez. Antes salía una `CurvedAnimation` nueva en cada
  // build, que además hay que desechar a mano.
  late final CurvedAnimation _curved =
      CurvedAnimation(parent: _ctrl, curve: kEaseOut);

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.35),
    end: Offset.zero,
  ).animate(_curved);

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _curved.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fade + slide con transiciones nativas: se resuelven en la capa de
    // composición y no reconstruyen el subárbol en cada fotograma, que es lo
    // que hacía el AnimatedBuilder anterior.
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
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
                        if (widget.badge != null) ...[
                          _HeroBadge(
                            text: widget.badge!,
                            icon: widget.badgeIcon,
                            accent: widget.accent,
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: kInk,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.subtitle!,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.45,
                              fontWeight: FontWeight.w400,
                              color: kMuted,
                            ),
                          ),
                        ],
                        if (widget.child != null) widget.child!,
                      ],
                    ),
                  ),
                  if (widget.aside != null) ...[
                    const SizedBox(width: 12),
                    widget.aside!,
                  ],
                ],
              ),
              if (widget.actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color accent;

  const _HeroBadge({required this.text, this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        // El `${accent}26` de la web: el mismo coral al 15 %.
        color: accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón sólido con borde de tinta. En la web se levanta medio píxel en hover;
/// aquí, que no hay puntero, se hunde contra su sombra al pulsarlo.
class StickerButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final bool expand;
  final bool compact;

  const StickerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color = kAccent,
    this.icon,
    this.expand = false,
    this.compact = false,
  });

  @override
  State<StickerButton> createState() => _StickerButtonState();
}

class _StickerButtonState extends State<StickerButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    // Al pulsar, el botón viaja hasta donde estaba su sombra: el gesto se lee
    // como si la pegatina se aplastara contra el papel.
    const depth = 4.0;
    final sunk = _down && enabled;

    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(sunk ? depth : 0, sunk ? depth : 0, 0),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 14 : 20,
          vertical: widget.compact ? 9 : 13,
        ),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kInk, width: 2),
          boxShadow: sunk ? const [] : inkShadow(depth),
        ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.compact ? 13 : 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: button,
    );
  }
}

/// Botón secundario: mismo peso tipográfico, sin relleno ni sombra.
class GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool compact;

  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.compact = false,
  });

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    // Sin sombra que aplastar, el estado pulsado se marca oscureciendo el
    // trazo: es el mismo `hover:border-[#2c3e50]` de la web.
    final active = _down && enabled;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 14 : 20,
            vertical: widget.compact ? 9 : 13,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? kInk : kHairline, width: 2),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: active ? kInk : kMuted),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.compact ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    color: active ? kInk : kMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rótulo de sección con línea que se come el hueco sobrante.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              color: kMuted.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: const Color(0xFFE6DEDA))),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// Cifra con etiqueta, para los resúmenes de portada.
class StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const StatChip({
    super.key,
    required this.value,
    required this.label,
    this.color = kAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: kMuted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Distintivo numerado de paso, para los formularios por pasos.
class StepBadge extends StatelessWidget {
  final int n;
  final bool active;
  final Color color;

  const StepBadge({
    super.key,
    required this.n,
    this.active = false,
    this.color = kAccent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 32,
      width: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? color : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(2),
      ),
      child: Text(
        '$n',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: active ? Colors.white : kInk,
        ),
      ),
    );
  }
}

/// Pastilla con icono, para estados y metadatos.
enum DocTone { neutral, accent, success, error, ink }

class DocChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final DocTone tone;

  const DocChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = DocTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    late final Color bg, fg, border;
    switch (tone) {
      case DocTone.neutral:
        bg = Colors.white;
        fg = kMuted;
        border = kHairline;
        break;
      case DocTone.accent:
        bg = const Color(0xFFFFF4EF);
        fg = const Color(0xFFB9705F);
        border = const Color(0xFFF1D3C9);
        break;
      case DocTone.success:
        bg = const Color(0xFFEAF2E8);
        fg = const Color(0xFF5F7E5C);
        border = const Color(0xFFCFE0CC);
        break;
      case DocTone.error:
        bg = const Color(0xFFFBEAE4);
        fg = const Color(0xFFC4655A);
        border = const Color(0xFFF0D2CC);
        break;
      case DocTone.ink:
        bg = kInk;
        fg = Colors.white;
        border = kInk;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          // Flexible: con una etiqueta larga ("Universidad de Granada") dentro
          // de un hueco estrecho, un Text suelto desborda y Flutter pinta las
          // rayas de aviso en vez de recortar.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interruptor con borde de tinta, para las preferencias.
class InkSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const InkSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32,
        width: 56,
        padding: const EdgeInsets.all(2),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? kAccent : const Color(0xFFEFEAE7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kInk, width: 2),
        ),
        child: Container(
          height: 22,
          width: 22,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: kInk, width: 2),
          ),
        ),
      ),
    );
  }
}

/// Campo de texto con el mismo trazo que el resto del sistema.
class InkInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final String? prefix;
  final int? maxLength;
  final bool enabled;
  final bool invalid;
  final bool autofocus;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const InkInput({
    super.key,
    required this.controller,
    this.hint,
    this.prefix,
    this.maxLength,
    this.enabled = true,
    this.invalid = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: invalid ? const Color(0xFFE6B0A6) : kHairline,
            width: 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (prefix != null)
              Text(
                prefix!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: kMuted,
                ),
              ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                autofocus: autofocus,
                maxLines: maxLines,
                maxLength: maxLength,
                textInputAction: textInputAction,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  // El contador de caracteres lo pone quien lo necesite, que
                  // en la web es un componente aparte (`CharCounter`).
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFB9B2AD),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rótulo diminuto arriba y valor debajo, como los campos de un carné.
class InkField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const InkField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accent = kAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: kMuted.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: kInk,
          ),
        ),
      ],
    );
  }
}

/// Botón de icono con trazo de tinta, para las acciones sueltas de cabecera.
class InkIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color color;
  final double size;

  const InkIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.color = Colors.white,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        height: size,
        width: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(3),
        ),
        child: Icon(icon, size: size * 0.45, color: kInk),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Pulgar del deslizador con el trazo del sistema: círculo blanco con borde de
/// tinta y su sombra dura, como todo lo que se agarra en esta interfaz.
class InkThumb extends SliderComponentShape {
  final double radius;

  const InkThumb({this.radius = 13});

  @override
  Size getPreferredSize(bool enabled, bool discrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    // La sombra va hacia el mismo sitio que la del resto del sistema.
    canvas.drawCircle(
      center.translate(2, 2),
      radius,
      Paint()..color = kInk,
    );
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kInk,
    );
  }
}

/// Carril del deslizador con borde de tinta, para que no parezca de Material.
class InkTrackShape extends RoundedRectSliderTrackShape {
  const InkTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      // Sin engorde del tramo activo: aquí el grosor lo fija el tema.
      additionalActiveTrackHeight: 0,
    );

    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kInk,
    );
  }
}
