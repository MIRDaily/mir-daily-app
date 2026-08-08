/* ════════════════════════════════════════════════════════════════════════
   MIRElectro-Pro — monitor.js
   Renderizadores sobre <canvas>:
     · RhythmMonitor : monitor de cabecera, barre una derivación en tiempo real.
     · TwelveLead    : ECG completo de 12 derivaciones (formato impresión 4×3 +
                       tira de ritmo), como un electro de verdad.
   Papel: 25 mm/s, 10 mm/mV, cuadrícula 1 mm / 5 mm.
═══════════════════════════════════════════════════════════════════════════ */
import { FS, DUR } from './ecg-core.js';
import { LEAD_ORDER } from './leads.js';

const PAPER = '#FFF7F4';
const FINE = 'rgba(212,151,140,0.22)';
const BOLD = 'rgba(212,151,140,0.52)';
const INK = '#1c1512';

function drawGrid(ctx, W, H, mm) {
  ctx.fillStyle = PAPER;
  ctx.fillRect(0, 0, W, H);
  ctx.lineWidth = 1; ctx.strokeStyle = FINE; ctx.beginPath();
  for (let x = 0; x <= W; x += mm) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
  for (let y = 0; y <= H; y += mm) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
  ctx.stroke();
  ctx.lineWidth = 1.3; ctx.strokeStyle = BOLD; ctx.beginPath();
  for (let x = 0; x <= W; x += mm * 5) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
  for (let y = 0; y <= H; y += mm * 5) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
  ctx.stroke();
}

/* ════════════════════════════════════════════════════════════════════
   Monitor de barrido en tiempo real (una derivación)
═══════════════════════════════════════════════════════════════════════ */
export class RhythmMonitor {
  constructor(gridCanvas, traceCanvas, opts = {}) {
    this.grid = gridCanvas; this.trace = traceCanvas;
    this.gctx = gridCanvas.getContext('2d');
    this.tctx = traceCanvas.getContext('2d');
    this.pxPerMm = opts.pxPerMm || 6;
    this.mmPerSec = 25; this.mmPerMv = 10;
    this.timeScale = 1;
    this.lead = opts.lead || 'II';
    this.buffer = null; this.beats = []; this.fs = FS; this.dur = DUR;
    this.tSim = 0; this.lastX = 0; this.running = false;
    this.onBeat = opts.onBeat || null;
    this._lastBeatIdx = -1; this._raf = null; this._prevTs = 0;
  }

  setLead(name) { if (this.synth) this.buffer = this.synth.leads[name]; this.lead = name; if (this.W) this.tctx.clearRect(0, 0, this.W, this.H); this.lastX = 0; }

