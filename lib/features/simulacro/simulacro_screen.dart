import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/mir_weights.dart';
import '../../shared/sticker/sticker.dart';
import 'widgets/count_slider.dart';
import 'widgets/highlightable_statement.dart';
import 'widgets/layout_mode_art.dart';
import 'widgets/subject_shortcuts.dart';
import 'simulacro_historial_screen.dart';
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

  /// Mostrar la asignatura en el enunciado. Apagado por defecto: saberla acota
  /// la respuesta antes de leer el caso, y un simulacro imita al examen.
  bool _showSubject = false;
  List<SimQuestion> _questions = [];
  List<int?> _answers = [];
  List<SimResult?> _results = [];

  /// Segundos que costó cada pregunta, para mandarlos con la respuesta. Sin
  /// esto el backend hace COALESCE(...,0) y toda la analítica de tiempo de la
  /// app queda a cero, indistinguible de la web.
  List<int?> _times = [];
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
    List<MirAllocation>? weights,
  }) async {
    setState(() {
      _generating = true;
      _generationError = null;
      _layout = layout;
      _showSubject = showSubject;
    });
    try {
      // Con reparto MIR se pide asignatura por asignatura con su cuota; sin
      // él, una sola petición con el total.
      final fetched = weights != null && weights.isNotEmpty
          ? await _api.getSimulacroQuestionsWeighted(weights)
          : await _api.getSimulacroQuestions(
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
        _times = List<int?>.filled(fetched.length, null);
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

  /// Apunta la opción elegida. **No corrige**, ni siquiera en modo inmediato:
  /// eso lo hace [_handleCheck] cuando el usuario pulsa "Comprobar". Así se
  /// puede cambiar de idea antes de comprometerse, que es como se responde un
  /// test de verdad.
  void _handleSelect(int qIndex, int optIndex, [int? timeSpent]) {
    setState(() {
      _answers[qIndex] = optIndex;
      _times[qIndex] = timeSpent;
    });
  }

  /// Manda al servidor la respuesta de UNA pregunta y guarda su corrección.
  /// Solo se usa en modo inmediato; en diferido se manda todo al terminar.
  Future<void> _handleCheck(int qIndex, [int? timeSpent]) async {
    if (_mode != 'immediate' || _results[qIndex] != null) return;
    final q = _questions[qIndex];
    final answer = _answers[qIndex];
    // El tiempo se cuenta hasta que se comprueba, no hasta que se elige: es
    // lo que de verdad ha tardado en decidirse.
    if (timeSpent != null) _times[qIndex] = timeSpent;
    try {
      final res = await _api.checkSimulacro([
        {
          'questionId': q.id,
          'selectedIndex': (answer == null || answer < 0) ? null : answer,
          if (_times[qIndex] != null) 'timeSpent': _times[qIndex],
        }
      ], sessionId: _sessionId);
      if (!mounted || res.isEmpty) return;
      setState(() => _results[qIndex] = res.first);
    } catch (_) {
      // Sin conexión no se corrige, pero la respuesta queda apuntada y el
      // envío diferido del final la recogerá igual.
    }
  }

  /// Dejar la pregunta en blanco (no puntúa ni penaliza, pero se registra).
  /// Se usa -1 como centinela de "en blanco" en [_answers].
  /// Deja la pregunta en blanco. Como al elegir, se apunta y ya: la corrección
  /// espera a "Comprobar".
  void _handleBlank(int qIndex, [int? timeSpent]) {
    setState(() {
      _answers[qIndex] = -1;
      _times[qIndex] = timeSpent;
    });
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
              if (_times[i] != null) 'timeSpent': _times[i],
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

    // Guarda el simulacro en el historial. Igual que en la web es
    // "best-effort": el backend solo lo guarda de verdad si hay >=50
    // respuestas persistidas, y un fallo de red aquí no debe estropear la
    // pantalla de resultados que el usuario ya está viendo.
    final sessionId = _sessionId;
    if (sessionId != null) {
      _api.finishSimulacro(sessionId, _mode).catchError((_) {});
    }
  }

  void _handleRestart() {
    setState(() {
      _questions = [];
      _answers = [];
      _results = [];
      _times = [];
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
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kInk, width: 2),
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
        onCheck: _handleCheck,
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
      onCheck: _handleCheck,
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
              )
            else if (_phase == 'builder')
              IconButton(
                tooltip: 'Historial',
                icon: const Icon(Icons.history_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SimulacroHistorialScreen()),
                ),
              ),
          ],
        ),
        body: switch (_phase) {
          'running' => _runner(),
        'results' => SimResultsView(
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
    List<MirAllocation>? weights,
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

  /// Reparto ponderado por peso en el MIR (botón "MIR").
  bool _weighted = false;

  /// Qué atajo produjo la selección actual, o null si se ha tocado a mano.
  /// Es lo que mantiene los tres botones marcados, no solo el de MIR.
  SubjectShortcut? _shortcut;

  /// Atajos de tamaño; 210 son las preguntas de un MIR real.
  // 150 rellena el salto de 100 a 210, que era el más grande con diferencia.
  static const List<int> _countPresets = [10, 25, 50, 100, 150, 210];
  static const int _maxCount = 210;

  /// Las asignatura elegidas, en la forma que espera [allocateByWeight].
  List<({int id, String name})> get _chosenSubjects => [
        for (final s in _subjects)
          if (_selectedSubjectIds.contains(s.id)) (id: s.id, name: s.name),
      ];

  /// Reparto que se va a pedir en modo MIR, para enseñarlo antes de generar.
  ///
  /// Si se quita una asignatura, [_weighted] NO se desactiva: los pesos se
  /// renormalizan sobre las que quedan, así que el reparto sigue siendo
  /// proporcional al MIR entre las elegidas. Enseñarlo aquí evita que ese
  /// recálculo sea invisible.
  List<MirAllocation> get _mirBreakdown {
    if (!_weighted) return const [];
    return allocateByWeight(_count, _chosenSubjects)
        .where((a) => a.count > 0)
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  void _selectAllSubjects() {
    setState(() {
      _selectedSubjectIds
        ..clear()
        ..addAll(_subjects.map((s) => s.id));
      _weighted = false;
      _shortcut = SubjectShortcut.todas;
    });
    _reloadTopics();
  }

  void _clearSubjects() {
    setState(() {
      _selectedSubjectIds.clear();
      _selectedTopicIds.clear();
      _weighted = false;
      _shortcut = null;
    });
    _reloadTopics();
  }

  /// Un puñado de asignaturas al azar, para salir del bloqueo de elegir.
  void _pickRandomSubjects() {
    if (_subjects.isEmpty) return;
    final shuffled = [..._subjects]..shuffle();
    // Entre 2 y 7, pero nunca más de las que hay.
    final howMany = (2 + Random().nextInt(6)).clamp(1, _subjects.length);
    setState(() {
      _selectedSubjectIds
        ..clear()
        ..addAll(shuffled.take(howMany).map((s) => s.id));
      _selectedTopicIds.clear();
      _weighted = false;
      _shortcut = SubjectShortcut.aleatorias;
    });
    _reloadTopics();
  }

  /// Simulacro tipo MIR: todas las asignaturas, pero repartiendo las preguntas
  /// según su peso en el examen real en vez de a partes iguales. Los temas se
  /// limpian porque aquí manda el reparto por asignatura.
  void _useMirDistribution() {
    setState(() {
      _selectedSubjectIds
        ..clear()
        ..addAll(_subjects.map((s) => s.id));
      _selectedTopicIds.clear();
      _weighted = true;
      _shortcut = SubjectShortcut.mir;
      // Un MIR son 210 preguntas: el atajo las pone solo.
      _count = _maxCount;
    });
    _reloadTopics();
  }

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

  /// Nombre de una asignatura por su id, o null si ya no está en el catálogo.
  String? _subjectName(int id) {
    for (final s in _subjects) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  void _toggleSubject(int id) {
    setState(() {
      if (_selectedSubjectIds.contains(id)) {
        _selectedSubjectIds.remove(id);
      } else {
        _selectedSubjectIds.add(id);
      }
      // La selección ya no es la que dejó el atajo, así que deja de estar
      // marcado. Y el reparto MIR, que va con "todas", deja de tener sentido.
      _shortcut = null;
      _weighted = false;
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
      weights: _weighted ? _mirBreakdown : null,
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
        const StickerHero(
          badge: 'Exámenes',
          badgeIcon: Icons.quiz_rounded,
          title: 'Diseña tu simulacro',
          subtitle:
              'Elige asignaturas y temas, cuántas preguntas quieres y cómo corregirlo.',
          accent: Color(0xFF6E8E6B),
        ),
        const SizedBox(height: 24),

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
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Atajos: elegir una a una entre veinte asignaturas
                        // es justo donde la gente se atasca.
                        SubjectShortcutBar(
                          active: _shortcut,
                          canClear: _selectedSubjectIds.isNotEmpty,
                          onPick: (s) => switch (s) {
                            SubjectShortcut.todas => _selectAllSubjects(),
                            SubjectShortcut.aleatorias => _pickRandomSubjects(),
                            SubjectShortcut.mir => _useMirDistribution(),
                            SubjectShortcut.quitar => _clearSubjects(),
                          },
                        ),
                        const SizedBox(height: 16),
                        Wrap(
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
                        if (_weighted) ...[
                          const SizedBox(height: 16),
                          _MirBreakdown(allocations: _mirBreakdown),
                        ],
                      ],
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
                        // Un renglón por asignatura, no una pastilla por tema:
                        // con doce temas de Urología la lista se iba de las
                        // manos y los nombres largos se salían de la pastilla.
                        // Lo que hace falta saber aquí es CUÁNTO has acotado
                        // cada asignatura, no cómo se llama cada tema.
                        for (final sid in _selectedSubjectIds)
                          _TopicSummaryRow(
                            subject: _subjectName(sid),
                            chosen: _topics
                                .where((t) =>
                                    t.subjectId == sid &&
                                    _selectedTopicIds.contains(t.id))
                                .length,
                            total: _topics
                                .where((t) => t.subjectId == sid)
                                .length,
                          ),
                        const SizedBox(height: 12),
                        GhostButton(
                          label: selectedTopics.isEmpty
                              ? 'Elegir temas concretos'
                              : 'Editar temas',
                          icon: Icons.tune_rounded,
                          expand: true,
                          onPressed: _openTopicPicker,
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
                  _stepperBtn(
                      Icons.remove_rounded,
                      () => setState(
                          () => _count = (_count - 1).clamp(1, _maxCount))),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$_count',
                        style: const TextStyle(
                          color: kInk,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  _stepperBtn(
                      Icons.add_rounded,
                      () => setState(
                          () => _count = (_count + 1).clamp(1, _maxCount))),
                ],
              ),
              const SizedBox(height: 6),
              // Deslizador con muelle, como en la web: con 210 posiciones,
              // llegar a golpe de botón sería absurdo.
              CountSlider(
                value: _count,
                max: _maxCount,
                onChanged: (v) => setState(() => _count = v),
              ),
              const SizedBox(height: 6),
              // Los atajos van en su propia fila: con el 210 ya no caben al
              // lado del contador sin apretarlos.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final p in _countPresets) _presetBtn(p)],
              ),
              const SizedBox(height: 10),
              Text(
                _count == _maxCount
                    ? 'Un MIR real son $_maxCount preguntas.'
                    : 'Si hay menos preguntas disponibles que las pedidas, '
                        'se usarán las que haya.',
                style: const TextStyle(color: AppColors.textLight, fontSize: 12),
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
    return StickerCard(
      depth: 4,
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StepBadge(
                n: int.tryParse(n) ?? 1,
                active: true,
                color: const Color(0xFF6E8E6B),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: kInk,
                      fontSize: 16)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(
                    color: kMuted.withOpacity(0.85),
                    fontSize: 12,
                    height: 1.4)),
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
          color: active ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? kInk : kHairline, width: 2),
          boxShadow: active ? inkShadow(2) : const [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : kMuted,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(2),
        ),
        child: Icon(icon, color: kInk, size: 20),
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
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? kInk : kHairline, width: 2),
          boxShadow: active ? inkShadow(2) : const [],
        ),
        child: Text(
          '$p',
          style: TextStyle(
            color: active ? Colors.white : kMuted,
            fontWeight: FontWeight.w900,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFF0EC) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? kInk : kHairline, width: 2),
          boxShadow: active ? inkShadow(3) : const [],
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
                border: Border.all(color: kInk, width: 1.6),
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
/// Cuántas preguntas le van a tocar a cada asignatura en el reparto MIR.
///
/// Se enseña ANTES de generar porque el reparto se renormaliza al quitar
/// asignaturas: sin verlo, ese recálculo sería invisible y el usuario no
/// sabría por qué le salen 18 de Digestivo y 4 de Oftalmología.
class _MirBreakdown extends StatelessWidget {
  final List<MirAllocation> allocations;

  const _MirBreakdown({required this.allocations});

  @override
  Widget build(BuildContext context) {
    if (allocations.isEmpty) return const SizedBox.shrink();
    final total = allocations.fold<int>(0, (a, b) => a + b.count);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tinted(const Color(0xFF6E8E6B), 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.balance_rounded,
                  size: 15, color: Color(0xFF4E6B4B)),
              const SizedBox(width: 6),
              Text(
                'REPARTO MIR · $total PREGUNTAS',
                style: const TextStyle(
                  color: Color(0xFF4E6B4B),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in allocations)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: kHairline, width: 1.6),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: a.name,
                          style: const TextStyle(
                            color: kMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: '${a.count}',
                          style: const TextStyle(
                            color: kInk,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un renglón del paso de temas: qué asignatura y cuánto se ha acotado.
///
/// Sustituye a la lista de pastillas de tema. Con doce temas de Urología
/// aquello eran diez líneas y los nombres largos se salían de la pastilla;
/// además, lo que hace falta saber en este paso es cuánto has recortado cada
/// asignatura, no cómo se llama cada tema — para eso está el selector.
class _TopicSummaryRow extends StatelessWidget {
  final String? subject;
  final int chosen;
  final int total;

  const _TopicSummaryRow({
    required this.subject,
    required this.chosen,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    // Sin temas marcados entra la asignatura entera: es la regla del backend.
    final todos = chosen == 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              subject ?? 'Asignatura',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kInk,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: todos ? Colors.white : tinted(AppColors.primary, 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kHairline, width: 2),
            ),
            child: Text(
              todos ? 'Todos' : '$chosen de $total',
              style: TextStyle(
                color: todos ? kMuted : AppColors.primaryDark,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

/// Entrada de la pregunta nueva al cambiar de una a otra.
///
/// Antes era un corte seco y costaba saber si habías avanzado o si la pantalla
/// se había quedado colgada. Se desplaza desde el lado hacia el que vas, así
/// que también dice la dirección.
mixin _QuestionSwap<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  /// +1 al avanzar, -1 al retroceder.
  int _swapDir = 1;

  void _playSwap(int dir) {
    _swapDir = dir;
    _swap.forward(from: 0);
  }

  void _disposeSwap() => _swap.dispose();

  /// Envuelve el cuerpo de la pregunta. El contenido va como `child` para que
  /// no se reconstruya en cada fotograma de la transición.
  Widget _swapped(Widget child) {
    return AnimatedBuilder(
      animation: _swap,
      child: child,
      builder: (context, inner) {
        final t = Curves.easeOutCubic.transform(_swap.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(_swapDir * 28 * (1 - t), 0),
            child: inner,
          ),
        );
      },
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
  final void Function(int qIndex, int optIndex, [int? timeSpent]) onSelect;
  final void Function(int qIndex, [int? timeSpent]) onBlank;

  /// Manda la respuesta y trae la corrección. Solo en modo inmediato.
  final Future<void> Function(int qIndex, [int? timeSpent]) onCheck;
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
    required this.onCheck,
    required this.onFinish,
    required this.onExit,
  });

  @override
  State<_SimRunnerCarousel> createState() => _SimRunnerCarouselState();
}

class _SimRunnerCarouselState extends State<_SimRunnerCarousel>
    // Plural, no `Single`: aquí conviven el parpadeo de la pista y la
    // transición entre preguntas, y `Single` solo admite un ticker.
    with TickerProviderStateMixin, _QuestionSwap {
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

  int _index = 0;
  int _page = 0;
  late final PageController _carousel;

  /// Cierto mientras se espera la corrección del servidor.
  bool _checking = false;

  /// Momento en que se mostró la pregunta actual. Se reinicia al cambiar de
  /// pregunta, igual que el `shownAtRef` del runner de la web.
  DateTime _shownAt = DateTime.now();

  /// Segundos transcurridos desde que apareció la pregunta.
  int get _elapsed =>
      (DateTime.now().difference(_shownAt).inMilliseconds / 1000).round().clamp(0, 86400);

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
    _disposeSwap();
    super.dispose();
  }

  void _goToQuestion(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.questions.length) return;
    _playSwap(newIndex > _index ? 1 : -1);
    setState(() {
      _index = newIndex;
      _page = 0;
      _checking = false;
      _shownAt = DateTime.now();
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
    final hasImage = q.hasImage && q.imageUrl != null;

    // Páginas del carrusel
    final pages = <Widget>[
      _statementPage(q),
      if (hasImage) _imagePage(q),
      _optionsPage(q, selected, revealed, correctIndex),
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
          child: _swapped(
            PageView(
              controller: _carousel,
              onPageChanged: (p) => setState(() => _page = p),
              children: pages,
            ),
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
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(5),
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
    return _pageShell(
      label: 'ENUNCIADO',
      icon: Icons.article_rounded,
      trailing: _highlighted.isEmpty
          ? null
          : ClearHighlightButton(onTap: () => setState(_highlighted.clear)),
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
          HighlightableStatement(
            statement: q.statement,
            highlighted: _highlighted,
            onToggle: (i) => setState(() {
              if (!_highlighted.remove(i)) _highlighted.add(i);
            }),
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
  Widget _optionsPage(
      SimQuestion q, int? selected, bool revealed, int correctIndex) {
    // Se bloquea al corregir, no al elegir: hasta que se pulsa "Comprobar"
    // se puede cambiar de opción.
    final locked =
        widget.mode == 'immediate' && widget.results[_index] != null;
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
                onTap: locked ? null : () => widget.onSelect(_index, i, _elapsed),
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
        ],
      ),
    );
  }

  /// Botón "Dejar en blanco" (no puntúa ni penaliza; se registra igual).
  Widget _blankButton(int? selected) {
    final isBlank = selected == -1;
    // Se bloquea al corregir, no al elegir: hasta que se pulsa "Comprobar"
    // se puede cambiar de opción.
    final locked =
        widget.mode == 'immediate' && widget.results[_index] != null;
    if (locked && !isBlank) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Pressable(
        onTap: locked ? null : () => widget.onBlank(_index, _elapsed),
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
  /// Manda la respuesta y espera la corrección, con el spinner mientras.
  Future<void> _comprobar() async {
    if (_checking) return;
    setState(() => _checking = true);
    await widget.onCheck(_index, _elapsed);
    if (mounted) setState(() => _checking = false);
  }

  Widget _bottomBar(int? selected, bool isLast) {
    // En inmediato hay un paso más: primero se comprueba y luego se avanza.
    final debeComprobar = widget.mode == 'immediate' &&
        selected != null &&
        widget.results[_index] == null;
    // Mientras se espera al servidor el botón no admite otro toque: sin esto
    // se puede pedir la corrección dos veces.
    final canNext = selected != null && !widget.finishing && !_checking;
    final ocupado = _checking || (isLast && widget.finishing);
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
                      if (debeComprobar) {
                        _comprobar();
                      } else if (isLast) {
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
                  color: canNext || ocupado
                      ? AppColors.primary
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _checking
                          ? 'Comprobando'
                          : debeComprobar
                              ? 'Comprobar'
                              : isLast
                                  ? (widget.finishing
                                      ? 'Corrigiendo'
                                      : 'Finalizar')
                                  : 'Siguiente',
                      style: TextStyle(
                        color: canNext ? Colors.white : AppColors.textLight,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (ocupado)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    else
                      Icon(
                        debeComprobar
                            ? Icons.check_rounded
                            : isLast
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
  final void Function(int qIndex, int optIndex, [int? timeSpent]) onSelect;
  final void Function(int qIndex, [int? timeSpent]) onBlank;

  /// Manda la respuesta y trae la corrección. Solo en modo inmediato.
  final Future<void> Function(int qIndex, [int? timeSpent]) onCheck;
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
    required this.onCheck,
    required this.onFinish,
    required this.onExit,
  });

  @override
  State<_SimRunnerClassic> createState() => _SimRunnerClassicState();
}

class _SimRunnerClassicState extends State<_SimRunnerClassic>
    with SingleTickerProviderStateMixin, _QuestionSwap {
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];
  int _index = 0;

  /// Cierto mientras se espera la corrección del servidor.
  bool _checking = false;

  /// Palabras subrayadas del enunciado. No se conserva entre preguntas.
  final Set<int> _highlighted = {};

  /// Momento en que se mostró la pregunta actual (ver el runner de carrusel).
  DateTime _shownAt = DateTime.now();

  int get _elapsed =>
      (DateTime.now().difference(_shownAt).inMilliseconds / 1000).round().clamp(0, 86400);

  /// Cambia de pregunta y reinicia el cronómetro.
  void _goToQuestion(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.questions.length) return;
    _playSwap(newIndex > _index ? 1 : -1);
    setState(() {
      _index = newIndex;
      _checking = false;
      _highlighted.clear(); // el subrayado no se conserva entre preguntas
      _shownAt = DateTime.now();
    });
  }

  @override
  void dispose() {
    _disposeSwap();
    super.dispose();
  }

  /// Manda la respuesta y espera la corrección, con el spinner mientras.
  Future<void> _comprobar() async {
    if (_checking) return;
    setState(() => _checking = true);
    await widget.onCheck(_index, _elapsed);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.questions.length;
    final q = widget.questions[_index];
    final selected = widget.answers[_index];
    final result = widget.results[_index];
    final correctIndex = result?.correctIndex ?? -1;
    final isLast = _index == total - 1;
    // En inmediato hay un paso más: primero se comprueba y luego se avanza.
    final debeComprobar =
        widget.mode == 'immediate' && selected != null && result == null;
    final ocupado = _checking || (isLast && widget.finishing);
    final immediate = widget.mode == 'immediate';
    // Se bloquea al corregir, no al elegir.
    final locked = immediate && result != null;
    final revealed = locked;
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
                      border: Border.all(color: kHairline, width: 2),
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
                Row(
                  children: [
                    const Spacer(),
                    if (_highlighted.isNotEmpty)
                      ClearHighlightButton(
                        onTap: () => setState(_highlighted.clear),
                      ),
                  ],
                ),
                HighlightableStatement(
                  statement: q.statement,
                  highlighted: _highlighted,
                  onToggle: (i) => setState(() {
                    if (!_highlighted.remove(i)) _highlighted.add(i);
                  }),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  lineHeight: 1.3,
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
                      onTap: locked
                          ? null
                          : () => widget.onSelect(_index, i, _elapsed),
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
                if (revealed) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kHairline, width: 2),
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
                  onPressed: _index == 0 ? null : () => _goToQuestion(_index - 1),
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
                  onTap: (selected == null || widget.finishing || _checking)
                      ? null
                      : () {
                          if (debeComprobar) {
                            _comprobar();
                          } else if (isLast) {
                            widget.onFinish();
                          } else {
                            _goToQuestion(_index + 1);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 15),
                    decoration: BoxDecoration(
                      color: (selected == null && !ocupado)
                          ? AppColors.border
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _checking
                              ? 'Comprobando'
                              : debeComprobar
                                  ? 'Comprobar'
                                  : isLast
                                      ? (widget.finishing
                                          ? 'Corrigiendo'
                                          : 'Finalizar')
                                      : 'Siguiente',
                          style: TextStyle(
                            color: (selected == null || widget.finishing)
                                ? AppColors.textLight
                                : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (ocupado)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        else
                          Icon(
                            debeComprobar
                                ? Icons.check_rounded
                                : isLast
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
    // Se bloquea al corregir, no al elegir: hasta que se pulsa "Comprobar"
    // se puede cambiar de opción.
    final locked =
        widget.mode == 'immediate' && widget.results[_index] != null;
    if (locked && !isBlank) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Pressable(
        onTap: locked ? null : () => widget.onBlank(_index, _elapsed),
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

/// Rejilla de corrección de un simulacro. La comparten la fase de resultados
/// y el repaso del historial, igual que en la web (`SimulacroResultsGrid`):
/// los datos tienen la misma forma en los dos sitios, así que la pantalla
/// también.
class SimResultsView extends StatelessWidget {
  final List<SimQuestion> questions;
  final List<int?> answers;
  final List<SimResult?> results;
  final VoidCallback onRestart;
  final VoidCallback? onClose;

  /// Rótulo de la acción principal. En el historial no se "crea otro
  /// simulacro", se vuelve a la lista.
  final String restartLabel;
  final IconData restartIcon;

  /// Antetítulo. Un simulacro recién hecho se "completa"; uno del historial
  /// se repasa.
  final String eyebrow;

  const SimResultsView({
    super.key,
    required this.questions,
    required this.answers,
    required this.results,
    required this.onRestart,
    this.onClose,
    this.restartLabel = 'Crear otro simulacro',
    this.restartIcon = Icons.replay_rounded,
    this.eyebrow = 'SIMULACRO COMPLETADO',
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
              Text(eyebrow,
                  style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1.4)),
              const SizedBox(height: 10),
              Text('$correct / $total aciertos',
                  style: const TextStyle(
                      color: kInk,
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
            border: Border.all(color: kHairline, width: 2),
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
        StickerButton(
          label: restartLabel,
          icon: restartIcon,
          expand: true,
          onPressed: onRestart,
        ),
        if (onClose != null) ...[
          const SizedBox(height: 10),
          GhostButton(label: 'Volver', expand: true, onPressed: onClose),
        ],
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
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(3),
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
                style: TextStyle(
                    color: kMuted.withOpacity(0.75),
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
                        border: Border.all(color: kHairline, width: 2),
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
  // Ver la nota de `_SimulacroScreenState._showSubject`: viene apagado.
  bool _showSubject = false;

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
                  color: kInk, fontWeight: FontWeight.w900, fontSize: 19),
            ),
            const SizedBox(height: 16),
            // ¿Mostrar la asignatura?
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kHairline, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Mostrar la asignatura',
                        style: TextStyle(
                            color: kInk,
                            fontWeight: FontWeight.w900,
                            fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  InkSwitch(
                    value: _showSubject,
                    onChanged: (v) => setState(() => _showSubject = v),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: SectionLabel('Cómo quieres verlo'),
            ),
            _option(
              context,
              value: 'classic',
              title: 'Clásico',
              desc: 'Todo en una pantalla. Bajas para ver las opciones.',
              graphic: _classicGraphic(),
            ),
            const SizedBox(height: 12),
            _option(
              context,
              value: 'carousel',
              title: 'Deslizar',
              badge: 'NUEVO',
              desc: 'Una tarjeta cada vez. Pasas de lado.',
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
          border: Border.all(color: kHairline, width: 2),
        ),
        child: Row(
          children: [
            SizedBox(width: 72, height: 94, child: Center(child: graphic)),
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

  Widget _classicGraphic() => const ClassicLayoutArt();

  Widget _carouselGraphic() => const SwipeLayoutArt();
}

/// Mini maqueta vertical con flecha que pulsa hacia abajo (scroll).
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
