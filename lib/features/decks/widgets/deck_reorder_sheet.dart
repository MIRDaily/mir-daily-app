import 'package:flutter/material.dart';

import '../../../core/models/mazos_extra.dart';
import '../../../core/models/models.dart';
import '../../../core/responsive/adaptive_modal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// «Colocar a mano»: ordena tus mazos arrastrando por el asa. En la galería no se arrastra (choca con el
/// scroll), así que se hace en esta lista aparte. Guarda el mismo orden que la web (`decks.position`),
/// solo de los mazos propios: los del sistema van siempre primero.
///
/// Devuelve los ids en el orden nuevo, o null si se cancela o no cambia nada.
Future<List<String>?> showDeckReorderSheet(BuildContext context, List<Deck> propios) {
  return showAdaptiveModal<List<String>>(
    context: context,
    dialogScrollable: false,
    builder: (_) => _DeckReorderSheet(propios: propios),
  );
}

class _DeckReorderSheet extends StatefulWidget {
  final List<Deck> propios;
  const _DeckReorderSheet({required this.propios});

  @override
  State<_DeckReorderSheet> createState() => _DeckReorderSheetState();
}

class _DeckReorderSheetState extends State<_DeckReorderSheet> {
  late List<Deck> _orden = [...widget.propios];

  bool get _cambiado {
    for (var i = 0; i < _orden.length; i++) {
      if (_orden[i].id != widget.propios[i].id) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: alto * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('Colocar a mano', style: TextStyle(color: kInk, fontSize: 19, fontWeight: FontWeight.w900)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Arrastra por el asa. Es el mismo orden que en la web; el mazo de fallos va siempre arriba.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                itemCount: _orden.length,
                // onReorderItem ya da el índice final (sin el hueco), así que se mueve tal cual.
                onReorderItem: (desde, hasta) => setState(() => _orden = moverEnLista(_orden, desde, hasta > desde ? hasta + 1 : hasta)),
                itemBuilder: (context, i) {
                  final d = _orden[i];
                  return Padding(
                    key: ValueKey(d.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: kInk, width: 2),
                      ),
                      child: Row(children: [
                        const SizedBox(width: 14),
                        Text('${i + 1}', style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kInk, fontSize: 14.5, fontWeight: FontWeight.w800)),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Semantics(
                            label: 'Mover ${d.name}',
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: Icon(Icons.drag_handle_rounded, color: kMuted),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(children: [
                Expanded(child: GhostButton(label: 'Cancelar', expand: true, onPressed: () => Navigator.pop(context))),
                const SizedBox(width: 10),
                Expanded(
                  child: StickerButton(
                    label: 'Guardar orden',
                    icon: Icons.check_rounded,
                    expand: true,
                    onPressed: _cambiado ? () => Navigator.pop(context, [for (final d in _orden) d.id]) : null,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