  resize() {
    const dpr = window.devicePixelRatio || 1;
    for (const c of [this.grid, this.trace]) {
      const r = c.getBoundingClientRect();
      c.width = Math.round(r.width * dpr); c.height = Math.round(r.height * dpr);
      c.getContext('2d').setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    const r = this.grid.getBoundingClientRect();
    this.W = r.width; this.H = r.height;
    drawGrid(this.gctx, this.W, this.H, this.pxPerMm);
    this.tctx.clearRect(0, 0, this.W, this.H); this.lastX = 0;
  }

  setPattern(synth) {
    this.synth = synth; this.buffer = synth.leads[this.lead];
    this.fs = synth.fs; this.dur = synth.dur; this.beats = synth.beats || [];
    this.tSim = 0; this.lastX = 0; this._lastBeatIdx = -1;
    if (this.W) this.tctx.clearRect(0, 0, this.W, this.H);
  }

  _volt(t) { const i = Math.floor((((t % this.dur) + this.dur) % this.dur) * this.fs); return this.buffer[i] || 0; }
  _y(mv) { return this.H / 2 - mv * this.mmPerMv * this.pxPerMm; }

  start() {
    if (this.running) return; this.running = true; this._prevTs = performance.now();
    const loop = (ts) => { if (!this.running) return; const dt = Math.min(0.05, (ts - this._prevTs) / 1000); this._prevTs = ts; this._step(dt); this._raf = requestAnimationFrame(loop); };
    this._raf = requestAnimationFrame(loop);
  }
  stop() { this.running = false; if (this._raf) cancelAnimationFrame(this._raf); }

  _step(dt) {
    if (!this.buffer || !this.W) return;
    const pxPerSec = this.mmPerSec * this.pxPerMm;
    const tPrev = this.tSim; this.tSim += dt * this.timeScale;
    const W = this.W, ctx = this.tctx;
    const xNow = (this.tSim * pxPerSec) % W;
    ctx.lineWidth = 1.8; ctx.strokeStyle = INK; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
    const span = this.tSim - tPrev;
    const steps = Math.max(2, Math.ceil(span * pxPerSec));
    ctx.beginPath(); let started = false;
    for (let s = 0; s <= steps; s++) {
      const t = tPrev + span * (s / steps);
      const x = (t * pxPerSec) % W, y = this._y(this._volt(t));
      if (s === 0 || x < this.lastX) { ctx.stroke(); ctx.beginPath(); started = false; }
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    ctx.stroke();
    const eraseW = this.pxPerMm * 3;
    ctx.clearRect(xNow + 1, 0, eraseW, this.H);
    if (xNow + 1 + eraseW > W) ctx.clearRect(0, 0, xNow + 1 + eraseW - W, this.H);
    this.lastX = xNow;
    if (this.onBeat && this.beats.length) {
      const tb = this.tSim % this.dur, tbPrev = tPrev % this.dur;
      for (let k = 0; k < this.beats.length; k++) {
        const bt = this.beats[k];
        const crossed = (tbPrev <= bt && tb >= bt) || (tb < tbPrev && (bt >= tbPrev || bt <= tb));
        if (crossed && k !== this._lastBeatIdx) { this._lastBeatIdx = k; this.onBeat(); break; }
      }
    }
  }
}

/* ════════════════════════════════════════════════════════════════════
   ECG de 12 derivaciones (estático, formato impresión)
   Disposición estándar 4 columnas × 3 filas:
       I    aVR   V1   V4
       II   aVL   V2   V5
       III  aVF   V3   V6
   + tira de ritmo (II) a lo ancho.  Cada panel muestra 2,5 s.
═══════════════════════════════════════════════════════════════════════ */
const GRID_12 = [
  ['I', 'aVR', 'V1', 'V4'],
  ['II', 'aVL', 'V2', 'V5'],
  ['III', 'aVF', 'V3', 'V6'],
];

export class TwelveLead {
  constructor(canvas, opts = {}) {
    this.canvas = canvas; this.ctx = canvas.getContext('2d');
    this.mmPerSec = 25; this.mmPerMv = 10;
    this.panelSecs = 2.5;
    this.synth = null;
    this.rhythmLead = opts.rhythmLead || 'II';
  }

  setPattern(synth) { this.synth = synth; this.draw(); }
  setRhythmLead(name) { this.rhythmLead = name; this.draw(); }

  draw() {
    const cv = this.canvas, ctx = this.ctx;
    const dpr = window.devicePixelRatio || 1;
    const rect = cv.getBoundingClientRect();
    const W = rect.width;
    // altura proporcional: 3 filas de derivaciones + 1 tira de ritmo
    const rows = 3, rhythmRows = 1;
    const H = rect.height;
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    // Tamaño de cuadrícula: encaja panelSecs en el ancho de columna.
    const cols = 4;
    const pad = 8;
    const colW = (W - pad * 2) / cols;
    const mm = colW / (this.panelSecs * this.mmPerSec);   // px por mm
    drawGrid(ctx, W, H, mm);
    if (!this.synth) return;

    const totalRows = rows + rhythmRows;
    const rowH = (H - pad * 2) / totalRows;
    const pxPerSec = this.mmPerSec * mm;
    const pxPerMv = this.mmPerMv * mm;

    ctx.lineWidth = 1.6; ctx.strokeStyle = INK; ctx.lineJoin = 'round'; ctx.lineCap = 'round';

    const plot = (name, x0, y0, w, secs, tOffset) => {
      const buf = this.synth.leads[name];
      const mid = y0;
      ctx.beginPath();
      const px = Math.max(2, Math.ceil(w));
      for (let p = 0; p <= px; p++) {
        const t = tOffset + (p / px) * secs;
        const i = Math.floor((((t % DUR) + DUR) % DUR) * FS);
        const x = x0 + p / px * w;
        const y = mid - (buf[i] || 0) * pxPerMv;
        p === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
      }
      ctx.stroke();
      // etiqueta + pulso de calibración
      ctx.fillStyle = INK; ctx.font = `600 ${Math.max(11, mm * 2.4)}px Lexend, sans-serif`;
      ctx.fillText(name, x0 + 4, y0 - rowH * 0.32);
      // marca de calibración (10 mm de alto = 1 mV) al inicio del panel
      ctx.strokeStyle = 'rgba(28,21,18,0.5)'; ctx.lineWidth = 1.2;
      ctx.beginPath();
      const cx = x0 + 2;
      ctx.moveTo(cx, mid); ctx.lineTo(cx, mid - pxPerMv); ctx.lineTo(cx + mm * 2, mid - pxPerMv);
      ctx.stroke();
      ctx.strokeStyle = INK; ctx.lineWidth = 1.6;
    };

    // 3×4 paneles. Cada columna toma una ventana temporal distinta (como el
    // ECG real, que registra las columnas en secuencia).
    for (let r = 0; r < rows; r++) {
      const yMid = pad + rowH * (r + 0.5);
      for (let c = 0; c < cols; c++) {
        const name = GRID_12[r][c];
        const x0 = pad + c * colW;
        const tOffset = c * this.panelSecs;    // columnas consecutivas en el tiempo
        // separador vertical tenue entre columnas
        if (c > 0) { ctx.strokeStyle = 'rgba(28,21,18,0.12)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(x0, pad + rowH * r + 4); ctx.lineTo(x0, pad + rowH * (r + 1) - 4); ctx.stroke(); ctx.strokeStyle = INK; ctx.lineWidth = 1.6; }
        plot(name, x0 + 2, yMid, colW - 6, this.panelSecs, tOffset);
      }
    }

    // Tira de ritmo (fila inferior, a todo lo ancho, DUR completo)
    const yMid = pad + rowH * (rows + 0.5);
    const buf = this.synth.leads[this.rhythmLead];
    ctx.beginPath();
    const px = Math.max(2, Math.ceil(W - pad * 2));
    for (let p = 0; p <= px; p++) {
      const t = (p / px) * DUR;
      const i = Math.floor(t * FS);
      const x = pad + p / px * (W - pad * 2);
      const y = yMid - (buf[i] || 0) * pxPerMv;
      p === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.fillStyle = INK; ctx.font = `600 ${Math.max(11, mm * 2.4)}px Lexend, sans-serif`;
    ctx.fillText(this.rhythmLead + '  (tira de ritmo · 10 s)', pad + 4, yMid - rowH * 0.34);
  }
}
