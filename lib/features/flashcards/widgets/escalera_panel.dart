// Escalera de dificultad de un grupo: por tema, qué niveles están abiertos y cuánto falta para los
// cerrados («Difícil: 12 de 20 dominadas de fácil y media»), con un candado. Los números y la regla
// vienen del servidor (get_flashcard_ladder): aquí solo se pintan.
// Puerto de src/components/flashcards/EscaleraNiveles.tsx.

import 'package:flutter/material.dart';

import '../../../core/models/flashcards.dart';
import '../../../shared/sticker/sticker.dart';
import 'flashcards_ui.dart';

class EscaleraPanel extends StatefulWidget {
  final Escalera escalera;

  /// La escalera está puesta en los ajustes de la sesión (si no, se pinta apagada).
  final bool activa;

  const EscaleraPanel({super.key, required this.escalera, required this.activa});

  @override
  State<EscaleraPanel> createState() => _EscaleraPanelState();
}

class _EscaleraPanelState extends State<EscaleraPanel> {
  static const _visibles = 6;
  bool _todos = false;

  @override
  Widget build(BuildContext context) {
    // Primero los temas con algo cerrado (lo que queda por hacer); con un solo nivel no hay escalera.
    final temas = widget.escalera.topics.where((t) => t.levels.length > 1).toList();
    int cerrado(TemaEscalera t) => t.levels.any((l) => !l.unlocked) ? 1 : 0;
    temas.sort((a, b) => cerrado(b) - cerrado(a));
    if (temas.isEmpty) return const SizedBox.shrink();
    final cerrados = resumenEscalera(Escalera(temas)).nivelesCerrados;
    final vistos = _todos ? temas : temas.take(_visibles).toList();

    return Opacity(
      opacity: widget.activa ? 1 : 0.7,
      child: StickerCard(
        depth: 4,
        radius: 22,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.stairs_rounded, color: kAccent, size: 22),
            const SizedBox(width: 8),
            const Expanded(child: Text('Escalera de niveles', style: TextStyle(color: kInk, fontSize: 15.5, fontWeight: FontWeight.w900))),
            Text(
              cerrados == 0 ? 'Todo abierto' : '$cerrados ${cerrados == 1 ? 'nivel cerrado' : 'niveles cerrados'}',
              style: const TextStyle(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            widget.activa
                ? 'Las tarjetas nuevas de un nivel salen cuando dominas el 80 % de las de los niveles de abajo de ese tema. Las que ya has visto salen siempre.'
                : 'Escalera quitada: al estudiar salen las nuevas de todos los niveles.',
            style: const TextStyle(color: kMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          for (final t in vistos) _tema(t),
          if (temas.length > _visibles)
            TextButton(
              onPressed: () => setState(() => _todos = !_todos),
              child: Text(_todos ? 'Ver menos' : 'Ver los ${temas.length} temas'),
            ),
        ]),
      ),
    );
  }

  Widget _tema(TemaEscalera t) {
    final primero = t.levels.where((l) => !l.unlocked).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFFAF7F4), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          (t.topic ?? 'Sin tema').toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: kInk, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.4),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in t.levels)
            Tooltip(
              message: l.unlocked ? '${nombreNivel(l.level)}: abierto (${l.mastered} de ${l.total} dominadas)' : textoFalta(t, l),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: l.unlocked ? kLevelColor[l.level]!.soft : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: l.unlocked ? kLevelColor[l.level]!.color : const Color(0xFFD4C8BE), width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(l.unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      size: 13, color: l.unlocked ? kLevelColor[l.level]!.color : kMuted),
                  const SizedBox(width: 4),
                  Text(
                    '${nombreNivel(l.level)} · ${l.total}',
                    style: TextStyle(color: l.unlocked ? kLevelColor[l.level]!.color : kMuted, fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ]),
              ),
            ),
        ]),
        if (primero != null) ...[
          const SizedBox(height: 6),
          Text(
            '${nombreNivel(primero.level)}: ${textoFalta(t, primero)}',
            style: const TextStyle(color: Color(0xFF8A6418), fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ]),
    );
  }
}
