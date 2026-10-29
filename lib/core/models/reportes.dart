// Reportar una pregunta: tipos de error, contexto y el cuerpo de POST /api/reports.
// Puerto de la web: src/lib/reports/categories.ts y src/lib/reports/api.ts.
//
// Las categorías y los orígenes tienen que coincidir con src/utils/reportes.js del backend (y con el
// CHECK de content_reports): si aquí se manda algo que la tabla no acepta, el usuario vería un 400.
// La foto de la pregunta la saca el servidor de la BD, así que el reporte nunca lleva la clave.

/// Tipo de error. [needsAnswer]: solo tiene sentido después de responder (antes destriparía).
class CategoriaReporte {
  final String key;
  final String label;

  /// Nombre del Material Symbol de la web; la vista lo traduce a `IconData`.
  final String icon;

  /// Pregunta del campo de texto (en «otro» es obligatorio).
  final String prompt;
  final bool needsAnswer;

  const CategoriaReporte(this.key, this.label, this.icon, this.prompt, {this.needsAnswer = false});
}

const categoriasPregunta = <CategoriaReporte>[
  CategoriaReporte('respuesta_erronea', 'Respuesta correcta errónea', 'rule',
      '¿Por qué? Si tienes una fuente, mejor.', needsAnswer: true),
  CategoriaReporte('explicacion', 'Explicación incorrecta o incompleta', 'menu_book',
      '¿Qué falla o qué falta?', needsAnswer: true),
  CategoriaReporte('errata', 'Errata en enunciado u opciones', 'spellcheck', '¿Qué pone y qué debería poner?'),
  CategoriaReporte('imagen', 'Problema con la imagen', 'hide_image', '¿Algo más que debamos saber?'),
  CategoriaReporte('desactualizada', 'Desactualizada', 'update', '¿Qué ha cambiado? (guía, año…)'),
  CategoriaReporte('duplicada', 'Duplicada', 'content_copy', '¿Con cuál? (año y número si lo sabes)'),
  CategoriaReporte('otro', 'Otro', 'more_horiz', 'Cuéntanos qué pasa'),
];

/// Los de una guía de estudio (la web: GUIDE_CATEGORIES). Sin imagen ni duplicada; con «Dato incorrecto».
const categoriasGuia = <CategoriaReporte>[
  CategoriaReporte('dato_incorrecto', 'Dato incorrecto', 'error', '¿Qué dato y dónde?'),
  CategoriaReporte('respuesta_erronea', 'Respuesta correcta errónea', 'rule',
      '¿Por qué? Si tienes una fuente, mejor.', needsAnswer: true),
  CategoriaReporte('errata', 'Errata en enunciado u opciones', 'spellcheck', '¿Qué pone y qué debería poner?'),
  CategoriaReporte('desactualizada', 'Desactualizada', 'update', '¿Qué ha cambiado? (guía, año…)'),
  CategoriaReporte('otro', 'Otro', 'more_horiz', 'Cuéntanos qué pasa'),
];

const subcategoriasImagen = <({String key, String label})>[
  (key: 'no_carga', label: 'No carga'),
  (key: 'no_corresponde', label: 'No corresponde'),
  (key: 'no_se_ve', label: 'No se ve bien'),
];

const maxMensajeReporte = 1000;

/// Etiqueta de una categoría (la del servidor si no se conoce).
String etiquetaCategoria(String key) {
  for (final c in [...categoriasPregunta, ...categoriasGuia]) {
    if (c.key == key) return c.label;
  }
  return key;
}

/// De dónde se reporta. Mismos valores que `ORIGENES` del backend.
enum OrigenReporte {
  daily('daily'),
  dailyReview('daily_review'),
  simulacro('simulacro'),
  simulacroReview('simulacro_review'),
  deck('deck'),
  versus('versus'),
  guide('guide');

  final String valor;
  const OrigenReporte(this.valor);
}

/// Lo que adjunta el sistema: de dónde viene, si ya había respondido y qué.
class ContextoReporte {
  final OrigenReporte origin;
  final String? sessionRef;
  final bool answered;

