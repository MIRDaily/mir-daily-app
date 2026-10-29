// «Estudiar» → ajustes de la sesión de resúmenes: qué niveles se TAPAN (los demás se ven), qué temas,
// qué párrafos (todos, pendientes, solo fallados, solo nuevos, solo huecos fallados, con su número) y
// cuántos; cómo se estudia (escribir la respuesta, cajas del mismo ancho); y «Vas a estudiar N».
// Los últimos de cada grupo se recuerdan en el teléfono. Puerto de AjustesEstudio.tsx.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/resumen.dart';
import '../../../core/responsive/adaptive_modal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../resumen_study_screen.dart';
import '../resumenes_api.dart';
import '../resumenes_grupo.dart';
import '../resumenes_logica.dart';

String _clave(String grupoId) => 'mirdaily:resumenes:ajustes:$grupoId';

Future<AjustesResumen?> leerAjustesResumen(String grupoId) async {
  try {
    final v = (await SharedPreferences.getInstance()).getString(_clave(grupoId));
    return v == null ? null : sanearAjustesResumen(jsonDecode(v));
  } catch (_) {
    return null;
  }
}

Future<void> guardarAjustesResumen(String grupoId, AjustesResumen a) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_clave(grupoId), jsonEncode(a.toJson()));
  } catch (_) {}
}

/// Abre los ajustes del grupo y, al pulsar «Empezar», el estudio. Sin [parrafos], los pide.
/// [temaInicial]: llega con ese tema elegido.
Future<void> estudiarResumenes(
  BuildContext context, {
  required String grupoId,
  required String grupoName,
  List<Parrafo>? parrafos,
}) async {
  var ps = parrafos;
  if (ps == null) {
    try {
      ps = (await context.read<ResumenesApi>().cargarGrupo(grupoId)).parrafos;
    } catch (_) {
      ps = null;
    }
    if (!context.mounted) return;
    if (ps == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo cargar el grupo.'), behavior: SnackBarBehavior.floating));
      return;
    }
  }
  if (ps.isEmpty) return;
  final inicial = await leerAjustesResumen(grupoId) ?? const AjustesResumen();
  if (!context.mounted) return;
  final lista = ps;
  final a = await showAdaptiveModal<AjustesResumen>(
    context: context,
    dialogScrollable: false,
    backgroundColor: AppColors.background,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.88,
      child: AjustesEstudioResumenPanel(grupoName: grupoName, parrafos: lista, inicial: inicial),
    ),
  );
  if (a == null || !context.mounted) return;
  guardarAjustesResumen(grupoId, a);
  final temas = lista.map((p) => (p.tema ?? '').trim()).toSet().toList();
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ResumenStudyScreen(grupoId: grupoId, grupoName: grupoName, ajustes: a, todosLosTemas: temas),
  ));
}

class AjustesEstudioResumenPanel extends StatefulWidget {
  final String grupoName;
  final List<Parrafo> parrafos;
  final AjustesResumen inicial;

  const AjustesEstudioResumenPanel({super.key, required this.grupoName, required this.parrafos, required this.inicial});

  @override
  State<AjustesEstudioResumenPanel> createState() => _AjustesEstudioResumenPanelState();
}

class _AjustesEstudioResumenPanelState extends State<AjustesEstudioResumenPanel> {
  late final List<String> _temas = widget.parrafos.map((p) => (p.tema ?? '').trim()).toSet().toList();
  // Los temas guardados que ya no existen en el grupo se olvidan.
  late AjustesResumen _a = widget.inicial.copyWith(
    temas: () {
      final t = widget.inicial.temas?.where(_temas.contains).toList();
      return t == null || t.isEmpty ? null : t;
    },
  );

