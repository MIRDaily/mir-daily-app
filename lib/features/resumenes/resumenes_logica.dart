// Resúmenes activos, lo puro que llegó con la tanda 3: previsión y aviso, ajustes de la sesión de
// estudio, modo «Escribir la respuesta», gestos de deslizar, niveles legibles (AA) y «Más» /
// «Rehacer» de la vista previa. Sin Flutter salvo los colores: se prueba en
// test/resumenes_logica_test.dart con los mismos casos que la web.
//
// Puerto de la web: src/lib/resumenes/prevision.ts, sesion.ts, escribir.ts, gestos.ts, accesible.ts y
// ampliar.ts (con fragmentoParaRama de src/lib/mapas/ia/rama.ts).

import 'dart:math' as math;
import 'dart:ui' show Color;

import '../../core/models/ia.dart';
import '../../core/models/resumen.dart';
import '../../core/models/resumen_ia.dart';
import 'resumenes_huecos.dart' show Respuesta;

const List<int> kNivelesResumen = [1, 2, 3, 4];

/// Sin tildes ni mayúsculas (la eñe se queda).
String _plano(String s) {
  const m = {'á': 'a', 'à': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'ü': 'u'};
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    b.write(m[c] ?? c);
  }
  return b.toString();
}

int _n(dynamic v) => v is num && v.isFinite && v >= 0 ? v.toInt() : 0;
double? _t(dynamic v) => v is num && v.isFinite ? v.toDouble().clamp(0, 1).toDouble() : null;
Map _o(dynamic v) => v is Map ? v : const {};
final _fecha = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _miles(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Previsión y estadísticas (GET /api/resumenes/prevision y /:id/prevision)
// ---------------------------------------------------------------------------

class HuecoFalladoResumen {
  final int itemId;
  final String? grupoId, grupo, tema;
  final int hueco;
  final String texto;
  final int nivel;
  final int fallos, intentos;
  final bool falladoAhora;

  const HuecoFalladoResumen({
    required this.itemId,
    this.grupoId,
    this.grupo,
    this.tema,
    required this.hueco,
    required this.texto,
    required this.nivel,
    required this.fallos,
    required this.intentos,
    required this.falladoAhora,
  });
}

class PrevisionResumenes {
  final int grupos, parrafos, nuevos;

  /// Lo que la lista de grupos llama «por repasar»: nuevos + los que tocan ya.
  final int pendientes;
  final int repasoAhora;
  final int atrasados, hoy, manana, semana, mes;
  final List<({String fecha, int n})> dias;
  final ResumenEstados estados;
  final int programados, recordados, programados30;
  final double? tasa, tasa30;
  final int huecosRepasados, huecosSabidos;
  final double? tasaHuecos;
  final List<HuecoFalladoResumen> masFallados;

  const PrevisionResumenes({
    this.grupos = 0,
    this.parrafos = 0,
    this.nuevos = 0,
    this.pendientes = 0,
    this.repasoAhora = 0,
    this.atrasados = 0,
    this.hoy = 0,
    this.manana = 0,
    this.semana = 0,
    this.mes = 0,
    this.dias = const [],
    this.estados = const ResumenEstados(nuevo: 0, failed: 0, learning: 0, mastered: 0),
    this.programados = 0,
    this.recordados = 0,
    this.programados30 = 0,
    this.tasa,
    this.tasa30,
    this.huecosRepasados = 0,
    this.huecosSabidos = 0,
    this.tasaHuecos,
    this.masFallados = const [],
  });
}

String? _s(dynamic v, int max) => v is String ? (v.length > max ? v.substring(0, max) : v) : null;

/// La respuesta del servidor → previsión (ceros y nulos si falta algo; nunca revienta).
PrevisionResumenes sanearPrevision(dynamic raw) {
  final x = _o(raw);
  final p = _o(x['prevision']);
  final e = _o(x['estados']);
  final r = _o(x['retencion']);
  final h = _o(x['huecos']);
  return PrevisionResumenes(
    grupos: _n(x['grupos']),
    parrafos: _n(x['parrafos']),
    nuevos: _n(x['nuevos']),
    pendientes: _n(x['pendientes']),
    repasoAhora: _n(x['repasoAhora']),
    atrasados: _n(p['atrasados']),
    hoy: _n(p['hoy']),
    manana: _n(p['manana']),
    semana: _n(p['semana']),
    mes: _n(p['mes']),
    dias: [
      for (final d in (p['dias'] is List ? p['dias'] as List : const []).map(_o))
        if (d['fecha'] is String && _fecha.hasMatch(d['fecha'] as String)) (fecha: d['fecha'] as String, n: _n(d['n'])),
    ].take(30).toList(),
    estados: ResumenEstados(nuevo: _n(e['new']), failed: _n(e['failed']), learning: _n(e['learning']), mastered: _n(e['mastered'])),
    programados: _n(r['programados']),
    recordados: _n(r['recordados']),
    programados30: _n(r['programados30']),
    tasa: _t(r['tasa']),
    tasa30: _t(r['tasa30']),
    huecosRepasados: _n(h['repasados']),
    huecosSabidos: _n(h['sabidos']),
    tasaHuecos: _t(h['tasa']),
    masFallados: [
      for (final m in (x['masFallados'] is List ? x['masFallados'] as List : const []).map(_o))
        if (m['texto'] is String && (m['texto'] as String).trim().isNotEmpty)
          HuecoFalladoResumen(
            itemId: _n(m['itemId']),
            grupoId: _s(m['grupoId'], 36),
            grupo: _s(m['grupo'], 80),
            tema: _s(m['tema'], 120),
            hueco: _n(m['hueco']),
            texto: _s(m['texto'], 120)!,
            nivel: kNivelesResumen.contains(m['nivel']) ? m['nivel'] as int : 2,
            fallos: _n(m['fallos']),
            intentos: _n(m['intentos']),
            falladoAhora: m['falladoAhora'] == true,
          ),
    ].take(5).toList(),
  );
}

String _parrafos(int k) => k == 1 ? '1 párrafo' : '${_miles(k)} párrafos';

/// El aviso de Studio y de la Biblioteca: null si no hay nada que repasar (no se enseña).
({String titulo, String detalle})? textoAviso(PrevisionResumenes p) {
  if (p.pendientes <= 0) return null;
  final partes = <String>[];
  // Los atrasados (de días anteriores) son parte de los de repaso: se dicen entre paréntesis.
  final atr = math.min(p.atrasados, p.repasoAhora);
  final deAntes = atr == 0
      ? ''
      : atr == p.repasoAhora
          ? (atr == 1 ? ' (de un día anterior)' : ' (todos de días anteriores)')
          : ' (${_miles(atr)} de días anteriores)';
  if (p.repasoAhora > 0) partes.add('${_miles(p.repasoAhora)} de repaso$deAntes');
  if (p.nuevos > 0) partes.add(p.nuevos == 1 ? '1 nuevo' : '${_miles(p.nuevos)} nuevos');
  return (titulo: 'Tienes ${_parrafos(p.pendientes)} para repasar', detalle: 'En tus resúmenes activos: ${partes.join(' · ')}.');
}

/// Porcentaje entero («80 %») o «—».
String porcentajeResumen(double? v) => v == null ? '—' : '${(v * 100).round()} %';

/// Las cuatro cifras de la previsión (hoy incluye lo atrasado; 7 y 30 días, acumulado).
List<({String etiqueta, int n, String? nota})> tramosPrevision(PrevisionResumenes p) => [
      (etiqueta: 'Hoy', n: p.hoy, nota: p.atrasados > 0 ? '${p.atrasados} atrasados' : null),
      (etiqueta: 'Mañana', n: p.manana, nota: null),
      (etiqueta: '7 días', n: p.semana, nota: null),
      (etiqueta: '30 días', n: p.mes, nota: null),
    ];

const _mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];

