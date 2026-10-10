// Filtros, búsqueda y orden de los párrafos de un grupo (lo puro, sin UI).
// La búsqueda es sin tildes ni mayúsculas y todas las palabras tienen que
// aparecer. Puerto de la web: src/lib/resumenes/grupo.ts.

import '../../core/models/resumen.dart';

/// Quita tildes y mayúsculas y normaliza espacios. Suficiente para el texto
/// médico en español (la web usa NFD + borrar marcas; aquí, un mapa explícito).
String normalizarResumen(String s) {
  final buf = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    buf.write(_sinTilde[c] ?? c);
  }
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const Map<String, String> _sinTilde = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  'Á': 'a', 'É': 'e', 'Í': 'i', 'Ó': 'o', 'Ú': 'u', 'Ü': 'u', 'Ñ': 'n',
};

/// Las palabras de una búsqueda, normalizadas y sin repetir.
List<String> terminosDe(String busqueda) {
  return normalizarResumen(busqueda).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet().toList();
}

String temaDe(Parrafo p) => (p.tema ?? '').trim();

/// «Toca repasar»: lo mismo que pinta la tarjeta (los nuevos no cuentan).
bool tocaRepasar(Parrafo p) => p.due == true && p.status != EstadoParrafoSrs.new_;

/// ¿Coincide el párrafo con la búsqueda? Todos los términos, en el texto o el
/// tema, o (con `soloHuecos`) en alguna de las respuestas de los huecos.
bool coincide(Parrafo p, List<String> terminos, {bool soloHuecos = false}) {
  if (terminos.isEmpty) return true;
  final donde = soloHuecos
      ? p.huecos.map((h) => normalizarResumen(p.texto.substring(h.i, h.f))).toList()
      : [normalizarResumen(p.texto), normalizarResumen(p.tema ?? '')];
  return terminos.every((term) => donde.any((d) => d.contains(term)));
}

class FiltrosGrupo {
  final String busqueda;
  final bool soloHuecos;
  final List<EstadoParrafoSrs> estados;
  final List<int> niveles;
  final bool tocaRepasar;
  final bool conFallados;

  const FiltrosGrupo({
    this.busqueda = '',
    this.soloHuecos = false,
    this.estados = const [],
    this.niveles = const [],
    this.tocaRepasar = false,
    this.conFallados = false,
  });

  bool get activos =>
      terminosDe(busqueda).isNotEmpty || estados.isNotEmpty || niveles.isNotEmpty || tocaRepasar || conFallados;

  FiltrosGrupo copyWith({
    String? busqueda,
    bool? soloHuecos,
    List<EstadoParrafoSrs>? estados,
    List<int>? niveles,
    bool? tocaRepasar,
    bool? conFallados,
  }) =>
      FiltrosGrupo(
        busqueda: busqueda ?? this.busqueda,
        soloHuecos: soloHuecos ?? this.soloHuecos,
        estados: estados ?? this.estados,
        niveles: niveles ?? this.niveles,
        tocaRepasar: tocaRepasar ?? this.tocaRepasar,
        conFallados: conFallados ?? this.conFallados,
      );
}

/// Los párrafos que pasan los filtros, en el mismo orden.
List<Parrafo> filtrarParrafos(List<Parrafo> ps, FiltrosGrupo f) {
  final terminos = terminosDe(f.busqueda);
  return ps.where((p) {
    if (f.estados.isNotEmpty && !f.estados.contains(p.status ?? EstadoParrafoSrs.new_)) return false;
    if (f.niveles.isNotEmpty && !p.huecos.any((h) => f.niveles.contains(h.n))) return false;
    if (f.tocaRepasar && !tocaRepasar(p)) return false;
    if (f.conFallados && (p.huecosFallados?.length ?? 0) == 0) return false;
    return coincide(p, terminos, soloHuecos: f.soloHuecos);
  }).toList();
}

/// Por tema, en el orden en que aparece cada tema por primera vez; dentro, el de llegada.
List<(String, List<Parrafo>)> agruparPorTema(List<Parrafo> ps) {
  final m = <String, List<Parrafo>>{};
  for (final p in ps) {
    final t = temaDe(p);
    (m[t] ??= []).add(p);
  }
  return m.entries.map((e) => (e.key, e.value)).toList();
}

