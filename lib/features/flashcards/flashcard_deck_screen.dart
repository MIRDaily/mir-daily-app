import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'flashcard_study_screen.dart';
import 'widgets/flashcard_dialogs.dart';

/// Las tarjetas de un grupo: listarlas, crearlas, editarlas y estudiarlas.
class FlashcardDeckScreen extends StatefulWidget {
  final FlashDeck deck;

  /// Cuando no es null, la pantalla está embebida en el panel derecho de un
  /// maestro-detalle (tablet grande): el botón de atrás deselecciona en el
  /// maestro en vez de hacer pop (aquí no hay ninguna ruta propia que cerrar).
  final VoidCallback? onClose;

  const FlashcardDeckScreen({super.key, required this.deck, this.onClose});

  @override
  State<FlashcardDeckScreen> createState() => _FlashcardDeckScreenState();
}

class _FlashcardDeckScreenState extends State<FlashcardDeckScreen> {
  List<Flashcard>? _cards;
  String? _error;
  bool _loading = true;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final cards = await _api.getFlashcards(widget.deck.id);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudieron cargar las tarjetas.';
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final count = _cards?.length ?? 0;
    if (count >= ApiService.maxFlashcardsPerDeck) {
      _toast('Este grupo ya tiene el máximo de '
          '${ApiService.maxFlashcardsPerDeck} tarjetas.');
      return;
    }
    final draft = await showFlashcardDialog(context);
    if (draft == null) return;
    try {
      await _api.createFlashcard(
        deckId: widget.deck.id,
        front: draft.front,
        back: draft.back,
      );
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo crear la tarjeta.');
    }
  }

  Future<void> _edit(Flashcard card) async {
    final draft = await showFlashcardDialog(
      context,
      initialFront: card.front,
      initialBack: card.back,
    );
    if (draft == null) return;
    try {
      await _api.updateFlashcard(
        flashcardId: card.flashcardId,
        front: draft.front,
        back: draft.back,
      );
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo guardar la tarjeta.');
    }
  }

  Future<void> _delete(Flashcard card) async {
    HapticFeedback.lightImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDelete(front: card.front),
    );
    if (ok != true) return;

    // Optimista: se quita ya de la lista y se recarga si el borrado falla.
    setState(() => _cards?.removeWhere((c) => c.itemId == card.itemId));
    try {
      await _api.deleteFlashcard(deckId: widget.deck.id, itemId: card.itemId);
    } catch (_) {
      _toast('No se pudo borrar la tarjeta.');
      _load();
    }
  }

  Future<void> _study() async {
    final count = _cards?.length ?? 0;
    if (count == 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlashcardStudyScreen(deck: widget.deck, limit: count),
      ),
    );
    _load();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: kInk,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards ?? const <Flashcard>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: widget.onClose == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onClose,
              ),
        title: Text(widget.deck.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Nueva tarjeta',
            icon: const Icon(Icons.add_rounded),
            onPressed: _create,
          ),
        ],
      ),
      floatingActionButton: cards.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: StickerButton(
                label: 'Estudiar',
                icon: Icons.play_arrow_rounded,
                onPressed: _study,
              ),
            ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : ListView(
                  physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                  children: [
                    if (_error != null) ...[
                      StickerCard(
                        depth: 4,
                        radius: 18,
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kInk, fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    SectionLabel('Tarjetas (${cards.length})'),
                    if (cards.isEmpty)
                      _EmptyCards(onCreate: _create)
                    else
                      for (final c in cards)
                        _FlashcardTile(
                          card: c,
                          onEdit: () => _edit(c),
                          onDelete: () => _delete(c),
                        ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Una tarjeta de la lista: se despliega para ver el reverso.
class _FlashcardTile extends StatefulWidget {
  final Flashcard card;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FlashcardTile({
    required this.card,
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
    return StickerCard(
      margin: const EdgeInsets.only(bottom: 12),
      depth: 3,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      texture: ruledPaper(step: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = !_open),
                  child: Text(
                    widget.card.front,
                    maxLines: _open ? null : 2,
                    overflow: _open ? null : TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kInk,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              InkIconButton(
                icon: _open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 34,
                onTap: () => setState(() => _open = !_open),
              ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            Container(height: 2, color: kHairline),
            const SizedBox(height: 12),
            Text(
              widget.card.back,
              style: TextStyle(
                color: kMuted,
                fontSize: 13.5,
                height: 1.5,
                backgroundColor: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                GhostButton(
                  label: 'Editar',
                  icon: Icons.edit_rounded,
                  compact: true,
                  onPressed: widget.onEdit,
                ),
                const SizedBox(width: 8),
                GhostButton(
                  label: 'Borrar',
                  icon: Icons.delete_outline_rounded,
                  compact: true,
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ],
        ],
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
          const Text(
            'Este grupo está vacío',
            style: TextStyle(
              color: kInk,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Añade tu primera tarjeta con el anverso y el reverso.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMuted.withOpacity(0.95),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          StickerButton(
            label: 'Nueva tarjeta',
            icon: Icons.add_rounded,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

class _ConfirmDelete extends StatelessWidget {
  final String front;

  const _ConfirmDelete({required this.front});

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
            const Text(
              '¿Borrar esta tarjeta?',
              style: TextStyle(
                color: kInk,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              front,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: kMuted, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Cancelar',
                    expand: true,
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StickerButton(
                    label: 'Borrar',
                    expand: true,
                    color: AppColors.error,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
