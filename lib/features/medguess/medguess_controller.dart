// El estado de una partida de MedGuess en pantalla. Puerto de la web: el hook useMedGuess.
//
// La partida la lleva el servidor (intentos, letras descubiertas, pistas): aquí solo se guarda lo
// que se está tecleando y lo que hace falta para animar el intento recién enviado.

import 'package:flutter/foundation.dart';

import '../../core/models/medguess.dart';
import '../../core/services/medguess_api.dart';

/// Lo que pasó al enviar, para que la pantalla elija animación, háptica y sonido.
enum ResultadoEnvio { revelado, noValida, error }

class MedGuessController extends ChangeNotifier {
  final MedGuessApi _api;

  MedGuessController(this._api);

  EstadoMedGuess? estado;
  bool cargando = true;
  String? errorCarga;

  /// Lo tecleado en la fila activa.
  String actual = '';
  bool enviando = false;

  /// La fila que se está volteando ahora mismo (el último intento), y un contador que cambia con
  /// cada intento para que la animación arranque de nuevo.
  int? filaRevelando;
  int cicloRevelado = 0;

  /// Sube con cada palabra rechazada: la fila activa tiembla.
  int sacudidas = 0;

  /// Un aviso corto (palabra no válida, sin conexión…). Lo borra el siguiente toque.
  String? aviso;

  bool _vivo = true;

  bool get puedeTeclear => !cargando && !enviando && estado != null && !estado!.terminado;
  bool get puedeEnviar => puedeTeclear && actual.length == largoIntentoMedGuess;

  Future<void> cargar() async {
    cargando = true;
    errorCarga = null;
    _avisar();
    try {
      estado = await _api.hoy();
    } on MedGuessException catch (e) {
      errorCarga = e.message;
    } catch (_) {
      errorCarga = 'No se pudo cargar MedGuess';
    }
    cargando = false;
    _avisar();
  }

  void teclear(String letra) {
    if (!puedeTeclear) return;
    aviso = null;
    actual = limpiarIntentoMedGuess(actual + letra);
    _avisar();
  }

  void borrar() {
    if (!puedeTeclear || actual.isEmpty) return;
    aviso = null;
    actual = actual.substring(0, actual.length - 1);
    _avisar();
  }

  Future<ResultadoEnvio?> enviar() async {
    if (!puedeTeclear) return null;
    if (actual.length != largoIntentoMedGuess) {
      aviso = 'Tiene que tener 5 letras';
      sacudidas++;
      _avisar();
      return ResultadoEnvio.noValida;
    }
    enviando = true;
    aviso = null;
    _avisar();
    try {
      final nuevo = await _api.intentar(actual);
      estado = nuevo;
      actual = '';
      filaRevelando = nuevo.intentos.length - 1;
      cicloRevelado++;
      return ResultadoEnvio.revelado;
    } on MedGuessException catch (e) {
      aviso = e.message;
      if (e.palabraNoValida) {
        sacudidas++;
        return ResultadoEnvio.noValida;
      }
      return ResultadoEnvio.error;
    } catch (_) {
      aviso = 'No se pudo enviar el intento';
      return ResultadoEnvio.error;
    } finally {
      enviando = false;
      _avisar();
    }
  }

  void _avisar() {
    if (_vivo) notifyListeners();
  }

  @override
  void dispose() {
    _vivo = false;
    super.dispose();
  }
}