/// «12 oct» de una fecha YYYY-MM-DD (el día de Madrid que manda el servidor).
String diaCortoResumen(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  final m = (int.tryParse(p[1]) ?? 1).clamp(1, 12);
  return '${int.tryParse(p[2]) ?? p[2]} ${_mesesCortos[m - 1]}';
}

// ---------------------------------------------------------------------------
// Ajustes de la sesión de estudio (los aplica la cola del servidor con las mismas definiciones)
// ---------------------------------------------------------------------------

enum SoloResumen { todos, due, failed, nuevo, huecos }

const Map<SoloResumen, String> kNombreSoloResumen = {
  SoloResumen.todos: 'Todos',
  SoloResumen.due: 'Pendientes',
  SoloResumen.failed: 'Solo fallados',
  SoloResumen.nuevo: 'Solo nuevos',
  SoloResumen.huecos: 'Solo huecos fallados',
};

String _idSolo(SoloResumen s) => switch (s) {
      SoloResumen.todos => 'todos',
      SoloResumen.due => 'due',
      SoloResumen.failed => 'failed',
      SoloResumen.nuevo => 'new',
      SoloResumen.huecos => 'huecos',
    };

const List<int> kCuantosResumen = [10, 20, 50];

class AjustesResumen {
  final List<int> niveles;
  final List<String>? temas;
  final SoloResumen solo;
  final int? cuantos;

