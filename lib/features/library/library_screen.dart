import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/analytics.dart';
import '../../core/models/biblioteca.dart';
import '../../core/models/flashcards.dart' show CategoriaAsignatura, kNombreCategoria, visualAsignatura;
import '../../core/responsive/content_shell.dart';
import '../../core/services/api_service.dart';
import '../../core/services/carpetas.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'asignatura_biblioteca_screen.dart';
import 'sin_clasificar_screen.dart';
import 'widgets/biblioteca_ui.dart';

/// Biblioteca: las asignaturas del catálogo con el material del usuario en cada una, «Sin clasificar»
/// arriba y, aparte, su acierto en las preguntas MIR (sin mezclar cifras). Sustituye a la maqueta de
/// «Apuntes». Puerto de src/app/library/page.tsx de la web.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<AsignaturaCatalogo>? _arbol;
  Recuento? _recuento;
  String? _error;
  Map<int, SubjectHeatmapCell> _acierto = const {};
  final _busca = TextEditingController();
  CategoriaAsignatura? _filtro;

  @override
  void initState() {
    super.initState();
    _busca.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final carpetas = context.read<CarpetasApi>();
    final api = context.read<ApiService>();
    setState(() => _error = null);
    try {
      final r = await Future.wait([carpetas.arbol(), carpetas.recuento()]);
      if (!mounted) return;
      setState(() {
        _arbol = r[0] as List<AsignaturaCatalogo>;
        _recuento = r[1] as Recuento;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
    // El acierto en preguntas es un añadido: si falla, la Biblioteca se enseña igual.
    try {
      final h = await api.getSubjectHeatmap(AnalyticsWindow.all, AnalyticsMode.all);
      if (mounted) setState(() => _acierto = {for (final s in h.subjects) s.subjectId: s});
    } catch (_) {}
  }

  List<TarjetaAsignatura> get _tarjetas {
    final arbol = _arbol;
    if (arbol == null) return const [];
    final q = normalizarCarpeta(_busca.text);
    return tarjetasAsignaturas(arbol, _recuento).where((t) {
      final a = t.asignatura;
      if (_filtro != null && visualAsignatura(a.nombre).categoria != _filtro) return false;
      if (q.isEmpty) return true;
      return [a.nombre, a.nombreCorto, a.subtitulo ?? '', a.sigla ?? ''].any((x) => normalizarCarpeta(x).contains(q));
    }).toList();
  }

  Future<void> _abrir(Widget pantalla) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
    // Al volver puede haber cambiado (se ha movido algo): se recuenta.
    if (!mounted) return;
    try {
      final r = await context.read<CarpetasApi>().recuento();
      if (mounted) setState(() => _recuento = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sin = _recuento?.sinClasificar;
    final tarjetas = _tarjetas;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Biblioteca', style: TextStyle(color: kInk, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _cargar,
          child: BodyConstraint(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                const StickerHero(
                  badge: 'Biblioteca',
                  badgeIcon: Icons.local_library_rounded,
                  title: 'Tu temario, carpeta a carpeta',
                  subtitle: 'Cada asignatura con tus mapas, flashcards y resúmenes, junto a las preguntas MIR de cada tema.',
                ),
                const SizedBox(height: 16),
                if (_error != null) EstadoBiblioteca(_error!, error: true),
                StickerCard(
                  depth: 5,
                  radius: 20,
                  texture: lomosArchivador(),
                  padding: const EdgeInsets.all(14),
                  pressDelay: const Duration(milliseconds: 120),
                  onTap: () => _abrir(const SinClasificarScreen()),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4EF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kInk, width: 2),
                        boxShadow: inkShadow(3),
                      ),
                      child: const Icon(Icons.inbox_rounded, color: kInk),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Sin clasificar${sin != null && sin.total > 0 ? ' · ${sin.total}' : ''}',
                            style: const TextStyle(color: kInk, fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          _recuento == null
                              ? 'Contando tu material…'
                              : sin != null && sin.total > 0
                                  ? '${textoCuenta(sin)} sin carpeta. Muévelos a su asignatura para verlos junto a sus preguntas.'
                                  : 'Todo tu material está en su carpeta.',
                          style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.35),
                        ),
                      ]),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: kInk),
                  ]),
                ),
                const SizedBox(height: 22),
                SectionLabel('Asignaturas',
                    trailing: _recuento != null
                        ? Text('${_recuento!.total} en total', style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w700))
                        : null),
                InkInput(controller: _busca, hint: 'Busca una asignatura…'),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final f in <CategoriaAsignatura?>[null, CategoriaAsignatura.medica, CategoriaAsignatura.quirurgica, CategoriaAsignatura.basica])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f == null ? 'Todas' : kNombreCategoria[f]!),
                          selected: _filtro == f,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filtro = f),
                          selectedColor: kInk,
                          backgroundColor: Colors.white,
                          side: BorderSide(color: _filtro == f ? kInk : kHairline, width: 1.5),
                          labelStyle: TextStyle(color: _filtro == f ? Colors.white : kMuted, fontWeight: FontWeight.w800, fontSize: 12.5),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 14),
                if (_arbol == null && _error == null)
                  const EstadoBiblioteca('Cargando las asignaturas…')
                else if (tarjetas.isEmpty && _arbol != null)
                  EstadoBiblioteca('Nada con «${_busca.text}».')
                else
                  for (final t in tarjetas) _tarjeta(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(TarjetaAsignatura t) {
    final a = t.asignatura;
    final h = _acierto[a.id];
    return StickerCard(
      depth: 4,
      radius: 20,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      onTap: () => _abrir(AsignaturaBibliotecaScreen(asignatura: a)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SiglaAsignatura(asignatura: a),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.nombre, style: const TextStyle(color: kInk, fontSize: 15.5, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                a.subtitulo ?? (a.temas.isNotEmpty ? '${a.temas.length} temas en el catálogo' : 'Temas en camino'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kMuted, fontSize: 12.5),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TU MATERIAL', style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              CifrasMaterial(cuenta: t.cuenta),
              if (t.carpetas > 0)
                Text('en ${t.carpetas} ${t.carpetas == 1 ? 'carpeta' : 'carpetas'}', style: const TextStyle(color: kMuted, fontSize: 11.5)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PREGUNTAS', style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              CifrasPreguntas(acierto: h?.accuracy, respondidas: h?.total ?? 0),
            ]),
          ),
        ]),
      ]),
    );
  }
}
