import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/quiz/game/pack_burst_game.dart';

import 'package:mirdaily_app/features/quiz/game/pack_haptics.dart';

/// La háptica de abrir el sobre.
///
/// No se puede ver ni oír, así que la única forma de comprobarla es enchufar
/// un doble que apunte lo que sale y mirar la lista. Lo que se afirma aquí es
/// justo lo que se pidió: que SUBA con el gesto, que se MANTENGA si te paras a
/// medias, que se DESVANEZCA si sueltas sin abrir, y que al abrirse pegue un
/// golpe seco distinto de todo lo anterior.
void main() {
  test('la fuerza sube con el avance, y sube en DURACIÓN', () {
    // La duración del pulso es lo que de verdad gobierna la intensidad. La
    // sonda del aparato lo dejó claro: la tablet de referencia (samsung
    // SM-X700) NO tiene control de amplitud, así que Android ignora ese
    // parámetro y vibra a tope siempre. Una rampa montada solo sobre amplitud
    // se sentía plana y al máximo desde el primer pulso.
    //
    // La duración sí funciona en cualquier motor: es física del propio motor
    // —tarda unos 30 ms en coger vueltas—, no una función del sistema.
    final driver = _FakeDriver(modulates: true);
    final h = PackHaptics(driver: driver);

    double duracionA(double nivel) {
      driver.limpiar();
      h.driveTo(nivel);
      _correr(h, 1.0);
      return driver.mediaDuracion;
    }

    final flojo = duracionA(0.25);
    final medio = duracionA(0.6);
    final tope = duracionA(1.0);

    expect(flojo, lessThan(medio));
    expect(medio, lessThan(tope));

    // Abajo tiene que ser un roce; arriba, el motor girando del todo.
    expect(flojo, lessThan(45));
    expect(tope, greaterThan(80));
  });

  test('arriba del todo los pulsos se solapan: zumbido continuo', () {
    // Lo más fuerte que puede dar un motor sin amplitud es no parar nunca. Si
    // el hueco entre pulsos fuera mayor que su duración, el tope se sentiría
    // como un traqueteo rápido en vez de como un zumbido sólido.
    final driver = _FakeDriver(modulates: true);
    final h = PackHaptics(driver: driver);

    h.driveTo(1.0);
    _correr(h, 1.0);

    final huecoMedio = 1000 / driver.pulsos.length; // ms entre pulsos
    expect(
      driver.mediaDuracion,
      greaterThan(huecoMedio),
      reason: 'cada pulso tiene que durar más que el hueco hasta el siguiente',
    );
  });

  test('el toque del agarre no pega más fuerte que el arranque', () {
    // Era el cuarto sospechoso del "empieza al máximo": el toque de posar el
    // dedo era bastante más gordo que los primeros pulsos de la rampa, así que
    // el gesto abría con un golpe y luego bajaba.
    final driver = _FakeDriver(modulates: true);
    final h = PackHaptics(driver: driver);

    h.grab();
    final agarre = driver.pulsos.single.$1;

    driver.limpiar();
    h.driveTo(0.05);
    _correr(h, 1.0);

    expect(agarre, lessThanOrEqualTo(driver.mediaDuracion.ceil()));
  });

  test('con amplitud: pararse a medias mantiene la fuerza', () {
    final driver = _FakeDriver(modulates: true);
    final h = PackHaptics(driver: driver);

    h.driveTo(0.6);
    _correr(h, 0.5);
    final primeraMitad = driver.mediaDuracion;

    // El dedo sigue puesto y quieto: nadie vuelve a llamar a driveTo.
    driver.limpiar();
    _correr(h, 0.5);

    expect(driver.pulsos, isNotEmpty, reason: 'debería seguir vibrando');
    expect(driver.mediaDuracion, closeTo(primeraMitad, 6));
  });

  test('soltar sin abrir desvanece hasta callarse', () {
    final driver = _FakeDriver(modulates: true);
    final h = PackHaptics(driver: driver);

    h.driveTo(0.8);
    _correr(h, 0.3);

    driver.limpiar();
    h.fadeOut();

    // A mitad del desvanecido ya se nota menos, pero sigue habiendo algo: eso
    // es lo que lo distingue de un corte seco.
    _correr(h, 0.2);
    expect(driver.pulsos, isNotEmpty);
    expect(driver.mediaDuracion, lessThan(70));

    // Y al final, silencio y motor cortado.
    driver.limpiar();
    _correr(h, 0.6);
    expect(h.level, 0);
    expect(driver.cancelaciones, greaterThan(0));

    driver.limpiar();
    _correr(h, 0.5);
    expect(driver.pulsos, isEmpty, reason: 'no debería quedar nada sonando');
  });

  test('abrirlo dispara un golpe aparte, no más de lo mismo', () {
    final driver = _FakeDriver(modulates: true);
    final h = PackHaptics(driver: driver);

    h.driveTo(0.99);
    _correr(h, 0.3);
    driver.limpiar();

    h.pop();
    _correr(h, 0.3);

    // Un patrón, que es lo único capaz de sonar a golpe seco: no se puede
    // pedir un pulso más fuerte que 255, así que la contundencia sale de la
    // FORMA (golpe, golpe, retumbe), no de la amplitud.
    expect(driver.patrones, hasLength(1));
    expect(driver.patrones.single.amplitudes.first, 0);
    expect(driver.patrones.single.amplitudes, contains(255));

    // Y el zumbido del gesto se ha callado: el golpe no compite con él.
    expect(h.level, 0);
    expect(driver.pulsos, isEmpty);
  });

  test('sin amplitud, el tren de pulsos sube en peso y en ritmo', () {
    // El camino de iOS: no hay intensidad, así que la sensación de que aquello
    // va a más tiene que salir de golpear más fuerte y más a menudo.
    final driver = _FakeDriver(modulates: false);
    final h = PackHaptics(driver: driver);

    h.driveTo(0.15);
    _correr(h, 1.0);
    final flojos = List.of(driver.disparos);

    driver.limpiar();
    h.driveTo(1.0);
    _correr(h, 1.0);
    final fuertes = List.of(driver.disparos);

    expect(flojos.every((s) => s == HapticShot.tick), isTrue);
    expect(fuertes.every((s) => s == HapticShot.heavy), isTrue);
    expect(
      fuertes.length,
      greaterThan(flojos.length * 2),
      reason: 'arriba tiene que golpear mucho más a menudo',
    );
  });

  test('sin amplitud, el golpe final son varios impactos seguidos', () {
    final driver = _FakeDriver(modulates: false);
    final h = PackHaptics(driver: driver);

    h.pop();
    _correr(h, 0.4);

    expect(
      driver.disparos.where((s) => s == HapticShot.heavy).length,
      greaterThanOrEqualTo(3),
      reason: 'con pesos fijos, la fuerza sale de encadenarlos',
    );
  });

  test('callar de golpe deja el motor parado', () {
    // Lo llama el juego al salir de la pestaña. Sin esto, el móvil se quedaría
    // zumbando en el bolsillo por haberse ido a medio apretón.
    final driver = _FakeDriver(modulates: true);
    final h = PackHaptics(driver: driver);

    h.driveTo(0.9);
    _correr(h, 0.3);
    expect(driver.pulsos, isNotEmpty);

    driver.limpiar();
    h.stop();
    expect(driver.cancelaciones, 1);

    _correr(h, 0.5);
    expect(driver.pulsos, isEmpty);
  });

  // ---- Enganchada al juego de verdad ----
  //
  // Lo de arriba comprueba el motor háptico solo. Esto comprueba el CABLEADO:
  // que la clase base la alimente con el avance mientras el dedo sujeta, que
  // la desvanezca al soltar y que el golpe salga al abrirse. Es donde de
  // verdad se rompería en un refactor, porque son tres sitios distintos.

  Future<void> avanzar(WidgetTester tester, double segundos) async {
    for (var i = 0; i < (segundos / 0.016).round(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<(PackBurstGame, _FakeDriver, Rect)> montar(WidgetTester tester) async {
    final driver = _FakeDriver(modulates: true);
    final game = PackBurstGame(
      specialties: const ['Cardio', 'Digestivo', 'Neuro', 'Nefro', 'Endo'],
      onComplete: (_) {},
      haptics: PackHaptics(driver: driver),
    );

    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameWidget(key: const ValueKey('sobre'), game: game),
        ),
      ),
    );
    await avanzar(tester, 0.2);

    return (game, driver, tester.getRect(find.byKey(const ValueKey('sobre'))));
  }

  testWidgets('apretando, la vibración sigue al sobre y se desvanece al soltar',
      (tester) async {
    final (game, driver, rect) = await montar(tester);

    expect(driver.pulsos, isEmpty, reason: 'en reposo, nada');

    final centro = game.debugPackRect.center + rect.topLeft;
    final gesto = await tester.startGesture(centro);

    // Al posarse el dedo, un toque que marca el agarre.
    expect(driver.pulsos, isNotEmpty, reason: 'debería avisar del agarre');

    // Medio segundo apretando: la vibración ya ha subido.
    driver.limpiar();
    await avanzar(tester, 0.5);
    expect(driver.mediaDuracion, greaterThan(0));

    // Se suelta sin abrirlo: baja hasta callarse del todo.
    await gesto.up();
    await avanzar(tester, 0.9);

    driver.limpiar();
    await avanzar(tester, 0.4);
    expect(driver.pulsos, isEmpty, reason: 'tenía que haberse desvanecido');
  });

  testWidgets('al abrirse, el golpe seco', (tester) async {
    final (game, driver, rect) = await montar(tester);

    final centro = game.debugPackRect.center + rect.topLeft;
    final gesto = await tester.startGesture(centro);

    driver.limpiar();
    await avanzar(tester, 1.3); // el apretón dura 1,15 s
    expect(game.openProgress, 1.0, reason: 'debería haber reventado');

    expect(driver.patrones, hasLength(1));
    expect(driver.patrones.single.amplitudes, contains(255));

    await gesto.up();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 4));
    }
  });

  testWidgets('salir de la pestaña a medio apretón calla el motor',
      (tester) async {
    // Sin esto el móvil se queda zumbando en el bolsillo: con el bucle del
    // juego parado ya no hay quien apague la vibración.
    final (game, driver, rect) = await montar(tester);

    final gesto = await tester.startGesture(
      game.debugPackRect.center + rect.topLeft,
    );
    await avanzar(tester, 0.5);
    expect(driver.pulsos, isNotEmpty);

    driver.limpiar();
    game.setVisible(false);

    expect(driver.cancelaciones, greaterThan(0));
    expect(driver.pulsos, isEmpty);

    await gesto.up();
  });
}

