import 'package:flutter/material.dart';

import '../../core/models/biblioteca.dart';
import '../../core/responsive/content_shell.dart';
import '../../core/services/carpetas.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'carpeta_biblioteca_screen.dart';
import 'sin_clasificar_screen.dart';
import 'widgets/biblioteca_ui.dart';
import 'widgets/datos_asignatura.dart';

/// Una asignatura de la Biblioteca: «General» y SOLO los temas en los que el usuario tiene material.
/// Cada carpeta enseña dos cosas separadas: sus preguntas MIR (cuántas y tu acierto) y tu material, con
/// la señal de dominio en su propio color. Puerto de BibliotecaAsignatura.tsx de la web.
class AsignaturaBibliotecaScreen extends StatefulWidget {
  /// La del catálogo, para pintar la cabecera mientras llegan los datos.
  final AsignaturaCatalogo asignatura;
  const AsignaturaBibliotecaScreen({super.key, required this.asignatura});

  @override
  State<AsignaturaBibliotecaScreen> createState() => _AsignaturaBibliotecaScreenState();
}

class _AsignaturaBibliotecaScreenState extends State<AsignaturaBibliotecaScreen> {
  late final CargaAsignatura _c = CargaAsignatura(widget.asignatura.id);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() => _c.cargar(context, () {
        if (mounted) setState(() {});
      });

  Future<void> _abrirCarpeta(CarpetaBiblioteca carpeta) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CarpetaBibliotecaScreen(asignatura: _c.datos?.asignatura ?? widget.asignatura, topicId: carpeta.topicId),
    ));
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final datos = _c.datos;
    final asig = datos?.asignatura ?? widget.asignatura;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(asig.nombreCorto, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
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
                  EstadoBiblioteca(_c.noExiste ? 'Esa asignatura no está en la Biblioteca.' : _c.error!, error: !_c.noExiste)
                else if (datos == null)
                  const EstadoBiblioteca('Cargando la asignatura…')
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
    final carpetas = carpetasDeAsignatura(asig, datos.elementos);
    final total = cuentaDe(datos.elementos);
    final general = _c.aciertoDe(null);
    final temasConMaterial = carpetas.where((c) => c.topicId != null).length;
    final ocultos = asig.temas.length - temasConMaterial;
    final medibles = carpetas.where((c) => c.cuenta.flashcards + c.cuenta.resumenes > 0).toList();
    final disponible = _c.dominioDisponible;

    return [
      StickerCard(
        depth: 6,
        radius: 24,
        texture: lomosArchivador(),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SiglaAsignatura(asignatura: asig, grande: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(asig.nombre, style: const TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15)),
                const SizedBox(height: 3),
                Text(
                  asig.subtitulo ??
                      (asig.temas.isNotEmpty ? '${asig.temas.length} temas en el catálogo' : 'Sus temas llegarán con su paquete de preguntas'),
                  style: const TextStyle(color: kMuted, fontSize: 13),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 22, runSpacing: 10, children: [
            _cifra('${datos.preguntasTotal}', 'preguntas MIR'),
            _cifra(
              general.acierto != null && general.respondidas > 0 ? '${general.acierto!.round()} %' : '—',
              'acierto',
              color: general.acierto != null && general.respondidas > 0 ? colorAcierto(general.acierto!) : kMuted,
            ),
            _cifra('${total.total}', 'de tu material'),
          ]),
        ]),
      ),
      const SizedBox(height: 22),
      const SectionLabel('Tus carpetas'),
      if (carpetas.isEmpty)
        StickerCard(
          depth: 4,
          radius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.folder_open_rounded, color: kMuted, size: 28),
            const SizedBox(height: 8),
            Text(
              'Aún no tienes material en ${asig.nombreCorto}. Cuando guardes aquí un mapa, un grupo de flashcards o de '
              'resúmenes, sus temas aparecerán en esta página, cada uno junto a sus preguntas MIR.',
              style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Ordenar lo que tienes sin clasificar',
              compact: true,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SinClasificarScreen())),
            ),
          ]),
        )
      else
        for (final c in carpetas) _tarjetaCarpeta(c, datos, disponible),
      if (ocultos > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            '$ocultos ${ocultos == 1 ? 'tema' : 'temas'} del catálogo sin material: no se enseñan hasta que archives algo en ellos (al guardar o con «Mover a…»).',
            style: const TextStyle(color: kMuted, fontSize: 12, height: 1.4),
          ),
        ),
      if (carpetas.isNotEmpty && disponible == false) ...[const SizedBox(height: 8), const HuecoDominio()],
      if (medibles.isNotEmpty && disponible == true)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${medibles.where((c) => estadoCarpeta(_c.dominio?.de(c.topicId)) == EstadoDominio.bien).length} de ${medibles.length} '
            '${medibles.length == 1 ? 'carpeta con flashcards o resúmenes está bien llevada' : 'carpetas con flashcards o resúmenes están bien llevadas'} '
            '(recordarías hoy al menos el ${porcentajeDe(umbralBienLlevado.dominio)} % y has visto el ${porcentajeDe(umbralBienLlevado.cobertura)} % '
            'o más). Los mapas no cuentan: no registran estudio.',
            style: const TextStyle(color: kMuted, fontSize: 12, height: 1.4),
          ),
        ),
    ];
  }

  Widget _cifra(String valor, String etiqueta, {Color color = kInk}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(valor, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
        Text(etiqueta, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ]);

  Widget _tarjetaCarpeta(CarpetaBiblioteca c, DatosAsignatura datos, bool? disponible) {
    final a = _c.aciertoDe(c.topicId);
    final general = c.topicId == null;
    return StickerCard(
      depth: 4,
      radius: 20,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      onTap: () => _abrirCarpeta(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(general ? Icons.folder_special_rounded : Icons.folder_rounded, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.nombre, style: const TextStyle(color: kInk, fontSize: 15, fontWeight: FontWeight.w900)),
              if (general) const Text('Lo que abarca varios temas de la asignatura', style: TextStyle(color: kMuted, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.arrow_forward_rounded, color: kInk, size: 20),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PREGUNTAS MIR${general ? ' · TODA' : ''}',
                  style: const TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              CifrasPreguntas(preguntas: datos.preguntasDe(c.topicId), acierto: a.acierto, respondidas: a.respondidas),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TU MATERIAL', style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              CifrasMaterial(cuenta: c.cuenta),
              if (disponible != false) ...[
                const SizedBox(height: 6),
                IndicadorDominio(d: _c.dominio?.de(c.topicId), cargando: disponible == null),
              ],
            ]),
          ),
        ]),
      ]),
    );
  }
}
