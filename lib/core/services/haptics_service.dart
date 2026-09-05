import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Vibración fiable multi-fabricante.
///
/// En Android, `HapticFeedback.lightImpact()/mediumImpact()/heavyImpact()` de
/// Flutter pasan por `View.performHapticFeedback`, que en muchas capas OEM
/// (Oppo/OnePlus/Realme con ColorOS, entre otras) queda silenciado por el
/// interruptor de "vibración táctil / feedback háptico" del sistema aunque la
/// vibración general esté activada — de ahí que a veces no se note nada. Aquí
/// se llama directamente al `Vibrator` nativo (canal en `MainActivity.kt`),
/// que solo depende del interruptor general de vibración. Si ese canal no
/// está disponible por lo que sea (p. ej. el APK instalado es de antes de
/// añadirlo, y solo se ha hecho hot reload/restart en vez de reinstalar), cae
/// al `HapticFeedback` de Flutter en vez de quedarse callado del todo.
class HapticsService {
  HapticsService._();

  static const _channel = MethodChannel('com.mirdaily.app/haptics');

  /// Se apaga en cuanto el canal nativo falla una vez.
  ///
  /// No es paranoia: el APK instalado puede ser de antes de que existiera el
  /// canal (hot restart no reinstala la parte nativa). Sin esto, cada llamada
  /// volvería a intentarlo y a fallar, y para una háptica continua eso son
  /// decenas de excepciones por segundo.
  static bool _nativoVivo = true;

  /// Solo para tests: finge la plataforma.
  ///
  /// La vía nativa está detrás de `Platform.isAndroid`, y los tests corren en
  /// el escritorio. Sin esta costura no habría forma de comprobar cómo se
  /// porta el canal —por ejemplo, que un método que falte no tumbe el resto—,
  /// que es justo donde estuvo el fallo.
  @visibleForTesting
  static bool? debugForzarAndroid;

  static bool get _esAndroid => debugForzarAndroid ?? Platform.isAndroid;

  /// Solo para tests: deja el servicio como recién arrancado.
  @visibleForTesting
  static void debugReset() {
    _nativoVivo = true;
    _metodosQueNoEstan.clear();
    _capacidades = null;
    _sondaLanzada = false;
    debugForzarAndroid = null;
  }

  /// Si se puede pedir una intensidad CONCRETA, y no solo un preset.
  ///
  /// Es lo que decide si la háptica del sobre puede ser de verdad continua
  /// (Android, con amplitud 0-255) o hay que fingirla con un tren de pulsos
  /// (iOS, donde `HapticFeedback` solo ofrece cuatro pesos fijos).
  static bool get modulaIntensidad => _esAndroid && _nativoVivo;

  /// Métodos que el APK instalado no conoce.
  ///
  /// El canal crece con el tiempo y el APK del móvil puede ser más viejo que
  /// el código: un `hot restart` no reinstala la parte nativa. Que falte un
  /// método NUEVO no significa que el canal esté muerto —`vibrate` lleva ahí
  /// desde el principio y sigue funcionando—, así que se apunta ese método y
  /// se sigue.
  ///
  /// Antes esto no se distinguía: cualquier fallo bajaba [_nativoVivo] y toda
  /// la vibración se iba al modo degradado. Como `cancel` se llama nada más
  /// deslizar fuera de la pestaña del sobre, bastaba un APK viejo para perder
  /// la amplitud entera sin enterarse.
  static final Set<String> _metodosQueNoEstan = {};

  static Future<bool> _invocar(
    String metodo, [
    Map<String, dynamic>? args,
    bool esencial = true,
  ]) async {
    if (!_esAndroid || !_nativoVivo) return false;
    if (_metodosQueNoEstan.contains(metodo)) return false;
    try {
      await _channel.invokeMethod(metodo, args);
      return true;
    } on MissingPluginException {
      _metodosQueNoEstan.add(metodo);
      return false;
    } catch (_) {
      if (esencial) _nativoVivo = false;
      return false;
    }
  }

  static Future<void> _native(int ms, int amplitude, Future<void> Function() fallback) async {
    if (!await _invocar('vibrate', {'ms': ms, 'amplitude': amplitude})) {
      await fallback();
    }
  }

  /// Un pulso de duración e intensidad exactas. Solo hace algo donde
  /// [modulaIntensidad] es cierto; quien llama decide qué hacer si no.
  ///
  /// Es el ladrillo de la háptica continua: reemitiendo pulsos cortos que se
  /// solapan, con la amplitud del momento, sale un zumbido sin costuras cuya
  /// fuerza sigue a lo que esté pasando en pantalla.
  static Future<void> pulse({required int ms, required int amplitude}) =>
      _invocar('vibrate', {'ms': ms, 'amplitude': amplitude.clamp(1, 255)});

  /// Un patrón completo: [timings] en ms (espera/on/off/on...) y su
  /// [amplitudes] (0-255). Devuelve `false` si no se pudo.
  static Future<bool> pattern(List<int> timings, List<int> amplitudes) =>
      _invocar('vibratePattern', {
        'timings': timings,
        'amplitudes': amplitudes,
      });

  /// Corta en seco lo que esté vibrando.
  ///
  /// Hace falta para rematar el desvanecido y para callar al salir de la
  /// pestaña a media apertura: sin esto se quedaría sonando el último pulso.
  /// `esencial: false` — cortar la vibración es una comodidad, no la base del
  /// sistema. Si el APK instalado no trae el método, se sigue vibrando.
  static Future<void> cancel() => _invocar('cancel', null, false);

  // ---- Sonda ----

  static HapticCapabilities? _capacidades;
  static bool _sondaLanzada = false;

