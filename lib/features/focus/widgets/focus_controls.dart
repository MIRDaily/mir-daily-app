import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/focus_provider.dart';

class FocusControls extends StatelessWidget {
  const FocusControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FocusProvider>(
      builder: (context, focusProvider, child) {
        final remainingTime = focusProvider.remainingTime;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Timer principal
                _buildTimer(remainingTime),
                
                const SizedBox(height: 32),
                
                // Controles
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Botón de música
                    _buildControlButton(
                      icon: focusProvider.isMusicPlaying
                          ? Icons.music_note
                          : Icons.music_off,
                      label: 'Música',
                      onTap: focusProvider.toggleMusic,
                      isActive: focusProvider.isMusicPlaying,
                    ),
                    
                    // Botón de salir (requiere confirmación)
                    _buildControlButton(
                      icon: Icons.exit_to_app,
                      label: 'Salir',
                      onTap: () => _showExitConfirmation(context),
                      isActive: false,
                      color: Colors.red.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimer(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    return Column(
      children: [
        // Tiempo en números grandes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hours > 0) ...[
              _buildTimeUnit(hours.toString().padLeft(2, '0')),
              _buildTimeSeparator(),
            ],
            _buildTimeUnit(minutes.toString().padLeft(2, '0')),
            _buildTimeSeparator(),
            _buildTimeUnit(seconds.toString().padLeft(2, '0')),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Etiquetas
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hours > 0) ...[
              const SizedBox(width: 60),
              _buildTimeLabel('HORAS'),
              const SizedBox(width: 30),
            ],
            _buildTimeLabel('MIN'),
            const SizedBox(width: 40),
            _buildTimeLabel('SEG'),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeUnit(String value) {
    return Container(
      width: 80,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTimeLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.7),
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isActive,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color ?? (isActive 
              ? Colors.white.withValues(alpha: 0.25) 
              : Colors.white.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          '¿Salir de la sesión?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Perderás el progreso de tu sesión de concentración actual.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<FocusProvider>().leaveRoom();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Salir',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
