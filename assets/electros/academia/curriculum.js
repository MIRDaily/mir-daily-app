/* ════════════════════════════════════════════════════════════════════════
   MIRElectro Academia — curriculum.js
   Ruta de aprendizaje. Cada módulo agrupa pasos; cada paso tiene un `type`
   que academia.js sabe renderizar como una tarjeta interactiva.

   Tipos de paso:
     info        texto + ilustración (onda o icono)
     conduction  animación impulso ↔ ECG (con reproducción y barra de avance)
     hotspot     tocar la zona correcta de una escena ('heart' | 'waves')
     choice      pregunta de opción múltiple con explicación
     caliper     medir un intervalo con el compás
     rate        calcular la frecuencia con la regla de los cuadros grandes
     axis        rotar el eje eléctrico y leer I / aVF
     reveal      desplegar una lista (aprendizaje por descubrimiento)
     summary     cierre del módulo
═══════════════════════════════════════════════════════════════════════════ */

export const MODULES = [
  /* ─── MÓDULO 0 ──────────────────────────────────────────────────────── */
  {
    id: 'm0', icon: 'bolt', color: '#D4978C',
    title: 'El corazón eléctrico',
    subtitle: 'La mecánica que hay detrás del trazo',
    steps: [
      {
        type: 'info', kicker: 'Idea base', title: 'El corazón es una bomba eléctrica',
        visual: 'heart-static',
        body: 'Antes de cada latido mecánico hay un latido eléctrico. El ECG no dibuja el bombeo: dibuja la onda de electricidad que lo ordena. Aprender a leerlo es aprender a seguir esa onda.',
        points: ['La electricidad va SIEMPRE por delante de la contracción', 'El ECG registra esa actividad desde la piel'],
      },
      {
        type: 'conduction', kicker: 'Obsérvalo latir', title: 'El viaje del impulso',
        focus: 'struct',
        body: 'Pulsa play y sigue el impulso: nace en el nodo sinusal, recorre las aurículas, se frena en el nodo AV y baja como un rayo por el His-Purkinje. Usa la barra para ir a tu ritmo.',
      },
      {
        type: 'hotspot', kicker: 'Tú lo diriges', title: '¿Dónde nace el impulso normal?',
        scene: 'heart', target: 'sa',
        prompt: 'Toca la estructura donde se origina el latido en un corazón sano.',
        ok: '¡Exacto! El nodo sinusal (SA), en la aurícula derecha, es el marcapasos fisiológico (60–100/min).',
        hint: 'Arriba, en la aurícula derecha.',
      },
      {
        type: 'choice', kicker: 'Comprende el porqué', title: 'El freno del nodo AV',
        prompt: '¿Para qué sirve que el nodo AV retrase el impulso unos milisegundos?',
        options: [
          { text: 'Para que las aurículas terminen de vaciarse antes de que se contraigan los ventrículos', correct: true },
          { text: 'Para acelerar la frecuencia cardíaca', correct: false },
          { text: 'Para generar la onda T', correct: false },
        ],
        why: 'Ese retraso (el segmento PR) da tiempo a que la sangre pase de aurículas a ventrículos: primero se llenan, luego se expulsa.',
      },
    ],
  },

  /* ─── MÓDULO 1 ──────────────────────────────────────────────────────── */
  {
    id: 'm1', icon: 'ecg_heart', color: '#B87A6F',
    title: 'El nacimiento de las ondas',
    subtitle: 'Cada fase eléctrica deja su huella',
    steps: [
      {
        type: 'info', kicker: 'Conecta causa y efecto', title: 'De la electricidad al dibujo',
        visual: 'wave-labeled',
        body: 'Cada tramo del ECG es la huella de una fase del impulso. Si sabes qué está pasando en el corazón, sabes qué onda esperar.',
        points: ['P = despolarización auricular', 'QRS = despolarización ventricular', 'T = repolarización ventricular'],
      },
      {
        type: 'conduction', kicker: 'Míralo en sincronía', title: 'La onda se escribe sola',
        focus: 'wave',
        body: 'Ahora fíjate en la etiqueta de la onda: mientras el impulso recorre cada estructura, el trazo dibuja P, PR, QRS, ST y T en tiempo real.',
      },
      {
        type: 'hotspot', kicker: 'Reconócelas', title: 'La huella de las aurículas',
        scene: 'waves', target: 'P',
        prompt: 'Toca la onda que produce la despolarización de las aurículas.',
        ok: 'Correcto: la onda P. Pequeña, redondeada y siempre antes del QRS.',
        hint: 'Es la primera deflexión, justo antes del gran pico.',
      },
      {
        type: 'hotspot', kicker: 'Reconócelas', title: 'La huella de los ventrículos',
        scene: 'waves', target: 'QRS',
        prompt: 'Toca el complejo de la despolarización ventricular.',
        ok: '¡Eso es! El QRS: alto y estrecho porque el His-Purkinje activa los ventrículos muy deprisa.',
        hint: 'La deflexión más grande y puntiaguda.',
      },
      {
        type: 'choice', kicker: 'Afiánzalo', title: '¿Y la onda T?',
        prompt: 'La onda T representa…',
        options: [
          { text: 'La repolarización (recuperación) de los ventrículos', correct: true },
          { text: 'La repolarización de las aurículas', correct: false },
          { text: 'La contracción de las aurículas', correct: false },
        ],
        why: 'La repolarización auricular queda oculta dentro del QRS. La T que ves es la recuperación ventricular.',
      },
    ],
  },

  /* ─── MÓDULO 2 ──────────────────────────────────────────────────────── */
  {
    id: 'm2', icon: 'grid_on', color: '#C9A24A',
    title: 'El papel y la medida',
    subtitle: 'Convertir cuadros en tiempo y voltaje',
    steps: [
      {
        type: 'info', kicker: 'La regla del papel', title: '25 mm/s · 10 mm/mV',
        visual: 'grid',
        body: 'El papel corre a 25 mm/s y la ganancia es 10 mm/mV. Con eso, cada cuadradito y cada cuadro grande valen siempre lo mismo:',
        points: ['1 cuadradito (1 mm) = 0,04 s   y   0,1 mV', '1 cuadro grande (5 mm) = 0,20 s   y   0,5 mV'],
      },
      {
        type: 'caliper', kicker: 'Mide tú', title: 'Mide la anchura del QRS',
        prompt: 'Desliza el compás para abarcar el QRS de principio a fin. Un QRS normal mide menos de 0,12 s (3 cuadraditos).',
        trueMs: 100, tolMs: 22, normalMax: 120,
      },
      {
        type: 'rate', kicker: 'Calcula la frecuencia', title: 'La regla 300',
        prompt: 'Divide 300 entre el nº de cuadros grandes que hay entre dos R. Ajusta el intervalo hasta una frecuencia normal (60–100 lpm).',
        targetMin: 60, targetMax: 100,
      },
      {
        type: 'choice', kicker: 'Aplica la medida', title: 'Un PR largo',
        prompt: 'Mides un intervalo PR de 6 cuadraditos (0,24 s). Eso es…',
        options: [
          { text: 'Prolongado (> 0,20 s): sugiere bloqueo AV de 1.er grado', correct: true },
          { text: 'Normal', correct: false },
          { text: 'Corto: sugiere preexcitación', correct: false },
        ],
        why: 'El PR normal es 0,12–0,20 s (3–5 cuadraditos). 0,24 s supera el límite: BAV de 1.er grado.',
      },
    ],
  },

  /* ─── MÓDULO 3 ──────────────────────────────────────────────────────── */
  {
    id: 'm3', icon: 'checklist', color: '#8BA888',
    title: 'Lectura sistemática',
    subtitle: 'Un orden fijo para no perderte',
    steps: [
      {
        type: 'info', kicker: 'La clave del método', title: 'Nunca improvises',
        visual: 'order',
        body: 'El error más común es mirar solo lo llamativo. Un buen lector recorre SIEMPRE el mismo orden, aunque el ECG parezca normal. Así no se escapa nada.',
        points: ['Un método fijo detecta lo sutil', 'Repítelo hasta que sea automático'],
      },
      {
        type: 'reveal', kicker: 'Descúbrelos', title: 'Los 5 pasos',
        prompt: 'Toca cada paso para ver qué te preguntas en él.',
        items: [
          { k: '1', label: 'Ritmo', text: '¿Hay onda P antes de cada QRS? ¿Es regular? → sinusal o no.' },
          { k: '2', label: 'Frecuencia', text: 'Regla 300 / cuadros grandes. ¿Bradicardia, normal o taquicardia?' },
          { k: '3', label: 'Eje', text: 'Mira I y aVF. ¿Eje normal, izquierdo o derecho?' },
          { k: '4', label: 'Intervalos', text: 'Mide PR, QRS y QT. ¿Alguno fuera de rango?' },
          { k: '5', label: 'Morfología', text: 'Ondas y segmentos: P, Q patológicas, ST (elevado/descendido), T.' },
        ],
      },
      {
        type: 'choice', kicker: 'Paso 1 en acción', title: 'Aplica el ritmo',
        prompt: 'Ritmo irregular, sin ondas P visibles y línea de base ondulante. Orienta a…',
        options: [
          { text: 'Fibrilación auricular', correct: true },
          { text: 'Ritmo sinusal normal', correct: false },
          { text: 'Bloqueo AV de 1.er grado', correct: false },
        ],
        why: 'Sin P + R-R irregularmente irregular = fibrilación auricular hasta que se demuestre lo contrario.',
      },
      {
        type: 'choice', kicker: 'Paso 4 en acción', title: 'Aplica los intervalos',
        prompt: 'Taquicardia regular con QRS ANCHO (> 0,12 s). Tu primera sospecha debe ser…',
        options: [
          { text: 'Taquicardia ventricular', correct: true },
          { text: 'Taquicardia sinusal', correct: false },
          { text: 'Fibrilación auricular', correct: false },
        ],
        why: 'Toda taquicardia de QRS ancho es TV mientras no se demuestre lo contrario, sobre todo si hay cardiopatía.',
      },
    ],
  },

  /* ─── MÓDULO 4 ──────────────────────────────────────────────────────── */
  {
    id: 'm4', icon: 'explore', color: '#7CA3C9',
    title: '12 miradas y el eje',
    subtitle: 'El mismo vector visto desde 12 ángulos',
    steps: [
      {
        type: 'info', kicker: 'Por qué 12', title: '12 derivaciones = 12 puntos de vista',
        visual: 'leads',
        body: 'El corazón genera un vector eléctrico. Cada derivación lo mira desde un ángulo distinto: si el vector se acerca, la onda sube; si se aleja, baja. Por eso una misma arritmia se ve distinta en cada derivación.',
        points: ['Miembros (I, II, III, aVR, aVL, aVF): plano frontal', 'Precordiales (V1–V6): plano horizontal'],
      },
      {
        type: 'axis', kicker: 'Gíralo tú', title: 'El eje eléctrico',
        prompt: 'Rota el vector del QRS y observa cómo cambian I y aVF. Colócalo en desviación IZQUIERDA (entre -30° y -90°).',
        targetMin: -90, targetMax: -30, targetLabel: 'desviación izquierda',
      },
      {
        type: 'choice', kicker: 'Localiza', title: 'La cara inferior',
        prompt: '¿Qué grupo de derivaciones "mira" la cara inferior del corazón?',
        options: [
          { text: 'II, III y aVF', correct: true },
          { text: 'V1, V2, V3 y V4', correct: false },
          { text: 'I y aVL', correct: false },
        ],
        why: 'II, III y aVF miran la cara inferior (suele irrigarla la coronaria derecha). V1–V4 = anterior; I, aVL, V5–V6 = lateral.',
      },
    ],
  },

  /* ─── MÓDULO: TAQUICARDIAS (algoritmo) ──────────────────────────────── */
  {
    id: 'm5t', icon: 'bolt', color: '#C45B4E',
    title: 'Algoritmo: taquicardias',
    subtitle: 'Dos preguntas ordenan el diagnóstico',
    steps: [
      {
        type: 'info', kicker: 'El método', title: 'Primero, mira el QRS',
        visual: 'tree',
        body: 'Toda taquicardia (FC > 100) se ordena con dos preguntas. La PRIMERA —¿el QRS es estrecho o ancho?— parte el problema en dos mitades. Por eso lo verás en dos árboles: en cada uno solo queda decidir si el ritmo es regular o irregular.',
        points: ['1) ¿QRS estrecho (supraventricular) o ancho (ventricular)?', '2) Dentro de cada rama: ¿regular o irregular?', 'Regla de oro: QRS ancho = trátala como TV hasta demostrar lo contrario'],
      },
      {
        type: 'algorithm', kicker: 'Rama 1 · QRS estrecho', title: 'Taquicardia de QRS estrecho',
        tree: 'taqui_narrow',
      },
      {
        type: 'algorithm', kicker: 'Rama 2 · QRS ancho', title: 'Taquicardia de QRS ancho',
        tree: 'taqui_wide',
      },
      {
        type: 'choice', kicker: 'Aplícalo', title: 'Taquicardia regular a 150',
        prompt: 'Taquicardia regular de QRS estrecho a 150 lpm con ondas negativas en dientes de sierra en II, III y aVF. Es…',
        options: [
          { text: 'Flúter auricular con conducción 2:1', correct: true },
          { text: 'Taquicardia sinusal', correct: false },
          { text: 'Fibrilación auricular', correct: false },
        ],
        why: 'Dientes de sierra a ~300/min con ventrículo a 150 = flúter 2:1. Ante toda taquicardia regular a 150, descártalo siempre.',
      },
      {
        type: 'choice', kicker: 'Trampa clásica', title: 'FA preexcitada',
        prompt: 'Joven con taquicardia IRREGULAR, muy rápida y de QRS anchos variables (FA sobre una vía accesoria). ¿Qué NO debes usar?',
        options: [
          { text: 'Frenadores del nodo AV (verapamilo, digoxina, adenosina)', correct: true },
          { text: 'Cardioversión eléctrica si hay inestabilidad', correct: false },
          { text: 'Procainamida', correct: false },
        ],
        why: 'Frenar el nodo AV favorece la conducción por la vía accesoria y puede degenerar en fibrilación ventricular. Si hay inestabilidad, cardioversión.',
      },
    ],
  },

  /* ─── MÓDULO: BRADICARDIAS Y BLOQUEOS ───────────────────────────────── */
  {
    id: 'm6b', icon: 'stairs', color: '#8BA888',
    title: 'Bradicardias y bloqueos AV',
    subtitle: 'Dónde y cómo se rompe la conducción',
    steps: [
      {
        type: 'info', kicker: 'El mapa', title: 'Cuando la conducción falla',
        visual: 'order',
        body: 'Si el corazón va lento, pregúntate primero si cada P conduce con normalidad. Si no, el fallo está en el nodo AV, y su patrón nos dice de qué bloqueo se trata.',
        points: ['1.er grado: PR largo pero todo conduce', '2.º grado: algún latido se pierde', '3.er grado: nada conduce (disociación)'],
      },
      {
        type: 'ladder', kicker: 'Míralo funcionar', title: 'La escalera de conducción',
        prompt: 'Cambia de patrón y observa cómo baja (o no) cada impulso de la aurícula (A) al ventrículo (V) a través del nodo AV.',
        kinds: ['normal', 'mobitz1', 'mobitz2', 'av3'],
      },
      {
        type: 'algorithm', kicker: 'Recórrelo tú', title: 'Árbol de las bradicardias',
        tree: 'bradi',
      },
      {
        type: 'choice', kicker: 'Distingue los peligrosos', title: 'Mobitz I vs Mobitz II',
        prompt: '¿Cuál de estos bloqueos de 2.º grado es "el malo" (riesgo de progresar a bloqueo completo → marcapasos)?',
        options: [
          { text: 'Mobitz II (PR fijo, caída súbita del QRS)', correct: true },
          { text: 'Mobitz I / Wenckebach (PR que se alarga)', correct: false },
          { text: 'Ambos tienen el mismo pronóstico', correct: false },
        ],
        why: 'Mobitz II suele ser infrahisiano e impredecible → marcapasos. Wenckebach suele ser suprahisiano y benigno.',
      },
    ],
  },

  /* ─── MÓDULO: LOCALIZA EL INFARTO ───────────────────────────────────── */
  {
    id: 'm7i', icon: 'target', color: '#B87A6F',
    title: 'Localiza el infarto',
    subtitle: 'De las derivaciones a la arteria',
    steps: [
      {
        type: 'info', kicker: 'La lógica', title: 'Cada cara, sus derivaciones',
        visual: 'leads',
        body: 'La elevación del ST aparece en las derivaciones que "miran" la zona infartada. Con ellas localizas la pared y, de ahí, deduces la arteria ocluida.',
        points: ['Inferior: II, III, aVF → coronaria derecha', 'Anterior/septal: V1-V4 → descendente anterior', 'Lateral: I, aVL, V5-V6 → circunfleja'],
      },
      {
        type: 'territory', kicker: 'Señálalo', title: 'ST elevado en II, III y aVF',
        prompt: 'El ST se eleva en II, III y aVF. Toca la pared del corazón que corresponde.',
        target: 'inferior',
        ok: 'Cara inferior: la irriga casi siempre la coronaria derecha. Pide derivaciones derechas (V4R) para descartar infarto de ventrículo derecho.',
      },
      {
        type: 'territory', kicker: 'Señálalo', title: 'ST elevado en V3 y V4',
        prompt: 'Ahora el ST se eleva en V3-V4. Toca la pared correspondiente.',
        target: 'anterior',
        ok: 'Cara anterior: oclusión de la descendente anterior (DA). Si además hay elevación en V1-V4, es anteroseptal extenso.',
      },
      {
        type: 'choice', kicker: 'El detalle que salva', title: 'Infarto de ventrículo derecho',
        prompt: 'SCACEST inferior con hipotensión. Confirmas afectación del VD (V4R). ¿Qué es clave?',
        options: [
          { text: 'Evitar nitratos y vasodilatadores: el VD depende de la precarga', correct: true },
          { text: 'Administrar nitroglicerina en dosis altas', correct: false },
          { text: 'Forzar diuresis', correct: false },
        ],
        why: 'El VD infartado depende de la precarga: los nitratos/diuréticos la bajan y provocan hipotensión grave. Se trata con sueroterapia.',
      },
      {
        type: 'choice', kicker: 'La cara que no se ve', title: 'Infarto posterior',
        prompt: 'Descenso del ST y ondas R altas en V1-V2 (sin elevación clásica). Piensa en…',
        options: [
          { text: 'Infarto posterior (imagen "en espejo" de V1-V2)', correct: true },
          { text: 'Hipertrofia ventricular izquierda', correct: false },
          { text: 'Pericarditis', correct: false },
        ],
        why: 'La cara posterior no tiene derivaciones directas: se ve como imagen especular en V1-V2 (descenso del ST, R altas). Confírmalo con V7-V9.',
      },
    ],
  },

  /* ─── MÓDULO 5 ──────────────────────────────────────────────────────── */
  {
    id: 'm5', icon: 'stethoscope', color: '#C45B4E',
    title: 'Del trazo al diagnóstico',
    subtitle: 'Junta todo en un árbol de decisión',
    steps: [
      {
        type: 'info', kicker: 'El momento de unirlo', title: 'De hallazgos a diagnóstico',
        visual: 'tree',
        body: 'Con la sistemática, el diagnóstico sale de un árbol de decisiones sencillo. Vamos a recorrerlo con tres preguntas clave.',
        points: ['¿QRS estrecho o ancho?', '¿Regular o irregular?', '¿Hay P? ¿Cómo está el ST?'],
      },
      {
        type: 'choice', kicker: 'Rama 1', title: 'Ancho o estrecho',
        prompt: 'Una taquicardia con QRS ESTRECHO y regular, sin P visibles, muy rápida (≈180). Piensa en…',
        options: [
          { text: 'Taquicardia supraventricular (TPSV)', correct: true },
          { text: 'Taquicardia ventricular', correct: false },
          { text: 'Flutter con conducción variable', correct: false },
        ],
        why: 'QRS estrecho + regular + muy rápido + sin P = TPSV. Primer escalón terapéutico: maniobras vagales.',
      },
      {
        type: 'choice', kicker: 'Rama 2', title: 'Regular o irregular',
        prompt: 'QRS estrecho pero R-R irregularmente irregular y sin ondas P. El diagnóstico es…',
        options: [
          { text: 'Fibrilación auricular', correct: true },
          { text: 'Taquicardia sinusal', correct: false },
          { text: 'Bloqueo AV completo', correct: false },
        ],
        why: 'Irregular + sin P = FA. Recuerda valorar la anticoagulación (CHA₂DS₂-VASc).',
      },
      {
        type: 'choice', kicker: 'Rama 3', title: 'El segmento ST',
        prompt: 'Dolor torácico con elevación del ST en II, III y aVF. Esto es…',
        options: [
          { text: 'Un infarto agudo de cara inferior (SCACEST)', correct: true },
          { text: 'Pericarditis', correct: false },
          { text: 'Un hallazgo normal', correct: false },
        ],
        why: 'ST elevado en ≥2 derivaciones contiguas (aquí las inferiores) = SCACEST → reperfusión urgente. El tiempo es músculo.',
      },
      {
        type: 'summary', kicker: '¡Lo lograste!', title: 'Ya lees un ECG con método',
        body: 'Has recorrido el camino completo: de la chispa del nodo sinusal a un diagnóstico razonado. Ahora consolida lo aprendido viendo estos patrones latir en el simulador de 12 derivaciones.',
        cta: 'Practicar en el simulador',
      },
    ],
  },
];
