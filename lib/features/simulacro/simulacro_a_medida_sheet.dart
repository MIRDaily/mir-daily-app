import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/simulacro_a_medida.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import 'simulacro_screen.dart';

/// Lo que se decide en la hoja: empezar la tanda con un modo, o ir al creador normal.
sealed class _Eleccion {
  const _Eleccion();
}

class _Empezar extends _Eleccion {
  final PlanAMedida plan;
  final String mode;
  const _Empezar(this.plan, this.mode);
}

class _CreadorNormal extends _Eleccion {
  const _CreadorNormal();
}

/// «Simulacro a tu medida» (tarjeta de Studio). Pide la tanda al abrir, enseña qué entra y el modo de
/// corrección, y al empezar pasa EXACTAMENTE esas preguntas al runner (no se vuelve a sortear). Antes de
/// arrancar sale el mismo «Antes de empezar» (clásico o deslizar) que en el creador normal.
/// Puerto de SmartSimulacroModal.tsx de la web.
Future<void> abrirSimulacroAMedida(BuildContext context) async {
  final api = context.read<ApiService>();
  final navigator = Navigator.of(context);
  final eleccion = await showAdaptiveModal<_Eleccion>(
    context: context,
    dialogScrollable: false,
    dialogMaxWidth: 520,
    builder: (_) => SimulacroAMedidaSheet(api: api),
  );
  if (eleccion == null || !context.mounted) return;
  switch (eleccion) {
    case _CreadorNormal():
      navigator.push(MaterialPageRoute(builder: (_) => const SimulacroScreen()));
    case _Empezar(:final plan, :final mode):
      final diseno = await showDialog<(String, bool)>(
        context: context,
        builder: (_) => const SimLayoutPickerDialog(),
      );
      if (diseno == null) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => SimulacroScreen(
          aMedida: SimAMedida(questions: plan.questions, mode: mode, layout: diseno.$1, showSubject: diseno.$2),
        ),
      ));
  }
}

class SimulacroAMedidaSheet extends StatefulWidget {
  final ApiService api;
  const SimulacroAMedidaSheet({super.key, required this.api});

  @override
  State<SimulacroAMedidaSheet> createState() => _SimulacroAMedidaSheetState();
}

class _SimulacroAMedidaSheetState extends State<SimulacroAMedidaSheet> {
  PlanAMedida? _plan;
  String? _error;

  /// Primero la que imita al examen real, como en el creador.
  String _mode = 'deferred';
  int _intento = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final yo = ++_intento;
    setState(() {
      _plan = null;
      _error = null;
    });
    try {
      final p = await widget.api.getSimulacroAMedida();
      if (mounted && yo == _intento) setState(() => _plan = p);
    } catch (e) {
      if (mounted && yo == _intento) {
        setState(() => _error = e is ApiException ? e.message : 'No se pudo generar tu simulacro a medida.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final cargando = plan == null && _error == null;
    final insuficiente = plan != null && plan.insuficiente;
    final subtitulo = cargando
        ? 'Buscando dónde flojeas…'
        : insuficiente
            ? 'Aún sin datos suficientes de tus fallos.'
            : plan != null
                ? '${plan.questions.length} preguntas centradas en donde peor vas ahora mismo.'
                : 'No se pudo generar.';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const DocChip(label: 'A tu medida', icon: Icons.track_changes_rounded, tone: DocTone.accent),
                    const SizedBox(height: 8),
                    const Text('Simulacro a tu medida',
                        style: TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: const TextStyle(color: kMuted, fontSize: 13)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: kMuted),
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: cargando
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Column(children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 14),
                          Text('Buscando dónde flojeas y armando la tanda…',
                              textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 13)),
                        ]),
                      )
                    : _error != null
                        ? _fallo()
                        : insuficiente
                            ? _sinDatos()
                            : _contenido(plan!),
              ),
            ),
            if (plan != null && !insuficiente)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                child: StickerButton(
                  label: 'Empezar',
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  onPressed: () => Navigator.pop(context, _Empezar(plan, _mode)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallo() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
        const SizedBox(height: 8),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error, fontSize: 14)),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
          GhostButton(label: 'Reintentar', icon: Icons.refresh_rounded, compact: true, onPressed: _cargar),
          StickerButton(
            label: 'Ir al creador normal',
            compact: true,
            onPressed: () => Navigator.pop(context, const _CreadorNormal()),
          ),
        ]),
      ]);

  Widget _sinDatos() => Column(children: [
        const SizedBox(height: 6),
        const Icon(Icons.track_changes_rounded, color: AppColors.primary, size: 40),
        const SizedBox(height: 10),
        const Text('Todavía no te conocemos lo suficiente',
            textAlign: TextAlign.center, style: TextStyle(color: kInk, fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text(
          'Aún no tenemos suficientes datos de tus fallos para armar un simulacro centrado en ellos. '
          'Responde unas cuantas preguntas más —el Daily, un simulacro normal, tus mazos— y vuelve.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted, fontSize: 13.5, height: 1.45),
        ),
        const SizedBox(height: 16),
        StickerButton(
          label: 'Crear un simulacro normal',
          icon: Icons.tune_rounded,
          onPressed: () => Navigator.pop(context, const _CreadorNormal()),
        ),
        const SizedBox(height: 8),
      ]);

  Widget _contenido(PlanAMedida plan) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Qué entra'),
          // Debajo y no junto al rótulo: a 360 px no caben los dos en una fila.
          if (plan.coverage == CoberturaAMedida.mixed)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DocChip(label: 'Completado con asignaturas flojas', tone: DocTone.neutral),
              ),
            ),
          for (final row in plan.composition)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kHairline, width: 1.5),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(row.subjectName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kInk, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Text('${row.count}', style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w900)),
              ]),
            ),
          const SizedBox(height: 12),
          const SectionLabel('Modo de corrección'),
          _opcionModo('deferred', Icons.flag_rounded, 'Corrección al final', 'Sin pistas durante el test; repasas todo al terminar.'),
          const SizedBox(height: 8),
          _opcionModo('immediate', Icons.bolt_rounded, 'Corrección inmediata', 'Ves si aciertas y la explicación justo al responder.'),
        ],
      );

  Widget _opcionModo(String valor, IconData icono, String titulo, String descripcion) {
    final activa = _mode == valor;
    return Semantics(
      button: true,
      selected: activa,
      child: GestureDetector(
        onTap: () => setState(() => _mode = valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: activa ? const Color(0xFFFFF0EC) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: activa ? kInk : kHairline, width: 2),
            boxShadow: activa ? inkShadow(3) : const [],
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: activa ? AppColors.primary : const Color(0xFFF2EFED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: activa ? Colors.white : kMuted, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(descripcion, style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.35)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