enum OrdenGrupo { documento, fallados, vencer }

DateTime? _fecha(String? s) {
  if (s == null) return null;
  return DateTime.tryParse(s)?.toUtc();
}

/// Ordena (sin tocar la lista que llega):
/// - documento: el de llegada, agrupado por tema.
/// - fallados: más fallos primero; a igualdad, más huecos fallados.
/// - vencer: los que tocan repasar primero, luego por fecha (la más cercana).
List<Parrafo> ordenarParrafos(List<Parrafo> ps, OrdenGrupo orden) {
  final doc = agruparPorTema(ps).expand((e) => e.$2).toList();
  if (orden == OrdenGrupo.documento) return doc;

  final pos = {for (var i = 0; i < doc.length; i++) doc[i].itemId: i};
  int porDoc(Parrafo a, Parrafo b) => pos[a.itemId]!.compareTo(pos[b.itemId]!);

  if (orden == OrdenGrupo.fallados) {
    return [...doc]..sort((a, b) {
        final r = b.fallos.compareTo(a.fallos);
        if (r != 0) return r;
        final h = (b.huecosFallados?.length ?? 0).compareTo(a.huecosFallados?.length ?? 0);
        return h != 0 ? h : porDoc(a, b);
      });
  }

  int grupo(Parrafo p) => tocaRepasar(p)
      ? 0
      : (p.status != EstadoParrafoSrs.new_ && _fecha(p.nextDueAt) != null)
          ? 1
          : 2;
  return [...doc]..sort((a, b) {
      final ga = grupo(a);
      final gb = grupo(b);
      if (ga != gb) return ga.compareTo(gb);
      if (ga == 2) return porDoc(a, b);
      final fa = _fecha(a.nextDueAt);
      final fb = _fecha(b.nextDueAt);
      if (fa != null && fb != null && !fa.isAtSameMomentAs(fb)) return fa.compareTo(fb);
      if (fa == null && fb != null) return 1;
      if (fb == null && fa != null) return -1;
      return porDoc(a, b);
    });
}

/// «vence hoy», «vence mañana», «vence en 5 días», «toca repasar»… (null si no hay fecha).
String? cuandoVence(Parrafo p, [DateTime? ahora]) {
  if (tocaRepasar(p)) return 'Toca repasar';
  final f = _fecha(p.nextDueAt);
  if (f == null || p.status == EstadoParrafoSrs.new_) return null;
  final a = (ahora ?? DateTime.now()).toUtc();
  final diaF = DateTime.utc(f.year, f.month, f.day);
  final diaA = DateTime.utc(a.year, a.month, a.day);
  final dias = diaF.difference(diaA).inDays;
  if (dias <= 0) return 'Vence hoy';
  if (dias == 1) return 'Vence mañana';
  return 'Vence en $dias días';
}

const List<String> _mesesAbrev = ['ene.', 'feb.', 'mar.', 'abr.', 'may.', 'jun.', 'jul.', 'ago.', 'sep.', 'oct.', 'nov.', 'dic.'];

/// Cuándo vuelve un párrafo, para la pantalla de fin: «hoy», «mañana», «en 3 días», «el 12 nov.».
String cuandoVuelve(String? iso, [DateTime? ahora]) {
  if (iso == null) return 'pendiente';
  final t = DateTime.tryParse(iso)?.toUtc();
  if (t == null) return 'pendiente';
  final a = (ahora ?? DateTime.now()).toUtc();
  final diaT = DateTime.utc(t.year, t.month, t.day);
  final diaA = DateTime.utc(a.year, a.month, a.day);
  final dias = diaT.difference(diaA).inDays;
  if (dias <= 0) return t.isAfter(a) ? 'hoy' : 'ya';
  if (dias == 1) return 'mañana';
  if (dias < 30) return 'en $dias días';
  return 'el ${t.day} ${_mesesAbrev[t.month - 1]}';
}
