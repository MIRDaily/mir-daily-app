import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/user_provider.dart';
import '../providers/focus_provider.dart';
import '../models/focus_room.dart';
import '../widgets/animated_focus_background.dart';
import '../widgets/floating_avatars.dart';
import '../widgets/create_room_dialog.dart';
import '../widgets/distraction_warning.dart';
import '../widgets/focus_score_indicator.dart';
import '../widgets/immersive_focus_ui.dart';

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FocusProvider>(
      builder: (context, focusProvider, child) {
        if (focusProvider.isInFocusMode && focusProvider.currentRoom != null) {
          return _FocusSessionScreen(room: focusProvider.currentRoom!);
        }
        
        return _FocusLobbyScreen();
      },
    );
  }
}

/// Pantalla de lobby donde se puede crear o unirse a salas
class _FocusLobbyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Concentración',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea una sala y estudia sin distracciones',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 40),

              // Botón principal de crear sala
              _buildCreateRoomButton(context),

              const SizedBox(height: 24),

              // Características
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildFeatureCard(
                        icon: Icons.timer,
                        title: 'Temporizador Inteligente',
                        description: 'Define tu sesión de estudio y mantén el foco',
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        icon: Icons.group,
                        title: 'Estudia en Grupo',
                        description: 'Invita amigos y estudien juntos virtualmente',
                        color: AppColors.secondary,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        icon: Icons.music_note,
                        title: 'Música de Concentración',
                        description: 'Ambiente relajante para maximizar tu productividad',
                        color: AppColors.success,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        icon: Icons.phone_locked,
                        title: 'Modo Sin Distracciones',
                        description: 'Tu teléfono se bloqueará para evitar interrupciones',
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateRoomButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => const CreateRoomDialog(),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primary.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.add_circle_outline,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 20),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crear Nueva Sala',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Comienza tu sesión de concentración',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pantalla de sesión activa de concentración
class _FocusSessionScreen extends StatefulWidget {
  final FocusRoom room;

  const _FocusSessionScreen({required this.room});

  @override
  State<_FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends State<_FocusSessionScreen> {
  bool _showControls = true;

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // NUEVO: Flutter 3.12+ usa PopScope en lugar de WillPopScope
      canPop: false, // Bloquear completamente el gesto de back
      onPopInvoked: (didPop) {
        if (didPop) return;
        
        // Prevenir salida accidental - mostrar controles si estaban ocultos
        if (!_showControls) {
          _toggleControls();
          return;
        }
        _showExitWarning(context);
      },
      child: Scaffold(
        // ✅ NUEVO: Sin AppBar ni colores del sistema para inmersión total
        extendBodyBehindAppBar: true,
        extendBody: true,
        backgroundColor: Colors.black,  // Fondo negro puro para inmersión
        body: Stack(
          children: [
            // Fondo animado
            const Positioned.fill(
              child: AnimatedFocusBackground(),
            ),

            // Avatares flotantes (sin nombres por defecto)
            Positioned.fill(
              child: FloatingAvatars(
                participants: widget.room.participants,
                showNames: _showControls,
              ),
            ),

            // UI Inmersiva (controles que aparecen/desaparecen)
            ImmersiveFocusUI(
              room: widget.room,
              showControls: _showControls,
              onToggleControls: _toggleControls,
            ),

            // Mensaje motivacional en el centro (siempre visible)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.self_improvement,
                          color: Colors.white.withOpacity(0.3),
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '¡Sigue concentrado!',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toca la pantalla para ver controles',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Alerta de distracción (overlay que aparece cuando vuelves)
            const DistractionWarning(),
          ],
        ),
      ),
    );
  }

  void _showExitWarning(BuildContext context) {
    final focusProvider = context.read<FocusProvider>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        contentPadding: EdgeInsets.zero,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con emoji
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: focusProvider.getFocusScoreColor().withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      focusProvider.focusScore >= 70 ? '🎉' : focusProvider.focusScore >= 40 ? '😊' : '😔',
                      style: const TextStyle(fontSize: 48),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '¿Terminar sesión?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Estadísticas
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const DistractionStats(),
                    
                    const SizedBox(height: 20),
                    
                    // Botones
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Seguir Concentrado',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              focusProvider.leaveRoom();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: focusProvider.getFocusScoreColor(),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Terminar',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