  Widget _chip(String label, bool on, VoidCallback? onTap, {Color color = kAccent, Color? texto}) => Semantics(
        selected: on,
        button: true,
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: on ? color : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? kInk : kInk.withValues(alpha: 0.18), width: 2),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: on ? (texto ?? Colors.white) : kInk, fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      );

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t.toUpperCase(), style: const TextStyle(color: kGrisAA, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
      );

  @override
  Widget build(BuildContext context) {
    final n = cuantosSeEstudian(widget.parrafos, _a);
    int cuenta(SoloResumen s) => widget.parrafos.where((p) => entraResumen(p, _a.copyWith(solo: s, cuantos: () => null))).length;
    final marcados = _a.temas ?? _temas;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
        child: Row(children: [
          const Icon(Icons.tune_rounded, color: kAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Estudiar', style: TextStyle(color: kInk, fontSize: 19, fontWeight: FontWeight.w900)),
              Text(widget.grupoName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kGrisAA, fontSize: 13)),
            ]),
          ),
          IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
          _seccion('Huecos que se tapan'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in kNivelesResumen)
              _chip(
                '${nivelInfoResumen[k]!.nombre} (${kNivelCorto[k]})',
                _a.niveles.contains(k),
                () => setState(() {
                  final ns = _a.niveles.contains(k) ? _a.niveles.where((x) => x != k).toList() : ([..._a.niveles, k]..sort());
                  if (ns.isNotEmpty) _a = _a.copyWith(niveles: ns);
                }),
                color: nivelInfoResumen[k]!.soft,
                texto: kTintaNivel[k],
              ),
          ]),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Los huecos de los demás niveles se ven. Solo salen los párrafos con algún hueco de estos niveles.',
              style: TextStyle(color: kGrisAA, fontSize: 12),
            ),
          ),
          if (_temas.length > 1) ...[
            _seccion('Temas'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in _temas)
                _chip(
                  t.isEmpty ? 'Sin tema' : t,
                  marcados.contains(t),
                  () => setState(() {
                    final nuevos = marcados.contains(t) ? marcados.where((x) => x != t).toList() : [...marcados, t];
                    if (nuevos.isNotEmpty) _a = _a.copyWith(temas: () => nuevos.length == _temas.length ? null : nuevos);
                  }),
                ),
            ]),
          ],
          _seccion('Qué párrafos'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in SoloResumen.values)
              _chip('${kNombreSoloResumen[s]} · ${cuenta(s)}', _a.solo == s, cuenta(s) == 0 && _a.solo != s ? null : () => setState(() => _a = _a.copyWith(solo: s))),
          ]),
          if (_a.solo == SoloResumen.huecos)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Salen los párrafos con algún hueco que la última vez no sabías, y se tapan solo esos.',
                style: TextStyle(color: kGrisAA, fontSize: 12),
              ),
            ),
          _seccion('Cuántos'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in [...kCuantosResumen, null]) _chip(c == null ? 'Todos' : '$c', _a.cuantos == c, () => setState(() => _a = _a.copyWith(cuantos: () => c))),
          ]),
          _seccion('Al estudiar'),
          _interruptor(
            'Escribir la respuesta',
            'Escribe lo que va en cada hueco antes de destaparlo; se compara y se propone «Lo sabía» o «No lo sabía».',
            _a.escribir,
            (v) => setState(() => _a = _a.copyWith(escribir: v)),
          ),
          _interruptor(
            'Cajas del mismo ancho',
            'Todas las cajas tapadas iguales: no delatan lo larga que es la respuesta.',
            _a.anchoFijo,
            (v) => setState(() => _a = _a.copyWith(anchoFijo: v)),
          ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kHairline))),
        child: SafeArea(
          top: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              n > 0 ? 'Vas a estudiar $n ${n == 1 ? 'párrafo' : 'párrafos'}.' : 'Ningún párrafo coincide con estos ajustes.',
              style: TextStyle(color: n > 0 ? kInk : kRojoKo, fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            StickerButton(label: 'Empezar', icon: Icons.play_arrow_rounded, expand: true, onPressed: n == 0 ? null : () => Navigator.pop(context, _a)),
          ]),
        ),
      ),
    ]);
  }

  // El fondo lo pinta un Material propio: dentro de una caja con color, el efecto de tocar no se vería.
  Widget _interruptor(String titulo, String ayuda, bool valor, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: valor ? kInk : kInk.withValues(alpha: 0.18), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
          value: valor,
          onChanged: onChanged,
          activeThumbColor: kAccent,
          title: Text(titulo, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w800)),
          subtitle: Text(ayuda, style: const TextStyle(color: kGrisAA, fontSize: 12)),
          ),
        ),
      );
}
