// Biblioteca sobre las carpetas del material: la parte pura, sin red ni Flutter.
// Puerto de la web: src/lib/carpetas/biblioteca.ts y src/lib/carpetas/dominio.ts. Los datos vienen de
// GET /api/carpetas/{recuento, sin-clasificar, asignatura/:id, asignatura/:id/dominio}.
//
// «Juntos pero no revueltos»: las preguntas MIR y el material propio se enseñan uno al lado del otro,
// pero sus cifras nunca se mezclan. La señal de dominio es solo del material (flashcards y resúmenes).

import '../services/carpetas.dart';

enum TipoElemento {
  mapa('mapa'),
  flashcards('flashcards'),
  resumenes('resumenes');

  final String valor;
  const TipoElemento(this.valor);

  static TipoElemento? de(Object? v) => switch (v) {
        'mapa' => TipoElemento.mapa,
        'flashcards' => TipoElemento.flashcards,
        'resumenes' => TipoElemento.resumenes,
        _ => null,
      };
}

int _n(Object? v) => v is num && v >= 0 ? v.toInt() : 0;

class Cuenta {
  final int total;
  final int mapas;
  final int flashcards;
  final int resumenes;
  const Cuenta({this.total = 0, this.mapas = 0, this.flashcards = 0, this.resumenes = 0});

  static const vacia = Cuenta();

  factory Cuenta.fromJson(Object? j) => j is Map
      ? Cuenta(total: _n(j['total']), mapas: _n(j['mapas']), flashcards: _n(j['flashcards']), resumenes: _n(j['resumenes']))
      : vacia;
}

class RecuentoAsignatura {
  final int id;
  final Cuenta cuenta;
  final Cuenta general;
  final Map<int, Cuenta> temas;
  const RecuentoAsignatura({required this.id, required this.cuenta, required this.general, required this.temas});
}

class Recuento {
  final int total;
  final Cuenta sinClasificar;
  final List<RecuentoAsignatura> asignaturas;
  const Recuento({required this.total, required this.sinClasificar, required this.asignaturas});

  factory Recuento.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    final asigs = <RecuentoAsignatura>[];
    for (final a in (m['asignaturas'] is List ? m['asignaturas'] as List : const [])) {
      if (a is! Map || a['id'] is! int) continue;
      asigs.add(RecuentoAsignatura(
        id: a['id'] as int,
        cuenta: Cuenta.fromJson(a),
        general: Cuenta.fromJson(a['general']),
        temas: {
          for (final t in (a['temas'] is List ? a['temas'] as List : const []))
            if (t is Map && t['id'] is int) t['id'] as int: Cuenta.fromJson(t),
        },
      ));
    }
    return Recuento(total: _n(m['total']), sinClasificar: Cuenta.fromJson(m['sinClasificar']), asignaturas: asigs);
  }
}

/// Un mapa o un grupo de flashcards o de resúmenes, con la carpeta en la que se enseña.
class ElementoMaterial {
  final TipoElemento tipo;
  final String id;
  final String titulo;
  final DateTime? actualizado;
  final Carpeta carpeta;

  /// Tarjetas o párrafos del grupo; null en un mapa.
  final int? elementos;

  /// Solo en «Sin clasificar»: con qué textos se sugiere la carpeta.
  final ({String? descripcion, List<String> etiquetas, List<String> fuentes})? textos;

  const ElementoMaterial({
    required this.tipo,
    required this.id,
    required this.titulo,
    this.actualizado,
    this.carpeta = Carpeta.sinClasificar,
    this.elementos,
    this.textos,
  });

  static ElementoMaterial? fromJson(Object? j) {
    if (j is! Map) return null;
    final tipo = TipoElemento.de(j['tipo']);
    if (tipo == null || j['id'] == null) return null;
    final c = j['carpeta'] is Map ? j['carpeta'] as Map : const {};
    final t = j['textos'];
    List<String> lista(Object? v) => v is List ? v.whereType<String>().toList() : const [];
    return ElementoMaterial(
      tipo: tipo,
      id: '${j['id']}',
      titulo: j['titulo'] is String && (j['titulo'] as String).trim().isNotEmpty
          ? j['titulo'] as String
          : (tipo == TipoElemento.mapa ? 'Mapa sin título' : 'Grupo sin nombre'),
      actualizado: j['actualizado'] is String ? DateTime.tryParse(j['actualizado'] as String) : null,
      carpeta: Carpeta(
        subjectId: c['subjectId'] is int ? c['subjectId'] as int : null,
        topicId: c['topicId'] is int ? c['topicId'] as int : null,
      ),
      elementos: tipo == TipoElemento.mapa ? null : _n(j['elementos']),
      textos: t is Map
          ? (
              descripcion: t['descripcion'] is String ? t['descripcion'] as String : null,
              etiquetas: lista(t['etiquetas']),
              fuentes: lista(t['fuentes']),
            )
          : null,
    );
  }
}