  /// Opción elegida, **1-based** (como la web). Solo cuenta si [answered].
  final int? userAnswer;
  final bool? isCorrect;

  const ContextoReporte({
    required this.origin,
    this.sessionRef,
    required this.answered,
    this.userAnswer,
    this.isCorrect,
  });
}

/// `q:<id>`, la clave con la que el servidor agrupa los reportes de una pregunta.
String claveContenido(int questionId) => 'q:$questionId';

/// `g:<guía>/<ref>` («g:reumatologia/q12»), la de un trozo de una guía de estudio.
String claveGuia(String guideRef) => 'g:$guideRef';

/// Antes de responder se ocultan las categorías que lo exigen.
List<CategoriaReporte> categoriasVisibles({required bool answered, bool guia = false}) {
  final todas = guia ? categoriasGuia : categoriasPregunta;
  return answered ? todas : todas.where((c) => !c.needsAnswer).toList();
}

/// «Otro» obliga a escribir; el resto, no.
bool puedeEnviarReporte({required String? categoria, required String mensaje, bool enviando = false}) =>
    categoria != null && !enviando && (categoria != 'otro' || mensaje.trim().isNotEmpty);

/// Cuerpo de POST /api/reports, campo a campo como `submitReport` de la web, con `platform: 'app'`.
/// Con [guideRef] es el reporte de una guía: la foto ([snapshot]) la manda el cliente, porque la guía no
/// está en la base de datos.
Map<String, dynamic> cuerpoReporte({
  int? questionId,
  String? guideRef,
  Map<String, dynamic>? snapshot,
  required ContextoReporte contexto,
  required String categoria,
  String? subcategoria,
  int? sugerida,
  String mensaje = '',
  String? appVersion,
  String? userAgent,
}) =>
    {
      'contentType': guideRef != null ? 'guide' : 'question',
      if (guideRef == null) 'questionId': questionId,
      if (guideRef != null) 'guideRef': guideRef,
      if (guideRef != null) 'snapshot': snapshot ?? const <String, dynamic>{},
      'category': categoria,
      'subcategory': categoria == 'imagen' ? subcategoria : null,
      'suggestedAnswer': categoria == 'respuesta_erronea' ? sugerida : null,
      'message': mensaje.trim(),
      'origin': contexto.origin.valor,
      'sessionRef': contexto.sessionRef,
      'answered': contexto.answered,
      'userAnswer': contexto.answered ? contexto.userAnswer : null,
      'isCorrect': contexto.answered ? contexto.isCorrect : null,
      'platform': 'app',
      'appVersion': appVersion,
      'userAgent': userAgent,
    };

/// Un reporte abierto del propio usuario (GET /api/reports/mine), para precargarlo y editarlo.
class MiReporte {
  final String category;
  final String? subcategory;
  final int? suggestedAnswer;
  final String? message;

  const MiReporte({required this.category, this.subcategory, this.suggestedAnswer, this.message});

  factory MiReporte.fromJson(Map<String, dynamic> j) => MiReporte(
        category: '${j['category'] ?? ''}',
        subcategory: j['subcategory'] is String ? j['subcategory'] as String : null,
        suggestedAnswer: j['suggested_answer'] is num ? (j['suggested_answer'] as num).toInt() : null,
        message: j['message'] is String ? j['message'] as String : null,
      );
}

/// «Ya lo reportaste (errata, duplicada). Puedes corregir tu reporte o añadir otro tipo.»
String textoYaReportado(List<MiReporte> mios) =>
    'Ya lo reportaste (${mios.map((r) => etiquetaCategoria(r.category).toLowerCase()).join(', ')}). '
    'Puedes corregir tu reporte o añadir otro tipo.';

/// Opción elegida en la app (0-based, -1 o null = en blanco) → la 1-based que espera el servidor.
int? respuestaUnoBased(int? indice) => indice == null || indice < 0 ? null : indice + 1;
