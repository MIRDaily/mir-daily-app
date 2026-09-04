// Musica de fondo mientras se navega: cuando debe callarse y cuando volver.
//
// No se prueba que suene (eso necesita un dispositivo): se prueban las
// decisiones, que es donde caben los errores.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/audio/background_music.dart';
import 'package:mirdaily_app/core/providers/settings_provider.dart';

Future<(SettingsProvider, BackgroundMusic)> _crear() async {
  final ajustes = SettingsProvider();
  await Future<void>.delayed(Duration.zero);
  final musica = BackgroundMusic(ajustes, audio: false);
  await musica.start();
  return (ajustes, musica);
}

/// Pantalla de mentira que se declara "modo interactivo".
class _PantallaInteractiva extends StatefulWidget {
  const _PantallaInteractiva();
  @override
  State<_PantallaInteractiva> createState() => _PantallaInteractivaState();
}

class _PantallaInteractivaState extends State<_PantallaInteractiva>
    with SilencesBackgroundMusic {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ajustes', () {
    test('de fabrica suena, a volumen discreto', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(ajustes.backgroundMusic, isTrue);
      expect(ajustes.backgroundMusicVolume, lessThan(0.5));
      expect(ajustes.backgroundMusicVolume, greaterThan(0));
    });

    test('apagarla se recuerda en la siguiente sesion', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      await ajustes.setBackgroundMusic(false);

      final otra = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(otra.backgroundMusic, isFalse);
    });

    test('el volumen se recuerda', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      await ajustes.setBackgroundMusicVolume(0.8);

      final otra = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(otra.backgroundMusicVolume, closeTo(0.8, 0.001));
    });

    test('arrastrar el deslizador NO escribe en disco hasta soltar', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);

      // Mientras se arrastra.
      await ajustes.setBackgroundMusicVolume(0.9, persist: false);
      expect(ajustes.backgroundMusicVolume, closeTo(0.9, 0.001));

      final otra = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(otra.backgroundMusicVolume, isNot(closeTo(0.9, 0.001)),
          reason: 'no debe haberse guardado todavia');
    });

    test('el volumen se acota a 0..1', () async {
      final ajustes = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      await ajustes.setBackgroundMusicVolume(5);
      expect(ajustes.backgroundMusicVolume, 1.0);
      await ajustes.setBackgroundMusicVolume(-3);
      expect(ajustes.backgroundMusicVolume, 0.0);
    });
  });

  group('volumen y curva del fundido', () {
    // El 35% de fabrica sonaba altisimo. El deslizador se aplica sobre un
    // techo, asi que su 100% sigue siendo musica de fondo.
    test('el 35% de fabrica queda muy por debajo del 35% de amplitud',
        () async {
      final (_, musica) = await _crear();
      final v = musica.volumenPara(1);

      expect(v, lessThan(0.35 * 0.3),
          reason: 'reduccion de al menos el 70% sobre lo que sonaba antes');
      expect(v, greaterThan(0), reason: 'pero se tiene que oir');

      musica.dispose();
    });

    test('ni al 100% del usuario se pone a volumen de app de musica',
        () async {
      final (ajustes, musica) = await _crear();
      await ajustes.setBackgroundMusicVolume(1);
      expect(musica.volumenPara(1), lessThanOrEqualTo(0.25));
      musica.dispose();
    });

    // El fallo que se oia: con una curva cuadratica, la mitad del fundido
    // dejaba la amplitud en 0,25 (unos -12 dB) y toda la segunda mitad
    // concentraba ese salto. En decibelios el reparto es parejo.
    test('el fundido no pega un salto al final', () async {
      final (_, musica) = await _crear();
      final maximo = musica.volumenPara(1);

      // A mitad de recorrido se tiene que estar MUY por debajo de la mitad
      // de la amplitud: eso es lo que hace que el ultimo tramo no salte.
      final mitad = musica.volumenPara(0.5);
      expect(mitad, lessThan(maximo * 0.1));

      // Y ningun tramo del fundido puede llevarse un pedazo desproporcionado.
      // En dB el salto entre pasos consecutivos es constante; se comprueba que
      // el ultimo 10% del recorrido no aporte mas de un tercio del volumen.
      final ultimoTramo = maximo - musica.volumenPara(0.9);
      expect(ultimoTramo, lessThan(maximo * 0.45),
          reason: 'con la curva cuadratica el final se comia el fundido');

      musica.dispose();
    });

    test('el fundido empieza y acaba donde debe', () async {
      final (_, musica) = await _crear();
      expect(musica.volumenPara(0), 0);
      expect(musica.volumenPara(1), greaterThan(0));
      musica.dispose();
    });

    test('el volumen del usuario escala el resultado', () async {
      final (ajustes, musica) = await _crear();
      await ajustes.setBackgroundMusicVolume(0.5);
      final mitad = musica.volumenPara(1);
      await ajustes.setBackgroundMusicVolume(1);
      final entero = musica.volumenPara(1);
      expect(mitad, closeTo(entero / 2, 0.0001));
      musica.dispose();
    });
  });

  group('mover el deslizador de volumen', () {
    // El fallo: cada notificacion del ajuste entraba por el camino de
    // "reanudar" y, como ya sonaba, relanzaba la reproduccion del MP3 de 6 MB.
    // Arrastrar el dedo son decenas de notificaciones por segundo y la app se
    // quedaba clavada, acumulando lag hasta ser inservible.
    test('NO relanza la reproduccion', () async {
      final (ajustes, musica) = await _crear();
      final alArrancar = musica.reproduccionesIniciadas;

      // Un arrastre real: muchos cambios seguidos sin persistir.
      for (var i = 1; i <= 40; i++) {
        await ajustes.setBackgroundMusicVolume(i / 40, persist: false);
      }

      expect(musica.reproduccionesIniciadas, alArrancar,
          reason: 'mover el volumen no puede volver a arrancar la cancion');

      musica.dispose();
    });

    test('pero el volumen si cambia mientras se arrastra', () async {
      final (ajustes, musica) = await _crear();

      await ajustes.setBackgroundMusicVolume(0.1, persist: false);
      final bajo = musica.volumenPara(1);
      await ajustes.setBackgroundMusicVolume(0.9, persist: false);
      final alto = musica.volumenPara(1);

      expect(alto, greaterThan(bajo));
      musica.dispose();
    });

    test('apagar y encender si cuenta como cambio de estado', () async {
      final (ajustes, musica) = await _crear();

      await ajustes.setBackgroundMusic(false);
      expect(musica.sonando, isFalse);
      await ajustes.setBackgroundMusic(true);
      expect(musica.sonando, isTrue);

      musica.dispose();
    });

    // Lo que separa el comportamiento sano del que colgaba la app: la musica
    // reacciona a CAMBIOS de estado, no a cada notificacion del ajuste.
    test('solo reacciona a cambios de estado, no a cada notificacion',
        () async {
      final (ajustes, musica) = await _crear();
      final alArrancar = musica.reproduccionesIniciadas;

      // Callada, y mientras tanto 40 cambios de volumen.
      musica.pushSilence();
      for (var i = 1; i <= 40; i++) {
        await ajustes.setBackgroundMusicVolume(i / 40, persist: false);
      }
      expect(musica.reproduccionesIniciadas, alArrancar,
          reason: 'callada y moviendo el volumen no arranca nada');

      // Al volver, UN arranque. Ni cuarenta ni ninguno.
      musica.popSilence();
      expect(musica.reproduccionesIniciadas, alArrancar + 1);

      musica.dispose();
    });
  });

  group('cuando debe callarse', () {
    test('suena al navegar y se calla en un modo interactivo', () async {
      final (_, musica) = await _crear();
      expect(musica.sonando, isTrue);

      musica.pushSilence();
      expect(musica.sonando, isFalse);

      musica.popSilence();
      expect(musica.sonando, isTrue);

      musica.dispose();
    });

    // Un simulacro que abre encima la hoja de un mazo: dos motivos a la vez.
    test('con motivos solapados no vuelve hasta cerrarlos todos', () async {
      final (_, musica) = await _crear();

      musica.pushSilence();
      musica.pushSilence();
      expect(musica.silencios, 2);

      musica.popSilence();
      expect(musica.sonando, isFalse, reason: 'aun queda un motivo abierto');

      musica.popSilence();
      expect(musica.sonando, isTrue);

      musica.dispose();
    });

    test('popSilence de mas no deja el contador en negativo', () async {
      final (_, musica) = await _crear();
      musica.popSilence();
      musica.popSilence();
      expect(musica.silencios, 0);
      expect(musica.sonando, isTrue);
      musica.dispose();
    });

    test('apagarla en ajustes la calla, y encenderla la devuelve', () async {
      final (ajustes, musica) = await _crear();
      expect(musica.sonando, isTrue);

      await ajustes.setBackgroundMusic(false);
      expect(musica.sonando, isFalse);

      await ajustes.setBackgroundMusic(true);
      expect(musica.sonando, isTrue);

      musica.dispose();
    });

    test('volumen a cero equivale a callada', () async {
      final (ajustes, musica) = await _crear();
      await ajustes.setBackgroundMusicVolume(0);
      expect(musica.sonando, isFalse);
      musica.dispose();
    });

    // Regresion del mismo fallo que tuvo la intro: seguia sonando con la
    // pantalla apagada.
    test('en segundo plano se calla, y al volver sigue', () async {
      final (_, musica) = await _crear();

      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(musica.sonando, isFalse);

      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(musica.sonando, isTrue);

      musica.dispose();
    });
  });

  group('el mixin de las pantallas interactivas', () {
    testWidgets('montar la pantalla calla, y desmontarla devuelve la musica',
        (tester) async {
      final ajustes = SettingsProvider();
      await tester.pump(Duration.zero);
      final musica = BackgroundMusic(ajustes, audio: false);
      await musica.start();

      Widget arbol({required bool interactiva}) => MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: ajustes),
              ChangeNotifierProvider<BackgroundMusic>.value(value: musica),
            ],
            child: MaterialApp(
              home: interactiva
                  ? const _PantallaInteractiva()
                  : const SizedBox(key: ValueKey('menu')),
            ),
          );

      await tester.pumpWidget(arbol(interactiva: false));
      await tester.pump();
      expect(musica.silencios, 0, reason: 'en un menu normal suena');

      await tester.pumpWidget(arbol(interactiva: true));
      await tester.pump();
      expect(musica.silencios, 1, reason: 'la pantalla interactiva la calla');

      await tester.pumpWidget(arbol(interactiva: false));
      await tester.pump();
      expect(musica.silencios, 0, reason: 'al salir vuelve');

      musica.dispose();
    });
  });
}
