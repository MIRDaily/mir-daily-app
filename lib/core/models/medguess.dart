// MedGuess, el reto médico diario. Puerto de la web: src/app/medguess (types, services y el hook
// useMedGuess) contra src/services/medguessService.js del backend.
//
// No es un wordle: hay un término médico oculto (con sus sinónimos) y cada intento es una palabra
// cualquiera de 5 letras del diccionario. Cada letra del intento que esté en el término lo destapa
// allí donde aparezca. Se gana al destapar todas las letras de uno de los términos; hay 6 intentos
// y cada fallo desbloquea una pista.
//
// Lo que manda el servidor por letra:
//  - `found`  la letra está en el término y se descubre con este intento.
//  - `known`  está en el término, pero ya se había descubierto antes.
//  - `absent` no está.
//
// OJO: /today manda en cada término `display` (el término completo) aunque la partida siga abierta.
// Aquí NUNCA se pinta `display` mientras se juega: el progreso sale solo de `mask`.

import 'dart:convert';

const int largoIntentoMedGuess = 5;
const int maxIntentosMedGuess = 6;

enum LetraMedGuess { encontrada, conocida, ausente }

LetraMedGuess _letra(Object? v) => switch (v) {
      'found' || 'correct' || 'present' => LetraMedGuess.encontrada,
      'known' => LetraMedGuess.conocida,
      _ => LetraMedGuess.ausente,
    };

class IntentoMedGuess {
  final String palabra; // en mayúsculas
  final List<LetraMedGuess> resultado;

  const IntentoMedGuess(this.palabra, this.resultado);

  static IntentoMedGuess? fromJson(Object? j) {
    if (j is! Map) return null;
    final palabra = (j['guess'] ?? '').toString().trim().toUpperCase();
    final r = j['result'];
    if (palabra.length != largoIntentoMedGuess || r is! List || r.length != largoIntentoMedGuess) return null;
    return IntentoMedGuess(palabra, [for (final e in r) _letra(e)]);
  }
}

/// Un término (la respuesta o uno de sus sinónimos) tal como se ve: una lista de casillas, con
/// `null` en las letras aún ocultas y el carácter tal cual en lo que no es letra (espacios, guiones).
class TerminoMedGuess {
  final String mascara;
  final String? completo; // solo al terminar la partida

  const TerminoMedGuess(this.mascara, {this.completo});

  /// Las casillas a pintar. Con la partida terminada se enseña el término entero.
  List<String?> get casillas {
    final fuente = completo ?? mascara;
    return [
      for (var i = 0; i < fuente.length; i++)
        completo == null && fuente[i] == '_' ? null : fuente[i].toUpperCase(),
    ];
  }

  /// Las palabras del término (separadas por espacios), para que una palabra no se parta de línea.
  List<List<String?>> get palabras {
    final out = <List<String?>>[];
    var actual = <String?>[];
    for (final c in casillas) {
      if (c == ' ') {
        if (actual.isNotEmpty) out.add(actual);
        actual = [];
      } else {
        actual.add(c);
      }
    }
    if (actual.isNotEmpty) out.add(actual);
    return out;
  }
}

class EstadoMedGuess {
  final String categoria;
  final int intentosUsados;
  final bool resuelto;
  final bool terminado;
  final List<IntentoMedGuess> intentos;
  final List<TerminoMedGuess> terminos;
  final List<String> pistas;
  final int totalPistas;

  /// La respuesta, solo con la partida terminada.
  final String? respuesta;

  const EstadoMedGuess({
    required this.categoria,
    required this.intentosUsados,
    required this.resuelto,
    required this.terminado,
    required this.intentos,
    required this.terminos,
    required this.pistas,
    required this.totalPistas,
    this.respuesta,
  });

  int get intentosRestantes => (maxIntentosMedGuess - intentosUsados).clamp(0, maxIntentosMedGuess);

