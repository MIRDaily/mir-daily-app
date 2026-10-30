// Centro de minijuegos. Puerto de la web: src/app/studio/minijuegos/page.tsx.
//
// La web solo lista GramSwipe (MedGuess va en su cabecera); en la app, que no tiene esa cabecera,
// MedGuess vive aquí también, como reto del día.

import 'package:flutter/material.dart';

import '../../core/models/gramswipe_datos.dart';
import '../../core/responsive/adaptive_grid.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../medguess/medguess_screen.dart';
import 'gramswipe_screen.dart';

class MinijuegosScreen extends StatelessWidget {
  const MinijuegosScreen({super.key});

  void _abrir(BuildContext context, Widget pantalla) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Minijuegos')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.bodyGutter, 8, context.bodyGutter, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Minijuegos',
                      style: TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Repasa a base de juego rápido, ideal para los huecos entre sesiones de estudio.',
                      style: TextStyle(color: kMuted, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    AdaptiveGrid(
                      targetItemWidth: 400,
                      maxColumns: 2,
                      children: [
                        SlideFadeIn(
                          delay: const Duration(milliseconds: 80),
                          beginOffset: const Offset(0, 0.12),
                          child: _TarjetaJuego(
                            titulo: 'GramSwipe',
                            texto: 'Clasifica antibióticos por su espectro de cobertura deslizando la tarjeta '
                                'en la dirección correcta.',
                            etiqueta: 'Antibióticos',
                            icono: Icons.vaccines_rounded,
                            color: const Color(0xFFD4978C),
                            datos: '${antibioticosGramSwipe.length} tarjetas · 2 modos',
                            onTap: () => _abrir(context, const GramSwipeScreen()),
                          ),
                        ),
                        SlideFadeIn(
                          delay: const Duration(milliseconds: 140),
                          beginOffset: const Offset(0, 0.12),
                          child: _TarjetaJuego(
                            titulo: 'MedGuess',
                            texto: 'El reto médico del día: destapa el término oculto con palabras de 5 letras.',
                            etiqueta: 'Reto diario',
                            icono: Icons.spellcheck_rounded,
                            color: const Color(0xFF8BA888),
                            datos: '1 término al día · 6 intentos',
                            onTap: () => _abrir(context, const MedGuessScreen()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaJuego extends StatelessWidget {
  final String titulo;
  final String texto;
  final String etiqueta;
  final IconData icono;
  final Color color;
  final String datos;
  final VoidCallback onTap;

  const _TarjetaJuego({
    required this.titulo,
    required this.texto,
    required this.etiqueta,
    required this.icono,
    required this.color,
    required this.datos,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      radius: 24,
      padding: const EdgeInsets.all(18),
      texture: tintedPaper(color, step: 26),
      onTap: onTap,
      pressDelay: const Duration(milliseconds: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kInk, width: 2),
                  boxShadow: inkShadow(3),
                ),
                child: Icon(icono, color: Colors.white, size: 26),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: kInk, width: 1.5),
                ),
                child: Text(
                  etiqueta.toUpperCase(),
                  style: const TextStyle(color: kInk, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(titulo, style: const TextStyle(color: kInk, fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(texto, style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(datos, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const Text('Jugar', style: TextStyle(color: kInk, fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: kInk),
            ],
          ),
        ],
      ),
    );
  }
}
