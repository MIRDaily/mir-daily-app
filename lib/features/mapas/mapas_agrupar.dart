// Cómo se ordena la lista de mapas: por asignatura y, dentro, por tema (las carpetas de la web y de
// la Biblioteca). Lógica pura, sin Flutter.
//
// - Asignaturas: la que tiene el mapa abierto o editado más recientemente, primero. «Sin
//   clasificar», al final.
// - Temas: en el orden del temario (el del catálogo), con «General» (sin tema) delante.
// - Mapas: el abierto o editado más recientemente, primero (`ResumenMapa.actividad`).

import '../../core/models/mapas.dart' show normalizarBusquedaMapa;
import '../../core/services/carpetas.dart';
import '../../core/services/mapas_api.dart';

class GrupoTema {
  final int? temaId;
  final String nombre;
  final List<ResumenMapa> mapas;
  const GrupoTema(this.temaId, this.nombre, this.mapas);
}

class GrupoAsignatura {
  /// Null = «Sin clasificar».
  final int? asignaturaId;
  final String nombre;
  final List<GrupoTema> temas;
  const GrupoAsignatura(this.asignaturaId, this.nombre, this.temas);

  int get total => temas.fold(0, (n, t) => n + t.mapas.length);
  List<ResumenMapa> get mapas => [for (final t in temas) ...t.mapas];
  DateTime get reciente => mapas.map((m) => m.actividad).reduce((a, b) => a.isAfter(b) ? a : b);
}

int _porFecha(ResumenMapa a, ResumenMapa b) => b.actividad.compareTo(a.actividad);

/// Todos, el abierto o editado más recientemente primero.
List<ResumenMapa> porActividad(List<ResumenMapa> mapas) => [...mapas]..sort(_porFecha);

/// «abierto hace…» o «editado hace…», lo que fuera lo último.
String cuandoMapa(ResumenMapa m, DateTime ahora) {
  final t = m.actividad;
  final d = ahora.difference(t);
  final que = m.ultimoFueAbrir ? 'abierto' : 'editado';
  if (d.inMinutes < 1) return '$que ahora';
  if (d.inHours < 1) return '$que hace ${d.inMinutes} min';
  if (d.inDays < 1) return '$que hace ${d.inHours} h';
  if (d.inDays < 30) return '$que hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
  return '$que el ${t.day}/${t.month}/${t.year}';
}

List<GrupoAsignatura> agruparPorCarpeta(List<ResumenMapa> mapas, List<AsignaturaCatalogo>? arbol) {
  final porAsignatura = <int?, List<ResumenMapa>>{};
  for (final m in mapas) {
    porAsignatura.putIfAbsent(m.carpeta?.subjectId, () => []).add(m);
  }
  final grupos = <GrupoAsignatura>[];
  porAsignatura.forEach((sid, lista) {
    if (sid == null) {
      grupos.add(GrupoAsignatura(null, 'Sin clasificar', [GrupoTema(null, 'Sin clasificar', lista..sort(_porFecha))]));
      return;
    }
    final asig = arbol?.where((a) => a.id == sid).firstOrNull;
    final orden = {for (var i = 0; i < (asig?.temas.length ?? 0); i++) asig!.temas[i].id: i};
    final porTema = <int?, List<ResumenMapa>>{};
    for (final m in lista) {
      final tid = m.carpeta?.topicId;
      // Un tema que el catálogo no conoce va a «General», como hace nombreCarpeta.
      porTema.putIfAbsent(tid != null && (asig == null || orden.containsKey(tid)) ? tid : null, () => []).add(m);
    }
    final ids = porTema.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return (orden[a] ?? 1 << 20).compareTo(orden[b] ?? 1 << 20);
      });
    grupos.add(GrupoAsignatura(sid, asig?.nombre ?? 'Asignatura', [
      for (final tid in ids)
        GrupoTema(
          tid,
          tid == null ? 'General' : asig?.temas.firstWhere((t) => t.id == tid).nombre ?? 'Tema',
          porTema[tid]!..sort(_porFecha),
        ),
    ]));
  });
  grupos.sort((a, b) {
    if (a.asignaturaId == null) return 1;
    if (b.asignaturaId == null) return -1;
    return b.reciente.compareTo(a.reciente);
  });
  return grupos;
}

/// La carpeta de un mapa, corta, para enseñarla bajo el título («Neumología › Asma»).
String carpetaDeMapa(ResumenMapa m, List<AsignaturaCatalogo>? arbol) =>
    m.carpeta == null ? '' : nombreCarpeta(arbol, m.carpeta!, corto: true);

/// Buscar por título o por carpeta, sin tildes ni mayúsculas.
List<ResumenMapa> buscarMapas(List<ResumenMapa> mapas, String texto, List<AsignaturaCatalogo>? arbol) {
  final q = normalizarBusquedaMapa(texto.trim());
  if (q.isEmpty) return mapas;
  return [
    for (final m in mapas)
      if (normalizarBusquedaMapa('${m.titulo} ${carpetaDeMapa(m, arbol)}').contains(q)) m,
  ];
}