  /// Escribir la respuesta de cada hueco antes de destaparlo (solo de la pantalla).
  final bool escribir;

  /// Todas las cajas tapadas del mismo ancho (solo de la pantalla).
  final bool anchoFijo;

  const AjustesResumen({
    this.niveles = kNivelesResumen,
    this.temas,
    this.solo = SoloResumen.todos,
    this.cuantos,
    this.escribir = false,
    this.anchoFijo = false,
  });

  AjustesResumen copyWith({
    List<int>? niveles,
    List<String>? Function()? temas,
    SoloResumen? solo,
    int? Function()? cuantos,
    bool? escribir,
    bool? anchoFijo,
  }) =>
      AjustesResumen(
        niveles: niveles ?? this.niveles,
        temas: temas != null ? temas() : this.temas,
        solo: solo ?? this.solo,
        cuantos: cuantos != null ? cuantos() : this.cuantos,
        escribir: escribir ?? this.escribir,
        anchoFijo: anchoFijo ?? this.anchoFijo,
      );

  Map<String, dynamic> toJson() => {
        'niveles': niveles,
        'temas': temas,
        'solo': _idSolo(solo),
        'cuantos': cuantos,
        'escribir': escribir,
        'anchoFijo': anchoFijo,
      };
}

String _temaDe(Parrafo p) => (p.tema ?? '').trim();

/// ¿Entra el párrafo con estos ajustes (sin contar el «cuántos»)?
bool entraResumen(Parrafo p, AjustesResumen a) {
  final todos = a.niveles.length >= kNivelesResumen.length;
  if (!todos && !p.huecos.any((h) => a.niveles.contains(h.n))) return false;
  if (a.temas != null && !a.temas!.contains(_temaDe(p))) return false;
  final visto = p.status != null && p.status != EstadoParrafoSrs.new_;
  switch (a.solo) {
    case SoloResumen.nuevo:
      if (visto) return false;
    case SoloResumen.failed:
      if (!(visto && p.status == EstadoParrafoSrs.failed)) return false;
    case SoloResumen.due:
      if (!(visto && (p.status == EstadoParrafoSrs.failed || p.due == true))) return false;
    case SoloResumen.huecos:
      final f = p.huecosFallados ?? const <int>[];
      if (!f.any((k) => k >= 0 && k < p.huecos.length && (todos || a.niveles.contains(p.huecos[k].n)))) return false;
    case SoloResumen.todos:
      break;
  }
  return true;
}

