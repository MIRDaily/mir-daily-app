// El sistema de niveles: la curva, los rangos, el parseo y la detección de
// logros.
//
//   flutter test test/niveles_test.dart
//
// Vigila las cuatro cosas que este sistema NO puede equivocarse, porque el
// mismo usuario ve el mismo dato en la web y en el móvil:
//
//   · La curva tiene que coincidir con `mirdaily_xp_for_level` de la base de
//     datos y con `src/lib/levels.ts` de la web.
//   · "Día redondo" (metric = all_daily) es el BONO, no un cuarto desafío:
//     contarlo daría "1/4" cuando en pantalla hay tres tareas.
//   · `xpToday` y `xpTodayTotal` NO son lo mismo: el tope solo mide el
//     primero, y confundirlos ya costó un fallo en la web.
//   · La primera vez que se ve a un usuario no se celebra nada.
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/logros.dart';
import 'package:mirdaily_app/core/models/progress.dart';
import 'package:mirdaily_app/core/theme/levels.dart';

ProgressSnapshot _snap({
  int level = 1,
  int xpTotal = 0,
  int racha = 0,
  List<Map<String, dynamic>> daily = const [],
  List<Map<String, dynamic>> weekly = const [],
}) {
  return ProgressSnapshot.fromJson({
    'progress': {
      'level': level,
      'maxLevel': 100,
      'xpTotal': xpTotal,
      'xpIntoLevel': xpTotal - xpParaNivel(level),
      'xpForNext': costeNivel(level),
      'currentStreak': racha,
      'longestStreak': racha,
      'streakFreezes': 0,
      'streakMultiplier': 1.0,
      'lastActiveDay': '2026-09-08',
      'xpToday': 0,
      'xpTodayTotal': 0,
      'dailyCap': 300,
    },
    'daily': daily,
    'weekly': weekly,
  });
}

Map<String, dynamic> _reto(
  String code, {
  String scope = 'daily',
  String metric = 'daily_questions',
  bool completed = false,
  int progress = 0,
  int target = 10,
}) =>
    {
      'code': code,
      'scope': scope,
      'metric': metric,
      'title': 'Reto $code',
      'description': 'Haz cosas',
      'progress': progress,
      'target': target,
      'xpReward': 30,
      'completed': completed,
      'sortOrder': 10,
      'meta': null,
    };

