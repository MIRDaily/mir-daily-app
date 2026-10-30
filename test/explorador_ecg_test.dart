// Tanda 9: la pantalla del Explorador de 12 derivaciones, en móvil (360×780) y tablet (1024×768), sin
// desbordes ni excepciones.
//
//   flutter test test/explorador_ecg_test.dart
//
// El monitor barre sin parar (un Ticker): nada de pumpAndSettle, se bombea con duraciones fijas.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/ecg_core.dart';
import 'package:mirdaily_app/core/models/ecg_patrones.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/electros/electros_hub_screen.dart';
import 'package:mirdaily_app/features/electros/explorador/ecg_lienzos.dart';
import 'package:mirdaily_app/features/electros/explorador/explorador_ecg_screen.dart';

const _movil = Size(360, 780);
const _tablet = Size(1024, 768);

Future<void> _montar(WidgetTester tester, Size size, Widget home) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: home));
  await _bombear(tester);
}

Future<void> _bombear(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Lleva el elemento a la vista (ensureVisible necesita un pump después) y lo toca.
Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(f);
}

MonitorTrazoPainter _trazo(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<MonitorTrazoPainter>()
    .single;

void main() {
  for (final (nombre, size) in [('móvil', _movil), ('tablet', _tablet)]) {
    group(nombre, () {
      testWidgets('el explorador: monitor que barre, ECG 4×3 y ficha del ritmo sinusal', (tester) async {
        await _montar(tester, size, const ExploradorEcgScreen());
        expect(tester.takeException(), isNull);
        expect(find.text('Explorador de 12 derivaciones'), findsOneWidget);
        expect(find.text('Ritmo sinusal normal'), findsWidgets);
        expect(find.byType(DoceDerivacionesEcg), findsOneWidget);

        final t0 = _trazo(tester).tSim;
        await _bombear(tester, 10);
        expect(_trazo(tester).tSim, greaterThan(t0), reason: 'el monitor avanza');

        // La ficha está más abajo.
        await tester.scrollUntilVisible(find.textContaining('Es el ritmo con el que comparas'), 300,
            scrollable: find.byType(Scrollable).first);
        await _bombear(tester, 2);
        expect(find.text('CLAVES EN EL ECG'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('derivación, velocidad y pausa', (tester) async {
        await _montar(tester, size, const ExploradorEcgScreen());
        await _tocar(tester, find.text('V1').first);
        await _bombear(tester, 2);
        final enV1 = _trazo(tester);
        expect(enV1.buffer, same(sintesisDe(patronesEcg.first).derivaciones['V1']));
        expect(enV1.tInicio, greaterThan(0), reason: 'al cambiar de derivación el trazo empieza limpio');

        await _tocar(tester, find.text('2×'));
        await _bombear(tester, 2);
        final a = _trazo(tester).tSim;
        await tester.pump(const Duration(milliseconds: 40));
        expect(_trazo(tester).tSim - a, closeTo(0.08, 0.01), reason: 'a 2× corre el doble');

        await _tocar(tester, find.bySemanticsLabel('Pausa'));
        await _bombear(tester, 2);
        final parado = _trazo(tester).tSim;
        await _bombear(tester, 5);
        expect(_trazo(tester).tSim, parado);
        // En pausa no late: activar el sonido no toca el reproductor.
        await _tocar(tester, find.bySemanticsLabel('Activar sonido'));
        await _bombear(tester, 2);
        expect(find.bySemanticsLabel('Silenciar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('elegir otro diagnóstico cambia el monitor, el ECG y la ficha', (tester) async {
        await _montar(tester, size, const ExploradorEcgScreen());
        if (size == _movil) {
          await _tocar(tester, find.text('Cambiar'));
          await _bombear(tester, 8);
          expect(find.text('Elige un diagnóstico'), findsOneWidget);
          expect(find.text('Requiere manejo'), findsOneWidget, reason: 'la leyenda de colores');
        }
        await _tocar(tester, find.text('Fibrilación auricular').last);
        await _bombear(tester, 8);
        final fa = sintesisDe(patronesEcg.firstWhere((p) => p.id == 'afib'));
        expect(_trazo(tester).buffer, same(fa.derivaciones['II']));
        expect(find.text('115'), findsOneWidget, reason: 'la FC del monitor');
        await tester.scrollUntilVisible(find.textContaining('Sin P + R-R irregularmente'), 300,
            scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });

      testWidgets('cada patrón se dibuja sin romper (los 33)', (tester) async {
        await _montar(tester, size, const ExploradorEcgScreen());
        final painter = DoceDerivacionesPainter(sintesis: null);
        for (final p in patronesEcg) {
          final s = sintesisDe(p);
          for (final (pintor, tam) in [
            (DoceDerivacionesPainter(sintesis: s, derivacionRitmo: 'V1') as CustomPainter, const Size(700, 380)),
            (MonitorTrazoPainter(buffer: s.derivaciones['aVR']!, tSim: 37.3, tInicio: 0), const Size(340, 210)),
          ]) {
            final rec = PictureRecorder();
            pintor.paint(Canvas(rec), tam);
            rec.endRecording().dispose();
          }
        }
        expect(painter.shouldRepaint(DoceDerivacionesPainter(sintesis: sintesisDe(patronesEcg.first))), isTrue);
      });

      testWidgets('modo examen: 10 ECG, corrige y da el resultado', (tester) async {
        const semilla = 4;
        final tanda = barajarExamen(patronesEcg, math.Random(semilla));
        await _montar(tester, size, ExploradorEcgScreen(azar: math.Random(semilla)));
        await _tocar(tester, find.text('Modo examen'));
        await _bombear(tester, 4);
        expect(find.text('¿Qué diagnóstico ves?'), findsOneWidget);
        expect(find.text('1 / 10'), findsOneWidget);

        for (var i = 0; i < largoExamenEcg; i++) {
          final campo = find.byType(TextField);
          await tester.scrollUntilVisible(campo, 300, scrollable: find.byType(Scrollable).first);
          final fallo = i == 0;
          // La primera, mal y eligiendo de la lista; el resto, escribiendo el nombre entero.
          if (fallo) {
            final otro = patronesEcg.firstWhere((p) => p.id == (tanda[i].id == 'afib' ? 'sinus' : 'afib'));
            await tester.enterText(campo, otro.sigla);
            await _bombear(tester, 2);
            await _tocar(tester, find.text(otro.nombre).last);
          } else {
            await tester.enterText(campo, tanda[i].nombre.toUpperCase());
          }
          await _bombear(tester, 2);
          final confirmar = find.text('Confirmar diagnóstico');
          await tester.scrollUntilVisible(confirmar, 200, scrollable: find.byType(Scrollable).first);
          await _tocar(tester, confirmar);
          await _bombear(tester, 3);
          expect(find.text(fallo ? 'Incorrecto' : '¡Correcto!'), findsOneWidget, reason: 'pregunta ${i + 1}');
          final siguiente = find.text(i == largoExamenEcg - 1 ? 'Ver resultados' : 'Siguiente');
          await tester.scrollUntilVisible(siguiente, 200, scrollable: find.byType(Scrollable).first);
          await _tocar(tester, siguiente);
          await _bombear(tester, 3);
          expect(tester.takeException(), isNull, reason: 'pregunta ${i + 1}');
        }

        await _bombear(tester, 20);
        expect(find.text('Examen completado'), findsOneWidget);
        expect(find.text('90%'), findsOneWidget);
        await _tocar(tester, find.text('Repetir examen'));
        await _bombear(tester, 3);
        expect(find.text('1 / 10'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Electros abre el explorador nativo, no el simulador web', (tester) async {
        await _montar(tester, size, const ElectrosHubScreen());
        expect(find.text('Simulador de ECG'), findsNothing);
        await _tocar(tester, find.text('Explorador de 12 derivaciones'));
        await _bombear(tester, 10);
        expect(find.byType(ExploradorEcgScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('el examen no se confirma sin un diagnóstico elegido', (tester) async {
    await _montar(tester, _movil, ExploradorEcgScreen(azar: math.Random(1)));
    await _tocar(tester, find.text('Modo examen'));
    await _bombear(tester, 3);
    final campo = find.byType(TextField);
    await tester.scrollUntilVisible(campo, 300, scrollable: find.byType(Scrollable).first);
    await tester.enterText(campo, 'fibrila');
    await _bombear(tester, 2);
    expect(find.text('Fibrilación auricular'), findsOneWidget, reason: 'sugerencia');
    expect(find.text('Fibrilación ventricular'), findsOneWidget, reason: 'sugerencia');
    final confirmar = find.text('Confirmar diagnóstico');
    await tester.scrollUntilVisible(confirmar, 200, scrollable: find.byType(Scrollable).first);
    await _tocar(tester, confirmar);
    await _bombear(tester, 2);
    expect(find.text('¡Correcto!'), findsNothing);
    expect(find.text('Incorrecto'), findsNothing);
  });
}
