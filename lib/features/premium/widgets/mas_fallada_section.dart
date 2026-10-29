import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/progreso_semana.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/zoomable_image.dart';
import 'panel_charts.dart';
import 'panel_section.dart';

/// «Pregunta más fallada de la semana» (GET /api/stats/most-failed-week): la que más costó la semana
/// pasada. Eliges sin que se guarde, «Ver respuesta» descubre la correcta, lo que contestaste tú aquel
/// día y la explicación. Puerto de la tarjeta del dashboard de la web.
class MasFalladaSubsection extends StatefulWidget {
  const MasFalladaSubsection({super.key});

  @override
  State<MasFalladaSubsection> createState() => _MasFalladaSubsectionState();
}

class _MasFalladaSubsectionState extends State<MasFalladaSubsection> {
  MasFallada? _datos;
  bool _cargando = true;
  bool _error = false;
  int? _elegida;
  bool _revelada = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final d = await context.read<ApiService>().getMostFailedWeek();
      if (!mounted) return;
      setState(() {
        _datos = d;
        _cargando = false;
        _elegida = null;
        _revelada = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    final semana = fechaCorta(d?.weekStart);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelSectionHeader(
          title: 'La más fallada',
          subtitle: 'La pregunta que más costó la semana pasada.',
          trailing: semana == null
              ? null
              : Text('Semana\n$semana',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: PanelColors.muted, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.3)),
        ),
        const SizedBox(height: 14),
        if (_cargando)
          const PanelLoadingCard(height: 220)
        else if (_error)
          PanelErrorCard(onRetry: _cargar)
        else if (d == null)
          const PanelCard(
            child: Text('Aún no hay datos esta semana.', style: TextStyle(color: PanelColors.muted, fontSize: 13)),
          )
        else
          _tarjeta(d),
      ],
    );
  }

  Widget _tarjeta(MasFallada d) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.isPlaceholder) ...[
            const Row(children: [
              Icon(Icons.science_outlined, size: 16, color: PanelColors.gold),
              SizedBox(width: 6),
              Expanded(
                child: Text('Datos de ejemplo: aún no hay suficientes respuestas esta semana',
                    style: TextStyle(color: Color(0xFF9A7B2F), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          Text(d.statement,
              style: const TextStyle(color: PanelColors.ink, fontSize: 16, fontWeight: FontWeight.w600, height: 1.45)),
          if (d.hasImage && d.imageUrl != null) ...[
            const SizedBox(height: 12),
            ZoomableImage(url: d.imageUrl!, borderRadius: BorderRadius.circular(14)),
          ],
          const SizedBox(height: 12),
          if (!_revelada)
            const Text('¿La volverías a acertar hoy?',
                style: TextStyle(color: PanelColors.wrong, fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (var i = 0; i < d.options.length; i++) _opcion(d, i),
          const SizedBox(height: 6),
          if (!_revelada) ...[
            const Text('Tu selección aquí no se guardará. Solo es para volver a reflexionar.',
                style: TextStyle(color: PanelColors.muted, fontSize: 12)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _revelada = true),
                style: TextButton.styleFrom(
                  backgroundColor: PanelColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Ver respuesta', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ] else ...[
            Text(textoMasFallada(d),
                style: TextStyle(
                  color: d.respondidaBien ? const Color(0xFF5C7A59) : PanelColors.ink,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                )),
            if (!d.nuncaRespondida) ...[
              const SizedBox(height: 4),
              Text(
                d.respondidaMal
                    ? 'A veces las preguntas más falladas son las que más enseñan.'
                    : 'Consolidar estos aciertos es lo que marca diferencia en el MIR.',
                style: const TextStyle(color: PanelColors.muted, fontSize: 12.5),
              ),
            ],
            if (d.explanation != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: PanelColors.soft, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.school_rounded, size: 18, color: PanelColors.accent),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text('Claves para no fallarla',
                          style: TextStyle(color: PanelColors.ink, fontSize: 14, fontWeight: FontWeight.w900)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(d.explanation!, style: const TextStyle(color: PanelColors.muted, fontSize: 13, height: 1.5)),
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _opcion(MasFallada d, int i) {
    final letra = String.fromCharCode(65 + i);
    final esCorrecta = d.correctIndex == i;
    final esTuya = d.tuRespuesta == i;
    var fondo = Colors.white;
    var borde = const Color(0xFFF0EAE6);
    var texto = PanelColors.muted;
    String? insignia;
    if (!_revelada) {
      if (_elegida == i) {
        fondo = const Color(0xFFEDF3F8);
        borde = const Color(0xFF9CAFC4);
        texto = PanelColors.ink;
      }
    } else if (d.respondidaMal) {
      if (esTuya) {
        fondo = const Color(0xFFFBEDEC);
        borde = const Color(0xFFD78A82);
        texto = const Color(0xFF7D2F2A);
        insignia = 'Tu respuesta';
      }
      if (esCorrecta) {
        fondo = const Color(0xFFEEF3ED);
        borde = PanelColors.correct;
        texto = PanelColors.ink;
        insignia = 'Correcta';
      }
    } else {
      // Acertada, o no la hiciste: se marca la correcta (y si fue la tuya, lo dice).
      if (esCorrecta) {
        fondo = const Color(0xFFEEF3ED);
        borde = PanelColors.correct;
        texto = PanelColors.ink;
        insignia = esTuya ? 'Tu respuesta' : 'Correcta';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: fondo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borde, width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _revelada ? null : () => setState(() => _elegida = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFF5F1EE), borderRadius: BorderRadius.circular(8)),
                child: Text(letra, style: const TextStyle(color: PanelColors.ink, fontSize: 12, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(d.options[i], style: TextStyle(color: texto, fontSize: 13.5, height: 1.35))),
              if (insignia != null) ...[
                const SizedBox(width: 8),
                Text(insignia,
                    style: TextStyle(
                      color: insignia == 'Correcta' || d.respondidaBien ? const Color(0xFF5C7A59) : PanelColors.wrong,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    )),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