void main() {
  group('la curva', () {
    test('coincide con los valores de la base de datos y de la web', () {
      // Los tres puntos de control del encargo. Si alguno falla, la animación
      // de subida acabaría en un número distinto del que enseña el servidor.
      expect(xpParaNivel(12), 3575);
      expect(xpParaNivel(20), 8075);
      expect(xpParaNivel(100), 141075);
    });

    test('subir del nivel n al n+1 cuesta 200 + 25 (n-1)', () {
      expect(costeNivel(1), 200);
      expect(costeNivel(2), 225);
      for (var n = 1; n < 100; n++) {
        expect(xpParaNivel(n + 1) - xpParaNivel(n), costeNivel(n),
            reason: 'el peldaño $n no cuadra con su coste');
      }
    });

    test('nivelParaXp es la inversa exacta, y topa en 100', () {
      for (var n = 1; n <= 100; n++) {
        expect(nivelParaXp(xpParaNivel(n)), n);
        if (n > 1) {
          expect(nivelParaXp(xpParaNivel(n) - 1), n - 1,
              reason: 'un XP por debajo del umbral no puede dar el nivel n');
        }
      }
      expect(nivelParaXp(999999), 100, reason: 'el tope es 100');
      expect(nivelParaXp(-5), 1, reason: 'un XP negativo no puede bajar del 1');
    });
  });

  group('los rangos', () {
    test('el rango es el escalón más alto cuyo mínimo no lo supera', () {
      expect(rankForLevel(1).name, 'Novato');
      expect(rankForLevel(5).name, 'Novato');
      expect(rankForLevel(6).name, 'Estudiante');
      expect(rankForLevel(22).name, 'Residente R1');
      expect(rankForLevel(100).name, 'Jefe de servicio');
    });

    test('el siguiente rango es null solo en el último', () {
      expect(nextRank(1)?.name, 'Estudiante');
      expect(nextRank(99)?.name, 'Jefe de servicio');
      expect(nextRank(100), isNull);
    });
  });

  group('el parseo de /api/progress', () {
    test('el bono "Día redondo" se muestra pero NO se cuenta', () {
      final s = _snap(daily: [
        _reto('daily_questions', completed: true),
        _reto('daily_weak', metric: 'weak_topic_questions'),
        _reto('daily_rot'),
        _reto('daily_all', metric: 'all_daily'),
      ]);

      expect(s.daily, hasLength(4), reason: 'los cuatro se pintan');
      expect(s.dailyReales, hasLength(3), reason: 'solo tres son tareas');
      expect(s.dailyHechos, 1);
      // El contador de la cabecera: "1/3", nunca "1/4".
      expect('${s.dailyHechos}/${s.dailyReales.length}', '1/3');
    });

    test('xpToday mide el tope y xpTodayTotal lo ganado de verdad', () {
      final p = UserProgress.fromJson({
        'level': 5,
        'xpToday': 300,
        'xpTodayTotal': 800,
        'dailyCap': 300,
      });

      expect(p.fraccionTope, 1.0, reason: 'la barra del tope mide xpToday');
      expect(p.xpTodayTotal, 800, reason: 'la cifra que se enseña');
      expect(p.xpFueraDeTope, 500,
          reason: 'los premios semanales viven fuera del tope');
    });

    test('una respuesta antigua sin xpTodayTotal cae en xpToday', () {
      final p = UserProgress.fromJson({'level': 3, 'xpToday': 120});
      expect(p.xpTodayTotal, 120);
      expect(p.xpFueraDeTope, 0);
    });

    test('el nivel máximo no divide por cero', () {
      final p = UserProgress.fromJson({
        'level': 100,
        'maxLevel': 100,
        'xpIntoLevel': 0,
        'xpForNext': 0,
      });
      expect(p.esTope, isTrue);
      expect(p.fraccionNivel, 1.0);
      expect(p.xpRestante, 0);
    });
  });

  group('la detección de logros', () {
    test('subir dentro del mismo rango es "nivel", cruzarlo es "rango"', () {
      final ref = Referencia(
        nivel: 3,
        xpTotal: xpParaNivel(3),
        racha: 1,
        hechos: const [],
      );

      final mismoRango = detectarLogros(
        ref,
        _snap(level: 4, xpTotal: xpParaNivel(4), racha: 1),
      );
      expect(mismoRango.single.tipo, TipoLogro.nivel);

      final cambioDeRango = detectarLogros(
        ref,
        _snap(level: 6, xpTotal: xpParaNivel(6), racha: 1),
      );
      expect(cambioDeRango.single.tipo, TipoLogro.rango,
          reason: 'cambiar de rango pesa más y no se duplica el aviso');
      expect(cambioDeRango.single.rango, 'Estudiante');
    });

    test('el logro lleva el TRAMO, para poder recorrerlo', () {
      final ref = Referencia(
        nivel: 11,
        xpTotal: xpParaNivel(11) + 30,
        racha: 0,
        hechos: const [],
      );
      final logro = detectarLogros(
        ref,
        _snap(level: 12, xpTotal: xpParaNivel(12) + 90),
      ).single;

      expect(logro.xpAntes, xpParaNivel(11) + 30);
      expect(logro.xpDespues, xpParaNivel(12) + 90);
      expect(nivelParaXp(logro.xpAntes), 11);
      expect(nivelParaXp(logro.xpDespues), 12);
    });

    test('un XP anterior mayor que el nuevo no rompe el tramo', () {
      // Pasa si se reconstruye el ledger: la barra arranca, como mucho, en el
      // XP actual, nunca hacia atrás.
      const ref = Referencia(
        nivel: 4,
        xpTotal: 99999,
        racha: 0,
        hechos: [],
      );
      final logro = detectarLogros(ref, _snap(level: 5, xpTotal: 1000)).single;
      expect(logro.xpAntes, lessThanOrEqualTo(logro.xpDespues));
    });

    test('bajar de nivel no celebra nada', () {
      final ref = Referencia(
        nivel: 20,
        xpTotal: xpParaNivel(20),
        racha: 5,
        hechos: const [],
      );
      expect(detectarLogros(ref, _snap(level: 12, xpTotal: xpParaNivel(12))),
          isEmpty);
    });

    test('solo los hitos de racha se celebran, no cada día', () {
      Referencia ref(int r) =>
          Referencia(nivel: 1, xpTotal: 0, racha: r, hechos: const []);

      expect(detectarLogros(ref(1), _snap(racha: 2)), isEmpty,
          reason: 'el día 2 no es hito: felicitar cada día es ruido');
      expect(detectarLogros(ref(2), _snap(racha: 3)).single.tipo,
          TipoLogro.racha);
      expect(detectarLogros(ref(29), _snap(racha: 30)).single.dias, 30);
    });

    test('un desafío ya visto no vuelve a avisar', () {
      final datos = _snap(
        daily: [_reto('daily_questions', completed: true)],
        weekly: [_reto('weekly_five', scope: 'weekly', completed: true)],
      );

      final primeraVez = detectarLogros(
        const Referencia(nivel: 1, xpTotal: 0, racha: 0, hechos: []),
        datos,
      );
      expect(primeraVez, hasLength(2));
      expect(primeraVez.every((l) => l.tipo == TipoLogro.desafio), isTrue);

      // La referencia de después ya los trae: no se repiten.
      expect(detectarLogros(Referencia.de(datos), datos), isEmpty);
    });

    test('el orden por peso pone el rango primero y el desafío último', () {
      final tanda = [
        const Logro(id: 'a', tipo: TipoLogro.desafio),
        const Logro(id: 'b', tipo: TipoLogro.racha, dias: 7),
        const Logro(id: 'c', tipo: TipoLogro.rango, nivel: 20),
        const Logro(id: 'd', tipo: TipoLogro.nivel, nivel: 4),
      ];
      expect(
        ordenarPorPeso(tanda).map((l) => l.tipo),
        [TipoLogro.rango, TipoLogro.nivel, TipoLogro.racha, TipoLogro.desafio],
      );
    });

    test('un logro sobrevive al viaje de ida y vuelta por disco', () {
      // La cola se persiste: un logro conseguido justo antes de cerrar la app
      // tiene que seguir ahí al volver, con su tramo intacto.
      const original = Logro(
        id: 'x1',
        tipo: TipoLogro.rango,
        nivel: 20,
        rango: 'Residente R1',
        xpAntes: 7000,
        xpDespues: 8200,
      );
      final vuelta = Logro.fromJson(original.toJson())!;

      expect(vuelta.id, 'x1');
      expect(vuelta.tipo, TipoLogro.rango);
      expect(vuelta.nivel, 20);
      expect(vuelta.rango, 'Residente R1');
      expect(vuelta.xpAntes, 7000);
      expect(vuelta.xpDespues, 8200);
    });

    test('una referencia vieja sin xpTotal se rellena con el nivel', () {
      final r = Referencia.fromJson({'nivel': 12, 'racha': 3})!;
      expect(r.xpTotal, xpParaNivel(12),
          reason: 'lo más honesto sin inventar: la barra arranca vacía');
    });
  });
}
