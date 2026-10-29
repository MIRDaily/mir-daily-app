// Créditos de IA: modelos, precio y textos, sin red (para poder probarlos).
// Puerto de la web: src/lib/ia/precio.ts y src/lib/ia/creditosTexto.ts.
//
// El precio que se calcula aquí solo se ENSEÑA y viaja como tope (`creditosAnunciados`): el que
// manda es el servidor (services/creditos/tarifa.js), que cuenta los caracteres a su manera y nunca
// cobra más de lo anunciado. Si lo anunciado se queda corto, contesta 409 `precio_cambiado`.
//
//   créditos = ⌈ (fijo × llamadas + por_mil × caracteres / 1.000) × factor ⌉, mínimo 1
//   (una clave sin coste, el índice, vale 0)

import 'ia.dart';

int _int(dynamic v, [int porDefecto = 0]) => v is num ? v.toInt() : porDefecto;
String? _str(dynamic v) => v is String ? v : null;

// --- Tarifa y precio ----------------------------------------------------------------------------

class TarifaClave {
  final double fijo;
  final double porMil;
  final Map<String, double> factores;

  const TarifaClave({required this.fijo, required this.porMil, this.factores = const {}});

  factory TarifaClave.fromJson(Map<String, dynamic> j) {
    double n(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);
    final f = j['factores'];
    return TarifaClave(
      fijo: n(j['fijo']),
      porMil: n(j['por_mil']),
      factores: f is Map ? {for (final e in f.entries) '${e.key}': n(e.value)} : const {},
    );
  }
}

class TarifaIa {
  final int version;
  final Map<String, TarifaClave> claves;
  final int cancelacionesGratisMes;
  final int cancelacionSinTextoSeg;

  const TarifaIa({
    required this.version,
    required this.claves,
    this.cancelacionesGratisMes = 0,
    this.cancelacionSinTextoSeg = 5,
  });

  factory TarifaIa.fromJson(Map<String, dynamic> j) {
    final c = j['claves'];
    return TarifaIa(
      version: _int(j['version']),
      claves: c is Map
          ? {for (final e in c.entries) if (e.value is Map) '${e.key}': TarifaClave.fromJson(Map<String, dynamic>.from(e.value as Map))}
          : const {},
      cancelacionesGratisMes: _int(j['cancelacionesGratisMes']),
      cancelacionSinTextoSeg: _int(j['cancelacionSinTextoSeg'], 5),
    );
  }
}

/// Créditos de una generación, o null si la tarifa no tiene esa clave (no se puede anunciar).
int? precioIa(TarifaIa? tarifa, {required String clave, int caracteres = 0, int llamadas = 1, String? densidad}) {
  final t = tarifa?.claves[clave];
  if (t == null) return null;
  if (t.fijo == 0 && t.porMil == 0) return 0;
  final f = densidad != null ? t.factores[densidad] : null;
  final factor = f != null && f.isFinite && f > 0 ? f : 1.0;
  final n = llamadas < 1 ? 1 : llamadas;
  final chars = caracteres < 0 ? 0 : caracteres;
  final bruto = (t.fijo * n + (t.porMil * chars) / 1000) * factor;
  // Redondeo a 6 decimales antes del techo: 13,0000000001 por la coma flotante no es 14.
  final p = ((bruto * 1e6).round() / 1e6).ceil();
  return p < 1 ? 1 : p;
}

String claveResumenes(String modo) => 'resumenes:${modo == 'literal' ? 'literal' : 'resumen'}';

// Caracteres de control, de formato invisible y de dirección bidi (los mismos que quita el servidor).
final RegExp _invisibles = RegExp(
  '[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F-\\u009F\\u00AD\\u061C\\u180E'
  '\\u200B-\\u200F\\u202A-\\u202E\\u2060-\\u206F\\uFEFF\\uFFF9-\\uFFFB\\u{E0000}-\\u{E007F}]',
  unicode: true,
);

/// El saneado de entrada del servidor (limpiarEntrada). Dart no normaliza a NFC: con un texto en
/// forma descompuesta aquí salen MÁS caracteres que en el servidor, nunca menos, así que el precio
/// anunciado puede pasarse por arriba (y el servidor cobra lo suyo), pero no quedarse corto.
String limpiarEntrada(String texto) => texto
    .replaceAll(_invisibles, '')
    .replaceAll(RegExp(r'\r\n?'), '\n')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r' ?\n ?'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// Caracteres de una sección (0 si el servidor la descarta: menos de 10 tras sanear).
int caracteresSeccion(Seccion s) {
  final n = limpiarEntrada(s.texto).length;
  return n < 10 ? 0 : n;
}

