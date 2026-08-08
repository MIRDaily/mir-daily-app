import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/models.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/versus_models.dart';
import '../services/versus_api.dart';

/// Configuración de la partida, solo para el anfitrión.
///
/// La lista de asignaturas es un catálogo compartido, no algo del simulacro:
/// se reutiliza su endpoint en vez de duplicarlo.
class VersusStartPanel extends StatefulWidget {
  /// Arranca la partida. El servidor anuncia el comienzo por el canal, así que
  /// la pantalla cambia sola al llegar el evento.
  final Future<int> Function({
    required List<int> subjectIds,
    required List<int> topicIds,
    required int count,
    String mode,
    int lives,
  }) onStart;

  /// Falso mientras no haya al menos dos jugadores en la sala.
  final bool canStart;

  const VersusStartPanel({
    super.key,
    required this.onStart,
    required this.canStart,
  });

  @override
  State<VersusStartPanel> createState() => _VersusStartPanelState();
}

class _VersusStartPanelState extends State<VersusStartPanel> {
  static const List<int> _counts = [5, 10, 15, 20];

  List<SimSubject> _subjects = const [];
  final Set<int> _selected = {};
  int _count = 10;
  String _mode = VersusMode.classic;
  int _lives = 1;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  /// Cuántas preguntas tiene cada asignatura. Se pide UNA vez: una pregunta
  /// pertenece a una sola asignatura, así que el fondo de una selección es la
  /// suma de las suyas y no hace falta volver a preguntar a cada toque.
  Map<int, int>? _fondo;

  Future<void> _loadSubjects() async {
    try {
      final api = context.read<ApiService>();
      final subjects = await api.getSimulacroSubjects();
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _loading = false;
      });

      // Que falle solo quita los recuentos; configurar la partida sigue yendo.
      final fondo =
          await VersusApi(api).pool(subjects.map((s) => s.id).toList());
      if (!mounted) return;
      setState(() => _fondo = fondo);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_subjects.isEmpty) _error = 'No se pudieron cargar las asignaturas.';
      });
    }
  }

  /// Preguntas disponibles con lo que hay marcado. Null mientras no se sepa.
  int? get _disponibles => _fondo == null
      ? null
      : _selected.fold<int>(0, (total, id) => total + (_fondo![id] ?? 0));

  /// Las que se jugarán de verdad: el servidor coge las que hay y se calla, así
  /// que pedir 20 sobre una asignatura de 5 daba una partida de 5 sin que nadie
  /// lo dijera.
  int get _seJugaran =>
      _disponibles == null ? _count : (_count < _disponibles! ? _count : _disponibles!);

  Future<void> _start() async {
    if (_selected.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onStart(
        subjectIds: _selected.toList(),
        topicIds: const [],
        count: _count,
        mode: _mode,
        lives: _lives,
      );
      // No se baja el flag al terminar bien: la sala pasa a 'question' y este
      // panel desaparece. Bajarlo solo dejaría el botón activo un frame.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is VersusException
            ? e.message
            : 'No se pudo empezar la partida.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONFIGURA LA PARTIDA',
            style: TextStyle(
              color: AppColors.textLight,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),

          // El modo se elige aquí y no al crear la sala, para poder cambiarlo
          // mientras la gente va entrando.
          const Text(
            'Modo',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.bolt_rounded,
                  title: 'Clásico',
                  subtitle: 'Acertar rápido puntúa más',
                  selected: _mode == VersusMode.classic,
                  onTap: () => setState(() => _mode = VersusMode.classic),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeCard(
                  icon: Icons.favorite_rounded,
                  title: 'Guardia',
                  subtitle: 'Quien falla, cae',
                  selected: _mode == VersusMode.survival,
                  onTap: () => setState(() => _mode = VersusMode.survival),
                ),
              ),
            ],
          ),

          if (_mode == VersusMode.survival) ...[
            const SizedBox(height: 18),
            const Text(
              'Vidas',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _LivesPicker(
              value: _lives,
              onChanged: (n) => setState(() => _lives = n),
            ),
          ],

          const SizedBox(height: 18),
          const Text(
            'Asignaturas',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.primary,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _subjects.map((subject) {
                final on = _selected.contains(subject.id);
                // Sin el recuento, el catálogo enseña por igual una asignatura
                // de 152 preguntas y otra de 1.
                final hay = _fondo?[subject.id];
                return _Chip(
                  label: hay == null ? subject.name : '${subject.name}  $hay',
                  selected: on,
                  onTap: hay == 0
                      ? null
                      : () => setState(() {
                            if (on) {
                              _selected.remove(subject.id);
                            } else {
                              _selected.add(subject.id);
                            }
                          }),
                );
              }).toList(),
            ),

          const SizedBox(height: 18),
          const Text(
            'Preguntas',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: _counts
                .map((value) => _Chip(
                      label: '$value',
                      selected: _count == value,
                      // Pedir mas de las que hay es legitimo ("todas las que
                      // haya"); lo que no vale es que nadie lo diga. Por eso se
                      // avisa debajo en vez de bloquearlo.
                      onTap: () => setState(() => _count = value),
                    ))
                .toList(),
          ),

          const SizedBox(height: 8),
          Text(
            _selected.isEmpty
                ? 'Elige alguna asignatura para ver cuántas preguntas hay.'
                : _disponibles == null
                    ? 'Contando las preguntas disponibles…'
                    : _disponibles! < _count
                        ? 'Solo hay ${_disponibles!} ${_disponibles == 1 ? "pregunta" : "preguntas"} '
                            'con esta selección, así que la partida será de $_seJugaran. '
                            'Marca más asignaturas si la quieres más larga.'
                        : 'Hay ${_disponibles!} disponibles: se jugarán $_seJugaran, al azar.',
            style: TextStyle(
              color: (_disponibles != null && _disponibles! < _count)
                  ? AppColors.error
                  : AppColors.textLight,
              fontSize: 12,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  widget.canStart && _selected.isNotEmpty && !_busy ? _start : null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: AppColors.surfaceVariant,
                disabledForegroundColor: AppColors.textLight,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                _busy
                    ? 'Empezando…'
                    : widget.canStart
                        ? 'Empezar partida'
                        : 'Falta gente para empezar',
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Vidas como corazones, igual que las estrellas de una valoración: se pulsa
/// el corazón que marca cuántas quieres y se rellenan todos los anteriores.
class _LivesPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _LivesPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int n = 1; n <= 5; n++)
          GestureDetector(
            onTap: () {
              HapticsService.light();
              onChanged(n);
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: AnimatedScale(
                // El último marcado da un respingo, para que se vea cuál manda.
                scale: n == value ? 1.18 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(
                  n <= value
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 32,
                  color: n <= value ? AppColors.error : AppColors.textLight,
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value == 1 ? 'Muerte súbita' : '$value vidas',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.primaryDark : AppColors.textLight,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color:
                    selected ? AppColors.primaryDark : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textLight,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;

  /// Null = no se puede elegir (una asignatura sin preguntas todavía).
  final VoidCallback? onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primaryDark : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
