import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/splash/loading_screen.dart';

/// Las imágenes de la pantalla de carga.
///
/// Los PNG de las células son de ~1000x1000 y se pintan a 50-200 puntos. Si se
/// decodifican enteros son ~4 MB cada uno y el arranque se atasca, que es lo
/// que hacía que aparecieran a trompicones.
Future<ui.Image> loadImage(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);

  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image);
    },
    onError: (error, stack) {
      stream.removeListener(listener);
      completer.completeError(error);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => imageCache.clear());

  test('las células se decodifican al tamaño en que se pintan, no al del '
      'archivo', () async {
    // El original, tal cual está en assets.
    final original = await loadImage(const AssetImage('assets/images/Virus.png'));
    expect(original.width, greaterThan(1000),
        reason: 'el archivo sigue siendo enorme; el test compara contra él');

    final acotada =
        await loadImage(LoadingScreenImages.particle('assets/images/Virus.png'));
    expect(acotada.width, lessThanOrEqualTo(400));

    // Lo que de verdad importa: cuánto trabajo se ahorra por imagen.
    final antes = original.width * original.height;
    final ahora = acotada.width * acotada.height;
    expect(ahora * 5, lessThan(antes),
        reason: 'debería decodificar al menos 5 veces menos píxeles');
  });

  test('la precarga vale para lo que luego se pinta (misma clave de caché)',
      () async {
    await LoadingScreenImages.precache();

    // Si el proveedor del pintado no coincidiera con el de la precarga, la
    // caché fallaría y la imagen se decodificaría otra vez al aparecer: la
    // precarga no serviría de nada y el tirón seguiría ahí.
    for (final path in LoadingScreenImages.particles) {
      final key = await LoadingScreenImages.particle(path)
          .obtainKey(ImageConfiguration.empty);
      expect(imageCache.containsKey(key), isTrue,
          reason: '$path no quedó en caché con la clave con la que se pinta');
    }

    final logoKey =
        await const AssetImage(LoadingScreenImages.logo)
            .obtainKey(ImageConfiguration.empty);
    expect(imageCache.containsKey(logoKey), isTrue);
  });

  test('las imágenes que ya son pequeñas no se agrandan', () async {
    // rbc.png es de 239 px: acotar a 400 no debe estirarlo.
    final img =
        await loadImage(LoadingScreenImages.particle('assets/images/rbc.png'));
    expect(img.width, lessThan(400));
  });
}
