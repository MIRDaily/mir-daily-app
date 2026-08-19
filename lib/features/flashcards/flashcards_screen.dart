import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../../shared/widgets/misc_widgets.dart';
import 'flashcard_deck_screen.dart';
import 'widgets/flashcard_dialogs.dart';

/// Flashcards personalizadas: los grupos de tarjetas del usuario.
///
/// Son mazos con `kind='flashcards'` en el backend y tienen endpoints propios
/// (`/api/studio/flashcard-decks`) para no mezclarse con la biblioteca de
/// mazos de preguntas. Reutilizan el motor SRS, pero **no cuentan para las
/// estadísticas globales**: son notas del usuario, no preguntas del MIR.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  List<FlashDeck>? _decks;
  String? _error;
  bool _loading = true;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _decks == null;
        _error = null;
      });
    }
    try {
      final decks = await _api.getFlashDecks();
      if (!mounted) return;
      setState(() {
        _decks = decks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudieron cargar tus grupos. Desliza para reintentar.';
        _loading = false;
      });
    }
  }

  Future<void> _createDeck() async {
    final data = await showFlashDeckDialog(context);
    if (data == null) return;
    try {
      await _api.createFlashDeck(data.name, description: data.description);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo crear el grupo.');
    }
  }

  Future<void> _renameDeck(FlashDeck deck) async {
    final data = await showFlashDeckDialog(
      context,
      initialName: deck.name,
      initialDescription: deck.description ?? '',
    );
    if (data == null) return;
    try {
      await _api.updateFlashDeck(
        deck.id,
        name: data.name,
        description: data.description,
      );
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo actualizar el grupo.');
    }
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

  Future<void> _open(FlashDeck deck) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FlashcardDeckScreen(deck: deck)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final decks = _decks ?? const <FlashDeck>[];
    final due = decks.fold<int>(0, (a, d) => a + d.dueCards);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 4),
        child: StickerButton(
          label: 'Nuevo grupo',
          icon: Icons.add_rounded,
          onPressed: _createDeck,
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 100),
            children: [
              StickerHero(
                badge: 'Flashcards',
                badgeIcon: Icons.style_rounded,
                title: 'Tus tarjetas',
                subtitle:
                    'Crea y repasa tus propias tarjetas, con anverso y reverso.',
                aside: due > 0
                    ? StatChip(value: '$due', label: 'por repasar')
                    : null,
              ),
              const SizedBox(height: 24),
              if (_loading)
                for (var i = 0; i < 3; i++) const _FlashDeckSkeleton()
              else if (_error != null)
                _ErrorBox(message: _error!, onRetry: _load)
              else if (decks.isEmpty)
                const _EmptyFlashcards()
              else ...[
                const SectionLabel('Tus grupos'),
                for (var i = 0; i < decks.length; i++)
                  SlideFadeIn(
                    delay: Duration(milliseconds: 70 * (i % 8)),
                    beginOffset: const Offset(0, 0.12),
                    child: _FlashDeckCard(
                      deck: decks[i],
                      onTap: () => _open(decks[i]),
                      onRename: () => _renameDeck(decks[i]),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ficha de un grupo: nombre, cuántas tarjetas tiene y cuántas tocan hoy.
class _FlashDeckCard extends StatelessWidget {
  final FlashDeck deck;
  final VoidCallback onTap;
  final VoidCallback onRename;

  const _FlashDeckCard({
    required this.deck,
    required this.onTap,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final hasDue = deck.dueCards > 0;

    return StickerCard(
      margin: const EdgeInsets.only(bottom: 14),
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(16),
      // Cartulina rayada, como una ficha de estudio de verdad.
      texture: ruledPaper(step: 24),
      onTap: onTap,
      child: Row(
        children: [
          const _CardStackArt(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deck.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kInk,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
                if ((deck.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    deck.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 12,
                      backgroundColor: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    DocChip(
                      label: deck.totalCards == 1
                          ? '1 tarjeta'
                          : '${deck.totalCards} tarjetas',
                      icon: Icons.style_rounded,
                    ),
                    if (hasDue)
                      DocChip(
                        label: '${deck.dueCards} por repasar',
                        icon: Icons.bolt_rounded,
                        tone: DocTone.accent,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkIconButton(
            icon: Icons.edit_rounded,
            tooltip: 'Renombrar',
            size: 38,
            onTap: onRename,
          ),
        ],
      ),
    );
  }
}

/// Pila de fichas: la misma ilustración que abre las flashcards en la web.
class _CardStackArt extends StatelessWidget {
  const _CardStackArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 58,
      child: Stack(
        children: [
          for (var i = 2; i >= 0; i--)
            Positioned(
              left: i * 4.0,
              top: i * 3.0,
              child: Transform.rotate(
                angle: (i - 1) * 0.07,
                child: Container(
                  width: 40,
                  height: 50,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: i == 0 ? Colors.white : const Color(0xFFFFF5F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kInk, width: 1.8),
                  ),
                  child: i == 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 4,
                              width: 16,
                              decoration: BoxDecoration(
                                color: kAccent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final w in [22.0, 18.0, 13.0]) ...[
                              Container(
                                height: 2.4,
                                width: w,
                                color: const Color(0xFFD9D2CE),
                              ),
                              const SizedBox(height: 4),
                            ],
                          ],
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyFlashcards extends StatelessWidget {
  const _EmptyFlashcards();

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(24),
      texture: ruledPaper(step: 26),
      child: Column(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: kAccent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(4),
            ),
            child: const Icon(Icons.style_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aún no tienes flashcards',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kInk,
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea un grupo (por ejemplo, una asignatura) y ve metiendo dentro '
            'tus tarjetas. Se repasan con repetición espaciada.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMuted.withOpacity(0.95),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: kMuted, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kInk, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          GhostButton(
            label: 'Reintentar',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _FlashDeckSkeleton extends StatelessWidget {
  const _FlashDeckSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(4),
      ),
    );
  }
}
