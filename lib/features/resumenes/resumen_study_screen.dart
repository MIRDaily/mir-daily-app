import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/resumen.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import 'resumenes_api.dart';
import 'resumenes_filtro.dart';
import 'resumenes_grupo.dart';
import 'resumenes_huecos.dart';
import 'resumenes_logica.dart';
import 'widgets/parrafo_huecos.dart';

/// Estudio de un grupo de resúmenes activos: cada párrafo sale con sus huecos
/// tapados. Tocar destapa el siguiente; en cada hueco, «Lo sabía» / «No lo
/// sabía». Al acabar el párrafo se propone la nota (se puede cambiar) y se pasa
/// al siguiente. Al terminar, los párrafos fallados y cuándo vuelve cada uno.
///
/// Con los ajustes de la sesión (ajustes_estudio_resumen.dart): niveles que se tapan, temas, qué
/// párrafos y cuántos, «Escribir la respuesta» y cajas del mismo ancho. Con un hueco destapado,
/// deslizar a la derecha es «Lo sabía» y a la izquierda «No lo sabía».
class ResumenStudyScreen extends StatefulWidget {
  final String grupoId;
  final String grupoName;
  final AjustesResumen ajustes;

  /// Todos los temas del grupo (para no mandar el filtro de temas si van todos).
  final List<String> todosLosTemas;

  const ResumenStudyScreen({
    super.key,
    required this.grupoId,
    required this.grupoName,
    this.ajustes = const AjustesResumen(),
    this.todosLosTemas = const [],
  });

  @override
  State<ResumenStudyScreen> createState() => _ResumenEstudioScreenState();
}

enum _FinEstudio { fin, caducada, limite }

Color _colorNota(int n) {
  switch (n) {
    case 1:
      return const Color(0xFFB04A5E);
    case 2:
      return const Color(0xFFB07A1E);
    case 3:
      return const Color(0xFF5E8C5A);
    default:
      return const Color(0xFF3F7EA6);
  }
}

class _Hecho {
  final int tapados;
  final int fallos;
  final int grade;
  const _Hecho(this.tapados, this.fallos, this.grade);
}

/// Botón de respuesta del estudio: fondo y texto configurables, con borde de tinta.
class _RespuestaButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onPressed;

  const _RespuestaButton({required this.label, required this.icon, required this.bg, required this.fg, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: kInk, width: 2), boxShadow: inkShadow(4)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 14))),
          ],
        ),
      ),
    );
  }
}

class _ResumenEstudioScreenState extends State<ResumenStudyScreen> {
  String? _sesion;
  Parrafo? _parrafo;
  EstadoParrafo? _estado;
  int? _destapado;
  int? _nota;
  _FinEstudio? _fin;
  List<ParrafoFallado>? _falladosFin;
  String? _error;
  bool _ocupado = false;

  int _hechos = 0;
  int _sabidos = 0;
  int _falladosTotal = 0;
  final Map<int, int> _notas = {};
  final List<_Hecho> _pila = [];
  DateTime? _desde;

  /// Lo que se pidió al servidor (para «Repasar ahora» con los mismos niveles).
  AjustesEstudio _peticion = const AjustesEstudio();

  /// Modo escribir: lo escrito en cada hueco del párrafo y cómo se compara con lo tapado.
  final Map<int, ({String texto, Comparacion c})> _escritos = {};

  /// Arrastre en curso sobre la tarjeta (para deslizar y contestar).
  Offset _arrastre = Offset.zero;

  List<int> get _niveles => widget.ajustes.niveles;

