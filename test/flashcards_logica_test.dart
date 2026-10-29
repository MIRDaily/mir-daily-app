// Lógica de las flashcards (lib/core/models/flashcards.dart) con los MISMOS casos que la web:
// test/flashcardsSesion.test.ts (ajustes de la sesión), test/flashcardsIA3.test.ts (escalera) y
// test/subjectVisuals.test.ts (asignatura reconocida por el nombre). Si la app y la web dicen cosas
// distintas sobre el mismo grupo, el usuario ve dos números para lo mismo.
import 'package:flutter_test/flutter_test.dart';
import 'package:mirdaily_app/core/data/mir_weights.dart';
import 'package:mirdaily_app/core/models/flashcards.dart';
import 'package:mirdaily_app/core/models/models.dart';

var _n = 0;
Flashcard _carta(String? topic, int? level, FlashStatus status, bool isDue) {
  _n++;
  return Flashcard(itemId: _n, flashcardId: 'f$_n', front: 'P$_n', back: 'R', topic: topic, level: level, status: status, isDue: isDue);
}

final _cards = [
  _carta('Gota', 1, FlashStatus.failed, true),
  _carta('Gota', 1, FlashStatus.learning, true),
  _carta('Gota', 2, FlashStatus.learning, false),
  _carta('Gota', 2, FlashStatus.nueva, true),
  _carta('Condrocalcinosis', 1, FlashStatus.nueva, true),
  _carta('Condrocalcinosis', 3, FlashStatus.nueva, true),
  _carta(null, null, FlashStatus.mastered, false),
  _carta('  ', null, FlashStatus.nueva, true),
];

AjustesSesion _con({int? Function()? cantidad, SoloTarjetas? solo, List<String>? temas, List<int>? niveles, bool? escalera}) =>
    kAjustesPorDefecto.copyWith(cantidad: cantidad ?? () => null, solo: solo, temas: temas == null ? null : () => temas, niveles: niveles, escalera: escalera);

const _raw = {
  'topics': [
    {
      'topic': 'Arteritis de células gigantes',
      'levels': [
        {'level': 3, 'total': 5, 'mastered': 0, 'lowerTotal': 20, 'lowerMastered': 12, 'needed': 16, 'unlocked': false},
        {'level': 1, 'total': 10, 'mastered': 8, 'lowerTotal': 0, 'lowerMastered': 0, 'needed': 0, 'unlocked': true},
        {'level': 2, 'total': 10, 'mastered': 4, 'lowerTotal': 10, 'lowerMastered': 8, 'needed': 8, 'unlocked': true},
        {'level': 2, 'total': 99},
      ],
    },
    {
      'topic': null,
      'levels': [
        {'level': 1, 'total': 2, 'mastered': 0, 'lowerTotal': 0, 'lowerMastered': 0, 'needed': 0, 'unlocked': 'true'},
      ],
    },
    {
      'topic': 'Vacío',
      'levels': [
        {'level': 9},
      ],
    },
  ],
};

