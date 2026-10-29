// Progreso mensual (GET /api/analytics/monthly-progress) y la pregunta más fallada de la semana
// pasada (GET /api/stats/most-failed-week), más la regla del nombre visible. Puerto de
// `buildProgressCard` de src/app/studio/page.tsx y de la tarjeta de src/app/dashboard/page.tsx.

import 'models.dart' show resolveOptionIndex;

class ProgresoMensual {
  /// Preguntas repasadas en los últimos 30 días, en los 30 anteriores y en el último año.
  final int mes;
  final int mesAnterior;
  final int anio;

  /// Variación frente al mes anterior, en %. Null si el mes anterior no tuvo actividad.
  final double? tendencia;

  const ProgresoMensual({required this.mes, required this.mesAnterior, required this.anio, this.tendencia});

  factory ProgresoMensual.fromJson(Map<String, dynamic> j) {
    int n(dynamic m) => m is Map && m['questions'] is num ? (m['questions'] as num).round() : 0;
    return ProgresoMensual(
      mes: n(j['month']),
      mesAnterior: n(j['previousMonth']),
      anio: n(j['year']),
      tendencia: j['trendPct'] is num ? (j['trendPct'] as num).toDouble() : null,
    );
  }
}

/// Número con el formato español de la web (`Intl.NumberFormat('es-ES')`): 1.234 y 12,5.
String numeroEs(num v) {
  final neg = v < 0;
  final abs = v.abs();
  final entero = abs.truncate();
  final dec = ((abs - entero) * 10).round();
  final digitos = '$entero';
  final b = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) b.write('.');
    b.write(digitos[i]);
  }
  // es-ES no agrupa los números de 4 cifras (1234), como hace la web.
  final texto = digitos.length == 4 ? digitos : b.toString();
  final conDec = dec == 0 ? texto : (dec == 10 ? numeroEs(entero + 1) : '$texto,$dec');
  return neg ? '-$conDec' : conDec;
}

/// Lo que enseña la tarjeta: valor («+120»), insignia («↑ +12,5%») y la línea del año.
({String valor, String? insignia, int signo, String detalle}) textoProgresoMensual(ProgresoMensual p) {
  final t = p.tendencia;
  final signo = t == null ? 0 : (t > 0 ? 1 : (t < 0 ? -1 : 0));
  final prefijo = t == null ? '' : (t > 0 ? '↑ +' : (t < 0 ? '↓ ' : '→ '));
  return (
    valor: p.mes > 0 ? '+${numeroEs(p.mes)}' : '0',
    insignia: t == null ? null : '$prefijo${numeroEs(t)}%',
    signo: signo,
    detalle: p.anio == 1 ? '1 pregunta repasada en el último año' : '${numeroEs(p.anio)} preguntas repasadas en el último año',
  );
}

class MasFallada {
  final String? weekStart;
  final int questionId;
  final double wrongPercentage;
  final int totalResponses;
  final String statement;
  final List<String> options;

  /// 0-based; -1 si no se sabe.
  final int correctIndex;
  final String? explanation;

  /// Tu respuesta cuando la hiciste (0-based), o null si no hiciste ese daily.
  final int? tuRespuesta;
  final bool? acertaste;
  final String? answeredAt;
  final bool hasImage;
  final String? imageUrl;

  /// Datos de ejemplo: esa semana ninguna pregunta llegó al mínimo de respuestas.
  final bool isPlaceholder;

  const MasFallada({
    this.weekStart,
    required this.questionId,
    required this.wrongPercentage,
    required this.totalResponses,
    required this.statement,
    required this.options,
    required this.correctIndex,
    this.explanation,
    this.tuRespuesta,
    this.acertaste,
    this.answeredAt,
    this.hasImage = false,
    this.imageUrl,
    this.isPlaceholder = false,
  });

  /// Null si el servidor responde «No data available…» (sin `questionId`).
  static MasFallada? fromJson(Map<String, dynamic> j) {
    final id = j['questionId'];
    if (id is! num) return null;
    final options = j['options'] is List ? (j['options'] as List).map((o) => '$o').toList() : <String>[];
    // Como `normalizeOptionIndex` de la web: 1-based si cabe, si no 0-based.
    int? indice(dynamic v) {
      if (v is! num) return null;
      final n = v.round();
      if (n >= 1 && n <= options.length) return n - 1;
      if (n >= 0 && n < options.length) return n;
      return null;
    }

    return MasFallada(
      weekStart: j['weekStart'] is String ? j['weekStart'] as String : null,
      questionId: id.round(),
      wrongPercentage: j['wrongPercentage'] is num ? (j['wrongPercentage'] as num).toDouble() : 0,
      totalResponses: j['totalResponses'] is num ? (j['totalResponses'] as num).round() : 0,
      statement: '${j['statement'] ?? ''}',
      options: options,
      correctIndex: resolveOptionIndex(j['correctAnswer'], options),
      explanation: j['explanation'] is String && (j['explanation'] as String).trim().isNotEmpty ? j['explanation'] as String : null,
      tuRespuesta: indice(j['yourLastAnswer']),
      acertaste: j['youWereCorrect'] is bool ? j['youWereCorrect'] as bool : null,
      answeredAt: j['answeredAt'] is String ? j['answeredAt'] as String : null,
      hasImage: j['hasImage'] == true,
      imageUrl: j['imageUrl'] is String && (j['imageUrl'] as String).isNotEmpty ? j['imageUrl'] as String : null,
      isPlaceholder: j['isPlaceholder'] == true,
    );
  }

  bool get nuncaRespondida => tuRespuesta == null;
  bool get respondidaBien => tuRespuesta != null && acertaste == true;
  bool get respondidaMal => tuRespuesta != null && acertaste == false;
}

/// dd/mm/aaaa. Una fecha sola («2026-10-19») se lee tal cual; una marca de tiempo, en la hora local.
String? fechaCorta(String? v) {
  if (v == null) return null;
  final soloFecha = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (soloFecha != null) return '${soloFecha[3]}/${soloFecha[2]}/${soloFecha[1]}';
  final d = DateTime.tryParse(v)?.toLocal();
  if (d == null) return null;
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year}';
}

/// «12.3» con un decimal, como `formatPercent` de la web (que usa punto).
String porcentaje(double v) => v.toStringAsFixed(1);

/// La frase tras «Ver respuesta», según hicieras o no aquel daily.
String textoMasFallada(MasFallada m) {
  final cuando = fechaCorta(m.answeredAt) ?? '--';
  if (m.respondidaMal) {
    return 'La fallaste cuando la hiciste el $cuando. No fuiste el único: el ${porcentaje(m.wrongPercentage)}% también la falló.';
  }
  if (m.respondidaBien) {
    return 'La acertaste cuando la hiciste el $cuando. Estás por encima del ${porcentaje(m.wrongPercentage)}% de usuarios.';
  }
  return 'Ese día no hiciste el Daily. Pero no te preocupes... ¿la habrías acertado?';
}

/// Nombre visible: 2-16 letras, números y espacios (el `DISPLAY_REGEX` del backend, sin tildes).
final _nombreVisible = RegExp(r'^[a-zA-Z0-9 ]{2,16}$');
bool nombreVisibleValido(String v) => _nombreVisible.hasMatch(v.trim());
const mensajeNombreVisible = 'Entre 2 y 16 caracteres: letras, números y espacios.';
