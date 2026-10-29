// Cliente y saneado de la generación de resúmenes con IA (/api/admin/resumenes-ia).
// Todo lo que llega del servidor se sanea (los huecos, con las mismas reglas).
// Puerto de la web: src/lib/resumenes/ia.ts y src/lib/resumenes/borrador.ts.

import '../../core/models/creditos_ia.dart';
import '../../core/models/ia.dart';
import '../../core/models/resumen.dart';
import '../../core/models/resumen_ia.dart';
import '../../core/services/ia_service.dart';
import 'resumenes_huecos.dart';

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

String _texto(dynamic v, int max) => v is String ? (v.length > max ? v.substring(0, max) : v) : '';

int? _entero(dynamic v) => v is int && v >= 1 && v <= 100000 ? v : null;

/// El origen que manda la IA (o el guardado), solo con campos conocidos.
OrigenParrafo? sanearOrigen(dynamic raw) {
  if (raw is! Map) return null;
  final o = OrigenParrafo(
    pagina: _entero(raw['pagina']),
    diapositiva: _entero(raw['diapositiva']),
    seccion: raw['seccion'] is String && (raw['seccion'] as String).isNotEmpty ? (raw['seccion'] as String).substring(0, raw['seccion'].length > 80 ? 80 : raw['seccion'].length) : null,
    dudoso: raw['dudoso'] is String && (raw['dudoso'] as String).isNotEmpty ? (raw['dudoso'] as String).substring(0, raw['dudoso'].length > 20 ? 20 : raw['dudoso'].length) : null,
    fragmento: raw['fragmento'] is String && (raw['fragmento'] as String).trim().isNotEmpty && (raw['fragmento'] as String).length <= 300 ? raw['fragmento'] as String : null,
  );
  if (o.pagina == null && o.diapositiva == null && o.seccion == null && o.dudoso == null && o.fragmento == null) return null;
  return o;
}

/// Una fuente firmada que viene de fuera, o null. La firma la comprueba el servidor.
FuenteFirmada? sanearFuente(dynamic raw) {
  if (raw is! Map) return null;
  final hash = raw['hash'];
  final firma = raw['firma'];
  final caracteres = raw['caracteres'];
  if (hash is! String || !_hex64.hasMatch(hash)) return null;
  if (firma is! String || !_hex64.hasMatch(firma)) return null;
  if (caracteres is! int || caracteres < 1 || caracteres > 10000000) return null;
  return FuenteFirmada(hash: hash, caracteres: caracteres, firma: firma);
}

/// Un párrafo de fuera (servidor o borrador) → párrafo limpio, o null si no vale.
ParrafoBorrador? sanearParrafoBorrador(dynamic raw, String key) {
  if (raw is! Map) return null;
  final t = _texto(raw['texto'], 1000);
  if (t.trim().length < 2) return null;
  final huecos = sanearHuecos(raw['huecos'], t);
  if (huecos.isEmpty) return null;
  final ia = sanearOrigen(raw['ia']);
  final temaRaw = _texto(raw['tema'], maxTemaResumen).trim();
  final docRaw = raw['doc'];
  return ParrafoBorrador(
    key: _texto(raw['key'], 40).isNotEmpty ? _texto(raw['key'], 40) : key,
    tema: temaRaw.isNotEmpty ? temaRaw : 'General',
    texto: t,
    huecos: huecos,
    incluir: raw['incluir'] != false,
    grupo: raw['grupo'] is String && (raw['grupo'] as String).isNotEmpty ? _texto(raw['grupo'], 200) : null,
    ia: ia,
    doc: docRaw is String && _hex64.hasMatch(docRaw) ? docRaw : null,
    incluirParecido: raw['incluirParecido'] == true,
    nuevo: raw['nuevo'] == true,
  );
}

/// Resultado de «más de este tema»: párrafos nuevos + lo que descartó el servidor.
class MasResumenes {
  final List<ParrafoBorrador> parrafos;
  final int repetidos;
  final int casiDuplicados;
  final int otroTema;
  final int vecino;