  /// Lo último que contestó el aparato, si ya se le ha preguntado.
  static HapticCapabilities? get capacidades => _capacidades;

  /// Le pregunta al motor qué sabe hacer.
  ///
  /// La respuesta que importa es `hasAmplitudeControl`. Toda la háptica
  /// progresiva del sobre da por hecho que se puede pedir una intensidad
  /// concreta; si el motor no la tiene, Android **ignora la amplitud y vibra
  /// a full**, y la rampa no se nota por muy bien calculada que esté.
  static Future<HapticCapabilities> probe() async {
    if (!_esAndroid) {
      return _capacidades = const HapticCapabilities.noAndroid();
    }
    if (_metodosQueNoEstan.contains('capabilities')) {
      return _capacidades = const HapticCapabilities.apkViejo();
    }
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('capabilities');
      return _capacidades = HapticCapabilities(
        canalVivo: true,
        apkAlDia: true,
        tieneVibrador: r?['hasVibrator'] as bool? ?? false,
        controlaAmplitud: r?['hasAmplitudeControl'] as bool? ?? false,
        sdk: r?['sdk'] as int? ?? 0,
        aparato: r?['device'] as String? ?? '?',
      );
    } on MissingPluginException {
      // El método es nuevo: si no está, el APK instalado es anterior.
      _metodosQueNoEstan.add('capabilities');
      return _capacidades = const HapticCapabilities.apkViejo();
    } catch (_) {
      return _capacidades = const HapticCapabilities.sinCanal();
    }
  }

  /// Escupe el diagnóstico por consola, una sola vez por ejecución.
  ///
  /// Lo llama el sobre al cargarse. Es la única forma de saber si la rampa de
  /// intensidad tiene algo debajo que la respete: desde el código no se puede
  /// distinguir "mando 84 y el motor da 84" de "mando 84 y el motor da 255".
  static void logProbeOnce() {
    if (_sondaLanzada) return;
    if (!Platform.isAndroid && !Platform.isIOS) return; // en tests, silencio
    _sondaLanzada = true;
    probe().then((c) => debugPrint('[haptics] $c'));
  }

  /// Toque suave (una por tarjeta del resumen del onboarding).
  static Future<void> light() =>
      _native(18, 110, HapticFeedback.lightImpact);

  static Future<void> medium() =>
      _native(28, 180, HapticFeedback.mediumImpact);

  /// Explosión de confeti: MUCHO más fuerte y larga que un impacto suelto.
  /// La amplitud de un solo pulso ya está limitada a 255 (el máximo posible),
  /// así que la intensidad extra viene de un PATRÓN — golpe seco inicial a
  /// tope seguido de un zumbido sostenido, también a tope — en vez de un
  /// único pulso corto. Si el canal nativo no responde, se encadenan varios
  /// impactos fuertes de Flutter para no quedarse sin nada.
  static Future<void> strong() async {
    // [espera, golpe, pausa, zumbido sostenido] en ms.
    if (await pattern(const [0, 90, 40, 320], const [0, 255, 0, 255])) return;

    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.heavyImpact();
  }
}

/// Lo que el motor de vibración de este aparato sabe hacer.
class HapticCapabilities {
  const HapticCapabilities({
    required this.canalVivo,
    required this.apkAlDia,
    required this.tieneVibrador,
    required this.controlaAmplitud,
    required this.sdk,
    required this.aparato,
  });

  /// No es Android: la vía nativa no aplica y se va por los presets.
  const HapticCapabilities.noAndroid()
      : canalVivo = false,
        apkAlDia = false,
        tieneVibrador = true,
        controlaAmplitud = false,
        sdk = 0,
        aparato = 'no-Android';

  /// El canal responde a lo viejo pero no conoce los métodos nuevos: el APK
  /// instalado es anterior al código. Se arregla reinstalando, no con un hot
  /// restart.
  const HapticCapabilities.apkViejo()
      : canalVivo = true,
        apkAlDia = false,
        tieneVibrador = true,
        controlaAmplitud = false,
        sdk = 0,
        aparato = '?';

  /// El canal no contesta en absoluto.
  const HapticCapabilities.sinCanal()
      : canalVivo = false,
        apkAlDia = false,
        tieneVibrador = false,
        controlaAmplitud = false,
        sdk = 0,
        aparato = '?';

  final bool canalVivo;
  final bool apkAlDia;
  final bool tieneVibrador;

  /// **La respuesta que importa.** Si es `false`, Android ignora la amplitud
  /// de `createOneShot` y vibra siempre a full: cualquier rampa de intensidad
  /// se siente plana y al máximo desde el primer pulso.
  final bool controlaAmplitud;

  final int sdk;
  final String aparato;

  /// Si la háptica progresiva puede funcionar tal y como está montada.
  bool get puedeEscalar => canalVivo && apkAlDia && controlaAmplitud;

  @override
  String toString() {
    if (!canalVivo && aparato == 'no-Android') {
      return 'no es Android; se usan los presets de Flutter';
    }
    if (!canalVivo) {
      return 'EL CANAL NATIVO NO CONTESTA -> sin amplitud, todo por presets';
    }
    if (!apkAlDia) {
      return 'APK INSTALADO ANTIGUO (le faltan métodos del canal) -> '
          'reinstala del todo, un hot restart no toca la parte nativa';
    }
    final veredicto = controlaAmplitud
        ? 'la rampa de intensidad SE RESPETA'
        : 'SIN CONTROL DE AMPLITUD -> Android ignora la intensidad y vibra a '
            'full: la rampa no se puede notar, hay que modularla con '
            'duración/ciclo en vez de con amplitud';
    return '$aparato (SDK $sdk) vibrador=$tieneVibrador '
        'amplitud=$controlaAmplitud -> $veredicto';
  }
}
