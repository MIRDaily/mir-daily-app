import 'dart:math';
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/quiz/game/pack_opening_game.dart';

/// El reparto de las cartas del sobre: salen desviadas de su sitio y ladeadas
/// para que el montón parezca tirado a mano, pero no pueden tocarse nunca.
///
/// Lo que se comprueba aquí es el caso peor, que es fácil de calcular mal: dos
/// vecinas que se desvían LA UNA HACIA LA OTRA se acercan el doble del desfase,
/// así que el hueco tiene que absorber a las dos, no a una.
void main() {
  // Las 5 del daily, con el nombre más largo que existe en el juego.
  final specialties = List.filled(5, 'Endocrinología');

  PackOpeningGame buildGame() =>
      PackOpeningGame(specialties: specialties, onComplete: (_) {});

  /// La caja que barre una carta ya inclinada, centrada en la carta.
  Rect tiltedBox(Vector2 topLeft, PackOpeningGame game) {
    final center = Offset(
      topLeft.x + game.cardWidth / 2,
      topLeft.y + game.cardHeight / 2,
    );
    final tilted = game.debugTiltedCardSize;
    return Rect.fromCenter(
      center: center,
      width: tilted.x,
      height: tilted.y,
    );
  }

  const screens = <(String, double, double)>[
    ('compacto', 360, 780),
    ('Pixel', 392, 850),
    ('grande', 411, 915),
    ('pequeño', 320, 690),
  ];

  test('las cartas nunca se solapan, en ninguna pantalla ni reparto', () {
    for (final (name, w, h) in screens) {
      final game = buildGame();
      // Muchos repartos: las posiciones son aleatorias y el solape solo
      // aparecería en las combinaciones desafortunadas.
      for (var seed = 0; seed < 300; seed++) {
        final positions = game.debugCardLayout(Vector2(w, h), Random(seed));
        expect(positions.length, specialties.length);

        for (var i = 0; i < positions.length; i++) {
          for (var j = i + 1; j < positions.length; j++) {
            final a = tiltedBox(positions[i], game);
            final b = tiltedBox(positions[j], game);
            expect(
              a.overlaps(b),
              isFalse,
              reason: 'cartas $i y $j se solapan en $name (seed $seed)',
            );
          }
        }
      }
    }
  });

  test('las cartas se quedan dentro de la pantalla', () {
    for (final (name, w, h) in screens) {
      final game = buildGame();
      for (var seed = 0; seed < 300; seed++) {
        final positions = game.debugCardLayout(Vector2(w, h), Random(seed));
        for (final p in positions) {
          final box = tiltedBox(p, game);
          expect(box.left, greaterThanOrEqualTo(0),
              reason: 'se sale por la izquierda en $name (seed $seed)');
          expect(box.right, lessThanOrEqualTo(w),
              reason: 'se sale por la derecha en $name (seed $seed)');
          expect(box.top, greaterThanOrEqualTo(0),
              reason: 'se sale por arriba en $name (seed $seed)');
          // Abajo se reserva sitio para la barra de navegación.
          expect(box.bottom, lessThanOrEqualTo(h),
              reason: 'se sale por abajo en $name (seed $seed)');
        }
      }
    }
  });

  test('la carta conserva la proporción de siempre', () {
    final game = buildGame();
    game.debugCardLayout(Vector2(360, 780), Random(0));
    expect(game.cardHeight / game.cardWidth, closeTo(115 / 85, 0.01));
  });

  test('las 5 cartas del daily se reparten 3-2, como en la web', () {
    final game = buildGame();
    final positions = game.debugCardLayout(Vector2(360, 780), Random(1));

    // Se agrupan por altura: las de una misma fila comparten banda.
    final rows = <double, int>{};
    for (final p in positions) {
      final band = rows.keys.firstWhere(
        (k) => (k - p.y).abs() < game.cardHeight * 0.8,
        orElse: () => p.y,
      );
      rows[band] = (rows[band] ?? 0) + 1;
    }

    final counts = rows.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    expect(counts.map((e) => e.value).toList(), [3, 2]);
  });
}
