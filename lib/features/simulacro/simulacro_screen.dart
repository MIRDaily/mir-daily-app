import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/zoomable_image.dart';

/// Creador de simulacros — réplica de la web (/studio/simulacro). Orquesta las
/// fases builder → running → results contra el backend (/api/simulacro/*): las
/// preguntas llegan SIN la respuesta correcta y la corrección la valida el
/// servidor en /check (inmediata por pregunta o diferida al final).
class SimulacroScreen extends StatefulWidget {
  const SimulacroScreen({super.key});

  @override
  State<SimulacroScreen> createState() => _SimulacroScreenState();
}

class _SimulacroScreenState extends State<SimulacroScreen> {
  String _phase = 'builder'; // builder | running | results
  String _mode = 'immediate'; // immediate | deferred
  String _layout = 'classic'; // classic | carousel
  bool _showSubject = true; // mostrar la asignatura en el enunciado
  List<SimQuestion> _questions = [];
  List<int?> _answers = [];
  List<SimResult?> _results = [];
  bool _generating = false;
  String? _generationError;
  bool _finishing = false;

  /// Id de la sesión de simulacro (uuid). Se envía a /check para que el backend
  /// registre cada respuesta como pregunta hecha por el usuario.
  String? _sessionId;

  ApiService get _api => context.read<ApiService>();

  /// UUID v4 válido (formato que exige el backend).
  static String _genSessionId() {
    final r = Random();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _handleSubmit({
    required List<int> subjectIds,
    required List<int> topicIds,
    required int count,
    required String mode,
    required String layout,
    required bool showSubject,
  }) async {
    setState(() {
      _generating = true;
      _generationError = null;
      _layout = layout;
      _showSubject = showSubject;
    });
    try {
      final fetched = await _api.getSimulacroQuestions(
        subjectIds: subjectIds,
        topicIds: topicIds,
        count: count,
      );
      if (!mounted) return;
      if (fetched.isEmpty) {
        setState(() => _generationError =
            'No se encontraron preguntas con esa selección. Prueba con otras asignaturas o temas.');
        return;
      }
      setState(() {
        _questions = fetched;
        _answers = List<int?>.filled(fetched.length, null);
        _results = List<SimResult?>.filled(fetched.length, null);
        _mode = mode;
        _sessionId = _genSessionId();
        _phase = 'running';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generationError =
          'No se pudieron cargar las preguntas: ${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _handleSelect(int qIndex, int optIndex) {
    setState(() => _answers[qIndex] = optIndex);
    if (_mode == 'immediate') {
      final q = _questions[qIndex];
      _api.checkSimulacro([
        {'questionId': q.id, 'selectedIndex': optIndex}
      ], sessionId: _sessionId).then((res) {
        if (!mounted || res.isEmpty) return;
        setState(() => _results[qIndex] = res.first);
      }).catchError((_) {});
    }
  }

  /// Dejar la pregunta en blanco (no puntúa ni penaliza, pero se registra).
  /// Se usa -1 como centinela de "en blanco" en [_answers].
  void _handleBlank(int qIndex) {
    setState(() => _answers[qIndex] = -1);
    if (_mode == 'immediate') {
      final q = _questions[qIndex];
      _api.checkSimulacro([
        {'questionId': q.id, 'selectedIndex': null}
      ], sessionId: _sessionId).then((res) {
        if (!mounted || res.isEmpty) return;
        setState(() => _results[qIndex] = res.first);
      }).catchError((_) {});
    }
  }

  Future<void> _handleFinish() async {
    if (_mode == 'deferred') {
      setState(() => _finishing = true);
      try {
        final payload = [
          for (var i = 0; i < _questions.length; i++)
            {
              'questionId': _questions[i].id,
              // -1 (o sin responder) => en blanco (null) para el backend.
              'selectedIndex':
                  (_answers[i] == null || _answers[i]! < 0) ? null : _answers[i],
            }
        ];
        final res = await _api.checkSimulacro(payload, sessionId: _sessionId);
        final byId = {for (final r in res) r.questionId: r};
        if (mounted) {
          setState(() =>
              _results = [for (final q in _questions) byId[q.id]]);
        }
      } catch (_) {
        // Mostramos la rejilla igualmente (sin corrección).
      } finally {
        if (mounted) setState(() => _finishing = false);
      }
    }
    if (mounted) setState(() => _phase = 'results');
  }

  void _handleRestart() {
    setState(() {
      _questions = [];
      _answers = [];
      _results = [];
      _generationError = null;
      _finishing = false;
      _phase = 'builder';
    });
  }

  /// Insignia del modo de corrección (va en el AppBar durante el test).
  Widget _modeBadge() {
    final immediate = _mode == 'immediate';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(immediate ? Icons.bolt_rounded : Icons.flag_rounded,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            immediate ? 'Inmediata' : 'Al final',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Runner según el modo de visualización elegido (clásico o carrusel).
  Widget _runner() {
    if (_layout == 'carousel') {
      return _SimRunnerCarousel(
        questions: _questions,
        mode: _mode,
        showSubject: _showSubject,
        answers: _answers,
        results: _results,
        finishing: _finishing,
        onSelect: _handleSelect,
        onBlank: _handleBlank,
        onFinish: _handleFinish,
        onExit: _exitRunning,
      );
    }
    return _SimRunnerClassic(
      questions: _questions,
      mode: _mode,
      showSubject: _showSubject,
      answers: _answers,
      results: _results,
      finishing: _finishing,
      onSelect: _handleSelect,
      onBlank: _handleBlank,
      onFinish: _handleFinish,
      onExit: _exitRunning,
    );
  }

  /// Aviso de salida durante el test (por si fue un despiste). Devuelve true
  /// si el usuario confirma salir.
  Future<bool> _confirmExit() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Salir del simulacro?'),
        content: const Text(
          'Perderás el progreso de este test. ¿Seguro que quieres salir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir en el test'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _exitRunning() async {
    if (await _confirmExit()) _handleRestart();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != 'running',
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && mounted) _handleRestart();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          title: const Text('Simulacro'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (_phase == 'builder') {
                Navigator.of(context).pop();
              } else if (_phase == 'running') {
                if (await _confirmExit()) _handleRestart();
              } else {
                _handleRestart();
              }
            },
          ),
          actions: [
            if (_phase == 'running')
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Center(child: _modeBadge()),
              ),
          ],
        ),
        body: switch (_phase) {
          'running' => _runner(),
        'results' => _SimResults(
            questions: _questions,
            answers: _answers,
            results: _results,
            onRestart: _handleRestart,
            onClose: () => Navigator.of(context).pop(),
          ),
        _ => _SimBuilder(
            generating: _generating,
            generationError: _generationError,
            onSubmit: _handleSubmit,
          ),
        },
      ),
    );
  }
}

// ==========================
// FASE 1 — BUILDER
// ==========================

class _SimBuilder extends StatefulWidget {
  final bool generating;
  final String? generationError;
  final void Function({
    required List<int> subjectIds,
    required List<int> topicIds,
    required int count,
    required String mode,
    required String layout,
    required bool showSubject,
  }) onSubmit;

