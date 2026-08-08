import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/quiz_provider.dart';
import '../../focus/providers/focus_provider.dart';
import '../models/studio_feature.dart';
import '../widgets/studio_card.dart';
import '../../decks/screens/decks_screen.dart';
import '../../focus/screens/focus_screen.dart';

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Studio',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tu espacio de estudio personalizado',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Stats Card (opcional - puedes comentar si no quieres mostrarla aún)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: _StatsCard(),
              ),
            ),
            
            // Features Grid
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildListDelegate([
                  // Tarjeta de Mazos
                  Consumer<UserProvider>(
                    builder: (context, userProvider, _) {
                      final deckCount = userProvider.decks.length;
                      return StudioCard(
                        feature: StudioFeature(
                          id: 'decks',
                          title: 'Mazos',
                          description: 'Organiza y repasa tus preguntas guardadas',
                          icon: Icons.style_rounded,
                          color: AppColors.primary,
                          badge: deckCount > 0 ? '$deckCount mazos' : null,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DecksScreen(),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  
                  // Tarjeta de Focus Mode
                  Consumer<FocusProvider>(
                    builder: (context, focusProvider, _) {
                      final sessionsToday = focusProvider.todaySessions;
                      return StudioCard(
                        feature: StudioFeature(
                          id: 'focus',
                          title: 'Focus Mode',
                          description: 'Sesiones de estudio sin distracciones',
                          icon: Icons.self_improvement_rounded,
                          color: const Color(0xFF6366F1), // Indigo
                          badge: sessionsToday > 0 ? '$sessionsToday hoy' : null,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const FocusScreen(),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  
                  // Tarjeta de Flashcards (próximamente)
                  StudioCard(
                    feature: StudioFeature(
                      id: 'flashcards',
                      title: 'Flashcards',
                      description: 'Repaso con espaciado inteligente',
                      icon: Icons.flip_to_front_rounded,
                      color: const Color(0xFFEC4899), // Pink
                      isEnabled: false,
                      onTap: () {},
                    ),
                  ),
                  
                  // Tarjeta de Estadísticas (próximamente)
                  StudioCard(
                    feature: StudioFeature(
                      id: 'stats',
                      title: 'Estadísticas',
                      description: 'Analiza tu progreso y rendimiento',
                      icon: Icons.analytics_rounded,
                      color: const Color(0xFF10B981), // Green
                      isEnabled: false,
                      onTap: () {},
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget que muestra estadísticas rápidas del usuario
class _StatsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<QuizProvider>(
      builder: (context, quizProvider, _) {
        final stats = quizProvider.userStats;
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withOpacity(0.1),
                AppColors.primary.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              _StatItem(
                icon: Icons.question_answer_rounded,
                label: 'Respondidas',
                value: '${stats['answered'] ?? 0}',
                color: AppColors.primary,
              ),
              const SizedBox(width: 24),
              Container(
                width: 1,
                height: 40,
                color: AppColors.secondary.withOpacity(0.2),
              ),
              const SizedBox(width: 24),
              _StatItem(
                icon: Icons.check_circle_rounded,
                label: 'Correctas',
                value: '${stats['correct'] ?? 0}',
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 24),
              Container(
                width: 1,
                height: 40,
                color: AppColors.secondary.withOpacity(0.2),
              ),
              const SizedBox(width: 24),
              _StatItem(
                icon: Icons.trending_up_rounded,
                label: 'Racha',
                value: '${stats['streak'] ?? 0}d',
                color: const Color(0xFFF59E0B),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
