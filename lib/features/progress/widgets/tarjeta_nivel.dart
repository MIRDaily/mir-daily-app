/* ════════════════════════════════════════════════════════════════════════
   La tarjeta de nivel: rango, avance dentro del nivel, racha y tope diario.

   DELIBERADAMENTE NO ENSEÑA NINGÚN PORCENTAJE DE ACIERTO. El nivel mide
   constancia; la precisión vive en el Panel. Juntarlos en la misma tarjeta
   haría creer al usuario que un nivel alto significa que va a aprobar, y no es
   así. En la web se respetó y aquí también.
═══════════════════════════════════════════════════════════════════════════ */
import 'package:flutter/material.dart';

import '../../../core/models/progress.dart';
import '../../../core/theme/levels.dart';
import '../../../shared/sticker/sticker.dart';
import 'llama_racha.dart';
import 'marco_nivel.dart';

/// Miles con punto, como en la web (`Intl.NumberFormat('es-ES')`), sin
/// arrastrar `intl` solo para esto.
String miles(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

class TarjetaNivel extends StatelessWidget {
  final UserProgress? progress;
  final bool loading;

  const TarjetaNivel({super.key, required this.progress, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) {
      return StickerCard(
        padding: const EdgeInsets.all(20),
        child: Text(
          loading
              ? 'Cargando tu progreso…'
              : 'Tu progreso aparecerá aquí en cuanto estudies.',
          style: const TextStyle(fontSize: 14, color: kMuted),
        ),
      );
    }

    final rango = rankForLevel(p.level);
    final siguiente = nextRank(p.level);

    return StickerCard(
      padding: EdgeInsets.zero,
      // SIN `clipBehavior`. Recortar contra el radio exterior hace que el pie
      // pinte por encima de la mitad interior del trazo de tinta y la esquina
      // se quede sin línea — está avisado en el propio kit. El pie se redondea
      // él solo con el radio INTERIOR (el de la tarjeta menos el borde), que
      // es el hueco que de verdad ocupa.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    MarcoNivel(
                      nivel: p.level,
                      tamano: 64,
                      color: rango.color,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rango.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                              color: kInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${miles(p.xpTotal)} XP en total',
                            style: const TextStyle(
                              fontSize: 13,
                              color: kMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Barra de avance DENTRO del nivel: xpIntoLevel / xpForNext.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        p.esTope
                            ? 'Nivel máximo alcanzado'
                            : 'Faltan ${miles(p.xpRestante)} XP '
                                'para el nivel ${p.level + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${miles(p.xpIntoLevel)} / ${miles(p.xpForNext)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: kMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                _Barra(fraccion: p.fraccionNivel, color: rango.color),
                if (siguiente != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Siguiente rango: ${siguiente.name} '
                    'en el nivel ${siguiente.minLevel}',
                    style: const TextStyle(fontSize: 11.5, color: kMuted),
                  ),
                ],
              ],
            ),
          ),

          // Pie: racha, multiplicador, protectores y el XP de hoy.
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFBF9F8),
              border: Border(top: BorderSide(color: kHairline, width: 2)),
              // El radio de la tarjeta (24) menos el grosor del trazo (2): el
              // pie llega hasta el filo interior y sigue su curva, así que las
              // dos esquinas de abajo quedan limpias.
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LlamaRacha(racha: p.currentStreak, size: 26),
                        const SizedBox(width: 8),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${p.currentStreak}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              TextSpan(
                                text: p.currentStreak == 1
                                    ? ' día de racha'
                                    : ' días de racha',
                              ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 13, color: kInk),
                        ),
                        if (p.streakMultiplier > 1) ...[
                          const SizedBox(width: 8),
                          _Pastilla(
                            texto: '×${_dosDecimales(p.streakMultiplier)} XP',
                            color: const Color(0xFF8BA888),
                          ),
                        ],
                      ],
                    ),
                    if (p.streakFreezes > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 26,
                            width: 26,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE3F0F5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shield_outlined,
                              size: 16,
                              color: Color(0xFF5E9AA8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${p.streakFreezes}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: p.streakFreezes == 1
                                      ? ' protector'
                                      : ' protectores',
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 13, color: kInk),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _PieDelTope(p: p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dosDecimales(double v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');
}

/// El XP de hoy y la barra del tope.
///
/// **Son dos cifras distintas midiendo cosas distintas.** El número grande es
/// `xpTodayTotal` —todo lo ganado hoy—, y la barra mide `xpToday` sobre el
/// tope, que solo cuenta las fuentes de estudio. Los premios semanales caen
/// todos el mismo día y viven fuera del tope: enseñar "300 / 300" un domingo
/// en que se han ganado 800 XP sería dejar 500 sin contar. Es un fallo que la
/// web ya cometió y corrigió.
class _PieDelTope extends StatelessWidget {
  final UserProgress p;

  const _PieDelTope({required this.p});

  @override
  Widget build(BuildContext context) {
    final extras = p.xpFueraDeTope;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Hoy '),
                  TextSpan(
                    text: miles(p.xpTodayTotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: kInk,
                    ),
                  ),
                  const TextSpan(text: ' XP'),
                ],
              ),
              style: const TextStyle(fontSize: 12.5, color: kMuted),
            ),
            const Spacer(),
            Text(
              '${miles(p.xpToday)} / ${miles(p.dailyCap)} del tope',
              style: const TextStyle(
                fontSize: 10.5,
                color: kMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        _Barra(
          fraccion: p.fraccionTope,
          color: const Color(0xFF8BA888),
          alto: 6,
        ),
        if (extras > 0) ...[
          const SizedBox(height: 5),
          Text(
            'Los ${miles(extras)} XP de premios semanales no gastan tope.',
            style: TextStyle(fontSize: 10.5, color: kMuted.withValues(alpha: 0.9)),
          ),
        ],
      ],
    );
  }
}

class _Barra extends StatelessWidget {
  final double fraccion;
  final Color color;
  final double alto;

  const _Barra({required this.fraccion, required this.color, this.alto = 10});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: Container(
        height: alto,
        color: const Color(0xFFF3EFED),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraccion.clamp(0.0, 1.0)),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 700),
          curve: kEaseOut,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(alto),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  final String texto;
  final Color color;

  const _Pastilla({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tinted(color, 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: haciaLaTinta(color, 0.18),
        ),
      ),
    );
  }
}