  const _SimBuilder({
    required this.generating,
    required this.generationError,
    required this.onSubmit,
  });

  @override
  State<_SimBuilder> createState() => _SimBuilderState();
}

class _SimBuilderState extends State<_SimBuilder> {
  List<SimSubject> _subjects = [];
  bool _loadingSubjects = true;
  String? _subjectsError;

  List<SimTopic> _topics = [];
  bool _loadingTopics = false;

  final List<int> _selectedSubjectIds = [];
  final Set<int> _selectedTopicIds = {};
  int _count = 10;
  String _mode = 'immediate';

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final data = await _api.getSimulacroSubjects();
      if (!mounted) return;
      setState(() {
        _subjects = data;
        _subjectsError = null;
        _loadingSubjects = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subjectsError = e is ApiException
            ? e.message
            : 'No se pudieron cargar las asignaturas.';
        _loadingSubjects = false;
      });
    }
  }

  Future<void> _reloadTopics() async {
    if (_selectedSubjectIds.isEmpty) {
      setState(() {
        _topics = [];
        _selectedTopicIds.clear();
      });
      return;
    }
    setState(() => _loadingTopics = true);
    try {
      final data = await _api.getSimulacroTopics(_selectedSubjectIds);
      if (!mounted) return;
      final valid = data.map((t) => t.id).toSet();
      setState(() {
        _topics = data;
        _selectedTopicIds.removeWhere((id) => !valid.contains(id));
        _loadingTopics = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _topics = [];
        _loadingTopics = false;
      });
    }
  }

  void _toggleSubject(int id) {
    setState(() {
      if (_selectedSubjectIds.contains(id)) {
        _selectedSubjectIds.remove(id);
      } else {
        _selectedSubjectIds.add(id);
      }
    });
    _reloadTopics();
  }

  Future<void> _openTopicPicker() async {
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TopicPickerSheet(
        subjects: _subjects,
        selectedSubjectIds: _selectedSubjectIds,
        topics: _topics,
        initialSelected: _selectedTopicIds,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedTopicIds
          ..clear()
          ..addAll(result);
      });
    }
  }

  /// Al generar: primero el popup gráfico para elegir el modo de visualización
  /// (clásico o deslizar) y, con la elección, se lanza el simulacro.
  Future<void> _onGenerate() async {
    final choice = await showDialog<(String, bool)>(
      context: context,
      builder: (_) => const _LayoutPickerDialog(),
    );
    if (choice == null || !mounted) return;
    widget.onSubmit(
      subjectIds: List<int>.from(_selectedSubjectIds),
      topicIds: _selectedTopicIds.toList(),
      count: _count,
      mode: _mode,
      layout: choice.$1,
      showSubject: choice.$2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _selectedSubjectIds.isNotEmpty &&
        _count >= 1 &&
        !widget.generating;
    final selectedTopics =
        _topics.where((t) => _selectedTopicIds.contains(t.id)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        const Text(
          'Diseña tu simulacro',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Elige asignaturas y temas, cuántas preguntas quieres y cómo corregirlo.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 22),

        // Paso 1 — Asignaturas
        _section(
          n: '1',
          title: 'Asignaturas',
          child: _loadingSubjects
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary)),
                )
              : _subjectsError != null
                  ? Text(_subjectsError!,
                      style: const TextStyle(color: AppColors.error))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _subjects.map((s) {
                        final active = _selectedSubjectIds.contains(s.id);
                        return _chip(
                          label: s.name,
                          active: active,
                          onTap: () => _toggleSubject(s.id),
                        );
                      }).toList(),
                    ),
        ),
        const SizedBox(height: 14),

        // Paso 2 — Temas
        _section(
          n: '2',
          title: 'Temas',
          subtitle:
              'Opcional. Si no eliges ninguno, se incluyen todos los temas de las asignaturas seleccionadas.',
          child: _selectedSubjectIds.isEmpty
              ? const Text(
                  'Selecciona una asignatura para ver sus temas.',
                  style: TextStyle(color: AppColors.textLight, fontSize: 13.5),
                )
              : _loadingTopics
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2.4))),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedTopics.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.border,
                                  style: BorderStyle.solid),
                            ),
                            child: const Text(
                              'Ahora mismo se incluirán todos los temas de las asignaturas elegidas.',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in selectedTopics.take(8))
                                _topicChip(t),
                              if (selectedTopics.length > 8)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '+${selectedTopics.length - 8} más',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openTopicPicker,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(selectedTopics.isEmpty
                              ? 'Elegir temas concretos'
                              : 'Editar temas'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryDark,
                            side: BorderSide(
                                color: AppColors.primary
                                    .withValues(alpha: 0.4)),
                          ),
                        ),
                      ],
                    ),
        ),
        const SizedBox(height: 14),

        // Paso 3 — Nº de preguntas
        _section(
          n: '3',
          title: 'Nº de preguntas',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _stepperBtn(Icons.remove_rounded,
                      () => setState(() => _count = (_count - 1).clamp(1, 200))),
                  Container(
                    width: 56,
                    alignment: Alignment.center,
                    child: Text(
                      '$_count',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _stepperBtn(Icons.add_rounded,
                      () => setState(() => _count = (_count + 1).clamp(1, 200))),
                  const SizedBox(width: 12),
                  for (final p in [5, 10, 20, 50])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _presetBtn(p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Si hay menos preguntas disponibles que las pedidas, se usarán las que haya.',
                style: TextStyle(color: AppColors.textLight, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Paso 4 — Modo
        _section(
          n: '4',
          title: 'Modo de corrección',
          child: Column(
            children: [
              _modeCard(
                value: 'immediate',
                icon: Icons.bolt_rounded,
                title: 'Corrección inmediata',
                desc: 'Ves si aciertas y la explicación justo al responder.',
              ),
              const SizedBox(height: 10),
              _modeCard(
                value: 'deferred',
                icon: Icons.flag_rounded,
                title: 'Corrección al final',
                desc: 'Sin pistas durante el test; repasas todo al terminar.',
              ),
            ],
          ),
        ),

        if (widget.generationError != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F6),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Text(
              widget.generationError!,
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w600),
            ),
          ),
        ],

        const SizedBox(height: 22),
        Pressable(
          onTap: canSubmit ? _onGenerate : null,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: canSubmit ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(16),
            ),
            child: widget.generating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.6),
                  )
                : Text(
                    'Generar simulacro',
                    style: TextStyle(
                      color: canSubmit ? Colors.white : AppColors.textLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _section({
    required String n,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Text(n,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      fontSize: 16)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle,
                style: const TextStyle(
                    color: AppColors.textLight, fontSize: 12, height: 1.4)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _chip(
      {required String label,
      required bool active,
      required VoidCallback onTap}) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: active ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _topicChip(SimTopic t) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.name,
              style: const TextStyle(
                  color: AppColors.successDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () => setState(() => _selectedTopicIds.remove(t.id)),
            child: const Icon(Icons.close_rounded,
                size: 16, color: AppColors.successDark),
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback onTap) {
    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 20),
      ),
    );
  }

  Widget _presetBtn(int p) {
    final active = _count == p;
    return Pressable(
      onTap: () => setState(() => _count = p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          '$p',
          style: TextStyle(
            color: active ? AppColors.primaryDark : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required String value,
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final active = _mode == value;
    return Pressable(
      onTap: () => setState(() => _mode = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFF0EC) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: active ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon,
                  color: active ? Colors.white : AppColors.textSecondary,
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector de temas (modal). Agrupa por asignatura con seleccionar todo.
class _TopicPickerSheet extends StatefulWidget {
  final List<SimSubject> subjects;
  final List<int> selectedSubjectIds;
  final List<SimTopic> topics;
  final Set<int> initialSelected;

  const _TopicPickerSheet({
    required this.subjects,
    required this.selectedSubjectIds,
    required this.topics,
    required this.initialSelected,
  });

  @override
  State<_TopicPickerSheet> createState() => _TopicPickerSheetState();
}

class _TopicPickerSheetState extends State<_TopicPickerSheet> {
  late final Set<int> _sel = {...widget.initialSelected};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Elegir temas',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  TextButton(
                    onPressed: () => setState(_sel.clear),
                    child: const Text('Quitar todos'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  for (final subjectId in widget.selectedSubjectIds)
                    _group(subjectId),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context, _sel),
                    child: Text('Aplicar (${_sel.length})'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _group(int subjectId) {
    final subject = widget.subjects
        .where((s) => s.id == subjectId)
        .map((s) => s.name)
        .firstOrNull;
    final items =
        widget.topics.where((t) => t.subjectId == subjectId).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final allSelected = items.every((t) => _sel.contains(t.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  subject ?? 'Asignatura',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      fontSize: 14.5),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _sel.removeAll(items.map((t) => t.id));
                  } else {
                    _sel.addAll(items.map((t) => t.id));
                  }
                }),
                child: Text(allSelected ? 'Ninguno' : 'Todos'),
              ),
            ],
          ),
        ),
        ...items.map((t) {
          final on = _sel.contains(t.id);
          return CheckboxListTile(
            value: on,
            onChanged: (_) => setState(() {
              if (on) {
                _sel.remove(t.id);
              } else {
                _sel.add(t.id);
              }
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
            title: Text(t.name,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14)),
          );
        }),
      ],
    );
  }
}

