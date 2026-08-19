import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';
import 'deck_detail_screen.dart';
import 'deck_trash_screen.dart';

/// Sección Mazos — conectada al backend (/api/studio/decks): lista con estado
/// visual, crear mazo, eliminar (papelera 24h) y abrir el detalle para estudiar.
class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Deck>? _decks;
  String? _error;
  bool _loading = true;

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
      final decks = await context.read<ApiService>().getDecks();
      if (!mounted) return;
      setState(() {
        _decks = decks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus mazos. Desliza para reintentar.';
        _loading = false;
      });
    }
  }

  Future<void> _createDeck() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nuevo mazo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Nombre del mazo (mín. 3 letras)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (name == null || name.length < 3) {
      if (name != null && name.isNotEmpty) {
        _toast('El nombre debe tener al menos 3 letras.');
      }
      return;
    }

    try {
      await context.read<ApiService>().createDeck(name);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo crear el mazo.');
    }
  }

  Future<void> _deleteDeck(Deck deck) async {
    final api = context.read<ApiService>();
    // Optimista: lo quitamos de la lista y ofrecemos deshacer.
    setState(() => _decks?.removeWhere((d) => d.id == deck.id));
    try {
      await api.deleteDeck(deck.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${deck.name}" eliminado'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
          action: SnackBarAction(
            label: 'Deshacer',
            textColor: AppColors.primary,
            onPressed: () async {
              try {
                await api.restoreDeck(deck.id);
              } catch (_) {}
              _load();
            },
          ),
        ),
      );
    } catch (_) {
      _toast('No se pudo eliminar el mazo.');
      _load();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
          label: 'Nuevo mazo',
          icon: Icons.add_rounded,
          onPressed: _createDeck,
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                  child: StickerHero(
                    badge: 'Dominio',
                    badgeIcon: Icons.layers_rounded,
                    title: 'Tus Mazos',
                    subtitle:
                        'Repaso con repetición espaciada para fijar lo que fallas.',
                    aside: InkIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Papelera',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const DeckTrashScreen()),
                        );
                        _load();
                      },
                    ),
                  ),
                ),
              ),
              ..._content(),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    if (_loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => const _DeckSkeleton(),
              childCount: 4,
            ),
          ),
        ),
      ];
    }

    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
            child: Column(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: AppColors.textLight, size: 44),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final decks = _decks ?? [];
    if (decks.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 50, 32, 0),
            child: Column(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: kInk, width: 2),
                    boxShadow: inkShadow(4),
                  ),
                  child: const Icon(Icons.style_rounded,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Aún no tienes mazos',
                  style: TextStyle(
                    color: kInk,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Crea tu primer mazo con el botón “Nuevo mazo”, o guarda preguntas que falles para repasarlas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => SlideFadeIn(
              delay: Duration(milliseconds: 70 * (i % 8)),
              beginOffset: const Offset(0, 0.12),
              child: _DeckCard(
                deck: decks[i],
                onOpen: () => _openDeck(decks[i]),
                onDelete: decks[i].systemGenerated ||
                        decks[i].autoType == 'failed_global'
                    ? null
                    : () => _confirmDelete(decks[i]),
              ),
            ),
            childCount: decks.length,
          ),
        ),
      ),
    ];
  }

  Future<void> _openDeck(Deck deck) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeckDetailScreen(deck: deck)),
    );
    _load();
  }

  Future<void> _confirmDelete(Deck deck) async {
    HapticFeedback.lightImpact();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error),
                title: Text('Eliminar "${deck.name}"'),
                subtitle: const Text('Podrás recuperarlo 24 h desde la papelera.'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) _deleteDeck(deck);
  }
}

class _DeckCard extends StatelessWidget {
  final Deck deck;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const _DeckCard({
    required this.deck,
    required this.onOpen,
    required this.onDelete,
  });

  ({Color accent, Color bg, IconData icon, String label}) get _style {
    switch (deck.visualState) {
      case 'failed':
        return (
          accent: const Color(0xFFC4655A),
          bg: const Color(0xFFFDF1EF),
          icon: Icons.local_fire_department_rounded,
          label: 'MAZO DE FALLOS',
        );
      case 'perfect':
        return (
          accent: const Color(0xFFC9A227),
          bg: const Color(0xFFFFFBEF),
          icon: Icons.workspace_premium_rounded,
          label: 'PERFECTO',
        );
      case 'destroyed':
        return (
          accent: const Color(0xFFB3543F),
          bg: const Color(0xFFFBF3F0),
          icon: Icons.healing_rounded,
          label: 'NECESITA REPASO',
        );
      default:
        return (
          accent: AppColors.success,
          bg: Colors.white,
          icon: Icons.style_rounded,
          label: 'EN FORMA',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final accuracyPct = (deck.accuracy * 100).round();
    final hasData = deck.totalReviews >= 25;

    return Pressable(
      onTap: onOpen,
      pressedScale: 0.97,
      child: StickerCard(
        margin: const EdgeInsets.only(bottom: 14),
        depth: 4,
        radius: 20,
        background: style.bg,
        padding: const EdgeInsets.all(16),
        // Cartulina teñida con el estado del mazo: la trama dice de un vistazo
        // si está en forma o si pide repaso, antes de leer la etiqueta.
        texture: tintedPaper(style.accent, step: 24),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              height: 62,
              child: Stack(
                children: [
                  for (var i = 2; i >= 0; i--)
                    Positioned(
                      left: i * 4.0,
                      top: i * 3.0,
                      child: Transform.rotate(
                        angle: (i - 1) * 0.06,
                        child: Container(
                          width: 42,
                          height: 54,
                          decoration: BoxDecoration(
                            color:
                                i == 0 ? Colors.white : const Color(0xFFFFF7F4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kInk, width: 1.6),
                          ),
                          child: i == 0
                              ? Icon(style.icon, color: style.accent, size: 20)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    style.label,
                    style: TextStyle(
                      color: style.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 9.5,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    deck.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kInk,
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.refresh_rounded,
                          size: 13, color: AppColors.textLight),
                      const SizedBox(width: 3),
                      Text(
                        '${deck.totalReviews} repasos',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (deck.systemGenerated) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.auto_awesome_rounded,
                            size: 12, color: AppColors.textLight),
                        const SizedBox(width: 3),
                        const Text(
                          'Automático',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: hasData ? deck.accuracy : 0),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: hasData ? value : null,
                        strokeWidth: 4.5,
                        strokeCap: StrokeCap.round,
                        backgroundColor: style.accent.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(
                          hasData
                              ? style.accent
                              : style.accent.withValues(alpha: 0.25),
                        ),
                      ),
                      Text(
                        hasData ? '$accuracyPct%' : '—',
                        style: TextStyle(
                          color: style.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textLight, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeckSkeleton extends StatefulWidget {
  const _DeckSkeleton();

  @override
  State<_DeckSkeleton> createState() => _DeckSkeletonState();
}

class _DeckSkeletonState extends State<_DeckSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_shimmer),
      child: Container(
        height: 94,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(4),
        ),
      ),
    );
  }
}
