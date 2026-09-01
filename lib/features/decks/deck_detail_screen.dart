import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'deck_study_screen.dart';
import 'widgets/deck_gradient.dart';
import 'widgets/deck_study_options.dart';
import 'widgets/highlighted_text.dart';

/// Detalle de un mazo: portada, resumen por estado, desglose por asignaturas,
/// lista de preguntas (con buscador y filtros de vista) y acceso a la sesión
/// de estudio.
class DeckDetailScreen extends StatefulWidget {
  final Deck deck;

  /// Cuando no es null, la pantalla está EMBEBIDA en el panel derecho de un
  /// maestro-detalle (tablet grande) en vez de empujada con `Navigator.push`.
  /// El botón de atrás llama a esto (para deseleccionar en el maestro) en vez
  /// de hacer pop, que aquí no correspondería a ninguna ruta propia.
  final VoidCallback? onClose;

  const DeckDetailScreen({super.key, required this.deck, this.onClose});

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  /// Copia local del mazo: la portada y la bio se editan en esta pantalla, y
  /// se pintan al instante sin esperar a recargar el mazo entero. Al volver,
  /// la galería recarga y coge los valores ya guardados en el servidor.
  late Deck _deck = widget.deck;

  List<DeckCard>? _items;
  int _itemsTotal = 0;
  int _itemsPage = 1;
  int _itemsTotalPages = 1;
  bool _loadingMore = false;

  DeckSummary? _summary;
  List<DeckSubject> _subjects = const [];
  bool _loading = true;
  String? _error;

  // ── Buscador ────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _search = '';
  bool _searching = false;

  // ── Preferencias de vista ───────────────────────────────────────────────
  // No se guardan en ningún sitio a propósito: la pantalla abre SIEMPRE igual
  // (contraída, respuestas ocultas, etiquetas visibles), que es lo que se
  // decidió también para la web.
  bool _showCorrect = false;
  bool _expandAll = false;
  bool _showMeta = true;

