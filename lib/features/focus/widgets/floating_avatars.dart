import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io' show File;
import '../models/focus_room.dart';

/// Widget que muestra los avatares de los participantes flotando en la pantalla
class FloatingAvatars extends StatefulWidget {
  final List<FocusUser> participants;
  final bool showNames;

  const FloatingAvatars({
    super.key,
    required this.participants,
    this.showNames = false,
  });

  @override
  State<FloatingAvatars> createState() => _FloatingAvatarsState();
}

class _FloatingAvatarsState extends State<FloatingAvatars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<AvatarPosition> _positions;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20), // Movimiento más lento
    )..repeat();
    
    _initializePositions();
  }

  void _initializePositions() {
    final random = math.Random();
    _positions = widget.participants.asMap().entries.map((entry) {
      return AvatarPosition(
        baseX: 0.1 + random.nextDouble() * 0.8,
        baseY: 0.2 + random.nextDouble() * 0.6,
        amplitude: 15 + random.nextDouble() * 20, // Amplitud reducida
        frequency: 0.3 + random.nextDouble() * 0.5, // Frecuencia reducida
        phase: random.nextDouble() * 2 * math.pi,
      );
    }).toList();
  }

  @override
  void didUpdateWidget(FloatingAvatars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.participants.length != widget.participants.length) {
      _initializePositions();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Asegurar que tenemos el tamaño correcto
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: List.generate(widget.participants.length, (index) {
                  final participant = widget.participants[index];
                  final position = _positions[index];
                  
                  return _buildFloatingAvatar(
                    participant: participant,
                    position: position,
                    animation: _controller.value,
                    index: index,
                    screenSize: Size(constraints.maxWidth, constraints.maxHeight),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFloatingAvatar({
    required FocusUser participant,
    required AvatarPosition position,
    required double animation,
    required int index,
    required Size screenSize,
  }) {
    // Calcular posición con movimiento sinusoidal directamente
    final x = screenSize.width * position.baseX +
        math.sin(animation * 2 * math.pi * position.frequency + position.phase) *
            position.amplitude;
    
    final y = screenSize.height * position.baseY +
        math.cos(animation * 2 * math.pi * position.frequency * 0.7 + position.phase) *
            position.amplitude * 0.5;

    return Positioned(
      left: x - 35, // Centrar el avatar (70/2)
      top: y - 35,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + index * 100),
          curve: Curves.elasticOut,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: _AvatarBubble(
            user: participant,
            showName: widget.showNames,
          ),
        ),
      ),
    );
  }
}

class AvatarPosition {
  final double baseX;
  final double baseY;
  final double amplitude;
  final double frequency;
  final double phase;

  AvatarPosition({
    required this.baseX,
    required this.baseY,
    required this.amplitude,
    required this.frequency,
    required this.phase,
  });
}

class _AvatarBubble extends StatelessWidget {
  final FocusUser user;
  final bool showName;

  const _AvatarBubble({
    required this.user,
    this.showName = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? _buildAvatarImage()
                      : Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _getColorFromString(user.name).withValues(alpha: 0.8),
                                _getColorFromString(user.name),
                              ],
                            ),
                          ),
                          child: _buildInitials(),
                        ),
                ),
              ),
              // Indicador de "en línea"
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showName) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              user.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInitials() {
    final initials = user.name
        .split(' ')
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();

    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Cargar avatar desde assets locales, archivos locales o desde URL de red
  Widget _buildAvatarImage() {
    final avatarUrl = user.avatarUrl!;
    
    // Verificar si es un asset local (comienza con 'assets/')
    if (avatarUrl.startsWith('assets/')) {
      return Image.asset(
        avatarUrl,
        width: 70,
        height: 70,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading asset avatar: $error');
          return _buildInitials();
        },
      );
    }
    
    // Verificar si es una ruta de archivo local (contiene '/')
    if (avatarUrl.contains('/') && !avatarUrl.startsWith('http')) {
      return Image.file(
        File(avatarUrl),
        width: 70,
        height: 70,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading file avatar: $error');
          return _buildInitials();
        },
      );
    }
    
    // Si no es un asset ni archivo local, intentar cargar desde red
    return Image.network(
      avatarUrl,
      width: 70,
      height: 70,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildInitials();
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Error loading network avatar: $error');
        return _buildInitials();
      },
    );
  }

  Color _getColorFromString(String str) {
    // Generar color basado en el hash del string
    int hash = 0;
    for (int i = 0; i < str.length; i++) {
      hash = str.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    final colors = [
      const Color(0xFF6B7FD7),
      const Color(0xFF9B59B6),
      const Color(0xFFE74C3C),
      const Color(0xFFF39C12),
      const Color(0xFF16A085),
      const Color(0xFF2ECC71),
      const Color(0xFF3498DB),
    ];
    
    return colors[hash.abs() % colors.length];
  }
}
