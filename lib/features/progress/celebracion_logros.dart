/* ════════════════════════════════════════════════════════════════════════
   La celebración de metas cumplidas.

   Se monta por encima de TODA la app (ver `main.dart`), y tres reglas la
   gobiernan:

   1. NUNCA APARECE POR SU CUENTA. Solo se pinta cuando alguien ha dado permiso
      explícito (`permitirCelebracion`), y el permiso solo se concede al
      TERMINAR una actividad: la pantalla de resultados del Daily, el final de
      un simulacro, el cierre de una sesión de mazo. Nunca durante una
      pregunta: interrumpir a alguien en mitad de un caso clínico para decirle
      que ha subido de nivel rompe justo la concentración que el producto
      existe para proteger.

   2. UNA tarjeta, no una cadena de modales. Si se han cumplido varias metas
      gordas a la vez, manda la más importante y las demás van resumidas
      debajo.

   3. NO TODO PESA IGUAL. Un desafío completado sale como aviso deslizante y se
      va solo; solo rango, nivel y hitos de racha se quedan esperando un gesto.
      Y cuando coinciden se turnan EN EL TIEMPO, no en la pantalla: primero la
      tarjeta, sola y limpia, y al cerrarla salen los avisos.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/logros.dart';
import '../../core/providers/progress_provider.dart';
import '../../core/theme/levels.dart';
import '../../shared/sticker/sticker.dart';
import 'widgets/avisos_desafio.dart';
import 'widgets/llama_racha.dart';
import 'widgets/subida_de_nivel.dart';
import 'widgets/tarjeta_nivel.dart' show miles;

class CelebracionLogros extends StatelessWidget {
  const CelebracionLogros({super.key});

  @override
  Widget build(BuildContext context) {
    final progreso = context.watch<ProgressProvider>();
    // Nada que celebrar (o sin permiso): un hueco que no pinta ni intercepta
    // el dedo. Se monta siempre para no depender de quién esté en pantalla.
    if (!progreso.celebracionLista) {
      return const IgnorePointer(child: SizedBox.shrink());
    }

    final ordenados = ordenarPorPeso(progreso.logros);
    final mayores =
        ordenados.where((l) => l.tipo != TipoLogro.desafio).toList();
    final desafios =
        ordenados.where((l) => l.tipo == TipoLogro.desafio).toList();

    // Los avisos solo salen cuando NO hay una meta gorda esperando: es el
    // relevo del punto 3 de la cabecera.
    if (mayores.isEmpty) {
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            AvisosDesafio(
              desafios: desafios,
              onDescartar: progreso.descartarLogro,
            ),
          ],
        ),
      );
    }

    final principal = mayores.first;
    // Solo se resumen OTRAS metas gordas (lo normal: un hito de racha el mismo
    // día que se sube de nivel). Los desafíos no entran aquí: tienen su propio
    // turno cuando esta tarjeta se cierre.
    final resto = mayores.skip(1).toList();

    final p = progreso.progress;
    final pie = p == null
        ? null
        : '${rankForLevel(p.level).name} · ${miles(p.xpTotal)} XP en total';

    return _TarjetaMeta(
      // La clave hace que el estado interno —si el titular ya se ha
      // destapado— se reinicie solo cuando cambia la meta que se celebra. Sin
      // ella, la segunda tarjeta de una tanda saldría con el titular ya
      // descubierto.
      key: ValueKey(principal.id),
      logro: principal,
      resto: resto,
      pie: pie,
      // Cerrar se lleva las metas gordas y SOLO esas. Si quedaban desafíos, el
      // permiso sigue vivo y salen a continuación como avisos.
      onCerrar: () =>
          progreso.descartarLogros([for (final m in mayores) m.id]),
    );
  }
}

class _Titular {
  final String kicker;
  final String titulo;
  final String sub;
  final Color color;

  const _Titular(this.kicker, this.titulo, this.sub, this.color);

  factory _Titular.de(Logro l) {
    switch (l.tipo) {
      case TipoLogro.rango:
        return _Titular(
          'Nuevo rango',
          l.rango ?? rankForLevel(l.nivel).name,
          'Has llegado al nivel ${l.nivel}.',
          rankForLevel(l.nivel).color,
        );
      case TipoLogro.nivel:
        return _Titular(
          'Has subido',
          'Nivel ${l.nivel}',
          'Un peldaño más.',
          rankForLevel(l.nivel).color,
        );
      case TipoLogro.racha:
        return _Titular(
          'Racha',
          '${l.dias} días seguidos',
          'Sin fallar un solo día.',
          const Color(0xFFEA8600),
        );
      case TipoLogro.desafio:
        return _Titular(
          l.scope == 'weekly' ? 'Desafío semanal' : 'Desafío del día',
          l.titulo ?? '',
          '+${miles(l.xp)} XP',
          const Color(0xFF8BA888),
        );
    }
  }
}

String _resumenDe(Logro l) {
  switch (l.tipo) {
    case TipoLogro.rango:
      return 'Nuevo rango: ${l.rango}';
    case TipoLogro.nivel:
      return 'Nivel ${l.nivel}';
    case TipoLogro.racha:
      return '${l.dias} días de racha';
    case TipoLogro.desafio:
      return '${l.titulo} · +${miles(l.xp)} XP';
  }
}

class _TarjetaMeta extends StatefulWidget {
  final Logro logro;
  final List<Logro> resto;

  /// Estado en el que queda el usuario, ya formateado.
  final String? pie;

  final VoidCallback onCerrar;

  const _TarjetaMeta({
    super.key,
    required this.logro,
    required this.resto,
    required this.pie,
    required this.onCerrar,
  });

  @override
  State<_TarjetaMeta> createState() => _TarjetaMetaState();
}

class _TarjetaMetaState extends State<_TarjetaMeta>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entrada;

  /// El titular se guarda hasta que la barra cruza de verdad. Enseñar "Nivel
  /// 12" mientras la barra todavía va por el 11 destripa el momento: el número
  /// tiene que llegar DESPUÉS del esfuerzo, no antes.
  bool _revelado = false;

  bool _listo = false;
  bool _sinAnimacion = false;

  /// Ya se está yendo: evita que un segundo toque relance la salida.
  bool _cerrando = false;

  @override
  void initState() {
    super.initState();
    _entrada = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      // La salida es más corta que la entrada: entrar es un acontecimiento,
      // salir es quitarse de en medio.
      reverseDuration: const Duration(milliseconds: 240),
    );
    _revelado = !widget.logro.esSalto;
    WidgetsBinding.instance.addObserver(this);
  }

  /// El botón "atrás" de Android cierra la tarjeta, como cualquier diálogo.
  ///
  /// Hace falta el observador porque esta capa vive POR ENCIMA del Navigator
  /// —una meta se puede cumplir en cualquier pantalla— y ahí un `PopScope` no
  /// se entera de nada: sin esto, el atrás desharía la navegación de debajo y
  /// dejaría la tarjeta flotando sobre otra pantalla. Los observadores se
  /// consultan en orden inverso al de registro, así que este, montado después
  /// de la app, se lleva la pulsación antes que el Navigator.
  @override
  Future<bool> didPopRoute() async {
    _cerrar();
    return true;
  }

  /// Cierra ANIMANDO la salida.
  ///
  /// La clave es el orden: primero se reproduce la salida y solo al terminar
  /// se avisa al provider. Al revés —que es como estaba— el provider vacía la
  /// cola, esta tarjeta deja de existir en el mismo fotograma y desaparece de
  /// golpe: un widget desmontado no puede animar su propia salida. Es el mismo
  /// fallo que la web tuvo con `AnimatePresence`.
  void _cerrar() {
    if (_cerrando) return;
    _cerrando = true;

    if (_sinAnimacion) {
      widget.onCerrar();
      return;
    }
    _entrada.reverse().whenComplete(() {
      if (mounted) widget.onCerrar();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listo) return;
    _listo = true;

    _sinAnimacion = MediaQuery.disableAnimationsOf(context);
    if (_sinAnimacion) {
      _entrada.value = 1;
      _revelado = true;
      return;
    }
    _entrada.forward();

    // Red de seguridad: si por lo que sea no llegara a cruzarse ningún peldaño
    // (un tramo raro, una referencia vieja), el titular no se queda escondido.
    if (!_revelado) {
      Future<void>.delayed(const Duration(milliseconds: 3600), () {
        if (mounted && !_revelado) setState(() => _revelado = true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.logro;
    final t = _Titular.de(l);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // El fondo atenuado también cierra, como cualquier diálogo.
          Positioned.fill(
            child: GestureDetector(
              onTap: _cerrar,
              child: AnimatedBuilder(
                animation: _entrada,
                builder: (context, _) => ColoredBox(
                  color: kInk.withValues(alpha: 0.35 * _entrada.value),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: AnimatedBuilder(
                animation: _entrada,
                builder: (context, hijo) {
                  final t = _entrada.value.clamp(0.0, 1.0);
                  // Al salir NO se reproduce la entrada al revés: el rebote de
                  // `easeOutBack` marcha atrás se lee como un tirón. Sale
                  // encogiéndose un poco y desvaneciéndose, que es lo que hace
                  // la web.
                  if (_cerrando) {
                    final v = Curves.easeIn.transform(t);
                    return Opacity(
                      opacity: v,
                      child: Transform.scale(scale: 0.95 + 0.05 * v, child: hijo),
                    );
                  }
                  final v = Curves.easeOutBack.transform(t);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - v)),
                      child: Transform.scale(scale: 0.9 + 0.1 * v, child: hijo),
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: StickerCard(
                    depth: 6,
                    radius: 26,
                    padding: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // El confeti que cae desde arriba se queda para la
                        // racha, que no tiene barra con la que interactuar. En
                        // un salto de nivel manda otra cosa: las chispas salen
                        // de la propia barra al llenarse y rebotan en ella.
                        // Papelitos cayendo por delante de eso solo restarían.
                        if (!_sinAnimacion && !l.esSalto)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: 190,
                            child: _Confeti(color: t.color),
                          ),
                        _contenido(l, t),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido(Logro l, _Titular t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (l.esSalto)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 256),
                child: SubidaDeNivel(
                  xpAntes: l.xpAntes,
                  xpDespues: l.xpDespues,
                  onNivelNuevo: (_) {
                    if (mounted && !_revelado) {
                      setState(() => _revelado = true);
                    }
                  },
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: LlamaRacha(racha: l.dias, size: 78),
            ),

          AnimatedOpacity(
            opacity: _revelado ? 1 : 0,
            duration: _sinAnimacion
                ? Duration.zero
                : const Duration(milliseconds: 320),
            curve: kEaseOut,
            child: Column(
              children: [
                Text(
                  t.kicker.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.7,
                    color: t.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: kMuted),
                ),
              ],
            ),
          ),

          if (widget.resto.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF9F8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Y ADEMÁS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: kMuted.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final r in widget.resto)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: Color(0xFF8BA888),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _resumenDe(r),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          // El estado en el que queda, para que la celebración informe y no
          // solo aplauda. En un salto llega con el titular: hasta entonces
          // contaría el final de la historia por su cuenta.
          if (widget.pie != null) ...[
            const SizedBox(height: 18),
            AnimatedOpacity(
              opacity: _revelado ? 1 : 0,
              duration: _sinAnimacion
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              child: Text(
                widget.pie!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: kMuted),
              ),
            ),
          ],

          const SizedBox(height: 16),
          StickerButton(
            label: 'Seguir',
            expand: true,
            onPressed: _cerrar,
          ),
        ],
      ),
    );
  }
}

/// Un puñado de papelitos. Se calla entero si el sistema pidió menos
/// animación.
class _Confeti extends StatefulWidget {
  final Color color;

  const _Confeti({required this.color});

  @override
  State<_Confeti> createState() => _ConfetiState();
}

class _ConfetiState extends State<_Confeti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tonos = [
      widget.color,
      const Color(0xFFEDB53F),
      const Color(0xFF8BA888),
      const Color(0xFF7BA7C4),
    ];

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _ConfetiPainter(t: _ctrl.value, tonos: tonos),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfetiPainter extends CustomPainter {
  final double t;
  final List<Color> tonos;

  const _ConfetiPainter({required this.t, required this.tonos});

  @override
  void paint(Canvas canvas, Size size) {
    const piezas = 14;
    final pincel = Paint();

    for (var i = 0; i < piezas; i++) {
      final x = size.width * (0.04 + (i * 0.92) / (piezas - 1));
      final retraso = (i % 7) * 0.09 / 2.5;
      final p = ((t - retraso) / (1.9 / 2.5)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;

      final caida = Curves.easeIn.transform(p);
      final y = -20 + 190 * caida;
      final giro = (i.isEven ? 220 : -200) * caida * math.pi / 180;
      // Entra, se mantiene y se va: 0 → 1 → 1 → 0.
      final alfa = p < 0.15
          ? p / 0.15
          : (p > 0.8 ? (1 - p) / 0.2 : 1.0);

      pincel.color = tonos[i % tonos.length].withValues(alpha: alfa.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(giro);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -5, 6, 10),
          const Radius.circular(1),
        ),
        pincel,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfetiPainter old) => old.t != t;
}
