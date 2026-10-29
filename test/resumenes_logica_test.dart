// Lo puro de la tanda 3 de resúmenes (lib/features/resumenes/resumenes_logica.dart) con los MISMOS
// casos que la web: test/resumenes.test.ts, resumenesEstudio.test.ts, resumenesPulido.test.ts y
// resumenesAmpliar.test.ts.
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mirdaily_app/core/models/ia.dart';
import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/core/models/resumen_ia.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_huecos.dart' show Respuesta;
import 'package:mirdaily_app/features/resumenes/resumenes_logica.dart';

const _t = 'La tiroiditis de Hashimoto da anti-TPO positivos y se trata con 1,6 µg/kg/día de levotiroxina.';
Hueco _h(String trozo, int n) {
  final i = _t.indexOf(trozo);
  return Hueco(i, i + trozo.length, n);
}

final _hs = [_h('Hashimoto', 1), _h('anti-TPO', 2), _h('1,6 µg/kg/día', 4), _h('levotiroxina', 2)];

var _k = 0;
Parrafo _p(String? tema, List<Hueco> huecos, EstadoParrafoSrs? status, {bool? due, List<int>? fallados}) => Parrafo(
      itemId: ++_k,
      id: 'p$_k',
      tema: tema,
      modo: ModoResumen.resumen,
      texto: _t,
      huecos: huecos,
      aiGenerated: false,
      status: status,
      due: due,
      huecosFallados: fallados,
      fallos: 0,
    );

const _dato = {
  'grupos': 2,
  'parrafos': 12,
  'nuevos': 3,
  'pendientes': 7,
  'repasoAhora': 4,
  'prevision': {
    'atrasados': 1,
    'hoy': 5,
    'manana': 2,
    'semana': 8,
    'mes': 9,
    'dias': [
      {'fecha': '2026-10-10', 'n': 5},
      {'fecha': '2026-10-11', 'n': 2},
    ],
  },
  'estados': {'new': 3, 'failed': 1, 'learning': 6, 'mastered': 2},
  'retencion': {'repasos': 20, 'programados': 15, 'recordados': 12, 'tasa': 0.8, 'programados30': 8, 'tasa30': 0.75},
  'huecos': {'repasados': 40, 'sabidos': 30, 'tasa': 0.75},
  'masFallados': [
    {'itemId': 9, 'grupoId': 'g', 'grupo': 'Gota', 'tema': 'Gota', 'hueco': 1, 'texto': 'colchicina', 'nivel': 2, 'fallos': 3, 'intentos': 4, 'falladoAhora': true},
  ],
};

Map<String, dynamic> _con(Map<String, dynamic> cambios) => {..._dato, ...cambios};

