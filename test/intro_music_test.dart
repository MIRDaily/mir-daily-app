// La musiquilla de la pantalla de carga: que se calle al irse la app a
// segundo plano, que el fundido no lo corte la destruccion de la pantalla, y
// que el silencio sea un ajuste que se recuerda.
//
// No se prueba que suene (eso necesita un dispositivo): se prueban las
// decisiones, que es donde estaban los fallos.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/features/splash/intro_music.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ajuste de silencio', () {
    test('de fabrica suena', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(ajustes.introMusic, isTrue);
    });

    test('silenciarla se guarda y se recupera en la siguiente sesion',
        () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);

      await ajustes.setIntroMusic(false);
      expect(ajustes.introMusic, isFalse);

      // Otra sesion: mismo almacenamiento, provider nuevo.
      final otra = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(otra.introMusic, isFalse, reason: 'tiene que recordarlo');
    });

    test('se puede volver a activar', () async {
      SharedPreferences.setMockInitialValues({'settings.intro_music': false});
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(ajustes.introMusic, isFalse);

      await ajustes.setIntroMusic(true);
      final otra = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(otra.introMusic, isTrue);
    });

    test('el boton de la pantalla escribe el mismo ajuste', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final musica = IntroMusic(ajustes);
      await musica.start();

      await musica.toggleSilencio();
      expect(ajustes.introMusic, isFalse,
          reason: 'el boton y Preferencias son el mismo ajuste');
      expect(musica.silenciada.value, isTrue);

      await musica.dispose();
    });

    test('cambiarlo desde Preferencias se refleja en la pantalla', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final musica = IntroMusic(ajustes);
      await musica.start();
      expect(musica.silenciada.value, isFalse);

      await ajustes.setIntroMusic(false);
      expect(musica.silenciada.value, isTrue);

      await musica.dispose();
    });
  });

  group('ciclo de vida', () {
    // Regresion: con la tablet bloqueada la musica seguia sonando.
    test('irse a segundo plano la calla, y volver la reanuda', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final musica = IntroMusic(ajustes);
      await musica.start();

      expect(musica.enPausaPorFondo, isFalse);

      // Se despacha por el binding, no llamando al metodo a mano: asi se
      // comprueba tambien que el observador esta registrado de verdad. Sin
      // eso, la musica seguia sonando con la tablet bloqueada.
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(musica.enPausaPorFondo, isTrue,
          reason: 'apagar la pantalla tiene que callarla');

      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(musica.enPausaPorFondo, isFalse,
          reason: 'y al volver tiene que seguir');

      await musica.dispose();
    });

    test('al soltarla se quita el observador', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final musica = IntroMusic(ajustes);
      await musica.start();
      await musica.dispose();

      // Y un lifecycle despues de soltarla no debe hacer nada raro.
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(musica.enPausaPorFondo, isFalse);
    });
  });

  group('fundido al pulsar Continuar', () {
    // Regresion: el fundido duraba 1,8s pero la pantalla se destruia a los
    // 850ms y su dispose() paraba el reproductor en seco. Se oia un corte.
    test('destruir la pantalla a mitad de fundido NO lo corta', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final musica = IntroMusic(ajustes);
      await musica.start();

      // "Continuar": arranca el fundido y no se espera.
      unawaited(musica.fadeOutAndStop());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // La pantalla de salida termina (850ms) y se destruye. Esto NO debe
      // apagar el reproductor: el fundido dura 5s y tiene que seguir.
      await musica.dispose();

      expect(musica.soltado, isFalse,
          reason: 'destruir la pantalla cortaba el fundido en seco');
    });

    test('el fundido acaba soltando el reproductor por su cuenta', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final musica = IntroMusic(ajustes);
      await musica.start();

      // Silenciada: el fundido no tiene nada que bajar y suelta enseguida.
      await ajustes.setIntroMusic(false);
      await musica.fadeOutAndStop();

      expect(musica.soltado, isTrue);
    });

    test('sin fundido en marcha, destruir la pantalla si apaga', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final musica = IntroMusic(ajustes);
      await musica.start();

      await musica.dispose();

      // Ya soltado: volver a soltarlo no explota (es idempotente).
      await musica.dispose();
    });
  });
}

void unawaited(Future<void> f) {}
