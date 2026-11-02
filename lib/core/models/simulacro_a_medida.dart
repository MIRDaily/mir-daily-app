// «Simulacro a tu medida» (POST /api/simulacro/smart): 30 preguntas de donde peor vas, que arma el
// servidor. Puerto de src/lib/simulacro/types.ts (SmartSimulacroPlan), de SmartSimulacroModal.tsx y de
// `buildFeaturedCard` / `weakTopic` de src/app/studio/page.tsx.
//
// Son 30 a propósito: dan XP por pregunta pero no entran al historial (hace falta >= 50).

import 'models.dart' show SimQuestion;
import 'progress.dart' show Challenge;

/// `topics`: todas salieron de temas flojos · `mixed`: se completó con asignaturas flojas ·
/// `insufficient`: aún no hay señal de fallos suficiente (el servidor manda la lista vacía).
enum CoberturaAMedida { topics, mixed, insufficient }

class PlanAMedida {
  final List<SimQuestion> questions;

  /// Preguntas por asignatura de la propia tanda, de más a menos.
  final List<({String subjectName, int count})> composition;
  final CoberturaAMedida coverage;

  const PlanAMedida({required this.questions, required this.composition, required this.coverage});

  factory PlanAMedida.fromJson(Map<String, dynamic> j) {
    final qs = j['questions'] is List
        ? (j['questions'] as List).whereType<Map>().map((e) => SimQuestion.fromJson(Map<String, dynamic>.from(e))).toList()
        : <SimQuestion>[];
    final comp = j['composition'] is List
        ? (j['composition'] as List)
            .whereType<Map>()
            .map((m) => (
                  subjectName: '${m['subjectName'] ?? ''}',
                  count: m['count'] is num ? (m['count'] as num).round() : 0,
                ))
            .toList()
        : <({String subjectName, int count})>[];
    final cov = switch (j['coverage']) {
      'topics' => CoberturaAMedida.topics,
      'mixed' => CoberturaAMedida.mixed,
      _ => CoberturaAMedida.insufficient,
    };
    return PlanAMedida(questions: qs, composition: comp, coverage: cov);
  }

  /// Como la web: sin señal suficiente, o sin preguntas, no se ofrece empezar.
  bool get insuficiente => coverage == CoberturaAMedida.insufficient || questions.isEmpty;
}

/// El tema más flojo del usuario, del desafío personalizado de hoy (`weak_topic_questions`): la misma
/// fuente que usa la web en Studio y el Perfil, así que no hace falta otra petición.
class PuntoDebil {
  final String tema;
  final String asignatura;
  final double? precision;

  const PuntoDebil({required this.tema, required this.asignatura, this.precision});
}

PuntoDebil? puntoDebilDe(List<Challenge> diarios) {
  for (final c in diarios) {
    if (c.metric != 'weak_topic_questions') continue;
    final m = c.meta;
    final tema = m?['topic_name'];
    if (tema is! String || tema.isEmpty) return null;
    return PuntoDebil(
      tema: tema,
      asignatura: m?['subject_name'] is String ? m!['subject_name'] as String : '',
      precision: m?['accuracy'] is num ? (m!['accuracy'] as num).toDouble() : null,
    );
  }
  return null;
}

/// Texto de la tarjeta de Studio, el mismo que la web.
// Corta a propósito: en el móvil la tarjeta va arriba del todo en Studio (prueba en el teléfono,
// 02/11/2026: la frase larga la hacía demasiado alta).
String descripcionAMedida(PuntoDebil? p) => p == null
    ? 'Cuando haya datos de tus fallos, aquí tendrás una sesión centrada en ellos.'
    : '30 preguntas de ${p.tema}${p.asignatura.isEmpty ? '' : ' (${p.asignatura})'}, donde más fallas ahora.';
