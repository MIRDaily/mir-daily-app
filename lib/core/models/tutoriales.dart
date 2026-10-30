// Los tutoriales de la mascota, como datos. Puerto de la web: src/lib/tutorials/types.ts y scripts.ts.
//
// Las CLAVES son las de la web a propósito («daily.v2», «studio.v3», «resumenes.v1»): lo visto se
// guarda en la cuenta (users.tutorials_seen), así que un tutorial visto en la web no vuelve a salir en
// la app, y al revés. Lo que dice la mascota sí cambia donde la app es distinta (lo avisa types.ts:
// «la app de Flutter consume este mismo formato aunque su contenido sea otro»):
//  - El daily de la app es el sobre a pantalla completa: no tiene la «más fallada» debajo (en la app
//    vive en el Panel), ni el bloque de la app móvil (dentro de la app no se recomienda la app).
//  - La barra está abajo (o a un lado en tablet), no arriba; y se reactivan desde el Perfil, no desde
//    Configuración.
//  - El Studio de la app no tiene Sala Zen (llega con la tanda 15): ese paso no está.
//  - mapas.v1 no está porque la app aún no tiene mapas (tanda 12).
//
// Aquí no hay Flutter: es lo que se prueba sin pantallas.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// Poses de la mascota. Cada una es un PNG de assets/mascota/, copiado tal cual de la web
/// (public/img/mascota): todos con la cabeza del mismo ancho y las patas sobre la misma línea, así que
/// la mascota no salta al cambiar de pose.
enum PoseMascota {
  saludo('saludo'),
  senalando('senalando'),
  hablando('hablando'),
  despedida('despedida'),
  senalandoAbajo('senalando-abajo'),
  celebracion('celebracion'),
  hablandoVariante2('hablando-variante2'),
  confiado('confiado'),
  dudando('dudando'),
  haciendoExamen('haciendo-examen'),
  conMazo('con-mazo');

  final String fichero;
  const PoseMascota(this.fichero);

  String get asset => 'assets/mascota/$fichero.png';
}

/// Dónde va un paso: junto a su ancla (si está en pantalla) o centrado.
enum ColocacionPaso { auto, centro }

class PasoTutorial {
  /// La ancla a iluminar (un `TutorialAncla` de la pantalla). Si no hay —o no está montada— el paso
  /// sale centrado en vez de romperse, como en la web.
  final String? ancla;
  final PoseMascota pose;
  final String texto;
  final ColocacionPaso colocacion;

  const PasoTutorial({
    this.ancla,
    required this.pose,
    required this.texto,
    this.colocacion = ColocacionPaso.auto,
  });

  /// La ancla que de verdad se busca: un paso centrado no ilumina nada aunque la tenga.
  String? get anclaEfectiva => colocacion == ColocacionPaso.centro ? null : ancla;
}

class Tutorial {
  /// «pantalla.vN». Subir la versión vuelve a enseñarlo a quien ya lo vio.
  final String id;
  final List<PasoTutorial> pasos;

  /// La despedida, aparte (en la web, entre los dos va el aviso de la app móvil, que aquí no sale).
  final List<PasoTutorial> cierre;

  const Tutorial({required this.id, required this.pasos, this.cierre = const []});
}

/// El formato de clave que acepta el backend (TUTORIAL_KEY_REGEX en src/routes/profile.js).
final RegExp formatoClaveTutorial = RegExp(r'^[a-z0-9-]{2,40}\.v[0-9]{1,3}$');

// Anclas. Las mismas palabras que los `data-tutorial` de la web, para poder seguirlas de un lado a otro.
const String anclaDailySobre = 'daily-sobre';
const String anclaNavPestanas = 'nav-pestanas';
const String anclaStudioSimulacro = 'studio-simulacro';
const String anclaStudioSimulacros = 'studio-preguntas-simulacros';
const String anclaStudioMazos = 'studio-mazos';
const String anclaStudioFlashcards = 'studio-flashcards';
const String anclaResumenesZona = 'resumenes-zona';
const String anclaResumenesNuevo = 'resumenes-nuevo';

