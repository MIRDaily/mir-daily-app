// Créditos de IA del usuario: GET /api/ia/saldo, /tarifa, /movimientos y POST /cancelar.
// Puerto de la web: src/lib/ia/creditos.ts.
//
// Con el interruptor del servidor apagado, /api/ia responde 503 `apagado`: entonces `activo` es false
// y las generaciones salen sin cobro, como antes. Nada de esto es la protección: el servidor calcula
// el precio y valida plan y saldo en cada generación.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/creditos_ia.dart';
import '../models/ia.dart';

class CreditosApi {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  CreditosApi({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> _pedir(String ruta, {String method = 'GET'}) async {
    final token = await _token();
    if (token.isEmpty) throw const IaException('Inicia sesión para usar la IA', status: 401);
    final req = http.Request(method, Uri.parse('$_baseUrl/api/ia$ruta'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (method == 'POST') req.body = '{}';
    final http.Response res;
    try {
      res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const IaException('No se pudo conectar con el servidor');
    }
    Map<String, dynamic>? cuerpo;
    try {
      final j = jsonDecode(res.body);
      if (j is Map) cuerpo = Map<String, dynamic>.from(j);
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw IaException(
        cuerpo?['error'] is String ? cuerpo!['error'] as String : 'No se pudo completar la operación',
        status: res.statusCode,
        codigo: cuerpo?['codigo'] is String ? cuerpo!['codigo'] as String : '',
        datos: cuerpo,
      );
    }
    return cuerpo ?? <String, dynamic>{};
  }

  Future<SaldoIa> saldo() async => SaldoIa.fromJson(await _pedir('/saldo'));

  Future<TarifaIa> tarifa() async => TarifaIa.fromJson(await _pedir('/tarifa'));

  /// Historial de 30 en 30, por id (`antes` = el `siguiente` de la página anterior).
  Future<({List<MovimientoIa> movimientos, int? siguiente})> movimientos({int? antes}) async {
    final r = await _pedir('/movimientos?limite=30${antes != null ? '&antes=$antes' : ''}');
    final m = r['movimientos'];
    return (
      movimientos: m is List ? m.whereType<Map>().map((x) => MovimientoIa.fromJson(Map<String, dynamic>.from(x))).toList() : <MovimientoIa>[],
      siguiente: r['siguiente'] is int ? r['siguiente'] as int : null,
    );
  }

  Future<PrevisionCancelacion> cancelar(int usageId) async =>
      PrevisionCancelacion.fromJson(await _pedir('/cancelar/$usageId', method: 'POST'));
}

/// Saldo y tarifa compartidos por toda la app (un solo pedido; se refresca tras cada generación).
class CreditosIa extends ChangeNotifier {
  final CreditosApi api;
  final Random _azar;

  CreditosIa(this.api, {Random? azar}) : _azar = azar ?? Random.secure();

  /// Ya se sabe si los créditos están encendidos.
  bool cargado = false;

  /// Encendidos en el servidor: se cobra en créditos.
  bool activo = false;
  SaldoIa? saldo;
  TarifaIa? tarifa;
  Future<void>? _enCurso;

  /// Vuelve a pedir saldo y tarifa (tras cada generación, cancelación o error).
  Future<void> refrescar() {
    return _enCurso ??= () async {
      try {
        final r = await Future.wait([api.tarifa(), api.saldo()]);
        tarifa = r[0] as TarifaIa;
        saldo = r[1] as SaldoIa;
        activo = true;
      } on IaException catch (e) {
        // 503 `apagado` (o sin sesión): sin créditos, se genera como antes.
        if (e.codigo == 'apagado' || e.status == 401 || e.status == 404) {
          activo = false;
          saldo = null;
          tarifa = null;
        }
      } catch (_) {
        // Red caída: se queda lo que hubiera.
      } finally {
        cargado = true;
        _enCurso = null;
        notifyListeners();
      }
    }();
  }

  /// Primera carga, si nadie la ha pedido todavía.
  void asegurar() {
    if (!cargado && _enCurso == null) refrescar();
  }

  String? _usuario;

  /// Al cambiar de cuenta (o cerrar sesión), nada del saldo anterior: se vuelve a pedir al usarlo.
  void setUsuario(String? usuario) {
    if (usuario == _usuario) return;
    _usuario = usuario;
    cargado = false;
    activo = false;
    saldo = null;
    tarifa = null;
    // Llega desde el `update` de un ProxyProvider (en pleno build): se avisa después.
    scheduleMicrotask(notifyListeners);
  }

  /// Un clic en «Generar». Sin créditos (o sin precio) no lleva cobro.
  GeneracionIa nuevaGeneracion(int? precio) {
    final t = tarifa;
    if (!activo || t == null || precio == null) return GeneracionIa();
    return GeneracionIa(
      cobro: CobroIa(creditosAnunciados: precio, tarifaVersion: t.version, idempotencyKey: _uuid()),
    );
  }

  String _uuid() {
    final b = List<int>.generate(16, (_) => _azar.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
