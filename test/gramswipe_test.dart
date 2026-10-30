// Tanda 11: minijuegos (GramSwipe). Lógica, datos generados y pantallas en móvil (360×780) y tablet
// (1024×768).
//
//   flutter test test/gramswipe_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/gramswipe.dart';
import 'package:mirdaily_app/core/models/gramswipe_datos.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/medguess/medguess_screen.dart';
import 'package:mirdaily_app/features/minijuegos/gramswipe_screen.dart';
import 'package:mirdaily_app/features/minijuegos/minijuegos_screen.dart';

Antibiotico _ab(String id) => antibioticosGramSwipe.firstWhere((a) => a.nombre == id);

/// Un mazo corto para jugar en los tests: uno de cada cobertura.
final List<Antibiotico> _mazo = [_ab('Vancomicina'), _ab('Aztreonam'), _ab('Meropenem')];

const _movil = Size(360, 780);
const _tablet = Size(1024, 768);

Future<void> _montar(WidgetTester tester, Size size, Widget home) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: home));
  await tester.pumpAndSettle();
}

Future<void> _boton(WidgetTester tester, String etiqueta) async {
  await tester.tap(find.bySemanticsLabel(etiqueta));
  await tester.pumpAndSettle();
}

String _arriba(WidgetTester tester) {
  final s = tester.widget<Semantics>(find.bySemanticsLabel(RegExp(r'Toca para voltear')).first);
  return s.properties.label!.split('.').first;
}

