import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/biblioteca.dart';
import '../../core/responsive/content_shell.dart';
import '../../core/services/carpetas.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ia/destino_carpeta.dart' show elegirCarpeta;
import '../../shared/sticker/sticker.dart';
import '../simulacro/simulacro_screen.dart';
import 'widgets/biblioteca_ui.dart';
import 'widgets/datos_asignatura.dart';

/// Una carpeta (un tema o «General» de la asignatura), con dos bloques que no mezclan cifras:
///  - Preguntas MIR: cuántas tiene el tema y tu acierto en ellas (las analíticas de siempre).
///  - Tu material: la señal de dominio y la lista de mapas y grupos, con abrir y «Mover a…».
/// Puerto de BibliotecaCarpeta.tsx de la web.
class CarpetaBibliotecaScreen extends StatefulWidget {
  final AsignaturaCatalogo asignatura;

  /// null = «General».
  final int? topicId;
  const CarpetaBibliotecaScreen({super.key, required this.asignatura, required this.topicId});

  @override
  State<CarpetaBibliotecaScreen> createState() => _CarpetaBibliotecaScreenState();
}

class _CarpetaBibliotecaScreenState extends State<CarpetaBibliotecaScreen> {
  late final CargaAsignatura _c = CargaAsignatura(widget.asignatura.id);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() => _c.cargar(context, () {
        if (mounted) setState(() {});
      });

  String get _nombre {
    if (widget.topicId == null) return 'General';
    final asig = _c.datos?.asignatura ?? widget.asignatura;
    return asig.temas.where((t) => t.id == widget.topicId).firstOrNull?.nombre ?? 'Tema';
  }

  Future<void> _mover(ElementoMaterial e) async {
    final carpetas = context.read<CarpetasApi>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final arbol = await carpetas.arbol();
      if (!mounted) return;
      final destino = await elegirCarpeta(context, arbol: arbol, valor: e.carpeta);
      if (destino == null || destino == e.carpeta) return;
      await carpetas.mover(e.tipo.valor, [e.id], destino);
      messenger.showSnackBar(SnackBar(
        content: Text('Movido a ${nombreCarpeta(arbol, destino, corto: true)}'),
        behavior: SnackBarBehavior.floating,
      ));
      _cargar();
    } catch (err) {
      messenger.showSnackBar(SnackBar(
        content: Text('$err'.replaceFirst('Exception: ', '')),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = _c.datos;
    final asig = datos?.asignatura ?? widget.asignatura;
    final existe = widget.topicId == null || asig.temas.any((t) => t.id == widget.topicId);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(_nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
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
                if (_c.error != null && datos == null)
                  EstadoBiblioteca(_c.noExiste ? 'Esa carpeta no está en la Biblioteca.' : _c.error!, error: !_c.noExiste)
                else if (datos == null)
                  const EstadoBiblioteca('Cargando la carpeta…')
                else if (!existe)
                  const EstadoBiblioteca('Esa carpeta no está en la Biblioteca.')
                else
                  ..._contenido(datos),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _contenido(DatosAsignatura datos) {
    final asig = datos.asignatura;
    final general = widget.topicId == null;
    final elementos = carpetasDeAsignatura(asig, datos.elementos).where((c) => c.topicId == widget.topicId).firstOrNull?.elementos ??
        const <ElementoMaterial>[];
    final a = _c.aciertoDe(widget.topicId);
    final d = _c.detalleDe(widget.topicId);
    final dominio = _c.dominio?.de(widget.topicId);
    final disponible = _c.dominioDisponible;

    return [
      Row(children: [
        SiglaAsignatura(asignatura: asig, grande: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(asig.nombre, style: const TextStyle(color: kMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(_nombre, style: const TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15)),
            if (general) Text('Lo que abarca varios temas de ${asig.nombreCorto}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      // ---- Preguntas MIR
      StickerCard(
        depth: 5,
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionLabel('Preguntas MIR'),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${datos.preguntasDe(widget.topicId)}', style: const TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900)),
                Text(general ? 'en toda la asignatura' : 'de este tema', style: const TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  a.respondidas > 0 && a.acierto != null ? '${a.acierto!.round()} %' : '—',
                  style: TextStyle(
                    color: a.respondidas > 0 && a.acierto != null ? colorAcierto(a.acierto!) : const Color(0xFFC9BFB9),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text('tu acierto', style: TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          if (d != null && d.total > 0)
            Wrap(spacing: 8, runSpacing: 6, children: [
              DocChip(label: '${d.bien} bien', tone: DocTone.success),
              DocChip(label: '${d.mal} mal', tone: DocTone.error),
              DocChip(label: '${d.blanco} en blanco'),
            ])
          else
            Text('Todavía no has respondido preguntas ${general ? 'de esta asignatura' : 'de este tema'}.',
                style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 8),
          const Text('Tus respuestas en el daily, los simulacros y los mazos de preguntas. Tu material propio no cuenta aquí.',
              style: TextStyle(color: kMuted, fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              label: 'Practicar en un simulacro',
              icon: Icons.quiz_rounded,
              compact: true,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SimulacroScreen())),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      // ---- Tu material
      StickerCard(
        depth: 5,
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel('Tu material', trailing: Text('${elementos.length}', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w900))),
          if (elementos.isNotEmpty) ...[
            if (disponible == false)
              const HuecoDominio()
            else if (disponible == null)
              const Text('Calculando cuánto recordarías…', style: TextStyle(color: kMuted, fontSize: 12.5))
            else
              SenalDominio(d: dominio, soloMapas: elementos.every((e) => e.tipo == TipoElemento.mapa)),
            const SizedBox(height: 14),
            for (final e in elementos)
              FilaElemento(
                e: e,
                onAbierto: _cargar,
                extra: e.tipo == TipoElemento.mapa
                    ? null
                    : LineaDominioGrupo(g: dominio?.grupos.where((g) => g.deckId == e.id).firstOrNull),
                acciones: [
                  TextButton.icon(
                    onPressed: () => _mover(e),
                    icon: const Icon(Icons.drive_file_move_outline, size: 18),
                    label: const Text('Mover'),
                    style: TextButton.styleFrom(foregroundColor: kMuted, visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
          ] else
            Column(children: [
              const Icon(Icons.folder_open_rounded, color: kMuted, size: 28),
              const SizedBox(height: 6),
              const Text('Esta carpeta se ha quedado vacía.', style: TextStyle(color: kMuted, fontSize: 13.5)),
              TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text('Volver a ${asig.nombreCorto}')),
            ]),
        ]),
      ),
    ];
  }
}
