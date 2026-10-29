import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/mazos_extra.dart';
import '../../core/models/models.dart';
import '../../core/responsive/content_shell.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';

/// Papelera de un mazo: las preguntas quitadas se conservan 24 h y se pueden devolver.
/// Puerto de la pestaña «Papelera» de /decks/[deckId] (DeckTrashList + TrashTimer).
///
/// Devuelve true al cerrarse si se restauró alguna, para que el detalle recargue.
class DeckItemsTrashScreen extends StatefulWidget {
  final Deck deck;

  const DeckItemsTrashScreen({super.key, required this.deck});

  @override
  State<DeckItemsTrashScreen> createState() => _DeckItemsTrashScreenState();
}

class _DeckItemsTrashScreenState extends State<DeckItemsTrashScreen> {
  List<DeckItemTrashEntry>? _items;
  String? _error;
  final Set<String> _restaurando = {};
  bool _restauradas = false;

  /// La cuenta atrás se refresca cada 30 s, como en la web.
  Timer? _reloj;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _load();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // Las caducadas desaparecen solas (el servidor ya no las devolvería).
      setState(() => _items?.removeWhere((e) => e.purgeAt != null && !e.purgeAt!.isAfter(DateTime.now())));
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await _api.getDeckItemsTrash(widget.deck.id);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : 'No se pudo cargar la papelera de preguntas.');
      }
    }
  }

  Future<void> _restore(DeckItemTrashEntry e) async {
    if (_restaurando.contains(e.id)) return;
    setState(() => _restaurando.add(e.id));
    try {
      await _api.restoreDeckItem(widget.deck.id, e.id);
      if (!mounted) return;
      setState(() {
        _items?.removeWhere((x) => x.id == e.id);
        _restauradas = true;
      });
      _snack('Pregunta restaurada');
    } catch (err) {
      if (mounted) _snack(err is ApiException ? err.message : 'No se pudo restaurar la pregunta.');
    } finally {
      if (mounted) setState(() => _restaurando.remove(e.id));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, backgroundColor: AppColors.textPrimary));

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_restauradas);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          title: const Text('Papelera del mazo'),
        ),
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      GhostButton(label: 'Reintentar', compact: true, onPressed: _load),
                    ]),
                  ),
                )
              : items == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: BodyConstraint(
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                          children: [
                            Text(
                              '${items.length} pregunta${items.length == 1 ? '' : 's'} eliminada${items.length == 1 ? '' : 's'} · '
                              'se pueden recuperar durante 24 horas',
                              style: const TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 14),
                            if (items.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: kInk, width: 2),
                                ),
                                child: const Row(children: [
                                  Icon(Icons.delete_outline_rounded, color: kMuted, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text('No hay preguntas en la papelera.',
                                        style: TextStyle(color: kMuted, fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                              )
                            else
                              for (final e in items) _Tarjeta(entry: e, restaurando: _restaurando.contains(e.id), onRestore: () => _restore(e)),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final DeckItemTrashEntry entry;
  final bool restaurando;
  final VoidCallback onRestore;

  const _Tarjeta({required this.entry, required this.restaurando, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final caducidad = textoCaducidad(entry.purgeAt);
    return StickerCard(
      depth: 3,
      radius: 16,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.statement,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w700, height: 1.35)),
                if (entry.subject != null) ...[
                  const SizedBox(height: 4),
                  Text(entry.subject!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFB07F72), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: AppColors.error),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(caducidad,
                        style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: restaurando ? null : onRestore,
            icon: restaurando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Restaurar'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }
}
