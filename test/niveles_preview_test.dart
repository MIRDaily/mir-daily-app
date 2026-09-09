// Muestrario del sistema de niveles: el marco de ficha en sus casos apurados,
// la escala de la llama, la tarjeta de nivel y la lista de desafíos.
//
//   flutter test test/niveles_preview_test.dart --update-goldens
//
// Deja las imágenes en test/goldens/. No es una prueba de regresión: es la
// hoja de contactos para poder mirar el resultado sin levantar la app. En
// estos tests las fuentes reales no cargan y el texto sale en bloques: es
// normal, y por eso el marco se comprueba aparte con medidas y no a ojo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/progress.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/core/theme/levels.dart';
import 'package:mirdaily_app/features/progress/widgets/llama_racha.dart';
import 'package:mirdaily_app/features/progress/widgets/marco_nivel.dart';
import 'package:mirdaily_app/features/progress/widgets/seccion_desafios.dart';
import 'package:mirdaily_app/features/progress/widgets/tarjeta_nivel.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

ProgressSnapshot _demo() => ProgressSnapshot.fromJson({
      'progress': {
        'level': 12,
        'maxLevel': 100,
        'xpTotal': 3665,
        'xpIntoLevel': 90,
        'xpForNext': 475,
        'currentStreak': 9,
        'longestStreak': 14,
        'streakFreezes': 2,
        'streakMultiplier': 1.15,
        'lastActiveDay': '2026-09-08',
        'xpToday': 300,
        'xpTodayTotal': 800,
        'dailyCap': 300,
      },
      'daily': [
        {
          'code': 'daily_do',
          'scope': 'daily',
          'metric': 'daily_done',
          'title': 'Haz el Daily',
          'description': 'Completa el sobre de hoy',
          'progress': 1,
          'target': 1,
          'xpReward': 30,
          'completed': true,
          'sortOrder': 10,
          'meta': null,
        },
        {
          'code': 'daily_weak',
          'scope': 'daily',
          'metric': 'weak_topic_questions',
          'title': 'Ataca tu punto débil',
          'description': 'Responde 8 preguntas de Lesiones de partes blandas',
          'progress': 3,
          'target': 8,
          'xpReward': 35,
          'completed': false,
          'sortOrder': 30,
          'meta': {
            'topic_id': 26,
            'topic_name': 'Lesiones de partes blandas',
            'subject_name': 'Traumatología',
            'accuracy': 62.5,
          },
        },
        {
          'code': 'daily_rot',
          'scope': 'daily',
          'metric': 'questions_answered',
          'title': 'Sesión de fondo',
          'description': 'Responde 25 preguntas hoy',
          'progress': 25,
          'target': 25,
          'xpReward': 25,
          'completed': true,
          'sortOrder': 20,
          'meta': null,
        },
        // El bono: se pinta, pero no cuenta para el "2/3" de la cabecera.
        {
          'code': 'daily_all',
          'scope': 'daily',
          'metric': 'all_daily',
          'title': 'Día redondo',
          'description': 'Completa los tres desafíos del día',
          'progress': 2,
          'target': 3,
          'xpReward': 40,
          'completed': false,
          'sortOrder': 90,
          'meta': null,
        },
      ],
      'weekly': [
        {
          'code': 'weekly_five',
          'scope': 'weekly',
          'metric': 'daily_done_week',
          'title': 'Cinco de siete',
          'description': 'Haz el Daily 5 días de esta semana',
          'progress': 3,
          'target': 5,
          'xpReward': 150,
          'completed': false,
          'sortOrder': 10,
          'meta': null,
        },
      ],
    });

Widget _lienzo(Widget hijo) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: hijo,
        ),
      ),
    );

void main() {
  testWidgets('muestrario del marco de ficha y la llama', (tester) async {
    tester.view.physicalSize = const Size(420, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_lienzo(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('El marco de ficha'),
          StickerCard(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // El 100 es el caso apurado: con tres cifras el cuerpo baja
                // para no rozar el cosido de puntos.
                for (final n in [1, 12, 47, 100])
                  MarcoNivel(
                    nivel: n,
                    tamano: 96,
                    color: rankForLevel(n).color,
                  ),
                for (final n in [1, 100])
                  MarcoNivel(
                    nivel: n,
                    tamano: 48,
                    color: rankForLevel(n).color,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel('La llama'),
          StickerCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final r in [0, 3, 9, 20, 45])
                  Column(
                    children: [
                      LlamaRacha(racha: r, size: 54),
                      const SizedBox(height: 6),
                      Text('$r', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/niveles_marco_llama.png'),
    );
  });

  testWidgets('muestrario de la tarjeta de nivel y los desafíos',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final datos = _demo();

    await tester.pumpWidget(_lienzo(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Tu progreso'),
          TarjetaNivel(progress: datos.progress),
          const SizedBox(height: 22),
          SeccionDesafios(snapshot: datos),
        ],
      ),
    ));
    // Nada de pumpAndSettle: el latido de la llama no para nunca y colgaría.
    await tester.pump(const Duration(milliseconds: 900));

    // El contador de la cabecera excluye el bono: "2/3", nunca "2/4". Se busca
    // dentro del rótulo porque el propio bono lleva su "2/3" en su fila.
    expect(
      find.descendant(
        of: find.byType(SectionLabel),
        matching: find.text('2/3'),
      ),
      findsOneWidget,
    );
    // Y el bono sí aparece en la lista.
    expect(find.text('Día redondo'), findsOneWidget);
    // La cifra del día es xpTodayTotal, no la del tope.
    expect(find.textContaining('800'), findsWidgets);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/niveles_perfil.png'),
    );
  });

  testWidgets('en apaisado los desafíos van a dos columnas', (tester) async {
    // Siete tarjetas en una sola columna obligan a un scroll largo justo donde
    // hay ancho de sobra.
    tester.view.physicalSize = const Size(1100, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final datos = _demo();

    await tester.pumpWidget(_lienzo(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Tu progreso'),
          TarjetaNivel(progress: datos.progress),
          const SizedBox(height: 22),
          SeccionDesafios(snapshot: datos),
        ],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 900));

    // Los dos rótulos están a la MISMA altura: es lo que prueba que van uno al
    // lado del otro y no apilados.
    final hoy = tester.getTopLeft(find.text('DESAFÍOS DE HOY'));
    final semana = tester.getTopLeft(find.text('ESTA SEMANA'));
    // Medio píxel de holgura: el rótulo de "hoy" lleva contador y el de la
    // semana no, y eso mueve la línea base lo justo.
    expect(semana.dy, moreOrLessEquals(hoy.dy, epsilon: 1), reason: 'misma fila');
    expect(semana.dx, greaterThan(hoy.dx), reason: 'la semana va a la derecha');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/niveles_perfil_apaisado.png'),
    );
  });
}
