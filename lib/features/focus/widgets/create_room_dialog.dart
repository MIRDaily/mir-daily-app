import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/user_provider.dart';
import '../providers/focus_provider.dart';
import '../models/focus_room.dart';

class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({super.key});

  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  final _nameController = TextEditingController();
  final _customMinutesController = TextEditingController();
  Duration _selectedDuration = const Duration(minutes: 25);
  bool _isCustomTime = false;

  final List<Duration> _durations = const [
    Duration(minutes: 15),
    Duration(minutes: 25),
    Duration(minutes: 45),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _customMinutesController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h';
    }
    return '${duration.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.self_improvement,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Crear Sala de Concentración',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre de la sala
                  const Text(
                    'Nombre de la sala',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Ej: Estudio de Anatomía',
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Duración
                  const Text(
                    'Duración',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Chips de duración
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._durations.map((duration) {
                        final isSelected = !_isCustomTime && _selectedDuration == duration;
                        return ChoiceChip(
                          label: Text(_formatDuration(duration)),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedDuration = duration;
                                _isCustomTime = false;
                              });
                            }
                          },
                          backgroundColor: AppColors.surfaceVariant,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        );
                      }),
                      // Chip de tiempo personalizado
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit,
                              size: 16,
                              color: _isCustomTime ? Colors.white : AppColors.textPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(_isCustomTime && _customMinutesController.text.isNotEmpty
                                ? '${_customMinutesController.text}min'
                                : 'Custom'),
                          ],
                        ),
                        selected: _isCustomTime,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _isCustomTime = true);
                            _showCustomTimeDialog();
                          }
                        },
                        backgroundColor: AppColors.surfaceVariant,
                        selectedColor: AppColors.secondary,
                        labelStyle: TextStyle(
                          color: _isCustomTime ? Colors.white : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Tu sesión se bloqueará para ayudarte a concentrarte',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

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
                            'Cancelar',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Consumer<FocusProvider>(
                          builder: (context, focusProvider, child) {
                            return ElevatedButton(
                              onPressed: focusProvider.isCreatingRoom
                                  ? null
                                  : () => _createRoom(context),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: focusProvider.isCreatingRoom
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'Crear Sala',
                                      style: TextStyle(fontSize: 16),
                                    ),
                            );
                          },
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
    );
  }

  void _createRoom(BuildContext context) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, ingresa un nombre para la sala'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Validar tiempo personalizado
    if (_isCustomTime) {
      final customMinutes = int.tryParse(_customMinutesController.text);
      if (customMinutes == null || customMinutes <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, ingresa un tiempo válido'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      _selectedDuration = Duration(minutes: customMinutes);
    }

    final userProvider = context.read<UserProvider>();
    final focusProvider = context.read<FocusProvider>();

    // Crear usuario usando el avatar que el usuario ya eligió en su perfil
    // avatarId: 0 = default, 1 = 1.jpeg, 2 = 2.jpeg, etc.
    final avatarId = userProvider.avatarId;
    final String? avatarUrl;
    
    if (avatarId == 0) {
      // Si es el avatar por defecto (índice 0), no usar imagen
      avatarUrl = null;
    } else {
      // Mapear el índice a la imagen correspondiente (1 -> 1.jpeg, 2 -> 2.jpeg, etc.)
      avatarUrl = 'assets/images/$avatarId.jpeg';
    }
    
    final currentUser = FocusUser(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: userProvider.profile.name,
      avatarUrl: avatarUrl,
      joinedAt: DateTime.now(),
    );

    await focusProvider.createRoom(
      name: name,
      duration: _selectedDuration,
      creator: currentUser,
    );

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showCustomTimeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Tiempo Personalizado',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _customMinutesController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Minutos',
                hintText: 'Ej: 30',
                suffixText: 'min',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) {
                Navigator.of(context).pop();
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Ingresa entre 1 y 480 minutos (8 horas)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _customMinutesController.clear();
              setState(() => _isCustomTime = false);
              Navigator.of(context).pop();
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final minutes = int.tryParse(_customMinutesController.text);
              if (minutes != null && minutes > 0 && minutes <= 480) {
                _selectedDuration = Duration(minutes: minutes);
                Navigator.of(context).pop();
                setState(() {});
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor, ingresa un tiempo válido (1-480 min)'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