const Tutorial tutorialDaily = Tutorial(
  id: 'daily.v2',
  pasos: [
    PasoTutorial(
      pose: PoseMascota.saludo,
      colocacion: ColocacionPaso.centro,
      texto: '¡Hola! Soy tu compi de estudio. Deja que te enseñe esto en diez segundos.',
    ),
    PasoTutorial(
      ancla: anclaDailySobre,
      pose: PoseMascota.senalando,
      texto: 'Este es tu sobre de hoy: cinco preguntas nuevas, una vez al día. Ábrelo y ya está.',
    ),
  ],
  cierre: [
    PasoTutorial(
      ancla: anclaNavPestanas,
      pose: PoseMascota.senalando,
      texto: 'En la barra está todo lo demás. Según vayas entrando en cada pestaña, te la voy explicando.',
    ),
    PasoTutorial(
      pose: PoseMascota.despedida,
      colocacion: ColocacionPaso.centro,
      texto:
          'Y sin agobios: nadie se lo sabe todo el primer día. Si quieres volver a verme, enciéndeme en tu Perfil, en Preferencias.',
    ),
  ],
);

const Tutorial tutorialStudio = Tutorial(
  id: 'studio.v3',
  // Sin cierre: la despedida ya la dio el daily.
  pasos: [
    PasoTutorial(
      pose: PoseMascota.saludo,
      colocacion: ColocacionPaso.centro,
      texto: 'Esto es el Studio. Aquí eliges tú qué estudiar, sin esperar al sobre del día.',
    ),
    PasoTutorial(
      ancla: anclaStudioSimulacro,
      pose: PoseMascota.haciendoExamen,
      texto: 'Este simulacro se monta solo: 30 preguntas de aquello que peor llevas.',
    ),
    PasoTutorial(
      ancla: anclaStudioSimulacros,
      pose: PoseMascota.confiado,
      texto: 'Aquí los montas tú: por asignatura, por tema, o un test rápido si solo tienes cinco minutos.',
    ),
    // Tres bocadillos sobre la misma tarjeta: qué es, cómo funciona y para qué sirve. Solo el primero
    // señala; los otros rotan de pose para que la mascota no se quede clavada.
    PasoTutorial(
      ancla: anclaStudioMazos,
      pose: PoseMascota.senalando,
      texto:
          'Un mazo lo armas tú: cuando una pregunta te cueste, la guardas ahí desde el Daily o desde un simulacro.',
    ),
    PasoTutorial(
      ancla: anclaStudioMazos,
      pose: PoseMascota.conMazo,
      texto: 'Y al estudiarlo, cada pregunta te vuelve a salir justo antes de que se te olvide.',
    ),
    PasoTutorial(
      ancla: anclaStudioMazos,
      pose: PoseMascota.hablandoVariante2,
      texto: 'Así dejas de repasar mil veces lo que ya te sabes y le das el tiempo a lo que se te resiste.',
    ),
    PasoTutorial(
      ancla: anclaStudioFlashcards,
      pose: PoseMascota.senalando,
      texto: 'Y si te lo escribes tú, flashcards: van bien para fármacos, dosis y criterios.',
    ),
  ],
);

const Tutorial tutorialResumenes = Tutorial(
  id: 'resumenes.v1',
  pasos: [
    PasoTutorial(
      pose: PoseMascota.saludo,
      colocacion: ColocacionPaso.centro,
      texto: 'Esto son los resúmenes activos: tus apuntes, con los datos clave tapados.',
    ),
    PasoTutorial(
      ancla: anclaResumenesZona,
      pose: PoseMascota.senalando,
      texto: 'Lees, intentas recordar lo tapado y lo destapas. Luego dices si lo sabías, con un botón o deslizando.',
    ),
    PasoTutorial(
      ancla: anclaResumenesNuevo,
      pose: PoseMascota.confiado,
      texto: 'Para hacer los tuyos, crea un grupo y escribe: tocando una palabra, la tapas.',
    ),
    PasoTutorial(
      pose: PoseMascota.hablandoVariante2,
      colocacion: ColocacionPaso.centro,
      texto:
          'Cada repaso los reprograma, y vuelven justo antes de que se te olviden. Lo que toque hoy te lo aviso en el Studio.',
    ),
  ],
);

/// Los tutoriales que tiene la app, por clave.
final Map<String, Tutorial> tutorialesApp = {
  for (final t in [tutorialDaily, tutorialStudio, tutorialResumenes]) t.id: t,
};

/// El guion completo de un tutorial: los pasos y después la despedida.
List<PasoTutorial> armarGuion(Tutorial t) => [...t.pasos, ...t.cierre];

