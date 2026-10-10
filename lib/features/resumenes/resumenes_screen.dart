import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/resumen.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/widgets/pressable.dart';
import 'resumen_detail_screen.dart';
import 'resumenes_api.dart';
import 'resumenes_grupo.dart';

/// Resúmenes activos: los grupos del usuario. Un resumen activo es un párrafo de
/// repaso con huecos que se estudia destapando y autoevaluando, con repaso
/// espaciado. Se crean con IA desde un documento (fase 2) o a mano en un grupo.
class ResumenesScreen extends StatefulWidget {
  const ResumenesScreen({super.key});

  @override
  State<ResumenesScreen> createState() => _ResumenesScreenState();
}

class _ResumenesScreenState extends State<ResumenesScreen> {
  List<GrupoResumen>? _grupos;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _grupos == null;
        _error = null;
      });
    }
    try {
      final grupos = await context.read<ResumenesApi>().listarGrupos();
      if (!mounted) return;
      setState(() {
        _grupos = grupos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus resúmenes. Desliza para reintentar.';
        _loading = false;
      });
    }
  }

  Future<void> _crear() async {
    final resultado = await showAdaptiveModal<(String, String, String)>(
      context: context,
      builder: (_) => const _CrearGrupoSheet(),
    );
    if (resultado == null || !mounted) return;
    final (nombre, color, icon) = resultado;
    try {
      await context.read<ResumenesApi>().crearGrupo(nombre, color: color, icon: icon);
      await _load();
    } on ResumenesApiError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo crear el grupo.');
    }
  }

  Future<void> _confirmarBorrado(GrupoResumen grupo) async {
    final ok = await showAdaptiveModal<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: Text('Eliminar "${grupo.name}"'),
                subtitle: const Text('Podrás recuperarlo 24 h desde la papelera.'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ResumenesApi>().borrarGrupo(grupo.id);
      await _load();
    } on ResumenesApiError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo eliminar el grupo.');
    }
  }

  void _abrir(GrupoResumen grupo) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResumenDetailScreen(grupo: grupo)));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _grupos ?? const <GrupoResumen>[];
    final totalParrafos = grupos.fold<int>(0, (n, g) => n + g.total);
    final totalPendientes = grupos.fold<int>(0, (n, g) => n + g.pendientes);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 4, right: 4),
        child: StickerButton(
          label: 'Nuevo grupo',
          icon: Icons.add_rounded,
          onPressed: _crear,
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                  child: StickerHero(
                    badge: 'Repaso espaciado',
                    badgeIcon: Icons.text_snippet_rounded,
                    title: 'Resúmenes activos',
                    subtitle:
                        'Párrafos de repaso con los datos clave tapados. Lee, intenta recordar, destapa y valora.',
                    aside: _loading || grupos.isEmpty
                        ? null
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              StatChip(value: '${grupos.length}', label: grupos.length == 1 ? 'grupo' : 'grupos'),
                              StatChip(value: '$totalParrafos', label: 'párrafos', color: const Color(0xFF3F7EA6)),
                              StatChip(value: '$totalPendientes', label: 'por repasar', color: const Color(0xFFB07A1E)),
                            ],
                          ),
                  ),
                ),
              ),
              ..._contenido(),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _contenido() {
    if (_loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((_, i) => const _GrupoSkeleton(), childCount: 3),
          ),
        ),
      ];
    }

    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
            child: Column(
              children: [
                const Icon(Icons.cloud_off_rounded, color: AppColors.textLight, size: 44),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              ],
            ),
          ),
        ),
      ];
    }

    final grupos = _grupos ?? const <GrupoResumen>[];
    if (grupos.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 14, 32, 0),
            child: Column(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: kInk, width: 2),
                    boxShadow: inkShadow(4),
                  ),
                  child: const Icon(Icons.text_snippet_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 18),
                const Text('Aún no tienes resúmenes activos', textAlign: TextAlign.center, style: TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                const Text(
                  'Crea un grupo y escribe tus párrafos marcando los datos que quieres tapar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
        sliver: SliverToBoxAdapter(child: SectionLabel('Tus grupos')),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _GrupoCard(
              grupo: grupos[i],
              onAbrir: () => _abrir(grupos[i]),
              onEstudiar: () => _toast('El estudio llega en una fase posterior.'),
              onBorrar: () => _confirmarBorrado(grupos[i]),
            ),
            childCount: grupos.length,
          ),
        ),
      ),
    ];
  }
}

