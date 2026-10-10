// Borradores de la vista previa de los resúmenes con IA, guardados SOLO en el
// dispositivo (SharedPreferences, base PROPIA). Si se cierra la app a mitad de
// revisión, lo generado (y editado) no se pierde. Caducan a los 7 días y se
// borran al guardar. Nunca van al servidor.
//
// UNO POR DOCUMENTO (la clave es usuario + SHA-256 del archivo). Puerto de la
// web: src/lib/resumenes/borrador.ts.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/resumen.dart';
import '../../core/models/resumen_ia.dart';
import 'resumenes_ia.dart' show sanearFuente, sanearParrafoBorrador;

const int diasBorradorResumen = 7;
const int maxBorradoresResumen = 12;
const String documentoBorradorV1 = 'documento';

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// SHA-256 de unos bytes en hex (la clave de un borrador por documento).
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String claveBorradorResumen(String usuario, [String documento = documentoBorradorV1]) => '$usuario:$documento';

bool caducadoBorrador(BorradorResumen b, [DateTime? ahora]) =>
    (ahora ?? DateTime.now()).millisecondsSinceEpoch >= b.caduca;

String _texto(dynamic v, int max) => v is String ? (v.length > max ? v.substring(0, max) : v) : '';

String _documentoDe(Map raw) {
  final d = raw['documento'];
  if (d is String && (_hex64.hasMatch(d) || d == documentoBorradorV1)) return d;
  final clave = raw['clave'] is String ? raw['clave'] as String : '';
  final idx = clave.indexOf(':');
  final sufijo = idx >= 0 ? clave.substring(idx + 1) : '';
  return _hex64.hasMatch(sufijo) ? sufijo : documentoBorradorV1;
}

/// Lo leído del almacenamiento tampoco se da por bueno: se reconstruye entero.
BorradorResumen? sanearBorradorResumen(dynamic raw) {
  if (raw is! Map) return null;
  final clave = raw['clave'];
  final usuario = raw['usuario'];
  final lista = raw['lista'];
  if (clave is! String || usuario is! String || lista is! List) return null;

  final parrafos = <ParrafoBorrador>[];
  var k = 0;
  for (final x in lista.take(1500)) {
    final p = sanearParrafoBorrador(x, 'r$k');
    if (p != null) parrafos.add(p);
    k++;
  }
  if (parrafos.isEmpty) return null;

  final f = raw['fuente'] is Map ? raw['fuente'] as Map : const {};
  int entero(dynamic v) => v is num && v.isFinite ? v.toInt() : 0;
  final fuentes = (raw['fuentes'] is List ? raw['fuentes'] as List : const []).map(sanearFuente).whereType<FuenteFirmada>().toList();

  final tituloRaw = _texto(raw['titulo'], 200);
  final nombreRaw = _texto(raw['nombreGrupo'], 80);
  return BorradorResumen(
    clave: clave,
    usuario: usuario,
    documento: _documentoDe(raw),
    titulo: tituloRaw.isNotEmpty ? tituloRaw : 'Resumen activo',
    nombreGrupo: nombreRaw.isNotEmpty ? nombreRaw : (tituloRaw.isNotEmpty ? (tituloRaw.length > 80 ? tituloRaw.substring(0, 80) : tituloRaw) : 'Resumen activo'),
    modo: raw['modo'] == 'literal' ? ModoResumen.literal : ModoResumen.resumen,
    fuenteNombre: f['nombre'] is String ? _texto(f['nombre'], 160) : null,
    fuenteUnidad: f['unidad'] == 'diapositiva' || f['unidad'] == 'pagina' ? f['unidad'] as String : null,
    fuentes: fuentes.take(60).toList(),
    lista: parrafos,
    fallidos: (raw['fallidos'] is List ? raw['fallidos'] as List : const []).whereType<String>().take(50).toList(),
    creado: entero(raw['creado']),
    actualizado: entero(raw['actualizado']),
    caduca: entero(raw['caduca']),
  );
}

