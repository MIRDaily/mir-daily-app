/* ════════════════════════════════════════════════════════════════════════
   MIRElectro-Pro — leads.js
   Modelo fisiológico de las 12 derivaciones.

   La clave del realismo de un ECG de 12 derivaciones es que las ondas de cada
   derivación NO son independientes: son la proyección del mismo dipolo cardíaco
   sobre distintos ejes. Aquí:

   1) Las 6 derivaciones de miembros se DERIVAN de un eje eléctrico (proyección
      vectorial sobre los ejes de Einthoven/Goldberger). Cambiar el eje ⇒ cambian
      todas a la vez de forma coherente (I/II/III/aVR/aVL/aVF).
   2) Las 6 precordiales parten de una tabla "normal" (progresión de R de V1→V6)
      que las transformaciones patológicas modifican.
   3) Cada patrón aplica una lista de "mods" (BRD, BRI, HVI, SCACEST anterior…)
      que mutan la morfología de forma localizada y fiel a la clínica.

   Voltajes en mV. Ángulos en grados. R centrada en τ=0.
═══════════════════════════════════════════════════════════════════════════ */

// Onda por derivación. Todas las amplitudes en mV; j = nivel del segmento ST
// en el punto J; prDep = desnivel del segmento PR; u = onda U.
function wave(o = {}) {
  return {
    p: 0, q: 0, r: 0, s: 0, rp: 0, // R' (segundo pico, p.ej. BRD)
    t: 0, j: 0, u: 0, prDep: 0,
    delta: 0,                       // onda delta (preexcitación)
    notch: 0,                       // muesca en la R (BRI)
    tSym: 0,                        // 0 = T asimétrica normal; 1 = simétrica (isquemia)
    ...o,
  };
}

const LIMB_ANGLES = { I: 0, II: 60, III: 120, aVR: -150, aVL: -30, aVF: 90 };
const PRECORDIAL = ['V1', 'V2', 'V3', 'V4', 'V5', 'V6'];
export const LEAD_ORDER = ['I', 'II', 'III', 'aVR', 'aVL', 'aVF', ...PRECORDIAL];

const deg = Math.PI / 180;
const proj = (leadAngle, vecAxis) => Math.cos((leadAngle - vecAxis) * deg);

/* ─── Derivaciones de miembros a partir del eje ─────────────────────────
   qrsMag  : magnitud del vector QRS (mV, referida a la derivación paralela)
   qrsAxis : eje eléctrico del QRS (º).  Normal 30–75; LAD < -30; RAD > +100.
   pAxis/pMag, tAxis/tMag idem para P y T.
*/
function limbLeads({ qrsMag, qrsAxis, pMag, pAxis, tMag, tAxis }) {
  const out = {};
  for (const [name, a] of Object.entries(LIMB_ANGLES)) {
    const net = qrsMag * proj(a, qrsAxis);      // deflexión neta del QRS
    const pv = pMag * proj(a, pAxis);
    const tv = tMag * proj(a, tAxis);
    out[name] = wave({
      p: pv,
      // pequeña q septal solo donde la R es claramente dominante (I, aVL, aVF…)
      q: net > 0.4 ? -0.05 : 0,
      r: net > 0 ? net + 0.06 : 0.06,
      s: net < 0 ? net - 0.05 : -0.09,
      t: tv,
    });
  }
  return out;
}

/* ─── Precordiales normales (progresión de R fisiológica) ───────────────
   V1: rS (R pequeña, S profunda) → transición en V3-V4 → V5-V6 qR dominante.
*/
function precordialNormal() {
  return {
    V1: wave({ p: 0.05, r: 0.20, s: -0.95, t: -0.05 }),
    V2: wave({ p: 0.08, r: 0.40, s: -1.35, t: 0.35 }),
    V3: wave({ p: 0.08, r: 0.70, s: -0.95, t: 0.45 }),
    V4: wave({ p: 0.08, q: -0.05, r: 1.35, s: -0.50, t: 0.50 }),
    V5: wave({ p: 0.08, q: -0.08, r: 1.30, s: -0.25, t: 0.38 }),
    V6: wave({ p: 0.06, q: -0.06, r: 1.00, s: -0.12, t: 0.28 }),
  };
}