  /// El estado de /today, de /attempt (que trae el mismo estado más `attempt` y `finished`) o de
  /// /result.
  factory EstadoMedGuess.fromJson(Map<String, dynamic> j) {
    final finished = j['finished'] is Map ? Map<String, dynamic>.from(j['finished'] as Map) : null;
    final intentos = [
      for (final a in (j['attempts'] is List ? j['attempts'] as List : const []))
        if (IntentoMedGuess.fromJson(a) case final i?) i,
    ].take(maxIntentosMedGuess).toList();
    final usados = j['attemptsUsed'] is num ? (j['attemptsUsed'] as num).toInt() : intentos.length;
    final resuelto = j['solved'] == true || finished?['success'] == true;
    final terminado =
        resuelto || j['isFinished'] == true || finished != null || usados >= maxIntentosMedGuess;

    final terminos = <TerminoMedGuess>[];
    for (final t in (j['terms'] is List ? j['terms'] as List : const [])) {
      if (t is Map) {
        final mascara = (t['mask'] ?? '').toString();
        final display = (t['display'] ?? '').toString();
        if (mascara.isEmpty && display.isEmpty) continue;
        terminos.add(TerminoMedGuess(
          mascara.isNotEmpty ? mascara : '_' * display.length,
          completo: terminado && display.isNotEmpty ? display : null,
        ));
      }
    }

    String? respuesta;
    if (terminado) {
      final a = finished?['answer'] ?? j['answer'];
      if (a is String && a.trim().isNotEmpty) {
        respuesta = a.trim().toUpperCase();
      } else {
        final completos = [for (final t in terminos) if (t.completo != null) t.completo!];
        if (completos.isNotEmpty) respuesta = completos.first.toUpperCase();
      }
    }

    return EstadoMedGuess(
      categoria: (j['category'] ?? '').toString().trim(),
      intentosUsados: usados.clamp(0, maxIntentosMedGuess),
      resuelto: resuelto,
      terminado: terminado,
      intentos: intentos,
      terminos: terminos,
      pistas: [
        for (final p in (j['cluesUnlocked'] is List ? j['cluesUnlocked'] as List : const []))
          if (p is String && p.trim().isNotEmpty) p.trim(),
      ],
      totalPistas: j['totalClues'] is num ? (j['totalClues'] as num).toInt() : 0,
      respuesta: respuesta,
    );
  }

  static EstadoMedGuess? decode(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map ? EstadoMedGuess.fromJson(Map<String, dynamic>.from(d)) : null;
    } catch (_) {
      return null;
    }
  }
}

/// Lo que se puede teclear: A-Z, sin tildes ni Ñ (el servidor las quita igualmente al normalizar).
String limpiarIntentoMedGuess(String texto) {
  const tildes = {'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N'};
  final b = StringBuffer();
  for (final c in texto.toUpperCase().split('')) {
    final l = tildes[c] ?? c;
    if (RegExp(r'^[A-Z]$').hasMatch(l)) b.write(l);
  }
  final s = b.toString();
  return s.length > largoIntentoMedGuess ? s.substring(0, largoIntentoMedGuess) : s;
}

/// El color de cada tecla: lo mejor que se sabe de la letra en todos los intentos.
Map<String, LetraMedGuess> estadoTeclasMedGuess(List<IntentoMedGuess> intentos) {
  int peso(LetraMedGuess e) => switch (e) {
        LetraMedGuess.encontrada || LetraMedGuess.conocida => 2,
        LetraMedGuess.ausente => 1,
      };
  final out = <String, LetraMedGuess>{};
  for (final it in intentos) {
    for (var i = 0; i < it.palabra.length && i < it.resultado.length; i++) {
      final l = it.palabra[i];
      final e = it.resultado[i] == LetraMedGuess.conocida ? LetraMedGuess.encontrada : it.resultado[i];
      final previo = out[l];
      if (previo == null || peso(e) > peso(previo)) out[l] = e;
    }
  }
  return out;
}

/// Los errores del servidor, en castellano (los de la web y alguno más).
String mensajeErrorMedGuess(String? error) {
  final e = (error ?? '').trim();
  if (e == 'INVALID_WORD') return 'Esa palabra no está en el diccionario';
  if (e.toLowerCase().contains('exactly 5 letters')) return 'Tiene que tener 5 letras';
  if (e == 'Already solved') return 'El reto de hoy ya está resuelto';
  if (e == 'No attempts left') return 'Ya no te quedan intentos hoy';
  if (e.contains('No medguess daily configured')) return 'Hoy no hay MedGuess. Vuelve mañana';
  return e.isEmpty ? 'Algo ha fallado' : e;
}
