import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/services/haptics_service.dart';

/// La sonda del motor de vibración, y lo que la rodea.
///
/// Todo esto existe por un fallo concreto: la háptica progresiva del sobre da
/// por hecho que se puede pedir una intensidad concreta, y en un motor sin
/// control de amplitud Android IGNORA la amplitud y vibra a full. La rampa se
/// calcula bien y no se nota nada. Desde Dart no hay forma de distinguirlo:
/// hay que preguntárselo al aparato.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el veredicto se lee sin saber de Android', () {
    // El mensaje va a consola y lo va a leer una persona, no un programa.
    // Tiene que decir qué pasa Y qué hacer.
    const sinAmplitud = HapticCapabilities(
      canalVivo: true,
      apkAlDia: true,
      tieneVibrador: true,
      controlaAmplitud: false,
      sdk: 34,
      aparato: 'samsung SM-X706B',
    );
    expect(sinAmplitud.puedeEscalar, isFalse);
    expect(sinAmplitud.toString(), contains('SIN CONTROL DE AMPLITUD'));
    expect(sinAmplitud.toString(), contains('samsung SM-X706B'));

    const bien = HapticCapabilities(
      canalVivo: true,
      apkAlDia: true,
      tieneVibrador: true,
      controlaAmplitud: true,
      sdk: 34,
      aparato: 'Pixel 8',
    );
    expect(bien.puedeEscalar, isTrue);
    expect(bien.toString(), contains('SE RESPETA'));

    expect(
      const HapticCapabilities.apkViejo().toString(),
      contains('reinstala'),
      reason: 'un APK viejo tiene que decir cómo se arregla',
    );
  });

  test('que falte un método NUEVO no tumba la vibración entera', () async {
    // Este era el segundo sospechoso del fallo. `cancel` se añadió después que
    // `vibrate`, y se llama nada más deslizar fuera de la pestaña del sobre.
    // Con un APK anterior lanzaba MissingPluginException y, como cualquier
    // fallo bajaba la bandera del canal, se perdía la amplitud entera —y con
    // ella el escalado— sin que nadie se enterara.
    final llamadas = <String>[];
    HapticsService.debugReset();
    HapticsService.debugForzarAndroid = true;
    addTearDown(HapticsService.debugReset);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mirdaily.app/haptics'),
      (call) async {
        llamadas.add(call.method);
        // El APK viejo solo conoce 'vibrate'.
        if (call.method != 'vibrate') {
          throw MissingPluginException('no está: ${call.method}');
        }
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.mirdaily.app/haptics'),
        null,
      ),
    );

    await HapticsService.cancel(); // el que falta
    await HapticsService.pulse(ms: 40, amplitude: 120); // el de siempre

    expect(
      llamadas,
      contains('vibrate'),
      reason: 'el método viejo tiene que seguir llegando al canal',
    );
  });
}
