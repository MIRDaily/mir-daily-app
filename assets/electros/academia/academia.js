/* ════════════════════════════════════════════════════════════════════════
   MIRElectro Academia — academia.js
   Controlador: mapa de la ruta, reproductor de lecciones, transiciones e
   interacciones (animación de conducción, hotspots, quiz, compás, frecuencia,
   eje). Pensado mobile-first y fácil de portar a app.
═══════════════════════════════════════════════════════════════════════════ */
import { MODULES } from './curriculum.js';
import { EcgTracer, beatPathSVG, phaseAt } from './ecgmini.js';
import { HeartConduction } from './heart.js';
import { TREES, WALLS } from './algorithms.js';
import { stripSVG } from './strips.js';

const $ = (s, r = document) => r.querySelector(s);
const app = $('#app');

/* ─── Progreso (localStorage) ──────────────────────────────────────────── */
const KEY = 'mirelectro_academia_v1';
const state = load();
function load() { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch { return {}; } }
function save() { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch {} }
function modState(id) { return state[id] || (state[id] = { done: false, step: 0 }); }
function isUnlocked(idx) { return idx === 0 || (state[MODULES[idx - 1].id]?.done); }
function moduleProgress(m) {
  const st = state[m.id];
  if (!st) return 0;
  if (st.done) return 1;
  return Math.min(0.95, (st.step || 0) / m.steps.length);
}

/* ─── Navegación entre pantallas ───────────────────────────────────────── */
function show(node) {
  app.classList.add('screen-out');
  setTimeout(() => {
    app.innerHTML = '';
    app.appendChild(node);
    app.classList.remove('screen-out');
    app.scrollTop = 0;
  }, 120);
}

/* ════════════════════════════════════════════════════════════════════════
   PANTALLA: MAPA DE LA RUTA
═══════════════════════════════════════════════════════════════════════════ */
function renderHome() {
  const wrap = el('div', 'home');
  const doneCount = MODULES.filter(m => state[m.id]?.done).length;
  wrap.innerHTML = `
    <header class="home-head">
      <div class="brand"><span class="material-symbols-outlined">cardiology</span></div>
      <h1>Academia ECG</h1>
      <p>Aprende a leer un electro paso a paso: de la chispa eléctrica del corazón al diagnóstico.</p>
      <div class="home-progress">
        <div class="hp-bar"><div class="hp-fill" style="width:${(doneCount / MODULES.length) * 100}%"></div></div>
        <span>${doneCount}/${MODULES.length} módulos</span>
      </div>
    </header>
    <div class="path" id="path"></div>`;
  const path = wrap.querySelector('#path');

  MODULES.forEach((m, i) => {
    const unlocked = isUnlocked(i);
    const done = state[m.id]?.done;
    const prog = moduleProgress(m);
    const node = el('button', 'mod' + (unlocked ? '' : ' locked') + (done ? ' done' : ''));
    node.style.setProperty('--mc', m.color);
    node.innerHTML = `
      <div class="mod-ring">
        <svg viewBox="0 0 44 44"><circle class="ring-bg" cx="22" cy="22" r="19"/><circle class="ring-fg" cx="22" cy="22" r="19"
          stroke-dasharray="119.4" stroke-dashoffset="${119.4 * (1 - prog)}" transform="rotate(-90 22 22)"/></svg>
        <span class="material-symbols-outlined mod-ic">${unlocked ? m.icon : 'lock'}</span>
        ${done ? '<span class="material-symbols-outlined mod-check">check</span>' : ''}
      </div>
      <div class="mod-txt">
        <span class="mod-n">Módulo ${i + 1}</span>
        <span class="mod-title">${m.title}</span>
        <span class="mod-sub">${m.subtitle}</span>
      </div>
      <span class="material-symbols-outlined mod-go">${unlocked ? 'arrow_forward' : ''}</span>`;
    if (unlocked) node.addEventListener('click', () => openModule(i, state[m.id]?.done ? 0 : (state[m.id]?.step || 0)));
    path.appendChild(node);
  });

  show(wrap);
}

/* ════════════════════════════════════════════════════════════════════════
   REPRODUCTOR DE LECCIONES
═══════════════════════════════════════════════════════════════════════════ */
let cur = { mIdx: 0, sIdx: 0, renderer: null, dir: 1 };

function openModule(mIdx, sIdx = 0) {
  cur.mIdx = mIdx; cur.sIdx = sIdx;
  const m = MODULES[mIdx];
  const shell = el('div', 'lesson');
  shell.innerHTML = `
    <header class="lesson-head">
      <button class="icon-btn" id="l-back"><span class="material-symbols-outlined">arrow_back</span></button>
      <div class="dots" id="l-dots"></div>
      <div class="l-mtitle">${m.title}</div>
    </header>
    <div class="stage" id="stage"></div>
    <footer class="lesson-foot">
      <div class="hud-slot" id="l-hud"></div>
      <button class="btn-primary" id="l-continue" disabled>Continuar</button>
    </footer>`;
  shell.querySelector('#l-back').addEventListener('click', () => { destroyRenderer(); renderHome(); });
  shell.querySelector('#l-continue').addEventListener('click', nextStep);
  show(shell);
  setTimeout(() => renderStep(0), 180);
}

function renderDots() {
  const m = MODULES[cur.mIdx];
  const dots = $('#l-dots'); if (!dots) return;
  dots.innerHTML = '';
  m.steps.forEach((_, i) => {
    const d = el('span', 'dot' + (i === cur.sIdx ? ' on' : '') + (i < cur.sIdx ? ' past' : ''));
    dots.appendChild(d);
  });
}

function destroyRenderer() { if (cur.renderer && cur.renderer.destroy) cur.renderer.destroy(); cur.renderer = null; }

