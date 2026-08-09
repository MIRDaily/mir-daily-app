import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import 'deck_study_screen.dart';

/// Detalle de un mazo: resumen por estado, lista de preguntas y acceso a la
/// sesión de estudio.
class DeckDetailScreen extends StatefulWidget {
  final Deck deck;

  const DeckDetailScreen({super.key, required this.deck});

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  List<DeckCard>? _items;
  DeckSummary? _summary;
  bool _loading = true;
  String? _error;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final results = await Future.wait([
        _api.getDeckItems(widget.deck.id),
        _api.getDeckSummary(widget.deck.id).catchError(
            (_) => const DeckSummary(
                newCount: 0, failed: 0, learning: 0, mastered: 0)),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<DeckCard>;
        _summary = results[1] as DeckSummary;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las preguntas del mazo.';
        _loading = false;
      });
    }
  }

  Future<void> _study() async {
    final count = _items?.length ?? 0;
    if (count == 0) return;
    final limit = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '¿Cuántas cartas quieres repasar?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            for (final n in [10, 20, count].toSet().where((n) => n > 0))
              ListTile(
                leading: const Icon(Icons.style_rounded,
                    color: AppColors.primaryDark),
                title: Text(n >= count ? 'Todas ($count)' : '$n cartas'),
                onTap: () => Navigator.pop(ctx, n > count ? count : n),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (limit == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeckStudyScreen(deck: widget.deck, limit: limit),
      ),
    );
    _load();
  }

  Future<void> _removeItem(DeckCard item) async {
    setState(() => _items?.removeWhere((x) => x.itemId == item.itemId));
    try {
      await _api.removeDeckItem(widget.deck.id, item.itemId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo quitar la pregunta.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = !widget.deck.systemGenerated &&
        widget.deck.autoType != 'failed_global';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.deck.name, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style:
                          const TextStyle(color: AppColors.textSecondary)))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    children: [
                      if (_summary != null) _summaryCard(_summary!),
                      const SizedBox(height: 16),
                      Text(
                        'Preguntas (${_items?.length ?? 0})',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if ((_items?.isEmpty ?? true))
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'Este mazo no tiene preguntas todavía.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        ..._items!.map((it) => _ItemCard(
                              item: it,
                              onRemove: canEdit ? () => _removeItem(it) : null,
                            )),
                    ],
                  ),
                ),
      floatingActionButton: (_items?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: _study,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Estudiar'),
            )
          : null,
    );
  }

  Widget _summaryCard(DeckSummary s) {
    Widget chip(String label, int n, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          chip('NUEVAS', s.newCount, AppColors.slate),
          chip('FALLOS', s.failed, AppColors.error),
          chip('APRENDIENDO', s.learning, AppColors.warning),
          chip('DOMINADAS', s.mastered, AppColors.success),
        ],
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  final DeckCard item;
  final VoidCallback? onRemove;

  const _ItemCard({required this.item, required this.onRemove});

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            title: Text(
              q.statement,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            subtitle: q.subject != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      q.subject!,
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
                if (widget.onRemove != null)
                  IconButton(
                    tooltip: 'Quitar del mazo',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.textLight, size: 20),
                  ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded,
                      color: AppColors.textLight),
                ),
              ],
            ),
          ),
          if (_expanded)
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
                          Icon(
                            i == q.correctIndex
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 17,
                            color: i == q.correctIndex
                                ? AppColors.success
                                : AppColors.textLight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_letters[i]}. ${q.options[i]}',
                              style: TextStyle(
                                color: i == q.correctIndex
                                    ? AppColors.successDark
                                    : AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: i == q.correctIndex
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if ((q.explanation ?? '').isNotEmpty) ...[
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
