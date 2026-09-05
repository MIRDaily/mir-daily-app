import 'dart:math';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/services/haptics_service.dart';

/// Los pesos de golpe que ofrece Flutter cuando NO se puede pedir una
/// intensidad concreta. Son cuatro escalones fijos, y son todo lo que hay en
/// iOS.
enum HapticShot { tick, light, medium, heavy }

/// Por dónde salen las vibraciones. Existe para poder enchufar un doble en los
/// tests: la háptica no se puede ver ni oír, así que la única forma de
/// comprobar que sube, se mantiene y se desvanece es apuntar lo que sale.
abstract class HapticDriver {
  /// Si se puede pedir una amplitud concreta (Android) o solo un peso fijo.
  bool get modulates;

  /// Un pulso de [ms] a [amplitude] (1-255). Solo si [modulates].
  void pulse(int ms, int amplitude);

  /// Uno de los cuatro pesos fijos. La vía de iOS.
  void shot(HapticShot shot);

  /// Un patrón completo de golpes, para el reventón final.
  void pattern(List<int> timings, List<int> amplitudes);

  /// Corta en seco.
  void cancel();
}

/// El de verdad: habla con [HapticsService].
class _RealHapticDriver implements HapticDriver {
  const _RealHapticDriver();

  @override
  bool get modulates => HapticsService.modulaIntensidad;

  @override
  void pulse(int ms, int amplitude) =>
      HapticsService.pulse(ms: ms, amplitude: amplitude);

  @override
  void shot(HapticShot s) {
    switch (s) {
      case HapticShot.tick:
        HapticFeedback.selectionClick();
      case HapticShot.light:
        HapticsService.light();
      case HapticShot.medium:
        HapticsService.medium();
      case HapticShot.heavy:
        HapticFeedback.heavyImpact();
    }
  }

  @override
  void pattern(List<int> timings, List<int> amplitudes) =>
      HapticsService.pattern(timings, amplitudes);

  @override
  void cancel() => HapticsService.cancel();
}

/// La háptica de abrir el sobre: sube con el gesto, se queda quieta si te
/// paras a medias, se desvanece si sueltas, y remata con un golpe seco.
///
/// El problema de fondo es que Flutter no tiene intensidad: `HapticFeedback`
/// son cuatro presets y nada más. Aquí hay dos caminos según lo que dé el
/// aparato:
///
///  - **Con amplitud** (Android, por el canal nativo de [HapticsService]): un
///    zumbido de verdad. Se reemiten pulsos cortos que SE SOLAPAN —75 ms cada
///    50 ms—, así que no hay costuras, y la amplitud de cada uno sale del
///    avance del momento. Eso es intensidad continua real.
///  - **Sin amplitud** (iOS): se finge con un tren de pulsos, subiendo a la
///    vez la CADENCIA y el PESO. No llega a ser un zumbido, pero la sensación
///    de que aquello va a más sí se transmite.
///
/// Todo va montado sobre [update], que llama el bucle del juego. No hay
/// temporizadores sueltos: si el sobre se pausa al cambiar de pestaña, la
/// vibración se para con él y no se queda un móvil zumbando en el bolsillo.
class PackHaptics {
  PackHaptics({HapticDriver? driver})
      : _driver = driver ?? const _RealHapticDriver();

  final HapticDriver _driver;

  // ---- Cómo se traduce el avance a fuerza ----
  //
  // La primera versión de esto modulaba SOLO la amplitud, y en la tablet no se
  // notaba ninguna rampa: arrancaba ya al máximo. El motivo lo dio la sonda de
  // [HapticsService.probe] — `samsung SM-X700 amplitud=false`. En un motor sin
  // control de amplitud, Android IGNORA el valor de `createOneShot` y vibra a
  // tope siempre. Daba igual mandar 84 que 247.
  //
  // Así que la intensidad sale ahora de DOS mandos, y el que manda de verdad
  // es el primero:
  //
  //  1. **Duración del pulso.** Un motor de móvil tarda unos 30 ms en coger
  //     vueltas. Un pulso de 18 ms se queda en un roce; uno de 95 ms llega a
  //     girar del todo. Esto funciona en CUALQUIER motor, tenga amplitud o no,
  //     porque es física del propio motor y no una función del sistema.
  //  2. **Hueco entre pulsos.** De golpes sueltos y espaciados —que se sienten
  //     como un trinquete— a pulsos que se solapan y salen como un zumbido
  //     continuo.
  //  3. La amplitud se sigue mandando, y en un aparato que sí la respete
  //     (Pixel y compañía) suma suavidad. Donde no, no estorba.

