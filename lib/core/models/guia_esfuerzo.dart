// «Esfuerzo frente a recompensa» de una guía: escalas, puntos y dónde va el nombre de cada tema, sin
// Flutter. Puerto del cálculo de src/components/library/guide/GuideEffortMatrix.tsx (que dibuja un SVG
// de 640×400): mismas escalas, mismos candidatos y la misma búsqueda con vuelta atrás para que los
// nombres no se pisen. La app pinta este diseño en un CustomPainter con las mismas coordenadas.

import 'guias.dart';

const esfuerzoAncho = 640.0;
const esfuerzoAlto = 400.0;
const esfuerzoPad = (top: 20.0, right: 24.0, bottom: 48.0, left: 52.0);

class _Escala {
  final double minPages, pageStep, minQuestions, questionStep, splitPages, splitQuestions, labelMin;
  const _Escala(this.minPages, this.pageStep, this.minQuestions, this.questionStep, this.splitPages, this.splitQuestions, this.labelMin);
}

const _normal = _Escala(28, 7, 20, 10, 12, 10, 6);

/// Asignaturas pequeñas (menos de 6 preguntas al año de media): cada eje se ajusta a sus datos.
const _pequenaPorAnio = 6;

_Escala _pequena(double topPages, double topQuestions) {
  final cortos = topPages <= _normal.minPages / 2;
  final paso = topQuestions <= 10 ? 2.0 : 4.0;
  // El tema más preguntado, como mucho al 85 % del eje (por debajo de los rótulos de los cuadrantes).
  var maxQ = paso;
  while (topQuestions * 20 > maxQ * 17) {
    maxQ += paso;
  }
  if (maxQ < 10) maxQ = 10;
  return _Escala(cortos ? 10 : _normal.minPages, cortos ? 2 : _normal.pageStep, maxQ, paso, cortos ? 5 : _normal.splitPages, maxQ / 2, 3);
}

enum AnclaTexto { inicio, fin, medio }

class DesplazamientoEtiqueta {
  final double dx, dy;
  final AnclaTexto ancla;
  const DesplazamientoEtiqueta(this.dx, this.dy, this.ancla);
}

/// Posiciones candidatas, en orden de preferencia.
const candidatosEtiqueta = <DesplazamientoEtiqueta>[
  DesplazamientoEtiqueta(12, 4, AnclaTexto.inicio),
  DesplazamientoEtiqueta(-12, 4, AnclaTexto.fin),
  DesplazamientoEtiqueta(0, -13, AnclaTexto.medio),
  DesplazamientoEtiqueta(0, 22, AnclaTexto.medio),
  DesplazamientoEtiqueta(12, -8, AnclaTexto.inicio),
  DesplazamientoEtiqueta(-12, -8, AnclaTexto.fin),
  DesplazamientoEtiqueta(12, 16, AnclaTexto.inicio),
  DesplazamientoEtiqueta(-12, 16, AnclaTexto.fin),
  DesplazamientoEtiqueta(12, -20, AnclaTexto.inicio),
  DesplazamientoEtiqueta(-12, -20, AnclaTexto.fin),
  DesplazamientoEtiqueta(12, 28, AnclaTexto.inicio),
  DesplazamientoEtiqueta(-12, 28, AnclaTexto.fin),
];

class Caja {
  final double x1, y1, x2, y2;
  const Caja(this.x1, this.y1, this.x2, this.y2);
  bool pisa(Caja o) => x1 < o.x2 && o.x1 < x2 && y1 < o.y2 && o.y1 < y2;
}

const _fuenteEtiqueta = 12.0;
const _anchoLetra = 7.4;

Caja cajaEtiqueta(double cx, double cy, DesplazamientoEtiqueta o, String texto) {
  final ancho = texto.length * _anchoLetra + 2;
  final x = cx + o.dx;
  final x1 = switch (o.ancla) {
    AnclaTexto.inicio => x,
    AnclaTexto.fin => x - ancho,
    AnclaTexto.medio => x - ancho / 2,
  };
  final base = cy + o.dy;
  return Caja(x1, base - _fuenteEtiqueta, x1 + ancho, base + 4);
}

class PuntoEsfuerzo {
  final GuideTopicWithStats tema;
  final double cx, cy, r;

  /// Con nombre visible en reposo (los menores solo al tocarlos).
  final bool mayor;
  final DesplazamientoEtiqueta etiqueta;
  const PuntoEsfuerzo(this.tema, this.cx, this.cy, this.r, this.mayor, this.etiqueta);
}

class DisenoEsfuerzo {
  final double splitX, splitY;
  final List<(double valor, double x)> marcasX;
  final List<(double valor, double y)> marcasY;
  final List<PuntoEsfuerzo> puntos;
  final double pocoRentableY, pasadaRapidaY;