void main() {
  group('previsión y aviso', () {
    test('se queda tal cual si es buena; ceros y nulos si no', () {
      final p = sanearPrevision(_dato);
      expect((p.pendientes, p.atrasados, p.hoy, p.mes, p.dias.length, p.tasa, p.tasaHuecos), (7, 1, 5, 9, 2, 0.8, 0.75));
      expect(p.masFallados.single.texto, 'colchicina');
      final v = sanearPrevision(null);
      expect((v.pendientes, v.tasa, v.masFallados.length), (0, null, 0));
      final raro = sanearPrevision({
        'pendientes': -2,
        'retencion': {'tasa': 7},
        'prevision': {
          'dias': [
            {'fecha': 'mañana', 'n': 3},
            null,
          ],
        },
        'masFallados': [
          {'texto': '  '},
          {'texto': 'x', 'nivel': 9},
        ],
      });
      expect((raro.pendientes, raro.tasa, raro.dias.length, raro.masFallados.length, raro.masFallados.first.nivel), (0, 1.0, 0, 1, 2));
    });

    test('«Tienes N párrafos para repasar» con el desglose; nada si no hay nada', () {
      final a = textoAviso(sanearPrevision(_dato))!;
      expect(a.titulo, 'Tienes 7 párrafos para repasar');
      expect(a.detalle, 'En tus resúmenes activos: 4 de repaso (1 de días anteriores) · 3 nuevos.');
      expect(
        textoAviso(sanearPrevision(_con({
          'pendientes': 78,
          'repasoAhora': 24,
          'nuevos': 54,
          'prevision': {'atrasados': 24},
        })))!
            .detalle,
        'En tus resúmenes activos: 24 de repaso (todos de días anteriores) · 54 nuevos.',
      );
      expect(
        textoAviso(sanearPrevision(_con({'pendientes': 1, 'repasoAhora': 0, 'nuevos': 1, 'prevision': {'atrasados': 0}})))!.titulo,
        'Tienes 1 párrafo para repasar',
      );
      expect(textoAviso(sanearPrevision(_con({'pendientes': 0}))), isNull);
      expect(textoAviso(sanearPrevision(_con({'pendientes': 12345})))!.titulo, contains('12.345 párrafos'));
      expect(porcentajeResumen(0.8), '80 %');
      expect(porcentajeResumen(null), '—');
      expect(diaCortoResumen('2026-10-12'), '12 oct');
    });
  });

  group('ajustes de la sesión', () {
    test('«Vas a estudiar N» con las definiciones de la cola, y la petición', () {
      final ps = [
        _p('ACG', [_h('anti-TPO', 1)], EstadoParrafoSrs.new_, due: true),
        _p('ACG', [_h('anti-TPO', 4)], EstadoParrafoSrs.failed, due: true),
        _p('Takayasu', [_h('anti-TPO', 2)], EstadoParrafoSrs.learning, due: false),
        _p(null, [_h('anti-TPO', 2)], EstadoParrafoSrs.learning, due: true),
      ];
      const a = AjustesResumen();
      expect(cuantosSeEstudian(ps, a), 4);
      expect(cuantosSeEstudian(ps, a.copyWith(niveles: [4])), 1);
      expect(cuantosSeEstudian(ps, a.copyWith(temas: () => ['ACG'])), 2);
      expect(cuantosSeEstudian(ps, a.copyWith(temas: () => [''])), 1, reason: "'' = sin tema");
      expect(cuantosSeEstudian(ps, a.copyWith(solo: SoloResumen.nuevo)), 1);
      expect(cuantosSeEstudian(ps, a.copyWith(solo: SoloResumen.failed)), 1);
      expect(cuantosSeEstudian(ps, a.copyWith(solo: SoloResumen.due)), 2, reason: 'pendiente = visto y fallado o vencido');
      expect(cuantosSeEstudian(ps, a.copyWith(cuantos: () => 3)), 3);
      expect(entraResumen(ps[2], a.copyWith(solo: SoloResumen.due)), isFalse);
      expect(aPeticion(a, ['ACG', 'Takayasu', '']).toJson(), isEmpty);
      expect(
        aPeticion(a.copyWith(niveles: [3, 4], temas: () => ['ACG'], solo: SoloResumen.due, cuantos: () => 10), ['ACG', 'Takayasu']).toJson(),
        {
          'levels': [3, 4],
          'topics': ['ACG'],
          'onlyStatus': 'due',
          'cardLimit': 10,
        },
      );
      expect(aPeticion(a.copyWith(temas: () => ['ACG', 'Takayasu']), ['ACG', 'Takayasu']).toJson(), isEmpty, reason: 'todos los temas = sin filtro');
    });

    test('«Solo huecos fallados» cuenta los de los niveles elegidos y va a la petición', () {
      final ps = [
        _p('A', _hs, EstadoParrafoSrs.learning, due: false, fallados: [2]),
        _p('A', _hs, EstadoParrafoSrs.failed, due: true, fallados: []),
        _p('B', _hs, EstadoParrafoSrs.learning, due: false, fallados: [0, 1]),
        _p('B', _hs, EstadoParrafoSrs.new_),
      ];
      const a = AjustesResumen(solo: SoloResumen.huecos);
      expect(cuantosSeEstudian(ps, a), 2);
      expect(cuantosSeEstudian(ps, a.copyWith(niveles: [4])), 1, reason: 'solo el que tiene fallado uno de nivel 4');
      expect(cuantosSeEstudian(ps, a.copyWith(niveles: [3])), 0);
      expect(aPeticion(a, ['A', 'B']).toJson(), {'soloHuecosFallados': true});
      expect(aPeticion(a.copyWith(niveles: [2]), ['A', 'B']).toJson(), {
        'levels': [2],
        'soloHuecosFallados': true,
      });
      expect(aPeticion(const AjustesResumen(escribir: true, anchoFijo: true), ['A']).toJson(), isEmpty, reason: 'lo de la pantalla no viaja');
      expect(repasarAhora(const AjustesEstudio(levels: [2]), [5, 5, 6]).toJson(), {
        'levels': [2],
        'soloHuecosFallados': true,
        'itemIds': [5, 6],
      });
    });

    test('lo guardado se sanea y hace ida y vuelta', () {
      final s = sanearAjustesResumen({'niveles': [9, 2, 2], 'temas': [3, 'Gota'], 'solo': 'raro', 'cuantos': 9999, 'escribir': true});
      expect(s.niveles, [2]);
      expect(s.temas, ['Gota']);
      expect((s.solo, s.cuantos, s.escribir, s.anchoFijo), (SoloResumen.todos, null, true, false));
      final ida = sanearAjustesResumen(s.copyWith(solo: SoloResumen.huecos, cuantos: () => 20).toJson());
      expect((ida.solo, ida.cuantos, ida.escribir), (SoloResumen.huecos, 20, true));
      expect(sanearAjustesResumen('basura').niveles, kNivelesResumen);
    });
  });

  group('escribir la respuesta', () {
    test('compara normalizando, sin tolerancia a erratas salvo una letra en palabras largas', () {
      const igual = [
        ['levotiroxina', 'Levotiroxina'],
        ['  LEVOTIROXINA. ', 'levotiroxina'],
        ['tiroiditis de hashimoto', 'Tiroiditis de Hashimoto'],
        ['claudicacion mandibular', 'claudicación mandibular'],
        ['40%', '40 %'],
        ['40 por ciento', '40 %'],
        ['40', '40 %'],
        ['1,6 ug/kg/dia', '1,6 µg/kg/día'],
        ['1.6 mcg/kg/día', '1,6 µg/kg/día'],
        ['1,6', '1,6 µg/kg/día'],
        ['>5 mg/dl', '> 5 mg/dL'],
        ['>= 50 años', '≥50 años'],
        ['2', 'tipo II'],
        ['tipo 2', 'Tipo II'],
        ['la biopsia de arteria temporal', 'biopsia de arteria temporal'],
        ['anti TPO', 'anti-TPO'],
      ];
      for (final x in igual) {
        expect(compararRespuesta(x[0], x[1]), Comparacion.igual, reason: '${x[0]} = ${x[1]}');
      }
      const distinta = [
        ['hipocalcemia', 'hipercalcemia'],
        ['IgM', 'IgA'],
        ['tipo 1', 'tipo II'],
        ['5', '> 5 mg/dl'],
        ['< 5', '> 5'],
        ['50', '60 años'],
        ['4', 'IgG4'],
        ['40 mg', '40 %'],
        ['metotrexato y leflunomida', 'metotrexato'],
      ];
      for (final x in distinta) {
        expect(compararRespuesta(x[0], x[1]), Comparacion.distinta, reason: '${x[0]} ≠ ${x[1]}');
      }
      expect(compararRespuesta('metotrexate', 'metotrexato'), Comparacion.casi, reason: 'una letra en palabra larga');
      expect(compararRespuesta('anti-TPA', 'anti-TPO'), Comparacion.distinta, reason: 'corta: sin tolerancia');
      expect(compararRespuesta('   ', 'algo'), Comparacion.vacia);
      expect([for (final c in Comparacion.values) propuestaSabia(c)], [true, true, false, false]);
      expect(normalizarRespuesta('El Síndrome de Sjögren'), 'sindromedesjogren');
    });
  });

  group('gestos y niveles AA', () {
    test('deslizar: derecha «Lo sabía», izquierda «No lo sabía», y lo vertical no cuenta', () {
      expect(umbralDeslizar(320), 70);
      expect(umbralDeslizar(100), 64);
      expect(umbralDeslizar(2000), 120);
      expect(respuestaDeslizar(90, 10, 340), Respuesta.sabia);
      expect(respuestaDeslizar(-90, 10, 340), Respuesta.no);
      expect(respuestaDeslizar(40, 0, 340), isNull, reason: 'corto');
      expect(respuestaDeslizar(90, 80, 340), isNull, reason: 'casi vertical: es desplazar la página');
      expect(respuestaDeslizar(double.nan, 0, 340), isNull);
    });

    test('las tintas de nivel, el verde, el rojo y el gris pasan AA (4,5:1)', () {
      expect(contraste(const Color(0xFFFFFFFF), const Color(0xFF000000)).round(), 21);
      const suaves = {1: Color(0xFFE7F0E5), 2: Color(0xFFE3EEF5), 3: Color(0xFFFBF0DA), 4: Color(0xFFFAE3E8)};
      for (final n in kNivelesResumen) {
        for (final fondo in [suaves[n]!, const Color(0xFFFFFFFF), const Color(0xFFFAF7F4)]) {
          expect(contraste(kTintaNivel[n]!, fondo), greaterThanOrEqualTo(4.5), reason: 'tinta $n');
        }
      }
      for (final c in [kVerdeOk, kRojoKo]) {
        expect(contraste(const Color(0xFFFFFFFF), c), greaterThanOrEqualTo(4.5));
      }
      for (final f in [const Color(0xFFFFFFFF), const Color(0xFFFAF7F4)]) {
        expect(contraste(kGrisAA, f), greaterThanOrEqualTo(4.5));
      }
    });

    test('lo que lee el lector de pantalla de cada hueco (tapado: nunca la respuesta)', () {
      final tapado = etiquetaHueco(EstadoHueco.tapado, 2, 'colchicina');
      expect(tapado, isNot(contains('colchicina')));
      expect(tapado, contains('nivel media'));
      expect(etiquetaHueco(EstadoHueco.tapado, 2, 'x', escribir: true), contains('escribir la respuesta'));
      expect(etiquetaHueco(EstadoHueco.destapado, 1, 'gota'), 'Destapado: gota. ¿Lo sabías?');
      expect(etiquetaHueco(EstadoHueco.sabia, 1, 'gota'), contains('gota: lo sabías. Toca para cambiarlo a «No lo sabía»'));
      expect(etiquetaHueco(EstadoHueco.no, 4, 'gota'), contains('no lo sabías. Toca para cambiarlo a «Lo sabía»'));
      expect(etiquetaHueco(EstadoHueco.visible, 3, 'gota'), contains('no se tapa en esta sesión'));
    });
  });

  group('Más y Rehacer de la vista previa', () {
    ParrafoBorrador b(String key, String tema, {String? doc, int? pagina}) => ParrafoBorrador(
          key: key,
          tema: tema,
          texto: 'Texto $key',
          huecos: const [Hueco(0, 5, 3)],
          incluir: true,
          doc: doc,
          ia: pagina == null ? null : OrigenParrafo(pagina: pagina),
        );

    test('lo nuevo entra tras el último del tema, marcado y con el documento de los del tema', () {
      final lista = [b('a', 'Gota', doc: 'h1'), b('b', 'Gota'), b('c', 'Lupus')];
      final r = insertarNuevos(lista, '', 'Gota', [b('x', 'Otro'), b('y', 'Otro')], 's');
      expect(r.lista.map((p) => p.key).toList(), ['a', 'b', 'ms-0', 'ms-1', 'c']);
      expect(r.primera, 'ms-0');
      expect(r.lista[2].tema, 'Gota');
      expect((r.lista[2].nuevo, r.lista[2].doc), (true, 'h1'));
      expect(insertarNuevos(lista, '', 'Gota', const [], 's').lista, same(lista));
      expect(vecinosDeTema(lista, '', 'Gota'), ['Lupus']);
      expect(parrafosDeTema(lista, '', 'Gota').length, 2);
      expect(nivelesDeLista(lista), [3]);
      expect(nivelesDeOpcion(OpcionMas.dificiles, [1, 2]), [3, 4]);
      expect(nivelesDeOpcion(OpcionMas.todo, [1, 2]), [1, 2]);
    });

    test('rehacer en su sitio y deshacer', () {
      final lista = [b('a', 'Gota'), b('b', 'Gota')];
      const nuevo = ParrafoBorrador(key: 'r', tema: 'X', texto: 'Otra versión', huecos: [Hueco(0, 4, 2)], incluir: true);
      final r = rehacerEnSitio(lista, 'b', nuevo);
      expect((r[1].key, r[1].tema, r[1].texto), ('b', 'Gota', 'Otra versión'));
      final d = deshacerEnSitio(r, 'b', lista[1]);
      expect(d[1].texto, 'Texto b');
      expect(textoMas(3, 0), '+3 nuevos');
      expect(textoMas(1, 1), '+1 nuevo · 1 quitado por repetir uno que ya tenías');
      expect(textoMas(5, 2), '+5 nuevos · 2 quitados por repetir uno que ya tenías');
    });

    test('el fragmento: sus páginas con margen; si no hay páginas, el documento si cabe', () {
      final secciones = [for (var p = 1; p <= 10; p++) Seccion(texto: 'pág $p', pagina: p)];
      final f = fragmentoDeParrafo(secciones, b('a', 'Gota', pagina: 5), const []);
      expect(f.map((s) => s.pagina).toList(), [4, 5, 6]);
      expect(paginasDeFragmento(f), 3);
      expect(fragmentoDeTema(secciones, 'Gota', [b('a', 'Gota')]).length, 10, reason: 'sin páginas y cabe: todo');
    });
  });
}