int caracteresDocumento(List<Seccion> secciones) =>
    secciones.fold(0, (n, s) => n + caracteresSeccion(s));

// --- Saldo e historial ---------------------------------------------------------------------------

class BolsaIa {
  final int id;
  final String tipo; // periodo | regalo | prueba | recarga | ajuste
  final int iniciales;
  final int saldo;
  final DateTime? caduca;
  final bool congelada;

  const BolsaIa({required this.id, required this.tipo, required this.iniciales, required this.saldo, this.caduca, this.congelada = false});

  factory BolsaIa.fromJson(Map<String, dynamic> j) => BolsaIa(
        id: _int(j['id']),
        tipo: _str(j['tipo']) ?? 'ajuste',
        iniciales: _int(j['iniciales']),
        saldo: _int(j['saldo']),
        caduca: DateTime.tryParse(_str(j['caduca_at']) ?? ''),
        congelada: j['congelada'] == true,
      );
}

class SaldoIa {
  final String? plan; // prueba | mensual | anual | admin
  final String? estado; // activo | impagado | cancelado | caducado
  final DateTime? periodoFin;
  final bool ilimitado;
  final bool puedeUsar;
  final int total;
  final List<BolsaIa> bolsas;
  final int cancelacionesGratisMes;
  final int cancelacionesGratisRestantes;
  final bool pruebaDisponible;

  const SaldoIa({
    this.plan,
    this.estado,
    this.periodoFin,
    this.ilimitado = false,
    this.puedeUsar = false,
    this.total = 0,
    this.bolsas = const [],
    this.cancelacionesGratisMes = 0,
    this.cancelacionesGratisRestantes = 0,
    this.pruebaDisponible = false,
  });

  factory SaldoIa.fromJson(Map<String, dynamic> j) {
    final b = j['bolsas'];
    return SaldoIa(
      plan: _str(j['plan']),
      estado: _str(j['estado']),
      periodoFin: DateTime.tryParse(_str(j['periodo_fin']) ?? ''),
      ilimitado: j['ilimitado'] == true,
      puedeUsar: j['puede_usar'] == true,
      total: _int(j['total']),
      bolsas: b is List ? b.whereType<Map>().map((x) => BolsaIa.fromJson(Map<String, dynamic>.from(x))).toList() : const [],
      cancelacionesGratisMes: _int(j['cancelaciones_gratis_mes']),
      cancelacionesGratisRestantes: _int(j['cancelaciones_gratis_restantes']),
      pruebaDisponible: j['prueba_disponible'] == true,
    );
  }

  /// La bolsa del mes en curso (la de periodo que caduca más tarde).
  BolsaIa? get bolsaDelMes {
    BolsaIa? mejor;
    for (final x in bolsas.where((x) => x.tipo == 'periodo')) {
      if (mejor == null || (x.caduca ?? DateTime(0)).isAfter(mejor.caduca ?? DateTime(0))) mejor = x;
    }
    return mejor;
  }

  /// Gastado del mes (0-1), para el aviso suave del 80 %.
  double get fraccionGastada {
    final b = bolsaDelMes;
    return b != null && b.iniciales > 0 ? 1 - b.saldo / b.iniciales : 0;
  }
}

class MovimientoIa {
  final int id;
  final String tipo; // alta | cargo | devolucion | caducidad | ajuste
  final int creditos;
  final DateTime? creado;
  final String bolsaTipo;
  final String? motivo;
  final String? clave;
  final String? kind;
  final String? titulo;

  const MovimientoIa({
    required this.id,
    required this.tipo,
    required this.creditos,
    this.creado,
    this.bolsaTipo = '',
    this.motivo,
    this.clave,
    this.kind,
    this.titulo,
  });

  factory MovimientoIa.fromJson(Map<String, dynamic> j) => MovimientoIa(
        id: _int(j['id']),
        tipo: _str(j['tipo']) ?? 'ajuste',
        creditos: _int(j['creditos']),
        creado: DateTime.tryParse(_str(j['creado_at']) ?? ''),
        bolsaTipo: _str(j['bolsa_tipo']) ?? '',
        motivo: _str(j['motivo']),
        clave: _str(j['clave']),
        kind: _str(j['kind']),
        titulo: _str(j['titulo']),
      );
}

/// Lo que responde POST /api/ia/cancelar.
class PrevisionCancelacion {
  final String prevision; // sin_texto | gratis | parcial
  final int creditos;
  final int cancelacionesGratisRestantes;

  const PrevisionCancelacion({required this.prevision, required this.creditos, required this.cancelacionesGratisRestantes});