/// Registros de un usuario → los borradores vivos (del más reciente al más viejo)
/// y las claves de los que sobran (caducados, rotos o de otro usuario).
({List<BorradorResumen> vivos, List<String> sobran}) ordenarBorradoresResumen(
  List<dynamic> registros,
  String usuario, [
  DateTime? ahora,
]) {
  final vivos = <BorradorResumen>[];
  final sobran = <String>[];
  final t = (ahora ?? DateTime.now()).millisecondsSinceEpoch;
  for (final raw in registros) {
    final b = sanearBorradorResumen(raw);
    final clave = raw is Map && raw['clave'] is String ? raw['clave'] as String : null;
    if (b == null || b.usuario != usuario || b.caduca <= t) {
      if (clave != null && (b == null || b.usuario == usuario)) sobran.add(clave);
      continue;
    }
    vivos.add(b);
  }
  vivos.sort((a, b) => b.actualizado.compareTo(a.actualizado));
  return (vivos: vivos, sobran: sobran);
}

Map<String, dynamic> borradorToJson(BorradorResumen b) => {
      'clave': b.clave,
      'usuario': b.usuario,
      'documento': b.documento,
      'titulo': b.titulo,
      'nombreGrupo': b.nombreGrupo,
      'modo': b.modo == ModoResumen.literal ? 'literal' : 'resumen',
      'fuente': {if (b.fuenteNombre != null) 'nombre': b.fuenteNombre, if (b.fuenteUnidad != null) 'unidad': b.fuenteUnidad},
      'fuentes': b.fuentes.map((f) => f.toJson()).toList(),
      'lista': b.lista.map(_parrafoToJson).toList(),
      'fallidos': b.fallidos,
      'creado': b.creado,
      'actualizado': b.actualizado,
      'caduca': b.caduca,
    };

Map<String, dynamic> _parrafoToJson(ParrafoBorrador p) => {
      'key': p.key,
      'tema': p.tema,
      'texto': p.texto,
      'huecos': p.huecos.map((h) => h.toJson()).toList(),
      'incluir': p.incluir,
      if (p.grupo != null) 'grupo': p.grupo,
      if (p.ia != null) 'ia': _origenToJson(p.ia!),
      if (p.doc != null) 'doc': p.doc,
      if (p.incluirParecido) 'incluirParecido': true,
      if (p.nuevo) 'nuevo': true,
    };

Map<String, dynamic> _origenToJson(OrigenParrafo o) => {
      if (o.pagina != null) 'pagina': o.pagina,
      if (o.diapositiva != null) 'diapositiva': o.diapositiva,
      if (o.seccion != null) 'seccion': o.seccion,
      if (o.dudoso != null) 'dudoso': o.dudoso,
      if (o.fragmento != null) 'fragmento': o.fragmento,
    };

/// Almacén de borradores (SharedPreferences). Nunca lanza.
class BorradorStore {
  static String _indice(String usuario) => 'resumen_borradores_$usuario';

  Future<void> _guardarRegistros(SharedPreferences prefs, String usuario, List<Map<String, dynamic>> lista) async {
    await prefs.setString(_indice(usuario), jsonEncode(lista));
  }

  /// Los borradores vivos del usuario (los caducados se borran).
  Future<List<BorradorResumen>> leerTodos(String usuario) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indice(usuario));
    if (raw == null) return const [];
    List<dynamic> lista;
    try {
      lista = jsonDecode(raw) as List;
    } catch (_) {
      return const [];
    }
    final r = ordenarBorradoresResumen(lista, usuario);
    if (r.sobran.isNotEmpty) await _guardarRegistros(prefs, usuario, r.vivos.map(borradorToJson).toList());
    return r.vivos;
  }

  Future<void> guardar(String usuario, BorradorResumen d) async {
    final prefs = await SharedPreferences.getInstance();
    final vivos = await leerTodos(usuario);
    final otros = vivos.where((b) => b.clave != d.clave).toList()
      ..sort((a, b) => b.actualizado.compareTo(a.actualizado));
    final limite = otros.take(maxBorradoresResumen - 1).toList();
    final todos = [d, ...limite];
    await _guardarRegistros(prefs, usuario, todos.map(borradorToJson).toList());
  }

  Future<BorradorResumen?> leer(String usuario, String documento) async {
    final vivos = await leerTodos(usuario);
    for (final b in vivos) {
      if (b.documento == documento) return b;
    }
    return null;
  }

  Future<void> borrar(String usuario, String documento) async {
    final prefs = await SharedPreferences.getInstance();
    final vivos = await leerTodos(usuario);
    final resto = vivos.where((b) => b.documento != documento).toList();
    await _guardarRegistros(prefs, usuario, resto.map(borradorToJson).toList());
  }
}
