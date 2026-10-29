// Tanda 7b: guías de estudio. Las cifras de cada tema salen IGUAL que en la web: se comparan con
// test/fixtures/guias_stats_web.json, que se generó ejecutando el stats.ts real de la web sobre los mismos
// assets/guides/*.json (ver el resultado de la tanda 7b en el plan). Y el gráfico esfuerzo/recompensa
// coloca los nombres dentro y sin pisarse.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirdaily_app/core/models/guia_esfuerzo.dart';
import 'package:mirdaily_app/core/models/guias.dart';

final indice = IndiceGuias.fromJson(jsonDecode(File('assets/guides/index.json').readAsStringSync()) as Map<String, dynamic>);
StudyGuide guia(String clave) =>
    StudyGuide.fromJson(jsonDecode(File('assets/guides/$clave.json').readAsStringSync()) as Map<String, dynamic>);
final esperadas = jsonDecode(File('test/fixtures/guias_stats_web.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('el índice: 7 guías, cada una con su asignatura del catálogo', () {
    expect(indice.guias.length, 7);
    expect(indice.deAsignatura(3080)!.clave, 'reumatologia');
    expect(indice.deAsignatura(1425)!.clave, 'dermatologia');
    expect(indice.deAsignatura(2), isNull);
    expect(indice.origen, startsWith('mir-daily-frontend'));
  });

  for (final g in indice.guias) {
    test('${g.clave}: las cifras de cada tema son las de stats.ts de la web', () {
      final gu = guia(g.clave);
      final esperada = esperadas[g.clave] as Map<String, dynamic>;
      expect(gu.subjectId, g.clave);
      expect([for (final p in subjectPerYear(gu)) {'year': p.year, 'count': p.count}], esperada['perYear']);
      final temas = withStats(gu.topics);
      final web = (esperada['temas'] as List).cast<Map<String, dynamic>>();
      expect(temas.map((t) => t.id), web.map((t) => t['id']));
      for (var i = 0; i < temas.length; i++) {
        final s = temas[i].stats;
        final w = web[i]['stats'] as Map<String, dynamic>;
        final id = temas[i].id;
        expect(temas[i].perYear, web[i]['perYear'], reason: '$id perYear (con reservas)');
        expect(s.historyCount, w['historyCount'], reason: '$id historyCount');
        expect(s.lastExamCount, w['lastExamCount'], reason: '$id lastExamCount');
        expect(s.totalCount, w['totalCount'], reason: '$id totalCount');
        expect(s.recentCount, w['recentCount'], reason: '$id recentCount');
        expect(s.recentAvg, closeTo((w['recentAvg'] as num).toDouble(), 1e-9), reason: '$id recentAvg');
        expect(s.earlierAvg, closeTo((w['earlierAvg'] as num).toDouble(), 1e-9), reason: '$id earlierAvg');
        expect(s.recentHits, w['recentHits'], reason: '$id recentHits');
        expect(s.trend.name, w['trend'], reason: '$id trend');
        expect(s.forecast, closeTo((w['forecast'] as num).toDouble(), 1e-9), reason: '$id forecast');
        expect(formatForecast(s.forecast), web[i]['forecastTexto'], reason: '$id forecast en texto');
      }
    });

    test('${g.clave}: esfuerzo/recompensa con los nombres dentro del gráfico', () {
      final d = disenoEsfuerzo(withStats(guia(g.clave).topics));
      expect(d.puntos.length, guia(g.clave).topics.length);
      for (final p in d.puntos) {
        expect(p.cx, inInclusiveRange(esfuerzoPad.left, esfuerzoAncho - esfuerzoPad.right + 1), reason: p.tema.id);
        expect(p.cy, inInclusiveRange(esfuerzoPad.top, esfuerzoAlto - esfuerzoPad.bottom), reason: p.tema.id);
      }
      // Los nombres que se ven en reposo no se pisan entre sí (la búsqueda lo consigue en las 7 guías).
      final cajas = [for (final p in d.puntos.where((p) => p.mayor)) cajaEtiqueta(p.cx, p.cy, p.etiqueta, p.tema.shortName)];
      for (var i = 0; i < cajas.length; i++) {
        for (var j = i + 1; j < cajas.length; j++) {
          expect(cajas[i].pisa(cajas[j]), isFalse, reason: 'se pisan dos nombres en ${g.clave}');
        }
      }
    });
  }

  test('formatForecast y formatAvg como la web', () {
    expect(formatForecast(0.04), '0');
    expect(formatForecast(0.6), '≈0,6');
    expect(formatForecast(0.94), '≈0,9');
    expect(formatForecast(0.96), '≈1');
    expect(formatForecast(3.4), '≈3');
    expect(formatAvg(4.5), '4,5');
    expect(formatAvg(12), '12');
    expect(formatAvg(2.25), '2,3');
  });

  test('tendencia con el umbral doble: sin ruido en temas de 0-1 preguntas', () {
    expect(computeTopicStats([0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1]).trend, GuideTrend.sube);
    expect(computeTopicStats([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]).trend, GuideTrend.estable, reason: '0,2 de diferencia es ruido');
    expect(computeTopicStats([3, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1]).trend, GuideTrend.baja);
    final s = computeTopicStats([1, 0, 2, 0, 1, 0, 1, 2, 0, 3, 1, 2]);
    expect(s.historyCount, 11);
    expect(s.lastExamCount, 2);
    expect(s.recentHits, 4);
  });

  test('orden de los temas: previsión, histórico y tendencia (lo que sube primero)', () {
    final temas = withStats(guia('urologia').topics);
    final prev = sortGuideTopics(temas, GuideSortKey.prevision);
    for (var i = 1; i < prev.length; i++) {
      expect(prev[i - 1].stats.forecast >= prev[i].stats.forecast, isTrue);
    }
    final hist = sortGuideTopics(temas, GuideSortKey.historico);
    for (var i = 1; i < hist.length; i++) {
      expect(hist[i - 1].stats.totalCount >= hist[i].stats.totalCount, isTrue);
    }
    final tend = sortGuideTopics(temas, GuideSortKey.tendencia).map((t) => t.stats.trend.index).toList();
    expect(tend, [...tend]..sort());
  });

  test('el resumen de la página (Urología)', () {
    final r = ResumenGuia.de(guia('urologia'));
    expect(r.years.first, 2015);
    expect(r.lastYear, 2026);
    expect(r.lastExamCount, 8); // 7 + 1 de reserva
    expect(r.average, closeTo(57 / 11, 1e-9));
    expect(r.periodLabel, '2015–2026');
    expect(r.earlierLabel, '2015–2021');
    expect(r.recentLabel, '2022–2026');
    expect(r.topThree.length, 3);
    expect(r.topThreeShare, inInclusiveRange(1, 100));
    expect(r.planDays, greaterThan(0));
    expect(refGuia('urologia', 12), 'urologia/q12');
    expect(refGuia('urologia'), 'urologia/general');
  });
}
