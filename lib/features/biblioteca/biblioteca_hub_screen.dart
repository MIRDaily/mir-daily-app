import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';
import '../decks/decks_screen.dart';
import '../electros/electros_hub_screen.dart';
import '../library/library_screen.dart';
import '../simulacro/simulacro_screen.dart';

/// Hub de Biblioteca: punto de entrada a las tres herramientas de estudio
/// — Mazos (repetición espaciada), Simulacros (exámenes a medida) y Apuntes
/// (temario por asignaturas). Cada una abre su propia pantalla.
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
            SlideFadeIn(
              child: Text(
                'Studio',
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ),
            const SizedBox(height: 6),
            const SlideFadeIn(
              delay: Duration(milliseconds: 100),
              child: Text(
                'Tu centro de estudio: repasa, ponte a prueba y consulta el temario.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 22),
            SlideFadeIn(
              delay: const Duration(milliseconds: 160),
              beginOffset: const Offset(0, 0.12),
              child: _HubCard(
                title: 'Mazos',
                subtitle: 'Flashcards con repetición espaciada para fijar lo que fallas.',
                icon: Icons.style_rounded,
                gradient: const [Color(0xFFE8A598), Color(0xFFD68C7F)],
                tag: 'DOMINIO · TEXTURAS',
                onTap: () => _open(context, const DecksScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 230),
              beginOffset: const Offset(0, 0.12),
              child: _HubCard(
                title: 'Simulacros',
                subtitle: 'Crea exámenes a medida por asignatura y tema, con corrección.',
                icon: Icons.quiz_rounded,
                gradient: const [Color(0xFF6E8E6B), Color(0xFF8BA888)],
                tag: 'EXÁMENES',
                onTap: () => _open(context, const SimulacroScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 300),
              beginOffset: const Offset(0, 0.12),
              child: _HubCard(
                title: 'Electros',
                subtitle: 'Aprende a leer el ECG y practica con un simulador de 12 derivaciones.',
                icon: Icons.monitor_heart_rounded,
                gradient: const [Color(0xFFC45B4B), Color(0xFFE8A598)],
                tag: 'ECG',
                onTap: () => _open(context, const ElectrosHubScreen()),
              ),
            ),
            const SizedBox(height: 14),
            SlideFadeIn(
              delay: const Duration(milliseconds: 360),
              beginOffset: const Offset(0, 0.12),
              child: _HubCard(
                title: 'Apuntes',
                subtitle: 'Temario por asignaturas, actualizado con IA predictiva.',
                icon: Icons.menu_book_rounded,
                gradient: const [Color(0xFF7D8A96), Color(0xFF94A3B8)],
                tag: 'TEMARIO',
                onTap: () => _open(context, const LibraryScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String tag;
  final VoidCallback onTap;

  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: gradient.first.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: gradient.first.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            color: gradient.first,
                            fontWeight: FontWeight.w800,
                            fontSize: 8,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.textLight, size: 16),
          ],
        ),
      ),
    );
  }
}