Cuenta cuentaDe(Iterable<ElementoMaterial> elementos) {
  var m = 0, f = 0, r = 0;
  for (final e in elementos) {
    switch (e.tipo) {
      case TipoElemento.mapa:
        m++;
      case TipoElemento.flashcards:
        f++;
      case TipoElemento.resumenes:
        r++;
    }
  }
  return Cuenta(total: m + f + r, mapas: m, flashcards: f, resumenes: r);
}

/// «2 mapas · 1 grupo de flashcards · 3 grupos de resúmenes». Vacío si no hay nada.
String textoCuenta(Cuenta c) {
  String grupos(int n, String de) => '$n ${n == 1 ? 'grupo' : 'grupos'} de $de';
  return [
    if (c.mapas > 0) '${c.mapas} ${c.mapas == 1 ? 'mapa' : 'mapas'}',
    if (c.flashcards > 0) grupos(c.flashcards, 'flashcards'),
    if (c.resumenes > 0) grupos(c.resumenes, 'resúmenes'),
  ].join(' · ');
}

class TarjetaAsignatura {
  final AsignaturaCatalogo asignatura;
  final Cuenta cuenta;

  /// Temas con material (sin contar «General»).
  final int temasConMaterial;
  final bool tieneGeneral;
  const TarjetaAsignatura({required this.asignatura, required this.cuenta, required this.temasConMaterial, required this.tieneGeneral});

  int get carpetas => temasConMaterial + (tieneGeneral ? 1 : 0);
}

/// La portada: TODAS las asignaturas visibles, en el orden del catálogo, con lo que el usuario tiene en cada una.
List<TarjetaAsignatura> tarjetasAsignaturas(List<AsignaturaCatalogo> arbol, Recuento? recuento) {
  final porId = {for (final a in recuento?.asignaturas ?? const <RecuentoAsignatura>[]) a.id: a};
  return [
    for (final a in arbol)
      TarjetaAsignatura(
        asignatura: a,
        cuenta: porId[a.id]?.cuenta ?? Cuenta.vacia,
        temasConMaterial: porId[a.id]?.temas.values.where((t) => t.total > 0).length ?? 0,
        tieneGeneral: (porId[a.id]?.general.total ?? 0) > 0,
      ),
  ];
}

class CarpetaBiblioteca {
  /// null = «General» de la asignatura.
  final int? topicId;
  final String nombre;
  final List<ElementoMaterial> elementos;
  const CarpetaBiblioteca({required this.topicId, required this.nombre, required this.elementos});

  Cuenta get cuenta => cuentaDe(elementos);
}

/// Las carpetas que se enseñan de una asignatura: «General» primero y después los temas en el orden del
/// catálogo, pero SOLO los que tienen material. Un tema que ya no está en el catálogo cuenta como «General».
List<CarpetaBiblioteca> carpetasDeAsignatura(AsignaturaCatalogo asig, List<ElementoMaterial> elementos) {
  final temas = {for (final t in asig.temas) t.id};
  final porTema = <int?, List<ElementoMaterial>>{};
  for (final e in elementos) {
    if (e.carpeta.subjectId != asig.id) continue;
    final t = e.carpeta.topicId != null && temas.contains(e.carpeta.topicId) ? e.carpeta.topicId : null;
    porTema.putIfAbsent(t, () => []).add(e);
  }
  return [
    if (porTema[null] != null) CarpetaBiblioteca(topicId: null, nombre: 'General', elementos: porTema[null]!),
    for (final t in asig.temas)
      if (porTema[t.id] != null) CarpetaBiblioteca(topicId: t.id, nombre: t.nombre, elementos: porTema[t.id]!),
  ];
}

/// La carpeta que se propone para algo sin clasificar, con el mismo emparejador que al crear: título,
/// descripción, temas de sus tarjetas o párrafos y documento de origen. null si no hay nada claro.
/// Nunca se aplica sola: es el atajo «¿A …?».
Carpeta? sugerenciaDe(List<AsignaturaCatalogo> arbol, ElementoMaterial e) {
  final t = e.textos;
  final s = sugerirCarpeta(
    arbol,
    textosDocumento(e.titulo, [
      [t?.descripcion],
      t?.etiquetas ?? const [],
      t?.fuentes ?? const [],
    ]),
  );
  return s.carpeta.subjectId == null ? null : s.carpeta;
}