  /// Duración del pulso: de un roce a un zumbido de motor entero.
  ///
  /// **Si el arranque no se nota en la tablet, sube [_msMin].** Es el número
  /// que gobierna lo flojo que puede llegar a ser el toque más suave.
  static const int _msMin = 18;
  static const int _msMax = 95;

  /// Hueco entre pulsos. Arriba del todo el hueco es MENOR que la duración,
  /// así que los pulsos se pisan y el zumbido sale sin costuras.
  static const double _huecoLento = 0.135;
  static const double _huecoRapido = 0.070;

  /// La curva del avance a la duración. Casi recta: con una curva agresiva el
  /// tramo bajo se saltaba de golpe al alto y volvía a parecer que no escala.
  static const double _curva = 0.9;

  /// La amplitud, para los aparatos que la respeten. Donde no, se ignora.
  static const int _ampMin = 90;
  static const int _ampMax = 255;

  /// Sin amplitud, el tren de pulsos va de lento a muy rápido.
  static const double _trenLento = 0.095;
  static const double _trenRapido = 0.030;

  /// Lo que tarda en apagarse al soltar sin abrir.
  static const double _desvanecido = 0.42;

  double _nivel = 0.0;
  double _acumulado = 0.0;
  double _reloj = 0.0;

  /// Desde dónde se desvanece, y por dónde va. [_fadeT] en 1 = no hay
  /// desvanecido en curso.
  double _fadeDesde = 0.0;
  double _fadeT = 1.0;

  /// El guion del golpe final, si está sonando: pares (segundo, disparo).
  List<(double, HapticShot)>? _guion;
  double _guionT = 0.0;
  int _guionPaso = 0;

  /// Lo que se está sintiendo ahora mismo, 0..1. Solo para tests.
  @visibleForTesting
  double get level => _nivel;

  /// El dedo acaba de posarse en el sobre. Un toque seco para marcar que se ha
  /// agarrado, antes de que el gesto tenga avance que transmitir.
  /// Del mismo tamaño que el primer escalón de la rampa, no más.
  ///
  /// Antes daba un pulso bastante más gordo que el arranque del gesto, así que
  /// lo primero que se sentía era un golpe y lo siguiente, medio segundo más
  /// flojo. Eso solo ya se leía como "empieza al máximo y luego baja".
  void grab() {
    if (_driver.modulates) {
      _driver.pulse(_msMin, _ampMin);
    } else {
      _driver.shot(HapticShot.tick);
    }
  }

  /// El gesto va por [avance] (0..1). Mientras no cambie, la vibración se
  /// queda exactamente donde está: es lo que hace que pararse a medias se
  /// sienta como sostener algo tenso.
  void driveTo(double avance) {
    _fadeT = 1.0; // cualquier desvanecido en curso queda anulado
    _nivel = avance.clamp(0.0, 1.0);
  }

  /// Se ha soltado sin abrirlo: la vibración baja hasta callarse.
  void fadeOut() {
    if (_nivel <= 0 || _fadeT < 1.0) return;
    _fadeDesde = _nivel;
    _fadeT = 0.0;
  }

