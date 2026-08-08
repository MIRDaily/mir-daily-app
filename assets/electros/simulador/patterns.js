/* ════════════════════════════════════════════════════════════════════════
   MIRElectro-Pro — patterns.js
   Catálogo de patrones ECG con metadatos clínicos + directivas de síntesis.

   morph:
     qrsAxis  eje eléctrico (º)         qrsWidth  factor anchura QRS (1≈90ms)
     qrsMag   magnitud del QRS (mV)     qtScale   escala posición/QT de la T
     pr       PR en s (P antes de R)    tWidth    anchura de la T
     pNotch/pPeak  P mitrale/pulmonale  mods[]    transformaciones (leads.js)
   gen: ritmo (ecg-core.js). rhythm: parámetros extra del generador.
═══════════════════════════════════════════════════════════════════════════ */

export const PATTERNS = [
  /* ─── NORMAL / SINUSAL ───────────────────────────────────────────── */
  {
    id: 'sinus', name: 'Ritmo sinusal normal', badge: 'RSN', category: 'Normal', severity: 'normal',
    hr: 72, gen: 'regular', morph: {},
    intervals: { fc: '60–100', pr: '120–200 ms', qrs: '<120 ms', qt: '≈400 ms', eje: '≈+60°' },
    summary: 'El patrón de referencia: cada P seguida de un QRS estrecho, ritmo regular a 60–100 lpm.',
    findings: [
      'Onda P positiva en II, negativa en aVR, antes de cada QRS',
      'PR constante (120–200 ms) y QRS estrecho (<120 ms)',
      'Progresión normal de R en precordiales (transición V3–V4)',
      'Eje entre -30° y +90°',
    ],
    pearl: 'Es el ritmo con el que comparas todo lo demás: P → QRS estrecho → T, regular y a 60–100 lpm, eje normal.',
  },
  {
    id: 'sinus_brady', name: 'Bradicardia sinusal', badge: 'Brady', category: 'Normal', severity: 'warn',
    hr: 45, gen: 'regular', morph: { qtScale: 1.15 },
    intervals: { fc: '<60', pr: '120–200 ms', qrs: '<120 ms', qt: '↑' },
    summary: 'Ritmo sinusal morfológicamente normal pero lento (<60 lpm).',
    findings: ['Morfología sinusal conservada', 'Frecuencia <60 lpm', 'Frecuente en deportistas, hipotiroidismo, β-bloqueantes'],
    pearl: 'Bradicardia sinusal asintomática en un joven deportista es normal. Si hay síncope o hipotensión, busca causa.',
  },
  {
    id: 'sinus_tachy', name: 'Taquicardia sinusal', badge: 'Tachy', category: 'Normal', severity: 'warn',
    hr: 130, gen: 'regular', morph: { qtScale: 0.82 },
    intervals: { fc: '100–150', pr: '120–180 ms', qrs: '<120 ms', qt: '↓' },
    summary: 'Ritmo sinusal rápido (>100 lpm). Casi siempre secundaria a una causa.',
    findings: ['P sinusal antes de cada QRS, regular', 'FC 100–150 lpm (rara vez >150)', 'Buscar causa: fiebre, dolor, anemia, TEP, hipertiroidismo'],
    pearl: 'La taquicardia sinusal es un síntoma, no un diagnóstico: trata la causa, no la frecuencia.',
  },

  /* ─── TAQUIARRITMIAS ─────────────────────────────────────────────── */
  {
    id: 'afib', name: 'Fibrilación auricular', badge: 'FA', category: 'Taquiarritmias', severity: 'warn',
    hr: 115, gen: 'afib', morph: {},
    intervals: { fc: '≈115', pr: '—', qrs: '<120 ms', qt: 'var' },
    summary: 'La arritmia sostenida más frecuente. Irregularmente irregular y sin ondas P.',
    findings: ['Ausencia de P → línea de base fibrilatoria', 'R-R "irregularmente irregular"', 'Respuesta ventricular variable', 'Riesgo embólico → anticoagulación (CHA₂DS₂-VASc)'],
    pearl: 'Sin P + R-R irregularmente irregular = FA. La clave MIR es la anticoagulación según CHA₂DS₂-VASc.',
  },
  {
    id: 'aflutter', name: 'Flutter auricular', badge: 'Flutter', category: 'Taquiarritmias', severity: 'warn',
    hr: 75, gen: 'aflutter', morph: {},
    intervals: { fc: '150 (2:1)', pr: '—', qrs: '<120 ms', qt: '—' },
    summary: 'Ondas F en "dientes de sierra" a ~300/min con conducción AV variable (típica 2:1).',
    findings: ['Ondas F en dientes de sierra en II, III, aVF', 'Frecuencia auricular ≈250–300/min', 'Conducción 2:1 → ventrículo a ~150', 'QRS estrecho y regular si el bloqueo es fijo'],
    pearl: 'Taquicardia regular a 150 lpm: piensa en flutter 2:1. Las maniobras vagales desenmascaran las ondas F.',
  },
  {
    id: 'svt', name: 'Taquicardia supraventricular (TPSV)', badge: 'TPSV', category: 'Taquiarritmias', severity: 'warn',
    hr: 185, gen: 'noP', morph: { qtScale: 0.7 },
    intervals: { fc: '150–220', pr: '—', qrs: '<120 ms', qt: '↓' },
    summary: 'Taquicardia regular de QRS estrecho, muy rápida y sin ondas P visibles.',
    findings: ['QRS estrecho, regular, 150–220 lpm', 'P no visibles o retrógradas', 'Inicio y fin bruscos (paroxística)', 'Responde a maniobras vagales / adenosina'],
    pearl: 'QRS estrecho + regular + muy rápido + sin P = TPSV. Primer escalón: vagales; si falla, adenosina.',
  },
  {
    id: 'wpw', name: 'Wolff-Parkinson-White', badge: 'WPW', category: 'Taquiarritmias', severity: 'warn',
    hr: 75, gen: 'regular', morph: { pr: 0.10, qrsWidth: 1.45, mods: ['wpw'] },
    intervals: { fc: '≈75', pr: '<120 ms', qrs: '>120 ms', qt: 'nl' },
    summary: 'Preexcitación: PR corto + onda delta por una vía accesoria.',
    findings: ['PR corto (<120 ms)', 'Onda delta: empastamiento inicial del QRS', 'QRS ensanchado a expensas del inicio', 'Riesgo de taquicardias por reentrada'],
    pearl: 'PR corto + onda delta = WPW. En FA preexcitada evita frenadores del nodo AV (digoxina, verapamilo): pueden ser letales.',
  },
  {
    id: 'vtach', name: 'Taquicardia ventricular monomorfa', badge: 'TV', category: 'Taquiarritmias', severity: 'crit',
    hr: 170, gen: 'noP', morph: { qrsWidth: 2.6, qrsMag: 1.6, qrsAxis: -120, tMag: -0.5, tAxis: 60 },
    intervals: { fc: '100–250', pr: '—', qrs: '>120 ms', qt: '—' },
    summary: 'Taquicardia regular de QRS ancho. Emergencia: puede degenerar en FV.',
    findings: ['QRS ancho (>120 ms), monomorfo y regular', 'Disociación AV / capturas / fusiones', 'Eje muy desviado, concordancia precordial', 'Toda taquicardia ancha es TV hasta que se demuestre lo contrario'],
    pearl: 'Taquicardia de QRS ancho + cardiopatía = TV. Inestable → cardioversión eléctrica inmediata.',
  },
  {
    id: 'torsades', name: 'Torsade de pointes', badge: 'TdP', category: 'Taquiarritmias', severity: 'crit',
    hr: 250, gen: 'torsades', morph: { qrsWidth: 2.0 },
    intervals: { fc: '200–280', pr: '—', qrs: '>120 ms', qt: 'QT largo previo' },
    summary: 'TV polimorfa cuyos complejos "giran" alrededor de la línea de base. Sobre un QT largo.',
    findings: ['Complejos que rotan en amplitud y eje (patrón en huso)', 'Asociada a QT largo (fármacos, hipoK, hipoMg)', 'Puede autolimitarse o degenerar en FV'],
    pearl: 'Torsade + QT largo → sulfato de magnesio IV, retirar el fármaco causal y corregir electrolitos.',
  },

  /* ─── PARO ───────────────────────────────────────────────────────── */
  {
    id: 'vfib', name: 'Fibrilación ventricular', badge: 'FV', category: 'Paro', severity: 'crit',
    hr: 0, gen: 'vfib', morph: {},
    intervals: { fc: '—', pr: '—', qrs: '—', qt: '—' },
    summary: 'Actividad eléctrica caótica sin complejos identificables. Parada cardíaca.',
    findings: ['Ondulaciones irregulares sin QRS reconocibles', 'No hay gasto → inconsciencia', 'Ritmo desfibrilable'],
    pearl: 'FV = RCP + desfibrilación inmediata. Junto a la TV sin pulso, el ritmo desfibrilable por excelencia.',
  },
  {
    id: 'asystole', name: 'Asistolia', badge: 'Asist.', category: 'Paro', severity: 'crit',
    hr: 0, gen: 'asystole', morph: {},
    intervals: { fc: '0', pr: '—', qrs: '—', qt: '—' },
    summary: 'Ausencia total de actividad eléctrica: línea isoeléctrica.',
    findings: ['Línea plana (confirma en 2 derivaciones, sube ganancia)', 'Ritmo NO desfibrilable', 'RCP + adrenalina; busca causas reversibles (5H/5T)'],
    pearl: 'La asistolia no se desfibrila. Confirma que no es FV fina ni cables desconectados antes de etiquetarla.',
  },

  /* ─── BLOQUEOS AV ─────────────────────────────────────────────────── */
  {
    id: 'avb1', name: 'Bloqueo AV de 1.er grado', badge: 'BAV I', category: 'Bloqueos', severity: 'normal',
    hr: 65, gen: 'regular', morph: { pr: 0.30 },
    intervals: { fc: '≈65', pr: '>200 ms', qrs: '<120 ms', qt: 'nl' },
    summary: 'PR alargado y constante. Toda P conduce.',
    findings: ['PR >200 ms, fijo en todos los latidos', 'Cada P va seguida de un QRS', 'Habitualmente benigno y asintomático'],
    pearl: 'PR largo pero constante y sin latidos perdidos = BAV de 1.er grado. No suele requerir tratamiento.',
  },
  {
    id: 'avb2_mobitz1', name: 'BAV 2.º grado Mobitz I (Wenckebach)', badge: 'Mobitz I', category: 'Bloqueos', severity: 'warn',
    hr: 55, gen: 'wenckebach', morph: {},
    intervals: { fc: '≈55', pr: 'creciente', qrs: '<120 ms', qt: 'nl' },
    summary: 'PR se alarga progresivamente hasta que una P no conduce.',
    findings: ['Alargamiento progresivo del PR', 'Hasta que una P se bloquea (QRS ausente)', 'El ciclo se reinicia tras la pausa', 'Suele ser suprahisiano y benigno'],
    pearl: 'PR que "se estira" hasta que cae un QRS = Wenckebach. Generalmente no precisa marcapasos.',
  },
  {
    id: 'avb2_mobitz2', name: 'BAV 2.º grado Mobitz II', badge: 'Mobitz II', category: 'Bloqueos', severity: 'crit',
    hr: 48, gen: 'mobitz2', morph: { qrsWidth: 1.4 },
    intervals: { fc: '≈48', pr: 'fijo', qrs: 'ancho', qt: 'nl' },
    summary: 'PR constante con caídas súbitas de QRS, sin previo aviso.',
    findings: ['PR fijo en los latidos conducidos', 'Caída brusca de algún QRS (P sin QRS)', 'Suele ser infrahisiano → riesgo de BAV completo'],
    pearl: 'Mobitz II es "el malo": riesgo de bloqueo completo y asistolia → marcapasos. No lo confundas con Wenckebach.',
  },
  {
    id: 'avb3', name: 'Bloqueo AV completo (3.er grado)', badge: 'BAV III', category: 'Bloqueos', severity: 'crit',
    hr: 38, gen: 'avblock3', morph: { qrsWidth: 1.8, qrsAxis: -60 },
    intervals: { fc: '30–45', pr: 'disociado', qrs: 'ancho', qt: '—' },
    summary: 'Disociación AV completa: las P y los QRS van cada uno a su ritmo.',
    findings: ['P regulares a su frecuencia (más rápidas)', 'QRS de escape regulares pero lentos (30–45 lpm)', 'Sin relación P-QRS (disociación AV)', 'Escape ventricular → QRS ancho'],
    pearl: 'P y QRS "cada uno a lo suyo" = BAV completo → marcapasos. Marca las P: marchan independientes de los QRS.',
  },
  {
    id: 'pvc', name: 'Extrasístoles ventriculares (bigeminismo)', badge: 'EV', category: 'Bloqueos', severity: 'warn',
    hr: 75, gen: 'bigeminy', morph: {},
    intervals: { fc: '≈75', pr: '—', qrs: 'EV ancha', qt: '—' },
    summary: 'Latido normal alternado con extrasístole ventricular ancha y prematura.',
    findings: ['Complejo prematuro, ancho y bizarro, sin P previa', 'Onda T opuesta al QRS de la extrasístole', 'Pausa compensadora posterior', 'Bigeminismo: se repite cada 2.º latido'],
    pearl: 'QRS ancho, prematuro y aislado con pausa compensadora = extrasístole ventricular. Patrón 1:1 = bigeminismo.',
  },

  /* ─── CONDUCCIÓN INTRAVENTRICULAR ─────────────────────────────────── */
  {
    id: 'rbbb', name: 'Bloqueo de rama derecha', badge: 'BRD', category: 'Conducción', severity: 'warn',
    hr: 72, gen: 'regular', morph: { qrsWidth: 1.9, mods: ['rbbb'] },
    intervals: { fc: '≈72', pr: 'nl', qrs: '>120 ms', qt: 'nl' },
    summary: 'QRS ancho con patrón rSR\' ("orejas de conejo") en V1-V2.',
    findings: ['QRS >120 ms', 'Patrón rSR\' (M) en V1-V2', 'S ancha y empastada en I y V6', 'T negativa en precordiales derechas'],
    pearl: 'QRS ancho + "orejas de conejo" (rSR\') en V1 = BRD. Mira el final del QRS en V1.',
  },
  {
    id: 'lbbb', name: 'Bloqueo de rama izquierda', badge: 'BRI', category: 'Conducción', severity: 'warn',
    hr: 72, gen: 'regular', morph: { qrsWidth: 2.0, mods: ['lbbb'] },
    intervals: { fc: '≈72', pr: 'nl', qrs: '>120 ms', qt: 'nl' },
    summary: 'QRS ancho y mellado en I/V6, con ST-T discordantes.',
    findings: ['QRS >120 ms, R ancha y mellada en I, aVL, V5-V6', 'Ausencia de Q septales', 'QS profundo en V1-V3', 'ST-T opuestos a la deflexión principal (discordancia)'],
    pearl: 'BRI nuevo + dolor torácico = manéjalo como SCACEST. Dificulta el IAM: criterios de Sgarbossa.',
  },
  {
    id: 'lah', name: 'Hemibloqueo anterior izquierdo (eje izq.)', badge: 'HBAI', category: 'Conducción', severity: 'normal',
    hr: 70, gen: 'regular', morph: { qrsAxis: -50 },
    intervals: { fc: '≈70', pr: 'nl', qrs: '<120 ms', eje: '≤ -45°' },
    summary: 'Desviación del eje a la izquierda por bloqueo del fascículo anterior.',
    findings: ['Eje izquierdo (≤ -45°)', 'qR en I y aVL, rS en II, III, aVF (S3>S2)', 'QRS solo levemente ensanchado', 'Causa frecuente de eje izquierdo aislado'],
    pearl: 'Eje muy a la izquierda con QRS casi estrecho: piensa en hemibloqueo anterior. I positivo, aVF negativo.',
  },

  /* ─── HIPERTROFIAS ────────────────────────────────────────────────── */
  {
    id: 'lvh', name: 'Hipertrofia ventricular izquierda', badge: 'HVI', category: 'Hipertrofia', severity: 'warn',
    hr: 70, gen: 'regular', morph: { qrsAxis: 10, mods: ['lvh'] },
    intervals: { fc: '≈70', pr: 'nl', qrs: '<120 ms', qt: 'nl' },
    summary: 'Voltajes de QRS aumentados con patrón de sobrecarga en cara lateral.',
    findings: ['Sokolow: S(V1)+R(V5-6) ≥ 35 mm', 'R alta en I, aVL, V5-V6', 'Sobrecarga: ST descendido + T negativa asimétrica lateral', 'Frecuente en HTA y estenosis aórtica'],
    pearl: 'Voltajes altos + "strain" lateral (ST↓, T neg) = HVI. Índice de Sokolow-Lyon ≥ 35 mm.',
  },
  {
    id: 'rvh', name: 'Hipertrofia ventricular derecha', badge: 'HVD', category: 'Hipertrofia', severity: 'warn',
    hr: 78, gen: 'regular', morph: { qrsAxis: 120, mods: ['rvh'] },
    intervals: { fc: '≈78', pr: 'nl', qrs: '<120 ms', eje: '>+100°' },
    summary: 'R dominante en V1, eje derecho y sobrecarga derecha.',
    findings: ['R > S en V1 (R dominante derecha)', 'Desviación del eje a la derecha', 'S persistente en V5-V6', 'T negativa en precordiales derechas (sobrecarga)'],
    pearl: 'R dominante en V1 + eje derecho = HVD. Piensa en cor pulmonale, HTP o valvulopatía derecha.',
  },

  /* ─── ISQUEMIA / SCA ──────────────────────────────────────────────── */
  {
    id: 'stemi_ant', name: 'SCACEST anterior', badge: 'STEMI ant.', category: 'Isquemia', severity: 'crit',
    hr: 92, gen: 'regular', morph: { mods: ['stemi:anterior'] },
    intervals: { fc: '≈92', pr: 'nl', qrs: '<120 ms', qt: 'nl' },
    summary: 'Elevación del ST en V1-V4: oclusión de la descendente anterior. Código infarto.',
    findings: ['ST elevado convexo en V1-V4 ("lomo de delfín")', 'T hiperaguda y Q de necrosis incipiente', 'Descenso recíproco en cara inferior', 'Oclusión de la DA → reperfusión urgente'],
    pearl: 'ST elevado en ≥2 derivaciones contiguas de V1-V4 = SCACEST anterior (DA). El tiempo es músculo.',
  },
  {
    id: 'stemi_inf', name: 'SCACEST inferior', badge: 'STEMI inf.', category: 'Isquemia', severity: 'crit',
    hr: 58, gen: 'regular', morph: { mods: ['stemi:inferior'] },
    intervals: { fc: '≈58', pr: 'nl', qrs: '<120 ms', qt: 'nl' },
    summary: 'Elevación del ST en II, III y aVF: oclusión de la coronaria derecha (habitual).',
    findings: ['ST elevado en II, III, aVF (III > II sugiere CD)', 'Descenso recíproco en I y aVL', 'Frecuente bradicardia/bloqueo AV asociado', 'Valora derivaciones derechas (V4R) por IAM de VD'],
    pearl: 'ST elevado inferior + bradicardia = CD. Pide V4R: si hay IAM de VD, cuidado con los nitratos (precarga-dependiente).',
  },
  {
    id: 'stemi_lat', name: 'SCACEST lateral', badge: 'STEMI lat.', category: 'Isquemia', severity: 'crit',
    hr: 88, gen: 'regular', morph: { mods: ['stemi:lateral'] },
    intervals: { fc: '≈88', pr: 'nl', qrs: '<120 ms', qt: 'nl' },
    summary: 'Elevación del ST en I, aVL, V5-V6: territorio lateral (circunfleja).',
    findings: ['ST elevado en I, aVL, V5-V6', 'Descenso recíproco en cara inferior', 'Suele deberse a la circunfleja o diagonal', 'Buscar afectación posterior asociada'],
    pearl: 'Elevación en I-aVL-V5-V6 = cara lateral (circunfleja). Revisa siempre las recíprocas inferiores.',
  },
  {
    id: 'nstemi', name: 'SCASEST / isquemia subendocárdica', badge: 'SCASEST', category: 'Isquemia', severity: 'warn',
    hr: 90, gen: 'regular', morph: { mods: ['ischemia:lateral'] },
    intervals: { fc: '≈90', pr: 'nl', qrs: '<120 ms', qt: 'nl' },
    summary: 'Descenso del ST y/o T invertidas simétricas, sin elevación persistente.',
    findings: ['Descenso del ST horizontal o descendente', 'T negativas, simétricas y profundas', 'No hay elevación persistente del ST', 'Manejo: SCASEST (antiagregación, estratificación)'],
    pearl: 'Descenso del ST + T negativas simétricas = isquemia subendocárdica. Diferénciala del SCACEST (no reperfusión inmediata sistemática).',
  },
  {
    id: 'wellens', name: 'Síndrome de Wellens', badge: 'Wellens', category: 'Isquemia', severity: 'crit',
    hr: 74, gen: 'regular', morph: { mods: ['wellens'] },
    intervals: { fc: '≈74', pr: 'nl', qrs: '<120 ms', qt: 'nl' },
    summary: 'T bifásicas o negativas profundas en V2-V4: estenosis crítica de la DA proximal.',
    findings: ['T negativas profundas / bifásicas en V2-V4', 'Sin pérdida significativa de R ni elevación del ST', 'Aparece con dolor resuelto', 'Alto riesgo de IAM anterior extenso'],
    pearl: 'T negativas profundas en precordiales con dolor resuelto = Wellens (DA crítica). No hagas prueba de esfuerzo: coronariografía.',
  },

  /* ─── PERICARDIO ──────────────────────────────────────────────────── */
  {
    id: 'pericarditis', name: 'Pericarditis aguda', badge: 'Pericard.', category: 'Isquemia', severity: 'warn',
    hr: 96, gen: 'regular', morph: { mods: ['pericarditis'] },
    intervals: { fc: '≈96', pr: 'PR↓', qrs: '<120 ms', qt: 'nl' },
    summary: 'Elevación cóncava difusa del ST con descenso del PR, sin distribución de territorio.',
    findings: ['Elevación del ST cóncava y difusa (no por territorios)', 'Descenso del segmento PR (elevación en aVR)', 'Sin recíprocas ni ondas Q', 'Suele haber taquicardia sinusal'],
    pearl: 'ST elevado difuso + PR descendido, sin recíprocas ni Q = pericarditis. La clave frente al SCACEST es la difusión y el PR.',
  },

  /* ─── ELECTROLITOS / TÓXICOS ──────────────────────────────────────── */
  {
    id: 'hyperk', name: 'Hiperpotasemia', badge: 'K⁺ ↑', category: 'Metabólico', severity: 'crit',
    hr: 60, gen: 'regular', morph: { tWidth: 0.55, qrsWidth: 1.5, mods: ['hyperk'] },
    intervals: { fc: '≈60', pr: '↑', qrs: 'ancho', qt: 'nl' },
    summary: 'T picudas y estrechas; en grados avanzados, P aplanada y QRS ancho.',
    findings: ['T altas, picudas y simétricas ("tienda de campaña")', 'Aplanamiento / desaparición de la P', 'Ensanchamiento progresivo del QRS', 'Puede evolucionar a onda sinusoidal y paro'],
    pearl: 'T picudas → busca hiperK. Si hay cambios ECG: gluconato cálcico (estabiliza membrana) + insulina/glucosa.',
  },
  {
    id: 'hypok', name: 'Hipopotasemia', badge: 'K⁺ ↓', category: 'Metabólico', severity: 'warn',
    hr: 78, gen: 'regular', morph: { qtScale: 1.15, mods: ['hypok'] },
    intervals: { fc: '≈78', pr: 'nl', qrs: '<120 ms', qt: 'QU largo' },
    summary: 'T aplanada, onda U prominente y ligero descenso del ST.',
    findings: ['Ondas U prominentes (sobre todo precordiales)', 'T aplanada o invertida, ST descendido', 'QT-U alargado → riesgo de torsade', 'Predispone a arritmias e intoxicación digitálica'],
    pearl: 'T plana + U prominente = hipoK. Alarga el QU y predispone a torsade; corrige también el Mg.',
  },
  {
    id: 'digoxin', name: 'Impregnación digitálica', badge: 'Digital', category: 'Metabólico', severity: 'normal',
    hr: 62, gen: 'regular', morph: { qtScale: 0.85, mods: ['digoxin'] },
    intervals: { fc: '≈62', pr: '↑', qrs: '<120 ms', qt: '↓' },
    summary: 'Cazoleta digitálica: ST descendido cóncavo ("bigote de Salvador Dalí") con QT corto.',
    findings: ['ST descendido en cazoleta en cara lateral', 'QT acortado', 'PR alargado (efecto vagal)', 'No confundir efecto (normal) con intoxicación'],
    pearl: 'Cazoleta digitálica (ST en "bigote de Dalí") = efecto, no toxicidad. La intoxicación da arritmias con bloqueo.',
  },

  /* ─── CANALOPATÍAS / OTROS ────────────────────────────────────────── */
  {
    id: 'brugada', name: 'Síndrome de Brugada (tipo 1)', badge: 'Brugada', category: 'Conducción', severity: 'crit',
    hr: 70, gen: 'regular', morph: { qrsWidth: 1.2, mods: ['brugada'] },
    intervals: { fc: '≈70', pr: 'nl', qrs: 'lím.', qt: 'nl' },
    summary: 'Elevación "coved" (convexa) del ST ≥2 mm en V1-V2 con T negativa.',
    findings: ['Elevación descendente "en aleta de tiburón" en V1-V2', 'Patrón tipo 1 (coved) diagnóstico', 'Riesgo de muerte súbita por FV', 'Desenmascarado por fiebre o fármacos'],
    pearl: 'Coved en V1-V2 = Brugada tipo 1. Riesgo de muerte súbita: valora DAI. Cuidado con la fiebre.',
  },
  {
    id: 'longqt', name: 'QT largo', badge: 'QT largo', category: 'Metabólico', severity: 'warn',
    hr: 68, gen: 'regular', morph: { qtScale: 1.5, tWidth: 1.4 },
    intervals: { fc: '≈68', pr: 'nl', qrs: '<120 ms', qt: '↑↑ (QTc>480)' },
    summary: 'Intervalo QT prolongado: sustrato para torsade de pointes.',
    findings: ['QTc prolongado (>460–480 ms)', 'T ancha y de aparición tardía', 'Congénito o adquirido (fármacos, hipoK/hipoMg/hipoCa)', 'Riesgo de torsade y muerte súbita'],
    pearl: 'Mide siempre el QT: un QTc largo predispone a torsade. Revisa fármacos y electrolitos.',
  },
  {
    id: 'tamponade', name: 'Derrame pericárdico / taponamiento', badge: 'Alternans', category: 'Metabólico', severity: 'crit',
    hr: 110, gen: 'regular', morph: { mods: ['lowvoltage'] },
    intervals: { fc: '≈110', pr: 'nl', qrs: '<120 ms', qt: 'nl' },
    summary: 'Bajo voltaje generalizado (± alternancia eléctrica) con taquicardia sinusal.',
    findings: ['Bajo voltaje del QRS en todas las derivaciones', 'Alternancia eléctrica (amplitud variable latido a latido)', 'Taquicardia sinusal', 'Contexto de derrame pericárdico'],
    pearl: 'Bajo voltaje + taquicardia + alternancia eléctrica = derrame/taponamiento. Tríada de Beck en la clínica.',
  },
];