  /// Preguntas que el usuario ha abierto o cerrado a mano, por encima de lo
  /// que diga [_expandAll].
  final Map<String, bool> _expandOverrides = {};

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final results = await Future.wait([
        _api.getDeckItems(_deck.id, page: 1, query: _search),
        _api.getDeckSummary(_deck.id).catchError((_) => const DeckSummary(
            newCount: 0, failed: 0, learning: 0, mastered: 0)),
        _api.getDeckSubjects(_deck.id).catchError((_) => <DeckSubject>[]),
      ]);
      if (!mounted) return;
      final page = results[0] as DeckItemsPage;
      setState(() {
        _items = page.items;
        _itemsTotal = page.total;
        _itemsPage = page.page;
        _itemsTotalPages = page.totalPages;
        _summary = results[1] as DeckSummary;
        _subjects = results[2] as List<DeckSubject>;
        _loading = false;
        _searching = false;
        _expandOverrides.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las preguntas del mazo.';
        _loading = false;
        _searching = false;
      });
    }
  }

  /// Recarga solo la lista (al buscar), sin tocar resumen ni asignaturas.
  Future<void> _reloadItems() async {
    setState(() => _searching = true);
    try {
      final page = await _api.getDeckItems(_deck.id, page: 1, query: _search);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _itemsTotal = page.total;
        _itemsPage = page.page;
        _itemsTotalPages = page.totalPages;
        _searching = false;
        _expandOverrides.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
      _toast('No se pudo buscar.');
    }
  }

  /// El backend pagina de 50 en 50. Sin esto, un mazo de 120 preguntas
  /// enseñaba las primeras y se comportaba como si no hubiera más.
  Future<void> _loadMore() async {
    if (_loadingMore || _itemsPage >= _itemsTotalPages) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.getDeckItems(
        _deck.id,
        page: _itemsPage + 1,
        query: _search,
      );
      if (!mounted) return;
      setState(() {
        _items = [...?_items, ...page.items];
        _itemsPage = page.page;
        _itemsTotalPages = page.totalPages;
        _itemsTotal = page.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast('No se pudieron cargar más preguntas.');
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || value.trim() == _search) return;
      _search = value.trim();
      _reloadItems();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (_search.isEmpty) {
      setState(() {});
      return;
    }
    _search = '';
    _reloadItems();
  }

  /// Elige el degradado de la portada. Se pinta al momento (optimista) y se
  /// revierte si el guardado falla, igual que en la web.
  Future<void> _pickGradient() async {
    final current = normalizeDeckGradient(_deck.bannerGradient);

    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Fondo del mazo',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Se guarda en tu cuenta: lo verás igual en la web.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final id in kDeckGradientIds)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, id),
                      child: SizedBox(
                        width: 66,
                        child: Column(
                          children: [
                            DeckGradientSwatch(
                              id: id,
                              size: 44,
                              selected: id == current,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              deckGradientOf(id).label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.2,
                                color: id == current
                                    ? kInk
                                    : AppColors.textSecondary,
                                fontWeight: id == current
                                    ? FontWeight.w900
                                    : FontWeight.w600,
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
        ),
      ),
    );

    if (chosen == null || chosen == current || !mounted) return;

    final previous = _deck.bannerGradient;
    setState(() => _deck = _deck.copyWith(bannerGradient: chosen));

    try {
      await _api.updateDeck(_deck.id, gradient: chosen);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deck = _deck.copyWith(bannerGradient: previous));
      _toast(e is ApiException ? e.message : 'No se pudo guardar el fondo.');
    }
  }

  /// Bio corta del mazo. Comparte endpoint con el gradiente
  /// (`POST /decks/:id/update`) y el mismo tope de 120 que la web.
  Future<void> _editBio() async {
    final controller = TextEditingController(text: _deck.description ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Descripción del mazo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: ApiService.maxDeckDescriptionLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'De qué va este mazo (opcional)',
            border: OutlineInputBorder(),
          ),
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
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    final value = result.isEmpty ? null : result;
    if (value == _deck.description) return;

    final previous = _deck.description;
    setState(() => _deck = _deck.copyWith(description: value));

    try {
      await _api.updateDeck(_deck.id, description: value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deck = _deck.copyWith(description: previous));
      _toast(
          e is ApiException ? e.message : 'No se pudo guardar la descripción.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
        ),
      );
  }

  Future<void> _study() async {
    // El total del mazo, no el de la búsqueda en curso: se estudia el mazo
    // entero, el buscador solo filtra el listado de abajo.
    final total = _deck.totalItems > 0 ? _deck.totalItems : _itemsTotal;
    if (total == 0) return;

    final options = await showDeckStudySheet(
      context: context,
      totalItems: total,
      subjects: _subjects,
      summary: _summary,
    );
    if (options == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeckStudyScreen(deck: _deck, options: options),
      ),
    );
    _load();
  }

  Future<void> _removeItem(DeckCard item) async {
    setState(() {
      _items?.removeWhere((x) => x.itemId == item.itemId);
      if (_itemsTotal > 0) _itemsTotal--;
    });
    try {
      await _api.removeDeckItem(_deck.id, item.itemId);
    } catch (_) {
      if (!mounted) return;
      _toast('No se pudo quitar la pregunta.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = !_deck.isSystemDeck;
    // Embebido en maestro-detalle (panel derecho de tablet).
    final embedded = widget.onClose != null;
    final canStudy = _deck.totalItems > 0 || _itemsTotal > 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        // null deja el botón de atrás automático de Flutter (pop normal).
        // Embebido en maestro-detalle, un pop se llevaría por delante toda
        // la pantalla de Mazos; en su lugar se deselecciona en el maestro.
        leading: !embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onClose,
              ),
        title: Text(_deck.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_deck.isAutoManaged)
            IconButton(
              tooltip: 'Fondo del mazo',
              onPressed: _pickGradient,
              icon: const Icon(Icons.palette_outlined, color: kInk),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.textSecondary)))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    children: [
                      DeckCover(
                        deck: _deck,
                        onEditBio: _deck.isAutoManaged ? null : _editBio,
                      ),
                      const SizedBox(height: 16),
                      if (_summary != null) _summaryCard(_summary!),
                      if (_subjects.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const SectionLabel('De qué se compone'),
                        _subjectsCard(),
                      ],
                      const SizedBox(height: 18),
                      SectionLabel(_search.isEmpty
                          ? 'Preguntas ($_itemsTotal)'
                          : 'Resultados ($_itemsTotal)'),
                      _toolbar(),
                      const SizedBox(height: 14),
                      if (_items?.isEmpty ?? true)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              _search.isEmpty
                                  ? 'Este mazo no tiene preguntas todavía.'
                                  : 'Ninguna pregunta coincide con tu búsqueda.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else ...[
                        ..._items!.map(
                          (it) => _ItemCard(
                            key: ValueKey(it.itemId),
                            item: it,
                            expanded: _expandOverrides[it.itemId] ?? _expandAll,
                            showCorrect: _showCorrect,
                            showMeta: _showMeta,
                            query: _search,
                            onToggle: () => setState(() {
                              final current =
                                  _expandOverrides[it.itemId] ?? _expandAll;
                              _expandOverrides[it.itemId] = !current;
                            }),
                            onRemove: canEdit ? () => _removeItem(it) : null,
                          ),
                        ),
                        if (_itemsPage < _itemsTotalPages)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Center(
                              child: _loadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                          strokeWidth: 2.4,
                                        ),
                                      ),
                                    )
                                  : GhostButton(
                                      label: 'Ver más '
                                          '(${_itemsTotal - _items!.length} restantes)',
                                      icon: Icons.expand_more_rounded,
                                      onPressed: _loadMore,
                                    ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
      // El mismo botón que en móvil. En maestro-detalle ya no choca con
      // nada: "Nuevo mazo" vive en la cabecera de la lista y la barra
      // flotante va centrada.
      floatingActionButton: canStudy
          ? Padding(
              padding: EdgeInsets.only(bottom: embedded ? 12 : 4, right: 4),
              child: StickerButton(
                label: 'Estudiar',
                icon: Icons.play_arrow_rounded,
                onPressed: _study,
              ),
            )
          : null,
    );
  }

  /// Buscador y los tres interruptores de vista, los mismos que la web:
  /// respuestas correctas, desplegar todo y etiquetas de asignatura/año.
  Widget _toolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kHairline, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded,
                  size: 19, color: AppColors.textLight),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    setState(() {}); // para que aparezca la X de limpiar
                    _onSearchChanged(v);
                  },
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    color: kInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 13),
                    hintText: 'Buscar en los enunciados…',
                    hintStyle: TextStyle(
                      color: AppColors.textLight,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (_searching)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                )
              else if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: _clearSearch,
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textLight),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ViewToggle(
                label: 'Respuestas',
                icon: _showCorrect
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                active: _showCorrect,
                onTap: () => setState(() => _showCorrect = !_showCorrect),
              ),
              const SizedBox(width: 8),
              _ViewToggle(
                label: _expandAll ? 'Contraer' : 'Desplegar',
                icon: _expandAll
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                active: _expandAll,
                onTap: () => setState(() {
                  _expandAll = !_expandAll;
                  _expandOverrides.clear();
                }),
              ),
              const SizedBox(width: 8),
              _ViewToggle(
                label: 'Etiquetas',
                icon: Icons.sell_outlined,
                active: _showMeta,
                onTap: () => setState(() => _showMeta = !_showMeta),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Los cuatro estados. Antes eran cuatro cajas con el nombre completo
  /// ("APRENDIENDO", "DOMINADAS") y en una pantalla estrecha el texto se
  /// partía en dos líneas y se salía de su caja. Ahora manda el icono y el
  /// número; el nombre sigue disponible tocando la caja.
  Widget _summaryCard(DeckSummary s) {
    final tiles = <({IconData icon, String label, int value, Color color})>[
      (
        icon: Icons.fiber_new_rounded,
        label: 'Nuevas',
        value: s.newCount,
        color: AppColors.slate,
      ),
      (
        icon: Icons.close_rounded,
        label: 'Falladas',
        value: s.failed,
        color: AppColors.error,
      ),
      (
        icon: Icons.trending_up_rounded,
        label: 'En aprendizaje',
        value: s.learning,
        color: const Color(0xFFB4831F),
      ),
      (
        icon: Icons.verified_rounded,
        label: 'Dominadas',
        value: s.mastered,
        color: AppColors.successDark,
      ),
    ];

    return StickerCard(
      depth: 4,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final t in tiles)
            Expanded(
              child: Tooltip(
                message: t.label,
                triggerMode: TooltipTriggerMode.tap,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kHairline, width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(t.icon, size: 18, color: t.color),
                      const SizedBox(height: 4),
                      Text(
                        '${t.value}',
                        style: TextStyle(
                          color: t.color,
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// De qué está hecho el mazo. La web enseña este desglose en la galería;
  /// aquí va en la pantalla del mazo, que es donde hay sitio para leerlo.
  Widget _subjectsCard() {
    final total = _subjects.fold<int>(0, (sum, s) => sum + s.count);
    if (total == 0) return const SizedBox.shrink();

    return StickerCard(
      depth: 3,
      radius: 16,
      padding: const EdgeInsets.all(14),
      texture: ruledPaper(step: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in _subjects) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kInk,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${s.count} · ${(s.count / total * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 6,
                color: const Color(0xFFEFEAE7),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (s.count / total).clamp(0.02, 1.0),
                    child: Container(color: AppColors.primary),
                  ),
                ),
              ),
            ),
            if (s != _subjects.last) const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }
}

/// Uno de los tres interruptores de vista de la lista de preguntas.
class _ViewToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ViewToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? kInk : kHairline, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? Colors.white : kMuted),
            const SizedBox(width: 6),
            // Ancho reservado con el texto más largo: "Desplegar" es más ancho
            // que "Contraer", y sin esto el botón cambiaba de tamaño al
            // alternar y arrastraba a los de al lado.
            Stack(
              alignment: Alignment.centerLeft,
              children: [
                Opacity(
                  opacity: 0,
                  child: Text(
                    label == 'Contraer' ? 'Desplegar' : label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
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

class _ItemCard extends StatelessWidget {
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

  final DeckCard item;
  final bool expanded;
  final bool showCorrect;
  final bool showMeta;

  /// Lo que hay escrito en el buscador, para marcarlo en el enunciado. El
  /// backend solo busca ahí, así que solo ahí se resalta.
  final String query;

  final VoidCallback onToggle;
  final VoidCallback? onRemove;

  const _ItemCard({
    super.key,
    required this.item,
    required this.expanded,
    required this.showCorrect,
    required this.showMeta,
    required this.query,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final q = item;
    final meta = [
      if (q.subject != null) q.subject!,
      if (q.year != null) 'MIR ${q.year}',
    ].join(' · ');

    return StickerCard(
      margin: const EdgeInsets.only(bottom: 12),
      depth: 3,
      radius: 16,
      // Cartulina rayada: son fichas de estudio, y la trama lo recuerda.
      texture: ruledPaper(step: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: onToggle,
            title: HighlightedText(
              text: q.statement,
              query: query,
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                color: kInk,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            subtitle: showMeta && meta.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      meta,
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Quitar del mazo',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.textLight, size: 20),
                  ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded,
                      color: AppColors.textLight),
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < q.options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // El icono se monta SIEMPRE, invisible cuando no
                          // toca: así reserva su hueco y la fila no cambia de
                          // ancho al mostrar u ocultar las respuestas.
                          Opacity(
                            opacity: showCorrect && i == q.correctIndex ? 1 : 0,
                            child: const Icon(
                              Icons.check_circle_rounded,
                              size: 17,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_letters[i]}. ${q.options[i]}',
                              style: TextStyle(
                                color: showCorrect && i == q.correctIndex
                                    ? AppColors.successDark
                                    : AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: showCorrect && i == q.correctIndex
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // La explicación va con las respuestas: enseñarla mientras
                  // están ocultas destriparía la pregunta igualmente.
                  if (showCorrect && (q.explanation ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        q.explanation!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Portada del mazo: el degradado elegido, el nombre, la bio corta y la
/// insignia de dominio. Es la traducción del `Hero` con `backdrop` de la web
/// (`decks/[deckId]/page.tsx`), reducida a lo que cabe en una pantalla de
/// móvil.
class DeckCover extends StatelessWidget {
  final Deck deck;

  /// Null en el mazo automático de fallos, que no admite bio propia.
  final VoidCallback? onEditBio;

  const DeckCover({super.key, required this.deck, required this.onEditBio});

  @override
  Widget build(BuildContext context) {
    final subtitle = deck.isAutoManaged
        ? 'Tus fallos recientes, listos para repasar.'
        : deck.description;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(5),
        color: Colors.white,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: DeckBannerGradient(
                id: normalizeDeckGradient(deck.bannerGradient),
              ),
            ),
            // Velo de legibilidad, más denso donde vive el texto. En la web la
            // cabecera es ancha y el tono claro cubre de sobra la columna del
            // título; en una pantalla de móvil la banda oscura llega hasta el
            // centro y el texto de tinta se perdía con los presets saturados
            // (albaricoque, brasa, carmesí).
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.72),
                        Colors.white.withValues(alpha: 0.42),
                        Colors.white.withValues(alpha: 0.10),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sobre un fondo saturado el distintivo translúcido de
                        // siempre se pierde: aquí va en blanco sólido, igual
                        // que hace el Hero de la web cuando lleva backdrop.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: kInk, width: 1.6),
                          ),
                          child: Text(
                            deck.isAutoManaged ? 'AUTOMÁTICO' : 'MAZO',
                            style: const TextStyle(
                              color: kAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          deck.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kInk,
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: onEditBio,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  subtitle ??
                                      (onEditBio == null
                                          ? ''
                                          : 'Añade una descripción'),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: subtitle == null
                                        ? kInk.withValues(alpha: 0.45)
                                        : kInk.withValues(alpha: 0.75),
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    fontStyle: subtitle == null
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ),
                              if (onEditBio != null) ...[
                                const SizedBox(width: 6),
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 14,
                                    color: kInk.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // El mazo automático de fallos no muestra Dominio: su
                  // contenido cambia solo con cada acierto o fallo, así que un
                  // porcentaje de largo plazo no significa nada ahí.
                  if (!deck.isAutoManaged) ...[
                    const SizedBox(width: 12),
                    DeckMasteryBadge(percent: deck.masteryPercent),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
