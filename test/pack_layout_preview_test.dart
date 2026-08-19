// Cómo queda el reparto de las cartas del sobre.
//
//   flutter test test/pack_layout_preview_test.dart --update-goldens
//
// Dibuja las posiciones REALES que calcula el juego, no una maqueta: si el
// reparto cambia, la imagen cambia.
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/quiz/game/pack_opening_game.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

const _asignaturas = [
  'Cardiología',
  'Digestivo',
  'Neurología',
  'Infecciosas',
  'Ginecología',
];

void main() {
  testWidgets('reparto de las cartas del sobre', (tester) async {
    const w = 360.0, h = 780.0;
    tester.view.physicalSize = const Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = PackOpeningGame(specialties: _asignaturas, onComplete: (_) {});
    final positions = game.debugCardLayout(Vector2(w, h), Random(0));

    // El tamaño de carta importa: con tres por fila salen más estrechas y los
    // nombres largos de asignatura tienen menos sitio.
    debugPrint('carta: ${game.cardWidth.toStringAsFixed(1)} x '
        '${game.cardHeight.toStringAsFixed(1)}');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              for (var i = 0; i < positions.length; i++)
                Positioned(
                  left: positions[i].x,
                  top: positions[i].y,
                  child: Container(
                    width: game.cardWidth,
                    height: game.cardHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kInk, width: 2),
                      boxShadow: inkShadow(3),
                    ),
                    child: Text(
                      _asignaturas[i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: kInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pack_layout.png'),
    );
  });
}
