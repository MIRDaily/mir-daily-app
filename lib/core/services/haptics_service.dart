import 'dart:io';

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

  static Future<void> _native(int ms, int amplitude, Future<void> Function() fallback) async {
    if (!Platform.isAndroid) {
      await fallback();
      return;
    }
    try {
      await _channel.invokeMethod('vibrate', {'ms': ms, 'amplitude': amplitude});
    } catch (_) {
      await fallback();
    }
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
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('vibratePattern', {
          // [espera, golpe, pausa, zumbido sostenido] en ms.
          'timings': const [0, 90, 40, 320],
          'amplitudes': const [0, 255, 0, 255],
        });
        return;
      } catch (_) {
        // Sigue abajo con el fallback.
      }
    }
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.heavyImpact();
  }
}
