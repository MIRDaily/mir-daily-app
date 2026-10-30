// Un mapa mental: verlo y la edición simple (texto, ramas y mover). La lógica está en
// core/models/mapas.dart; el editor completo (estilos, tablas, IA, modo estudio) sigue en la web.
//
// - El lienzo se mueve con el dedo y se amplía pellizcando. Al abrir, el mapa entero cabe.
// - Tocar un nodo lo selecciona; abajo sale su barra: editar el texto, añadir una rama, borrarla.
//   Un nodo SELECCIONADO se arrastra para moverlo (con toda su rama); sin seleccionar, arrastrar
//   mueve el lienzo. Así mover un nodo no se confunde con desplazarse por el mapa.
// - Las ramas plegadas en la web salen plegadas, con un «+N» para desplegarlas aquí (eso no se
//   guarda: es solo para mirar).
// - Se guarda solo, al poco de cada cambio, «sin pisar» (ver MapasApi.guardar). Si la web guardó
//   entre medias, se pregunta con qué quedarse.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/mapas.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/services/haptics_service.dart';
import '../../core/services/mapas_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';

enum _Guardado { guardado, pendiente, guardando, error }

const double _margen = 160;
const double _aire = 22;
const Duration _esperaGuardado = Duration(milliseconds: 1500);

class MapaScreen extends StatefulWidget {
  final String mapaId;

  /// Título para la barra mientras carga.
  final String? titulo;

  const MapaScreen({super.key, required this.mapaId, this.titulo});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  late final MapasApi _api = context.read<MapasApi>();
  MapaGuardado? _mapa;
  DocMapa? _doc;
  String _titulo = '';
  String _marca = '';
  String? _error;
  bool _cargando = true;

  String? _seleccion;
  final Map<String, bool> _plegado = {};
  final List<String> _deshacer = [];

  _Guardado _estado = _Guardado.guardado;
  bool _docSucio = false;
  bool _tituloSucio = false;
  Timer? _timer;
  bool _guardandoAhora = false;

  final TransformationController _vista = TransformationController();
  bool _encuadrado = false;
  final Map<String, Size> _tamanos = {};

  /// «Ordenar»: el mapa recolocado en árbol con los tamaños de la app, solo para mirar. Al editar
  /// sobre él, esas posiciones pasan al mapa (y se guardan con la edición).
  bool _ordenar = false;
  Map<String, Offset> _posOrdenadas = const {};

