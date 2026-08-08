/* ════════════════════════════════════════════════════════════════════════
   MIRElectro Academia — heart.js
   Corazón esquemático con el sistema de conducción, animado.
   update(f) ilumina la estructura activa según la fase y mueve el "impulso"
   por la vía de conducción (nodo SA → AV → His → ramas → Purkinje).
═══════════════════════════════════════════════════════════════════════════ */
import { phaseAt } from './ecgmini.js';

// Trayecto del impulso en coordenadas del viewBox (0 0 200 250). Keyframes por f.
const ROUTE = [
  { f: 0.00, x: 138, y: 62 },   // nodo SA (aurícula derecha, arriba)
  { f: 0.07, x: 118, y: 92 },   // difusión auricular
  { f: 0.12, x: 102, y: 120 },  // nodo AV
  { f: 0.20, x: 102, y: 132 },  // retraso AV (apenas avanza)
  { f: 0.23, x: 102, y: 150 },  // haz de His
  { f: 0.27, x: 102, y: 168 },  // ramas
  { f: 0.31, x: 102, y: 210 },  // Purkinje / punta
];

function routePoint(f) {
  if (f <= ROUTE[0].f) return ROUTE[0];
  if (f >= ROUTE[ROUTE.length - 1].f) return ROUTE[ROUTE.length - 1];
  for (let i = 1; i < ROUTE.length; i++) {
    if (f <= ROUTE[i].f) {
      const a = ROUTE[i - 1], b = ROUTE[i];
      const k = (f - a.f) / (b.f - a.f);
      return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k };
    }
  }
  return ROUTE[ROUTE.length - 1];
}

const SVG = `
<svg viewBox="0 0 200 250" class="heart-svg" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Corazón y sistema de conducción">
  <!-- cámaras -->
  <path class="chamber atria" d="M40 60 Q40 30 72 34 Q100 20 100 46 Q100 20 128 34 Q160 30 160 60 Q160 96 100 104 Q40 96 40 60 Z"/>
  <path class="chamber vent" d="M46 104 Q40 150 72 210 Q100 244 100 210 Q100 244 128 210 Q160 150 154 104 Q100 128 46 104 Z"/>
  <!-- tabique -->
  <line class="septum" x1="100" y1="104" x2="100" y2="214"/>
  <!-- vía de conducción -->
  <path class="cond" d="M138 62 Q118 92 102 120 L102 150"/>
  <path class="cond branch" d="M102 168 Q80 184 70 214"/>
  <path class="cond branch" d="M102 168 Q124 184 134 214"/>
  <path class="cond purkinje" d="M70 214 Q66 224 60 230 M70 214 Q78 226 84 232 M134 214 Q138 224 144 230 M134 214 Q126 226 120 232"/>
  <!-- nodos -->
  <circle class="node sa" cx="138" cy="62" r="7"/>
  <circle class="node av" cx="102" cy="120" r="6"/>
  <rect class="node his" x="98" y="146" width="8" height="16" rx="3"/>
  <!-- impulso -->
  <circle class="spark" cx="138" cy="62" r="6"/>
  <!-- etiquetas -->
  <text class="hlbl lbl-sa" x="150" y="52">SA</text>
  <text class="hlbl lbl-av" x="112" y="120">AV</text>
  <text class="hlbl lbl-his" x="112" y="160">His</text>
</svg>`;

export class HeartConduction {
  constructor(container) {
    container.innerHTML = SVG;
    const q = s => container.querySelector(s);
    this.el = {
      atria: q('.atria'), vent: q('.vent'),
      sa: q('.node.sa'), av: q('.node.av'), his: q('.node.his'),
      cond: container.querySelectorAll('.cond'),
      spark: q('.spark'), svg: q('.heart-svg'),
    };
  }

  update(f) {
    const ph = phaseAt(f);
    const s = ph.struct;
    // reset
    this.el.atria.classList.toggle('lit', s === 'atria' || s === 'sa');
    this.el.vent.classList.toggle('lit', s === 'vent' || s === 'st');
    this.el.vent.classList.toggle('repol', s === 'repol');
    this.el.sa.classList.toggle('active', s === 'sa');
    this.el.av.classList.toggle('active', s === 'av');
    this.el.his.classList.toggle('active', s === 'his');
    this.el.cond.forEach(c => c.classList.toggle('active', s === 'his' || s === 'vent'));

    // impulso visible durante la despolarización (f < 0.32)
    const x = ((f % 1) + 1) % 1;
    if (x < 0.32) {
      const p = routePoint(x);
      this.el.spark.style.opacity = '1';
      this.el.spark.setAttribute('cx', p.x.toFixed(1));
      this.el.spark.setAttribute('cy', p.y.toFixed(1));
    } else {
      this.el.spark.style.opacity = '0';
    }
    return ph;
  }

  reset() { this.update(0.66); }   // estado en diástole (todo apagado)
}
