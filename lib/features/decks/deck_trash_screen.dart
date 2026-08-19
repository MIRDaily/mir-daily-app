import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';

/// Papelera de mazos: los eliminados se conservan 24 h y pueden restaurarse.
class DeckTrashScreen extends StatefulWidget {
  const DeckTrashScreen({super.key});

  @override
  State<DeckTrashScreen> createState() => _DeckTrashScreenState();
}

class _DeckTrashScreenState extends State<DeckTrashScreen> {
  List<DeckTrashEntry>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final items = await context.read<ApiService>().getDecksTrash();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la papelera.';
        _loading = false;
      });
    }
  }

  Future<void> _restore(DeckTrashEntry e) async {
    try {
      await context.read<ApiService>().restoreDeck(e.id);
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.id == e.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${e.name}" restaurado'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo restaurar el mazo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _remaining(DateTime? purgeAt) {
    if (purgeAt == null) return '';
    final diff = purgeAt.difference(DateTime.now());
    if (diff.isNegative) return 'expirando…';
    final h = diff.inHours;
    if (h >= 1) return 'quedan ${h}h';
    return 'quedan ${diff.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Papelera de mazos'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.textSecondary)))
              : (_items == null || _items!.isEmpty)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 56, color: AppColors.textLight),
                            SizedBox(height: 12),
                            Text(
                              'La papelera está vacía',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final e = _items![i];
                        return StickerCard(
                          depth: 3,
                          radius: 16,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: kInk,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _remaining(e.purgeAt),
                                      style: const TextStyle(
                                        color: AppColors.textLight,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _restore(e),
                                icon: const Icon(Icons.restore_rounded,
                                    size: 18),
                                label: const Text('Restaurar'),
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