void main() {
  group('ajustes de la sesión', () {
    test('qué tarjetas: las mismas definiciones que el servidor', () {
      expect(coincideSolo(_cards[0], SoloTarjetas.failed), isTrue);
      expect(coincideSolo(_cards[0], SoloTarjetas.due), isTrue, reason: 'una fallada también está pendiente');
      expect(coincideSolo(_cards[1], SoloTarjetas.due), isTrue);
      expect(coincideSolo(_cards[2], SoloTarjetas.due), isFalse, reason: 'vista pero aún no toca');
      expect(coincideSolo(_cards[3], SoloTarjetas.due), isFalse, reason: 'una nueva no es pendiente de repaso');
      expect(coincideSolo(_cards[3], SoloTarjetas.nueva), isTrue);
      expect(coinciden(_cards, _con(solo: SoloTarjetas.failed)).length, 1);
      expect(coinciden(_cards, _con(solo: SoloTarjetas.due)).length, 2);
      expect(coinciden(_cards, _con(solo: SoloTarjetas.nueva)).length, 4);
    });

    test('temas: con su número, «sin tema» al final (vacío o en blanco cuentan igual)', () {
      expect(temasDelGrupo(_cards).map((t) => (t.tema, t.total)).toList(), [('Condrocalcinosis', 2), ('Gota', 4), ('', 2)]);
      expect(coinciden(_cards, _con(temas: ['Gota'])).length, 4);
      expect(coinciden(_cards, _con(temas: [''])).length, 2);
    });

    test('dificultad: con filtro, las que no tienen nivel no entran; y se combina con lo demás', () {
      expect(coinciden(_cards, _con(niveles: [1])).length, 3);
      expect(coinciden(_cards, _con(niveles: [1], solo: SoloTarjetas.nueva, temas: ['Condrocalcinosis'])).length, 1);
    });

    test('escalera: las nuevas de un nivel cerrado no cuentan (con la foto del servidor)', () {
      const escalera = Escalera([
        TemaEscalera('Condrocalcinosis', [
          EscalonEscalera(level: 1, total: 1, unlocked: true),
          EscalonEscalera(level: 3, total: 1, lowerTotal: 1, needed: 1),
        ]),
      ]);
      expect(coinciden(_cards, _con(temas: ['Condrocalcinosis']), escalera).length, 1);
      expect(coinciden(_cards, _con(temas: ['Condrocalcinosis'], escalera: false), escalera).length, 2);
    });

    test('paraEmpezar: solo los filtros que filtran algo, y el tope de servidas', () {
      final todo = paraEmpezar(_con(), _cards, true);
      expect(todo.opciones, {'ladder': true});
      expect(todo.limit, 20, reason: 'mínimo 20');
      final r = paraEmpezar(
        _con(cantidad: () => 10, solo: SoloTarjetas.failed, temas: ['Gota'], niveles: [1, 2], escalera: false),
        _cards,
        true,
      );
      expect(r.opciones, {
        'levels': [1, 2],
        'ladder': false,
        'topics': ['Gota'],
        'onlyStatus': 'failed',
        'cardLimit': 10,
      });
      expect(paraEmpezar(_con(temas: ['Gota', 'Condrocalcinosis', '']), _cards, true).opciones, {'ladder': true},
          reason: 'todos los temas = sin filtro');
      expect(paraEmpezar(_con(niveles: [1]), _cards, false).opciones, {'ladder': false},
          reason: 'sin tarjetas con nivel, ni niveles ni escalera');
      final muchas = List.generate(300, (_) => _carta('X', null, FlashStatus.nueva, true));
      expect(paraEmpezar(_con(), muchas, false).limit, 200, reason: 'máximo 200');
    });

    test('sanearAjustes: lo guardado no se da por bueno', () {
      final d = sanearAjustes(null);
      expect((d.cantidad, d.solo, d.temas, d.niveles, d.escalera), (20, SoloTarjetas.todas, null, kFlashLevels, true));
      final s = sanearAjustes({
        'cantidad': 7,
        'solo': 'raro',
        'temas': [3, 'Gota'],
        'niveles': [9, 2],
        'escalera': 'no',
      });
      expect((s.cantidad, s.solo, s.escalera), (20, SoloTarjetas.todas, true));
      expect(s.temas, ['Gota']);
      expect(s.niveles, [2]);
      expect(sanearAjustes({'cantidad': null}).cantidad, isNull, reason: 'todas');
      expect(sanearAjustes({'escalera': false}).escalera, isFalse);
      expect(sanearAjustes({'temas': []}).temas, isNull);
      // Ida y vuelta: lo que se guarda se lee igual.
      final ida = sanearAjustes(s.copyWith(cantidad: () => 50, solo: SoloTarjetas.nueva).toJson());
      expect((ida.cantidad, ida.solo), (50, SoloTarjetas.nueva));
    });
  });

  group('escalera', () {
    test('sanearEscalera: niveles válidos sin repetir y en orden; abierto solo si es true; temas vacíos fuera', () {
      final e = sanearEscalera(_raw);
      expect(e.topics.length, 2);
      expect(e.topics[0].levels.map((l) => l.level).toList(), [1, 2, 3]);
      expect(e.topics[0].levels[1].total, 10, reason: 'el nivel repetido se ignora');
      expect(e.topics[1].topic, isNull);
      expect(e.topics[1].levels[0].unlocked, isFalse);
      expect(sanearEscalera('basura').topics, isEmpty);
      expect(hayEscalera(e), isTrue);
      expect(hayEscalera(Escalera([e.topics[1]])), isFalse, reason: 'un solo nivel: nada que escalar');
    });

    test('textos: «12 de 20 dominadas de fácil y media», y el escalón anterior cerrado', () {
      final t = sanearEscalera(_raw).topics[0];
      expect(nombresNiveles([1, 2, 3]), 'fácil, media y difícil');
      expect(textoFalta(t, t.levels[2]), '12 de 20 dominadas de fácil y media (hacen falta 16)');
      const camino = TemaEscalera('X', [
        EscalonEscalera(level: 1, total: 5, mastered: 3, unlocked: true),
        EscalonEscalera(level: 2, total: 5, mastered: 5, lowerTotal: 5, lowerMastered: 3, needed: 4),
        EscalonEscalera(level: 3, total: 5, lowerTotal: 10, lowerMastered: 8, needed: 8),
      ]);
      expect(textoFalta(camino, camino.levels[2]), '8 de 10 dominadas de fácil y media; antes hay que abrir media');
      final r = resumenEscalera(const Escalera([camino]));
      expect((r.abiertas, r.cerradas, r.nivelesCerrados), (5, 10, 2));
    });

    test('desbloqueados: solo lo que estaba cerrado y ahora está abierto', () {
      final antes = sanearEscalera(_raw);
      final despues = sanearEscalera({
        'topics': [
          {
            'topic': 'Arteritis de células gigantes',
            'levels': [
              {'level': 1, 'total': 10, 'mastered': 9, 'unlocked': true},
              {'level': 2, 'total': 10, 'mastered': 8, 'unlocked': true},
              {'level': 3, 'total': 5, 'mastered': 0, 'unlocked': true},
              {'level': 4, 'total': 3, 'mastered': 0, 'unlocked': true},
            ],
          },
          {
            'topic': null,
            'levels': [
              {'level': 1, 'total': 2, 'unlocked': true},
            ],
          },
        ],
      });
      final d = desbloqueados(antes, despues);
      expect(d, [(topic: 'Arteritis de células gigantes', level: 3), (topic: null, level: 1)]);
      expect(textoDesbloqueo(d.sublist(0, 1)), 'Has desbloqueado Difícil en Arteritis de células gigantes');
      expect(textoDesbloqueo(d), 'Has desbloqueado Difícil en Arteritis de células gigantes y Fácil');
      expect(textoDesbloqueo(const []), '');
      expect(desbloqueados(null, despues), isEmpty);
    });
  });

  group('intervalos de los botones', () {
    final ahora = DateTime.utc(2026, 10, 29, 10);
    test('días, meses y años como Anki; minutos y horas por debajo de un día', () {
      expect(formatInterval(null, ahora), '—');
      expect(formatInterval(GradePreview(0, ahora.add(const Duration(seconds: 20))), ahora), '<1 min');
      expect(formatInterval(GradePreview(0, ahora.add(const Duration(minutes: 10))), ahora), '10 min');
      expect(formatInterval(GradePreview(0, ahora.add(const Duration(hours: 5))), ahora), '5 h');
      expect(formatInterval(GradePreview(3, ahora), ahora), '3 d');
      expect(formatInterval(GradePreview(45, ahora), ahora), '2 m');
      expect(formatInterval(GradePreview(365, ahora), ahora), '1 a');
      expect(formatInterval(GradePreview(548, ahora), ahora), '1.5 a');
      expect(formatInterval(GradePreview(4000, ahora), ahora), '11 a');
    });

    test('la previsión llega por grado y se ignora lo que no vale', () {
      final p = GradePreview.mapFromJson({
        '1': {'scheduledDays': 0, 'due': '2026-10-29T10:10:00.000Z'},
        '3': {'scheduledDays': 4, 'due': '2026-11-02T10:00:00.000Z'},
        '4': {'scheduledDays': 9},
      });
      expect(p.keys.toList(), [1, 3]);
      expect(p[3]!.scheduledDays, 4);
    });
  });

  group('temas de un grupo', () {
    test('cubos por tema, sin tema al final y repasos sin contar dos veces', () {
      final rows = groupTopics(_cards);
      expect(rows.map((r) => r.label).toList(), ['Condrocalcinosis', 'Gota', 'Sin tema']);
      final gota = rows[1];
      expect((gota.total, gota.dueCards, gota.summary.nuevas, gota.summary.failed, gota.summary.learning), (4, 3, 1, 1, 2));
      expect(gota.repasos, 1);
      expect(rows.last.key, isNull);
    });

    test('orden en español: las tildes no se van detrás de la zeta', () {
      expect(compararEs('Úlcera', 'Vasculitis'), lessThan(0));
      expect(compararEs('ñame', 'nube'), greaterThan(0));
    });
  });

  group('asignatura por el nombre', () {
    test('no confunde urología con neurología y acepta abreviaturas', () {
      expect(visualAsignatura('Urología').key, 'urologia');
      expect(visualAsignatura('Neurología').key, 'neurologia');
      expect(visualAsignatura('Neumo').key, 'neumologia');
      expect(visualAsignatura('Digestivo y cirugía general').key, 'digestivo');
    });

    test('categorías de la Biblioteca y siglas', () {
      expect(visualAsignatura('Cardiología').categoria, CategoriaAsignatura.medica);
      expect(visualAsignatura('Traumatología').categoria, CategoriaAsignatura.quirurgica);
      expect(visualAsignatura('Farmacología').categoria, CategoriaAsignatura.basica);
      expect(visualAsignatura('Bioestadística').sigla, 'ES');
      expect(visualAsignatura('Cirugía General y Digestivo').sigla, 'DG');
      expect(visualAsignatura('Cirugía Ortopédica y Trauma').sigla, 'TR');
      expect(visualAsignatura('Cirugía Plástica').sigla, 'CP');
      final otro = visualAsignatura('Fórmulas que se me olvidan');
      expect((otro.categoria, otro.key, otro.sigla), (CategoriaAsignatura.personal, null, 'FQ'));
      expect(visualAsignatura('Chuletas').sigla, 'CH');
    });

    test('el color y el icono elegidos a mano mandan; la categoría no se toca', () {
      expect(visualAsignatura('Cardiología').icon, 'cardiology');
      final aMano = visualAsignatura('Cardiología', 'teal', 'science');
      expect((aMano.icon, aMano.color, aMano.categoria), ('science', 'teal', CategoriaAsignatura.medica));
    });

    test('Mosaico es la antigua Miscelánea: mismo peso y misma sigla', () {
      expect(weightForSubject('Mosaico'), weightForSubject('Miscelánea y Ciencias Básicas'));
      expect(weightForSubject('Mosaico'), isNot(kDefaultWeight));
      expect(visualAsignatura('Mosaico').key, 'miscelanea');
    });

    test('secciones por categoría, buscador y orden', () {
      const decks = [
        FlashDeck(id: 'a', name: 'Cardiología', dueCards: 2, totalCards: 10),
        FlashDeck(id: 'b', name: 'Digestivo', dueCards: 9, totalCards: 10),
        FlashDeck(id: 'c', name: 'Neumología', dueCards: 5, totalCards: 10, summary: FlashSummary(mastered: 9)),
        FlashDeck(id: 'd', name: 'Mis chuletas', dueCards: 1),
      ];
      final s = agruparAsignaturas(decks, '', OrdenAsignaturas.pendientes);
      expect(s.map((x) => x.categoria).toList(), [CategoriaAsignatura.medica, CategoriaAsignatura.quirurgica, CategoriaAsignatura.personal]);
      expect(s.first.grupos.map((d) => d.id).toList(), ['c', 'a']);
      expect(agruparAsignaturas(decks, '', OrdenAsignaturas.dominio).first.grupos.map((d) => d.id).toList(), ['a', 'c']);
      expect(agruparAsignaturas(decks, 'neu', OrdenAsignaturas.nombre).single.grupos.single.id, 'c');
    });
  });
}