/// Lo visto, de todas las fuentes: el servidor manda, la caché local evita que un fallo de red repita
/// el mismo tutorial en bucle, y lo marcado en esta sesión cubre el rato hasta que el perfil se refresca.
Set<String> unirVistos(Iterable<String> servidor, Iterable<String> local, Iterable<String> ahora) =>
    {...servidor, ...local, ...ahora};

/// Qué tutorial toca arrancar ahora, o null. Las reglas del TutorialProvider de la web:
/// uno cada vez, nunca a la vez que una celebración, solo si la pantalla dijo que está lista, solo con
/// sesión, solo si están encendidos y solo si no se ha visto ya.
String? tutorialQueToca({
  required String? candidato,
  required String? enCurso,
  required bool conSesion,
  required bool activos,
  required bool celebrando,
  required Set<String> vistos,
  Map<String, Tutorial>? catalogo,
}) {
  if (enCurso != null || candidato == null || !conSesion || !activos || celebrando) return null;
  if (vistos.contains(candidato)) return null;
  if (!(catalogo ?? tutorialesApp).containsKey(candidato)) return null;
  return candidato;
}

/// Cómo se dibuja el bocadillo: en fila (mascota al lado) o apilado (mascota encima, en móvil).
bool bocadilloEnFila(double anchoPantalla) => anchoPantalla >= 600;

/// Dónde cae el bocadillo (su esquina de arriba a la izquierda) respecto al foco. Puerto de la cuenta
/// de TutorialOverlay.tsx, con una diferencia: aquí se conoce el tamaño REAL del bocadillo (lo mide
/// el layout), así que no hace falta el alto estimado de 260 px de la web.
///
/// Tres colocaciones: debajo del foco, encima si debajo no cabe, y pegado al fondo (encima de la barra
/// de los puntos y «Saltar») cuando no cabe en ninguno — lo normal en móvil con el sobre, que ocupa
/// casi toda la pantalla. Sin foco, centrado.
Offset colocarBocadillo({
  required Size pantalla,
  required Size bocadillo,
  required Rect? foco,
  double margenArriba = 0,
  double altoBarra = 72,
  double hueco = 24,
  double borde = 16,
}) {
  if (foco == null) {
    return Offset(
      math.max((pantalla.width - bocadillo.width) / 2, 0),
      math.max((pantalla.height - bocadillo.height) / 2, 0),
    );
  }
  final espacioDebajo = pantalla.height - altoBarra - foco.bottom;
  final espacioEncima = foco.top - margenArriba;
  final double top;
  if (espacioDebajo >= bocadillo.height + hueco) {
    top = foco.bottom + hueco;
  } else if (espacioEncima >= bocadillo.height + hueco) {
    top = foco.top - hueco - bocadillo.height;
  } else {
    top = pantalla.height - altoBarra - bocadillo.height;
  }
  final maxIzquierda = math.max(pantalla.width - bocadillo.width - borde, borde);
  final left = (foco.center.dx - bocadillo.width / 2).clamp(borde, maxIzquierda);
  return Offset(left.toDouble(), math.max(top, margenArriba));
}

/// La mascota mira a la izquierda cuando el foco cae en el tercio derecho de la pantalla.
bool mascotaMiraIzquierda(Rect? foco, double anchoPantalla) =>
    foco != null && foco.center.dx > anchoPantalla * 0.6;

/// El rectángulo que engloba a todos los de una misma ancla (en la web, el sobre y su botón son
/// hermanos y se iluminan juntos). Los vacíos no cuentan: un elemento oculto mide cero y arrastraría
/// el foco a la esquina.
Rect? unirRectangulos(Iterable<Rect> rects) {
  Rect? u;
  for (final r in rects) {
    if (r.width <= 0 || r.height <= 0) continue;
    u = u == null ? r : u.expandToInclude(r);
  }
  return u;
}

/// La máquina de escribir: cada toque mientras escribe divide el retardo por 4, con un suelo de 4 ms
/// (por debajo el texto ya sale de golpe y no se lee el avance). Mismos números que MascotBubble.tsx.
const int msPorCaracter = 28;
const int factorAceleracion = 4;
const int msMinimo = 4;

int retardoAcelerado(int retardoMs) => math.max(msMinimo, retardoMs ~/ factorAceleracion);
