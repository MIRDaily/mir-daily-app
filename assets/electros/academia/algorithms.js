/* ════════════════════════════════════════════════════════════════════════
   MIRElectro Academia — algorithms.js
   Árboles de decisión diagnósticos (datos) y territorios del infarto.
   Contenido original, redactado para esta herramienta.

   Un nodo es una PREGUNTA (tiene `q` + `options[{label, go}]`) o una HOJA
   diagnóstica (tiene `dx`). Las hojas enlazan una tira de ritmo (strips.js).
═══════════════════════════════════════════════════════════════════════════ */

export const TREES = {
  /* ─── Taquicardias · QRS ESTRECHO (< 0,12 s) ──────────────────────── */
  taqui_narrow: {
    id: 'taqui_narrow', title: 'Taquicardia de QRS estrecho', root: 'q_nr0',
    intro: 'Primera pregunta ya contestada: el QRS es estrecho (< 0,12 s), así que el origen es supraventricular. Ahora decide si el ritmo es regular o irregular y afina con la actividad auricular.',
    nodes: {
      q_nr0: { q: '¿El ritmo es regular o irregular?', options: [
        { label: 'Regular', go: 'q_nr' },
        { label: 'Irregular', go: 'q_ni' },
      ] },
      q_nr: { q: '¿Qué actividad auricular ves?', options: [
        { label: 'P sinusal normal antes de cada QRS', go: 'l_sinustaq' },
        { label: 'Ondas en “dientes de sierra” (~300/min)', go: 'l_flutter' },
        { label: 'Sin P visibles; inicio y fin bruscos', go: 'l_tpsv' },
        { label: 'Ondas P′ distintas de la sinusal, PR fijo', go: 'l_atrial' },
      ] },
      q_ni: { q: '¿Qué ves en la línea de base?', options: [
        { label: 'Sin ondas P; línea de base ondulante', go: 'l_af' },
        { label: 'Dientes de sierra con conducción variable', go: 'l_flutvar' },
      ] },
      l_sinustaq: { dx: 'Taquicardia sinusal', badge: 'T. sinusal', sev: 'warn', strip: 'sinus_tachy',
        clue: 'P sinusal antes de cada QRS, regular, 100–150 lpm.',
        why: 'Es la causa más frecuente de taquicardia regular estrecha. Casi siempre secundaria (fiebre, dolor, anemia, hipovolemia, TEP…): trata la causa.' },
      l_flutter: { dx: 'Flúter auricular', badge: 'Flúter', sev: 'warn', strip: 'flutter',
        clue: 'Ondas F en dientes de sierra ~300/min, mejor en II-III-aVF; conducción 2:1 → ventrículo ~150.',
        why: 'Macrorreentrada por el istmo cavotricuspídeo. Toda taquicardia regular a 150 obliga a descartar flúter 2:1; las maniobras vagales desenmascaran las ondas F.' },
      l_tpsv: { dx: 'Taquicardia paroxística supraventricular', badge: 'TPSV', sev: 'warn', strip: 'svt',
        clue: 'QRS estrecho, muy regular, 150–220 lpm; P no visibles o retrógradas tras el QRS; inicio/fin bruscos.',
        why: 'Casi siempre reentrada intranodal (la más frecuente) o por vía accesoria ortodrómica. Escalón inicial: maniobras vagales; si fallan, adenosina.' },
      l_atrial: { dx: 'Taquicardia auricular monofocal', badge: 'T. auricular', sev: 'warn', strip: 'atrial',
        clue: 'Ondas P′ iguales entre sí pero distintas de la sinusal, con PR constante.',
        why: 'Un foco ectópico auricular único. La polaridad de la P′ orienta a su localización (P′ negativa en cara inferior = foco auricular bajo).' },
      l_af: { dx: 'Fibrilación auricular', badge: 'FA', sev: 'warn', strip: 'af',
        clue: 'Ausencia de P, R-R irregularmente irregular, línea de base fibrilatoria.',
        why: 'La arritmia sostenida más frecuente. La clave MIR es valorar la anticoagulación con la escala CHA₂DS₂-VASc.' },
      l_flutvar: { dx: 'Flúter con conducción variable', badge: 'Flúter var.', sev: 'warn', strip: 'flutter',
        clue: 'Dientes de sierra a ~300/min pero con bloqueo AV cambiante → R-R irregular.',
        why: 'Mismo sustrato que el flúter, pero el nodo AV deja pasar los impulsos de forma variable (3:1, 4:1…), por lo que el ritmo ventricular se ve irregular.' },
    },
  },

  /* ─── Taquicardias · QRS ANCHO (≥ 0,12 s) ─────────────────────────── */
  taqui_wide: {
    id: 'taqui_wide', title: 'Taquicardia de QRS ancho', root: 'q_wr0',
    intro: 'Primera pregunta ya contestada: el QRS es ancho (≥ 0,12 s). Regla de oro: trátala como taquicardia ventricular hasta demostrar lo contrario. Aun así, ¿regular o irregular? y algún dato clínico ayudan a afinar.',
    nodes: {
      q_wr0: { q: '¿El ritmo es regular o irregular?', options: [
        { label: 'Regular', go: 'q_wr' },
        { label: 'Irregular', go: 'q_wi' },
      ] },
      q_wr: { q: '¿Qué dato clínico o ECG tienes?', options: [
        { label: 'Cardiopatía, disociación AV o latidos de captura/fusión', go: 'l_vt' },
        { label: 'Bloqueo de rama ya conocido o dependiente de la frecuencia', go: 'l_aberr' },
      ] },
      q_wi: { q: '¿Cómo son los complejos?', options: [
        { label: 'Anchos, muy rápidos y de morfología variable', go: 'l_fapre' },
        { label: 'Giran sobre la línea de base; QT largo previo', go: 'l_tdp' },
      ] },
      l_vt: { dx: 'Taquicardia ventricular', badge: 'TV', sev: 'crit', strip: 'vt',
        clue: 'QRS ancho, regular, 100–250 lpm; busca disociación AV, capturas y fusiones.',
        why: 'Toda taquicardia de QRS ancho es TV hasta que se demuestre lo contrario, sobre todo con cardiopatía. Si hay inestabilidad → cardioversión eléctrica.' },
      l_aberr: { dx: 'TSV conducida con aberrancia', badge: 'TSV aberr.', sev: 'warn', strip: 'vt',
        clue: 'Taquicardia supraventricular que se ve ancha por bloqueo de rama fijo o dependiente de la frecuencia.',
        why: 'Se parece a una TV. La clave es el ECG basal previo: si ya tenía ese bloqueo de rama, apoya aberrancia. Ante la duda, actúa como si fuera TV.' },
      l_fapre: { dx: 'FA preexcitada', badge: 'FA + WPW', sev: 'crit', strip: 'af_wide',
        clue: 'Irregular, muy rápida, QRS anchos de amplitud y morfología variables, voltajes normales.',
        why: 'FA en un paciente con vía accesoria. NO uses frenadores del nodo AV (digoxina, verapamilo, adenosina): pueden acelerar la conducción por la vía y degenerar en FV.' },
      l_tdp: { dx: 'Torsade de pointes', badge: 'TdP', sev: 'crit', strip: 'torsades',
        clue: 'TV polimorfa cuyos complejos giran alrededor de la línea de base; sobre un QT largo previo.',
        why: 'Tratamiento: sulfato de magnesio IV, retirar el fármaco causal y corregir electrolitos (K, Mg).' },
    },
  },

  /* ─── Bradicardias y bloqueos (FC < 60 o pausas) ──────────────────── */
  bradi: {
    id: 'bradi', title: 'Algoritmo de las bradicardias', root: 'q1',
    intro: 'Ante una bradicardia, comprueba primero si la relación entre P y QRS es normal. Si lo es, es una bradicardia sinusal; si no, busca dónde se rompe la conducción AV.',
    nodes: {
      q1: { q: '1) ¿Cada P conduce con un PR normal y constante?', options: [
        { label: 'Sí: todo sinusal, solo que lento (< 60)', go: 'l_brady' },
        { label: 'No: algo falla en la conducción', go: 'q2' },
      ] },
      q2: { q: '2) ¿Cómo se comporta el PR y la conducción?', options: [
        { label: 'PR largo (> 0,20 s) pero fijo; toda P conduce', go: 'l_av1' },
        { label: 'El PR se alarga poco a poco hasta que cae un QRS', go: 'l_m1' },
        { label: 'PR fijo y de pronto cae un QRS sin avisar', go: 'l_m2' },
        { label: 'P y QRS van cada uno a su ritmo (disociados)', go: 'l_av3' },
      ] },
      l_brady: { dx: 'Bradicardia sinusal', badge: 'Brady', sev: 'normal', strip: 'sinus_brady',
        clue: 'Morfología sinusal conservada (P antes de cada QRS), solo que a < 60 lpm.',
        why: 'Frecuente y benigna en deportistas o durante el sueño. Busca causa (fármacos, hipotiroidismo) solo si es sintomática.' },
      l_av1: { dx: 'Bloqueo AV de 1.er grado', badge: 'BAV I', sev: 'normal', strip: 'av1',
        clue: 'PR > 0,20 s, constante; cada P va seguida de su QRS (ninguna se pierde).',
        why: 'Retraso en la conducción AV sin latidos perdidos. Habitualmente benigno y no requiere tratamiento.' },
      l_m1: { dx: 'BAV 2.º grado Mobitz I (Wenckebach)', badge: 'Mobitz I', sev: 'warn', strip: 'mobitz1',
        clue: 'Alargamiento progresivo del PR hasta que una P se bloquea; luego el ciclo se reinicia.',
        why: 'Suele ser suprahisiano y de buen pronóstico; rara vez precisa marcapasos.' },
      l_m2: { dx: 'BAV 2.º grado Mobitz II', badge: 'Mobitz II', sev: 'crit', strip: 'mobitz2',
        clue: 'PR fijo en los latidos conducidos y caída súbita de un QRS, sin aviso previo.',
        why: 'Suele ser infrahisiano y puede progresar a bloqueo completo → indica marcapasos. Es “el malo”; no lo confundas con Wenckebach.' },
      l_av3: { dx: 'BAV completo (3.er grado)', badge: 'BAV III', sev: 'crit', strip: 'av3',
        clue: 'Disociación AV: las P marchan a su ritmo y los QRS de escape al suyo, sin relación entre ellos.',
        why: 'Ningún impulso auricular llega al ventrículo; sobrevive un marcapasos de escape (nodal = QRS estrecho; ventricular = ancho y lento). Tratamiento: marcapasos.' },
    },
  },
};

/* ─── Localización del infarto por territorio ───────────────────────────
   Datos para el mapa interactivo. Cada pared: derivaciones con elevación del
   ST y arteria coronaria habitualmente responsable.
*/
export const WALLS = {
  septal:    { name: 'Septal', leads: 'V1–V2', artery: 'DA (ramas septales)', color: '#C9A24A' },
  anterior:  { name: 'Anterior', leads: 'V3–V4', artery: 'Descendente anterior (DA)', color: '#C45B4E' },
  lateral:   { name: 'Lateral', leads: 'I, aVL, V5–V6', artery: 'Circunfleja (Cx) / 1.ª diagonal', color: '#7CA3C9' },
  inferior:  { name: 'Inferior', leads: 'II, III, aVF', artery: 'Coronaria derecha (CD)', color: '#8BA888' },
  posterior: { name: 'Posterior', leads: 'V7–V9 (espejo en V1–V2)', artery: 'Cx o CD', color: '#B87A6F' },
  rv:        { name: 'Ventrículo derecho', leads: 'V3R–V4R', artery: 'CD proximal', color: '#D4978C' },
};