class _GrupoCard extends StatelessWidget {
  final GrupoResumen grupo;
  final VoidCallback onAbrir;
  final VoidCallback onEstudiar;
  final VoidCallback onBorrar;

  const _GrupoCard({required this.grupo, required this.onAbrir, required this.onEstudiar, required this.onBorrar});

  @override
  Widget build(BuildContext context) {
    final color = resolveColorResumen(grupo.color);
    return Pressable(
      onTap: onAbrir,
      pressedScale: 0.97,
      child: StickerCard(
        margin: const EdgeInsets.only(bottom: 14),
        depth: 4,
        radius: 20,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera con el color del grupo.
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: color.soft,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                border: const Border(bottom: BorderSide(color: Color(0x1F2C3E50))),
              ),
              child: Row(
                children: [
                  _BaldosaGrupo(color: color.bg, icon: iconoGrupoResumen(grupo.icon)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(grupo.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 17)),
                        Text(
                          '${grupo.total} ${grupo.total == 1 ? 'párrafo' : 'párrafos'} · ${grupo.pendientes} por repasar',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onBorrar,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: kInk, width: 1.6)),
                      child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barra de estados.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 8,
                      color: const Color(0xFFF2EFED),
                      child: Row(
                        children: [
                          for (final e in ordenEstadosResumen)
                            if (grupo.total > 0 && cuentaEstadoResumen(grupo.resumen, e) > 0)
                              Expanded(flex: cuentaEstadoResumen(grupo.resumen, e), child: Container(color: estadoRepasoResumen[e]!.color)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      for (final e in ordenEstadosResumen)
                        if (cuentaEstadoResumen(grupo.resumen, e) > 0)
                          Text('${cuentaEstadoResumen(grupo.resumen, e)} ${estadoRepasoResumen[e]!.nombre}', style: TextStyle(color: estadoRepasoResumen[e]!.color, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StickerButton(
                          label: 'Estudiar',
                          icon: Icons.play_arrow_rounded,
                          compact: true,
                          onPressed: grupo.total == 0 ? null : onEstudiar,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GhostButton(label: 'Abrir', icon: Icons.list_rounded, compact: true, onPressed: onAbrir),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaldosaGrupo extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _BaldosaGrupo({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(2),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _GrupoSkeleton extends StatefulWidget {
  const _GrupoSkeleton();
  @override
  State<_GrupoSkeleton> createState() => _GrupoSkeletonState();
}

class _GrupoSkeletonState extends State<_GrupoSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_shimmer),
      child: Container(
        height: 130,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(4),
        ),
      ),
    );
  }
}

/// Modal de crear grupo: nombre + color + icono.
class _CrearGrupoSheet extends StatefulWidget {
  const _CrearGrupoSheet();
  @override
  State<_CrearGrupoSheet> createState() => _CrearGrupoSheetState();
}

class _CrearGrupoSheetState extends State<_CrearGrupoSheet> {
  final _controller = TextEditingController();
  String _color = colorGrupoPorDefecto;
  String _icon = iconoResumenPorDefecto;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _crear() {
    final nombre = _controller.text.trim();
    if (nombre.length < 3) return;
    Navigator.pop(context, (nombre, _color, _icon));
  }

  @override
  Widget build(BuildContext context) {
    final color = resolveColorResumen(_color);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuevo grupo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: kInk)),
            const SizedBox(height: 16),
            Row(
              children: [
                _BaldosaGrupo(color: color.bg, icon: iconoGrupoResumen(_icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _crear(),
                    decoration: const InputDecoration(hintText: 'Nombre del grupo (mín. 3 letras)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Color'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in subjectColorsResumen)
                  GestureDetector(
                    onTap: () => setState(() => _color = c.key),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c.bg,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.key == _color ? kInk : const Color(0x262C3E50), width: 2),
                        boxShadow: c.key == _color ? const [BoxShadow(color: Colors.white, spreadRadius: 0, blurRadius: 0), BoxShadow(color: kInk, offset: Offset(0, 0), blurRadius: 0, spreadRadius: 0)] : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const SectionLabel('Icono'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ic in iconosResumen)
                  GestureDetector(
                    onTap: () => setState(() => _icon = ic),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ic == _icon ? color.bg : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ic == _icon ? kInk : kHairline, width: 2),
                      ),
                      child: Icon(iconoGrupoResumen(ic), size: 20, color: ic == _icon ? Colors.white : AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                    onPressed: _controller.text.trim().length < 3 ? null : _crear,
                    child: const Text('Crear'),
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