/// Cuántos párrafos distintos va a servir la sesión.
int cuantosSeEstudian(List<Parrafo> ps, AjustesResumen a) {
  final n = ps.where((p) => entraResumen(p, a)).length;
  return a.cuantos != null ? math.min(n, a.cuantos!) : n;
}

/// Ajustes → cuerpo de POST /api/resumenes/:id/sesion (null o todo = sin ese filtro).
AjustesEstudio aPeticion(AjustesResumen a, List<String> todosLosTemas) {
  final temas = a.temas != null && a.temas!.length < todosLosTemas.length ? a.temas : null;
  return AjustesEstudio(
    levels: a.niveles.isNotEmpty && a.niveles.length < kNivelesResumen.length ? a.niveles : null,
    topics: temas,
    soloHuecosFallados: a.solo == SoloResumen.huecos ? true : null,
    onlyStatus: a.solo == SoloResumen.huecos || a.solo == SoloResumen.todos ? null : _idSolo(a.solo),
    cardLimit: a.cuantos,
  );
}

/// «Repasar ahora» los fallados de una sesión: los mismos niveles, solo esos párrafos y solo sus huecos fallados.
AjustesEstudio repasarAhora(AjustesEstudio a, List<int> itemIds) =>
    AjustesEstudio(levels: a.levels, soloHuecosFallados: true, itemIds: itemIds.toSet().toList());

/// Lo guardado en el teléfono (los últimos ajustes de cada grupo) no se da por bueno.
AjustesResumen sanearAjustesResumen(dynamic raw) {
  if (raw is! Map) return const AjustesResumen();
  final niveles = (raw['niveles'] is List ? (raw['niveles'] as List) : const []).whereType<int>().where(kNivelesResumen.contains).toSet().toList()..sort();
  final temas = raw['temas'] is List
      ? (raw['temas'] as List).whereType<String>().map((t) => t.length > 120 ? t.substring(0, 120) : t).take(200).toList()
      : null;
  final c = raw['cuantos'];
  return AjustesResumen(
    niveles: niveles.isEmpty ? kNivelesResumen : niveles,
    temas: temas != null && temas.isNotEmpty ? temas : null,
    solo: SoloResumen.values.firstWhere((s) => _idSolo(s) == raw['solo'], orElse: () => SoloResumen.todos),
    cuantos: c is int && c > 0 && c <= 500 ? c : null,
    escribir: raw['escribir'] == true,
    anchoFijo: raw['anchoFijo'] == true,
  );
}

// ---------------------------------------------------------------------------
// «Escribir la respuesta»: lo escrito frente a lo tapado. Nada de esto llega al servidor.
// Deliberadamente sin tolerancia a erratas salvo una letra en palabras largas: en medicina una letra
// cambia el dato (hipo/hiper, IgA/IgM, tipo I/tipo II).
// ---------------------------------------------------------------------------

enum Comparacion { igual, casi, distinta, vacia }

final Set<String> _unidades = ('% mg g kg ug ng pg ml l dl mmol umol mol meq mosm mosmol mmhg cmh2o cm mm um nm m m2 mm3 h hora horas min minutos '
        'seg segundos s dia dias semana semanas mes meses ano anos ui u x veces lpm rpm kda kcal cal fl ul celulas')
    .split(' ')
    .toSet();
