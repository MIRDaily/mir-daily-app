// «Estudiar» en un grupo de flashcards → ajustes mínimos de la sesión antes de empezar: cuántas, qué
// tarjetas (todas, pendientes, solo falladas, solo nuevas), temas, dificultad y escalera. Abre con los
// últimos que se usaron en ese grupo; «Empezar» en un toque si no se quiere tocar nada. Los aplica el
// servidor; aquí se avisa de cuántas van a salir. Puerto de src/components/flashcards/AjustesSesion.tsx.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/flashcards.dart';
import '../../../core/models/models.dart';
import '../../../core/responsive/adaptive_modal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import 'flashcards_ui.dart';

String _clave(String deckId) => 'mirdaily:flashcards:ajustes:$deckId';

/// Los últimos ajustes de un grupo en este teléfono (comodidad: si se pierden, por defecto).
Future<AjustesSesion?> leerAjustesGuardados(String deckId) async {
  try {
    final v = (await SharedPreferences.getInstance()).getString(_clave(deckId));
    return v == null ? null : sanearAjustes(jsonDecode(v));
  } catch (_) {
    return null;
  }
}

Future<void> guardarAjustes(String deckId, AjustesSesion a) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_clave(deckId), jsonEncode(a.toJson()));
  } catch (_) {
    // Sin almacenamiento: la próxima vez, por defecto.
  }
}

/// Abre los ajustes; devuelve los elegidos al pulsar «Empezar» (null si se cierra).
Future<AjustesSesion?> elegirAjustesSesion(
  BuildContext context, {
  required String deckName,
  required List<Flashcard> cards,
  required AjustesSesion inicial,
  Escalera? escalera,
}) {
  return showAdaptiveModal<AjustesSesion>(
    context: context,
    dialogScrollable: false,
    backgroundColor: AppColors.background,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.86,
      child: AjustesSesionPanel(deckName: deckName, cards: cards, inicial: inicial, escalera: escalera),
    ),
  );
}

class AjustesSesionPanel extends StatefulWidget {
  final String deckName;
  final List<Flashcard> cards;
  final AjustesSesion inicial;
  final Escalera? escalera;

  const AjustesSesionPanel({super.key, required this.deckName, required this.cards, required this.inicial, this.escalera});

  @override
  State<AjustesSesionPanel> createState() => _AjustesSesionPanelState();
}

class _AjustesSesionPanelState extends State<AjustesSesionPanel> {
  late AjustesSesion _a = widget.inicial;
  late final _temas = temasDelGrupo(widget.cards);
  late final _conNivel = widget.cards.any((c) => c.level != null);

  void _alternarTema(String t) {
    final actual = (_a.temas ?? _temas.map((x) => x.tema)).toSet();
    if (!actual.remove(t)) actual.add(t);
    setState(() => _a = _a.copyWith(temas: () => actual.length == _temas.length ? null : actual.toList()));
  }

  void _alternarNivel(int n) {
    final ns = _a.niveles.contains(n) ? _a.niveles.where((x) => x != n).toList() : ([..._a.niveles, n]..sort());
    if (ns.isNotEmpty) setState(() => _a = _a.copyWith(niveles: ns));
  }

