import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/build_info.dart';
import '../../core/models/reportes.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/services/reportes_api.dart';
import '../../core/theme/app_theme.dart';
import '../sticker/sticker.dart';

/// Botón de «reportar pregunta» para la cabecera de una pregunta, al lado de «guardar en mazo».
/// Autónomo: abre su propia ventana y se queda con la bandera rellena si ya se reportó en esta sesión.
/// Puerto de src/components/report/ReportButton.tsx de la web.
class ReportButton extends StatelessWidget {
  final int? questionId;
  final ContextoReporte contexto;
  final int optionCount;
  final String? subtitle;
  final Color color;
  final double size;

  const ReportButton({
    super.key,
    required this.questionId,
    required this.contexto,
    this.optionCount = 4,
    this.subtitle,
    this.color = AppColors.textSecondary,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final id = questionId;
    if (id == null || id <= 0) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Reportadas.instancia,
      builder: (context, _) {
        final reportada = Reportadas.instancia.contiene(claveContenido(id));
        return IconButton(
          onPressed: () => showReportSheet(
            context,
            questionId: id,
            contexto: contexto,
            optionCount: optionCount,
            subtitle: subtitle,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          tooltip: reportada ? 'Ya la reportaste' : 'Reportar pregunta',
          icon: Icon(
            reportada ? Icons.report_rounded : Icons.report_outlined,
            size: size,
            color: reportada ? AppColors.error : color,
          ),
        );
      },
    );
  }
}

/// Abre la ventana de reporte (hoja en móvil, diálogo en tablet). Necesita un [ReportesApi] en el árbol.
Future<void> showReportSheet(
  BuildContext context, {
  required int questionId,
  required ContextoReporte contexto,
  int optionCount = 4,
  String? subtitle,
}) {
  final api = context.read<ReportesApi>();
  return showAdaptiveModal<void>(
    context: context,
    dialogScrollable: false,
    builder: (_) => ReportSheet(
      api: api,
      questionId: questionId,
      contexto: contexto,
      optionCount: optionCount,
      subtitle: subtitle,
    ),
  );
}

const _letras = ['A', 'B', 'C', 'D', 'E'];

const _iconos = <String, IconData>{
  'rule': Icons.rule_rounded,
  'menu_book': Icons.menu_book_rounded,
  'spellcheck': Icons.spellcheck_rounded,
  'hide_image': Icons.hide_image_outlined,
  'update': Icons.update_rounded,
  'content_copy': Icons.content_copy_rounded,
  'more_horiz': Icons.more_horiz_rounded,
};

/// La ventana: un toque para el tipo y, si quiere, una línea más. Lo demás (foto de la pregunta, de
/// dónde viene, qué respondió, versión) lo adjunta el sistema. No enseña nada de la respuesta correcta.
class ReportSheet extends StatefulWidget {
  final ReportesApi api;
  final int questionId;
  final ContextoReporte contexto;
  final int optionCount;
  final String? subtitle;

  const ReportSheet({
    super.key,
    required this.api,
    required this.questionId,
    required this.contexto,
    this.optionCount = 4,
    this.subtitle,
  });

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  late final List<CategoriaReporte> _categorias = categoriasVisibles(answered: widget.contexto.answered);
  final _texto = TextEditingController();
  String? _categoria;
  String? _sub;
  int? _sugerida;
  List<MiReporte> _mios = const [];
  bool _enviando = false;
  String? _error;
  bool? _actualizado;
  Timer? _cierre;

