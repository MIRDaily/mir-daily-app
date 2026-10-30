// La lista de mapas mentales, ordenada por carpetas (asignatura y tema), las mismas de la web y de
// la Biblioteca.
//
// - Arriba, los fijados en una tira (atajo; siguen también en su carpeta).
// - «Por asignatura»: una sección plegable por asignatura, con su icono y color, y dentro los mapas
//   por tema. «Sin clasificar», al final. «Recientes»: todos, el último tocado primero.
// - Buscar mira el título y la carpeta.
// - Cada mapa tiene su menú: fijarlo o quitarlo, y moverlo a otra carpeta (la herramienta para
//   ordenar de verdad).
//
// La lista no baja los mapas enteros (sin miniatura hasta la tanda 6 de Studio). Crear, borrar y
// la IA siguen en la web.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/flashcards.dart' show visualAsignatura;
import '../../core/responsive/breakpoints.dart';
import '../../core/services/carpetas.dart';
import '../../core/services/haptics_service.dart';
import '../../core/services/mapas_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ia/destino_carpeta.dart' show elegirCarpeta;
import '../../shared/sticker/sticker.dart';
import '../flashcards/widgets/flashcards_ui.dart' show iconoAsignatura;
import '../resumenes/resumenes_grupo.dart' show resolveColorResumen;
import 'mapa_screen.dart';
import 'mapas_agrupar.dart';

enum _Vista { carpetas, recientes }

class MapasScreen extends StatefulWidget {
  const MapasScreen({super.key});

  @override
  State<MapasScreen> createState() => _MapasScreenState();
}

class _MapasScreenState extends State<MapasScreen> {
  List<ResumenMapa>? _mapas;
  List<AsignaturaCatalogo>? _arbol;
  String? _error;
  String _buscar = '';
  _Vista _vista = _Vista.carpetas;

  /// Las asignaturas desplegadas (null = «Sin clasificar»). Null hasta la primera carga.
  Set<int?>? _abiertas;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final mapasApi = context.read<MapasApi>();
    final carpetas = _carpetasApi();
    try {
      // El catálogo es solo para los nombres: si falla, la lista sale igual.
      final arbolF = carpetas?.arbol().then<List<AsignaturaCatalogo>?>((a) => a, onError: (_) => null);
      final m = await mapasApi.lista();
      final a = await (arbolF ?? Future<List<AsignaturaCatalogo>?>.value(null));
      if (!mounted) return;
      setState(() {
        _mapas = m;
        _arbol = a ?? _arbol;
        _error = null;
        if (_abiertas == null) {
          // Con pocas asignaturas, todas abiertas; con más, solo la primera (la más reciente).
          final g = agruparPorCarpeta(m, _arbol);
          _abiertas = g.length <= 2 ? {for (final x in g) x.asignaturaId} : {if (g.isNotEmpty) g.first.asignaturaId};
        }
        // Sin carpetas en la BD, agrupar no aporta nada.
        if (m.isNotEmpty && m.every((x) => x.carpeta == null)) _vista = _Vista.recientes;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is MapasException ? e.message : 'No se pudieron cargar los mapas');
    }
  }

  /// El cliente de carpetas, si está en el árbol (en la app siempre; en algún test, no).
  /// `read<CarpetasApi?>` no lo encuentra: busca un proveedor del tipo nullable.
  CarpetasApi? _carpetasApi() {
    try {
      return context.read<CarpetasApi>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _aviso(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  Future<void> _abrir(ResumenMapa m) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapaScreen(mapaId: m.id, titulo: m.titulo)));
    if (mounted) _cargar();
  }

  void _reemplazar(ResumenMapa nuevo) =>
      setState(() => _mapas = [for (final m in _mapas!) m.id == nuevo.id ? nuevo : m]);

  Future<void> _fijar(ResumenMapa m) async {
    HapticsService.light();
    _reemplazar(m.copiaCon(fijado: !m.fijado));
    try {
      await context.read<MapasApi>().fijar(m.id, !m.fijado);
    } catch (_) {
      if (!mounted) return;
      _reemplazar(m);
      _aviso('No se pudo ${m.fijado ? 'quitar de fijados' : 'fijar'} el mapa');
    }
  }