  factory PrevisionCancelacion.fromJson(Map<String, dynamic> j) => PrevisionCancelacion(
        prevision: _str(j['prevision']) ?? 'parcial',
        creditos: _int(j['creditos']),
        cancelacionesGratisRestantes: _int(j['cancelacionesGratisRestantes']),
      );
}

// --- Una generación ------------------------------------------------------------------------------

/// Lo que viaja en el cuerpo de cada generación con créditos.
class CobroIa {
  final int creditosAnunciados;
  final int tarifaVersion;
  final String idempotencyKey;

  const CobroIa({required this.creditosAnunciados, required this.tarifaVersion, required this.idempotencyKey});

  Map<String, dynamic> toJson() => {
        'creditosAnunciados': creditosAnunciados,
        'tarifaVersion': tarifaVersion,
        'idempotencyKey': idempotencyKey,
      };
}

/// Un clic en «Generar»: su cobro y, cuando llega el evento «reserva», el id para cancelar.
class GeneracionIa {
  final CobroIa? cobro;
  final DateTime inicio;
  int? usageId;
  int cobrados;

  GeneracionIa({this.cobro, DateTime? inicio})
      : inicio = inicio ?? DateTime.now(),
        cobrados = cobro?.creditosAnunciados ?? 0;

  void anotar(EventoReserva e) {
    usageId = e.usageId;
    if (e.cobrados != null) cobrados = e.cobrados!;
  }
}

// --- Textos --------------------------------------------------------------------------------------

/// 1240 → «1.240», como `toLocaleString('es-ES')`.
String fmtCreditos(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/// «29 de octubre».
String fechaCortaIa(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.day} de ${_meses[l.month - 1]}';
}

/// Aviso ANTES de cancelar cuando ya no quedan cancelaciones gratis (y ya salió texto), o null.
String? avisoAntesDeCancelar(GeneracionIa g, SaldoIa? saldo, TarifaIa? tarifa, {DateTime? ahora}) {
  final restantes = saldo?.cancelacionesGratisRestantes ?? 1;
  final umbral = Duration(seconds: tarifa?.cancelacionSinTextoSeg ?? 5);
  final pasado = (ahora ?? DateTime.now()).difference(g.inicio);
  if ((saldo?.ilimitado ?? false) || restantes > 0 || pasado < umbral || g.cobrados <= 0) return null;
  return 'Ya has usado las ${fmtCreditos(saldo?.cancelacionesGratisMes ?? 0)} cancelaciones gratis de este mes. '
      'Si cancelas ahora se cobrará la parte ya generada (como mucho ${fmtCreditos(g.cobrados)} créditos). ¿Cancelar?';
}

/// Lo que se dice tras cancelar, con lo que respondió el servidor (o nada, si no llegó).
String mensajeCancelacion(PrevisionCancelacion? p, GeneracionIa g) {
  final n = p?.creditos ?? g.cobrados;
  if (p == null) return n > 0 ? 'Cancelado. Te hemos devuelto ${fmtCreditos(n)} créditos.' : 'Generación cancelada.';
  if (p.prevision == 'sin_texto') {
    return 'Cancelado antes de empezar: te hemos devuelto ${fmtCreditos(n)} créditos (no cuenta como cancelación).';
  }
  if (p.prevision == 'gratis') {
    final r = p.cancelacionesGratisRestantes;
    return 'Cancelado. Te hemos devuelto ${fmtCreditos(n)} créditos · te '
        '${r == 1 ? 'queda 1 cancelación gratis' : 'quedan ${fmtCreditos(r)} cancelaciones gratis'} este mes.';
  }
  return 'Cancelado. Se ha cobrado la parte ya generada (como mucho ${fmtCreditos(n)} créditos) y se devuelve el resto.';
}

/// Lo que se añade al mensaje de un error cuando el servidor devolvió los créditos.
String mensajeDevolucion(Map<String, dynamic>? datos) {
  final c = datos?['creditos'];
  if (c is! Map || c['devueltos'] is! num || (c['devueltos'] as num) <= 0) return '';
  final cobrados = c['cobrados'] is num ? (c['cobrados'] as num).toInt() : 0;
  return cobrados <= 0 ? ' No se ha cobrado nada.' : ' Te hemos devuelto ${fmtCreditos((c['devueltos'] as num).toInt())} créditos.';
}

