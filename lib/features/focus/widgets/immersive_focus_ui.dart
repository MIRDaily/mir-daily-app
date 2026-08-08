import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/focus_provider.dart';
import '../models/focus_room.dart';

/// Widget que maneja la UI inmersiva con controles que aparecen/desaparecen
class ImmersiveFocusUI extends StatefulWidget {
  final FocusRoom room;
  final bool showControls;
  final VoidCallback onToggleControls;

  const ImmersiveFocusUI({
    super.key,
    required this.room,
    required this.showControls,
    required this.onToggleControls,
  });

  @override
  State<ImmersiveFocusUI> createState() => _ImmersiveFocusUIState();
}

class _ImmersiveFocusUIState extends State<ImmersiveFocusUI> {
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Mostrar controles al inicio por 3 segundos
    if (widget.showControls) {
      _startHideTimer();
    }
  }

  @override
  void didUpdateWidget(ImmersiveFocusUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si los controles se muestran, iniciar timer
    if (widget.showControls && !oldWidget.showControls) {
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.showControls) {
        widget.onToggleControls();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // GestureDetector que captura toques en toda la pantalla
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onToggleControls,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        
        // Nombre de la sala (top) - se oculta
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          top: widget.showControls ? 20 : -100,
          left: 20,
          right: 20,
          child: SafeArea(
            child: _buildRoomLabel(),
          ),
        ),

        // Score indicator (top) - se oculta
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          top: widget.showControls ? 80 : -100,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Center(
              child: _buildScoreIndicator(),
            ),
          ),
        ),

        // Timer (bottom) - SIEMPRE VISIBLE
        Positioned(
          bottom: 120,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: Center(
              child: _buildTimer(),
            ),
          ),
        ),

        // Controles de música y salida (bottom) - se ocultan
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          bottom: widget.showControls ? 20 : -100,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: _buildBottomControls(),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.circle,
            color: Colors.green,
            size: 8,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.room.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people,
                  color: Colors.white70,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.room.participantCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreIndicator() {
    return Consumer<FocusProvider>(
      builder: (context, focusProvider, child) {
        final score = focusProvider.focusScore;
        final color = focusProvider.getFocusScoreColor();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withOpacity(0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                score >= 70
                    ? Icons.emoji_events
                    : score >= 40
                        ? Icons.sentiment_satisfied
                        : Icons.sentiment_dissatisfied,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                '/100',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(
            icon: Icons.music_note,
            onTap: () {
              context.read<FocusProvider>().toggleMusic();
            },
            isActive: context.watch<FocusProvider>().isMusicPlaying,
          ),
          
          const SizedBox(width: 24),
          
          _buildControlButton(
            icon: Icons.close,
            onTap: () => _showExitConfirmation(context),
            isActive: false,
            color: Colors.red.withOpacity(0.8),
          ),
        ],
      ),
    );
  }

  Widget _buildTimer() {
    return Consumer<FocusProvider>(
      builder: (context, focusProvider, child) {
        final duration = focusProvider.remainingTime;
        final hours = duration.inHours;
        final minutes = duration.inMinutes.remainder(60);
        final seconds = duration.inSeconds.remainder(60);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (hours > 0) ...[
              _buildTimeUnit(hours.toString().padLeft(2, '0')),
              _buildTimeSeparator(),
            ],
            _buildTimeUnit(minutes.toString().padLeft(2, '0')),
            _buildTimeSeparator(),
            _buildTimeUnit(seconds.toString().padLeft(2, '0')),
          ],
        );
      },
    );
  }

  Widget _buildTimeUnit(String value) {
    return Container(
      width: 70,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 48,
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
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isActive,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color ?? (isActive 
              ? Colors.white.withOpacity(0.25) 
              : Colors.white.withOpacity(0.15)),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  void _showExitConfirmation(BuildContext context) {
    final focusProvider = context.read<FocusProvider>();
    final exitCount = focusProvider.exitCount;
    final distractionTime = focusProvider.totalDistractionTime;
    final distractionCount = focusProvider.distractionCount;
    final focusScore = focusProvider.focusScore;
    final rating = focusProvider.getFocusRating();
    
    showDialog(
      context: context,
      barrierDismissible: false, // No cerrar al tocar fuera
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con emoji
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    // Emoji
                    const Text(
                      '🎉',
                      style: TextStyle(fontSize: 64),
                    ),
                    const SizedBox(height: 16),
                    // Pregunta
                    Text(
                      '¿Terminar sesión?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Contenido
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text(
                      'Resumen de Concentración',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Score Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          // Icono
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.emoji_events,
                              color: Colors.green,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Score
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Score Final: $focusScore/100',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rating,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Divider
                    Divider(color: Colors.grey[300], thickness: 1),
                    
                    const SizedBox(height: 16),
                    
                    // Estadísticas
                    _buildStatRow(
                      icon: Icons.exit_to_app,
                      iconColor: Colors.orange,
                      label: 'Salidas de la app',
                      value: exitCount.toString(),
                      valueColor: exitCount > 0 ? Colors.orange : Colors.grey,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    _buildStatRow(
                      icon: Icons.timer_off,
                      iconColor: Colors.red,
                      label: 'Tiempo distraído',
                      value: _formatDuration(distractionTime),
                      valueColor: distractionTime.inSeconds > 0 ? Colors.red : Colors.grey,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    _buildStatRow(
                      icon: Icons.phone_android,
                      iconColor: Colors.purple,
                      label: 'Distracciones totales',
                      value: distractionCount.toString(),
                      valueColor: distractionCount > 0 ? Colors.purple : Colors.grey,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Botones
                    Row(
                      children: [
                        // Botón Seguir
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              'Seguir Concentrado',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // Botón Terminar
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              context.read<FocusProvider>().leaveRoom();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Terminar',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
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
  
  Widget _buildStatRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
  
  String _formatDuration(Duration duration) {
    if (duration.inSeconds == 0) return '0s';
    if (duration.inMinutes == 0) return '${duration.inSeconds}s';
    if (duration.inHours == 0) return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
}
