import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/audio/background_music.dart';
import '../../core/models/flashcards.dart';
import '../../core/models/models.dart';
import '../../core/providers/progress_provider.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'widgets/flashcard_dialogs.dart';
import 'widgets/flashcards_ui.dart';

/// Cómo se sale del estudio: «Otros ajustes» vuelve al grupo con los ajustes abiertos.
enum FlashStudyExit { volver, otrosAjustes }

/// Estudio de un grupo de flashcards, con las cuatro notas de Anki.
///
/// La sesión se abre con sus ajustes (`start-session`, ver flashcards.dart), la cola es propia
/// (`/flashcard-decks/:id/next`) y cada repaso va con su GRADO a `/flashcard-decks/:id/log`, que
/// planifica con FSRS. Los cuatro intervalos de los botones los manda el servidor con cada tarjeta.
/// Puerto del modo estudio de src/app/flashcards/[deckId]/page.tsx.
class FlashcardStudyScreen extends StatefulWidget {
  final FlashDeck deck;

  /// Tope de tarjetas servidas (con las repeticiones de las falladas).
  final int limit;

  /// Ajustes de la sesión tal y como los espera el servidor (paraEmpezar).
  final Map<String, dynamic> opciones;

  const FlashcardStudyScreen({
    super.key,
    required this.deck,
    required this.limit,
    this.opciones = const {},
  });

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

typedef _Deshacer = ({Flashcard card, int grade});

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> with SilencesBackgroundMusic {
  String? _sessionId;
  bool _sessionEnded = false;
  Flashcard? _card;
  Map<int, GradePreview> _preview = const {};
  bool _loading = true;
  bool _busy = false;
  bool _undoing = false;
  bool _revealed = false;
  bool _showSource = false;
  String? _error;

  /// Cómo terminó la sesión, para explicarlo bien al usuario.
  FlashNextKind? _finished;

  int _studied = 0;
  final Map<int, int> _byGrade = {};

  /// Pila para deshacer: la tarjeta Y el grado, que se descuenta del reparto del resumen. Es de la
  /// sesión: el servidor solo deshace repasos de la sesión en curso.
  final List<_Deshacer> _undoStack = [];

  /// Cuándo se mostró la tarjeta: cronómetro de la respuesta y origen de los intervalos.
  DateTime _shownAt = DateTime.now();

  /// Foto de la escalera al empezar, para decir al final qué se ha desbloqueado.
  Escalera? _ladderAntes;
  String _unlockedMsg = '';

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // Cerrar la sesión es "best-effort": si falla, el backend la caduca sola.
    _endSession();
    super.dispose();
  }