/* Construye la tabla base de 12 derivaciones para un patrón (antes de mods). */
export function baseLeads(cfg = {}) {
  const c = {
    qrsMag: 1.2, qrsAxis: 60,
    pMag: 0.15, pAxis: 55,
    tMag: 0.35, tAxis: 45,
    ...cfg,
  };
  return { ...limbLeads(c), ...precordialNormal() };
}

/* ════════════════════════════════════════════════════════════════════
   TRANSFORMACIONES PATOLÓGICAS
   Cada una recibe la tabla L (nombre→onda) y la muta.
═══════════════════════════════════════════════════════════════════════ */
const each = (L, names, fn) => names.forEach(n => L[n] && fn(L[n], n));
const all = (L, fn) => Object.entries(L).forEach(([n, w]) => fn(w, n));

// Territorios coronarios para SCACEST (elevación) y sus recíprocas (descenso).
const TERRITORY = {
  anterior:      { up: ['V1', 'V2', 'V3', 'V4'], recip: ['II', 'III', 'aVF'] },
  anteroseptal:  { up: ['V1', 'V2', 'V3'],        recip: ['II', 'III', 'aVF'] },
  lateral:       { up: ['I', 'aVL', 'V5', 'V6'],  recip: ['III', 'aVF'] },
  inferior:      { up: ['II', 'III', 'aVF'],      recip: ['I', 'aVL'] },
  extenso:       { up: ['I', 'aVL', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6'], recip: ['III'] },
};

export const MODS = {
  /* ── Eje ── (se aplica recomputando miembros; aquí solo marca, el motor
     ya recibe qrsAxis en la config base, así que estos son atajos visuales) */

  /* ── Hipertrofia ventricular izquierda + sobrecarga ── */
  lvh(L) {
    each(L, ['V1', 'V2'], w => { w.s *= 1.7; });
    each(L, ['V5', 'V6'], w => { w.r *= 1.6; });
    each(L, ['I', 'aVL'], w => { w.r *= 1.4; });
    // patrón de sobrecarga: ST descendido y T negativa asimétrica en cara lateral
    each(L, ['I', 'aVL', 'V5', 'V6'], w => { w.j = -0.1; w.t = -Math.abs(w.t) * 0.9; });
  },

  /* ── Hipertrofia ventricular derecha ── */
  rvh(L) {
    L.V1.r = 1.1; L.V1.s = -0.2; L.V1.t = -0.25;   // R dominante en V1
    L.V2.r = 0.9; L.V2.s = -0.5; L.V2.t = -0.2;
    each(L, ['V5', 'V6'], w => { w.s *= 1.6; w.r *= 0.8; });
  },

  /* ── Bloqueo de rama derecha ── (QRS ancho lo pone el patrón) */
  rbbb(L) {
    L.V1.r = 0.25; L.V1.s = -0.15; L.V1.rp = 0.9;   // rSR' "orejas de conejo"
    L.V2.r = 0.30; L.V2.s = -0.30; L.V2.rp = 0.6;
    each(L, ['I', 'aVL', 'V5', 'V6'], w => { w.s = Math.min(w.s, -0.35); }); // S ancha
    each(L, ['V1', 'V2', 'V3'], w => { w.t = -Math.abs(w.t || 0.2); });      // T neg dcha
  },

  /* ── Bloqueo de rama izquierda ── */
  lbbb(L) {
    each(L, ['V1', 'V2', 'V3'], w => { w.r = 0.05; w.s = -1.5; w.rp = 0; w.q = 0; });
    each(L, ['I', 'aVL', 'V5', 'V6'], w => { w.q = 0; w.r = Math.max(w.r, 1.4); w.s = -0.05; w.notch = 1; });
    // discordancia apropiada: ST/T opuestos a la deflexión dominante
    all(L, (w) => {
      const dom = (w.r + w.rp) + w.s;      // signo de la deflexión principal
      if (dom > 0.3) { w.j = -0.1; w.t = -Math.abs(w.t || 0.3) - 0.1; }
      else if (dom < -0.3) { w.j = 0.12; w.t = Math.abs(w.t) + 0.2; }
    });
  },

  /* ── SCACEST (IAM con elevación del ST) por territorio ── */
  stemi(L, territory = 'anterior') {
    const T = TERRITORY[territory] || TERRITORY.anterior;
    each(L, T.up, w => {
      w.j = 0.32;                    // elevación del punto J (lomo de delfín)
      w.t = Math.abs(w.t || 0.3) + 0.35; // T hiperaguda
      w.q = Math.min(w.q, -0.25);    // onda Q de necrosis incipiente
      w.r *= 0.55;
    });
    each(L, T.recip, w => { w.j = -0.14; w.t = -Math.abs(w.t || 0.2); }); // recíproco
  },

  /* ── SCASEST / isquemia subendocárdica ── */
  ischemia(L, territory = 'lateral') {
    const leads = (TERRITORY[territory] || TERRITORY.lateral).up;
    each(L, leads, w => { w.j = -0.18; w.t = -0.35; w.tSym = 1; }); // descenso ST + T neg simétrica
  },

  /* ── Wellens (T bifásicas/negativas profundas V2-V4, DA crítica) ── */
  wellens(L) {
    each(L, ['V2', 'V3', 'V4'], w => { w.t = -0.55; w.tSym = 1; w.j = 0.02; });
  },

  /* ── Pericarditis aguda: elevación cóncava difusa + descenso del PR ── */
  pericarditis(L) {
    all(L, (w, n) => {
      if (n === 'aVR' || n === 'V1') { w.j = -0.05; w.prDep = 0.05; }
      else { w.j = 0.12; w.prDep = -0.06; }
    });
  },

  /* ── Hiperpotasemia: T picudas simétricas, P aplanada ── */
  hyperk(L) {
    all(L, (w) => {
      if (Math.abs(w.t) > 0.02) { w.t = Math.sign(w.t || 1) * (Math.abs(w.t) + 0.5); w.tSym = 1; }
      w.p *= 0.2;   // P aplanada / ausente
    });
  },

  /* ── Hipopotasemia: T aplanada, onda U prominente, ST descendido ── */
  hypok(L) {
    all(L, (w) => { w.t *= 0.4; w.u = 0.22 * Math.sign(w.r || 1); w.j = -0.06; });
  },

  /* ── Brugada tipo 1: elevación "coved" en V1-V2 con T negativa ── */
  brugada(L) {
    each(L, ['V1', 'V2'], w => { w.r = 0.2; w.rp = 0.35; w.j = 0.28; w.t = -0.3; w.tSym = 1; });
  },

  /* ── WPW: onda delta difusa (el PR corto lo pone el patrón) ── */
  wpw(L) {
    all(L, (w) => { w.delta = 0.25 * Math.sign(w.r + 0.01); });
  },

  /* ── Bajo voltaje (derrame/tamponade) ── */
  lowvoltage(L) {
    all(L, (w) => { w.q *= 0.4; w.r *= 0.4; w.s *= 0.4; w.t *= 0.4; });
  },

  /* ── Crecimiento auricular ── */
  pmitrale(L) { each(L, ['II'], w => { w.p = 0.16; }); },   // (la muesca/anchura la da el motor)
  ppulmonale(L) { each(L, ['II', 'III', 'aVF'], w => { w.p = 0.30; }); },

  /* ── Impregnación digitálica: cazoleta (ST descendido cóncavo) lateral ── */
  digoxin(L) { each(L, ['V5', 'V6', 'I'], w => { w.j = -0.12; w.t = -0.1; }); },
};

/* Aplica una lista de mods ('stemi:anterior', 'rbbb', …) sobre la tabla. */
export function applyMods(L, mods = []) {
  for (const m of mods) {
    const [fn, arg] = m.split(':');
    if (MODS[fn]) MODS[fn](L, arg);
  }
  return L;
}