  Future<void> _mover(ResumenMapa m) async {
    final carpetas = _carpetasApi();
    if (carpetas == null) return;
    try {
      final arbol = _arbol ?? await carpetas.arbol();
      if (!mounted) return;
      final actual = m.carpeta ?? Carpeta.sinClasificar;
      final elegida = await elegirCarpeta(context, arbol: arbol, valor: actual);
      if (elegida == null || elegida == actual || !mounted) return;
      await carpetas.mover('mapa', [m.id], elegida);
      if (!mounted) return;
      _reemplazar(m.copiaCon(carpeta: elegida));
      setState(() => _abiertas = {...?_abiertas, elegida.subjectId});
      _aviso('Movido a ${nombreCarpeta(arbol, elegida)}');
    } catch (_) {
      if (mounted) _aviso('No se pudo mover el mapa');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapas = _mapas;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mapas mentales')),
      body: SafeArea(
        top: false,
        child: mapas == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: AppColors.primary)
                    : Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kInk, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 14),
                          StickerButton(label: 'Reintentar', icon: Icons.refresh_rounded, onPressed: _cargar),
                        ]),
                      ),
              )
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(context.bodyGutter, 8, context.bodyGutter, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _contenido(mapas),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _contenido(List<ResumenMapa> mapas) {
    final grupos = agruparPorCarpeta(mapas, _arbol);
    final buscando = _buscar.trim().isNotEmpty;
    final fijados = [for (final m in mapas) if (m.fijado) m];
    final conCarpetas = mapas.any((m) => m.carpeta != null);
    final asignaturas = grupos.where((g) => g.asignaturaId != null).length;

    Widget fila(ResumenMapa m, {bool conCarpeta = false}) => _FilaMapa(
          mapa: m,
          carpeta: conCarpeta ? carpetaDeMapa(m, _arbol) : null,
          onAbrir: () => _abrir(m),
          onFijar: () => _fijar(m),
          onMover: conCarpetas && _carpetasApi() != null ? () => _mover(m) : null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Tus mapas', style: TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(
          mapas.isEmpty
              ? 'Créalos en la web (Studio → Mapas) y aparecerán aquí.'
              : '${mapas.length} ${mapas.length == 1 ? 'mapa' : 'mapas'}'
                  '${asignaturas > 0 ? ' en $asignaturas ${asignaturas == 1 ? 'asignatura' : 'asignaturas'}' : ''}'
                  '. Aquí los miras y retocas; crearlos, estilos e IA, en la web.',
          style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.4),
        ),
        if (mapas.isNotEmpty) ...[
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _buscar = v),
            decoration: InputDecoration(
              hintText: 'Buscar por título o asignatura',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
        if (buscando) ...[
          const SizedBox(height: 16),
          ...() {
            final r = buscarMapas(mapas, _buscar, _arbol);
            return r.isEmpty
                ? [const Padding(padding: EdgeInsets.all(24), child: Text('Ningún mapa coincide.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)))]
                : [_Caja(children: [for (final m in r) fila(m, conCarpeta: true)])];
          }(),
        ] else if (mapas.isNotEmpty) ...[
          if (fijados.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionLabel('Fijados'),
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: fijados.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _Fijado(
                  mapa: fijados[i],
                  carpeta: carpetaDeMapa(fijados[i], _arbol),
                  onTap: () => _abrir(fijados[i]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (conCarpetas)
            _SelectorVista(vista: _vista, onCambiar: (v) => setState(() => _vista = v)),
          const SizedBox(height: 14),
          if (_vista == _Vista.recientes)
            _Caja(children: [for (final m in [...mapas]..sort((a, b) => b.actualizado.compareTo(a.actualizado))) fila(m, conCarpeta: conCarpetas)])
          else
            for (final g in grupos) ...[
              _SeccionAsignatura(
                grupo: g,
                abierta: _abiertas?.contains(g.asignaturaId) ?? true,
                onAlternar: () => setState(() {
                  final a = {...?_abiertas};
                  a.contains(g.asignaturaId) ? a.remove(g.asignaturaId) : a.add(g.asignaturaId);
                  _abiertas = a;
                }),
                fila: fila,
              ),
              const SizedBox(height: 12),
            ],
        ],
      ],
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Piezas
═══════════════════════════════════════════════════════════════════════════ */

class _SelectorVista extends StatelessWidget {
  final _Vista vista;
  final ValueChanged<_Vista> onCambiar;

  const _SelectorVista({required this.vista, required this.onCambiar});

  @override
  Widget build(BuildContext context) {
    Widget opcion(_Vista v, IconData icono, String texto) {
      final sel = v == vista;
      return Expanded(
        child: Semantics(
          selected: sel,
          button: true,
          child: GestureDetector(
            onTap: () => onCambiar(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: sel ? kInk : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icono, size: 17, color: sel ? Colors.white : kMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(texto, style: TextStyle(color: sel ? Colors.white : kMuted, fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kInk, width: 1.5),
      ),
      child: Row(children: [
        opcion(_Vista.carpetas, Icons.folder_rounded, 'Por asignatura'),
        opcion(_Vista.recientes, Icons.schedule_rounded, 'Recientes'),
      ]),
    );
  }
}

/// Una caja blanca con filas separadas por una línea fina.
class _Caja extends StatelessWidget {
  final List<Widget> children;
  const _Caja({required this.children});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      radius: 18,
      depth: 4,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: kHairline, indent: 14, endIndent: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SeccionAsignatura extends StatelessWidget {
  final GrupoAsignatura grupo;
  final bool abierta;
  final VoidCallback onAlternar;
  final Widget Function(ResumenMapa m, {bool conCarpeta}) fila;

  const _SeccionAsignatura({required this.grupo, required this.abierta, required this.onAlternar, required this.fila});

  @override
  Widget build(BuildContext context) {
    final sin = grupo.asignaturaId == null;
    final v = visualAsignatura(grupo.nombre);
    final color = sin ? const Color(0xFFEDEAE7) : resolveColorResumen(v.color).bg;
    final icono = sin ? Icons.inbox_rounded : iconoAsignatura(v.icon);
    // Los temas solo se rotulan si hay más de uno o si el único no es «General».
    final rotularTemas = grupo.temas.length > 1 || (grupo.temas.single.temaId != null);

    return StickerCard(
      radius: 18,
      depth: 4,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: abierta,
            label: '${grupo.nombre}, ${grupo.total} ${grupo.total == 1 ? 'mapa' : 'mapas'}',
            child: InkWell(
              onTap: onAlternar,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kInk, width: 1.5),
                        ),
                        child: Icon(icono, color: sin ? kMuted : Colors.white, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          grupo.nombre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kInk, fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFF2EFED), borderRadius: BorderRadius.circular(99)),
                        child: Text('${grupo.total}', style: const TextStyle(color: kInk, fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: abierta ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more_rounded, color: kInk),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: kEaseOut,
            alignment: Alignment.topCenter,
            child: !abierta
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, thickness: 1.5, color: kInk),
                      for (final t in grupo.temas) ...[
                        if (rotularTemas)
                          Container(
                            color: const Color(0xFFFAF7F4),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                            child: Text(
                              t.nombre.toUpperCase(),
                              style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                            ),
                          ),
                        for (var i = 0; i < t.mapas.length; i++) ...[
                          if (i > 0) const Divider(height: 1, thickness: 1, color: kHairline, indent: 14, endIndent: 14),
                          fila(t.mapas[i]),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _cuando(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'ahora';
  if (d.inHours < 1) return 'hace ${d.inMinutes} min';
  if (d.inDays < 1) return 'hace ${d.inHours} h';
  if (d.inDays < 30) return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
  return '${t.day}/${t.month}/${t.year}';
}

class _FilaMapa extends StatelessWidget {
  final ResumenMapa mapa;
  final String? carpeta;
  final VoidCallback onAbrir;
  final VoidCallback onFijar;
  final VoidCallback? onMover;

  const _FilaMapa({required this.mapa, required this.carpeta, required this.onAbrir, required this.onFijar, required this.onMover});

  @override
  Widget build(BuildContext context) {
    final sub = [if (mapa.ejemplo) 'Ejemplo', if (carpeta != null && carpeta!.isNotEmpty) carpeta!, _cuando(mapa.actualizado)].join(' · ');
    return InkWell(
      onTap: onAbrir,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            const Icon(Icons.account_tree_rounded, color: kAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mapa.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
                ],
              ),
            ),
            if (mapa.fijado) const Icon(Icons.push_pin_rounded, size: 16, color: kMuted),
            PopupMenuButton<String>(
              tooltip: 'Opciones de ${mapa.titulo}',
              icon: const Icon(Icons.more_vert_rounded, color: kInk),
              onSelected: (v) => v == 'fijar' ? onFijar() : onMover?.call(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'fijar',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(mapa.fijado ? Icons.push_pin_outlined : Icons.push_pin_rounded),
                    title: Text(mapa.fijado ? 'Quitar de fijados' : 'Fijar arriba'),
                  ),
                ),
                if (onMover != null)
                  const PopupMenuItem(
                    value: 'mover',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_move_rounded),
                      title: Text('Mover a carpeta'),
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

class _Fijado extends StatelessWidget {
  final ResumenMapa mapa;
  final String carpeta;
  final VoidCallback onTap;

  const _Fijado({required this.mapa, required this.carpeta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: StickerCard(
        radius: 16,
        depth: 3,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        background: tinted(kAccent, 0.14),
        onTap: onTap,
        pressDelay: const Duration(milliseconds: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.push_pin_rounded, size: 15, color: kInk),
            const SizedBox(height: 4),
            Text(mapa.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.2)),
            const Spacer(),
            Text(carpeta.isEmpty ? _cuando(mapa.actualizado) : carpeta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
