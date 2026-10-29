import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/models/analytics.dart';
import '../../../core/models/biblioteca.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/carpetas.dart';

/// Lo que enseñan una asignatura y sus carpetas. Puerto de useDatosAsignatura.ts de la web:
///  - el material y las preguntas MIR por tema (GET /api/carpetas/asignatura/:id);
///  - aparte, el acierto en esas preguntas (/api/analytics, ventana «todo»). Si falla, se enseña lo
///    demás sin acierto;
///  - la señal de dominio del material, en su propia petición. Si falla o la base de datos aún no la
///    calcula, «no disponible».
class CargaAsignatura {
  final int subjectId;
  CargaAsignatura(this.subjectId);

  DatosAsignatura? datos;
  String? error;
  bool noExiste = false;

  /// null mientras llega.
  RespuestaDominio? dominio;
  Map<int, TopicHeatmapCell> _temas = const {};
  SubjectHeatmapCell? _asig;

  Future<void> cargar(BuildContext context, VoidCallback alCambiar) async {
    final carpetas = context.read<CarpetasApi>();
    final api = context.read<ApiService>();
    await Future.wait([
      () async {
        try {
          datos = await carpetas.asignatura(subjectId);
          error = null;
          noExiste = false;
        } catch (e) {
          final m = '$e'.replaceFirst('Exception: ', '');
          error = m;
          noExiste = RegExp('no existe|no válida', caseSensitive: false).hasMatch(m);
        }
        alCambiar();
      }(),
      () async {
        try {
          dominio = await carpetas.dominio(subjectId);
        } catch (_) {
          dominio = RespuestaDominio.noDisponible;
        }
        alCambiar();
      }(),
      () async {
        try {
          final r = await Future.wait([
            api.getTopicHeatmap(subjectId, AnalyticsWindow.all, AnalyticsMode.all),
            api.getSubjectHeatmap(AnalyticsWindow.all, AnalyticsMode.all),
          ]);
          _temas = {for (final t in (r[0] as TopicHeatmapResponse).topics) t.topicId: t};
          _asig = (r[1] as SubjectHeatmapResponse).subjects.where((s) => s.subjectId == subjectId).firstOrNull;
          alCambiar();
        } catch (_) {}
      }(),
    ]);
  }

  /// Acierto en las preguntas de un tema, o de toda la asignatura con `topicId` null («General»).
  ({double? acierto, int respondidas}) aciertoDe(int? topicId) {
    final total = topicId == null ? _asig?.total : _temas[topicId]?.total;
    final acierto = topicId == null ? _asig?.accuracy : _temas[topicId]?.accuracy;
    return (acierto: acierto, respondidas: total ?? 0);
  }

  /// Bien, mal y en blanco de un tema (o de la asignatura), para el detalle de la carpeta.
  ({int bien, int mal, int blanco, int total})? detalleDe(int? topicId) {
    if (topicId == null) {
      final a = _asig;
      return a == null ? null : (bien: a.correct, mal: a.wrong, blanco: a.blank, total: a.total);
    }
    final t = _temas[topicId];
    return t == null ? null : (bien: t.correct, mal: t.wrong, blanco: t.blank, total: t.total);
  }

  /// null mientras llega; false si la base de datos todavía no calcula la señal.
  bool? get dominioDisponible => dominio?.disponible;
}
