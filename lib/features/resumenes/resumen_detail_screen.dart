import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/resumen.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import 'crear_resumenes_ia_screen.dart';
import 'resumen_editor.dart';
import 'resumen_study_screen.dart';
import 'resumenes_api.dart';
import 'resumenes_filtro.dart';
import 'resumenes_grupo.dart';
import 'widgets/parrafo_huecos.dart';

/// Detalle de un grupo: sus párrafos, escribir y editar (marcando huecos) y
/// filtrar/buscar. El estudio llega en la fase 1d.
class ResumenDetailScreen extends StatefulWidget {
  final GrupoResumen grupo;

  const ResumenDetailScreen({super.key, required this.grupo});

  @override
  State<ResumenDetailScreen> createState() => _ResumenDetailScreenState();
}

class _ResumenDetailScreenState extends State<ResumenDetailScreen> {
  List<Parrafo>? _parrafos;
  String? _error;
  bool _loading = true;
  final _busquedaCtrl = TextEditingController();
  FiltrosGrupo _filtros = const FiltrosGrupo();
  final OrdenGrupo _orden = OrdenGrupo.documento;
  int _pagina = 0;
  static const int _porPagina = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _parrafos == null;
        _error = null;
      });
    }
    try {
      final r = await context.read<ResumenesApi>().cargarGrupo(widget.grupo.id);
      if (!mounted) return;
      setState(() {
        _parrafos = r.parrafos;
        _loading = false;
      });
    } on ResumenesApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el grupo.';
        _loading = false;
      });
    }
  }

  List<String> get _temas => (_parrafos ?? const <Parrafo>[])
      .map((p) => (p.tema ?? '').trim())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _escribir() async {
    final res = await Navigator.of(context).push<ResultadoEditor>(
      MaterialPageRoute(
        builder: (_) => ResumenEditorScreen(textoInicial: '', huecosIniciales: const [], temaInicial: '', temas: _temas),
      ),
    );
    if (res == null || !mounted) return;
    try {
      await context.read<ResumenesApi>().anadirParrafos(
            widget.grupo.id,
            [ParrafoNuevo(texto: res.texto, huecos: res.huecos, tema: res.tema.isEmpty ? null : res.tema)],
          );
      await _load();
    } on ResumenesApiError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo guardar el párrafo.');
    }
  }

  Future<void> _editar(Parrafo p) async {
    final res = await Navigator.of(context).push<ResultadoEditor>(
      MaterialPageRoute(
        builder: (_) => ResumenEditorScreen(textoInicial: p.texto, huecosIniciales: p.huecos, temaInicial: p.tema ?? '', temas: _temas),
      ),
    );
    if (res == null || !mounted) return;
    try {
      await context.read<ResumenesApi>().editarParrafo(p.id, texto: res.texto, huecos: res.huecos, tema: res.tema);
      await _load();
    } on ResumenesApiError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo guardar el párrafo.');
    }
  }

  Future<void> _borrar(Parrafo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Borrar párrafo'),
        content: const Text('Podrás recuperarlo 24 h desde la papelera.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ResumenesApi>().quitarParrafo(widget.grupo.id, p.itemId);
      await _load();
    } on ResumenesApiError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo borrar el párrafo.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: AppColors.textPrimary));
  }

  void _estudiar() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResumenStudyScreen(grupoId: widget.grupo.id, grupoName: widget.grupo.name),
    ));
  }

  Future<void> _crearConIa() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CrearResumenesIAScreen()));
    _load();
  }

  Future<void> _abrirPapelera() async {
    final api = context.read<ResumenesApi>();
    final papelera = await api.listarPapelera(widget.grupo.id);
    if (!mounted) return;
    await showAdaptiveModal<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Papelera', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: kInk)),
              const SizedBox(height: 6),
              const Text('Los párrafos borrados se recuperan hasta pasadas 24 horas.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 14),
              if (papelera.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('La papelera está vacía.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)))
              else
                for (final e in papelera)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.parrafo.texto, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontSize: 13)),
                    subtitle: Text(e.parrafo.tema?.isNotEmpty == true ? e.parrafo.tema! : 'Sin tema', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await api.restaurarParrafo(widget.grupo.id, e.parrafo.itemId);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _load();
                        } on ResumenesApiError catch (err) {
                          _toast(err.message);
                        } catch (_) {
                          _toast('No se pudo recuperar el párrafo.');
                        }
                      },
                      child: const Text('Restaurar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = resolveColorResumen(widget.grupo.color);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kInk, width: 2)),
              child: Icon(iconoGrupoResumen(widget.grupo.icon), color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.grupo.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Papelera',
            icon: const Icon(Icons.delete_outline_rounded, color: kInk),
            onPressed: _abrirPapelera,
          ),
          IconButton(
            tooltip: 'Crear con IA',
            icon: const Icon(Icons.auto_awesome_rounded, color: kInk),
            onPressed: _crearConIa,
          ),
          IconButton(
            tooltip: 'Estudiar',
            icon: const Icon(Icons.play_arrow_rounded, color: kInk),
            onPressed: _estudiar,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 4),
        child: StickerButton(label: 'Escribir párrafo', icon: Icons.edit_note_rounded, onPressed: _escribir),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: _buscadorYFiltros()),
              ..._contenido(),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buscadorYFiltros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _busquedaCtrl,
            onChanged: (v) => setState(() {
              _filtros = _filtros.copyWith(busqueda: v);
              _pagina = 0;
            }),
            decoration: InputDecoration(
              hintText: 'Buscar en los párrafos',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kHairline, width: 2)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kHairline, width: 2)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in ordenEstadosResumen) _chipEstado(e),
              _chipToggle('Toca repasar', Icons.schedule_rounded, _filtros.tocaRepasar, () => setState(() {
                _filtros = _filtros.copyWith(tocaRepasar: !_filtros.tocaRepasar);
                _pagina = 0;
              })),
              _chipToggle('Con fallados', Icons.local_fire_department_rounded, _filtros.conFallados, () => setState(() {
                _filtros = _filtros.copyWith(conFallados: !_filtros.conFallados);
                _pagina = 0;
              })),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipEstado(EstadoParrafoSrs e) {
    final sel = _filtros.estados.contains(e);
    final info = estadoRepasoResumen[e]!;
    return GestureDetector(
      onTap: () {
        setState(() {
          final estados = List<EstadoParrafoSrs>.from(_filtros.estados);
          sel ? estados.remove(e) : estados.add(e);
          _filtros = _filtros.copyWith(estados: estados);
          _pagina = 0;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? info.color : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: sel ? info.color : kHairline, width: 2),
        ),
        child: Text(info.nombre, style: TextStyle(color: sel ? Colors.white : info.color, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _chipToggle(String label, IconData icon, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kHairline, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: sel ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  List<Widget> _contenido() {
    if (_loading) {
      return [const SliverPadding(padding: EdgeInsets.all(20), sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator(color: AppColors.primary))))];
    }
    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
            child: Column(children: [
              const Icon(Icons.cloud_off_rounded, color: AppColors.textLight, size: 44),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            ]),
          ),
        ),
      ];
    }

    final parrafos = _parrafos ?? const <Parrafo>[];
    if (parrafos.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 40, 32, 0),
            child: Column(children: [
              Text('Aún no hay párrafos', textAlign: TextAlign.center, style: TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 18)),
              SizedBox(height: 8),
              Text('Toca «Escribir párrafo» y marca las palabras que quieres tapar.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5)),
            ]),
          ),
        ),
      ];
    }

    final filtrados = filtrarParrafos(parrafos, _filtros);
    final ordenados = ordenarParrafos(filtrados, _orden);
    final totalPaginas = (ordenados.length / _porPagina).ceil();
    final pagina = _pagina.clamp(0, totalPaginas > 1 ? totalPaginas - 1 : 0);
    final inicio = pagina * _porPagina;
    final paginados = ordenados.skip(inicio).take(_porPagina).toList();
    final grupos = agruparPorTema(paginados);

    if (grupos.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 40, 32, 0),
            child: Text('Ningún párrafo coincide con los filtros.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ),
        ),
      ];
    }

    return [
      for (final (tema, lista) in grupos)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (tema.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tema, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.4))),
              for (final p in lista) _ParrafoCard(parrafo: p, onEditar: () => _editar(p), onBorrar: () => _borrar(p)),
            ]),
          ),
        ),
      if (totalPaginas > 1)
        SliverToBoxAdapter(child: _paginador(totalPaginas, pagina)),
    ];
  }

  Widget _paginador(int totalPaginas, int pagina) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: pagina > 0 ? () => setState(() => _pagina = pagina - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('Página ${pagina + 1} de $totalPaginas', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: pagina < totalPaginas - 1 ? () => setState(() => _pagina = pagina + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _ParrafoCard extends StatelessWidget {
  final Parrafo parrafo;
  final VoidCallback onEditar;
  final VoidCallback onBorrar;

  const _ParrafoCard({required this.parrafo, required this.onEditar, required this.onBorrar});

  @override
  Widget build(BuildContext context) {
    final vence = cuandoVence(parrafo);
    final estado = parrafo.status != null ? estadoRepasoResumen[parrafo.status] : null;
    return StickerCard(
      margin: const EdgeInsets.only(bottom: 12),
      depth: 3,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (estado != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: estado.color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              if (vence != null) Text(vence, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              InkWell(onTap: onEditar, borderRadius: BorderRadius.circular(8), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_rounded, size: 18, color: AppColors.textSecondary))),
              InkWell(onTap: onBorrar, borderRadius: BorderRadius.circular(8), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error))),
            ],
          ),
          const SizedBox(height: 6),
          ParrafoHuecos(texto: parrafo.texto, huecos: parrafo.huecos),
        ],
      ),
    );
  }
}