  ResumenesApi get _api => context.read<ResumenesApi>();

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  Future<void> _arrancar([List<int>? soloItemIds]) async {
    setState(() {
      _error = null;
      _fin = null;
      _falladosFin = null;
      _hechos = 0;
      _sabidos = 0;
      _falladosTotal = 0;
      _notas.clear();
      _pila.clear();
      _parrafo = null;
      _estado = null;
      _destapado = null;
      _nota = null;
    });
    try {
      final base = aPeticion(widget.ajustes, widget.todosLosTemas);
      _peticion = soloItemIds != null ? repasarAhora(base, soloItemIds) : base;
      final s = await _api.empezarSesion(widget.grupoId, _peticion);
      if (!mounted) return;
      setState(() => _sesion = s);
      await _cargarSiguiente(s);
    } on ResumenesApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo empezar la sesión.');
    }
  }

  Future<void> _cargarSiguiente(String s) async {
    setState(() => _ocupado = true);
    try {
      final r = await _api.siguiente(widget.grupoId, s);
      if (!mounted) return;
      if (r.tipo == SiguienteTipoResumen.parrafo) {
        _mostrar(r.parrafo!);
      } else {
        await _terminar(s, r.tipo == SiguienteTipoResumen.caducada
            ? _FinEstudio.caducada
            : r.tipo == SiguienteTipoResumen.limite
                ? _FinEstudio.limite
                : _FinEstudio.fin);
      }
    } on ResumenesApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el siguiente párrafo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _mostrar(Parrafo p) {
    setState(() {
      _parrafo = p;
      // Con «solo huecos fallados» se tapan solo esos (de los niveles elegidos).
      _estado = empezarParrafo(p.huecos, _niveles, _peticion.soloHuecosFallados == true ? p.huecosFallados : null);
      _destapado = null;
      _escritos.clear();
      _nota = null;
      _desde = DateTime.now();
    });
  }

  Future<void> _terminar(String s, _FinEstudio tipo) async {
    setState(() {
      _parrafo = null;
      _fin = tipo;
      _falladosFin = null;
    });
    try {
      final fallados = await _api.terminarSesion(widget.grupoId, s);
      if (mounted) setState(() => _falladosFin = fallados);
    } catch (_) {
      if (mounted) setState(() => _falladosFin = const []);
    }
  }

  Future<void> _destapar(int k) async {
    if (_destapado != null) return;
    if (widget.ajustes.escribir && !_escritos.containsKey(k)) {
      final p = _parrafo!;
      final escrito = await _pedirRespuesta(p.huecos[k].n);
      if (escrito == null || !mounted || _parrafo != p) return;
      final correcta = p.texto.substring(p.huecos[k].i, p.huecos[k].f);
      setState(() => _escritos[k] = (texto: escrito, c: compararRespuesta(escrito, correcta)));
    }
    setState(() => _destapado = k);
    final p = _parrafo!;
    SemanticsService.sendAnnouncement(View.of(context), 'Destapado: ${p.texto.substring(p.huecos[k].i, p.huecos[k].f)}. ¿Lo sabías?', TextDirection.ltr);
  }

  /// Modo escribir: lo que el usuario cree que va en el hueco (null si cancela).
  Future<String?> _pedirRespuesta(int nivel) =>
      showDialog<String>(context: context, builder: (_) => _EscribirRespuesta(nivel: nivel));

  void _destaparSiguiente() {
    final k = siguienteTapado(_estado!);
    if (k != null) _destapar(k);
  }

  void _contestar(Respuesta r) {
    if (_destapado == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _estado = responder(_estado!, _destapado!, r);
      _destapado = null;
      _nota = null;
    });
  }

  void _corregir(int k) {
    if (_destapado != null) return;
    setState(() {
      _estado = cambiarRespuesta(_estado!, k);
      _nota = null;
    });
  }

  Future<void> _pasar() async {
    if (_parrafo == null || _estado == null || _sesion == null || !terminado(_estado!) || _ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final e = _estado!;
      final fallosN = fallos(e);
      if (e.tapados.isNotEmpty) {
        final r = await _api.registrarRepaso(
          widget.grupoId,
          sessionId: _sesion!,
          deckItemId: _parrafo!.itemId,
          huecos: resultados(e, _parrafo!.huecos),
          grade: (_nota != null && _nota != notaDeRepaso(fallosN)) ? _nota : null,
          timeSpent: _desde == null ? 0 : DateTime.now().difference(_desde!).inSeconds,
        );
        setState(() {
          _hechos += 1;
          _sabidos += e.tapados.length - fallosN;
          _falladosTotal += fallosN;
          _notas[r.grade] = (_notas[r.grade] ?? 0) + 1;
          _pila.add(_Hecho(e.tapados.length, fallosN, r.grade));
        });
      }
      setState(() => _ocupado = false);
      await _cargarSiguiente(_sesion!);
    } on ResumenesApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _ocupado = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo registrar el repaso.';
          _ocupado = false;
        });
      }
    }
  }

  Future<void> _deshacer() async {
    if (_sesion == null || _ocupado || _pila.isEmpty) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final r = await _api.deshacerRepaso(widget.grupoId, _sesion!);
      final u = _pila.removeLast();
      setState(() {
        _hechos = math.max(0, _hechos - 1);
        _sabidos = math.max(0, _sabidos - (u.tapados - u.fallos));
        _falladosTotal = math.max(0, _falladosTotal - u.fallos);
        _notas[u.grade] = math.max(0, (_notas[u.grade] ?? 0) - 1);
        _fin = null;
        _falladosFin = null;
      });
      if (r.parrafo != null) {
        _mostrar(r.parrafo!);
      } else {
        setState(() => _ocupado = false);
        await _cargarSiguiente(_sesion!);
      }
    } on ResumenesApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _ocupado = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo deshacer el repaso.';
          _ocupado = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.grupoName, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    if (_error != null && _parrafo == null && _fin == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver al grupo')),
          ]),
        ),
      );
    }
    if (_fin != null) return _pantallaFin();
    if (_parrafo == null || _estado == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return _pantallaEstudio();
  }

  Widget _pantallaEstudio() {
    final p = _parrafo!;
    final e = _estado!;
    final listo = terminado(e);
    final fallosN = fallos(e);
    final propuesta = notaDeRepaso(fallosN);
    final pendientes = e.tapados.where((k) => !e.respuestas.containsKey(k)).length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: kInk, width: 2)),
                      child: Text(p.tema?.isNotEmpty == true ? p.tema! : 'Sin tema', style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$_hechos hechos · ${e.tapados.length} ${e.tapados.length == 1 ? 'hueco tapado' : 'huecos tapados'}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _pila.isEmpty || _ocupado ? null : _deshacer,
                      child: const Text('Deshacer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    // Con un hueco destapado: deslizar a la derecha = «Lo sabía», a la izquierda = «No lo sabía».
                    onHorizontalDragStart: _destapado == null ? null : (_) => _arrastre = Offset.zero,
                    onHorizontalDragUpdate: _destapado == null ? null : (d) => setState(() => _arrastre += d.delta),
                    onHorizontalDragEnd: _destapado == null
                        ? null
                        : (_) {
                            final r = respuestaDeslizar(_arrastre.dx, _arrastre.dy, c.maxWidth);
                            setState(() => _arrastre = Offset.zero);
                            if (r != null) _contestar(r);
                          },
                    child: Transform.translate(
                      offset: Offset(_destapado == null ? 0 : _arrastre.dx.clamp(-120.0, 120.0) * 0.5, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _arrastre.dx.abs() < 24 ? kInk : (_arrastre.dx > 0 ? kVerdeOk : kRojoKo),
                            width: 2,
                          ),
                          boxShadow: inkShadow(5),
                        ),
                        child: _textoEstudio(p, e),
                      ),
                    ),
                  ),
                ),
                if (_destapado != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Desliza la tarjeta: a la derecha «Lo sabía», a la izquierda «No lo sabía».',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kGrisAA, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: const BoxDecoration(color: AppColors.background, border: Border(top: BorderSide(color: kHairline))),
          child: _acciones(e, listo, fallosN, propuesta, pendientes),
        ),
      ],
    );
  }

  Widget _textoEstudio(Parrafo p, EstadoParrafo e) {
    final segs = segmentos(p.texto, p.huecos);
    final children = <InlineSpan>[];
    for (final s in segs) {
      if (s.k == null) {
        children.add(TextSpan(text: s.t));
        continue;
      }
      final k = s.k!;
      final h = p.huecos[k];
      final info = nivelInfoResumen[h.n]!;
      if (!e.tapados.contains(k)) {
        children.add(TextSpan(
          text: s.t,
          semanticsLabel: etiquetaHueco(EstadoHueco.visible, h.n, s.t),
          style: TextStyle(color: kInk, decoration: TextDecoration.underline, decorationColor: info.color, decorationThickness: 2),
        ));
        continue;
      }
      final r = e.respuestas[k];
      if (r != null) {
        final color = r == Respuesta.sabia ? kVerdeOk : kRojoKo;
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Semantics(
            button: true,
            label: etiquetaHueco(r == Respuesta.sabia ? EstadoHueco.sabia : EstadoHueco.no, h.n, s.t),
            excludeSemantics: true,
            child: GestureDetector(
            onTap: () => _corregir(k),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.t, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
                  Icon(r == Respuesta.sabia ? Icons.check_rounded : Icons.close_rounded, size: 15, color: color),
                ],
              ),
            ),
          ),
          ),
        ));
        continue;
      }
      if (_destapado == k) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Semantics(
            label: etiquetaHueco(EstadoHueco.destapado, h.n, s.t),
            excludeSemantics: true,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(color: info.soft, borderRadius: BorderRadius.circular(4), border: Border(bottom: BorderSide(color: info.color, width: 2))),
              child: Text(s.t, style: TextStyle(color: kTintaNivel[h.n], fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ));
        continue;
      }
      final esSiguiente = siguienteTapado(e) == k && _destapado == null;
      // Sin «cajas del mismo ancho», la caja crece con la respuesta (como en la web).
      final ancho = widget.ajustes.anchoFijo ? 72.0 : (s.t.length * 8.5).clamp(36.0, 220.0);
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Semantics(
          button: true,
          label: etiquetaHueco(EstadoHueco.tapado, h.n, '', escribir: widget.ajustes.escribir),
          excludeSemantics: true,
          child: GestureDetector(
          onTap: () => _destapar(k),
          child: Container(
            width: ancho,
            height: 20,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
            decoration: BoxDecoration(
              color: info.soft,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: esSiguiente ? kInk : info.color, width: 2),
              boxShadow: esSiguiente ? const [BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0)] : null,
            ),
            // Quien no distingue los colores lee el nivel.
            child: Text(kNivelCorto[h.n]!, style: TextStyle(color: kTintaNivel[h.n], fontSize: 9.5, fontWeight: FontWeight.w900, height: 1)),
          ),
        ),
        ),
      ));
    }
    return Text.rich(TextSpan(children: children), style: const TextStyle(fontSize: 16, height: 2.1, color: kInk));
  }

  Widget _acciones(EstadoParrafo e, bool listo, int fallosN, int propuesta, int pendientes) {
    if (_destapado != null) {
      final escrito = _escritos[_destapado!];
      // Con lo escrito se PROPONE una respuesta (resaltada); el usuario manda.
      final propuestaSi = escrito == null ? null : propuestaSabia(escrito.c);
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (escrito != null) ...[
          Text.rich(
            TextSpan(style: const TextStyle(color: kInk, fontSize: 13.5), children: [
              const TextSpan(text: 'Escribiste: '),
              TextSpan(text: escrito.texto.trim().isEmpty ? '(nada)' : escrito.texto.trim(), style: const TextStyle(fontWeight: FontWeight.w900)),
              TextSpan(
                text: switch (escrito.c) {
                  Comparacion.igual => ' · coincide',
                  Comparacion.casi => ' · casi (una letra)',
                  Comparacion.distinta => ' · no coincide',
                  Comparacion.vacia => '',
                },
                style: TextStyle(color: propuestaSi == true ? kVerdeOk : kRojoKo, fontWeight: FontWeight.w800),
              ),
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: _RespuestaButton(
                label: 'No lo sabía',
                icon: Icons.close_rounded,
                bg: propuestaSi == false ? kRojoKo : Colors.white,
                fg: propuestaSi == false ? Colors.white : kRojoKo,
                onPressed: () => _contestar(Respuesta.no),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _RespuestaButton(
                label: 'Lo sabía',
                icon: Icons.check_rounded,
                bg: propuestaSi == false ? Colors.white : kVerdeOk,
                fg: propuestaSi == false ? kVerdeOk : Colors.white,
                onPressed: () => _contestar(Respuesta.sabia),
              ),
            ),
          ],
        ),
      ]);
    }

    if (!listo) {
      final escribir = widget.ajustes.escribir;
      return StickerButton(
        label: escribir
            ? (pendientes > 1 ? 'Escribir (quedan $pendientes)' : 'Escribir el último')
            : (pendientes > 1 ? 'Destapar (quedan $pendientes)' : 'Destapar el último'),
        icon: escribir ? Icons.edit_rounded : Icons.visibility_rounded,
        expand: true,
        onPressed: _destaparSiguiente,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fallosN == 0 ? 'Todos bien' : fallosN == 1 ? 'Un fallo' : '$fallosN fallos',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in [1, 2, 3, 4])
              GestureDetector(
                onTap: () => setState(() => _nota = n),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_nota ?? propuesta) == n ? _colorNota(n) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (_nota ?? propuesta) == n ? kInk : _colorNota(n), width: 2),
                    boxShadow: (_nota ?? propuesta) == n ? const [BoxShadow(color: kInk, offset: Offset(2, 2), blurRadius: 0)] : null,
                  ),
                  child: Text(
                    nombreNotaResumen[n]!,
                    style: TextStyle(color: (_nota ?? propuesta) == n ? Colors.white : _colorNota(n), fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        StickerButton(
          label: _ocupado ? 'Guardando…' : 'Siguiente',
          icon: Icons.arrow_forward_rounded,
          color: kInk,
          expand: true,
          onPressed: _ocupado ? null : _pasar,
        ),
      ],
    );
  }

  Widget _pantallaFin() {
    final siguen = (_falladosFin ?? const <ParrafoFallado>[]).where((p) => (p.parrafo.huecosFallados?.length ?? 0) > 0).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Center(
          child: Column(
            children: [
              Icon(_fin == _FinEstudio.fin ? Icons.celebration_rounded : Icons.schedule_rounded, size: 44, color: _colorNota(3)),
              const SizedBox(height: 4),
              Text(
                _fin == _FinEstudio.fin
                    ? 'Sesión terminada'
                    : _fin == _FinEstudio.caducada
                        ? 'La sesión ha caducado'
                        : 'Has llegado al límite de la sesión',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                '$_hechos ${_hechos == 1 ? 'párrafo repasado' : 'párrafos repasados'} · $_sabidos huecos sabidos · $_falladosTotal por repasar',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in [1, 2, 3, 4])
                    if ((_notas[n] ?? 0) > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: _colorNota(n), borderRadius: BorderRadius.circular(8)),
                        child: Text('${_notas[n]} ${nombreNotaResumen[n]}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_falladosFin == null)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Buscando los huecos fallados…', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))))
        else if (_falladosFin!.isEmpty && _hechos > 0)
          Center(child: Text('Ningún hueco fallado en esta sesión.', style: TextStyle(color: _colorNota(3), fontWeight: FontWeight.w700, fontSize: 14)))
        else
          for (final f in _falladosFin!)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StickerCard(
                depth: 3,
                radius: 16,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: kInk, width: 1.5)),
                          child: Text(f.parrafo.tema?.isNotEmpty == true ? f.parrafo.tema! : 'Sin tema', style: const TextStyle(color: kInk, fontSize: 11, fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (f.parrafo.huecosFallados?.length ?? 0) > 0
                                ? (f.parrafo.huecosFallados!.length == 1 ? 'Sigue fallado 1 hueco' : 'Siguen fallados ${f.parrafo.huecosFallados!.length} huecos')
                                : 'Recuperado al repetirlo',
                            style: TextStyle(
                              color: (f.parrafo.huecosFallados?.length ?? 0) > 0 ? _colorNota(1) : _colorNota(3),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text('Vuelve ${cuandoVuelve(f.parrafo.nextDueAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ParrafoHuecos(texto: f.parrafo.texto, huecos: f.parrafo.huecos),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 16),
        if (_pila.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GhostButton(label: 'Deshacer el último', icon: Icons.undo_rounded, expand: true, onPressed: _ocupado ? null : _deshacer),
          ),
        if (siguen.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StickerButton(
              label: siguen.length == 1 ? 'Repasar ahora el fallado' : 'Repasar ahora los ${siguen.length} fallados',
              icon: Icons.replay_rounded,
              color: _colorNota(1),
              expand: true,
              onPressed: () => _arrancar(siguen.map((p) => p.parrafo.itemId).toList()),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: StickerButton(label: 'Repasar otra vez', icon: Icons.refresh_rounded, expand: true, onPressed: () => _arrancar()),
        ),
        GhostButton(label: 'Volver al grupo', icon: Icons.arrow_back_rounded, expand: true, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// El diálogo de «Escribir la respuesta». Tiene su propio estado para que el campo se libere cuando
/// el diálogo termina de cerrarse, no antes.
class _EscribirRespuesta extends StatefulWidget {
  final int nivel;

  const _EscribirRespuesta({required this.nivel});

  @override
  State<_EscribirRespuesta> createState() => _EscribirRespuestaState();
}

class _EscribirRespuestaState extends State<_EscribirRespuesta> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('¿Qué va aquí? (${nivelInfoResumen[widget.nivel]!.nombre.toLowerCase()})'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Escribe la respuesta'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('No lo sé')),
        TextButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Comprobar')),
      ],
    );
  }
}
