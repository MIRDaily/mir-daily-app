// La lista de mapas mentales. Puerto reducido de la web (src/components/mapas/list): búsqueda por
// título y los fijados arriba. Sin miniatura ni recuento de nodos: la lista no baja los mapas
// enteros (eso llega con el resumen guardado de la tanda 6 de Studio). Crear, borrar, mover de
// carpeta y la IA siguen en la web.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/mapas.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/services/mapas_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import 'mapa_screen.dart';

class MapasScreen extends StatefulWidget {
  const MapasScreen({super.key});

  @override
  State<MapasScreen> createState() => _MapasScreenState();
}

class _MapasScreenState extends State<MapasScreen> {
  List<ResumenMapa>? _mapas;
  String? _error;
  String _buscar = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final m = await context.read<MapasApi>().lista();
      if (mounted) {
        setState(() {
          _mapas = m;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is MapasException ? e.message : 'No se pudieron cargar los mapas');
    }
  }

  Future<void> _abrir(ResumenMapa m) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapaScreen(mapaId: m.id, titulo: m.titulo)));
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final mapas = _mapas;
    final q = normalizarBusquedaMapa(_buscar.trim());
    final filtrados = mapas == null
        ? const <ResumenMapa>[]
        : [for (final m in mapas) if (q.isEmpty || normalizarBusquedaMapa(m.titulo).contains(q)) m];
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Tus mapas',
                              style: TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Míralos, cambia textos, añade ramas y recoloca nodos. Para crearlos, estilos, tablas o IA, la web.',
                              style: TextStyle(color: kMuted, fontSize: 13.5, height: 1.4),
                            ),
                            const SizedBox(height: 14),
                            if (mapas.length > 4) ...[
                              TextField(
                                onChanged: (v) => setState(() => _buscar = v),
                                decoration: InputDecoration(
                                  hintText: 'Buscar por título',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (mapas.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Text(
                                  'Aún no tienes mapas. Créalos en la web (Studio → Mapas) y aparecerán aquí.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: kMuted, fontSize: 14, height: 1.4),
                                ),
                              )
                            else if (filtrados.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 30),
                                child: Text('Ningún mapa con ese título.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                              ),
                            for (final m in filtrados)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _TarjetaMapa(mapa: m, onTap: () => _abrir(m)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TarjetaMapa extends StatelessWidget {
  final ResumenMapa mapa;
  final VoidCallback onTap;

  const _TarjetaMapa({required this.mapa, required this.onTap});

  String get _cuando {
    final d = DateTime.now().difference(mapa.actualizado);
    if (d.inMinutes < 1) return 'ahora';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    if (d.inDays < 30) return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
    final a = mapa.actualizado;
    return '${a.day}/${a.month}/${a.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      radius: 18,
      depth: 4,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: onTap,
      pressDelay: const Duration(milliseconds: 120),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tinted(kAccent, 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kInk, width: 1.5),
            ),
            child: const Icon(Icons.account_tree_rounded, color: kInk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mapa.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kInk, fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [if (mapa.ejemplo) 'Ejemplo', _cuando].join(' · '),
                  style: const TextStyle(color: kMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (mapa.fijado) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.push_pin_rounded, size: 18, color: kMuted)),
          const Icon(Icons.chevron_right_rounded, color: kInk),
        ],
      ),
    );
  }
}
