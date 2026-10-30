// El cliente HTTP de todas las llamadas al backend con la sesión del usuario.
//
// Si el backend contesta 401 (token caducado antes de tiempo, reloj del móvil adelantado, sesión
// renovada en otra pestaña…), pide un token nuevo y repite la MISMA petición una vez con él. Así las
// pantallas no tienen que saber nada de renovar: un 401 que sobrevive al reintento es de verdad.
//
// - Solo reintenta peticiones que se puedan rehacer tal cual (`http.Request`, con el cuerpo en
//   memoria) y que llevaran `Authorization: Bearer …`.
// - La renovación la decide [renovar] (ApiService.tokenTrasRechazo): si otra petición ya renovó, da el
//   token nuevo sin volver a renovar; si no se puede (la sesión ha muerto), devuelve null y se
//   entrega el 401 original.

import 'package:http/http.dart' as http;

class ClienteConSesion extends http.BaseClient {
  final http.Client _interno;

  /// Recibe el token rechazado y devuelve uno distinto con el que reintentar, o null.
  final Future<String?> Function(String rechazado) renovar;

  ClienteConSesion(this._interno, {required this.renovar});

  static const _prefijo = 'Bearer ';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final respuesta = await _interno.send(request);
    final auth = request.headers['Authorization'] ?? request.headers['authorization'];
    if (respuesta.statusCode != 401 || request is! http.Request || auth == null || !auth.startsWith(_prefijo)) {
      return respuesta;
    }

    // El 401 se lee entero: si al final no se puede reintentar, se devuelve tal cual.
    final cuerpo = await respuesta.stream.toBytes();
    final original = http.StreamedResponse(
      Stream.value(cuerpo),
      respuesta.statusCode,
      contentLength: cuerpo.length,
      request: respuesta.request,
      headers: respuesta.headers,
      reasonPhrase: respuesta.reasonPhrase,
    );

    final rechazado = auth.substring(_prefijo.length);
    final String? nuevo;
    try {
      nuevo = await renovar(rechazado);
    } catch (_) {
      return original;
    }
    if (nuevo == null || nuevo.isEmpty || nuevo == rechazado) return original;

    final otra = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = request.bodyBytes;
    otra.headers.remove('authorization');
    otra.headers['Authorization'] = '$_prefijo$nuevo';
    return _interno.send(otra);
  }

  @override
  void close() => _interno.close();
}