  @override
  void initState() {
    super.initState();
    _titulo = widget.titulo ?? '';
    _cargar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Lo pendiente se manda al salir, sin esperar (como la web al cerrar el editor).
    if (_docSucio || _tituloSucio) unawaited(_guardar(silencioso: true));
    _vista.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final m = await _api.abrir(widget.mapaId);
      if (!mounted) return;
      if (m == null) {
        setState(() {
          _cargando = false;
          _error = 'Este mapa ya no existe o está en la papelera.';
        });
        return;
      }
      setState(() {
        _mapa = m;
        _doc = m.doc;
        _titulo = m.titulo;
        _marca = m.actualizadoEn;
        _cargando = false;
        _docSucio = false;
        _tituloSucio = false;
        _estado = _Guardado.guardado;
        _deshacer.clear();
        _plegado.clear();
        _seleccion = null;
        _encuadrado = false;
        _tamanos.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e is MapasException ? e.message : 'No se pudo abrir el mapa';
      });
    }
  }

  /* ── Tamaños y lo que se ve ───────────────────────────────────────────── */

  Size _tamano(NodoMapa n) => _tamanos.putIfAbsent(n.id, () => medirNodo(n));

  /// Si [n] está plegado ahora (lo de la web, o lo que se haya tocado aquí).
  bool _estaPlegado(NodoMapa n) => _plegado[n.id] ?? n.plegado;

  /// Los nodos que se ven: fuera los que cuelgan de una rama plegada.
  List<NodoMapa> _visibles(DocMapa doc) {
    final nodos = doc.nodos;
    final ocultos = <String>{};
    for (final n in nodos) {
      if (_estaPlegado(n)) ocultos.addAll(doc.descendientes(n.id));
    }
    return [
      for (final n in nodos)
        if (!ocultos.contains(n.id)) n,
    ];
  }

  /* ── Ediciones ───────────────────────────────────────────────────────── */

  void _antesDeEditar() {
    _deshacer.add(jsonEncode(_doc!.json));
    if (_deshacer.length > 30) _deshacer.removeAt(0);
    if (_ordenar) {
      // Se edita sobre lo que se ve: el orden pasa a ser el del mapa.
      _doc!.colocar(_posOrdenadas);
      _ordenar = false;
    }
  }

  void _alternarOrden() {
    HapticsService.light();
    setState(() {
      _ordenar = !_ordenar;
      _encuadrado = false;
    });
  }

  void _cambiado({bool tamanos = false}) {
    if (tamanos) _tamanos.clear();
    _docSucio = true;
    _programarGuardado();
    setState(() {});
  }

  void _deshacerUno() {
    if (_deshacer.isEmpty) return;
    HapticsService.light();
    setState(() {
      _doc = DocMapa.desde(jsonDecode(_deshacer.removeLast()));
      if (_seleccion != null && !_doc!.nodos.any((n) => n.id == _seleccion)) _seleccion = null;
    });
    _cambiado(tamanos: true);
  }

  Future<void> _editarTexto(NodoMapa n, {bool nuevo = false}) async {
    final texto = await showAdaptiveModal<String>(
      context: context,
      builder: (_) =>
          _EditorTexto(inicial: textoDeLabel(n.label), conFormato: labelTieneFormato(n.label), seleccionarTodo: nuevo),
    );
    if (texto == null || !mounted) return;
    _antesDeEditar();
    if (_doc!.cambiarTexto(n.id, texto)) {
      _tamanos.remove(n.id);
      _cambiado();
    } else {
      _deshacer.removeLast();
    }
  }

  Future<void> _anadirRama(NodoMapa padre) async {
    HapticsService.light();
    _antesDeEditar();
    final id = _doc!.anadirHijo(padre.id, tamano: (id) => _tamano(_doc!.nodos.firstWhere((n) => n.id == id)));
    _plegado.remove(padre.id);
    setState(() => _seleccion = id);
    _cambiado();
    final nuevo = _doc!.nodos.firstWhere((n) => n.id == id);
    await _editarTexto(nuevo, nuevo: true);
  }

  Future<void> _borrarRama(NodoMapa n) async {
    final cuantos = _doc!.descendientes(n.id).length;
    if (cuantos > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Borrar esta rama?'),
          content: Text('Se borrará este nodo y los $cuantos que cuelgan de él. Puedes deshacerlo.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    HapticsService.medium();
    _antesDeEditar();
    _doc!.borrarRama(n.id);
    setState(() => _seleccion = null);
    _cambiado();
  }

  Future<void> _renombrar() async {
    if (_doc == null) return;
    final c = TextEditingController(text: _titulo);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del mapa'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Guardar')),
        ],
      ),
    );
    c.dispose();
    if (nuevo == null || nuevo.trim().isEmpty || nuevo.trim() == _titulo || !mounted) return;
    setState(() => _titulo = nuevo.trim());
    _tituloSucio = true;
    _programarGuardado();
  }

  /* ── Guardar ─────────────────────────────────────────────────────────── */

  void _programarGuardado() {
    _timer?.cancel();
    if (mounted) setState(() => _estado = _Guardado.pendiente);
    _timer = Timer(_esperaGuardado, _guardar);
  }

  Future<void> _guardar({bool silencioso = false, bool forzar = false}) async {
    final mapa = _mapa;
    final doc = _doc;
    if (mapa == null || doc == null || (!_docSucio && !_tituloSucio)) return;
    if (_guardandoAhora) {
      // Ya hay uno en marcha: se vuelve a intentar al acabar.
      if (!silencioso) _programarGuardado();
      return;
    }
    _guardandoAhora = true;
    final conDoc = _docSucio && doc.editable;
    final conTitulo = _tituloSucio;
    _docSucio = false;
    _tituloSucio = false;
    if (!silencioso && mounted) setState(() => _estado = _Guardado.guardando);
    try {
      _marca = await _api.guardar(
        mapa.id,
        actualizadoEn: _marca,
        titulo: conTitulo ? _titulo : null,
        doc: conDoc ? doc : null,
        forzar: forzar,
      );
      if (mounted && !silencioso) {
        setState(() => _estado = (_docSucio || _tituloSucio) ? _Guardado.pendiente : _Guardado.guardado);
      }
    } on MapaCambiadoException {
      _docSucio = _docSucio || conDoc;
      _tituloSucio = _tituloSucio || conTitulo;
      if (mounted && !silencioso) {
        setState(() => _estado = _Guardado.error);
        _guardandoAhora = false;
        await _conflicto();
        return;
      }
    } catch (_) {
      _docSucio = _docSucio || conDoc;
      _tituloSucio = _tituloSucio || conTitulo;
      if (mounted && !silencioso) setState(() => _estado = _Guardado.error);
    } finally {
      _guardandoAhora = false;
    }
  }

  Future<void> _conflicto() async {
    final quedarme = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('El mapa ha cambiado en otro sitio'),
        content: const Text(
          'Lo has guardado desde la web (u otro móvil) mientras lo tenías abierto aquí. '
          '¿Con qué versión te quedas?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cargar la otra')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quedarme con esta')),
        ],
      ),
    );
    if (!mounted) return;
    if (quedarme == true) {
      await _guardar(forzar: true);
    } else {
      _docSucio = false;
      _tituloSucio = false;
      await _cargar();
    }
  }

  /* ── Pantalla ────────────────────────────────────────────────────────── */

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F4),
      appBar: AppBar(
        title: GestureDetector(
          onTap: doc == null ? null : _renombrar,
          child: Text(_titulo.isEmpty ? 'Mapa' : _titulo, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          if (doc != null)
            IconButton(
              tooltip: _ordenar ? 'Ver como está en la web' : 'Ordenar el mapa',
              onPressed: _alternarOrden,
              isSelected: _ordenar,
              icon: const Icon(Icons.account_tree_outlined),
              selectedIcon: const Icon(Icons.account_tree_rounded, color: kAccent),
            ),
          if (doc != null && doc.editable) ...[
            IconButton(
              tooltip: 'Deshacer',
              onPressed: _deshacer.isEmpty ? null : _deshacerUno,
              icon: const Icon(Icons.undo_rounded),
            ),
            _IndicadorGuardado(estado: _estado, onReintentar: () => _guardar()),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : doc == null
            ? _Error(mensaje: _error ?? 'No se pudo abrir el mapa', onReintentar: _cargar)
            : _cuerpo(doc),
      ),
    );
  }

  Widget _cuerpo(DocMapa doc) {
    final visibles = _visibles(doc);
    final todos = doc.nodos;
    if (visibles.isEmpty) return const _Error(mensaje: 'Este mapa está vacío');
    final ps0 = doc.padres;
    if (_ordenar) {
      final o = ordenarEnArbol(
        ids: [for (final n in visibles) n.id],
        padres: ps0,
        tamano: (id) => _tamano(visibles.firstWhere((n) => n.id == id)),
      );
      _posOrdenadas = {for (final e in o.entries) e.key: e.value.topLeft};
    }
    Offset pos(NodoMapa n) => _ordenar ? (_posOrdenadas[n.id] ?? n.posicion) : n.posicion;
    final cajas = <String, Rect>{for (final n in visibles) n.id: pos(n) & _tamano(n)};
    final limites = cajas.values.reduce((a, b) => a.expandToInclude(b)).inflate(_margen);
    final origen = limites.topLeft;
    final ps = ps0;
    final conHijos = <String, int>{};
    for (final n in todos) {
      final p = ps[n.id];
      if (p != null) conHijos[p] = (conHijos[p] ?? 0) + 1;
    }
    final seleccionado = _seleccion == null ? null : todos.where((n) => n.id == _seleccion).firstOrNull;
    final editable = doc.editable;

    return Column(
      children: [
        // Una franja y no un aviso flotante: ese tapaba la barra de editar de abajo.
        if (_ordenar)
          Container(
            width: double.infinity,
            color: tinted(const Color(0xFF8BA888), 0.25),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.account_tree_rounded, size: 18, color: kInk),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ordenado para leerlo aquí. El mapa no cambia salvo que lo edites.',
                    style: TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ),
                TextButton(onPressed: _alternarOrden, child: const Text('Quitar')),
              ],
            ),
          ),
        if (!editable)
          Container(
            width: double.infinity,
            color: tinted(kAccent, 0.18),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: const Text(
              'Este mapa aún está como lo dejó la IA. Ábrelo una vez en la web y luego podrás editarlo aquí.',
              style: TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              if (!_encuadrado) {
                _encuadrado = true;
                // Si cabe entero a una escala legible, entero y centrado. Si no (un mapa grande en
                // el móvil), a esa escala mínima y centrado en la raíz: el resto, desplazándose.
                const legible = 0.6;
                final cabe = math.min(cons.maxWidth / limites.width, cons.maxHeight / limites.height);
                final s = math.min(1.0, math.max(cabe, legible));
                final raiz = visibles.where((n) => ps[n.id] == null).firstOrNull;
                final Offset centro = cabe >= legible || raiz == null
                    ? limites.center - origen
                    : cajas[raiz.id]!.center - origen + Offset(cons.maxWidth * 0.25 / s, 0);
                _vista.value = Matrix4.identity()
                  ..translateByDouble(cons.maxWidth / 2 - centro.dx * s, cons.maxHeight / 2 - centro.dy * s, 0, 1)
                  ..scaleByDouble(s, s, 1, 1);
              }
              return GestureDetector(
                onTap: () => setState(() => _seleccion = null),
                child: InteractiveViewer(
                  transformationController: _vista,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(4000),
                  minScale: 0.12,
                  maxScale: 3,
                  child: SizedBox(
                    width: limites.width,
                    height: limites.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _LineasPainter(
                                aristas: doc.aristas,
                                cajas: {for (final e in cajas.entries) e.key: e.value.shift(-origen)},
                              ),
                            ),
                          ),
                        ),
                        for (final n in visibles)
                          Positioned(
                            // El nodo va dentro de una caja con [_aire] a cada lado: ahí cabe el
                            // botón de plegar, que si sobresaliera no recibiría toques.
                            left: pos(n).dx - origen.dx - _aire,
                            top: pos(n).dy - origen.dy,
                            child: _NodoWidget(
                              key: ValueKey(n.id),
                              nodo: n,
                              tamano: _tamano(n),
                              seleccionado: n.id == _seleccion,
                              hijos: conHijos[n.id] ?? 0,
                              plegado: _estaPlegado(n),
                              ladoHijos: _ladoHijos(n, todos, ps),
                              arrastrable: editable && n.id == _seleccion,
                              onTap: () {
                                HapticsService.light();
                                setState(() => _seleccion = n.id == _seleccion ? null : n.id);
                              },
                              onPlegar: () => setState(() => _plegado[n.id] = !_estaPlegado(n)),
                              onArrastrar: (delta) {
                                final escala = _vista.value.getMaxScaleOnAxis();
                                if (!_arrastrando) {
                                  _arrastrando = true;
                                  _antesDeEditar();
                                }
                                doc.moverRama(n.id, delta / escala);
                                setState(() {});
                              },
                              onSoltar: () {
                                if (!_arrastrando) return;
                                _arrastrando = false;
                                _cambiado();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (editable && seleccionado != null)
          _BarraNodo(
            nodo: seleccionado,
            esRaiz: ps[seleccionado.id] == null,
            onEditar: seleccionado.textoEditable ? () => _editarTexto(seleccionado) : null,
            onAnadir: () => _anadirRama(seleccionado),
            onBorrar: () => _borrarRama(seleccionado),
          ),
      ],
    );
  }

  bool _arrastrando = false;

  /// Hacia qué lado cuelgan los hijos de [n] (para poner ahí el botón de plegar).
  bool _ladoHijos(NodoMapa n, List<NodoMapa> todos, Map<String, String?> ps) {
    final hijos = todos.where((h) => ps[h.id] == n.id);
    if (hijos.isEmpty) return true;
    final media = hijos.map((h) => h.posicion.dx).reduce((a, b) => a + b) / hijos.length;
    return media >= n.posicion.dx;
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Medir y pintar un nodo (NodeBody.tsx / NodeLabel.tsx)
═══════════════════════════════════════════════════════════════════════════ */

TextSpan spanDeLabel(NodoMapa n) {
  final e = n.estilo;
  final rotulo = e.forma == FormaNodo.rotulo;
  final trozos = trozosDeLabel(n.label);
  return TextSpan(
    // Sin heredar nada del tema: se mide con este mismo estilo (medirNodo) y, si heredara un
    // espaciado distinto, el texto pintado no cabría en su caja y se cortaría la última palabra.
    style: TextStyle(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontFamily: 'Lexend',
      fontSize: rotulo ? math.min(e.tamanoLetra, 13) : e.tamanoLetra,
      height: 1.5,
      color: rotulo ? kMuted : e.texto,
      fontWeight: rotulo ? FontWeight.w800 : FontWeight.w400,
      // Explícitos: un nulo aquí lo rellena el motor con lo del tema (0,3 de espaciado), aunque el
      // estilo no herede. Eran 3 px de más en «Tos nocturna»: la última palabra no cabía.
      letterSpacing: rotulo ? 0.8 : 0,
      wordSpacing: 0,
      decoration: TextDecoration.none,
    ),
    children: [
      for (final t in trozos)
        TextSpan(
          text: rotulo ? t.texto.toUpperCase() : t.texto,
          style: TextStyle(
            fontWeight: t.negrita ? FontWeight.w700 : null,
            fontStyle: t.cursiva ? FontStyle.italic : null,
            decoration: TextDecoration.combine([
              if (t.subrayado) TextDecoration.underline,
              if (t.tachado) TextDecoration.lineThrough,
            ]),
            color: t.color,
            backgroundColor: t.fondo,
            fontSize: t.escala == null ? null : e.tamanoLetra * t.escala!,
          ),
        ),
    ],
  );
}

/// El relleno de cada forma (NodeBody: 10×16, rombo 18×52, rótulo 4×8).
EdgeInsets _relleno(FormaNodo f) => switch (f) {
  FormaNodo.rombo => const EdgeInsets.symmetric(horizontal: 52, vertical: 18),
  FormaNodo.rotulo => const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  _ => const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
};

/// Mide un texto de una línea con la letra de los mapas (para la geometría de las tablas).
double medirCeldaLexend(String texto, bool negrita, double tamano) {
  final tp = TextPainter(
    text: TextSpan(
      text: texto,
      style: TextStyle(
        inherit: false,
        fontFamily: 'Lexend',
        fontSize: tamano,
        fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: 0,
        wordSpacing: 0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// La geometría de un nodo tabla, con la letra real.
GeometriaTabla geometriaDe(NodoMapa n) => geometriaTabla(
  n.tabla!,
  medir: medirCeldaLexend,
  tamano: n.estilo.tamanoLetra,
  borde: math.max(1, n.estilo.grosorBorde),
);

/// El tamaño que ocupa un nodo, como en la web: el guardado si lo hay (redimensionado o círculo);
/// una tabla, por su geometría; el resto, lo que pide su texto (sin partir líneas salvo los saltos
/// que tenga: la caja crece con el texto, como en el lienzo de la web). Si en la app las cajas
/// midieran distinto, se montarían unas sobre otras con las posiciones guardadas desde la web.
Size medirNodo(NodoMapa n) {
  final e = n.estilo;
  if (n.tabla != null) {
    final g = geometriaDe(n);
    return Size(n.ancho ?? g.ancho.ceilToDouble(), g.alto.ceilToDouble());
  }
  final pad = _relleno(e.forma);
  final borde = e.forma == FormaNodo.rotulo ? 0.0 : e.grosorBorde * 2;
  final tp = TextPainter(text: spanDeLabel(n), textDirection: TextDirection.ltr, textAlign: e.alineacion);
  if (n.ancho != null) {
    tp.layout(maxWidth: math.max(20, n.ancho! - pad.horizontal - borde));
  } else {
    tp.layout();
  }
  // +2 de holgura (como estimateSize de la web): con el ancho justo, el redondeo hacía que el texto
  // pintado partiera la línea y la última palabra se quedara fuera de la caja.
  var w = n.ancho ?? (tp.width + pad.horizontal + borde + 2).ceilToDouble();
  var h = n.alto ?? (tp.height + pad.vertical + borde).ceilToDouble();
  final minimo = switch (e.forma) {
    FormaNodo.rombo => const Size(130, 64),
    FormaNodo.circulo => const Size(80, 80),
    FormaNodo.rotulo => Size.zero,
    _ => const Size(100, 0),
  };
  w = math.max(w, minimo.width);
  h = math.max(h, math.max(minimo.height, e.forma == FormaNodo.rotulo ? 0 : 40));
  tp.dispose();
  if (e.forma == FormaNodo.circulo) {
    final lado = math.max(w, h);
    return Size(lado, lado);
  }
  return Size(w, h);
}

/// Un nodo tabla como en la web (TableBody.tsx): franja de título del color del nodo, cabecera
/// tintada, rejilla fina y cada celda con su estilo.
class _TablaWidget extends StatelessWidget {
  final NodoMapa nodo;
  final Size tamano;
  final bool seleccionado;

  const _TablaWidget({required this.nodo, required this.tamano, required this.seleccionado});

  @override
  Widget build(BuildContext context) {
    final t = nodo.tabla!;
    final e = nodo.estilo;
    final g = geometriaDe(nodo);
    final bw = math.max(1.0, e.grosorBorde);
    final acento = acentoTabla(e);
    final rejilla = acento.withValues(alpha: 0.38);

    Widget celda(int fila, int col, String texto) {
      final st = t.estiloDe(fila, col);
      return Container(
        width: g.anchosColumna[col],
        padding: const EdgeInsets.symmetric(horizontal: tablaPadX, vertical: tablaPadY),
        decoration: BoxDecoration(
          color: st.fondo,
          border: Border(
            left: col > 0 ? BorderSide(color: rejilla) : BorderSide.none,
            top: BorderSide(color: rejilla),
          ),
        ),
        child: Text(
          texto.isEmpty ? ' ' : texto,
          textAlign: st.alineacion ?? TextAlign.left,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            inherit: false,
            fontFamily: 'Lexend',
            fontSize: g.tamanoCelda,
            height: tablaLinea,
            letterSpacing: 0,
            wordSpacing: 0,
            fontWeight: st.negrita == true ? FontWeight.w700 : FontWeight.w400,
            fontStyle: st.cursiva == true ? FontStyle.italic : FontStyle.normal,
            color: st.color ?? e.texto,
            textBaseline: TextBaseline.alphabetic,
          ),
        ),
      );
    }

    Widget fila(int i, List<String> textos) => SizedBox(
      height: g.altosFila[i + 1],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var j = 0; j < textos.length; j++) celda(i, j, textos[j])],
      ),
    );

    return Container(
      width: tamano.width,
      height: tamano.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: e.relleno,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: seleccionado ? kInk : acento, width: seleccionado ? math.max(bw, 2.5) : bw),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 2))],
      ),
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: g.ancho - 2 * bw,
        maxWidth: g.ancho - 2 * bw,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: g.altoTitulo,
              color: acento,
              padding: const EdgeInsets.symmetric(horizontal: tablaTituloPadX, vertical: tablaTituloPadY),
              child: Text(
                t.titulo.isEmpty ? ' ' : t.titulo,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  inherit: false,
                  fontFamily: 'Lexend',
                  fontSize: e.tamanoLetra,
                  height: tablaLinea,
                  letterSpacing: 0,
                  wordSpacing: 0,
                  fontWeight: FontWeight.w700,
                  color: legibleSobre(acento),
                  textBaseline: TextBaseline.alphabetic,
                ),
              ),
            ),
            Container(color: acento.withValues(alpha: 0.14), child: fila(-1, t.columnas)),
            for (var i = 0; i < t.filas.length; i++) fila(i, t.filas[i]),
          ],
        ),
      ),
    );
  }
}