function renderStep(dir = 1) {
  cur.dir = dir;
  destroyRenderer();
  const m = MODULES[cur.mIdx];
  const step = m.steps[cur.sIdx];
  renderDots();

  const stage = $('#stage'); if (!stage) return;
  const card = el('div', 'step-card ' + (dir >= 0 ? 'in-right' : 'in-left'));
  card.innerHTML = `<div class="step-kicker" style="--mc:${m.color}">${step.kicker || ''}</div>
                    <h2 class="step-title">${step.title}</h2>
                    <div class="step-body" id="step-body"></div>`;
  stage.innerHTML = '';
  stage.appendChild(card);
  requestAnimationFrame(() => card.classList.add('shown'));

  const body = card.querySelector('#step-body');
  const btn = $('#l-continue');
  btn.disabled = true;
  btn.textContent = (cur.sIdx === m.steps.length - 1) ? 'Terminar módulo' : 'Continuar';
  const unlock = () => { btn.disabled = false; };

  const ctx = { body, unlock, color: m.color, step };
  const R = RENDERERS[step.type] || RENDERERS.info;
  cur.renderer = R(ctx) || {};

  // guarda avance
  const st = modState(m.id); st.step = Math.max(st.step || 0, cur.sIdx); save();
}

function nextStep() {
  const m = MODULES[cur.mIdx];
  if (cur.sIdx < m.steps.length - 1) { cur.sIdx++; renderStep(1); }
  else finishModule();
}

function finishModule() {
  destroyRenderer();
  const m = MODULES[cur.mIdx];
  modState(m.id).done = true; modState(m.id).step = m.steps.length; save();
  const next = MODULES[cur.mIdx + 1];
  const done = el('div', 'module-done');
  done.innerHTML = `
    <div class="done-burst" style="--mc:${m.color}"><span class="material-symbols-outlined">verified</span></div>
    <h2>Módulo completado</h2>
    <p class="done-sub">${m.title}</p>
    <div class="done-actions">
      ${next && isUnlocked(cur.mIdx + 1)
        ? `<button class="btn-primary" id="d-next">Módulo ${cur.mIdx + 2}: ${next.title}</button>` : ''}
      <button class="btn-ghost" id="d-home">Volver al mapa</button>
    </div>`;
  show(done);
  const nx = done.querySelector('#d-next');
  if (nx) nx.addEventListener('click', () => openModule(cur.mIdx + 1, 0));
  done.querySelector('#d-home').addEventListener('click', renderHome);
}

/* ════════════════════════════════════════════════════════════════════════
   HELPERS
═══════════════════════════════════════════════════════════════════════════ */
function el(tag, cls, html) { const n = document.createElement(tag); if (cls) n.className = cls; if (html != null) n.innerHTML = html; return n; }

class AnimLoop {
  constructor(cb) { this.cb = cb; this.running = false; this._raf = null; this._t0 = 0; }
  start() { if (this.running) return; this.running = true; this._t0 = performance.now(); const loop = (ts) => { if (!this.running) return; this.cb((ts - this._t0) / 1000); this._raf = requestAnimationFrame(loop); }; this._raf = requestAnimationFrame(loop); }
  stop() { this.running = false; if (this._raf) cancelAnimationFrame(this._raf); }
}

/* Genera un latido SVG con zonas tocables (para hotspot de ondas). */
function wavesSceneSVG(withHits) {
  const W = 320, H = 150;
  const { d, xOf } = beatPathSVG(0, 0, W, H, { fStart: 0, fEnd: 0.66 });
  const regions = [
    { id: 'P', a: 0.03, b: 0.15, label: 'P' },
    { id: 'PR', a: 0.15, b: 0.235, label: 'PR' },
    { id: 'QRS', a: 0.235, b: 0.315, label: 'QRS' },
    { id: 'ST', a: 0.315, b: 0.45, label: 'ST' },
    { id: 'T', a: 0.45, b: 0.63, label: 'T' },
  ];
  let hits = '';
  if (withHits) for (const r of regions) {
    const x0 = xOf(r.a), x1 = xOf(r.b);
    hits += `<rect class="hit" data-hit="${r.id}" x="${x0.toFixed(1)}" y="4" width="${(x1 - x0).toFixed(1)}" height="${H - 8}" rx="6"/>
             <text class="hit-lbl" x="${((x0 + x1) / 2).toFixed(1)}" y="${H - 6}">${r.label}</text>`;
  }
  return `<svg viewBox="0 0 ${W} ${H}" class="scene-svg waves" xmlns="http://www.w3.org/2000/svg">
    <rect width="${W}" height="${H}" fill="#FFF7F4"/>
    <path d="${d}" fill="none" stroke="#241c1a" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/>
    ${hits}</svg>`;
}

/* Corazón con zonas tocables (para hotspot). */
function heartSceneSVG() {
  return `<svg viewBox="0 0 200 250" class="scene-svg heart" xmlns="http://www.w3.org/2000/svg">
    <path class="hz" data-hit="atria" d="M40 60 Q40 30 72 34 Q100 20 100 46 Q100 20 128 34 Q160 30 160 60 Q160 96 100 104 Q40 96 40 60 Z"/>
    <path class="hz" data-hit="vent" d="M46 104 Q40 150 72 210 Q100 244 100 210 Q100 244 128 210 Q160 150 154 104 Q100 128 46 104 Z"/>
    <path class="cond-static" d="M138 62 Q118 92 102 120 L102 150 M102 168 Q80 184 70 214 M102 168 Q124 184 134 214"/>
    <circle class="hz node" data-hit="sa" cx="138" cy="62" r="9"/>
    <circle class="hz node" data-hit="av" cx="102" cy="120" r="8"/>
    <rect class="hz node" data-hit="his" x="96" y="146" width="12" height="18" rx="3"/>
    <text class="hz-lbl" x="152" y="52">SA</text>
    <text class="hz-lbl" x="114" y="120">AV</text>
    <text class="hz-lbl" x="116" y="160">His</text>
  </svg>`;
}