  /// «← 3 temas menores», o null si no hay.
  final String? textoMenores;
  final double menoresX, menoresY;

  const DisenoEsfuerzo({
    required this.splitX,
    required this.splitY,
    required this.marcasX,
    required this.marcasY,
    required this.puntos,
    required this.pocoRentableY,
    required this.pasadaRapidaY,
    required this.textoMenores,
    required this.menoresX,
    required this.menoresY,
  });
}

DisenoEsfuerzo disenoEsfuerzo(List<GuideTopicWithStats> temas) {
  const pad = esfuerzoPad;
  final topPages = temas.map((t) => t.topic.pages.toDouble()).fold(0.0, (a, b) => a > b ? a : b);
  final topQuestions = temas.map((t) => t.stats.totalCount.toDouble()).fold(0.0, (a, b) => a > b ? a : b);
  final periodoTotal = temas.fold(0, (a, t) => a + t.stats.totalCount);
  final anios = temas.isEmpty || temas.first.perYear.isEmpty ? 1 : temas.first.perYear.length;
  final e = periodoTotal < _pequenaPorAnio * anios ? _pequena(topPages, topQuestions) : _normal;

  final maxPages = [e.minPages, (topPages / e.pageStep).ceil() * e.pageStep].reduce((a, b) => a > b ? a : b);
  var maxQuestions = [e.minQuestions, (topQuestions / e.questionStep).ceil() * e.questionStep].reduce((a, b) => a > b ? a : b);
  while (topQuestions * 20 > maxQuestions * 17) {
    maxQuestions += e.questionStep;
  }

  double x(double pages) => pad.left + (pages / maxPages) * (esfuerzoAncho - pad.left - pad.right);
  double y(double q) => esfuerzoAlto - pad.bottom - (q / maxQuestions) * (esfuerzoAlto - pad.top - pad.bottom);

  final marcasX = [for (var i = 0; i <= (maxPages / e.pageStep).round(); i++) (i * e.pageStep, x(i * e.pageStep))];
  final marcasY = [for (var i = 0; i <= (maxQuestions / e.questionStep).round(); i++) (i * e.questionStep, y(i * e.questionStep))];
  final ratio = e.minPages / _normal.minPages;
  final splitX = x(e.splitPages);
  final splitY = y(e.splitQuestions);
  final menores = temas.where((t) => t.stats.totalCount < e.labelMin).length;

  // Separa los puntos que caen exactamente en el mismo sitio.
  final mismoSitio = <String, List<String>>{};
  for (final t in temas) {
    mismoSitio.putIfAbsent('${t.topic.pages}|${t.stats.totalCount}', () => []).add(t.id);
  }
  final base = [
    for (final t in temas)
      () {
        final grupo = mismoSitio['${t.topic.pages}|${t.stats.totalCount}']!;
        final empuje = grupo.length > 1 ? (grupo.indexOf(t.id) - (grupo.length - 1) / 2) * 0.7 : 0.0;
        final mayor = t.stats.totalCount >= e.labelMin;
        return (tema: t, cx: x(t.topic.pages + empuje), cy: y(t.stats.totalCount.toDouble()), r: mayor ? 8.0 : 5.5, mayor: mayor);
      }(),
  ];
  final cajasPunto = [for (final p in base) (id: p.tema.id, caja: Caja(p.cx - p.r, p.cy - p.r, p.cx + p.r, p.cy + p.r))];

  Caja cajaTexto(double tx, double ty, String texto, bool inicio, [double size = 12]) {
    final ancho = texto.length * size * 0.6;
    final x1 = inicio ? tx : tx - ancho;
    return Caja(x1, ty - size, x1 + ancho, ty + 4);
  }

  // Los rótulos de los cuadrantes de abajo bajan al pie si tienen algún punto encima.
  double bajo(double tx, String texto) {
    final c = cajaTexto(tx, splitY + 22, texto, false);
    return cajasPunto.any((pb) => c.pisa(pb.caja)) ? esfuerzoAlto - pad.bottom - 8 : splitY + 22;
  }

  final pocoRentableY = bajo(esfuerzoAncho - pad.right - 10, 'Poco rentable');
  final pasadaRapidaY = bajo(splitX - 10, 'Pasada rápida');
  final fijas = [
    cajaTexto(pad.left + 10, pad.top + 18, 'Máxima rentabilidad', true),
    cajaTexto(pad.left + 10, pad.top + 33, 'poco temario, muchas preguntas', true, 10.5),
    cajaTexto(esfuerzoAncho - pad.right - 10, pad.top + 18, 'Pilares', false),
    cajaTexto(esfuerzoAncho - pad.right - 10, pad.top + 33, 'mucho temario, pero cae siempre', false, 10.5),
    cajaTexto(esfuerzoAncho - pad.right - 10, pocoRentableY, 'Poco rentable', false),
    cajaTexto(splitX - 10, pasadaRapidaY, 'Pasada rápida', false),
  ];
  bool dentro(Caja c) => c.x1 >= pad.left + 2 && c.x2 <= esfuerzoAncho - pad.right && c.y1 >= pad.top && c.y2 <= esfuerzoAlto - pad.bottom;

  int choques(({GuideTopicWithStats tema, double cx, double cy, double r, bool mayor}) p, DesplazamientoEtiqueta o, List<Caja> puestas) {
    final c = cajaEtiqueta(p.cx, p.cy, o, p.tema.shortName);
    return (dentro(c) ? 0 : 10) +
        puestas.where(c.pisa).length * 3 +
        cajasPunto.where((pb) => pb.id != p.tema.id && c.pisa(pb.caja)).length * 2 +
        fijas.where(c.pisa).length * 3;
  }

  // Nombres visibles (de mayor a menor peso): búsqueda con vuelta atrás del reparto con menos choques.
  final porPeso = ordenEstable(base, (a, b) {
    final c = (b.mayor ? 1 : 0) - (a.mayor ? 1 : 0);
    return c != 0 ? c : b.tema.stats.totalCount.compareTo(a.tema.stats.totalCount);
  });
  final mayores = porPeso.where((p) => p.mayor).toList();
  var mejor = (offsets: <DesplazamientoEtiqueta>[], coste: 1 << 30);
  final actual = <DesplazamientoEtiqueta>[];
  final cajasActuales = <Caja>[];
  var intentos = 0;
  void buscar(int i, int coste) {
    if (coste >= mejor.coste || intentos > 3000) return;
    if (i == mayores.length) {
      mejor = (offsets: [...actual], coste: coste);
      return;
    }
    intentos++;
    final p = mayores[i];
    final opciones = ordenEstable(
      [for (final o in candidatosEtiqueta) (o: o, c: choques(p, o, cajasActuales))],
      (a, b) => a.c.compareTo(b.c),
    );
    for (final op in opciones) {
      actual.add(op.o);
      cajasActuales.add(cajaEtiqueta(p.cx, p.cy, op.o, p.tema.shortName));
      buscar(i + 1, coste + op.c);
      actual.removeLast();
      cajasActuales.removeLast();
      if (mejor.coste == 0) return;
    }
  }

  buscar(0, 0);

  final etiquetas = <String, DesplazamientoEtiqueta>{};
  final visibles = <Caja>[];
  for (var i = 0; i < mayores.length; i++) {
    final o = i < mejor.offsets.length ? mejor.offsets[i] : candidatosEtiqueta.first;
    etiquetas[mayores[i].tema.id] = o;
    visibles.add(cajaEtiqueta(mayores[i].cx, mayores[i].cy, o, mayores[i].tema.shortName));
  }
  // Los menores, uno a uno en su mejor sitio.
  final puestas = [...visibles];
  for (final p in porPeso.where((p) => !p.mayor)) {
    var elegido = candidatosEtiqueta.first;
    for (final o in candidatosEtiqueta) {
      if (choques(p, o, puestas) < choques(p, elegido, puestas)) elegido = o;
    }
    etiquetas[p.tema.id] = elegido;
    puestas.add(cajaEtiqueta(p.cx, p.cy, elegido, p.tema.shortName));
  }

  // Aviso de temas menores: en su sitio o desplazado a la derecha hasta quedar libre.
  final textoMenores = '← $menores ${menores == 1 ? 'tema menor' : 'temas menores'}';
  final menoresY = y(2 * ratio) + 4;
  var menoresX = x(6.8 * ratio);
  for (var dx = 0.0; dx < esfuerzoAncho; dx += 4) {
    final c = cajaTexto(x(6.8 * ratio) + dx, menoresY, textoMenores, true, 11);
    final libre = !cajasPunto.any((pb) => c.pisa(pb.caja)) && !visibles.any(c.pisa) && !fijas.any(c.pisa);
    if (libre && c.x2 <= esfuerzoAncho - pad.right) {
      menoresX = c.x1;
      break;
    }
  }

  return DisenoEsfuerzo(
    splitX: splitX,
    splitY: splitY,
    marcasX: marcasX,
    marcasY: marcasY,
    puntos: [for (final p in base) PuntoEsfuerzo(p.tema, p.cx, p.cy, p.r, p.mayor, etiquetas[p.tema.id]!)],
    pocoRentableY: pocoRentableY,
    pasadaRapidaY: pasadaRapidaY,
    textoMenores: menores > 0 ? textoMenores : null,
    menoresX: menoresX,
    menoresY: menoresY,
  );
}