void _correr(PackHaptics h, double segundos) {
  for (var i = 0; i < (segundos * 60).round(); i++) {
    h.update(1 / 60);
  }
}

class _Patron {
  _Patron(this.timings, this.amplitudes);
  final List<int> timings;
  final List<int> amplitudes;
}

class _FakeDriver implements HapticDriver {
  _FakeDriver({required this.modulates});

  @override
  final bool modulates;

  /// (duración en ms, amplitud) de cada pulso.
  final List<(int, int)> pulsos = [];
  final List<HapticShot> disparos = [];
  final List<_Patron> patrones = [];
  int cancelaciones = 0;

  double get mediaAmplitud => _media((p) => p.$2);

  /// Lo que de verdad manda la intensidad en un motor sin control de amplitud,
  /// que es el caso de la tablet de referencia.
  double get mediaDuracion => _media((p) => p.$1);

  double _media(int Function((int, int)) campo) => pulsos.isEmpty
      ? 0
      : pulsos.map(campo).reduce((a, b) => a + b) / pulsos.length;

  void limpiar() {
    pulsos.clear();
    disparos.clear();
    patrones.clear();
    cancelaciones = 0;
  }

  @override
  void pulse(int ms, int amplitude) => pulsos.add((ms, amplitude));

  @override
  void shot(HapticShot shot) => disparos.add(shot);

  @override
  void pattern(List<int> timings, List<int> amplitudes) =>
      patrones.add(_Patron(timings, amplitudes));

  @override
  void cancel() => cancelaciones++;
}
