import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/responsive/adaptive_modal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/simulacro/widgets/count_slider.dart';
import '../../../shared/sticker/sticker.dart';

/// Lo que el usuario elige antes de empezar a estudiar un mazo.
///
/// Los tres filtros los aplica el backend en CADA petición de carta
/// (`GET /decks/:id/next?subject=&status=&mode=`), no al crear la sesión, así
/// que viajan juntos durante toda la sesión.
class DeckStudyOptions {
  final int limit;

  /// 'normal' (orden aleatorio dentro de lo filtrado) o 'smart' (Smart Review:
  /// puntúa por debilidad de tema, dificultad personal y retraso del repaso).
  final String mode;

  final int? subjectId;

  /// null | new | failed | learning | mastered.
  ///
  /// Siempre null en modo Smart: la función del servidor
  /// (`get_next_session_item`) sencillamente NO mira `p_status` cuando
  /// `p_mode='smart'` — su elegibilidad es "nueva o vencida" y el orden lo
  /// decide su propia puntuación. Mandarlo sería pedir algo que no se cumple.
  final String? status;

  const DeckStudyOptions({
    required this.limit,
    this.mode = 'normal',
    this.subjectId,
    this.status,
  });
}

const List<({String value, String label, Color color})> kDeckStatusOptions = [
  (value: 'new', label: 'Nuevas', color: Color(0xFF5D7A93)),
  (value: 'failed', label: 'Falladas', color: Color(0xFFC4655A)),
  (value: 'learning', label: 'En aprendizaje', color: Color(0xFFB4831F)),
  (value: 'mastered', label: 'Dominadas', color: Color(0xFF5C7A59)),
];

/// Hoja de "Estudiar": modo, filtros y cuántas cartas.
///
/// Sustituye al desplegable anterior, que ofrecía siempre `[10, 20, total]` sin
/// mirar el total: en un mazo de 2 preguntas salían tres opciones idénticas
/// ("Todas (2)" tres veces), porque tanto 10 como 20 como 2 son ">= total".
Future<DeckStudyOptions?> showDeckStudySheet({
  required BuildContext context,
  required int totalItems,
  required List<DeckSubject> subjects,
  required DeckSummary? summary,
}) {
  return showAdaptiveModal<DeckStudyOptions>(
    context: context,
    dialogMaxWidth: 520,
    builder: (ctx) => _StudySheet(
      totalItems: totalItems,
      subjects: subjects,
      summary: summary,
    ),
  );
}

class _StudySheet extends StatefulWidget {
  final int totalItems;
  final List<DeckSubject> subjects;
  final DeckSummary? summary;

  const _StudySheet({
    required this.totalItems,
    required this.subjects,
    required this.summary,
  });

  @override
  State<_StudySheet> createState() => _StudySheetState();
}

class _StudySheetState extends State<_StudySheet> {
  /// Tope de cartas por sesión que impone el backend (`MAX_SESSION_LIMIT` en
  /// `src/routes/studio.js`): pedir más devuelve 400.
  static const int _maxSessionLimit = 200;

  String _mode = 'normal';
  int? _subjectId;
  String? _status;

  bool get _isSmart => _mode == 'smart';

  int get _maxLimit => widget.totalItems.clamp(1, _maxSessionLimit);

  late int _limit = _maxLimit;

  /// Atajos, solo los que caben en el mazo. El deslizador cubre el resto: de
  /// 1 hasta el total, sin escalones.
  List<int> get _shortcuts => [
        for (final n in const [5, 10, 20, 50, 100])
          if (n < _maxLimit) n,
        _maxLimit,
      ];

  void _setLimit(int value) =>
      setState(() => _limit = value.clamp(1, _maxLimit));