  const MasResumenes({
    required this.parrafos,
    required this.repetidos,
    required this.casiDuplicados,
    required this.otroTema,
    required this.vecino,
  });
}

/// Cliente de la generación de resúmenes con IA sobre [IaService].
class ResumenesIa {
  final IaService ia;

  ResumenesIa(this.ia);

  /// null si la función no está disponible para este usuario.
  Future<Map<String, dynamic>?> estado() => ia.estado(IaArea.resumenes);

  /// Índice de un documento largo (solo viaja el principio de cada sección).
  Future<List<TemaIndice>> indice(String titulo, List<Seccion> secciones) =>
      ia.indice(IaArea.resumenes, titulo: titulo, secciones: secciones);

  /// Genera los párrafos (en streaming si hay `onEvento`). Devuelve los validados.
  Future<ResumenGenerado> generar({
    required String titulo,
    required ModoResumen modo,
    required List<int> niveles,
    required Densidad densidad,
    required List<Seccion> secciones,
    required int paginas,
    String? unidad,
    List<({String titulo, int desde, int hasta})>? temas,
    CobroIa? cobro,
    void Function(EventoIa)? onEvento,
  }) async {
    final cuerpo = <String, dynamic>{
      'titulo': titulo,
      'modo': modo == ModoResumen.literal ? 'literal' : 'resumen',
      'niveles': niveles,
      'densidad': densidad.id,
      'secciones': secciones.map((s) => s.toJson()).toList(),
      'paginas': paginas,
      if (unidad != null) 'unidad': unidad,
      if (temas != null) 'temas': temas.map((t) => {'titulo': t.titulo, 'desde': t.desde, 'hasta': t.hasta}).toList(),
      // Con créditos, el precio que se enseñó (tope) y la clave para no cobrar dos veces.
      ...?cobro?.toJson(),
    };
    final datos = await ia.post(IaArea.resumenes, cuerpo: cuerpo, onEvento: onEvento);
    return _parseGenerado(datos, titulo);
  }

  /// Párrafos NUEVOS de un tema («Más de este tema»).
  Future<MasResumenes> mas({
    required String titulo,
    required ModoResumen modo,
    required List<Seccion> secciones,
    required int paginas,
    String? unidad,
    required List<int> niveles,
    required String tema,
    required int cantidad,
    required List<String> existentes,
    required List<String> vecinos,
    CobroIa? cobro,
  }) async {
    final datos = await ia.post(IaArea.resumenes, cuerpo: {
      'titulo': titulo,
      'modo': modo == ModoResumen.literal ? 'literal' : 'resumen',
      'secciones': secciones.map((s) => s.toJson()).toList(),
      'paginas': paginas,
      if (unidad != null) 'unidad': unidad,
      'niveles': niveles,
      'ampliar': {'tema': tema, 'cantidad': cantidad, 'existentes': existentes, 'vecinos': vecinos},
      // Con créditos activos, sin esto el servidor rechaza la petición (precio_cambiado).
      ...?cobro?.toJson(),
    });
    final st = datos['stats'] is Map ? datos['stats'] as Map : const {};
    int cuenta(dynamic v) => v is int && v >= 0 ? v : 0;
    return MasResumenes(
      parrafos: _parrafos(datos['parrafos'], 'm', null).map((p) => ParrafoBorrador(
            key: p.key,
            tema: tema,
            texto: p.texto,
            huecos: p.huecos,
            incluir: p.incluir,
            grupo: p.grupo,
            ia: p.ia,
            doc: p.doc,
            incluirParecido: p.incluirParecido,
            nuevo: p.nuevo,
          )).toList(),
      repetidos: cuenta(st['repetidos']),
      casiDuplicados: cuenta(st['casiDuplicados']),
      otroTema: cuenta(st['otroTema']),
      vecino: cuenta(st['vecino']),
    );
  }

