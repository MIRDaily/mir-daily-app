import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import 'package:mirdaily_app/features/splash/loading_screen.dart';

/// Los bichos animados del fondo de la pantalla de carga: la bacteria y el
/// virión del COVID.
///
/// Un `.lottie` no es un JSON: es un zip con el JSON dentro, y el de la
/// bacteria lleva además sus 21 PNG. Si se rompiera el empaquetado, los assets
/// dejaran de estar declarados en pubspec.yaml o el paquete cambiara de
/// decodificador, desaparecerían del fondo sin que fallara nada más.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(Lottie.cache.clear);

  test('cada .lottie se abre con todo lo que lleva dentro', () async {
    for (final asset in LoadingScreenImages.animaciones) {
      final composicion = await AssetLottie(asset).load();

      expect(composicion.duration, greaterThan(Duration.zero), reason: asset);
      // La bacteria está hecha de PNG (el virión es vectorial y no trae
      // ninguno): si el zip no los resolviera, se pintaría vacía.
      expect(
        composicion.images.values.where((i) => i.loadedImage == null),
        isEmpty,
        reason: '$asset: alguna imagen del zip no se resolvió',
      );
    }
  });

  test('la precarga deja los bichos en la caché con la clave con la que se '
      'pintan', () async {
    await LoadingScreenImages.precache();

    // Misma idea que con las células: si la clave de la precarga no fuera la
    // de `Lottie.asset`, abrir el zip caería en medio de la caída, que es justo
    // lo que se quiere evitar. `evict` devuelve true solo si había algo
    // guardado con esa clave.
    for (final asset in LoadingScreenImages.animaciones) {
      expect(
        Lottie.cache.evict(AssetLottie(asset)),
        isTrue,
        reason: '$asset no quedó cacheado donde Lottie.asset va a buscarlo',
      );
    }
  });

  testWidgets('los bichos nadan acelerados, no a la velocidad del archivo',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => LoadingScreenImages.precache());

    // Son la rareza del fondo: cada uno sale en ~2 de cada 3 montajes, así que
    // se monta hasta verlos a los dos. Con 80 intentos, que falte alguno sería
    // una casualidad astronómica.
    //
    // Cada reloj se mira en el acto, con su fondo todavía montado: guardarlo
    // para el final no vale, porque el siguiente montaje tira el anterior y
    // deja el controlador suelto (y un controlador suelto siempre dice que no
    // está animando, con lo que el test pasaría a mentir).
    final vistos = <String>{};
    for (var intento = 0;
        intento < 80 &&
            vistos.length < LoadingScreenImages.animaciones.length;
        intento++) {
      await tester.pumpWidget(
        MaterialApp(key: ValueKey(intento), home: const ParticlesBackground()),
      );
      await tester.pump(const Duration(milliseconds: 50));

      for (final builder in tester.widgetList<LottieBuilder>(
        find.byType(LottieBuilder),
      )) {
        final asset = (builder.lottie as AssetLottie).assetName;
        if (!vistos.add(asset)) continue;

        // Los dos .lottie vienen a 5 s por vuelta, y a esa velocidad parecen
        // dibujos quietos: su movimiento es sutil y la pantalla dura unos
        // segundos. El número exacto es de cada Bicho.speed y se puede afinar;
        // lo que no puede volver es que giren a la velocidad del archivo.
        final reloj = builder.controller as AnimationController;
        expect(reloj.duration, isNotNull,
            reason: '$asset: sin duración no gira, onLoaded no se la puso');
        expect(reloj.duration, lessThan(const Duration(seconds: 3)),
            reason: asset);
        expect(reloj.isAnimating, isTrue, reason: asset);
      }
    }

    expect(
      vistos,
      unorderedEquals(LoadingScreenImages.animaciones),
      reason: 'algún bicho no llegó a salir en 80 fondos',
    );
  });

  testWidgets('los bichos caen en las tres capas, sobre todo en la nítida',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => LoadingScreenImages.precache());

    // Cada capa da a sus células un tamaño distinto (50-70, 80-110 y 140-200) y
    // el del bicho sale de ahí, así que las cajas de las tres no se solapan y
    // el ancho delata en cuál cayó.
    int capaDe(Bicho bicho, double ancho) {
      if (ancho < bicho.boxFor(75)) return 0;
      if (ancho < bicho.boxFor(125)) return 1;
      return 2;
    }

    final cuenta = <String, List<int>>{
      for (final asset in LoadingScreenImages.animaciones) asset: [0, 0, 0],
    };

    for (var intento = 0; intento < 60; intento++) {
      await tester.pumpWidget(
        MaterialApp(key: ValueKey(intento), home: const ParticlesBackground()),
      );
      await tester.pump(const Duration(milliseconds: 50));

      for (final builder in tester.widgetList<LottieBuilder>(
        find.byType(LottieBuilder),
      )) {
        final asset = (builder.lottie as AssetLottie).assetName;
        final bicho = Bicho.todos.firstWhere((b) => b.asset == asset);
        cuenta[asset]![capaDe(bicho, builder.width!)]++;
      }
    }

    cuenta.forEach((asset, capas) {
      // Las tres, para que no se queden clavados en una y pierdan la
      // profundidad que les da caer a distintas distancias.
      expect(capas.every((n) => n > 0), isTrue,
          reason: '$asset no cayó en alguna de las tres capas: $capas');
      // Y sobre todo en la nítida, que es donde se les ve la animación: en las
      // otras van desenfocados (ver _pesoDeCapa).
      expect(capas[1], greaterThan(capas[0] + capas[2]),
          reason: '$asset sale más veces borroso que nítido: $capas');
    });
  });

  testWidgets('el virión ni se desplaza ni se ladea: solo se mueve por dentro',
      (tester) async {
    final covid = Bicho.todos.firstWhere(
      (bicho) => bicho.asset == LoadingScreenImages.covid,
    );

    late LottieComposition composicion;
    await tester.runAsync(() async {
      composicion = await AssetLottie(covid.asset).load();
    });

    /// Cuánto se menea el dibujo dentro de una caja de 200 a lo largo del
    /// bucle, en píxeles: se busca el píxel pintado más alto de cada instante y
    /// se mira cuánto baila. Su altura delata el vaivén (el bicho sube y baja)
    /// y su horizontal, el ladeo (la punta de arriba se va a los lados al
    /// girar el cuerpo).
    Future<({int vaiven, int ladeo})> meneo(LottieDelegates? delegates) async {
      final key = GlobalKey();
      final reloj = AnimationController(
        vsync: tester,
        duration: composicion.duration,
      );
      addTearDown(reloj.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 200,
                height: 200,
                child: Lottie(
                  composition: composicion,
                  controller: reloj,
                  delegates: delegates,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      );

      var altoMin = 9999, altoMax = -1, ladoMin = 9999, ladoMax = -1;
      for (var i = 0; i < 16; i++) {
        reloj.value = i / 16;
        await tester.pump();
        await tester.runAsync(() async {
          final caja =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final imagen = await caja.toImage();
          final datos =
              await imagen.toByteData(format: ui.ImageByteFormat.rawRgba);
          final pixeles = datos!.buffer.asUint8List();

          var alto = -1, lado = -1;
          for (var y = 0; y < imagen.height && alto < 0; y++) {
            for (var x = 0; x < imagen.width; x++) {
              if (pixeles[(y * imagen.width + x) * 4 + 3] > 8) {
                alto = y;
                lado = x;
                break;
              }
            }
          }
          if (alto < altoMin) altoMin = alto;
          if (alto > altoMax) altoMax = alto;
          if (lado < ladoMin) ladoMin = lado;
          if (lado > ladoMax) ladoMax = lado;
        });
      }
      return (vaiven: altoMax - altoMin, ladeo: ladoMax - ladoMin);
    }

    // Tal cual viene, el virión sube y baja 60 de sus 500 puntos de lienzo y se
    // ladea de +7° a -7°. Se comprueba primero para que el test no pueda pasar
    // por las buenas si algún día el archivo dejara de menearse.
    final crudo = await meneo(null);
    expect(crudo.vaiven, greaterThan(10),
        reason: 'el .lottie ya no trae el vaivén que este test quita');
    expect(crudo.ladeo, greaterThan(5),
        reason: 'el .lottie ya no trae el ladeo que este test quita');

    // Y con el retoque el ladeo desaparece, mientras que el vaivén se queda en
    // lo poco que mueven las espículas: venían girando al revés que el cuerpo
    // para compensarlo, y al quedarse el cuerpo quieto se balancean solas. Eso
    // es movimiento de dentro del bicho, no del bicho.
    //
    // Los topes están puestos para cazar que se pierda cualquiera de los dos
    // retoques: sin el de posición el vaivén se dispara a ~24, y sin el de giro
    // el ladeo sube a ~7.
    final retocado = await meneo(covid.delegates);
    expect(retocado.vaiven, lessThan(10));
    expect(retocado.ladeo, lessThan(5));
  });
}