/* Diana del ventrículo izquierdo (eje corto) con paredes tocables. */
function polar(cx, cy, r, deg) { const a = deg * Math.PI / 180; return { x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) }; }
function sectorPath(cx, cy, r, a0, a1) {
  const p0 = polar(cx, cy, r, a0), p1 = polar(cx, cy, r, a1);
  const large = (a1 - a0) > 180 ? 1 : 0;
  return `M${cx} ${cy} L${p0.x.toFixed(1)} ${p0.y.toFixed(1)} A${r} ${r} 0 ${large} 1 ${p1.x.toFixed(1)} ${p1.y.toFixed(1)} Z`;
}
function bullseyeSVG() {
  const cx = 110, cy = 112, r = 82;
  const secs = [
    { id: 'anterior', a0: -135, a1: -45, lab: 'Anterior', sub: 'V3-V4' },
    { id: 'lateral', a0: -45, a1: 45, lab: 'Lateral', sub: 'I·aVL·V5-V6' },
    { id: 'inferior', a0: 45, a1: 135, lab: 'Inferior', sub: 'II·III·aVF' },
    { id: 'septal', a0: 135, a1: 225, lab: 'Septo', sub: 'V1-V2' },
  ];
  let paths = '', labels = '';
  for (const s of secs) {
    paths += `<path class="wall" data-wall="${s.id}" d="${sectorPath(cx, cy, r, s.a0, s.a1)}"/>`;
    const mid = (s.a0 + s.a1) / 2, lp = polar(cx, cy, r * 0.6, mid);
    labels += `<text class="wall-lab" x="${lp.x.toFixed(1)}" y="${(lp.y - 2).toFixed(1)}">${s.lab}</text>
               <text class="wall-sub" x="${lp.x.toFixed(1)}" y="${(lp.y + 11).toFixed(1)}">${s.sub}</text>`;
  }
  return `<svg viewBox="0 0 220 224" class="scene-svg bullseye" xmlns="http://www.w3.org/2000/svg">
    <path class="rv-crescent" d="M28 112 A82 82 0 0 1 192 112" fill="none"/>
    <text class="rv-lab" x="110" y="18">VD: V3R-V4R · Posterior: espejo en V1-V2</text>
    ${paths}<circle cx="${cx}" cy="${cy}" r="26" class="wall-core"/><text class="wall-core-lab" x="${cx}" y="${cy + 4}">VI</text>${labels}
  </svg>`;
}

/* Escalera de Lewis (A–nodo AV–V) animada por un cabezal que avanza. */
function ladderEvents(kind) {
  const x0 = 16, dx = 48, Ay = 34, Ny0 = 60, Ny1 = 92, Vy = 118, ev = [];
  const nA = 6;
  const addCond = (xP, pr) => { const xQ = xP + pr; ev.push({ k: 'cond', x1: xP, y1: Ay, x2: xQ, y2: Vy, rx: xQ }); ev.push({ k: 'qrs', x: xQ, rx: xQ }); };
  if (kind === 'av3') {
    for (let i = 0; i < nA; i++) { const xP = x0 + i * dx; ev.push({ k: 'p', x: xP, rx: xP }); ev.push({ k: 'block', x: xP, y2: Ny1, rx: xP }); }
    let xv = 30; while (xv < x0 + nA * dx) { ev.push({ k: 'qrs', x: xv, rx: xv }); ev.push({ k: 'vstub', x: xv, rx: xv }); xv += 92; }
    return { ev, Ay, Ny0, Ny1, Vy };
  }
  for (let i = 0; i < nA; i++) {
    const xP = x0 + i * dx; ev.push({ k: 'p', x: xP, rx: xP });
    let blocked = false, pr = 22;
    if (kind === 'mobitz1') { pr = 20 + (i % 4) * 12; blocked = (i % 4 === 3); }
    else if (kind === 'mobitz2') { pr = 24; blocked = (i % 3 === 2); }
    if (blocked) ev.push({ k: 'block', x: xP, y2: Ny1, rx: xP });
    else addCond(xP, pr);
  }
  return { ev, Ay, Ny0, Ny1, Vy };
}
function drawLadder(kind, head) {
  const { ev, Ay, Ny0, Ny1, Vy } = ladderEvents(kind);
  const W = 320, H = 150;
  let g = '';
  const tier = (y, lab) => `<line class="lad-tier" x1="8" y1="${y}" x2="${W - 8}" y2="${y}"/><text class="lad-lab" x="10" y="${y - 4}">${lab}</text>`;
  g += tier(Ay, 'A') + `<line class="lad-tier" x1="8" y1="${Ny0}" x2="${W - 8}" y2="${Ny0}"/><line class="lad-tier" x1="8" y1="${Ny1}" x2="${W - 8}" y2="${Ny1}"/><text class="lad-lab" x="10" y="${Ny0 - 4}">AV</text>` + tier(Vy, 'V');
  for (const e of ev) {
    if (e.rx > head) continue;
    if (e.k === 'p') g += `<line class="lad-p" x1="${e.x}" y1="${Ay - 10}" x2="${e.x}" y2="${Ay + 4}"/><circle class="lad-dot p" cx="${e.x}" cy="${Ay - 10}" r="3"/>`;
    else if (e.k === 'cond') g += `<line class="lad-cond" x1="${e.x1}" y1="${e.y1}" x2="${e.x2}" y2="${e.y2}"/>`;
    else if (e.k === 'block') g += `<line class="lad-cond block" x1="${e.x}" y1="${Ay}" x2="${e.x}" y2="${e.y2}"/><text class="lad-x" x="${e.x}" y="${e.y2 + 12}">✕</text>`;
    else if (e.k === 'qrs') g += `<line class="lad-qrs" x1="${e.x}" y1="${Vy - 4}" x2="${e.x}" y2="${Vy + 14}"/><circle class="lad-dot q" cx="${e.x}" cy="${Vy + 14}" r="3"/>`;
    else if (e.k === 'vstub') g += `<line class="lad-cond esc" x1="${e.x}" y1="${Ny1}" x2="${e.x}" y2="${Vy}"/>`;
  }
  g += `<line class="lad-head" x1="${head.toFixed(1)}" y1="20" x2="${head.toFixed(1)}" y2="${H - 16}"/>`;
  return `<svg viewBox="0 0 ${W} ${H}" class="ladder-svg" xmlns="http://www.w3.org/2000/svg">${g}</svg>`;
}

