import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/flashcards.dart';
import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/services/carpetas.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ia/destino_carpeta.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'flashcard_study_screen.dart';
import 'widgets/ajustes_sesion_sheet.dart';
import 'widgets/escalera_panel.dart';
import 'widgets/flashcard_dialogs.dart';
import 'widgets/flashcards_ui.dart';

/// Un grupo de flashcards (una «asignatura»): su dominio y sus cubos, la escalera de dificultad,
/// los temas en lista tipo Anki y las tarjetas de cada tema. Desde aquí se crean, corrigen, mueven,
/// copian o borran tarjetas, y se estudia con los ajustes de la sesión.
/// Puerto de src/app/flashcards/page.tsx (nivel de asignatura y de tema) y [deckId]/page.tsx.
class FlashcardDeckScreen extends StatefulWidget {
  final FlashDeck deck;

  /// Cuando no es null, la pantalla está embebida en el panel derecho de un
  /// maestro-detalle (tablet grande): el botón de atrás deselecciona en el
  /// maestro en vez de hacer pop (aquí no hay ninguna ruta propia que cerrar).
  final VoidCallback? onClose;

  /// El grupo ha cambiado (tarjetas, carpeta o papelera): la lista se recarga.
  final VoidCallback? onChanged;

  /// Al cargar, abre los ajustes de la sesión («Estudiar» desde la lista).
  final bool autoStudy;

  const FlashcardDeckScreen({super.key, required this.deck, this.onClose, this.onChanged, this.autoStudy = false});

  @override
  State<FlashcardDeckScreen> createState() => _FlashcardDeckScreenState();
}

class _FlashcardDeckScreenState extends State<FlashcardDeckScreen> {
  List<Flashcard>? _cards;
  String? _error;
  bool _loading = true;
  Escalera? _ladder;
  AjustesSesion _ajustes = kAjustesPorDefecto;

  /// Tema abierto (null = la lista de temas; '' = las tarjetas sin tema).
  String? _tema;

