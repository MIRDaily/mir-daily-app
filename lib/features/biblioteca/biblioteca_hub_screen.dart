import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../decks/decks_screen.dart';
import '../electros/electros_hub_screen.dart';
import '../flashcards/flashcards_screen.dart';
import '../library/library_screen.dart';
import '../simulacro/simulacro_screen.dart';
import 'widgets/studio_card_art.dart';

/// Hub de Studio: punto de entrada a las herramientas de estudio — Mazos
/// (repetición espaciada), Simulacros (exámenes a medida), Electros (ECG) y
/// Apuntes (temario por asignaturas).
///
/// Rediseñado con el lenguaje visual de la web (borde de tinta y sombra dura).
/// Aquí la textura de cada tarjeta es un anticipo de la de su herramienta:
/// cartulina rayada para lo que son fichas, papel milimetrado para el ECG.
class BibliotecaHubScreen extends StatelessWidget {
  const BibliotecaHubScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            const StickerHero(
              badge: 'Studio',
              badgeIcon: Icons.auto_awesome_rounded,
              title: 'Tu centro de estudio',
              subtitle: 'Repasa, ponte a prueba y consulta el temario.',
            ),
            const SizedBox(height: 26),
            const SectionLabel('Herramientas'),
            SlideFadeIn(
              delay: const Duration(milliseconds: 120),
              beginOffset: const Offset(0, 0.12),
              child: _ToolCard(
                title: 'Mazos',
                subtitle:
                    'Repaso espaciado de tus preguntas guardadas para retenerlas a largo plazo.',
                tag: 'Dominio',
                icon: Icons.layers_rounded,
                accent: const Color(0xFFE8A598),
                art: const DeckCardArt(),
                texture: ruledPaper(step: 22),
                onTap: () => _open(context, const DecksScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 155),
              beginOffset: const Offset(0, 0.12),
              child: _ToolCard(
                title: 'Flashcards',
                subtitle:
                    'Crea y repasa tus propias tarjetas, con anverso y reverso.',
                tag: 'Tarjetas',
                icon: Icons.style_rounded,
                accent: const Color(0xFFD68C7F),
                art: const FlashcardFlipArt(),
                texture: ruledPaper(step: 20),
                onTap: () => _open(context, const FlashcardsScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 220),
              beginOffset: const Offset(0, 0.12),
              child: _ToolCard(
                title: 'Simulacros',
                subtitle:
                    'Crea exámenes a medida por asignatura y tema, con corrección e historial.',
                tag: 'Exámenes',
                icon: Icons.quiz_rounded,
                accent: const Color(0xFF6E8E6B),
                art: const ExamSheetArt(),
                texture: ruledPaper(step: 26),
                onTap: () => _open(context, const SimulacroScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 290),
              beginOffset: const Offset(0, 0.12),
              child: _ToolCard(
                title: 'Electros',
                subtitle:
                    'Aprende a leer el ECG en la Academia y practica con un simulador de 12 derivaciones.',
                tag: 'ECG',
                icon: Icons.monitor_heart_rounded,
                accent: const Color(0xFFC45B4B),
                art: const EcgMonitorArt(),
                texture: graphPaper(tint: const Color(0xFFC45B4B), step: 9),
                onTap: () => _open(context, const ElectrosHubScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 360),
              beginOffset: const Offset(0, 0.12),
              child: _ToolCard(
                title: 'Apuntes',
                subtitle: 'Temario por asignaturas, actualizado con IA predictiva.',
                tag: 'Temario',
                icon: Icons.menu_book_rounded,
                accent: const Color(0xFF7D8A96),
                texture: ruledPaper(step: 18),
                onTap: () => _open(context, const LibraryScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de herramienta: pastilla con el icono, título, descripción y la
/// textura de la herramienta asomando por detrás.
class _ToolCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String tag;
  final IconData icon;
  final Color accent;
  final Decoration texture;
  final VoidCallback onTap;

  /// Ilustración animada que sustituye al icono, cuando la hay. Las de Mazos y
  /// Simulacros vienen de la web; el resto sigue con su icono.
  final Widget? art;

  const _ToolCard({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.icon,
    required this.accent,
    required this.texture,
    required this.onTap,
    this.art,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      onTap: onTap,
      // Se hunde contra su sombra y aguanta un instante antes de abrir la
      // sección: sin esa espera, en un toque rápido la pantalla ya ha cambiado
      // y el gesto no llega a verse.
      pressDelay: const Duration(milliseconds: 120),
      texture: texture,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Con ilustración se deja respirar sobre el fondo de la tarjeta: la
          // pastilla de color la aplastaría y taparía el dibujo.
          if (art != null)
            SizedBox(width: 56, height: 56, child: art)
          else
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kInk, width: 2),
                boxShadow: inkShadow(3),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kInk,
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tag.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 9,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    // Un pelo de fondo bajo el texto para que la textura no le
                    // reste legibilidad en las líneas más apretadas.
                    backgroundColor: Colors.white.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios_rounded,
              color: kMuted.withOpacity(0.6), size: 16),
        ],
      ),
    );
  }
}