function feedback(body, ok, msg) {
  let fb = body.querySelector('.step-fb');
  if (!fb) { fb = el('div', 'step-fb'); body.appendChild(fb); }
  fb.className = 'step-fb show ' + (ok ? 'ok' : 'no');
  fb.innerHTML = `<span class="material-symbols-outlined">${ok ? 'check_circle' : 'info'}</span><p>${msg}</p>`;
}

/* ════════════════════════════════════════════════════════════════════════
   RENDERIZADORES POR TIPO DE PASO
═══════════════════════════════════════════════════════════════════════════ */
const RENDERERS = {
  /* ── Info ───────────────────────────────────────────────────────────── */
  info(ctx) {
    const { body, step, unlock } = ctx;
    const vis = infoVisual(step.visual);
    body.innerHTML = `${vis}
      <p class="lead">${step.body}</p>
      ${step.points ? `<ul class="pts">${step.points.map(p => `<li><span class="material-symbols-outlined">check</span>${p}</li>`).join('')}</ul>` : ''}`;
    unlock();
    // Corazón animado decorativo en el primer paso
    let loop = null;
    const hm = body.querySelector('#hm');
    if (hm) {
      const heart = new HeartConduction(hm);
      loop = new AnimLoop((t) => heart.update((t / 3.6) % 1));
      loop.start();
    }
    return { destroy() { if (loop) loop.stop(); } };
  },

  /* ── Animación de conducción sincronizada ───────────────────────────── */
  conduction(ctx) {
    const { body, step, unlock } = ctx;
    body.innerHTML = `
      <p class="lead">${step.body}</p>
      <div class="cond-stage">
        <div class="heart-holder" id="heart-holder"></div>
        <div class="phase-tag" id="phase-tag"></div>
      </div>
      <div class="ecg-holder">
        <canvas id="c-grid"></canvas><canvas id="c-trace"></canvas>
      </div>
      <div class="cond-controls">
        <button class="round-btn" id="c-play"><span class="material-symbols-outlined">pause</span></button>
        <input type="range" id="c-scrub" min="0" max="1000" value="0" />
      </div>`;
    const heart = new HeartConduction(body.querySelector('#heart-holder'));
    const tracer = new EcgTracer(body.querySelector('#c-grid'), body.querySelector('#c-trace'));
    const tag = body.querySelector('#phase-tag');
    const scrub = body.querySelector('#c-scrub');
    const playBtn = body.querySelector('#c-play');
    const focusWave = step.focus === 'wave';
    setTimeout(() => tracer.resize(), 60);

    const CYCLE = 3.6;      // s por ciclo (cómodo para observar)
    let playing = true, base = 0, lastPhase = null;

    const draw = (f) => {
      const ph = heart.update(f);
      tracer.render(((f % 1) + 1) % 1);
      // Actualiza el texto SOLO al cambiar de fase (reescribir innerHTML cada
      // frame provoca reflujo y da sensación de lag en el WebView móvil).
      if (ph.id !== lastPhase) {
        lastPhase = ph.id;
        const waveTxt = ph.wave === '—' ? '' : `<b style="color:${ph.color}">Onda ${ph.wave}</b> · `;
        tag.innerHTML = focusWave ? `${waveTxt}${ph.text}` : `<b style="color:${ph.color}">${ph.title}</b> · ${ph.text}`;
      }
      scrub.value = Math.round((((f % 1) + 1) % 1) * 1000);
    };

    const loop = new AnimLoop((t) => { const f = (base + t / CYCLE) % 1; draw(f); });
    loop.start(); unlock();

    playBtn.addEventListener('click', () => {
      playing = !playing;
      playBtn.innerHTML = `<span class="material-symbols-outlined">${playing ? 'pause' : 'play_arrow'}</span>`;
      if (playing) loop.start(); else loop.stop();
    });
    scrub.addEventListener('input', () => {
      if (playing) { playing = false; loop.stop(); playBtn.innerHTML = `<span class="material-symbols-outlined">play_arrow</span>`; }
      base = scrub.value / 1000; draw(base);
    });
    window.addEventListener('resize', tracer._rz = () => tracer.resize());
    return { destroy() { loop.stop(); window.removeEventListener('resize', tracer._rz); } };
  },

  /* ── Hotspot: tocar la zona correcta ────────────────────────────────── */
  hotspot(ctx) {
    const { body, step, unlock } = ctx;
    const scene = step.scene === 'heart' ? heartSceneSVG() : wavesSceneSVG(true);
    body.innerHTML = `<p class="prompt">${step.prompt}</p>
      <div class="scene-holder">${scene}</div>
      <p class="hint" id="hint">Pista: ${step.hint}</p>`;
    let solved = false;
    body.querySelectorAll('[data-hit]').forEach(hit => {
      hit.addEventListener('click', () => {
        if (solved) return;
        if (hit.dataset.hit === step.target) {
          solved = true;
          hit.classList.add('correct');
          body.querySelector('#hint').style.display = 'none';
          feedback(body, true, step.ok);
          unlock();
        } else {
          hit.classList.add('wrong');
          setTimeout(() => hit.classList.remove('wrong'), 500);
          body.querySelector('#hint').classList.add('show');
        }
      });
    });
    return {};
  },

  /* ── Choice: opción múltiple ────────────────────────────────────────── */
  choice(ctx) {
    const { body, step, unlock } = ctx;
    body.innerHTML = `<p class="prompt">${step.prompt}</p><div class="opts" id="opts"></div>`;
    const opts = body.querySelector('#opts');
    let solved = false;
    step.options.forEach(o => {
      const b = el('button', 'opt');
      b.innerHTML = `<span class="opt-dot"></span><span>${o.text}</span>`;
      b.addEventListener('click', () => {
        if (solved) return;
        if (o.correct) {
          solved = true;
          b.classList.add('correct');
          opts.querySelectorAll('.opt').forEach(x => x.disabled = true);
          feedback(body, true, step.why);
          unlock();
        } else {
          b.classList.add('wrong'); b.disabled = true;
        }
      });
      opts.appendChild(b);
    });
    return {};
  },

  /* ── Reveal: desplegar lista ────────────────────────────────────────── */
  reveal(ctx) {
    const { body, step, unlock } = ctx;
    body.innerHTML = `<p class="prompt">${step.prompt}</p><div class="reveal-list" id="rl"></div>`;
    const rl = body.querySelector('#rl');
    let opened = 0;
    step.items.forEach(it => {
      const row = el('button', 'reveal-item');
      row.innerHTML = `<span class="rv-k">${it.k}</span><div class="rv-main"><span class="rv-label">${it.label}<span class="material-symbols-outlined rv-chev">expand_more</span></span><span class="rv-text">${it.text}</span></div>`;
      row.addEventListener('click', () => {
        if (row.classList.contains('open')) return;
        row.classList.add('open'); opened++;
        if (opened >= step.items.length) unlock();
      });
      rl.appendChild(row);
    });
    return {};
  },

  /* ── Caliper: medir la anchura del QRS ──────────────────────────────── */
  caliper(ctx) {
    const { body, step, unlock } = ctx;
    const msPerSq = 40;                       // 1 cuadradito "ampliado" = 40 ms
    const trueSq = step.trueMs / msPerSq;     // anchura real del QRS
    body.innerHTML = `<p class="prompt">${step.prompt}</p>
      <div class="measure-holder" id="mh"></div>
      <div class="measure-read"><span id="ms-val">40 ms</span><span class="ms-tag" id="ms-tag"></span></div>
      <div class="cond-controls"><span class="ctl-lbl">Compás</span>
        <input type="range" id="cal" min="1" max="6" step="0.5" value="1"/></div>`;
    const mh = body.querySelector('#mh');
    const W = 320, H = 150, sq = 30, x0 = 60, base = H * 0.62;
    // QRS glifo (onda estilizada) con anchura trueSq*sq centrada en x0
    const qw = trueSq * sq;
    const qrs = `M${x0 - qw / 2} ${base} L${x0 - qw / 2 + qw * 0.2} ${base + 14} L${x0} ${base - 70} L${x0 + qw * 0.3} ${base + 22} L${x0 + qw / 2} ${base} L${W - 10} ${base}`;
    const pre = `M10 ${base} L${x0 - qw / 2} ${base}`;
    let msVal = msPerSq, solved = false;
    const cal = body.querySelector('#cal');
    const valEl = body.querySelector('#ms-val'), tagEl = body.querySelector('#ms-tag');
    function render() {
      const sqSel = parseFloat(cal.value);
      msVal = Math.round(sqSel * msPerSq);
      const rightX = (x0 - qw / 2) + sqSel * sq;
      mh.innerHTML = `<svg viewBox="0 0 ${W} ${H}" class="scene-svg">
        <defs><pattern id="mg" width="${sq}" height="${sq}" patternUnits="userSpaceOnUse">
          <path d="M${sq} 0 L0 0 0 ${sq}" fill="none" stroke="rgba(212,151,140,0.28)" stroke-width="1"/></pattern></defs>
        <rect width="${W}" height="${H}" fill="#FFF7F4"/><rect width="${W}" height="${H}" fill="url(#mg)"/>
        <path d="${pre}" fill="none" stroke="#241c1a" stroke-width="2.2"/>
        <path d="${qrs}" fill="none" stroke="#241c1a" stroke-width="2.4" stroke-linejoin="round"/>
        <line class="cal-line" x1="${x0 - qw / 2}" y1="8" x2="${x0 - qw / 2}" y2="${H - 8}"/>
        <line class="cal-line move" x1="${rightX}" y1="8" x2="${rightX}" y2="${H - 8}"/>
        <rect class="cal-span" x="${x0 - qw / 2}" y="${base - 82}" width="${Math.max(0, rightX - (x0 - qw / 2))}" height="6"/>
      </svg>`;
      valEl.textContent = `${(msVal / 1000).toFixed(2)} s  (${msVal} ms)`;
      const okMeasure = Math.abs(msVal - step.trueMs) <= step.tolMs;
      if (okMeasure && !solved) {
        solved = true;
        tagEl.textContent = msVal < step.normalMax ? 'QRS normal (< 0,12 s) ✓' : 'QRS ancho';
        tagEl.className = 'ms-tag ok';
        feedback(body, true, `Bien medido: el QRS mide ≈ ${step.trueMs} ms. Al ser < 0,12 s es un QRS estrecho (normal).`);
        unlock();
      } else if (!solved) {
        tagEl.textContent = 'Ajusta el compás al final del QRS';
        tagEl.className = 'ms-tag';
      }
    }
    cal.addEventListener('input', render);
    render();
    return {};
  },

  /* ── Rate: regla de la frecuencia (300 / cuadros grandes) ───────────── */
  rate(ctx) {
    const { body, step, unlock } = ctx;
    body.innerHTML = `<p class="prompt">${step.prompt}</p>
      <div class="measure-holder" id="mh"></div>
      <div class="measure-read"><span id="bpm-val">—</span><span class="ms-tag" id="bpm-tag"></span></div>
      <div class="cond-controls"><span class="ctl-lbl">Distancia R-R</span>
        <input type="range" id="rr" min="1.5" max="6" step="0.5" value="6"/></div>`;
    const mh = body.querySelector('#mh');
    const W = 320, H = 150, big = 30, base = H * 0.55;
    const bpmEl = body.querySelector('#bpm-val'), tagEl = body.querySelector('#bpm-tag');
    const rr = body.querySelector('#rr');
    let solved = false;
    const spike = (x) => `M${x - 6} ${base} L${x - 3} ${base + 10} L${x} ${base - 60} L${x + 3} ${base + 16} L${x + 6} ${base}`;
    function render() {
      const nBig = parseFloat(rr.value);
      const bpm = Math.round(300 / nBig);
      const gap = nBig * big;
      const x1 = 40, x2 = x1 + gap;
      mh.innerHTML = `<svg viewBox="0 0 ${W} ${H}" class="scene-svg">
        <defs><pattern id="bg2" width="${big}" height="${big}" patternUnits="userSpaceOnUse">
          <path d="M${big} 0 L0 0 0 ${big}" fill="none" stroke="rgba(212,151,140,0.4)" stroke-width="1.1"/></pattern></defs>
        <rect width="${W}" height="${H}" fill="#FFF7F4"/><rect width="${W}" height="${H}" fill="url(#bg2)"/>
        <path d="M10 ${base} L${x1 - 6} ${base} ${spike(x1).slice(1)} L${x2 - 6} ${base} ${spike(x2).slice(1)} L${W - 10} ${base}" fill="none" stroke="#241c1a" stroke-width="2.3" stroke-linejoin="round"/>
        <path class="rr-brace" d="M${x1} ${base + 22} L${x2} ${base + 22}" />
        <text class="rr-txt" x="${(x1 + x2) / 2}" y="${base + 38}">${nBig} cuadros</text>
      </svg>`;
      bpmEl.innerHTML = `300 ÷ ${nBig} = <b>${bpm}</b> lpm`;
      const ok = bpm >= step.targetMin && bpm <= step.targetMax;
      tagEl.textContent = ok ? 'Frecuencia normal ✓' : (bpm < step.targetMin ? 'Bradicardia' : 'Taquicardia');
      tagEl.className = 'ms-tag ' + (ok ? 'ok' : '');
      if (ok && !solved) { solved = true; feedback(body, true, `${bpm} lpm está en el rango normal (60–100). Recuerda la regla: 300, 150, 100, 75, 60, 50 para 1–6 cuadros.`); unlock(); }
    }
    rr.addEventListener('input', render);
    render();
    return {};
  },

  /* ── Axis: rotar el eje eléctrico ───────────────────────────────────── */
  axis(ctx) {
    const { body, step, unlock } = ctx;
    body.innerHTML = `<p class="prompt">${step.prompt}</p>
      <div class="axis-holder" id="ah"></div>
      <div class="axis-read" id="ar"></div>
      <div class="cond-controls"><span class="ctl-lbl">Eje</span>
        <input type="range" id="ax" min="-150" max="150" step="5" value="60"/></div>`;
    const ah = body.querySelector('#ah'), ar = body.querySelector('#ar');
    const ax = body.querySelector('#ax');
    const cx = 110, cy = 110, R = 82;
    let solved = false;
    function quad(a) {
      const I = Math.cos(a * Math.PI / 180) >= 0;         // lead I +
      const F = Math.sin(a * Math.PI / 180) >= 0;         // aVF + (hacia abajo)
      if (I && F) return { n: 'Eje normal', c: '#8BA888' };
      if (I && !F) return { n: 'Desviación izquierda', c: '#C9A24A' };
      if (!I && F) return { n: 'Desviación derecha', c: '#7CA3C9' };
      return { n: 'Eje extremo', c: '#C45B4E' };
    }
    function render() {
      const a = parseFloat(ax.value);
      const rad = a * Math.PI / 180;
      const ex = cx + R * Math.cos(rad), ey = cy + R * Math.sin(rad);
      const q = quad(a);
      const Ipos = Math.cos(rad) >= 0, Fpos = Math.sin(rad) >= 0;
      ah.innerHTML = `<svg viewBox="0 0 220 220" class="axis-svg">
        <circle cx="${cx}" cy="${cy}" r="${R}" class="ax-circle"/>
        <line x1="${cx - R}" y1="${cy}" x2="${cx + R}" y2="${cy}" class="ax-lead"/>
        <line x1="${cx}" y1="${cy - R}" x2="${cx}" y2="${cy + R}" class="ax-lead"/>
        <text class="ax-lbl" x="${cx + R + 8}" y="${cy + 4}">I+ (0°)</text>
        <text class="ax-lbl" x="${cx - 6}" y="${cy + R + 16}">aVF+ (+90°)</text>
        <line x1="${cx}" y1="${cy}" x2="${ex.toFixed(1)}" y2="${ey.toFixed(1)}" class="ax-vec" style="stroke:${q.c}"/>
        <circle cx="${ex.toFixed(1)}" cy="${ey.toFixed(1)}" r="6" fill="${q.c}"/>
        <text class="ax-deg" x="${cx}" y="${cy + 4}" style="fill:${q.c}">${a}°</text>
      </svg>`;
      ar.innerHTML = `
        <div class="ax-badges">
          <span class="ax-b ${Ipos ? 'up' : 'down'}">I ${Ipos ? '▲' : '▼'}</span>
          <span class="ax-b ${Fpos ? 'up' : 'down'}">aVF ${Fpos ? '▲' : '▼'}</span>
        </div>
        <div class="ax-quad" style="color:${q.c}">${q.n}</div>`;
      const ok = a >= step.targetMin && a <= step.targetMax;
      if (ok && !solved) { solved = true; feedback(body, true, `¡Eso es ${step.targetLabel}! Con I positivo y aVF negativo, el eje apunta arriba-izquierda (${step.targetMin}° a ${step.targetMax}°).`); unlock(); }
    }
    ax.addEventListener('input', render);
    render();
    return {};
  },

  /* ── Algorithm: árbol de decisión que se ramifica poco a poco ────────── */
  algorithm(ctx) {
    const { body, step, unlock, color } = ctx;
    const tree = TREES[step.tree];
    body.innerHTML = `<p class="lead">${tree.intro}</p>
      <p class="tree-help"><span class="material-symbols-outlined">movie</span>Pulsa play y mira cómo se ramifica el algoritmo. Al terminar (o cuando quieras), toca un diagnóstico para iluminar su camino y ver su detalle.</p>
      <div class="dtree" id="dtree"></div>
      <div class="tree-detail" id="tree-detail"></div>`;
    // Los controles viven en el HUD del pie (fijos, junto a "Continuar").
    const hud = document.getElementById('l-hud');
    hud.innerHTML = `<div class="cond-controls algo-ctrls">
        <button class="round-btn" id="algo-play"><span class="material-symbols-outlined">pause</span></button>
        <input type="range" id="algo-scrub" min="0" max="1000" value="0"/>
        <button class="round-btn ghost" id="algo-replay" title="Reiniciar"><span class="material-symbols-outlined">replay</span></button>
      </div>`;
    const root = body.querySelector('#dtree');
    const detail = body.querySelector('#tree-detail');
    const scrub = hud.querySelector('#algo-scrub');
    const playBtn = hud.querySelector('#algo-play');
    const replayBtn = hud.querySelector('#algo-replay');
    root.style.setProperty('--mc', color);

    // Construye el árbol; cada elemento visible se registra como "unidad de
    // aparición" con un orden por profundidad (así se revela nivel a nivel).
    const units = [];
    function build(id, depth) {
      const node = tree.nodes[id];
      if (node.options) {
        const q = el('div', 'qnode');
        const box = el('div', 'qbox reveal-unit', `<span class="qn">${depth + 1}</span><span>${node.q.replace(/^\d\)\s*/, '')}</span>`);
        units.push({ el: box, order: depth }); q.appendChild(box);
        const branches = el('div', 'branches');
        node.options.forEach(o => {
          const br = el('div', 'branch');
          const label = el('div', 'branch-label reveal-unit', `<span>${o.label}</span>`);
          units.push({ el: label, order: depth + 0.5 });
          br.appendChild(label); br.appendChild(build(o.go, depth + 1));
          branches.appendChild(br);
        });
        q.appendChild(branches);
        return q;
      }
      const leaf = el('div', 'leafnode');
      const btn = el('button', 'leafbtn reveal-unit', `<span class="sev-dot ${node.sev}"></span><span class="leaf-name">${node.dx}</span><span class="material-symbols-outlined lf-go">chevron_right</span>`);
      units.push({ el: btn, order: depth });
      btn.addEventListener('click', () => select(leaf, btn, node));
      leaf.appendChild(btn);
      return leaf;
    }
    function select(leaf, btn, node) {
      if (!btn.classList.contains('shown')) return;   // aún no revelado
      root.querySelectorAll('.branch.on, .leafbtn.on').forEach(x => x.classList.remove('on'));
      let e = leaf;
      while (e && e !== root) { if (e.classList.contains('branch')) e.classList.add('on'); e = e.parentElement; }
      btn.classList.add('on');
      detail.innerHTML = `<div class="algo-leaf">
        <div class="leaf-head"><span class="sev-dot ${node.sev}"></span><h3>${node.dx}</h3><span class="leaf-badge">${node.badge}</span></div>
        <div class="leaf-strip">${stripSVG(node.strip, { label: node.badge })}</div>
        <p class="leaf-clue"><b>En el ECG:</b> ${node.clue}</p>
        <p class="leaf-why">${node.why}</p></div>`;
      detail.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      done = true; unlock();
    }
    root.appendChild(build(tree.root, 0));
    units.sort((a, b) => a.order - b.order);
    const ordered = units.map(u => u.el);
    const total = ordered.length;

    // Reproducción tipo Módulo 1: play/pausa + barra + reiniciar.
    let f = 0, base = 0, playing = true, done = false;
    const DUR = Math.min(6.5, Math.max(2.6, total * 0.17));
    const icon = (b, n) => { b.innerHTML = `<span class="material-symbols-outlined">${n}</span>`; };
    function apply(fr) {
      f = fr;
      const head = Math.round(fr * total);
      ordered.forEach((elm, i) => elm.classList.toggle('shown', i < head));
      scrub.value = Math.round(fr * 1000);
      if (fr >= 1 && !done) { done = true; unlock(); }
    }
    const loop = new AnimLoop((t) => {
      apply(Math.min(1, base + t / DUR));
      if (f >= 1) { playing = false; loop.stop(); icon(playBtn, 'replay'); }
    });
    function play() { playing = true; base = f >= 1 ? 0 : f; loop.start(); icon(playBtn, 'pause'); }
    function pause() { playing = false; loop.stop(); icon(playBtn, 'play_arrow'); }
    playBtn.addEventListener('click', () => (playing && f < 1) ? pause() : play());
    replayBtn.addEventListener('click', () => { base = 0; apply(0); play(); });
    scrub.addEventListener('input', () => { loop.stop(); playing = false; base = scrub.value / 1000; apply(base); icon(playBtn, f >= 1 ? 'replay' : 'play_arrow'); });
    play();
    return { destroy() { loop.stop(); if (hud) hud.innerHTML = ''; } };
  },

  /* ── Territory: mapa interactivo de localización del infarto ─────────── */
  territory(ctx) {
    const { body, step, unlock } = ctx;
    body.innerHTML = `<p class="prompt">${step.prompt}</p>
      <div class="scene-holder">${bullseyeSVG()}</div>
      <div class="territory-read" id="tr-read"></div>
      <p class="hint" id="hint">Pista: relaciona el grupo de derivaciones con su pared.</p>`;
    const read = body.querySelector('#tr-read');
    let solved = false;
    body.querySelectorAll('[data-wall]').forEach(sec => {
      sec.addEventListener('click', () => {
        if (solved) return;
        if (sec.dataset.wall === step.target) {
          solved = true; sec.classList.add('sel');
          const w = WALLS[step.target];
          read.innerHTML = `<div class="tr-card"><b>Cara ${w.name.toLowerCase()}</b><span><i>Derivaciones:</i> ${w.leads}</span><span><i>Arteria:</i> ${w.artery}</span></div>`;
          feedback(body, true, step.ok || `Cara ${w.name.toLowerCase()}: la irriga habitualmente la ${w.artery}.`);
          body.querySelector('#hint').style.display = 'none';
          unlock();
        } else { sec.classList.add('bad'); setTimeout(() => sec.classList.remove('bad'), 450); body.querySelector('#hint').classList.add('show'); }
      });
    });
    return {};
  },

  /* ── Ladder: escalera de conducción AV (animada) ────────────────────── */
  ladder(ctx) {
    const { body, step, unlock } = ctx;
    const kinds = step.kinds || ['normal', 'mobitz1', 'mobitz2', 'av3'];
    const NAMES = { normal: 'Normal', mobitz1: 'Mobitz I', mobitz2: 'Mobitz II', av3: 'BAV III' };
    const CAP = {
      normal: 'Conducción 1:1: cada P baja por el nodo AV con un PR constante y genera su QRS.',
      mobitz1: 'Wenckebach: la pendiente en el nodo AV (el PR) crece latido a latido hasta que una P se bloquea.',
      mobitz2: 'El PR se mantiene fijo… y de pronto una P no conduce, sin aviso previo.',
      av3: 'Disociación completa: ninguna P conduce; un marcapasos de escape mueve los ventrículos por su cuenta.',
    };
    body.innerHTML = `<p class="prompt">${step.prompt}</p>
      <div class="ladder-tabs" id="ltabs"></div>
      <div class="ladder-holder" id="lh"></div>
      <div class="phase-tag" id="lcap"></div>`;
    const tabs = body.querySelector('#ltabs'), lh = body.querySelector('#lh'), cap = body.querySelector('#lcap');
    let kind = kinds[0];
    kinds.forEach(k => {
      const b = el('button', 'ltab' + (k === kind ? ' on' : ''), NAMES[k]);
      b.addEventListener('click', () => { kind = k; [...tabs.children].forEach(x => x.classList.remove('on')); b.classList.add('on'); cap.textContent = CAP[k]; head = 0; });
      tabs.appendChild(b);
    });
    cap.textContent = CAP[kind];
    let head = 0;
    const loop = new AnimLoop((t) => { head = (t * 82) % 360; lh.innerHTML = drawLadder(kind, head); });
    loop.start(); unlock();
    return { destroy() { loop.stop(); } };
  },

  /* ── Summary: cierre del módulo ─────────────────────────────────────── */
  summary(ctx) {
    const { body, step, unlock } = ctx;
    body.innerHTML = `<div class="summary-visual"><span class="material-symbols-outlined">workspace_premium</span></div>
      <p class="lead">${step.body}</p>
      <button class="btn-link" id="summary-cta" type="button">${step.cta}<span class="material-symbols-outlined">arrow_forward</span></button>`;
    const cta = body.querySelector('#summary-cta');
    if (cta) cta.addEventListener('click', () => { try { window.MirdailyElectros && window.MirdailyElectros.postMessage('open-simulador'); } catch {} });
    unlock();
    return {};
  },
};