/// Para mover una selección mezclada: el servidor mueve un tipo cada vez.
Map<TipoElemento, List<String>> agruparPorTipo(Iterable<ElementoMaterial> seleccion) {
  final m = <TipoElemento, List<String>>{};
  for (final e in seleccion) {
    m.putIfAbsent(e.tipo, () => []).add(e.id);
  }
  return m;
}

/// «Flashcards · 12 tarjetas · 3 oct»: la línea de detalle de una fila de material.
String detalleElemento(ElementoMaterial e) {
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
  final nombre = switch (e.tipo) {
    TipoElemento.mapa => 'Mapa',
    TipoElemento.flashcards => 'Flashcards',
    TipoElemento.resumenes => 'Resumen',
  };
  final n = e.elementos;
  final cuantos = n == null
      ? null
      : e.tipo == TipoElemento.flashcards
          ? '$n ${n == 1 ? 'tarjeta' : 'tarjetas'}'
          : '$n ${n == 1 ? 'párrafo' : 'párrafos'}';
  final d = e.actualizado?.toLocal();
  return [nombre, if (cuantos != null) cuantos, if (d != null) '${d.day} ${meses[d.month - 1]}'].join(' · ');
}

/// Lo de una asignatura: el catálogo, cuántas preguntas MIR tiene (en total y por tema) y el material.
class DatosAsignatura {
  final AsignaturaCatalogo asignatura;
  final int preguntasTotal;
  final Map<int, int> preguntasPorTema;
  final List<ElementoMaterial> elementos;
  const DatosAsignatura({
    required this.asignatura,
    required this.preguntasTotal,
    required this.preguntasPorTema,
    required this.elementos,
  });

  /// Preguntas de un tema, o de toda la asignatura con `topicId` null («General»).
  int preguntasDe(int? topicId) => topicId == null ? preguntasTotal : (preguntasPorTema[topicId] ?? 0);

  static DatosAsignatura? fromJson(Object? j) {
    if (j is! Map) return null;
    final asig = AsignaturaCatalogo.fromJson(j['asignatura']);
    if (asig == null) return null;
    final p = j['preguntas'] is Map ? j['preguntas'] as Map : const {};
    final pt = p['porTema'] is Map ? p['porTema'] as Map : const {};
    return DatosAsignatura(
      asignatura: asig,
      preguntasTotal: _n(p['total']),
      preguntasPorTema: {
        for (final e in pt.entries)
          if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): _n(e.value),
      },
      elementos: (j['elementos'] is List ? j['elementos'] as List : const [])
          .map(ElementoMaterial.fromJson)
          .whereType<ElementoMaterial>()
          .toList(),
    );
  }
}

// ---- Señal de dominio del material (fase 3) ---------------------------------------------------

double? _fraccion(Object? v) => v is num ? v.toDouble().clamp(0.0, 1.0) : null;
DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v) : null;

class DominioGrupo {
  final String deckId;
  final TipoElemento tipo;
  final int elementos;
  final int estudiados;
  final double? dominio;
  final double? cobertura;
  final DateTime? ultimoRepaso;
  const DominioGrupo({
    required this.deckId,
    required this.tipo,
    required this.elementos,
    required this.estudiados,
    this.dominio,
    this.cobertura,
    this.ultimoRepaso,
  });
}

class HuecoDebil {
  final String texto;
  final int fallos;
  final int intentos;
  final bool falladoAhora;
  const HuecoDebil({required this.texto, required this.fallos, required this.intentos, this.falladoAhora = false});
}

class DominioCarpeta {
  /// null = «General».
  final int? topicId;
  final int elementos;
  final int estudiados;

  /// Probabilidad media de recordar hoy, 0-1 (lo no estudiado cuenta 0); null sin elementos.
  final double? dominio;

  /// Estudiados / elementos, 0-1; null sin elementos.
  final double? cobertura;
  final DateTime? ultimoRepaso;
  final List<DominioGrupo> grupos;
  final List<HuecoDebil> huecosDebiles;
  const DominioCarpeta({
    required this.topicId,
    required this.elementos,
    required this.estudiados,
    this.dominio,
    this.cobertura,
    this.ultimoRepaso,
    this.grupos = const [],
    this.huecosDebiles = const [],
  });
}

class RespuestaDominio {
  final bool disponible;
  final List<DominioCarpeta> carpetas;
  const RespuestaDominio({required this.disponible, required this.carpetas});

  static const noDisponible = RespuestaDominio(disponible: false, carpetas: []);

