// Previsión y estadísticas de los resúmenes activos («Lo que te espera», «Cómo lo llevas» y «Los
// huecos que más se te resisten») y el aviso «Tienes N párrafos para repasar» de Studio y la
// Biblioteca. Una sola petición agregada (la base de datos cuenta). Si falla, no sale nada: es un
// extra. Puerto de src/components/resumenes/PanelPrevision.tsx y AvisoResumenes.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/resumen.dart';
import '../../../shared/sticker/sticker.dart';
import '../resumenes_api.dart';
import '../resumenes_grupo.dart';
import '../resumenes_logica.dart';

const _estados = [
  (e: EstadoParrafoSrs.new_, nombre: 'nuevos', color: Color(0xFF7D8A96)),
  (e: EstadoParrafoSrs.failed, nombre: 'fallados', color: Color(0xFFB04A5E)),
  (e: EstadoParrafoSrs.learning, nombre: 'aprendiendo', color: Color(0xFFB07A1E)),
  (e: EstadoParrafoSrs.mastered, nombre: 'dominados', color: Color(0xFF5E8C5A)),
];

BoxDecoration _caja() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: kInk, width: 2),
      boxShadow: inkShadow(3),
    );

Widget _titulo(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(t.toUpperCase(), style: const TextStyle(color: kGrisAA, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
    );

class PanelPrevisionResumenes extends StatefulWidget {
  /// null = todos los grupos.
  final String? grupoId;

  /// Al cambiar, se vuelve a pedir (tras estudiar o tocar el grupo).
  final int recarga;

  const PanelPrevisionResumenes({super.key, this.grupoId, this.recarga = 0});

  @override
  State<PanelPrevisionResumenes> createState() => _PanelPrevisionResumenesState();
}

class _PanelPrevisionResumenesState extends State<PanelPrevisionResumenes> {
  PrevisionResumenes? _p;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant PanelPrevisionResumenes old) {
    super.didUpdateWidget(old);
    if (old.recarga != widget.recarga || old.grupoId != widget.grupoId) _cargar();
  }

  Future<void> _cargar() async {
    try {
      final p = await context.read<ResumenesApi>().cargarPrevision(widget.grupoId);
      if (mounted) setState(() => _p = p);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (_error || p == null || p.parrafos == 0) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final dos = c.maxWidth >= 640;
      final a = _teEspera(p);
      final b = _comoVas(p);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (dos)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]),
          )
        else ...[
          a,
          const SizedBox(height: 12),
          b,
        ],
        if (p.masFallados.isNotEmpty) ...[const SizedBox(height: 12), _masFallados(p)],
      ]);
    });
  }

  Widget _teEspera(PrevisionResumenes p) {
    final maxDia = p.dias.isEmpty ? 1 : p.dias.map((d) => d.n).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final tramos = tramosPrevision(p);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _caja(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titulo('Lo que te espera'),
        Row(children: [
          for (var i = 0; i < tramos.length; i++)
            Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < tramos.length - 1 ? 6 : 0),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: i == 0 ? const Color(0xFFFBEDEA) : const Color(0xFFFAF7F4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: i == 0 ? kInk : kInk.withValues(alpha: 0.12), width: 2),
                ),
                child: Column(children: [
                  Text('${tramos[i].n}', style: const TextStyle(color: kInk, fontSize: 22, fontWeight: FontWeight.w900)),
                  Text(
                    tramos[i].etiqueta.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kGrisAA, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                  if (tramos[i].nota != null)
                    Text(
                      tramos[i].nota!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kRojoKo, fontSize: 9.5, fontWeight: FontWeight.w800),
                    ),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        if (p.dias.any((d) => d.n > 0)) ...[
          Semantics(
            label: 'Párrafos que vencen cada día durante 30 días: hoy ${p.dias.first.n}, en total ${p.mes}.',
            excludeSemantics: true,
            child: SizedBox(
              height: 72,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < p.dias.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${i == 0 ? 'Hoy' : diaCortoResumen(p.dias[i].fecha)}: ${p.dias[i].n} ${p.dias[i].n == 1 ? 'párrafo' : 'párrafos'}',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: (72 * p.dias[i].n / maxDia).clamp(p.dias[i].n > 0 ? 6.0 : 2.0, 72.0),
                        decoration: BoxDecoration(
                          color: p.dias[i].n > 0 ? (i == 0 ? const Color(0xFFE8A598) : const Color(0xFF3F7EA6)) : const Color(0xFFEFEAE7),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          Container(height: 2, color: kInk),
          const SizedBox(height: 3),
          const DefaultTextStyle(
            style: TextStyle(color: kGrisAA, fontSize: 10, fontWeight: FontWeight.w800),
            child: Row(children: [Text('HOY'), Spacer(), Text('+15 D'), Spacer(), Text('+30 D')]),
          ),
        ] else
          const Text(
            'Nada programado aún: estudia un párrafo y aquí verás cuándo vuelve.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kGrisAA, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        if (p.nuevos > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Además, ${p.nuevos == 1 ? '1 párrafo nuevo' : '${p.nuevos} párrafos nuevos'} sin estudiar todavía.',
            style: const TextStyle(color: kGrisAA, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ]),
    );
  }

  Widget _comoVas(PrevisionResumenes p) {
    final total = _estados.fold<int>(0, (n, e) => n + cuentaEstadoResumen(p.estados, e.e));
    Widget cifra(String titulo, String valor, String detalle) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFAF7F4), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo.toUpperCase(), style: const TextStyle(color: kGrisAA, fontSize: 10, fontWeight: FontWeight.w800)),
              Text(valor, style: const TextStyle(color: kInk, fontSize: 22, fontWeight: FontWeight.w900)),
              Text(detalle, style: const TextStyle(color: kGrisAA, fontSize: 11, height: 1.3)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _caja(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titulo('Cómo lo llevas'),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
            child: Row(children: [
              for (final e in _estados)
                if (cuentaEstadoResumen(p.estados, e.e) > 0) Expanded(flex: cuentaEstadoResumen(p.estados, e.e), child: Container(color: e.color)),
              if (total == 0) Expanded(child: Container(color: const Color(0xFFEFEAE7))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          for (final e in _estados)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: e.color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('${cuentaEstadoResumen(p.estados, e.e)}', style: const TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w900)),
              const SizedBox(width: 3),
              Text(e.nombre, style: const TextStyle(color: kGrisAA, fontSize: 12)),
            ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          cifra(
            'Retención',
            porcentajeResumen(p.tasa),
            p.programados > 0
                ? '${p.recordados} de ${p.programados} repasos sin «Otra vez»'
                    '${p.tasa30 != null && p.programados30 != p.programados ? ' · 30 días: ${porcentajeResumen(p.tasa30)}' : ''}'
                : 'Cuando repases un párrafo por segunda vez',
          ),
          const SizedBox(width: 8),
          cifra(
            'Huecos sabidos',
            porcentajeResumen(p.tasaHuecos),
            p.huecosRepasados > 0 ? '${p.huecosSabidos} de ${p.huecosRepasados} destapados' : 'Aún no has destapado ninguno',
          ),
        ]),
      ]),
    );
  }

  Widget _masFallados(PrevisionResumenes p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _caja(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titulo('Los huecos que más se te resisten'),
        for (final m in p.masFallados)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: nivelInfoResumen[m.nivel]!.soft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border(bottom: BorderSide(color: nivelInfoResumen[m.nivel]!.color, width: 2)),
                ),
                child: Text(m.texto, style: TextStyle(color: kTintaNivel[m.nivel], fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: nivelInfoResumen[m.nivel]!.color, width: 1.5)),
                child: Text(kNivelCorto[m.nivel]!.toUpperCase(), style: TextStyle(color: kTintaNivel[m.nivel], fontSize: 10, fontWeight: FontWeight.w900)),
              ),
              if ([widget.grupoId == null ? m.grupo : null, m.tema].whereType<String>().isNotEmpty)
                Text([widget.grupoId == null ? m.grupo : null, m.tema].whereType<String>().join(' · '), style: const TextStyle(color: kGrisAA, fontSize: 12)),
              Text('${m.fallos} de ${m.intentos}', style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w800)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: m.falladoAhora ? kRojoKo : kVerdeOk, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  m.falladoAhora ? 'SIGUE FALLADO' : 'RECUPERADO',
                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// «Tienes N párrafos para repasar»: el aviso de Studio y de la Biblioteca. No sale si no hay nada,
/// ni si falla. [onAbrir] lleva a los resúmenes.
class AvisoResumenes extends StatefulWidget {
  final VoidCallback onAbrir;

  const AvisoResumenes({super.key, required this.onAbrir});

  @override
  State<AvisoResumenes> createState() => _AvisoResumenesState();
}

class _AvisoResumenesState extends State<AvisoResumenes> {
  ({String titulo, String detalle})? _aviso;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    try {
      final p = await context.read<ResumenesApi>().cargarPrevision();
      if (mounted) setState(() => _aviso = textoAviso(p));
    } catch (_) {
      // El aviso es un extra: sin él la pantalla sigue igual.
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _aviso;
    if (a == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        child: StickerCard(
          depth: 3,
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () async {
            widget.onAbrir();
          },
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFFFBEDEA), borderRadius: BorderRadius.circular(12), border: Border.all(color: kInk, width: 2)),
              child: const Icon(Icons.text_snippet_rounded, color: Color(0xFFB04A5E)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.titulo, style: const TextStyle(color: kInk, fontSize: 15, fontWeight: FontWeight.w900)),
                Text(a.detalle, style: const TextStyle(color: kGrisAA, fontSize: 12)),
              ]),
            ),
            const Icon(Icons.arrow_forward_rounded, color: kInk),
          ]),
        ),
      ),
    );
  }
}
