// La celebración de metas: cuándo sale, qué enseña y cuándo se calla.
//
//   flutter test test/celebracion_logros_test.dart
//   flutter test test/celebracion_logros_test.dart --update-goldens
//
// Comprueba la regla de oro —nada aparece por su cuenta— y los dos detalles
// que en la web costaron tiempo: el titular no se destapa hasta que la barra
// cruza de verdad, y con las animaciones desactivadas la tarjeta enseña el
// resultado sin recorrido ni partículas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/logros.dart';
import 'package:mirdaily_app/core/providers/progress_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/core/theme/levels.dart';
import 'package:mirdaily_app/features/progress/celebracion_logros.dart';
import 'package:mirdaily_app/features/progress/widgets/subida_de_nivel.dart';

/// Un provider sin red: nunca se autentica, así que nunca pide nada.
ProgressProvider _provider() => ProgressProvider(
      ApiService(AuthService(), client: MockClient((_) async => throw 'nada')),
    );

/// Monta la celebración sobre una pantalla cualquiera, como en `main.dart`.
Widget _app(ProgressProvider p, {bool sinAnimaciones = false}) {
  return ChangeNotifierProvider<ProgressProvider>.value(
    value: p,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('la pantalla de debajo')),
      ),
      builder: (context, child) {
        final capa = Stack(
          textDirection: TextDirection.ltr,
          children: [
            child ?? const SizedBox(),
            const Positioned.fill(child: CelebracionLogros()),
          ],
        );
        return sinAnimaciones
            ? MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: capa,
              )
            : capa;
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sin permiso no se pinta nada, aunque haya logros en la cola',
      (tester) async {
    final p = _provider();
    addTearDown(p.dispose);

    await tester.pumpWidget(_app(p));
    // Un logro entra en la cola, como haría la detección al recargar…
    p.encolarLogros([
      Logro(
        id: 'l1',
        tipo: TipoLogro.nivel,
        nivel: 12,
        xpAntes: xpParaNivel(11),
        xpDespues: xpParaNivel(12) + 90,
      ),
    ]);
    await tester.pump();

    // …y no se pinta nada, porque nadie ha dado permiso.
    expect(p.logros, hasLength(1));
    expect(find.byType(SubidaDeNivel), findsNothing);
    expect(find.text('Seguir'), findsNothing,
        reason: 'la regla de oro: nada aparece por su cuenta');
    expect(find.text('la pantalla de debajo'), findsOneWidget);
  });

  testWidgets('el titular espera al primer cruce de peldaño', (tester) async {
    final p = _provider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_app(p));

    // Un salto de DOS peldaños, como el que deja un simulacro largo.
    p.encolarLogros([
      Logro(
        id: 'l1',
        tipo: TipoLogro.rango,
        nivel: 20,
        rango: 'Residente R1',
        xpAntes: xpParaNivel(18) + 120,
        xpDespues: xpParaNivel(20) + 140,
      ),
    ]);
    p.permitirCelebracion();
    await tester.pump();

    // Nada más abrirse, la barra todavía va por el nivel de partida: el
    // titular no puede estar contando el final de la historia.
    expect(find.byType(SubidaDeNivel), findsOneWidget);
    // Se ancla en el subtítulo y no en el nombre del rango: ese sale también
    // como rótulo de la propia barra, y habría dos coincidencias.
    final tituloAntes = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('Has llegado al nivel 20.'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(tituloAntes.opacity, 0,
        reason: 'el número tiene que llegar DESPUÉS del esfuerzo');

    // Se deja correr el recorrido entero (arranque + duración máxima).
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final tituloDespues = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('Has llegado al nivel 20.'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(tituloDespues.opacity, 1);
    expect(find.text('Has llegado al nivel 20.'), findsOneWidget);
  });

  testWidgets('cerrar la tarjeta deja paso a los avisos de desafío',
      (tester) async {
    final p = _provider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_app(p, sinAnimaciones: true));

    p.encolarLogros([
      Logro(
        id: 'nivel',
        tipo: TipoLogro.nivel,
        nivel: 4,
        xpAntes: xpParaNivel(4) - 40,
        xpDespues: xpParaNivel(4) + 10,
      ),
      const Logro(
        id: 'reto',
        tipo: TipoLogro.desafio,
        titulo: 'Cinco de siete',
        xp: 150,
        scope: 'weekly',
      ),
    ]);
    p.permitirCelebracion();
    await tester.pump();

    // Primero la tarjeta, sola: el desafío NO se cuela dentro ni por encima.
    expect(find.text('Nivel 4'), findsOneWidget);
    expect(find.text('Cinco de siete'), findsNothing,
        reason: 'meterlo dentro diluiría la meta gorda en una lista');

    await tester.tap(find.text('Seguir'));
    await tester.pump();

    // Y ahora sí: se turnan EN EL TIEMPO.
    expect(find.text('Nivel 4'), findsNothing);
    expect(find.text('Cinco de siete'), findsOneWidget);
    expect(find.text('DESAFÍO SEMANAL'), findsOneWidget);

    // El aviso se va solo a los 4,6 s.
    await tester.pump(const Duration(milliseconds: 4700));
    await tester.pump();
    expect(find.text('Cinco de siete'), findsNothing);
    expect(p.logros, isEmpty, reason: 'y solo entonces sale de la cola');
  });

  testWidgets('con las animaciones desactivadas se enseña el resultado ya',
      (tester) async {
    final p = _provider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_app(p, sinAnimaciones: true));

    p.encolarLogros([
      Logro(
        id: 'l1',
        tipo: TipoLogro.nivel,
        nivel: 12,
        xpAntes: xpParaNivel(11) + 30,
        xpDespues: xpParaNivel(12) + 90,
      ),
    ]);
    p.permitirCelebracion();
    // Un solo frame: sin recorrido que esperar.
    await tester.pump();

    expect(find.text('Nivel 12'), findsOneWidget);
    final titulo = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('Nivel 12'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(titulo.opacity, 1, reason: 'sin recorrido no hay nada que esperar');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/celebracion_nivel.png'),
    );
  });

  testWidgets('la tarjeta anima su salida antes de irse', (tester) async {
    final p = _provider();
    addTearDown(p.dispose);
    // Con animaciones: es justo lo que se está comprobando.
    await tester.pumpWidget(_app(p));

    p.encolarLogros([
      const Logro(id: 'racha', tipo: TipoLogro.racha, dias: 7),
    ]);
    p.permitirCelebracion();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // entrada acabada

    await tester.tap(find.text('Seguir'));
    // Dos pumps: el primero arranca el ticker (reporta 0 ms transcurridos) y
    // el segundo ya avanza el reloj. Con uno solo la salida parecería quieta.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // A mitad de la salida la tarjeta SIGUE montada y desvaneciéndose. Si se
    // avisara al provider al pulsar, aquí ya no existiría: un widget
    // desmontado no puede animar su propia salida.
    expect(find.text('7 días seguidos'), findsOneWidget);
    expect(p.logros, hasLength(1), reason: 'todavía no se ha descartado');
    // Se miran todas las capas de opacidad por encima del texto en vez de
    // adivinar cuál es: lo que importa es que ALGUNA esté a medio camino.
    final opacidades = tester
        .widgetList<Opacity>(find.ancestor(
          of: find.text('7 días seguidos'),
          matching: find.byType(Opacity),
        ))
        .map((o) => o.opacity)
        .toList();
    expect(opacidades, isNotEmpty);
    expect(opacidades.any((o) => o > 0 && o < 1), isTrue,
        reason: 'debería estar desvaneciéndose, no quieta: $opacidades');

    // Y al terminar sí sale de la cola.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('7 días seguidos'), findsNothing);
    expect(p.logros, isEmpty);
  });

  testWidgets('el botón atrás de Android cierra la tarjeta', (tester) async {
    final p = _provider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_app(p, sinAnimaciones: true));

    p.encolarLogros([
      const Logro(id: 'racha', tipo: TipoLogro.racha, dias: 7),
    ]);
    p.permitirCelebracion();
    await tester.pump();
    expect(find.text('7 días seguidos'), findsOneWidget);

    // La tarjeta vive POR ENCIMA del Navigator: sin el observador, este atrás
    // desharía la navegación de debajo y la dejaría flotando.
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('7 días seguidos'), findsNothing);
    expect(p.logros, isEmpty);
  });

  testWidgets('el hito de racha manda sobre el nivel, y el nivel lo resume',
      (tester) async {
    final p = _provider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_app(p, sinAnimaciones: true));

    p.encolarLogros([
      const Logro(id: 'racha', tipo: TipoLogro.racha, dias: 30),
      Logro(
        id: 'rango',
        tipo: TipoLogro.rango,
        nivel: 20,
        rango: 'Residente R1',
        xpAntes: xpParaNivel(19),
        xpDespues: xpParaNivel(20) + 50,
      ),
    ]);
    p.permitirCelebracion();
    await tester.pump();

    // El rango pesa más: es el titular. La racha va resumida en "Y además".
    // `findsWidgets` porque el nombre del rango sale dos veces: como titular y
    // como rótulo de la barra que acaba de recorrerse.
    expect(find.text('Residente R1'), findsWidgets);
    expect(find.text('NUEVO RANGO'), findsOneWidget);
    expect(find.text('Y ADEMÁS'), findsOneWidget);
    expect(find.text('30 días de racha'), findsOneWidget);
  });
}