  /// El sobre se ha abierto: golpe seco.
  ///
  /// Es el único momento que no depende del avance, y el que tiene que
  /// separarse de todo lo anterior. Con amplitud es un patrón —dos golpes a
  /// tope y un retumbe que decae—; sin ella, tres impactos fuertes seguidos,
  /// que es lo más parecido a un golpe grande que se puede montar con pesos
  /// fijos.
  void pop() {
    _nivel = 0;
    _fadeT = 1.0;
    _acumulado = 0;

    if (_driver.modulates) {
      _driver.pattern(
        // golpe seco, respiro cortísimo, segundo golpe, y retumbe que cae.
        const [0, 80, 26, 62, 30, 210],
        const [0, 255, 0, 235, 0, 130],
      );
      return;
    }

    _guion = const [
      (0.0, HapticShot.heavy),
      (0.045, HapticShot.heavy),
      (0.095, HapticShot.heavy),
      (0.180, HapticShot.medium),
    ];
    _guionT = 0;
    _guionPaso = 0;
  }

  /// Silencio inmediato. Lo llama el juego al perderse de vista.
  void stop() {
    _nivel = 0;
    _fadeT = 1.0;
    _acumulado = 0;
    _guion = null;
    _driver.cancel();
  }

  void update(double dt) {
    _reloj += dt;

    if (_avanzarGuion(dt)) return;

    if (_fadeT < 1.0) {
      _fadeT = (_fadeT + dt / _desvanecido).clamp(0.0, 1.0);
      // Cae deprisa y luego se arrastra: es como se apaga algo que se suelta,
      // y evita el corte seco de una bajada recta.
      _nivel = _fadeDesde * (1 - Curves.easeOutCubic.transform(_fadeT));
      if (_fadeT >= 1.0) {
        _nivel = 0;
        _driver.cancel();
      }
    }

    if (_nivel <= 0.001) return;

    _acumulado += dt;
    final hueco = _driver.modulates
        ? _huecoLento + (_huecoRapido - _huecoLento) * _nivel
        : _trenLento + (_trenRapido - _trenLento) * _nivel;

    if (_acumulado < hueco) return;
    _acumulado = 0;

    if (_driver.modulates) {
      _driver.pulse(_duracion(), _amplitud());
    } else {
      _driver.shot(_peso());
    }
  }

  /// Lo que dura el pulso de este instante. **Este es el mando de intensidad**
  /// en un motor sin control de amplitud.
  int _duracion() {
    final base = _msMin + (_msMax - _msMin) * pow(_nivel, _curva);

    // Un temblor en la duración para que el zumbido tenga GRANO. Un pulso
    // siempre igual se siente como un electrodoméstico; lo que se busca aquí
    // es papel tensándose, que es irregular. Y el grano se acelera con el
    // avance, así que el propio temblor cuenta que aquello va a reventar.
    //
    // Se APLANA al llegar arriba: a media carga la textura es lo interesante,
    // pero en el último tramo lo que se quiere es que el motor no pare.
    final profundidad = 0.18 * (1 - _nivel * 0.8);
    final grano =
        1 - profundidad * (0.5 + 0.5 * sin(_reloj * (26 + 40 * _nivel)));

    return (base * grano).round().clamp(8, _msMax);
  }

  /// La amplitud, para quien la respete. Donde no, Android la ignora y vibra a
  /// tope: por eso NO puede ser el único mando de intensidad.
  int _amplitud() =>
      (_ampMin + (_ampMax - _ampMin) * pow(_nivel, _curva)).round().clamp(
            1,
            _ampMax,
          );

  /// El peso del golpe cuando no hay amplitud que valga.
  HapticShot _peso() {
    if (_nivel < 0.26) return HapticShot.tick;
    if (_nivel < 0.52) return HapticShot.light;
    if (_nivel < 0.80) return HapticShot.medium;
    return HapticShot.heavy;
  }

  /// Devuelve `true` si el golpe final está sonando y manda él.
  bool _avanzarGuion(double dt) {
    final guion = _guion;
    if (guion == null) return false;

    _guionT += dt;
    while (_guionPaso < guion.length && _guionT >= guion[_guionPaso].$1) {
      _driver.shot(guion[_guionPaso].$2);
      _guionPaso++;
    }
    if (_guionPaso >= guion.length) _guion = null;
    return true;
  }
}