  /// Cuántas cartas hay realmente detrás de cada estado, para no ofrecer un
  /// filtro que deja la sesión vacía.
  int _statusCount(String value) {
    final s = widget.summary;
    if (s == null) return 1;
    switch (value) {
      case 'new':
        return s.newCount;
      case 'failed':
        return s.failed;
      case 'learning':
        return s.learning;
      default:
        return s.mastered;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Empezar a estudiar',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 18),
              const _SheetLabel('Modo'),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      title: 'Normal',
                      subtitle: 'Orden aleatorio de lo que toque repasar.',
                      icon: Icons.shuffle_rounded,
                      selected: _mode == 'normal',
                      onTap: () => setState(() => _mode = 'normal'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeCard(
                      title: 'Smart Review',
                      subtitle: 'Prioriza lo más débil y lo más atrasado.',
                      icon: Icons.auto_awesome_rounded,
                      selected: _isSmart,
                      // Se limpia el estado al entrar en Smart: si no, quedaría
                      // marcado un filtro que después no se aplica.
                      onTap: () => setState(() {
                        _mode = 'smart';
                        _status = null;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _isSmart
                    ? 'El motor decide qué repasar primero: lo que fallas, lo '
                        'que se te resiste y lo que ya tocaba revisar. Solo '
                        'sirve cartas nuevas o vencidas, así que la sesión '
                        'puede acabar antes del número que elijas.'
                    : 'Tú eliges qué repasar; dentro de eso, el orden es '
                        'aleatorio.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              // En Smart el estado no se puede elegir porque el servidor no lo
              // mira: `get_next_session_item` ignora `p_status` en ese modo.
              // Dejarlo activo sería ofrecer un filtro que no se cumple.
              Row(
                children: [
                  const _SheetLabel('Estado'),
                  if (_isSmart) ...[
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 9),
                      child: Text(
                        'lo decide el motor',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Opacity(
                opacity: _isSmart ? 0.4 : 1,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'Todas',
                      selected: _status == null,
                      enabled: !_isSmart,
                      onTap: () => setState(() => _status = null),
                    ),
                    for (final option in kDeckStatusOptions)
                      _FilterChip(
                        label:
                            '${option.label} (${_statusCount(option.value)})',
                        color: option.color,
                        selected: _status == option.value,
                        enabled: !_isSmart && _statusCount(option.value) > 0,
                        onTap: () => setState(() => _status = option.value),
                      ),
                  ],
                ),
              ),
              if (widget.subjects.length > 1) ...[
                const SizedBox(height: 18),
                const _SheetLabel('Asignatura'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'Todas',
                      selected: _subjectId == null,
                      onTap: () => setState(() => _subjectId = null),
                    ),
                    for (final s in widget.subjects)
                      _FilterChip(
                        label: '${s.subject} (${s.count})',
                        selected: _subjectId == s.subjectId,
                        onTap: () => setState(() => _subjectId = s.subjectId),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              const _SheetLabel('Cuántas cartas'),
              Row(
                children: [
                  _StepButton(
                    icon: Icons.remove_rounded,
                    onTap: _limit > 1 ? () => _setLimit(_limit - 1) : null,
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            '$_limit',
                            style: const TextStyle(
                              color: kInk,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _limit == _maxLimit
                                ? 'todas las del mazo'
                                : 'de $_maxLimit',
                            style: const TextStyle(
                              color: AppColors.textLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add_rounded,
                    onTap:
                        _limit < _maxLimit ? () => _setLimit(_limit + 1) : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Deslizador con muelle, el mismo del creador de simulacros: con
              // mazos de cientos de cartas, llegar a golpe de botón sería
              // absurdo, y los atajos no cubren los valores intermedios.
              if (_maxLimit > 1)
                CountSlider(
                  value: _limit,
                  max: _maxLimit,
                  onChanged: _setLimit,
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in _shortcuts)
                    _FilterChip(
                      label: n >= _maxLimit ? 'Todas ($n)' : '$n',
                      selected: _limit == n,
                      onTap: () => _setLimit(n),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              StickerButton(
                label: 'Empezar',
                icon: Icons.play_arrow_rounded,
                expand: true,
                onPressed: () => Navigator.pop(
                  context,
                  DeckStudyOptions(
                    limit: _limit,
                    mode: _mode,
                    subjectId: _subjectId,
                    // Red de seguridad: aunque la interfaz ya lo apaga, en
                    // Smart nunca se manda estado. El servidor lo ignoraría,
                    // pero mandarlo dejaría un rastro enganoso en la sesion.
                    status: _isSmart ? null : _status,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;

  const _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: kMuted,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
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
          color: selected ? tinted(AppColors.primary, 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? kInk : kHairline, width: 2),
          boxShadow: selected ? inkShadow(3) : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: selected ? kInk : kMuted),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: kInk,
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.primaryDark;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? tinted(accent, 0.20) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? kInk : kHairline, width: 2),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? kInk : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo de -1 / +1 del contador de cartas.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kInk, width: 2),
            boxShadow: enabled ? inkShadow(3) : const [],
          ),
          child: Icon(icon, size: 20, color: kInk),
        ),
      ),
    );
  }
}
