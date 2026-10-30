// El cliente de MedGuess: GET /api/medguess/today y POST /api/medguess/attempt. Puerto de la web:
// src/app/medguess/services/medguessService.ts.
//
// /result no hace falta: /today ya trae el estado entero y, con la partida terminada, los términos
// completos (de ahí sale la respuesta).

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/medguess.dart';

class MedGuessException implements Exception {
  final String message;
  final int? status;

  /// Una palabra que no vale (fuera del diccionario o mal formada): la partida sigue igual.
  final bool palabraNoValida;

  const MedGuessException(this.message, {this.status, this.palabraNoValida = false});

  @override
  String toString() => message;
}

class MedGuessApi {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  MedGuessApi({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  Future<EstadoMedGuess> _pedir(String metodo, String ruta, {Map<String, dynamic>? cuerpo}) async {
    final token = await _token();
    if (token.isEmpty) throw const MedGuessException('No hay sesión activa', status: 401);
    final req = http.Request(metodo, Uri.parse('$_baseUrl/api/medguess/$ruta'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (cuerpo != null) req.body = jsonEncode(cuerpo);
    final http.Response res;
    try {
      res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const MedGuessException('No se pudo conectar con el servidor');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String? error;
      try {
        final d = jsonDecode(res.body);
        if (d is Map && d['error'] is String) error = d['error'] as String;
      } catch (_) {}
      throw MedGuessException(
        mensajeErrorMedGuess(error),
        status: res.statusCode,
        palabraNoValida: error == 'INVALID_WORD' || (error ?? '').contains('exactly 5 letters'),
      );
    }
    final estado = EstadoMedGuess.decode(res.body);
    if (estado == null) throw const MedGuessException('No se pudo leer MedGuess');
    return estado;
  }

  Future<EstadoMedGuess> hoy() => _pedir('GET', 'today');

  /// Manda un intento. Devuelve el estado de la partida después de él.
  Future<EstadoMedGuess> intentar(String palabra) => _pedir('POST', 'attempt', cuerpo: {'guess': palabra});
}
