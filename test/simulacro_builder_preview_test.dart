// Muestrario de las piezas nuevas del creador de simulacros.
//
//   flutter test test/simulacro_builder_preview_test.dart --update-goldens
//
// Deja la imagen en test/goldens/simulacro_builder.png. Los iconos y las
// ilustraciones se animan en bucle, así que se congelan en varios instantes
// del ciclo para ver que el dibujo aguanta en todos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/simulacro/widgets/count_slider.dart';
import 'package:mirdaily_app/features/simulacro/widgets/layout_mode_art.dart';
import 'package:mirdaily_app/features/simulacro/widgets/subject_shortcuts.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

void main() {
  testWidgets('piezas del creador de simulacros', (tester) async {
    tester.view.physicalSize = const Size(420, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Atajos de asignatura'),
                SubjectShortcutBar(
                  active: SubjectShortcut.todas,
                  canClear: true,
                  onPick: (_) {},
                ),
                const SizedBox(height: 22),
                const SectionLabel('Nº de preguntas'),
                CountSlider(value: 90, onChanged: (_) {}),
                const SizedBox(height: 18),
                const SectionLabel('Modo de visualizacion'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    ClassicLayoutArt(),
                    SwipeLayoutArt(),
                    ClassicLayoutArt(),
                    SwipeLayoutArt(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // El cartel explicativo solo aparece al pulsar un atajo: se pulsa "MIR",
    // que es el que más falta hace explicar.
    await tester.tap(find.text('Aleatorias'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/simulacro_builder.png'),
    );
  });

  testWidgets('el deslizador llega con muelle, no de golpe', (tester) async {
    // El valor va en un notificador para que el ARBOL no cambie de forma al
    // moverlo: si cambia, Flutter monta un State nuevo, `didUpdateWidget` no
    // llega a correr y el muelle no se dispara — el widget estaria bien y el
    // test daria rojo igualmente.
    final count = ValueNotifier<int>(10);
    addTearDown(count.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: count,
            builder: (context, v, _) =>
                CountSlider(value: v, onChanged: (n) => count.value = n),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    // Un salto como el de pulsar el atajo "210".
    count.value = 210;
    await tester.pump();
    await tester.pump();

    // Si el mando saltara de golpe no habria nada que animar.
    expect(tester.hasRunningAnimations, isTrue,
        reason: 'el salto tiene que recorrerse, no teletransportarse');

    // Y acaba parando: un muelle mal puesto oscila para siempre.
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