/* Ilustraciones estáticas para pasos 'info'. */
function infoVisual(kind) {
  if (kind === 'wave-labeled') {
    const { d, xOf, base } = beatPathSVG(0, 0, 320, 130, { fStart: 0, fEnd: 0.66 });
    const lbl = (f, t) => `<text class="wv-lbl" x="${xOf(f).toFixed(1)}" y="18">${t}</text>`;
    return `<div class="info-visual"><svg viewBox="0 0 320 130" class="scene-svg"><rect width="320" height="130" fill="#FFF7F4"/>
      <path d="${d}" fill="none" stroke="#241c1a" stroke-width="2.4" stroke-linejoin="round"/>
      ${lbl(0.09, 'P')}${lbl(0.268, 'QRS')}${lbl(0.52, 'T')}</svg></div>`;
  }
  if (kind === 'grid') {
    return `<div class="info-visual"><svg viewBox="0 0 320 120" class="scene-svg">
      <defs><pattern id="ig" width="12" height="12" patternUnits="userSpaceOnUse"><path d="M12 0 L0 0 0 12" fill="none" stroke="rgba(212,151,140,0.25)" stroke-width="1"/></pattern>
      <pattern id="igb" width="60" height="60" patternUnits="userSpaceOnUse"><rect width="60" height="60" fill="url(#ig)"/><path d="M60 0 L0 0 0 60" fill="none" stroke="rgba(212,151,140,0.55)" stroke-width="1.3"/></pattern></defs>
      <rect width="320" height="120" fill="#FFF7F4"/><rect width="320" height="120" fill="url(#igb)"/>
      <rect x="0" y="30" width="60" height="60" fill="rgba(212,151,140,0.16)"/>
      <text class="wv-lbl" x="8" y="108">1 grande = 0,20 s</text><text class="wv-lbl" x="200" y="108">y 0,5 mV</text></svg></div>`;
  }
  if (kind === 'heart-static') return `<div class="info-visual heart-mini" id="hm"></div>`;
  if (kind === 'leads') return `<div class="info-visual"><div class="leads-badges">
      <span>I</span><span>II</span><span>III</span><span>aVR</span><span>aVL</span><span>aVF</span>
      <span>V1</span><span>V2</span><span>V3</span><span>V4</span><span>V5</span><span>V6</span></div></div>`;
  if (kind === 'order') return `<div class="info-visual order-chips"><span>Ritmo</span><span>Frecuencia</span><span>Eje</span><span>Intervalos</span><span>Morfología</span></div>`;
  if (kind === 'tree') return `<div class="info-visual tree-mini"><span class="material-symbols-outlined">account_tree</span></div>`;
  return '';
}

/* ─── Arranque ─────────────────────────────────────────────────────────── */
renderHome();