  factory RespuestaDominio.fromJson(Object? j) {
    if (j is! Map) return noDisponible;
    final out = <DominioCarpeta>[];
    for (final c in (j['carpetas'] is List ? j['carpetas'] as List : const [])) {
      if (c is! Map) continue;
      out.add(DominioCarpeta(
        topicId: c['topicId'] is int ? c['topicId'] as int : null,
        elementos: _n(c['elementos']),
        estudiados: _n(c['estudiados']),
        dominio: _fraccion(c['dominio']),
        cobertura: _fraccion(c['cobertura']),
        ultimoRepaso: _fecha(c['ultimoRepaso']),
        grupos: [
          for (final g in (c['grupos'] is List ? c['grupos'] as List : const []))
            if (g is Map && g['deckId'] != null)
              DominioGrupo(
                deckId: '${g['deckId']}',
                tipo: g['tipo'] == 'resumenes' ? TipoElemento.resumenes : TipoElemento.flashcards,
                elementos: _n(g['elementos']),
                estudiados: _n(g['estudiados']),
                dominio: _fraccion(g['dominio']),
                cobertura: _fraccion(g['cobertura']),
                ultimoRepaso: _fecha(g['ultimoRepaso']),
              ),
        ],
        huecosDebiles: [
          for (final h in (c['huecosDebiles'] is List ? c['huecosDebiles'] as List : const []))
            if (h is Map && h['texto'] is String && (h['texto'] as String).trim().isNotEmpty)
              HuecoDebil(texto: h['texto'] as String, fallos: _n(h['fallos']), intentos: _n(h['intentos']), falladoAhora: h['falladoAhora'] == true),
        ],
      ));
    }
    return RespuestaDominio(disponible: j['disponible'] == true, carpetas: out);
  }

  /// La señal de una carpeta (null = «General»).
  DominioCarpeta? de(int? topicId) {
    for (final c in carpetas) {
      if (c.topicId == topicId) return c;
    }
    return null;
  }
}

/// Cuándo un tema está «bien llevado»: dominio ≥ 80 % Y cobertura ≥ 70 % (lo mismo que la web).
const umbralBienLlevado = (dominio: 0.8, cobertura: 0.7);

enum EstadoDominio { bien, enMarcha, sinEstudiar, vacio }

EstadoDominio estadoDominio({required int elementos, required int estudiados, double? dominio, double? cobertura}) {
  if (elementos == 0 || dominio == null || cobertura == null) return EstadoDominio.vacio;
  if (estudiados == 0) return EstadoDominio.sinEstudiar;
  return dominio >= umbralBienLlevado.dominio && cobertura >= umbralBienLlevado.cobertura ? EstadoDominio.bien : EstadoDominio.enMarcha;
}

EstadoDominio estadoCarpeta(DominioCarpeta? d) =>
    d == null ? EstadoDominio.vacio : estadoDominio(elementos: d.elementos, estudiados: d.estudiados, dominio: d.dominio, cobertura: d.cobertura);

EstadoDominio estadoGrupo(DominioGrupo? g) =>
    g == null ? EstadoDominio.vacio : estadoDominio(elementos: g.elementos, estudiados: g.estudiados, dominio: g.dominio, cobertura: g.cobertura);

/// Un porcentaje entero (0,7234 → 72).
int porcentajeDe(double f) => (f.clamp(0.0, 1.0) * 100).round();

/// «recordarías hoy ~72 %».
String textoRecordarias(double dominio) => 'recordarías hoy ~${porcentajeDe(dominio)} %';

/// «hoy», «ayer», «hace 3 días», «hace 2 semanas» o la fecha («12 sept»), en días de calendario.
String? haceCuanto(DateTime? fecha, {DateTime? ahora}) {
  if (fecha == null) return null;
  final hoy = (ahora ?? DateTime.now()).toLocal();
  final d = fecha.toLocal();
  final dias = DateTime.utc(hoy.year, hoy.month, hoy.day).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (dias <= 0) return 'hoy';
  if (dias == 1) return 'ayer';
  if (dias < 14) return 'hace $dias días';
  if (dias < 60) return 'hace ${dias ~/ 7} semanas';
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];
  return '${d.day} ${meses[d.month - 1]}${d.year != hoy.year ? ' ${d.year}' : ''}';
}

/// Color del acierto en preguntas (escala de las preguntas MIR, no la del dominio): verde, ámbar o rojo.
enum TonoAcierto { bien, regular, mal }

TonoAcierto tonoAcierto(double p) => p >= 70 ? TonoAcierto.bien : (p >= 50 ? TonoAcierto.regular : TonoAcierto.mal);