  @override
  Widget build(BuildContext context) {
    final efectivos = _a.copyWith(escalera: _conNivel && _a.escalera);
    final salen = coinciden(widget.cards, efectivos, widget.escalera).length;
    final tarjetas = _a.cantidad != null && _a.cantidad! < salen ? _a.cantidad! : salen;
    final elegidos = _a.temas?.toSet();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
        child: Row(children: [
          const Icon(Icons.tune_rounded, color: kAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ajustes de la sesión', style: TextStyle(color: kInk, fontSize: 19, fontWeight: FontWeight.w900)),
              Text(widget.deckName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ),
          IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), children: [
          const SectionLabel('Cuántas tarjetas'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in [...kCantidades, null])
              _Chip(
                label: n == null ? 'Todas' : '$n',
                on: _a.cantidad == n,
                onTap: () => setState(() => _a = _a.copyWith(cantidad: () => n)),
              ),
          ]),
          const SizedBox(height: 18),
          const SectionLabel('Qué tarjetas'),
          for (final o in kOpcionesSolo) _opcionSolo(o),
          if (_temas.length > 1) ...[
            const SizedBox(height: 12),
            SectionLabel(
              'Temas',
              trailing: TextButton(
                onPressed: _a.temas == null ? null : () => setState(() => _a = _a.copyWith(temas: () => null)),
                child: const Text('Todos'),
              ),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in _temas)
                _Chip(
                  label: '${t.tema.isEmpty ? 'Sin tema' : t.tema} · ${t.total}',
                  on: elegidos == null || elegidos.contains(t.tema),
                  tachado: true,
                  onTap: () => _alternarTema(t.tema),
                ),
            ]),
          ],
          if (_conNivel) ...[
            const SizedBox(height: 18),
            const SectionLabel('Dificultad'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in kFlashLevels) _chipNivel(n),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _a.escalera,
              activeColor: kAccent,
              onChanged: (v) => setState(() => _a = _a.copyWith(escalera: v)),
              title: const Text('Escalera de dificultad', style: TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w800)),
              subtitle: const Text(
                'Lo nuevo de un nivel sale cuando dominas lo de abajo de su tema. Lo ya visto sale siempre.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
            ),
          ],
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kHairline))),
        child: SafeArea(
          top: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (tarjetas > 0)
              Text.rich(
                TextSpan(style: const TextStyle(color: kInk, fontSize: 13.5), children: [
                  const TextSpan(text: 'Vas a estudiar '),
                  TextSpan(text: '$tarjetas', style: const TextStyle(fontWeight: FontWeight.w900)),
                  TextSpan(text: tarjetas == 1 ? ' tarjeta' : ' tarjetas'),
                  if (_a.cantidad != null && salen > _a.cantidad!)
                    TextSpan(text: ' de $salen que coinciden', style: const TextStyle(color: kMuted)),
                  const TextSpan(text: '. Las que falles vuelven en la misma sesión.'),
                ]),
              )
            else
              const Text(
                'Ninguna tarjeta coincide con estos ajustes.',
                style: TextStyle(color: Color(0xFFB04A5E), fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 12),
            StickerButton(
              label: 'Empezar',
              icon: Icons.play_arrow_rounded,
              expand: true,
              onPressed: tarjetas == 0 ? null : () => Navigator.pop(context, _a),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _opcionSolo(({SoloTarjetas id, String titulo, String descripcion}) o) {
    final n = widget.cards.where((c) => coincideSolo(c, o.id)).length;
    final on = _a.solo == o.id;
    return Opacity(
      opacity: n == 0 ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: n == 0 ? null : () => setState(() => _a = _a.copyWith(solo: o.id)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? kAccent : Colors.transparent, width: 2),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.titulo, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(o.descripcion, style: const TextStyle(color: kMuted, fontSize: 11.5)),
                  ]),
                ),
                Text('$n', style: const TextStyle(color: kMuted, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipNivel(int n) {
    final total = widget.cards.where((c) => c.level == n).length;
    final on = _a.niveles.contains(n);
    final c = kLevelColor[n]!;
    return Opacity(
      opacity: total == 0 ? 0.45 : 1,
      child: GestureDetector(
        onTap: total == 0 ? null : () => _alternarNivel(n),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on ? c.soft : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? c.color : const Color(0xFFE4DCD8), width: 2),
          ),
          child: Text(
            '${nombreNivel(n)} · $total',
            style: TextStyle(color: on ? c.color : kMuted, fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final bool tachado;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.on, required this.onTap, this.tachado = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: on,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? kAccent : const Color(0xFFEDE6DE), width: 2),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: on ? kInk : kMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              decoration: tachado && !on ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}