  void _endSession() {
    final id = _sessionId;
    if (id == null || _sessionEnded) return;
    _sessionEnded = true;
    _api.endDeckSession(id).catchError((_) {});
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
      _finished = null;
      _studied = 0;
      _byGrade.clear();
      _undoStack.clear();
      _unlockedMsg = '';
      _sessionEnded = false;
    });
    try {
      // Foto de antes (la de ahora mismo). Si falla, no se dice qué se ha desbloqueado y ya.
      _ladderAntes = widget.opciones['ladder'] == true
          ? await _api.getFlashcardLadder(widget.deck.id).then<Escalera?>((e) => e).catchError((_) => null)
          : null;
      final id = await _api.startFlashcardSession(widget.deck.id, widget.limit, opciones: widget.opciones);
      if (!mounted) return;
      _sessionId = id;
      await _next();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'No se pudo empezar la sesión de estudio.';
        _loading = false;
      });
    }
  }

  Future<void> _next() async {
    final id = _sessionId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _revealed = false;
    });
    try {
      final res = await _api.getNextFlashcard(widget.deck.id, id);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _busy = false;
        if (res.kind == FlashNextKind.card) {
          _card = res.card;
          _preview = res.preview;
          _shownAt = DateTime.now();
          _showSource = false;
        } else {
          _card = null;
          _finished = res.kind;
        }
      });
      if (_finished != null) _alTerminar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'No se pudo cargar la siguiente tarjeta.';
        _loading = false;
        _busy = false;
      });
    }
  }

  void _alTerminar() {
    _endSession();
    // Se acabó el repaso: el servidor ya ha sumado lo que tocaba, así que se relee el progreso y se
    // abre el permiso de celebrar. Nunca antes: a mitad de una tarjeta el usuario está estudiando.
    final progreso = context.read<ProgressProvider>();
    progreso.refresh().whenComplete(progreso.permitirCelebracion);
    final antes = _ladderAntes;
    _ladderAntes = null;
    if (antes == null) return;
    _api.getFlashcardLadder(widget.deck.id).then((despues) {
      if (mounted) setState(() => _unlockedMsg = textoDesbloqueo(desbloqueados(antes, despues)));
    }).catchError((_) {});
  }

  Future<void> _answer(int grade) async {
    final id = _sessionId;
    final card = _card;
    if (id == null || card == null || _busy || !_revealed) return;

    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      await _api.logFlashcard(
        deckId: widget.deck.id,
        deckItemId: card.itemId,
        grade: grade,
        sessionId: id,
        timeSpent: DateTime.now().difference(_shownAt).inSeconds,
      );
      if (!mounted) return;
      setState(() {
        _studied++;
        _byGrade[grade] = (_byGrade[grade] ?? 0) + 1;
        _undoStack.add((card: card, grade: grade));
      });
      await _next();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e is ApiException ? e.message : 'No se pudo registrar la respuesta.');
    }
  }

  /// Deshace el último repaso. Funciona también con la sesión terminada: es justo cuando uno se da
  /// cuenta de que la última respuesta no era la que quería.
  Future<void> _undo() async {
    final id = _sessionId;
    if (id == null || _busy || _undoing || _undoStack.isEmpty) return;
    setState(() => _undoing = true);
    try {
      final restored = await _api.undoFlashcardReview(widget.deck.id, id);
      if (!mounted) return;
      if (restored == null) {
        _toast('Ese repaso ya no se puede deshacer.');
        return;
      }
      final ultimo = _undoStack.removeLast();
      setState(() {
        _studied = math.max(0, _studied - 1);
        _byGrade[ultimo.grade] = math.max(0, (_byGrade[ultimo.grade] ?? 0) - 1);
        // Se vuelve a enseñar la tarjeta ya girada: quien deshace quiere cambiar la respuesta, no
        // volver a leerse el anverso. Los intervalos, los del estado restaurado.
        _card = ultimo.card;
        _preview = restored.preview;
        _revealed = true;
        _finished = null;
        _sessionEnded = false;
        _shownAt = DateTime.now();
      });
    } catch (e) {
      _toast(e is ApiException ? e.message : 'No se pudo deshacer el repaso.');
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }

  /// Corregir la tarjeta sin salir de la sesión: la IA se equivoca y es aquí donde se ve.
  Future<void> _editCurrent() async {
    final card = _card;
    if (card == null || _busy) return;
    final draft = await showFlashcardDialog(context, initialFront: card.front, initialBack: card.back, initialLevel: card.level);
    if (draft == null || !mounted) return;
    try {
      await _api.updateFlashcard(
        flashcardId: card.flashcardId,
        front: draft.front,
        back: draft.back,
        setLevel: draft.level != card.level,
        level: draft.level,
      );
      if (!mounted || _card?.itemId != card.itemId) return;
      setState(() => _card = card.copyWith(front: draft.front, back: draft.back, level: () => draft.level));
    } catch (e) {
      _toast(e is ApiException ? e.message : 'No se pudo guardar la tarjeta.');
    }
  }

  Future<void> _deleteCurrent() async {
    final card = _card;
    if (card == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar esta tarjeta?'),
        content: const Text('Se puede recuperar durante 24 horas desde el grupo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.deleteFlashcard(deckId: widget.deck.id, itemId: card.itemId);
      // La cola ya no la vuelve a servir.
      await _next();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e is ApiException ? e.message : 'No se pudo borrar la tarjeta.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: kInk),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = colorDeGrupo(widget.deck).bg;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.deck.name, overflow: TextOverflow.ellipsis),
          const Text('Repaso', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Deshacer el último repaso',
            icon: const Icon(Icons.undo_rounded),
            onPressed: _undoStack.isEmpty || _undoing || _busy ? null : _undo,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: DocChip(label: '$_studied repasadas', tone: DocTone.accent)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: widget.limit > 0 ? (_studied / widget.limit).clamp(0, 1).toDouble() : 0,
                minHeight: 5,
                backgroundColor: const Color(0xFFEFEAE7),
                color: color,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _error != null && _card == null && _finished == null
            ? _Message(
                icon: Icons.cloud_off_rounded,
                title: 'Algo ha fallado',
                body: _error!,
                actionLabel: 'Volver',
                onAction: () => Navigator.of(context).pop(FlashStudyExit.volver),
              )
            : _finished != null
                ? _finishedView()
                : _loading || _card == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _studyView(_card!),
      ),
    );
  }

  Widget _studyView(Flashcard card) {
    final ancho = MediaQuery.sizeOf(context).width >= 560;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          child: Row(children: [
            if (card.level != null) NivelBadge(card.level!),
            if (card.tema.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(child: DocChip(label: card.tema, icon: Icons.sell_rounded)),
            ],
            const Spacer(),
            IconButton(
              tooltip: 'Editar esta tarjeta',
              onPressed: _busy ? null : _editCurrent,
              icon: const Icon(Icons.edit_rounded, size: 20),
              color: kMuted,
            ),
            IconButton(
              tooltip: 'Borrar esta tarjeta',
              onPressed: _busy ? null : _deleteCurrent,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: kMuted,
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: _FlipCard(
              revealed: _revealed,
              front: card.front,
              back: card.back,
              onTap: () => setState(() => _revealed = !_revealed),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: kInk, width: 2)),
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!_revealed)
                StickerButton(
                  label: 'Mostrar respuesta',
                  icon: Icons.flip_rounded,
                  expand: true,
                  onPressed: () => setState(() => _revealed = true),
                )
              else
                _GradeGrid(
                  preview: _preview,
                  from: _shownAt,
                  columnas: ancho ? 4 : 2,
                  disabled: _busy,
                  onGrade: _answer,
                ),
              if (_revealed && card.source != null) ...[
                const SizedBox(height: 10),
                _Fuente(
                  source: card.source!,
                  abierta: _showSource,
                  onAlternar: () => setState(() => _showSource = !_showSource),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _finishedView() {
    final title = switch (_finished!) {
      FlashNextKind.limit => 'Límite de la sesión alcanzado',
      FlashNextKind.expired => 'La sesión expiró',
      _ => '¡Sesión completada!',
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: StickerCard(
            depth: 6,
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: kInk, width: 2),
                  boxShadow: inkShadow(4),
                ),
                child: Icon(_finished == FlashNextKind.done ? Icons.task_alt_rounded : Icons.timer_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(style: const TextStyle(color: kMuted, fontSize: 14), children: [
                  const TextSpan(text: 'Has repasado '),
                  TextSpan(text: '$_studied', style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
                  const TextSpan(text: ' tarjetas.'),
                ]),
              ),
              if (_unlockedMsg.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF0DA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kInk, width: 2),
                    boxShadow: inkShadow(3),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock_open_rounded, color: Color(0xFFB07A1E)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_unlockedMsg, style: const TextStyle(color: kInk, fontSize: 13.5, fontWeight: FontWeight.w800))),
                  ]),
                ),
              ],
              if (_studied > 0) ...[
                const SizedBox(height: 16),
                Row(children: [
                  for (final b in kGradeButtons)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: b.bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: b.fg, width: 2),
                        ),
                        child: Column(children: [
                          Text('${_byGrade[b.grade] ?? 0}', style: TextStyle(color: b.fg, fontSize: 19, fontWeight: FontWeight.w900)),
                          Text(
                            b.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kMuted, fontSize: 9, fontWeight: FontWeight.w800),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 20),
              StickerButton(label: 'Repasar de nuevo', icon: Icons.replay_rounded, expand: true, onPressed: _start),
              const SizedBox(height: 8),
              GhostButton(
                label: 'Otros ajustes',
                icon: Icons.tune_rounded,
                expand: true,
                onPressed: () => Navigator.of(context).pop(FlashStudyExit.otrosAjustes),
              ),
              if (_undoStack.isNotEmpty) ...[
                const SizedBox(height: 8),
                GhostButton(label: 'Deshacer la última', icon: Icons.undo_rounded, expand: true, onPressed: _undoing ? null : _undo),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(FlashStudyExit.volver),
                child: const Text('Volver al grupo'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Los cuatro botones de respuesta, cada uno con el intervalo que le tocaría a la tarjeta.
class _GradeGrid extends StatelessWidget {
  final Map<int, GradePreview> preview;
  final DateTime from;
  final int columnas;
  final bool disabled;
  final ValueChanged<int> onGrade;

  const _GradeGrid({required this.preview, required this.from, required this.columnas, required this.disabled, required this.onGrade});

  @override
  Widget build(BuildContext context) {
    Widget boton(({int grade, String label, IconData icon, Color fg, Color bg}) b) => Padding(
          padding: const EdgeInsets.all(4),
          child: Semantics(
            button: true,
            label: '${b.label}: vuelve en ${formatInterval(preview[b.grade], from)}',
            excludeSemantics: true,
            child: Opacity(
              opacity: disabled ? 0.5 : 1,
              child: GestureDetector(
                onTap: disabled ? null : () => onGrade(b.grade),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: b.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kInk, width: 2),
                    boxShadow: [BoxShadow(color: b.fg, offset: const Offset(3, 3))],
                  ),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(b.icon, size: 18, color: b.fg),
                      const SizedBox(width: 5),
                      Text(b.label, style: TextStyle(color: b.fg, fontSize: 14, fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      formatInterval(preview[b.grade], from),
                      style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );

    final filas = <Widget>[];
    for (var i = 0; i < kGradeButtons.length; i += columnas) {
      filas.add(Row(children: [
        for (final b in kGradeButtons.skip(i).take(columnas)) Expanded(child: boton(b)),
      ]));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: filas);
  }
}

/// «Ver de dónde sale» al estudiar una tarjeta de la IA: el archivo y la página y el trozo del texto.
/// (Abrir la rama del mapa llega con los mapas en la app.)
class _Fuente extends StatelessWidget {
  final FlashSource source;
  final bool abierta;
  final VoidCallback onAlternar;

  const _Fuente({required this.source, required this.abierta, required this.onAlternar});

  @override
  Widget build(BuildContext context) {
    final lugar = source.lugar;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4C8BE), width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onAlternar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              const Icon(Icons.menu_book_rounded, size: 19, color: Color(0xFFC99A8D)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Ver de dónde sale', style: TextStyle(color: kInk, fontSize: 13.5, fontWeight: FontWeight.w800))),
              Icon(abierta ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: kMuted),
            ]),
          ),
        ),
        if (abierta)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (lugar.isNotEmpty) Text(lugar, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (source.snippet != null)
                Container(
                  padding: const EdgeInsets.only(left: 10),
                  decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFE8A598), width: 4))),
                  child: Text(source.snippet!, style: const TextStyle(color: kInk, fontSize: 13.5, height: 1.45)),
                )
              else
                const Text('No se guardó el trozo del texto de esta tarjeta.', style: TextStyle(color: kMuted, fontSize: 12)),
            ]),
          ),
      ]),
    );
  }
}

