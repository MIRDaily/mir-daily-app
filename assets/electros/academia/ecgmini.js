/* ════════════════════════════════════════════════════════════════════════
   MIRElectro Academia — ecgmini.js
   Piezas compartidas para las animaciones didácticas:
     · PHASES        fases del ciclo cardíaco (impulso ↔ onda del ECG).
     · beatVoltage   voltaje (mV) de un latido "de libro" en función de la
                     fracción del ciclo f ∈ [0,1].
     · beatPathSVG   genera el trazo de un latido para ilustraciones SVG.
     · EcgTracer     dibuja UN latido progresivamente sobre canvas, sincronizado
                     con f, con papel milimetrado y "bolígrafo" en la punta.
═══════════════════════════════════════════════════════════════════════════ */

// Cada fase mapea una parte de la mecánica eléctrica con su huella en el ECG.
export const PHASES = [
  { id: 'sa',    t0: 0.00, t1: 0.05, struct: 'sa',    wave: 'P',  color: '#D4978C',
    title: 'Nodo sinusal', text: 'El marcapasos fisiológico dispara el impulso.' },
  { id: 'atria', t0: 0.05, t1: 0.13, struct: 'atria', wave: 'P',  color: '#D4978C',
    title: 'Despolarización auricular', text: 'El impulso recorre las aurículas → onda P.' },
  { id: 'av',    t0: 0.13, t1: 0.21, struct: 'av',    wave: 'PR', color: '#C9A24A',
    title: 'Retraso en el nodo AV', text: 'Pausa fisiológica → segmento PR (línea isoeléctrica).' },
  { id: 'his',   t0: 0.21, t1: 0.24, struct: 'his',   wave: 'QRS', color: '#7CA3C9',
    title: 'Haz de His y ramas', text: 'El impulso baja rápido por el sistema His-Purkinje.' },
  { id: 'vent',  t0: 0.24, t1: 0.31, struct: 'vent',  wave: 'QRS', color: '#7CA3C9',
    title: 'Despolarización ventricular', text: 'Los ventrículos se activan → complejo QRS.' },
  { id: 'st',    t0: 0.31, t1: 0.44, struct: 'vent',  wave: 'ST', color: '#8BA888',
    title: 'Meseta', text: 'Ventrículos despolarizados y contraídos → segmento ST.' },
  { id: 'trep',  t0: 0.44, t1: 0.64, struct: 'repol', wave: 'T',  color: '#8BA888',
    title: 'Repolarización ventricular', text: 'Los ventrículos se recuperan → onda T.' },
  { id: 'dias',  t0: 0.64, t1: 1.00, struct: 'none',  wave: '—',  color: '#A8A4A0',
    title: 'Diástole eléctrica', text: 'Reposo: el corazón se llena y espera el próximo impulso.' },
];

export function phaseAt(f) {
  const x = ((f % 1) + 1) % 1;
  return PHASES.find(p => x >= p.t0 && x < p.t1) || PHASES[PHASES.length - 1];
}

const gauss = (t, c, a, w) => a * Math.exp(-0.5 * ((t - c) / w) ** 2);

/* Voltaje (mV) de un latido de referencia (tipo II) según la fracción f. */
export function beatVoltage(f) {
  const x = ((f % 1) + 1) % 1;
  let v = 0;
  v += gauss(x, 0.090, 0.15, 0.020);   // P
  v += gauss(x, 0.250, -0.08, 0.008);  // Q
  v += gauss(x, 0.268, 1.20, 0.010);   // R
  v += gauss(x, 0.288, -0.25, 0.010);  // S
  v += gauss(x, 0.520, 0.30, 0.040);   // T
  return v;
}

/* Puntos clave (fracción f) para etiquetar ondas en ilustraciones. */
export const WAVE_MARKS = [
  { id: 'P',  f: 0.090, label: 'P' },
  { id: 'QRS', f: 0.268, label: 'QRS' },
  { id: 'T',  f: 0.520, label: 'T' },
];

/* Genera el path SVG de un latido dentro de un rectángulo dado. */
export function beatPathSVG(x0, y0, w, h, { fStart = 0, fEnd = 1, samples = 240 } = {}) {
  const base = y0 + h * 0.62, scale = h * 0.42;
  let d = '';
  for (let i = 0; i <= samples; i++) {
    const f = fStart + (fEnd - fStart) * (i / samples);
    const x = x0 + w * (i / samples);
    const y = base - beatVoltage(f) * scale;
    d += (i ? 'L' : 'M') + x.toFixed(1) + ' ' + y.toFixed(1) + ' ';
  }
  return { d, xOf: f => x0 + w * ((f - fStart) / (fEnd - fStart)), base, scale };
}

/* ─── Trazador progresivo sobre canvas ─────────────────────────────────── */
export class EcgTracer {
  constructor(gridCanvas, traceCanvas) {
    this.grid = gridCanvas; this.trace = traceCanvas;
    this.gctx = gridCanvas.getContext('2d');
    this.tctx = traceCanvas.getContext('2d');
    this.marginX = 0.06;      // margen izq/dcha como fracción del ancho
    this.pen = true;
  }

  resize() {
    const dpr = window.devicePixelRatio || 1;
    for (const c of [this.grid, this.trace]) {
      const r = c.getBoundingClientRect();
      c.width = Math.max(1, Math.round(r.width * dpr));
      c.height = Math.max(1, Math.round(r.height * dpr));
      c.getContext('2d').setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    const r = this.grid.getBoundingClientRect();
    this.W = r.width; this.H = r.height;
    this.mm = this.H / 26;    // ~26 mm de alto visibles
    this._drawGrid();
  }

  _drawGrid() {
    const ctx = this.gctx, W = this.W, H = this.H, mm = this.mm;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = '#FFF7F4'; ctx.fillRect(0, 0, W, H);
    ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(212,151,140,0.22)'; ctx.beginPath();
    for (let x = 0; x <= W; x += mm) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
    for (let y = 0; y <= H; y += mm) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
    ctx.stroke();
    ctx.lineWidth = 1.3; ctx.strokeStyle = 'rgba(212,151,140,0.5)'; ctx.beginPath();
    for (let x = 0; x <= W; x += mm * 5) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
    for (let y = 0; y <= H; y += mm * 5) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
    ctx.stroke();
  }

  _x(f) { const m = this.W * this.marginX; return m + (this.W - 2 * m) * f; }
  _y(mv) { return this.H * 0.60 - mv * (this.mm * 10); }

  /* Dibuja el latido desde 0 hasta f. */
  render(f) {
    if (!this.W) return;
    const ctx = this.tctx; ctx.clearRect(0, 0, this.W, this.H);
    ctx.lineWidth = 2.4; ctx.strokeStyle = '#241c1a'; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
    const steps = Math.max(2, Math.floor(240 * f));
    ctx.beginPath();
    for (let i = 0; i <= steps; i++) {
      const ff = f * (i / steps);
      const x = this._x(ff), y = this._y(beatVoltage(ff));
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    }
    ctx.stroke();
    if (this.pen && f > 0 && f < 1) {
      const x = this._x(f), y = this._y(beatVoltage(f));
      ctx.beginPath(); ctx.fillStyle = '#B87A6F';
      ctx.arc(x, y, 3.6, 0, 7); ctx.fill();
      ctx.beginPath(); ctx.strokeStyle = 'rgba(184,122,111,0.35)'; ctx.lineWidth = 1.2;
      ctx.moveTo(x, 0); ctx.lineTo(x, this.H); ctx.stroke();
    }
  }

  clear() { if (this.W) this.tctx.clearRect(0, 0, this.W, this.H); }
}