  /// Selección múltiple (por itemId).
  final Set<int> _sel = {};
  bool _selecting = false;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _load();
    leerAjustesGuardados(widget.deck.id).then((a) {
      if (a != null && mounted) setState(() => _ajustes = a);
    });
  }

  bool _autoStudyHecho = false;

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final cards = await _api.getFlashcards(widget.deck.id);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
        _sel.retainAll(cards.map((c) => c.itemId));
        if (_tema != null && !cards.any((c) => c.tema == _tema)) _tema = null;
      });
      // La escalera no es imprescindible: si falla, el grupo se usa igual (sin el panel).
      if (cards.any((c) => c.level != null)) {
        _api.getFlashcardLadder(widget.deck.id).then((e) {
          if (mounted) setState(() => _ladder = e);
        }).catchError((_) {
          if (mounted) setState(() => _ladder = null);
        });
      } else {
        setState(() => _ladder = null);
      }
      if (widget.autoStudy && !_autoStudyHecho && cards.isNotEmpty) {
        _autoStudyHecho = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _study();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'No se pudieron cargar las tarjetas.';
        _loading = false;
      });
    }
  }

  void _changed() {
    widget.onChanged?.call();
    _load();
  }

  // ---- Tarjetas ------------------------------------------------------------

  Future<void> _create() async {
    final count = _cards?.length ?? 0;
    if (count >= ApiService.maxFlashcardsPerDeck) {
      _toast('Este grupo ya tiene el máximo de ${ApiService.maxFlashcardsPerDeck} tarjetas.');
      return;
    }
    final creadas = await showFlashcardCreator(
      context,
      deckName: widget.deck.name,
      initialCount: count,
      initialTopic: _tema ?? '',
      onSave: (d) async {
        try {
          await _api.createFlashcard(deckId: widget.deck.id, front: d.front, back: d.back, topic: d.topic, level: d.level);
          return null;
        } on ApiException catch (e) {
          return e.message;
        } catch (_) {
          return 'No se pudo crear la tarjeta.';
        }
      },
    );
    if (creadas > 0) _changed();
  }

  Future<void> _edit(Flashcard card) async {
    final draft = await showFlashcardDialog(context, initialFront: card.front, initialBack: card.back, initialLevel: card.level);
    if (draft == null) return;
    try {
      await _api.updateFlashcard(
        flashcardId: card.flashcardId,
        front: draft.front,
        back: draft.back,
        setLevel: draft.level != card.level,
        level: draft.level,
      );
      _changed();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo guardar la tarjeta.');
    }
  }

  Future<void> _delete(Flashcard card) async {
    HapticFeedback.lightImpact();
    final ok = await _confirmar('¿Borrar esta tarjeta?', card.front, 'Borrar');
    if (ok != true) return;
    // Optimista: se quita ya de la lista y se recarga si el borrado falla.
    setState(() => _cards?.removeWhere((c) => c.itemId == card.itemId));
    try {
      await _api.deleteFlashcard(deckId: widget.deck.id, itemId: card.itemId);
      _changed();
    } catch (_) {
      _toast('No se pudo borrar la tarjeta.');
      _load();
    }
  }

  // ---- Selección múltiple: copiar, mover o borrar --------------------------

  void _toggle(Flashcard c) => setState(() {
        if (!_sel.remove(c.itemId)) _sel.add(c.itemId);
        _selecting = _sel.isNotEmpty;
      });

  void _clearSel() => setState(() {
        _sel.clear();
        _selecting = false;
      });

  Future<void> _bulkDelete() async {
    final n = _sel.length;
    final ok = await _confirmar('¿Eliminar $n ${n == 1 ? 'tarjeta' : 'tarjetas'}?', 'Se pueden recuperar durante 24 horas.', 'Eliminar');
    if (ok != true) return;
    final ids = _sel.toList();
    _clearSel();
    try {
      await _api.bulkDeleteFlashcards(ids);
    } catch (e) {
      _toast(e is ApiException ? e.message : 'No se pudieron eliminar las tarjetas.');
    }
    _changed();
  }

  Future<void> _destino({required bool mover}) async {
    List<FlashDeck> grupos;
    try {
      grupos = (await _api.getFlashDecks()).where((d) => d.id != widget.deck.id).toList();
    } catch (_) {
      _toast('No se pudieron cargar tus grupos.');
      return;
    }
    if (!mounted) return;
    if (grupos.isEmpty) {
      _toast('No tienes otro grupo al que ${mover ? 'moverlas' : 'copiarlas'}.');
      return;
    }
    final n = _sel.length;
    final destino = await showModalBottomSheet<FlashDeck>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
            Text(
              '${mover ? 'Mover' : 'Copiar'} $n ${n == 1 ? 'tarjeta' : 'tarjetas'} a…',
              style: const TextStyle(color: kInk, fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final g in grupos)
              ListTile(
                leading: CircleAvatar(backgroundColor: colorDeGrupo(g).bg, child: Icon(iconoDeGrupo(g), color: Colors.white, size: 20)),
                title: Text(g.name, style: const TextStyle(color: kInk, fontWeight: FontWeight.w800)),
                subtitle: Text('${g.totalCards} ${g.totalCards == 1 ? 'tarjeta' : 'tarjetas'}'),
                onTap: () => Navigator.pop(ctx, g),
              ),
          ]),
        ),
      ),
    );
    if (destino == null || !mounted) return;
    final ids = _sel.toList();
    try {
      final r = mover ? await _api.moveFlashcards(ids, destino.id) : await _api.copyFlashcards(ids, destino.id);
      _clearSel();
      if (r.alreadyThere > 0) {
        final hechas = r.done > 0 ? '${r.done} ${mover ? 'movida' : 'copiada'}${r.done == 1 ? '' : 's'}. ' : '';
        _toast('$hechas${r.alreadyThere} ya ${mover ? 'estaban' : 'existían'} en «${destino.name}»${mover ? '' : ' y no se duplicaron'}.');
      } else {
        _toast('${r.done} ${r.done == 1 ? 'tarjeta' : 'tarjetas'} ${mover ? 'movidas' : 'copiadas'} a «${destino.name}».');
      }
    } catch (e) {
      _toast(e is ApiException ? e.message : 'No se pudieron ${mover ? 'mover' : 'copiar'} las tarjetas.');
    }
    _changed();
  }

  // ---- Grupo: carpeta y papelera ---------------------------------------------

  Future<void> _moverACarpeta() async {
    final carpetas = context.read<CarpetasApi>();
    try {
      final arbol = await carpetas.arbol();
      if (!mounted) return;
      final actual = Carpeta(subjectId: widget.deck.folderSubjectId, topicId: widget.deck.folderTopicId);
      final elegida = await elegirCarpeta(context, arbol: arbol, valor: actual);
      if (elegida == null || elegida == actual) return;
      await carpetas.mover('flashcards', [widget.deck.id], elegida);
      _toast('Movido a ${nombreCarpeta(arbol, elegida)}.');
      widget.onChanged?.call();
    } catch (e) {
      _toast(e is ApiException ? e.message : 'No se pudo mover el grupo.');
    }
  }

  Future<void> _papelera() async {
    final ok = await _confirmar('¿Enviar «${widget.deck.name}» a la papelera?', 'Se puede recuperar durante 24 horas.', 'Enviar');
    if (ok != true) return;
    try {
      await _api.deleteFlashDeck(widget.deck.id);
      widget.onChanged?.call();
      if (!mounted) return;
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _toast(e is ApiException ? e.message : 'No se pudo eliminar el grupo.');
    }
  }

  // ---- Estudio -----------------------------------------------------------------

  Future<void> _study() async {
    final cards = _cards ?? const <Flashcard>[];
    if (cards.isEmpty) return;
    // Desde un tema, los ajustes llegan con ese tema elegido.
    final inicial = _tema != null ? _ajustes.copyWith(temas: () => [_tema!]) : _ajustes;
    final a = await elegirAjustesSesion(context, deckName: widget.deck.name, cards: cards, inicial: inicial, escalera: _ladder);
    if (a == null || !mounted) return;
    setState(() => _ajustes = a);
    guardarAjustes(widget.deck.id, a);
    final conNivel = cards.any((c) => c.level != null);
    final p = paraEmpezar(a, cards, conNivel, _ladder);
    final salida = await Navigator.of(context).push<FlashStudyExit>(
      MaterialPageRoute(builder: (_) => FlashcardStudyScreen(deck: widget.deck, limit: p.limit, opciones: p.opciones)),
    );
    _changed();
    if (salida == FlashStudyExit.otrosAjustes && mounted) _study();
  }

  // ---- Utilidades ----------------------------------------------------------------

  Future<bool?> _confirmar(String titulo, String texto, String accion) => showDialog<bool>(
        context: context,
        builder: (ctx) => _ConfirmDelete(title: titulo, body: texto, action: accion),
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: kInk),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards ?? const <Flashcard>[];
    final embedded = widget.onClose != null;
    final topics = groupTopics(cards);
    final hasTopics = topics.any((t) => t.key != null);
    final enTema = _tema != null;
    final visibles = enTema ? cards.where((c) => c.tema == _tema).toList() : (hasTopics ? const <Flashcard>[] : cards);
    final conNivel = cards.any((c) => c.level != null);
    final summary = FlashSummary(
      nuevas: cards.where((c) => c.status == FlashStatus.nueva).length,
      failed: cards.where((c) => c.status == FlashStatus.failed).length,
      learning: cards.where((c) => c.status == FlashStatus.learning).length,
      mastered: cards.where((c) => c.status == FlashStatus.mastered).length,
    );
    final ruta = ['Mis flashcards', widget.deck.name, if (enTema) (_tema!.isEmpty ? 'Sin tema' : _tema!)].join(' › ');

    return PopScope(
      canPop: !enTema && !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSel();
        } else {
          setState(() => _tema = null);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: enTema
              ? IconButton(
                  tooltip: 'Volver a los temas',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() {
                    _tema = null;
                    _clearSel();
                  }),
                )
              : (!embedded ? null : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onClose)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              enTema ? (_tema!.isEmpty ? 'Sin tema' : _tema!) : widget.deck.name,
              overflow: TextOverflow.ellipsis,
            ),
            // La ruta completa, como en la cabecera de la web.
            Text(ruta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
          actions: [
            IconButton(tooltip: 'Crear tarjetas', icon: const Icon(Icons.add_rounded), onPressed: _create),
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (v) => switch (v) {
                'sel' => setState(() => _selecting = true),
                'carpeta' => _moverACarpeta(),
                'papelera' => _papelera(),
                _ => null,
              },
              itemBuilder: (_) => [
                if (visibles.isNotEmpty) const PopupMenuItem(value: 'sel', child: Text('Seleccionar tarjetas')),
                const PopupMenuItem(value: 'carpeta', child: Text('Mover a carpeta…')),
                const PopupMenuItem(value: 'papelera', child: Text('Enviar a la papelera')),
              ],
            ),
          ],
        ),
        floatingActionButton: cards.isEmpty || _selecting
            ? null
            : Padding(
                padding: EdgeInsets.only(bottom: embedded ? 12 : 4, right: 4),
                child: StickerButton(label: 'Estudiar', icon: Icons.play_arrow_rounded, onPressed: _study),
              ),
        bottomNavigationBar: _selecting ? _barraSeleccion(visibles) : null,
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                    children: [
                      if (_error != null) ...[
                        StickerCard(
                          depth: 4,
                          radius: 18,
                          padding: const EdgeInsets.all(18),
                          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kInk, fontSize: 13.5)),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (cards.isNotEmpty && !enTema) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFE4DCD8), width: 2),
                          ),
                          child: SummaryTiles(summary: summary, total: cards.length),
                        ),
                        const SizedBox(height: 14),
                        if (conNivel && hayEscalera(_ladder)) ...[
                          EscaleraPanel(escalera: _ladder!, activa: _ajustes.escalera),
                          const SizedBox(height: 14),
                        ],
                      ],
                      if (cards.isEmpty)
                        _EmptyCards(onCreate: _create)
                      else if (hasTopics && !enTema) ...[
                        SectionLabel('${topics.length} ${topics.length == 1 ? 'tema' : 'temas'}'),
                        const WorkCountsHeader(trailing: 30),
                        const SizedBox(height: 4),
                        for (final t in topics) _TopicTile(row: t, color: colorDeGrupo(widget.deck).bg, onTap: () => setState(() => _tema = t.key ?? '')),
                      ] else ...[
                        SectionLabel('Tarjetas (${visibles.length})'),
                        for (final c in visibles)
                          _FlashcardTile(
                            card: c,
                            selecting: _selecting,
                            selected: _sel.contains(c.itemId),
                            onToggle: () => _toggle(c),
                            onEdit: () => _edit(c),
                            onDelete: () => _delete(c),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _barraSeleccion(List<Flashcard> visibles) {
    final n = _sel.length;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(4),
        ),
        child: Row(children: [
          IconButton(tooltip: 'Cancelar selección', icon: const Icon(Icons.close_rounded), onPressed: _clearSel),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n ${n == 1 ? 'seleccionada' : 'seleccionadas'}', style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
              GestureDetector(
                onTap: () => setState(() => _sel.addAll(visibles.map((c) => c.itemId))),
                child: const Text('Seleccionar todas', style: TextStyle(color: AppColors.primaryDark, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          IconButton(tooltip: 'Copiar', icon: const Icon(Icons.content_copy_rounded), onPressed: n == 0 ? null : () => _destino(mover: false)),
          IconButton(tooltip: 'Mover', icon: const Icon(Icons.drive_file_move_rounded), onPressed: n == 0 ? null : () => _destino(mover: true)),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: n == 0 ? null : _bulkDelete,
          ),
        ]),
      ),
    );
  }
}