/// Mensaje para los rechazos del cobro (402, 403, 409), o '' si no es uno de ellos.
String mensajeRechazo(String codigo, Map<String, dynamic>? datos) {
  final d = datos ?? const {};
  switch (codigo) {
    case 'sin_creditos':
      return 'No te quedan créditos suficientes: hacen falta ${fmtCreditos(_int(d['necesarios']))} y tienes ${fmtCreditos(_int(d['saldo']))}.';
    case 'precio_cambiado':
      return 'El precio ha cambiado: ahora son ${fmtCreditos(_int(d['creditos']))} créditos. Revísalo y vuelve a generar.';
    case 'sin_plan':
      return 'Necesitas un plan con IA para usar esta función.';
    case 'repetida':
      return 'Esta generación ya se había pedido: espera a que termine.';
  }
  return '';
}

/// Mensaje de un error de generación: el del servidor, más lo devuelto o el motivo del rechazo.
String mensajeErrorIa(Object e, String porDefecto) {
  if (e is! IaException) return porDefecto;
  final rechazo = mensajeRechazo(e.codigo, e.datos);
  if (rechazo.isNotEmpty) return rechazo;
  final extra = mensajeDevolucion(e.datos);
  if (extra.isEmpty) return e.message;
  return RegExp(r'[.!?…]$').hasMatch(e.message) ? '${e.message}$extra' : '${e.message}.$extra';
}

/// Descripción de una línea del historial.
String describirMovimiento(MovimientoIa m) {
  String que(String? k, String? clave) {
    if (k == null && clave == null) return 'IA';
    if (clave != null && clave.startsWith('mapa')) return clave.contains('detalle') ? 'Mapa con más contenido' : 'Mapa';
    if (clave == 'rama' || k == 'rama') return 'Rama del mapa';
    if (clave == 'flashcards_mas') return 'Más flashcards';
    if (clave != null && clave.startsWith('flashcards')) return clave.endsWith(':mapa') ? 'Flashcards desde el mapa' : 'Flashcards';
    if (clave == 'resumenes_mas') return 'Más párrafos';
    if (clave == 'resumenes_rehacer') return 'Párrafo rehecho';
    if (clave != null && clave.startsWith('resumenes')) return 'Resumen activo';
    if (clave == 'indice') return 'Índice';
    return 'IA';
  }

  final titulo = m.titulo != null ? ' · ${m.titulo}' : '';
  switch (m.tipo) {
    case 'cargo':
      return '${que(m.kind, m.clave)}$titulo';
    case 'devolucion':
      const por = {
        'error': 'error',
        'conexion': 'conexión cortada',
        'cancelacion_sin_texto': 'cancelado',
        'cancelacion_gratis': 'cancelado',
        'cancelacion_parcial': 'cancelado',
        'temas_fallidos': 'temas que no salieron',
      };
      return 'Devuelto (${por[m.motivo ?? ''] ?? 'devolución'})$titulo';
    case 'caducidad':
      return 'Caducados';
    case 'alta':
      const tipos = {
        'periodo': 'Renovación',
        'regalo': 'Regalo del primer mes',
        'prueba': 'Prueba',
        'recarga': 'Recarga',
        'ajuste': 'Regalo del equipo',
      };
      if (m.bolsaTipo == 'ajuste' && m.motivo != null) return 'Regalo del equipo · ${m.motivo}';
      return tipos[m.bolsaTipo] ?? 'Alta';
  }
  return m.motivo != null ? 'Ajuste · ${m.motivo}' : 'Ajuste';
}

/// La línea del precio: «Usará 14 créditos · te quedan 1.240», o el motivo por el que no se puede.
class LineaPrecio {
  final String texto;
  final bool suficiente;
  final bool aviso; // 80 % del mes gastado

  const LineaPrecio(this.texto, {this.suficiente = true, this.aviso = false});
}

LineaPrecio lineaPrecio(int? precio, SaldoIa? saldo) {
  if (precio == null) return const LineaPrecio('No se ha podido calcular el precio.', suficiente: false);
  final usa = 'Usará ${fmtCreditos(precio)} ${precio == 1 ? 'crédito' : 'créditos'}';
  if (saldo == null) return LineaPrecio(usa);
  if (saldo.ilimitado) return LineaPrecio('$usa · sin límite');
  if (!saldo.puedeUsar) return const LineaPrecio('Necesitas un plan con IA para usar esta función.', suficiente: false);
  if (precio > saldo.total) {
    final renueva = saldo.periodoFin != null ? ' Se renuevan el ${fechaCortaIa(saldo.periodoFin)}.' : '';
    return LineaPrecio('Hacen falta ${fmtCreditos(precio)} créditos y te quedan ${fmtCreditos(saldo.total)}.$renueva', suficiente: false);
  }
  return LineaPrecio('$usa · te quedan ${fmtCreditos(saldo.total)}', aviso: saldo.fraccionGastada >= 0.8);
}
