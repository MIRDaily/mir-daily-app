import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/focus_provider.dart';

/// Widget que muestra el score de concentración del usuario
class FocusScoreIndicator extends StatelessWidget {
  const FocusScoreIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FocusProvider>(
      builder: (context, focusProvider, child) {
        final score = focusProvider.focusScore;
        final color = focusProvider.getFocusScoreColor();
        final rating = focusProvider.getFocusRating();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withOpacity(0.5),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono animado
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.8 + (value * 0.2),
                    child: Icon(
                      score >= 70
                          ? Icons.emoji_events
                          : score >= 40
                              ? Icons.sentiment_satisfied
                              : Icons.sentiment_dissatisfied,
                      color: color,
                      size: 28,
                    ),
                  );
                },
              ),
              
              const SizedBox(width: 12),
              
              // Score y rating
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Score: ',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 100, end: score.toDouble()),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, value, child) {
                          return Text(
                            '${value.toInt()}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          );
                        },
                      ),
                      const Text(
                        '/100',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    rating,
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(width: 16),
              
              // Barra de progreso circular
              SizedBox(
                width: 40,
                height: 40,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.0, end: score / 100),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, value, child) {
                    return CircularProgressIndicator(
                      value: value,
                      strokeWidth: 4,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Widget que muestra estadísticas de distracción (para el resumen final)
class DistractionStats extends StatelessWidget {
  const DistractionStats({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FocusProvider>(
      builder: (context, focusProvider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resumen de Concentración',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Score final
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: focusProvider.getFocusScoreColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.emoji_events,
                      color: focusProvider.getFocusScoreColor(),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Score Final: ${focusProvider.focusScore}/100',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          focusProvider.getFocusRating(),
                          style: TextStyle(
                            fontSize: 14,
                            color: focusProvider.getFocusScoreColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),
              
              // Estadísticas
              _buildStatRow(
                icon: Icons.exit_to_app,
                label: 'Salidas de la app',
                value: '${focusProvider.exitCount}',
                color: Colors.orange,
              ),
              
              const SizedBox(height: 12),
              
              _buildStatRow(
                icon: Icons.timer_off,
                label: 'Tiempo distraído',
                value: _formatDuration(focusProvider.totalDistractionTime),
                color: Colors.red,
              ),
              
              const SizedBox(height: 12),
              
              _buildStatRow(
                icon: Icons.phone_android,
                label: 'Distracciones totales',
                value: '${focusProvider.distractionCount}',
                color: Colors.purple,
              ),
              
              if (focusProvider.focusScore < 70) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Tip: Activa "No Molestar" en tu teléfono para mejorar tu concentración',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
