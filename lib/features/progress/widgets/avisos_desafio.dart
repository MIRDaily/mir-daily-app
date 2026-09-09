/* ════════════════════════════════════════════════════════════════════════
   Avisos de desafío completado.

   Un desafío cumplido no merece tapar la pantalla: se anuncia arriba, se va
   solo a los 4,6 s y ya. Las metas gordas —subir de nivel, cambiar de rango,
   un hito de racha— sí se quedan esperando un gesto, y para eso está la
   tarjeta de CelebracionLogros.

   Los dos NO conviven a la vez a propósito: se turnan EN EL TIEMPO. Si hay
   algo gordo que celebrar sale primero su tarjeta, sola y limpia, y estos
   avisos esperan a que se cierre. Meterlos dentro de la tarjeta diluiría la
   meta gorda en una lista; sacarlos por encima de un modal atenuado se lee
   como un error de montaje.

   CADA AVISO SE APAGA SOLO, con su propio reloj atado a su montaje. Un lote de
   temporizadores compartidos en el padre traía dos problemas en la web: al
   llegar un aviso nuevo se cancelaban los del lote anterior, y los avisos
   reutilizaban identificadores, así que se reciclaba el nodo y el texto
   cambiaba SIN ANIMAR.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/models/logros.dart';
import '../../../shared/sticker/sticker.dart';
import 'tarjeta_nivel.dart' show miles;

/// Lo que tarda cada aviso en irse solo.
const Duration kVidaAviso = Duration(milliseconds: 4600);

/// Cuántos se enseñan a la vez.
///
/// Siete son alcanzables de verdad —tres desafíos diarios, "Día redondo" y los
/// tres semanales, un domingo en que alguien lo cierre todo— y en una pantalla
/// de móvil esa columna se la come entera. A partir del cuarto se cuentan en
/// una línea.
const int kAvisosVisibles = 4;

const Color _kVerde = Color(0xFF8BA888);

class AvisosDesafio extends StatelessWidget {
  final List<Logro> desafios;

  /// Quita ese aviso de la cola: se ha visto o se ha ido solo.
  final void Function(String id) onDescartar;

  const AvisosDesafio({
    super.key,
    required this.desafios,
    required this.onDescartar,
  });

  @override
  Widget build(BuildContext context) {
    if (desafios.isEmpty) return const SizedBox.shrink();

    final visibles = desafios.take(kAvisosVisibles).toList();
    final sobran = desafios.length - visibles.length;
    final arriba = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: arriba + 14,
      right: 14,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.86 > 320
            ? 320
            : MediaQuery.sizeOf(context).width * 0.86,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in visibles)
              _Aviso(
                key: ValueKey(l.id),
                logro: l,
                onIr: () => onDescartar(l.id),
              ),
            if (sobran > 0)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: kInk.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: Text(
                  'Y $sobran MÁS',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                    color: kMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatefulWidget {
  final Logro logro;
  final VoidCallback onIr;

  const _Aviso({super.key, required this.logro, required this.onIr});

  @override
  State<_Aviso> createState() => _AvisoState();
}

class _AvisoState extends State<_Aviso> with TickerProviderStateMixin {
  late final AnimationController _entrada;
  late final AnimationController _salida;
  Timer? _reloj;
  bool _sinAnimacion = false;
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    _entrada = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _salida = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listo) return;
    _listo = true;

    _sinAnimacion = MediaQuery.disableAnimationsOf(context);
    if (_sinAnimacion) {
      _entrada.value = 1;
    } else {
      _entrada.forward();
    }

    // Su propio reloj, y atado SOLO a su montaje: si dependiera de la posición
    // en la lista, al desaparecer un aviso los de debajo reiniciarían la
    // cuenta atrás y alguno no se iría nunca.
    _reloj = Timer(kVidaAviso, _irse);
  }

  void _irse() {
    if (!mounted) return;
    if (_sinAnimacion) {
      widget.onIr();
      return;
    }
    _salida.forward().whenComplete(() {
      if (mounted) widget.onIr();
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _entrada.dispose();
    _salida.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.logro;

    final tarjeta = GestureDetector(
      onTap: _irse,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(4),
        ),
        child: Row(
          children: [
            Container(
              height: 34,
              width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tinted(_kVerde, 0.16),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: kInk, width: 2),
              ),
              child: const Icon(
                Icons.task_alt_rounded,
                size: 18,
                color: Color(0xFF6E8D6B),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.scope == 'weekly'
                        ? 'DESAFÍO SEMANAL'
                        : 'DESAFÍO COMPLETADO',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                      color: kMuted,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    l.titulo ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: kInk,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _kVerde,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+${miles(l.xp)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (_sinAnimacion) return tarjeta;

    return AnimatedBuilder(
      animation: Listenable.merge([_entrada, _salida]),
      builder: (context, hijo) {
        // Entrada con rebote: el muelle va poco amortiguado a propósito, pasa
        // de largo y vuelve.
        final e = Curves.elasticOut.transform(_entrada.value.clamp(0.0, 1.0));
        final s = Curves.easeIn.transform(_salida.value.clamp(0.0, 1.0));

        // El desenfoque finge la estela: va de 12 px a 0 en menos de lo que
        // tarda el muelle en asentarse, así que se disipa justo cuando la
        // pieza frena y el ojo lo lee como velocidad. Se anima con su PROPIO
        // ritmo y no con el del muelle: con el muelle rebotaría también el
        // borroso, y un borroso que va y viene se lee como un fallo de render.
        final avanceBorroso =
            (_entrada.value / 0.45).clamp(0.0, 1.0);
        final desenfoque = 12 * (1 - Curves.easeOut.transform(avanceBorroso)) +
            8 * s;

        final x = 90 * (1 - e) + 64 * s;
        final escala = (0.86 + 0.14 * e) * (1 - 0.08 * s);
        final opacidad = (_entrada.value / 0.18).clamp(0.0, 1.0) * (1 - s);

        Widget w = Transform.translate(
          offset: Offset(x, 0),
          child: Transform.scale(
            scale: escala,
            child: Opacity(opacity: opacidad, child: hijo),
          ),
        );

        if (desenfoque > 0.4) {
          w = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: desenfoque / 3,
              sigmaY: desenfoque / 3,
            ),
            child: w,
          );
        }
        return w;
      },
      child: tarjeta,
    );
  }
}