/* ─── Sinónimos para el modo examen ─────────────────────────────────── */
const ALIASES = {
  sinus: ['rsn', 'normal', 'ritmo sinusal'],
  sinus_brady: ['bradicardia', 'bradi'],
  sinus_tachy: ['taquicardia', 'taqui', 'taquicardia sinusal'],
  afib: ['fa', 'fibrilacion auricular', 'acxfa', 'acfa', 'fibrilacion'],
  aflutter: ['flutter', 'aleteo auricular', 'dientes de sierra'],
  svt: ['tpsv', 'tsv', 'taquicardia supraventricular', 'paroxistica', 'avnrt'],
  wpw: ['wpw', 'wolff parkinson white', 'preexcitacion', 'onda delta', 'via accesoria'],
  vtach: ['tv', 'taquicardia ventricular', 'qrs ancho monomorfa'],
  torsades: ['tdp', 'torsade', 'torsada', 'torsades de pointes', 'tv polimorfa'],
  vfib: ['fv', 'fibrilacion ventricular'],
  asystole: ['asistolia', 'linea plana', 'parada', 'paro'],
  avb1: ['bav 1', 'bloqueo av primer grado', 'pr largo', 'primer grado'],
  avb2_mobitz1: ['wenckebach', 'mobitz 1', 'mobitz i', 'bav 2 mobitz 1'],
  avb2_mobitz2: ['mobitz 2', 'mobitz ii', 'bav 2 mobitz 2'],
  avb3: ['bav completo', 'bav 3', 'bloqueo completo', 'disociacion av', 'tercer grado'],
  pvc: ['ev', 'extrasistole', 'extrasistoles', 'bigeminismo', 'bigeminia', 'cvp'],
  rbbb: ['brd', 'bloqueo rama derecha', 'rsr', 'orejas de conejo'],
  lbbb: ['bri', 'bloqueo rama izquierda'],
  lah: ['hbai', 'hemibloqueo anterior', 'eje izquierdo', 'hemibloqueo'],
  lvh: ['hvi', 'hipertrofia ventricular izquierda', 'sokolow', 'strain'],
  rvh: ['hvd', 'hipertrofia ventricular derecha', 'eje derecho', 'r dominante v1'],
  stemi_ant: ['iam anterior', 'scacest anterior', 'infarto anterior', 'da', 'descendente anterior'],
  stemi_inf: ['iam inferior', 'scacest inferior', 'infarto inferior', 'coronaria derecha', 'cd'],
  stemi_lat: ['iam lateral', 'scacest lateral', 'infarto lateral', 'circunfleja'],
  nstemi: ['scasest', 'isquemia', 'descenso st', 't invertida', 'angina', 'subendocardica'],
  wellens: ['wellens', 'da critica', 't bifasica'],
  pericarditis: ['pericarditis', 'pr descendido', 'elevacion difusa'],
  hyperk: ['hiperpotasemia', 'hiperkalemia', 't picuda', 'potasio alto', 'k alto'],
  hypok: ['hipopotasemia', 'hipokalemia', 'onda u', 'potasio bajo', 'k bajo'],
  digoxin: ['digital', 'digoxina', 'cazoleta', 'impregnacion digitalica'],
  brugada: ['brugada', 'coved', 'aleta de tiburon'],
  longqt: ['qt largo', 'qtc largo', 'sindrome qt largo'],
  tamponade: ['taponamiento', 'derrame pericardico', 'alternancia electrica', 'bajo voltaje'],
};
PATTERNS.forEach(p => { p.search = [p.name, p.badge, ...(ALIASES[p.id] || [])]; });

export const PATTERN_BY_ID = Object.fromEntries(PATTERNS.map(p => [p.id, p]));

export const CATEGORIES = [
  'Normal', 'Taquiarritmias', 'Bloqueos', 'Conducción', 'Hipertrofia', 'Isquemia', 'Metabólico', 'Paro',
];