class _NodoWidget extends StatelessWidget {
  final NodoMapa nodo;
  final Size tamano;
  final bool seleccionado;
  final int hijos;
  final bool plegado;
  final bool ladoHijos; // true = derecha
  final bool arrastrable;
  final VoidCallback onTap;
  final VoidCallback onPlegar;
  final ValueChanged<Offset> onArrastrar;
  final VoidCallback onSoltar;

  const _NodoWidget({
    super.key,
    required this.nodo,
    required this.tamano,
    required this.seleccionado,
    required this.hijos,
    required this.plegado,
    required this.ladoHijos,
    required this.arrastrable,
    required this.onTap,
    required this.onPlegar,
    required this.onArrastrar,
    required this.onSoltar,
  });

  @override
  Widget build(BuildContext context) {
    final e = nodo.estilo;
    // Sin el escalado de letra del sistema: el mapa ya se amplía pellizcando, y medirNodo no lo usa.
    final texto = Text.rich(spanDeLabel(nodo), textAlign: e.alineacion, textScaler: TextScaler.noScaling);
    final colorBorde = seleccionado ? e.brillo : e.borde;
    final sombras = seleccionado
        ? [
            // Aro de tinta: en un nodo relleno, uno del color del brillo no se distinguía.
            const BoxShadow(color: kInk, spreadRadius: 2.5),
            BoxShadow(color: e.brillo.withValues(alpha: 0.35), blurRadius: 20),
          ]
        : const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 2))];

    final Widget cuerpo = nodo.tabla != null
        ? _TablaWidget(nodo: nodo, tamano: tamano, seleccionado: seleccionado)
        : switch (e.forma) {
            FormaNodo.rombo => CustomPaint(
              painter: _RomboPainter(
                e.relleno,
                e.grosorBorde > 0 || seleccionado ? colorBorde : null,
                math.max(e.grosorBorde, seleccionado ? 2 : 0),
              ),
              child: Container(
                width: tamano.width,
                height: tamano.height,
                alignment: Alignment.center,
                padding: _relleno(e.forma),
                child: texto,
              ),
            ),
            FormaNodo.rotulo => Container(
              width: tamano.width,
              height: tamano.height,
              alignment: Alignment.center,
              padding: _relleno(e.forma),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: seleccionado ? const [BoxShadow(color: kInk, spreadRadius: 2)] : null,
                color: seleccionado ? Colors.white : null,
              ),
              child: texto,
            ),
            _ => Container(
              width: tamano.width,
              height: tamano.height,
              alignment: Alignment.center,
              padding: _relleno(e.forma),
              decoration: BoxDecoration(
                color: e.relleno,
                shape: e.forma == FormaNodo.circulo ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: switch (e.forma) {
                  FormaNodo.pastilla => BorderRadius.circular(999),
                  FormaNodo.circulo => null,
                  _ => BorderRadius.circular(12),
                },
                border: e.grosorBorde > 0 || seleccionado
                    ? Border.all(color: colorBorde, width: math.max(e.grosorBorde, seleccionado ? 2 : 0))
                    : null,
                boxShadow: sombras,
              ),
              child: texto,
            ),
          };

    return Semantics(
      button: true,
      selected: seleccionado,
      label: textoDeLabel(nodo.label),
      child: SizedBox(
        width: tamano.width + 2 * _aire,
        height: tamano.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _aire,
              top: 0,
              child: GestureDetector(
                // Sin doble toque: haría esperar 300 ms a cada toque para seleccionar. El texto se
                // edita desde la barra de abajo.
                onTap: onTap,
                onPanUpdate: arrastrable ? (d) => onArrastrar(d.delta) : null,
                onPanEnd: arrastrable ? (_) => onSoltar() : null,
                onPanCancel: arrastrable ? onSoltar : null,
                child: ExcludeSemantics(child: cuerpo),
              ),
            ),
            if (hijos > 0)
              Positioned(
                top: tamano.height / 2 - 12,
                left: ladoHijos ? _aire + tamano.width - 6 : null,
                right: ladoHijos ? null : _aire + tamano.width - 6,
                child: Semantics(
                  button: true,
                  label: plegado ? 'Desplegar la rama ($hijos)' : 'Plegar la rama',
                  child: GestureDetector(
                    onTap: onPlegar,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: e.brillo, width: 1.5),
                      ),
                      child: ExcludeSemantics(
                        child: Text(
                          plegado ? '+$hijos' : '−',
                          style: const TextStyle(color: kInk, fontSize: 11, fontWeight: FontWeight.w800, height: 1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RomboPainter extends CustomPainter {
  final Color relleno;
  final Color? borde;
  final double grosor;
  _RomboPainter(this.relleno, this.borde, this.grosor);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawShadow(p, const Color(0x55000000), 3, false);
    canvas.drawPath(p, Paint()..color = relleno);
    if (borde != null && grosor > 0) {
      canvas.drawPath(
        p,
        Paint()
          ..color = borde!
          ..style = PaintingStyle.stroke
          ..strokeWidth = grosor
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RomboPainter old) => old.relleno != relleno || old.borde != borde || old.grosor != grosor;
}

class _LineasPainter extends CustomPainter {
  final List<AristaMapa> aristas;
  final Map<String, Rect> cajas;
  _LineasPainter({required this.aristas, required this.cajas});

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in aristas) {
      final s = cajas[a.origen], t = cajas[a.destino];
      if (s == null || t == null) continue;
      final (p0, c1, c2, p1) = curvaEntre(s, t);
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p1.dx, p1.dy);
      final paint = Paint()
        ..color = a.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = a.grosor
        ..strokeCap = a.variante == 'dotted' ? StrokeCap.round : StrokeCap.butt;
      if (a.variante == 'solid') {
        canvas.drawPath(path, paint);
      } else {
        // Discontinua (10 5) o de puntos (2 6), como el dasharray de la web.
        final (largo, hueco) = a.variante == 'dotted' ? (2.0, 6.0) : (10.0, 5.0);
        for (final m in path.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, math.min(d + largo, m.length)), paint);
            d += largo + hueco;
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LineasPainter old) => true;
}

/* ════════════════════════════════════════════════════════════════════════
   Barra del nodo, editor de texto e indicador de guardado
═══════════════════════════════════════════════════════════════════════════ */

class _BarraNodo extends StatelessWidget {
  final NodoMapa nodo;
  final bool esRaiz;
  final VoidCallback? onEditar;
  final VoidCallback onAnadir;
  final VoidCallback onBorrar;

  const _BarraNodo({
    required this.nodo,
    required this.esRaiz,
    required this.onEditar,
    required this.onAnadir,
    required this.onBorrar,
  });

  @override
  Widget build(BuildContext context) {
    Widget boton(IconData icono, String texto, VoidCallback? onTap, {Color color = kInk}) => Expanded(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: texto,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, color: onTap == null ? kHairline : color, size: 22),
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    style: TextStyle(
                      color: onTap == null ? kHairline : color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kInk, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nodo.esTabla
                ? 'Las tablas se editan en la web · arrastra para mover'
                : 'Arrastra el nodo para moverlo con su rama',
            style: const TextStyle(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              boton(Icons.edit_rounded, 'Editar texto', onEditar),
              boton(Icons.add_circle_outline_rounded, 'Añadir rama', onAnadir),
              boton(Icons.delete_outline_rounded, 'Borrar', esRaiz ? null : onBorrar, color: const Color(0xFFC0564B)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditorTexto extends StatefulWidget {
  final String inicial;
  final bool conFormato;
  final bool seleccionarTodo;

  const _EditorTexto({required this.inicial, required this.conFormato, required this.seleccionarTodo});

  @override
  State<_EditorTexto> createState() => _EditorTextoState();
}

class _EditorTextoState extends State<_EditorTexto> {
  late final TextEditingController _c = TextEditingController(text: widget.inicial)
    ..selection = widget.seleccionarTodo
        ? TextSelection(baseOffset: 0, extentOffset: widget.inicial.length)
        : TextSelection.collapsed(offset: widget.inicial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Texto del nodo',
            style: TextStyle(color: kInk, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          if (widget.conFormato) ...[
            const SizedBox(height: 6),
            const Text(
              'Este nodo tiene formato (negrita, colores…). Si cambias el texto aquí, se quedará sin él.',
              style: TextStyle(color: Color(0xFF9A6A12), fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ''),
          ),
          const SizedBox(height: 12),
          StickerButton(
            label: 'Guardar',
            expand: true,
            onPressed: () {
              final t = _c.text.trim();
              Navigator.of(context).pop(t.isEmpty ? null : t);
            },
          ),
        ],
      ),
    );
  }
}

class _IndicadorGuardado extends StatelessWidget {
  final _Guardado estado;
  final VoidCallback onReintentar;

  const _IndicadorGuardado({required this.estado, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    final (IconData icono, String texto, Color color) = switch (estado) {
      _Guardado.guardado => (Icons.cloud_done_rounded, 'Guardado', const Color(0xFF6E8E6B)),
      _Guardado.pendiente => (Icons.cloud_queue_rounded, 'Sin guardar', kMuted),
      _Guardado.guardando => (Icons.cloud_upload_rounded, 'Guardando…', kMuted),
      _Guardado.error => (Icons.cloud_off_rounded, 'No se pudo guardar. Toca para reintentar', const Color(0xFFC0564B)),
    };
    return IconButton(
      tooltip: texto,
      onPressed: estado == _Guardado.error ? onReintentar : null,
      icon: Icon(icono, color: color),
      disabledColor: color,
    );
  }
}

class _Error extends StatelessWidget {
  final String mensaje;
  final VoidCallback? onReintentar;

  const _Error({required this.mensaje, this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined, size: 40, color: kMuted),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kInk, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (onReintentar != null) ...[
              const SizedBox(height: 16),
              StickerButton(label: 'Reintentar', icon: Icons.refresh_rounded, onPressed: onReintentar),
            ],
          ],
        ),
      ),
    );
  }
}