  @override
  void initState() {
    super.initState();
    _texto.addListener(() => setState(() {}));
    // Si ya lo había reportado, se precarga lo suyo para que edite en vez de repetir.
    widget.api.mios(widget.questionId).then((r) {
      if (!mounted || r.isEmpty) return;
      setState(() {
        _mios = r;
        final ultimo = r.first;
        if (_categorias.any((c) => c.key == ultimo.category)) _precargar(ultimo.category);
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _cierre?.cancel();
    _texto.dispose();
    super.dispose();
  }

  void _precargar(String key) {
    _categoria = key;
    MiReporte? previo;
    for (final m in _mios) {
      if (m.category == key) {
        previo = m;
        break;
      }
    }
    _sub = previo?.subcategory;
    _sugerida = previo?.suggestedAnswer;
    _texto.text = previo?.message ?? '';
  }

  Future<void> _enviar() async {
    final cat = _categoria;
    if (!puedeEnviarReporte(categoria: cat, mensaje: _texto.text, enviando: _enviando)) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final actualizado = await widget.api.enviar(
        questionId: widget.questionId,
        contexto: widget.contexto,
        categoria: cat!,
        subcategoria: _sub,
        sugerida: _sugerida,
        mensaje: _texto.text,
        appVersion: BuildInfo.label,
        userAgent: 'MIRDaily app (${defaultTargetPlatform.name})',
      );
      if (!mounted) return;
      setState(() => _actualizado = actualizado);
      _cierre = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ReporteException ? e.message : 'No se pudo enviar el reporte');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: SafeArea(
        top: false,
        child: _actualizado != null ? _hecho() : _formulario(),
      ),
    );
  }

  Widget _hecho() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(3),
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            _actualizado! ? 'Reporte actualizado' : '¡Gracias por avisar!',
            style: const TextStyle(color: kInk, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Lo revisamos y te avisaremos cuando esté resuelto. Si tenías razón, te llevas XP.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          GhostButton(label: 'Cerrar', onPressed: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }

  Widget _formulario() {
    CategoriaReporte? def;
    for (final c in _categorias) {
      if (c.key == _categoria) def = c;
    }
    final obligatorio = _categoria == 'otro';
    final puede = puedeEnviarReporte(categoria: _categoria, mensaje: _texto.text, enviando: _enviando);
    final editando = _categoria != null && _mios.any((m) => m.category == _categoria);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabecera coral, como la de la web.
        Container(
          color: tinted(AppColors.error, 0.14),
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kInk, width: 2),
              ),
              child: const Icon(Icons.report_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reportar pregunta', style: TextStyle(color: kInk, fontSize: 18, fontWeight: FontWeight.w900)),
                if (widget.subtitle != null)
                  Text(widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFA0524A), fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: kMuted),
            ),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_mios.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
                    child: Text(textoYaReportado(_mios), style: const TextStyle(color: kMuted, fontSize: 12.5)),
                  ),
                  const SizedBox(height: 14),
                ],
                const _Rotulo('¿Qué pasa?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _categorias)
                      _Ficha(
                        texto: c.label,
                        icono: _iconos[c.icon],
                        activa: c.key == _categoria,
                        coral: true,
                        onTap: () => setState(() {
                          _error = null;
                          _precargar(c.key);
                        }),
                      ),
                  ],
                ),
                if (!widget.contexto.answered)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Responde primero si lo que falla es la respuesta o la explicación.',
                      style: TextStyle(color: kMuted, fontSize: 11.5),
                    ),
                  ),
                if (_categoria == 'respuesta_erronea') ...[
                  const SizedBox(height: 16),
                  const _Rotulo('¿Cuál crees que es la correcta? (opcional)'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < widget.optionCount.clamp(2, 5); i++)
                      _Ficha(
                        texto: _letras[i],
                        activa: _sugerida == i + 1,
                        onTap: () => setState(() => _sugerida = _sugerida == i + 1 ? null : i + 1),
                      ),
                  ]),
                ],
                if (_categoria == 'imagen') ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in subcategoriasImagen)
                      _Ficha(
                        texto: s.label,
                        activa: _sub == s.key,
                        onTap: () => setState(() => _sub = _sub == s.key ? null : s.key),
                      ),
                  ]),
                ],
                if (def != null) ...[
                  const SizedBox(height: 16),
                  _Rotulo(obligatorio ? def.prompt : '${def.prompt} (opcional)'),
                  InkInput(
                    controller: _texto,
                    maxLines: 3,
                    maxLength: maxMensajeReporte,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Pie fijo, fuera del scroll: con el texto abierto (y el teclado) «Enviar» sigue a la vista.
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: kHairline))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
              ],
              Row(children: [
                const Expanded(
                  child: Text(
                    'Adjuntamos la pregunta tal como la ves y tu respuesta.',
                    style: TextStyle(color: kMuted, fontSize: 11.5, height: 1.3),
                  ),
                ),
                const SizedBox(width: 12),
                Opacity(
                  opacity: puede ? 1 : 0.45,
                  child: StickerButton(
                    label: _enviando ? 'Enviando…' : (editando ? 'Actualizar' : 'Enviar'),
                    color: AppColors.error,
                    compact: true,
                    onPressed: puede ? _enviar : null,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Rotulo extends StatelessWidget {
  final String texto;
  const _Rotulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// Píldora seleccionable: coral para el tipo de error, tinta para el resto (como la web).
class _Ficha extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final bool activa;
  final bool coral;
  final VoidCallback onTap;

  const _Ficha({required this.texto, this.icono, required this.activa, this.coral = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fondo = activa ? (coral ? AppColors.error : kInk) : Colors.white;
    final tinta = activa ? Colors.white : kInk;
    return Semantics(
      button: true,
      selected: activa,
      child: Material(
        color: fondo,
        shape: StadiumBorder(side: BorderSide(color: activa ? fondo : kHairline, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icono != null) ...[Icon(icono, size: 16, color: tinta), const SizedBox(width: 6)],
              Flexible(
                child: Text(texto, style: TextStyle(color: tinta, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
