import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/models.dart';
import '../../../shared/sticker/sticker.dart';
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

  /// Anuncia lo marcado al resto del lobby, para que no esperen a ciegas.
  final void Function(VersusLobbyDraft draft) onDraftChanged;

  const VersusStartPanel({
    super.key,
    required this.onStart,
    required this.canStart,
    required this.onDraftChanged,
  });

  @override
  State<VersusStartPanel> createState() => _VersusStartPanelState();
}

class _VersusStartPanelState extends State<VersusStartPanel> {
  static const List<int> _counts = [5, 10, 15, 20];

  List<SimSubject> _subjects = const [];
  final Set<int> _selected = {};
  int _count = 10;
  /// Sin preseleccionar a propósito: elegir modo es una decisión, no un valor
  /// por defecto que se acepta sin mirar.
  String? _mode;
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

  /// Cambia la configuración y la anuncia al resto del lobby, que si no se
  /// queda mirando un "esperando al anfitrión" sin saber a qué va a jugar.
  void _change(VoidCallback apply) {
    setState(apply);
    widget.onDraftChanged(VersusLobbyDraft(
      mode: _mode,
      lives: _lives,
      count: _count,
      // Van los NOMBRES, no los ids: el resto no tiene por qué haber cargado el
      // catálogo de asignaturas.
      subjects: _subjects
          .where((s) => _selected.contains(s.id))
          .map((s) => s.name)
          .toList(),
    ));
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

  /// No se puede empezar sin elegir modo ni asignaturas.
  bool get _listo => _mode != null && _selected.isNotEmpty;

  Future<void> _start() async {
    final mode = _mode;
    if (mode == null || _selected.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onStart(
        subjectIds: _selected.toList(),
        topicIds: const [],
        count: _count,
        mode: mode,
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
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Configura la partida'),

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
          _ModeCard(
            icon: Icons.bolt_rounded,
            title: 'Clásico',
            subtitle: 'Acertar y ser rápido. Gana quien más puntúa.',
            selected: _mode == VersusMode.classic,
            onTap: () => _change(() => _mode = VersusMode.classic),
          ),
          const SizedBox(height: 8),
          _ModeCard(
            icon: Icons.trending_up_rounded,
            title: 'Número de orden',
            subtitle: 'Como el MIR: +3 acertar, −1 fallar. Sin premio a la '
                'velocidad.',
            selected: _mode == VersusMode.mirRank,
            onTap: () => _change(() => _mode = VersusMode.mirRank),
          ),
          const SizedBox(height: 8),
          _ModeCard(
            icon: Icons.favorite_rounded,
            title: 'Guardia',
            subtitle: 'Quien falla pierde una vida. El último en pie gana.',
            selected: _mode == VersusMode.survival,
            onTap: () => _change(() => _mode = VersusMode.survival),
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
              onChanged: (n) => _change(() => _lives = n),
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
                      : () => _change(() {
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
                      onTap: () => _change(() => _count = value),
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
              onPressed: widget.canStart && _listo && !_busy ? _start : null,
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
                    : !widget.canStart
                        ? 'Falta gente para empezar'
                        // Se dice QUÉ falta, en vez de dejar un botón apagado
                        // sin explicación.
                        : _mode == null
                            ? 'Elige un modo'
                            : _selected.isEmpty
                                ? 'Elige alguna asignatura'
                                : 'Empezar partida',
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
          color: selected ? tinted(AppColors.primary, 0.20) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? kInk : kHairline,
            width: 2,
          ),
          boxShadow: selected ? inkShadow(3) : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: selected ? kInk : kHairline, width: 2),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : kMuted,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? kInk : kMuted,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: kMuted,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
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
            color: selected ? kInk : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? kInk : kHairline, width: 2),
            boxShadow: selected ? inkShadow(2) : const [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : kMuted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