// ==========================
// FASE 2 — RUNNER (carrusel: enunciado → imagen → opciones → corrección)
// ==========================

class _SimRunnerCarousel extends StatefulWidget {
  final List<SimQuestion> questions;
  final String mode;
  final bool showSubject;
  final List<int?> answers;
  final List<SimResult?> results;
  final bool finishing;
  final void Function(int qIndex, int optIndex) onSelect;
  final void Function(int qIndex) onBlank;
  final VoidCallback onFinish;
  final VoidCallback onExit;

  const _SimRunnerCarousel({
    required this.questions,
    required this.mode,
    required this.showSubject,
    required this.answers,
    required this.results,
    required this.finishing,
    required this.onSelect,
    required this.onBlank,
    required this.onFinish,
    required this.onExit,
  });

  @override
  State<_SimRunnerCarousel> createState() => _SimRunnerCarouselState();
}

class _SimRunnerCarouselState extends State<_SimRunnerCarousel>
    with SingleTickerProviderStateMixin {
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];
  static const _highlightColor = Color(0xFFFFE082);

  int _index = 0;
  int _page = 0;
  late final PageController _carousel;

  // Subrayado del enunciado: índices de palabras marcadas. EFÍMERO: se borra
  // al cambiar de pregunta (no se guarda).
  final Set<int> _highlighted = {};

  // Preguntas a cuya corrección ya hicimos auto-slide (para no repetir).
  final Set<int> _autoSlid = {};

  // Pista de subrayado: parpadeo suave; solo 5 s en la primera pregunta.
  late final AnimationController _hintBlink;
  Timer? _hintTimer;
  bool _showHlHint = true;

  @override
  void initState() {
    super.initState();
    _carousel = PageController();
    _hintBlink = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHlHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _hintBlink.dispose();
    _carousel.dispose();
    super.dispose();
  }

  void _goToQuestion(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.questions.length) return;
    setState(() {
      _index = newIndex;
      _page = 0;
      _highlighted.clear(); // el subrayado no se conserva entre preguntas
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_carousel.hasClients) _carousel.jumpToPage(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.questions.length;
    final q = widget.questions[_index];
    final selected = widget.answers[_index];
    final result = widget.results[_index];
    final correctIndex = result?.correctIndex ?? -1;
    final isLast = _index == total - 1;
    final immediate = widget.mode == 'immediate';
    final revealed = immediate && selected != null && result != null;
    final checking = immediate && selected != null && result == null;
    final hasImage = q.hasImage && q.imageUrl != null;

    // Páginas del carrusel
    final pages = <Widget>[
      _statementPage(q),
      if (hasImage) _imagePage(q),
      _optionsPage(q, selected, revealed, checking, correctIndex),
      if (revealed) _correctionPage(q, result, correctIndex),
    ];

    // Auto-slide a la corrección cuando se revela (modo inmediato).
    if (revealed && !_autoSlid.contains(_index)) {
      _autoSlid.add(_index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_carousel.hasClients) {
          _carousel.animateToPage(
            pages.length - 1,
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }

    return Column(
      children: [
        _progress(total),
        Expanded(
          child: PageView(
            controller: _carousel,
            onPageChanged: (p) => setState(() => _page = p),
            children: pages,
          ),
        ),
        _dots(pages.length),
        _bottomBar(selected, isLast),
      ],
    );
  }

  // ---- PROGRESO (compacto: barra + "n de N" en una fila) ----
  Widget _progress(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (_index + 1) / total,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('${_index + 1} de $total',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5)),
        ],
      ),
    );
  }

  // ---- PUNTOS DEL CARRUSEL ----
  Widget _dots(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _page == i ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _page == i ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
        ],
      ),
    );
  }

  // ---- CONTENEDOR DE PÁGINA ----
  Widget _pageShell({
    required String label,
    required IconData icon,
    Widget? trailing,
    required Widget child,
    bool scroll = true,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textSecondary.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.2)),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: scroll
                  ? SingleChildScrollView(child: child)
                  : child,
            ),
          ],
        ),
      ),
    );
  }

  // ---- PÁGINA 1: ENUNCIADO (con subrayado) ----
  Widget _statementPage(SimQuestion q) {
    final words = q.statement.trim().split(RegExp(r'\s+'));
    return _pageShell(
      label: 'ENUNCIADO',
      icon: Icons.article_rounded,
      trailing: _highlighted.isEmpty
          ? null
          : GestureDetector(
              onTap: () => setState(_highlighted.clear),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.format_clear_rounded,
                      size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text('Limpiar',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ],
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showSubject && q.subject != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(q.subject!.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      letterSpacing: 0.6)),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 5,
            runSpacing: 8,
            children: [
              for (var i = 0; i < words.length; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    if (!_highlighted.remove(i)) _highlighted.add(i);
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 1.5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _highlighted.contains(i)
                          ? _highlightColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      words[i],
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Pistas solo en la PRIMERA pregunta del simulacro.
          if (_index == 0) ...[
            const SizedBox(height: 22),
            // Subrayado: parpadeo suave durante 5 s.
            if (_showHlHint) ...[
              AnimatedBuilder(
                animation: _hintBlink,
                builder: (context, child) => Opacity(
                  opacity: 0.35 + 0.65 * _hintBlink.value,
                  child: child,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.touch_app_outlined,
                        size: 15, color: AppColors.textLight),
                    SizedBox(width: 6),
                    Text('Toca las palabras para subrayar',
                        style: TextStyle(
                            color: AppColors.textLight, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Pista de deslizar: mano animada con estela.
            const _SwipeHandHint(),
          ],
        ],
      ),
    );
  }

  // ---- PÁGINA 2: IMAGEN ----
  Widget _imagePage(SimQuestion q) {
    return _pageShell(
      label: 'IMAGEN',
      icon: Icons.image_rounded,
      scroll: false,
      child: ZoomableImage(
        url: q.imageUrl!,
        fit: BoxFit.contain,
        expand: true,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  // ---- PÁGINA 3: OPCIONES ----
  Widget _optionsPage(SimQuestion q, int? selected, bool revealed,
      bool checking, int correctIndex) {
    final locked = widget.mode == 'immediate' && selected != null;
    return _pageShell(
      label: 'OPCIONES',
      icon: Icons.checklist_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...List.generate(q.options.length, (i) {
            final isSelected = selected == i;
            final isCorrect = i == correctIndex;

            Color border = AppColors.border;
            Color bg = Colors.white;
            Color circleBorder = const Color(0xFFD8D2CE);
            Color circleBg = Colors.transparent;
            Widget? circleChild;

            if (revealed) {
              if (isCorrect) {
                border = AppColors.success;
                bg = AppColors.success.withValues(alpha: 0.10);
                circleBorder = AppColors.success;
                circleBg = AppColors.success;
                circleChild = const Icon(Icons.check_rounded,
                    color: Colors.white, size: 16);
              } else if (isSelected) {
                border = AppColors.error;
                bg = const Color(0xFFFFF1EC);
                circleBorder = AppColors.error;
                circleBg = AppColors.error;
                circleChild =
                    const Icon(Icons.close_rounded, color: Colors.white, size: 16);
              }
            } else if (isSelected) {
              border = AppColors.primary;
              circleBorder = AppColors.primary;
              circleBg = AppColors.primary;
              circleChild = const Icon(Icons.check_rounded,
                  color: Colors.white, size: 16);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Pressable(
                onTap: locked ? null : () => widget.onSelect(_index, i),
                pressedScale: 0.98,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border, width: 2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: circleBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: circleBorder, width: 2),
                        ),
                        child: circleChild ??
                            Text(
                              _letters[i],
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12),
                            ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            q.options[i],
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          _blankButton(selected),
          if (checking) ...[
            const SizedBox(height: 4),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Comprobando tu respuesta...',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Botón "Dejar en blanco" (no puntúa ni penaliza; se registra igual).
  Widget _blankButton(int? selected) {
    final isBlank = selected == -1;
    final locked = widget.mode == 'immediate' && selected != null;
    if (locked && !isBlank) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Pressable(
        onTap: locked ? null : () => widget.onBlank(_index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isBlank
                ? AppColors.textSecondary.withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isBlank ? AppColors.textSecondary : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isBlank ? Icons.check_circle_rounded : Icons.block_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                isBlank ? 'En blanco · no puntúa ni penaliza' : 'Dejar en blanco',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- PÁGINA 4: CORRECCIÓN (aparece a la derecha tras responder) ----
  Widget _correctionPage(SimQuestion q, SimResult result, int correctIndex) {
    final correct = result.isCorrect;
    final blank = result.isBlank;
    final exp = result.explanation?.trim() ?? '';
    final letter = (correctIndex >= 0 && correctIndex < _letters.length)
        ? _letters[correctIndex]
        : '?';
    final headColor = blank
        ? AppColors.textSecondary
        : (correct ? AppColors.success : AppColors.error);
    final headIcon = blank
        ? Icons.block_rounded
        : (correct ? Icons.check_rounded : Icons.close_rounded);
    final headText = blank
        ? 'En blanco'
        : (correct ? '¡Correcto!' : 'Incorrecto');
    return _pageShell(
      label: 'CORRECCIÓN',
      icon: Icons.lightbulb_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: headColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(headIcon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                headText,
                style: TextStyle(
                  color: blank
                      ? AppColors.textSecondary
                      : (correct ? AppColors.successDark : AppColors.error),
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, height: 1.4),
                children: [
                  const TextSpan(
                      text: 'Respuesta correcta: ',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                    text: '$letter) ',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.successDark),
                  ),
                  TextSpan(
                    text: (correctIndex >= 0 &&
                            correctIndex < q.options.length)
                        ? q.options[correctIndex]
                        : '',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('EXPLICACIÓN',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(
            exp.isNotEmpty
                ? exp
                : 'No hay explicación disponible para esta pregunta.',
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ---- BARRA INFERIOR: navegación entre preguntas ----
  Widget _bottomBar(int? selected, bool isLast) {
    final canNext = selected != null && !widget.finishing;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: _index == 0 ? null : () => _goToQuestion(_index - 1),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Anterior'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const Spacer(),
            Pressable(
              onTap: canNext
                  ? () {
                      if (isLast) {
                        widget.onFinish();
                      } else {
                        _goToQuestion(_index + 1);
                      }
                    }
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                decoration: BoxDecoration(
                  color: canNext ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isLast
                          ? (widget.finishing ? 'Corrigiendo' : 'Finalizar')
                          : 'Siguiente',
                      style: TextStyle(
                        color: canNext ? Colors.white : AppColors.textLight,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isLast && widget.finishing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    else
                      Icon(
                        isLast
                            ? Icons.done_all_rounded
                            : Icons.arrow_forward_rounded,
                        color: canNext ? Colors.white : AppColors.textLight,
                        size: 19,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================
// RUNNER CLÁSICO (scroll: enunciado + imagen + opciones en una pantalla)
// ==========================

class _SimRunnerClassic extends StatefulWidget {
  final List<SimQuestion> questions;
  final String mode;
  final bool showSubject;
  final List<int?> answers;
  final List<SimResult?> results;
  final bool finishing;
  final void Function(int qIndex, int optIndex) onSelect;
  final void Function(int qIndex) onBlank;
  final VoidCallback onFinish;
  final VoidCallback onExit;

  const _SimRunnerClassic({
    required this.questions,
    required this.mode,
    required this.showSubject,
    required this.answers,
    required this.results,
    required this.finishing,
    required this.onSelect,
    required this.onBlank,
    required this.onFinish,
    required this.onExit,
  });

  @override
  State<_SimRunnerClassic> createState() => _SimRunnerClassicState();
}

class _SimRunnerClassicState extends State<_SimRunnerClassic> {
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final total = widget.questions.length;
    final q = widget.questions[_index];
    final selected = widget.answers[_index];
    final result = widget.results[_index];
    final correctIndex = result?.correctIndex ?? -1;
    final isLast = _index == total - 1;
    final immediate = widget.mode == 'immediate';
    final locked = immediate && selected != null;
    final revealed = locked && result != null;
    final checking = locked && result == null;
    final explanation = result?.explanation?.trim() ?? '';

    return Column(
      children: [
        // Progreso (compacto: barra + "n de N" en una fila)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / total,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${_index + 1} de $total',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showSubject && q.subject != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      q.subject!.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          letterSpacing: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  q.statement,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (q.hasImage && q.imageUrl != null) ...[
                  const SizedBox(height: 14),
                  ZoomableImage(url: q.imageUrl!),
                ],
                const SizedBox(height: 18),
                ...List.generate(q.options.length, (i) {
                  final isSelected = selected == i;
                  final isCorrect = i == correctIndex;

                  Color border = AppColors.border;
                  Color bg = Colors.white;
                  Color circleBorder = const Color(0xFFD8D2CE);
                  Color circleBg = Colors.transparent;
                  Widget? circleChild;

                  if (revealed) {
                    if (isCorrect) {
                      border = AppColors.success;
                      bg = AppColors.success.withValues(alpha: 0.10);
                      circleBorder = AppColors.success;
                      circleBg = AppColors.success;
                      circleChild = const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16);
                    } else if (isSelected) {
                      border = AppColors.error;
                      bg = const Color(0xFFFFF1EC);
                      circleBorder = AppColors.error;
                      circleBg = AppColors.error;
                      circleChild = const Icon(Icons.close_rounded,
                          color: Colors.white, size: 16);
                    }
                  } else if (isSelected) {
                    border = AppColors.primary;
                    circleBorder = AppColors.primary;
                    circleBg = AppColors.primary;
                    circleChild = const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16);
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Pressable(
                      onTap: locked ? null : () => widget.onSelect(_index, i),
                      pressedScale: 0.98,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border, width: 2),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: circleBg,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: circleBorder, width: 2),
                              ),
                              child: circleChild ??
                                  Text(
                                    _letters[i],
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12),
                                  ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${_letters[i]})  ${q.options[i]}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                _blankButton(selected),
                if (checking) ...[
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Comprobando tu respuesta...',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ],
                if (revealed) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EXPLICACIÓN',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                                letterSpacing: 1)),
                        const SizedBox(height: 6),
                        Text(
                          explanation.isNotEmpty
                              ? explanation
                              : 'No hay explicación disponible para esta pregunta.',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Controles
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _index == 0
                      ? null
                      : () => setState(() => _index--),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Anterior'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: (selected == null || widget.finishing)
                      ? null
                      : () {
                          if (isLast) {
                            widget.onFinish();
                          } else {
                            setState(() => _index++);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 15),
                    decoration: BoxDecoration(
                      color: (selected == null || widget.finishing)
                          ? AppColors.border
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isLast
                              ? (widget.finishing ? 'Corrigiendo' : 'Finalizar')
                              : 'Siguiente',
                          style: TextStyle(
                            color: (selected == null || widget.finishing)
                                ? AppColors.textLight
                                : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isLast && widget.finishing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        else
                          Icon(
                            isLast
                                ? Icons.done_all_rounded
                                : Icons.arrow_forward_rounded,
                            color: (selected == null || widget.finishing)
                                ? AppColors.textLight
                                : Colors.white,
                            size: 19,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Botón "Dejar en blanco" (no puntúa ni penaliza; se registra igual).
  Widget _blankButton(int? selected) {
    final isBlank = selected == -1;
    final locked = widget.mode == 'immediate' && selected != null;
    if (locked && !isBlank) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Pressable(
        onTap: locked ? null : () => widget.onBlank(_index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isBlank
                ? AppColors.textSecondary.withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isBlank ? AppColors.textSecondary : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isBlank ? Icons.check_circle_rounded : Icons.block_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                isBlank ? 'En blanco · no puntúa ni penaliza' : 'Dejar en blanco',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================
// FASE 3 — RESULTS
// ==========================

enum _SimStatus { correct, incorrect, empty }

_SimStatus _statusOf(int? selected, SimResult? result) {
  // null = sin decidir, -1 = en blanco: ambos cuentan como "en blanco".
  if (selected == null || selected < 0) return _SimStatus.empty;
  if (result == null) return _SimStatus.incorrect;
  return selected == result.correctIndex
      ? _SimStatus.correct
      : _SimStatus.incorrect;
}

class _SimResults extends StatelessWidget {
  final List<SimQuestion> questions;
  final List<int?> answers;
  final List<SimResult?> results;
  final VoidCallback onRestart;
  final VoidCallback onClose;

  const _SimResults({
    required this.questions,
    required this.answers,
    required this.results,
    required this.onRestart,
    required this.onClose,
  });

  Color _cellColor(_SimStatus s) => switch (s) {
        _SimStatus.correct => AppColors.success,
        _SimStatus.incorrect => AppColors.error,
        _SimStatus.empty => const Color(0xFFEDE8E5),
      };

  @override
  Widget build(BuildContext context) {
    var correct = 0, incorrect = 0, empty = 0;
    for (var i = 0; i < questions.length; i++) {
      switch (_statusOf(answers[i], results[i])) {
        case _SimStatus.correct:
          correct++;
        case _SimStatus.incorrect:
          incorrect++;
        case _SimStatus.empty:
          empty++;
      }
    }
    final total = questions.length;
    final pct = total > 0 ? (correct / total * 100).round() : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      children: [
        Center(
          child: Column(
            children: [
              const Text('SIMULACRO COMPLETADO',
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.4)),
              const SizedBox(height: 10),
              Text('$correct / $total aciertos',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Has acertado el $pct% del simulacro.',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            _statBox('Aciertos', correct, AppColors.successDark),
            const SizedBox(width: 10),
            _statBox('Fallos', incorrect, AppColors.error),
            const SizedBox(width: 10),
            _statBox('En blanco', empty, AppColors.textSecondary),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Repaso de preguntas',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              const SizedBox(height: 2),
              const Text(
                  'Toca una pregunta para ver la respuesta correcta y su explicación.',
                  style:
                      TextStyle(color: AppColors.textLight, fontSize: 12.5)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < questions.length; i++)
                    Pressable(
                      onTap: () => _openDetail(context, i),
                      pressedScale: 0.92,
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _cellColor(
                              _statusOf(answers[i], results[i])),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: _statusOf(answers[i], results[i]) ==
                                    _SimStatus.empty
                                ? AppColors.textSecondary
                                : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _legend('Acierto', AppColors.success),
                  _legend('Fallo', AppColors.error),
                  _legend('En blanco', const Color(0xFFEDE8E5)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: onRestart,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Crear otro simulacro'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onClose,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: const Text('Volver'),
        ),
      ],
    );
  }

  void _openDetail(BuildContext context, int index) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _SimDetailDialog(
        questions: questions,
        answers: answers,
        results: results,
        initialIndex: index,
      ),
    );
  }

  Widget _statBox(String label, int n, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text('$n',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 22)),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _SimDetailDialog extends StatefulWidget {
  final List<SimQuestion> questions;
  final List<int?> answers;
  final List<SimResult?> results;
  final int initialIndex;

  const _SimDetailDialog({
    required this.questions,
    required this.answers,
    required this.results,
    required this.initialIndex,
  });

  @override
  State<_SimDetailDialog> createState() => _SimDetailDialogState();
}

class _SimDetailDialogState extends State<_SimDetailDialog> {
  late int _index = widget.initialIndex;
  bool _showImage = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_index];
    final answer = widget.answers[_index];
    final result = widget.results[_index];
    final correctIndex = result?.correctIndex ?? -1;
    final status = _statusOf(answer, result);

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabecera
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  _statusChip(status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pregunta ${_index + 1} de ${widget.questions.length}',
                      style: const TextStyle(
                          color: AppColors.textLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          letterSpacing: 0.6),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(height: 3, color: _statusColor(status)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (q.subject != null)
                      Text(q.subject!.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.textLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                              letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    Text(q.statement,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            height: 1.4)),
                    if (q.hasImage && q.imageUrl != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _showImage = !_showImage),
                        icon: Icon(
                            _showImage
                                ? Icons.visibility_off_rounded
                                : Icons.image_rounded,
                            size: 18),
                        label: Text(_showImage ? 'Ocultar' : 'Ver imagen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryDark,
                          side: BorderSide(
                              color:
                                  AppColors.primary.withValues(alpha: 0.4)),
                        ),
                      ),
                      if (_showImage) ...[
                        const SizedBox(height: 8),
                        ZoomableImage(
                            url: q.imageUrl!,
                            fit: BoxFit.contain,
                            borderRadius: BorderRadius.circular(12)),
                      ],
                    ],
                    const SizedBox(height: 14),
                    ...List.generate(q.options.length, (i) {
                      final isCorrect = i == correctIndex;
                      final isSelected = answer == i;
                      Color border = AppColors.border;
                      Color bg = Colors.white;
                      Color badgeBg = AppColors.surfaceVariant;
                      Color badgeFg = AppColors.textSecondary;
                      if (isCorrect) {
                        border = AppColors.success.withValues(alpha: 0.5);
                        bg = AppColors.success.withValues(alpha: 0.10);
                        badgeBg = AppColors.success;
                        badgeFg = Colors.white;
                      } else if (isSelected) {
                        border = AppColors.error.withValues(alpha: 0.5);
                        bg = const Color(0xFFFFF1EC);
                        badgeBg = AppColors.error;
                        badgeFg = Colors.white;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  String.fromCharCode(65 + i),
                                  style: TextStyle(
                                      color: badgeFg,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(q.options[i],
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13.5,
                                          height: 1.35)),
                                ),
                              ),
                              if (isCorrect)
                                _tag('CORRECTA', AppColors.successDark)
                              else if (isSelected)
                                _tag('TU RESPUESTA', AppColors.error),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('EXPLICACIÓN',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                  letterSpacing: 1)),
                          const SizedBox(height: 6),
                          Text(
                            (result?.explanation?.trim().isNotEmpty ?? false)
                                ? result!.explanation!.trim()
                                : 'No hay explicación disponible para esta pregunta.',
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Navegación
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _index == 0
                        ? null
                        : () => setState(() {
                              _index--;
                              _showImage = false;
                            }),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Anterior'),
                  ),
                  TextButton(
                    onPressed: _index == widget.questions.length - 1
                        ? null
                        : () => setState(() {
                              _index++;
                              _showImage = false;
                            }),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Siguiente'),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
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

  Color _statusColor(_SimStatus s) => switch (s) {
        _SimStatus.correct => AppColors.success,
        _SimStatus.incorrect => AppColors.error,
        _SimStatus.empty => const Color(0xFFC9C2BC),
      };

  Widget _statusChip(_SimStatus s) {
    final (label, color, icon) = switch (s) {
      _SimStatus.correct => (
          'Acierto',
          AppColors.successDark,
          Icons.check_circle_rounded
        ),
      _SimStatus.incorrect => ('Fallo', AppColors.error, Icons.cancel_rounded),
      _SimStatus.empty => (
          'En blanco',
          AppColors.textSecondary,
          Icons.radio_button_unchecked_rounded
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 8.5,
                letterSpacing: 0.5)),
      ),
    );
  }
}

// ==========================
// POPUP: elegir modo de visualización (clásico vs deslizar), gráfico
// ==========================

class _LayoutPickerDialog extends StatefulWidget {
  const _LayoutPickerDialog();

  @override
  State<_LayoutPickerDialog> createState() => _LayoutPickerDialogState();
}

class _LayoutPickerDialogState extends State<_LayoutPickerDialog> {
  bool _showSubject = true;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Antes de empezar',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18),
            ),
            const SizedBox(height: 16),
            // ¿Mostrar la asignatura?
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mostrar la asignatura',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        SizedBox(height: 2),
                        Text(
                            'Si la ocultas, no la verás en el enunciado durante el test.',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                                height: 1.3)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _showSubject,
                    onChanged: (v) => setState(() => _showSubject = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('MODO DE VISUALIZACIÓN',
                  style: TextStyle(
                      color: AppColors.textLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      letterSpacing: 1.2)),
            ),
            const SizedBox(height: 10),
            _option(
              context,
              value: 'classic',
              title: 'Clásico',
              desc:
                  'Todo en una pantalla. Desplázate hacia abajo para ver imagen y opciones.',
              graphic: _classicGraphic(),
            ),
            const SizedBox(height: 12),
            _option(
              context,
              value: 'carousel',
              title: 'Deslizar',
              badge: 'NUEVO',
              desc:
                  'Una tarjeta cada vez (enunciado → imagen → opciones). Desliza para avanzar. Incluye subrayado del enunciado.',
              graphic: _carouselGraphic(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required String value,
    required String title,
    required String desc,
    required Widget graphic,
    String? badge,
  }) {
    return Pressable(
      onTap: () => Navigator.pop(context, (value, _showSubject)),
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(width: 76, height: 92, child: Center(child: graphic)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(badge,
                              style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 8.5,
                                  letterSpacing: 0.6)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _classicGraphic() => const _ClassicAnim();

  Widget _carouselGraphic() => const _CarouselAnim();
}

Widget _miniBar(double h, {Color? color}) => Container(
      height: h,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(3),
      ),
    );

/// Mini maqueta vertical con flecha que pulsa hacia abajo (scroll).
class _ClassicAnim extends StatefulWidget {
  const _ClassicAnim();

  @override
  State<_ClassicAnim> createState() => _ClassicAnimState();
}

class _ClassicAnimState extends State<_ClassicAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 84,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _miniBar(11, color: AppColors.primary.withValues(alpha: 0.55)),
              const SizedBox(height: 7),
              _miniBar(6),
              const SizedBox(height: 4),
              _miniBar(6),
              const SizedBox(height: 4),
              _miniBar(6),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value; // 0..1
                return Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, t * 12),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: AppColors.primaryDark),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini maqueta horizontal con flecha que pulsa hacia la izquierda (swipe).
class _CarouselAnim extends StatefulWidget {
  const _CarouselAnim();

  @override
  State<_CarouselAnim> createState() => _CarouselAnimState();
}

class _CarouselAnimState extends State<_CarouselAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 84,
      child: Stack(
        children: [
          // Peek de la siguiente tarjeta
          Positioned(
            right: 0,
            top: 14,
            bottom: 20,
            child: Container(
              width: 14,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
            ),
          ),
          // Tarjeta principal
          Positioned(
            left: 0,
            right: 20,
            top: 4,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _miniBar(10,
                      color: AppColors.primary.withValues(alpha: 0.55)),
                  const SizedBox(height: 6),
                  _miniBar(6),
                  const SizedBox(height: 4),
                  _miniBar(6),
                ],
              ),
            ),
          ),
          // Flecha de deslizar (pulsa hacia la izquierda)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value; // 0..1
                return Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(-t * 14, 0),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        size: 15, color: AppColors.primaryDark),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Pista de deslizar: una mano que se desliza dejando una estela desde la
/// punta del dedo y se desvanece, en bucle suave. Solo en la primera pregunta.
class _SwipeHandHint extends StatefulWidget {
  const _SwipeHandHint();

  @override
  State<_SwipeHandHint> createState() => _SwipeHandHintState();
}

class _SwipeHandHintState extends State<_SwipeHandHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1900))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 40,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) =>
            CustomPaint(painter: _SwipeHandPainter(_c.value)),
      ),
    );
  }
}

class _SwipeHandPainter extends CustomPainter {
  final double t; // 0..1
  _SwipeHandPainter(this.t);

  static const _coral = AppColors.primaryDark;

  @override
  void paint(Canvas canvas, Size size) {
    // Envolvente de opacidad: aparece, se mantiene y se desvanece.
    double op;
    if (t < 0.12) {
      op = t / 0.12;
    } else if (t > 0.7) {
      op = (1 - t) / 0.3;
    } else {
      op = 1;
    }
    op = op.clamp(0.0, 1.0);
    if (op <= 0.01) return;

    final move = Curves.easeInOut.transform(t.clamp(0.0, 1.0)); // 0..1
    final y = size.height * 0.5;
    final startX = size.width * 0.74; // empieza a la derecha
    final endX = size.width * 0.26; // termina a la izquierda
    final handX = startX + (endX - startX) * move;

    // Estela: desde la mano hacia atrás (de dónde viene), se desvanece.
    final trailStart = Offset(handX + 12, y);
    final trailEnd = Offset(startX + 12, y);
    if ((trailEnd.dx - trailStart.dx) > 2) {
      final trailPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..shader = ui.Gradient.linear(
          trailStart,
          trailEnd,
          [_coral.withValues(alpha: 0.5 * op), _coral.withValues(alpha: 0.0)],
        );
      canvas.drawLine(trailStart, trailEnd, trailPaint);
    }

    // Mano (glifo de Material Icons).
    const icon = Icons.back_hand_rounded;
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 26,
          color: _coral.withValues(alpha: op),
        ),
      ),
    )..layout();
    tp.paint(canvas, Offset(handX - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SwipeHandPainter oldDelegate) =>
      oldDelegate.t != t;
}