/// La tarjeta que se voltea. El giro es de verdad (3D con perspectiva), y a
/// mitad de camino se cambia la cara para que nunca se lea el texto del revés.
///
/// Las dos caras se construyen **una vez** y solo se mueven: antes se volvían a
/// montar en cada fotograma, y con ellas la textura de la cartulina, que son
/// varias decenas de líneas por repintado.
class _FlipCard extends StatefulWidget {
  final bool revealed;
  final String front;
  final String back;
  final VoidCallback onTap;

  const _FlipCard({
    required this.revealed,
    required this.front,
    required this.back,
    required this.onTap,
  });

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.revealed ? 1 : 0,
  );

  late final CurvedAnimation _t =
      CurvedAnimation(parent: _c, curve: kEaseOut);

  // Las caras, cacheadas. Solo se rehacen si cambia el texto, o sea al pasar
  // de tarjeta.
  Widget? _frontFace;
  Widget? _backFace;

  @override
  void initState() {
    super.initState();
    _buildFaces();
  }

  @override
  void didUpdateWidget(covariant _FlipCard old) {
    super.didUpdateWidget(old);
    if (old.front != widget.front || old.back != widget.back) _buildFaces();
    if (old.revealed != widget.revealed) {
      widget.revealed ? _c.forward() : _c.reverse();
    }
  }

  void _buildFaces() {
    _frontFace = _face(
      text: widget.front,
      label: 'ANVERSO',
      accent: kAccent,
    );
    _backFace = _face(
      text: widget.back,
      label: 'REVERSO',
      accent: AppColors.success,
    );
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final angle = _t.value * math.pi;
            final showBack = _t.value > 0.5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012) // perspectiva
                ..rotateY(angle),
              child: Transform(
                alignment: Alignment.center,
                // La cara de atrás se contragira, o saldría en espejo.
                transform: Matrix4.identity()..rotateY(showBack ? math.pi : 0),
                // Al ser la MISMA instancia de widget entre fotogramas, Flutter
                // se salta el rebuild del subárbol.
                child: showBack ? _backFace! : _frontFace!,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _face({
    required String text,
    required String label,
    required Color accent,
  }) {
    return StickerCard(
      depth: 6,
      radius: 24,
      padding: const EdgeInsets.all(22),
      texture: tintedPaper(accent, step: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: kInk, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  color: kMuted.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                text,
                style: const TextStyle(
                  color: kInk,
                  fontSize: 18,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              'Toca la tarjeta para girarla',
              style: TextStyle(
                color: kMuted.withOpacity(0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: StickerCard(
          depth: 5,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: kInk, width: 2),
                  boxShadow: inkShadow(4),
                ),
                child: Icon(icon, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kInk,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kMuted.withOpacity(0.95),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              StickerButton(
                label: actionLabel,
                expand: true,
                onPressed: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