  /// Otra versión del MISMO párrafo (mismos datos en los huecos, mismo nivel).
  Future<ParrafoBorrador> rehacer({
    required String titulo,
    required ModoResumen modo,
    required List<Seccion> secciones,
    required int paginas,
    String? unidad,
    required String tema,
    required String texto,
    required List<Hueco> huecos,
    CobroIa? cobro,
  }) async {
    final datos = await ia.post(IaArea.resumenes, cuerpo: {
      'titulo': titulo,
      'modo': modo == ModoResumen.literal ? 'literal' : 'resumen',
      'secciones': secciones.map((s) => s.toJson()).toList(),
      'paginas': paginas,
      if (unidad != null) 'unidad': unidad,
      'rehacer': {'tema': tema, 'texto': texto, 'huecos': huecos.map((h) => h.toJson()).toList()},
      ...?cobro?.toJson(),
    });
    final lista = _parrafos([datos['parrafo']], 'r', null);
    if (lista.isEmpty) throw const IaException('La IA devolvió un resultado no válido. Inténtalo de nuevo.');
    final p = lista.first;
    return ParrafoBorrador(
      key: p.key,
      tema: tema,
      texto: p.texto,
      huecos: p.huecos,
      incluir: p.incluir,
      grupo: p.grupo,
      ia: p.ia,
      doc: p.doc,
      incluirParecido: p.incluirParecido,
      nuevo: p.nuevo,
    );
  }

  ResumenGenerado _parseGenerado(Map<String, dynamic> datos, String tituloInicial) {
    final titulo = _texto(datos['titulo'], 200);
    final tituloFinal = titulo.isNotEmpty ? titulo : tituloInicial;

    if (datos['temas'] is List) {
      final fuentes = <FuenteFirmada>[];
      final temas = <TemaGenerado>[];
      for (final t in (datos['temas'] as List).whereType<Map>()) {
        final i = t['i'];
        if (i is! int) continue;
        final nombre = _texto(t['titulo'], 200);
        final nombreFinal = nombre.isNotEmpty ? nombre : 'Tema ${i + 1}';
        final fuente = sanearFuente(t['fuente']);
        if (fuente != null && !fuentes.any((f) => f.hash == fuente.hash)) fuentes.add(fuente);
        final parrafos = _parrafos(t['parrafos'], 't$i-', fuente)
            .map((p) => ParrafoBorrador(key: p.key, tema: p.tema, texto: p.texto, huecos: p.huecos, incluir: p.incluir, grupo: nombreFinal, ia: p.ia, doc: p.doc, incluirParecido: p.incluirParecido, nuevo: p.nuevo))
            .toList();
        temas.add(TemaGenerado(i: i, titulo: nombreFinal, parrafos: parrafos));
      }
      final fallidos = <({int i, String titulo, String motivo})>[];
      for (final f in (datos['fallidos'] is List ? datos['fallidos'] as List : const []).whereType<Map>()) {
        if (f['i'] is int) fallidos.add((i: f['i'] as int, titulo: _texto(f['titulo'], 200), motivo: _texto(f['motivo'], 300)));
      }
      return ResumenGenerado(titulo: tituloFinal, parrafos: const [], temas: temas, fallidos: fallidos, fuentes: fuentes);
    }

    final fuente = sanearFuente(datos['fuente']);
    return ResumenGenerado(
      titulo: tituloFinal,
      parrafos: _parrafos(datos['parrafos'], 'p', fuente),
      temas: const [],
      fallidos: const [],
      fuentes: fuente != null ? [fuente] : const [],
    );
  }

  List<ParrafoBorrador> _parrafos(dynamic raw, String prefijo, FuenteFirmada? fuente) {
    if (raw is! List) return const [];
    final out = <ParrafoBorrador>[];
    var k = 0;
    for (final x in raw) {
      final p = sanearParrafoBorrador(x, '$prefijo$k');
      if (p != null) {
        out.add(ParrafoBorrador(
          key: p.key,
          tema: p.tema,
          texto: p.texto,
          huecos: p.huecos,
          incluir: p.incluir,
          grupo: p.grupo,
          ia: p.ia,
          doc: fuente?.hash ?? p.doc,
          incluirParecido: p.incluirParecido,
          nuevo: p.nuevo,
        ));
      }
      k++;
    }
    return out;
  }
}