/// Un tema en la lista tipo Anki: dominio y las tres columnas (nuevas, falladas, repasos).
class _TopicTile extends StatelessWidget {
  final TopicRow row;
  final Color color;
  final VoidCallback onTap;

  const _TopicTile({required this.row, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final idle = row.dueCards == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: idle ? const Color(0xFFEFEAE7) : const Color(0xFFE4DCD8), width: 2),
            ),
            child: Row(children: [
              Container(width: 5, height: 32, decoration: BoxDecoration(color: color.withOpacity(idle ? 0.4 : 1), borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: idle ? const Color(0xFF9CA3AF) : kInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      fontStyle: row.key == null ? FontStyle.italic : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MasteryBar(percent: row.dominio, total: row.total),
                ]),
              ),
              const SizedBox(width: 8),
              WorkCounts(nuevas: row.summary.nuevas, falladas: row.summary.failed, repasos: row.repasos),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFC9CFD5)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Una tarjeta de la lista: se despliega para ver el reverso. En modo selección, se marca.
class _FlashcardTile extends StatefulWidget {
  final Flashcard card;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FlashcardTile({
    required this.card,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_FlashcardTile> createState() => _FlashcardTileState();
}

class _FlashcardTileState extends State<_FlashcardTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    return GestureDetector(
      onLongPress: widget.onToggle,
      child: StickerCard(
        margin: const EdgeInsets.only(bottom: 12),
        depth: widget.selected ? 1 : 3,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        texture: ruledPaper(step: 24),
        background: widget.selected ? const Color(0xFFFFF4F1) : Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.level != null || c.aiGenerated || c.tema.isNotEmpty) ...[
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (c.tema.isNotEmpty) DocChip(label: c.tema, icon: Icons.sell_rounded),
                if (c.level != null) NivelBadge(c.level!),
                if (c.aiGenerated)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(10)),
                    child: const Text('IA', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                  ),
              ]),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.selecting)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Checkbox(value: widget.selected, onChanged: (_) => widget.onToggle(), activeColor: kAccent),
                  ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.selecting ? widget.onToggle : () => setState(() => _open = !_open),
                    child: Text(
                      c.front,
                      maxLines: _open ? null : 2,
                      overflow: _open ? null : TextOverflow.ellipsis,
                      style: const TextStyle(color: kInk, fontWeight: FontWeight.w700, fontSize: 14, height: 1.4),
                    ),
                  ),
                ),
                if (!widget.selecting)
                  InkIconButton(
                    icon: _open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 34,
                    onTap: () => setState(() => _open = !_open),
                  ),
              ],
            ),
            if (_open && !widget.selecting) ...[
              const SizedBox(height: 12),
              Container(height: 2, color: kHairline),
              const SizedBox(height: 12),
              Text(
                c.back,
                style: TextStyle(color: kMuted, fontSize: 13.5, height: 1.5, backgroundColor: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  GhostButton(label: 'Editar', icon: Icons.edit_rounded, compact: true, onPressed: widget.onEdit),
                  const SizedBox(width: 8),
                  GhostButton(label: 'Borrar', icon: Icons.delete_outline_rounded, compact: true, onPressed: widget.onDelete),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCards extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyCards({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(24),
      texture: ruledPaper(step: 26),
      child: Column(
        children: [
          const Text('Este grupo está vacío', style: TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'Añade tus tarjetas con el anverso y el reverso; puedes crear varias seguidas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted.withOpacity(0.95), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          StickerButton(label: 'Crear tarjetas', icon: Icons.add_rounded, onPressed: onCreate),
        ],
      ),
    );
  }
}

class _ConfirmDelete extends StatelessWidget {
  final String title;
  final String body;
  final String action;

  const _ConfirmDelete({required this.title, required this.body, required this.action});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: StickerCard(
        depth: 6,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 10),
            Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: kMuted, fontSize: 13, height: 1.45)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'Cancelar', expand: true, onPressed: () => Navigator.pop(context, false))),
                const SizedBox(width: 10),
                Expanded(
                  child: StickerButton(label: action, expand: true, color: AppColors.error, onPressed: () => Navigator.pop(context, true)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