bool _esUnidad(String x) => x.split('/').every((p) => p.isEmpty || _unidades.contains(p));
const _clases = {'tipo', 'grado', 'estadio', 'clase', 'fase', 'nivel', 'escala'};
const _articulos = {'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'lo'};
const _romanos = {'i': '1', 'ii': '2', 'iii': '3', 'iv': '4', 'v': '5', 'vi': '6', 'vii': '7', 'viii': '8', 'ix': '9', 'x': '10'};

/// Palabras normalizadas: minúsculas, sin tildes, «por ciento» → «%», «≥» → «>=», «µg» → «ug», romanos → cifras.
List<String> palabrasRespuesta(String s) {
  var t = _plano(s)
      .replaceAll(RegExp('[µμ]'), 'u')
      .replaceAll(RegExp(r'\bmcg\b'), 'ug')
      .replaceAll(RegExp(r'\bpor\s*ciento\b'), '%')
      .replaceAll('≥', '>=')
      .replaceAll('≤', '<=')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}')
      .replaceAll(RegExp('[«»"“”\'‘’¿?¡!;:()\\[\\]{}]'), ' ')
      .replaceAllMapped(RegExp(r'(\D)[.,](?=\s|$)'), (m) => '${m[1]} ')
      .replaceAll(',', ' ')
      .replaceAllMapped(RegExp(r'(\d)(%|[a-z/]+)'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([<>]=?|=|±)(\d)'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('-', ' ');
  return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => _romanos[w] ?? w).toList();
}

/// Forma compacta para comparar: sin artículos delante, sin espacios.
String normalizarRespuesta(String s) {
  final w = palabrasRespuesta(s);
  while (w.length > 1 && _articulos.contains(w.first)) {
    w.removeAt(0);
  }
  return w.join();
}

final _esCifra = RegExp(r'^[<>]=?$|^=$|^±$|\d');

({String cifras, List<String> resto}) _partes(String s) {
  final w = palabrasRespuesta(s).where((x) => !_articulos.contains(x)).toList();
  return (cifras: w.where(_esCifra.hasMatch).join(' '), resto: w.where((x) => !_esCifra.hasMatch(x)).toList());
}

int _distancia(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var fila = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
      fila = math.min(fila, cur[j]);
    }
    if (fila > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// Lo escrito frente a lo tapado: igual, casi (una letra en una respuesta larga sin cifras), distinta o vacía.
Comparacion compararRespuesta(String escrita, String correcta) {
  final e = normalizarRespuesta(escrita);
  if (e.isEmpty) return Comparacion.vacia;
  final c = normalizarRespuesta(correcta);
  if (e == c) return Comparacion.igual;
  final digito = RegExp(r'\d');
  if (digito.hasMatch(c)) {
    final pe = _partes(escrita);
    final pc = _partes(correcta);
    if (pe.cifras != pc.cifras) return Comparacion.distinta;
    if (pe.resto.join() == pc.resto.join()) return Comparacion.igual;
    bool omitible(String x) => _esUnidad(x) || _clases.contains(x);
    if (pc.resto.every(omitible) && pe.resto.every(pc.resto.contains)) return Comparacion.igual;
    return Comparacion.distinta;
  }
  if (c.length >= 8 && !digito.hasMatch(e) && _distancia(e, c, 1) <= 1) return Comparacion.casi;
  return Comparacion.distinta;
}

/// Lo que se propone: igual o casi → «Lo sabía».
bool propuestaSabia(Comparacion c) => c == Comparacion.igual || c == Comparacion.casi;

// ---------------------------------------------------------------------------
// Gestos: con un hueco destapado, deslizar a la derecha = «Lo sabía», a la izquierda = «No lo sabía».
// ---------------------------------------------------------------------------

/// Distancia mínima para que un deslizamiento cuente: el 22 % del ancho, entre 64 y 120.
double umbralDeslizar(double ancho) => (ancho * 0.22).roundToDouble().clamp(64, 120).toDouble();

/// ¿Qué respuesta da un deslizamiento de (dx, dy) sobre una tarjeta de `ancho`? null si no cuenta.
Respuesta? respuestaDeslizar(double dx, double dy, double ancho) {
  if (!dx.isFinite || !dy.isFinite) return null;
  if (dx.abs() < umbralDeslizar(ancho)) return null;
  // Un movimiento casi vertical es desplazar la página, no contestar.
  if (dy.abs() > dx.abs() * 0.6) return null;
  return dx > 0 ? Respuesta.sabia : Respuesta.no;
}

// ---------------------------------------------------------------------------
// Niveles legibles por todos (AA): una etiqueta corta además del color, y una tinta más oscura para
// el texto (los colores de siempre no llegan a 4,5:1 sobre su tono suave).
// ---------------------------------------------------------------------------

const Map<int, String> kNivelCorto = {1: 'Fác', 2: 'Med', 3: 'Dif', 4: 'Dem'};
const Map<int, String> kNivelNombre = {1: 'fácil', 2: 'media', 3: 'difícil', 4: 'demencial'};
const Map<int, Color> kTintaNivel = {1: Color(0xFF3B6537), 2: Color(0xFF2B5F82), 3: Color(0xFF7E520A), 4: Color(0xFF8E3346)};

/// Verde y rojo de «Lo sabía» / «No lo sabía» con texto blanco encima (AA).
const Color kVerdeOk = Color(0xFF3B6537);
const Color kRojoKo = Color(0xFF8E3346);

/// El gris secundario de la casa no llega a AA en letra pequeña: este sí.
const Color kGrisAA = Color(0xFF5F6B76);

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// Contraste WCAG 2.x entre dos colores.
double contraste(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

enum EstadoHueco { tapado, destapado, sabia, no, visible }

/// Lo que dice un lector de pantalla de un hueco del estudio. Tapado: el nivel, nunca la respuesta.
String etiquetaHueco(EstadoHueco estado, int n, String respuesta, {bool escribir = false}) {
  final nivel = 'nivel ${kNivelNombre[n] ?? ''}';
  return switch (estado) {
    EstadoHueco.tapado => 'Hueco tapado, $nivel. ${escribir ? 'Toca para escribir la respuesta' : 'Toca para destaparlo'}',
    EstadoHueco.destapado => 'Destapado: $respuesta. ¿Lo sabías?',
    EstadoHueco.sabia => '$respuesta: lo sabías. Toca para cambiarlo a «No lo sabía»',
    EstadoHueco.no => '$respuesta: no lo sabías. Toca para cambiarlo a «Lo sabía»',
    EstadoHueco.visible => '$respuesta (hueco de $nivel, no se tapa en esta sesión)',
  };
}

// ---------------------------------------------------------------------------
// «Más de este tema» y «Rehacer este párrafo» en la vista previa
// ---------------------------------------------------------------------------

enum OpcionMas { todo, dificiles, faciles }

const List<({OpcionMas id, String titulo, String descripcion, List<int>? niveles})> kOpcionesMas = [
  (id: OpcionMas.todo, titulo: 'Más de todo', descripcion: 'Con los niveles de la generación.', niveles: null),
  (id: OpcionMas.dificiles, titulo: 'Más difíciles', descripcion: 'Huecos difícil y demencial.', niveles: [3, 4]),
  (id: OpcionMas.faciles, titulo: 'Más fáciles', descripcion: 'Huecos fácil y media.', niveles: [1, 2]),
];
const List<int> kCantidadesMas = [3, 5, 10];

/// Los niveles de los huecos de una lista (los de la generación). Sin huecos, todos.
List<int> nivelesDeLista(List<ParrafoBorrador> lista) {
  final hay = {for (final p in lista) for (final h in p.huecos) h.n};
  final out = kNivelesResumen.where(hay.contains).toList();
  return out.isEmpty ? kNivelesResumen : out;
}

List<int> nivelesDeOpcion(OpcionMas o, List<int> generacion) =>
    kOpcionesMas.firstWhere((x) => x.id == o).niveles ?? (generacion.isEmpty ? kNivelesResumen : generacion);

bool _delTema(ParrafoBorrador p, String grupo, String tema) => (p.grupo ?? '') == grupo && p.tema == tema;

List<ParrafoBorrador> parrafosDeTema(List<ParrafoBorrador> l, String grupo, String tema) => l.where((p) => _delTema(p, grupo, tema)).toList();

/// Los otros temas (primero los del mismo tema del libro): la IA no hace párrafos de ellos.
List<String> vecinosDeTema(List<ParrafoBorrador> lista, String grupo, String tema, [int max = 60]) {
  final mismos = <String>[], otros = <String>[];
  for (final p in lista) {
    if (p.tema == tema || mismos.contains(p.tema) || otros.contains(p.tema)) continue;
    ((p.grupo ?? '') == grupo ? mismos : otros).add(p.tema);
  }
  return [...mismos, ...otros].take(max).toList();
}

List<int> paginasDe(List<ParrafoBorrador> ps) => [
      for (final p in ps)
        if ((p.ia?.pagina ?? p.ia?.diapositiva) != null) (p.ia?.pagina ?? p.ia?.diapositiva)!,
    ];

const int _maxFragmento = 55000;

({int desde, int hasta})? _rango(List<int> paginas, [int margen = 1]) {
  if (paginas.isEmpty) return null;
  final ord = [...paginas]..sort();
  final med = ord[ord.length ~/ 2];
  final cerca = ord.where((p) => (p - med).abs() <= 3).toList();
  return (desde: math.max(1, cerca.first - margen), hasta: cerca.last + margen);
}

Set<String> _raices(String s) => RegExp('[a-z0-9ñ]{4,}').allMatches(_plano(s)).map((m) => m[0]!.substring(0, 5)).toSet();

/// El fragmento del documento: las páginas de los párrafos (con margen) o las secciones que más
/// palabras comparten, alrededor de la mejor. Acotado a ~55.000 caracteres.
List<Seccion> fragmentoParaTema(List<Seccion> secciones, List<int> paginas, String texto) {
  final r = _rango(paginas);
  var elegidas = <Seccion>[];
  if (r != null && secciones.any((s) => s.pagina != null)) {
    elegidas = secciones.where((s) => s.pagina != null && s.pagina! >= r.desde && s.pagina! <= r.hasta).toList();
  }
  if (elegidas.isEmpty) {
    final total = secciones.fold<int>(0, (n, s) => n + s.texto.length);
    if (total <= _maxFragmento || secciones.isEmpty) return secciones;
    final raices = _raices(texto);
    final puntos = [
      for (final s in secciones) _raices('${s.titulo ?? ''} ${s.texto}').where(raices.contains).length,
    ];
    final mejor = puntos.indexOf(puntos.reduce(math.max));
    var a = mejor, b = mejor;
    var chars = secciones[mejor].texto.length;
    for (;;) {
      final izq = a > 0 ? puntos[a - 1] : -1;
      final der = b < secciones.length - 1 ? puntos[b + 1] : -1;
      final sig = der >= izq ? b + 1 : a - 1;
      if ((izq <= 0 && der <= 0) || sig < 0 || sig >= secciones.length) break;
      if (chars + secciones[sig].texto.length > _maxFragmento) break;
      chars += secciones[sig].texto.length;
      if (sig > b) {
        b = sig;
      } else {
        a = sig;
      }
    }
    elegidas = secciones.sublist(a, b + 1);
  }
  while (elegidas.length > 1 && elegidas.fold<int>(0, (n, s) => n + s.texto.length) > _maxFragmento) {
    elegidas = elegidas.length.isOdd ? elegidas.sublist(1) : elegidas.sublist(0, elegidas.length - 1);
  }
  return elegidas;
}

/// El fragmento de un tema (el documento de la app no va tema a tema: se busca en todo él).
List<Seccion> fragmentoDeTema(List<Seccion> secciones, String tema, List<ParrafoBorrador> ps) =>
    fragmentoParaTema(secciones, paginasDe(ps), '$tema ${ps.map((p) => p.texto).join(' ')}');

/// Para rehacer un párrafo: su página ±1 o, si no se sabe, el fragmento de su tema.
List<Seccion> fragmentoDeParrafo(List<Seccion> secciones, ParrafoBorrador p, List<ParrafoBorrador> delTema) {
  final pagina = p.ia?.pagina ?? p.ia?.diapositiva;
  if (pagina == null) return fragmentoDeTema(secciones, p.tema, delTema);
  return fragmentoParaTema(secciones, [pagina], '${p.tema} ${p.texto}');
}

/// Cuántas páginas tiene un fragmento (las distintas; sin páginas, sus secciones). Al menos 1.
int paginasDeFragmento(List<Seccion> secciones) {
  final pags = {for (final s in secciones) if (s.pagina != null) s.pagina!};
  return math.max(1, pags.isNotEmpty ? pags.length : secciones.length);
}

ParrafoBorrador _con(ParrafoBorrador p, {String? key, String? texto, List<Hueco>? huecos, bool? incluir, bool? nuevo, OrigenParrafo? ia, bool quitarIa = false, String? doc, bool? incluirParecido}) =>
    ParrafoBorrador(
      key: key ?? p.key,
      tema: p.tema,
      texto: texto ?? p.texto,
      huecos: huecos ?? p.huecos,
      incluir: incluir ?? p.incluir,
      grupo: p.grupo,
      ia: quitarIa ? ia : (ia ?? p.ia),
      doc: doc ?? p.doc,
      incluirParecido: incluirParecido ?? p.incluirParecido,
      nuevo: nuevo ?? p.nuevo,
    );

/// Mete los párrafos nuevos de un tema justo después del último de ese tema, marcados como nuevos y
/// con el `doc` de los del tema (el tope de texto original es por documento). No muta `lista`.
({List<ParrafoBorrador> lista, String? primera}) insertarNuevos(
  List<ParrafoBorrador> lista,
  String grupo,
  String tema,
  List<ParrafoBorrador> nuevos,
  String sello,
) {
  if (nuevos.isEmpty) return (lista: lista, primera: null);
  final usadas = lista.map((p) => p.key).toSet();
  final doc = lista.where((p) => _delTema(p, grupo, tema) && p.doc != null).map((p) => p.doc).firstOrNull;
  var n = 0;
  String clave() {
    var k = 'm$sello-${n++}';
    while (usadas.contains(k)) {
      k = 'm$sello-${n++}';
    }
    usadas.add(k);
    return k;
  }

  final aMeter = [
    for (final p in nuevos)
      ParrafoBorrador(
        key: clave(),
        tema: tema,
        texto: p.texto,
        huecos: p.huecos,
        incluir: true,
        grupo: grupo.isEmpty ? null : grupo,
        ia: p.ia,
        doc: doc,
        nuevo: true,
      ),
  ];
  var ultima = -1;
  for (var i = 0; i < lista.length; i++) {
    if (_delTema(lista[i], grupo, tema)) ultima = i;
  }
  return (
    lista: ultima < 0 ? [...lista, ...aMeter] : [...lista.sublist(0, ultima + 1), ...aMeter, ...lista.sublist(ultima + 1)],
    primera: aMeter.first.key,
  );
}

/// La versión rehecha EN SU SITIO: texto, huecos y origen nuevos; misma clave, tema, documento e «incluir».
List<ParrafoBorrador> rehacerEnSitio(List<ParrafoBorrador> lista, String key, ParrafoBorrador nuevo) => [
      for (final p in lista)
        p.key == key ? _con(p, texto: nuevo.texto, huecos: nuevo.huecos, ia: nuevo.ia, quitarIa: true, incluirParecido: false, nuevo: false) : p,
    ];

/// «Deshacer»: vuelve la versión anterior; «incluir» se queda como esté.
List<ParrafoBorrador> deshacerEnSitio(List<ParrafoBorrador> lista, String key, ParrafoBorrador anterior) => [
      for (final p in lista) p.key == key ? _con(anterior, key: key, incluir: p.incluir, nuevo: false) : p,
    ];

/// «+3 nuevos · 2 quitados por repetir uno que ya tenías».
String textoMas(int nuevos, int quitados) {
  final base = '+$nuevos ${nuevos == 1 ? 'nuevo' : 'nuevos'}';
  return quitados > 0 ? '$base · $quitados ${quitados == 1 ? 'quitado' : 'quitados'} por repetir uno que ya tenías' : base;
}