void main() {
  group('datos generados de la web', () {
    test('25 antibióticos con id único, 7 Gram +, 4 Gram − y 14 de amplio espectro', () {
      expect(antibioticosGramSwipe, hasLength(25));
      expect({for (final a in antibioticosGramSwipe) a.id}, hasLength(25));
      int n(Cobertura c) => antibioticosGramSwipe.where((a) => a.cobertura == c).length;
      expect((n(Cobertura.gramPositivo), n(Cobertura.gramNegativo), n(Cobertura.amplio)), (7, 4, 14));
    });

    test('cada foto existe y está declarada en el pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/gramswipe/'));
      for (final a in antibioticosGramSwipe) {
        expect(File(a.foto).existsSync(), isTrue, reason: a.foto);
      }
    });
  });

  group('lógica', () {
    test('cada dirección es una respuesta; abajo es «no sé»', () {
      expect(coberturaDe(DireccionSwipe.derecha), Cobertura.gramPositivo);
      expect(coberturaDe(DireccionSwipe.izquierda), Cobertura.gramNegativo);
      expect(coberturaDe(DireccionSwipe.arriba), Cobertura.amplio);
      expect(coberturaDe(DireccionSwipe.abajo), isNull);
    });

    test('el arrastre: manda el eje largo y cuenta a partir de 90 px', () {
      expect(direccionDeArrastre(40, -10), DireccionSwipe.derecha);
      expect(direccionDeArrastre(-5, -40), DireccionSwipe.arriba);
      expect(direccionAlSoltar(89, 0), isNull);
      expect(direccionAlSoltar(-91, 30), DireccionSwipe.izquierda);
      expect(direccionAlSoltar(20, 120), DireccionSwipe.abajo);
      expect(intensidadArrastre(45, 0), 0.5);
      expect(intensidadArrastre(0, -400), 1);
    });

    test('una partida: aciertos, fallos, saltadas al final y repetir errores', () {
      final p = PartidaGramSwipe(_mazo);
      expect(p.deslizar(DireccionSwipe.derecha)!.acierto, isTrue, reason: 'vancomicina, Gram +');
      expect(p.deslizar(DireccionSwipe.abajo), isNull, reason: 'aztreonam: no sé');
      expect(p.cola.map((a) => a.nombre), ['Meropenem', 'Aztreonam'], reason: 'vuelve al final');
      final r = p.deslizar(DireccionSwipe.izquierda)!;
      expect(r.acierto, isFalse);
      expect(r.marcada, Cobertura.gramNegativo);
      expect(p.deslizar(DireccionSwipe.izquierda)!.acierto, isTrue, reason: 'aztreonam, Gram −');
      expect(p.terminada, isTrue);
      expect((p.aciertos, p.fallos, p.saltadas.length, p.precision), (2, 1, 1, 67));
      expect(p.falladas.single.nombre, 'Meropenem');
      expect(p.repetirErrores(math.Random(1)).cola.single.nombre, 'Meropenem');
      expect(p.deslizar(DireccionSwipe.derecha), isNull, reason: 'sin tarjetas no hace nada');
    });

    test('barajar no pierde ni repite tarjetas', () {
      final p = PartidaGramSwipe.barajada(antibioticosGramSwipe, math.Random(7));
      expect({for (final a in p.cola) a.id}, {for (final a in antibioticosGramSwipe) a.id});
      expect(p.total, 25);
    });

    test('el titular según la precisión', () {
      expect(tituloResultadoGramSwipe(100), '¡Perfecto!');
      expect(tituloResultadoGramSwipe(70), '¡Muy bien!');
      expect(tituloResultadoGramSwipe(69), 'Sigue practicando');
    });
  });

  for (final (nombre, size) in [('móvil', _movil), ('tablet', _tablet)]) {
    group(nombre, () {
      testWidgets('modo estudio: corrección tras cada tarjeta, voltear y resultado', (tester) async {
        await _montar(tester, size, GramSwipeScreen(mazo: _mazo, azar: math.Random(3)));
        expect(find.text('Clasifica antibióticos'), findsOneWidget);
        await tester.tap(find.text('Empezar'));
        await tester.pumpAndSettle();
        expect(find.text('0 / 3'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Un toque voltea la tarjeta.
        await tester.tap(find.bySemanticsLabel(RegExp(r'Toca para voltear')));
        await tester.pumpAndSettle();
        expect(find.text('MECANISMO DE ACCIÓN'), findsOneWidget);

        // Se responden las tres con los botones: la primera bien y el resto mal.
        for (var i = 0; i < 3; i++) {
          final a = _mazo.firstWhere((x) => x.nombre == _arriba(tester));
          final bien = switch (a.cobertura) {
            Cobertura.gramPositivo => 'Gram +',
            Cobertura.gramNegativo => 'Gram −',
            Cobertura.amplio => 'Amplio espectro',
          };
          final mal = a.cobertura == Cobertura.gramPositivo ? 'Gram −' : 'Gram +';
          await _boton(tester, i == 0 ? bien : mal);
          expect(find.text(i == 0 ? '¡Correcto!' : 'Incorrecto'), findsOneWidget, reason: 'tarjeta ${i + 1}');
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Continuar'));
          await tester.pumpAndSettle();
        }

        expect(find.text('Sigue practicando'), findsOneWidget);
        expect(find.text('1 de 3 correctas · 33% de precisión'), findsOneWidget);
        expect(find.text('TARJETAS FALLADAS'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Repetir errores'), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Repetir errores'));
        await tester.pumpAndSettle();
        expect(find.text('0 / 2'), findsOneWidget, reason: 'solo las dos falladas');
        expect(tester.takeException(), isNull);
      });

      testWidgets('repaso rápido: arrastrar con el dedo, «no sé» y sin pausas', (tester) async {
        await _montar(tester, size, GramSwipeScreen(mazo: _mazo, azar: math.Random(3)));
        await tester.tap(find.text('Repaso rápido'));
        await tester.pump();
        await tester.tap(find.text('Empezar'));
        await tester.pumpAndSettle();

        final primera = _arriba(tester);
        // Un arrastre corto no cuenta: vuelve a su sitio.
        await tester.drag(find.bySemanticsLabel(RegExp(r'Toca para voltear')), const Offset(50, 0));
        await tester.pumpAndSettle();
        expect(_arriba(tester), primera);
        expect(find.text('0 / 3'), findsOneWidget);

        // Hacia abajo: «no sé», se va al final sin puntuar.
        await tester.drag(find.bySemanticsLabel(RegExp(r'Toca para voltear')), const Offset(0, 200));
        await tester.pumpAndSettle();
        expect(_arriba(tester), isNot(primera));
        expect(find.text('0 / 3'), findsOneWidget);

        // El resto, arrastrando a la derecha, sin corrección entre medias.
        for (var i = 0; i < 3; i++) {
          await tester.drag(find.bySemanticsLabel(RegExp(r'Toca para voltear')), const Offset(220, 10));
          await tester.pumpAndSettle();
          expect(find.text('Continuar'), findsNothing);
        }
        expect(find.textContaining('de 3 correctas'), findsOneWidget);
        expect(find.text('1'), findsWidgets, reason: 'una saltada');
        expect(tester.takeException(), isNull);
      });

      testWidgets('salir a mitad de partida pide confirmación', (tester) async {
        await _montar(tester, size, GramSwipeScreen(mazo: _mazo));
        await tester.tap(find.text('Empezar'));
        await tester.pumpAndSettle();
        final dynamic estado = tester.state(find.byType(Navigator));
        await (estado as NavigatorState).maybePop();
        await tester.pumpAndSettle();
        expect(find.text('¿Abandonar la sesión?'), findsOneWidget);
        await tester.tap(find.text('Seguir jugando'));
        await tester.pumpAndSettle();
        expect(find.text('0 / 3'), findsOneWidget);
        await estado.maybePop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Abandonar'));
        await tester.pumpAndSettle();
        expect(find.text('Clasifica antibióticos'), findsOneWidget);
      });

      testWidgets('el centro de minijuegos abre GramSwipe y MedGuess', (tester) async {
        await _montar(tester, size, const MinijuegosScreen());
        expect(find.text('GramSwipe'), findsOneWidget);
        expect(find.text('MedGuess'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('GramSwipe'));
        await tester.pumpAndSettle();
        expect(find.byType(GramSwipeScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MedGuessScreen), findsNothing);
      });
    });
  }
}
