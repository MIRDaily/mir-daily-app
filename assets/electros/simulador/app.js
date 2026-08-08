/* ════════════════════════════════════════════════════════════════════
   MIRElectro Pro — app.js
   Orquesta pantallas, monitor animado, ECG de 12 derivaciones, examen y sonido.
═══════════════════════════════════════════════════════════════════════ */
import { PATTERNS, PATTERN_BY_ID, CATEGORIES } from './patterns.js';
import { synthesize } from './ecg-core.js';
import { RhythmMonitor, TwelveLead } from './monitor.js';
import { LEAD_ORDER } from './leads.js';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

/* ─── Navegación ───────────────────────────────────────────────────── */
const screens = { start: $('#screen-start'), explore: $('#screen-explore'), quiz: $('#screen-quiz'), results: $('#screen-results') };
let current = 'start';
function go(name) {
  screens[current].classList.remove('active');
  screens[name].classList.add('active');
  current = name;
  if (name === 'explore') { requestAnimationFrame(() => { exploreMon.resize(); exploreMon.start(); ecg12.draw(); }); } else exploreMon.stop();
  if (name === 'quiz') { requestAnimationFrame(() => qEcg12.draw()); }
}

$('#pattern-count').textContent = PATTERNS.length;
$$('[data-go]').forEach(b => b.addEventListener('click', () => {
  audioInit();
  if (b.dataset.go === 'quiz') startQuiz();
  else { go('explore'); selectPattern(PATTERNS[0].id); }
}));
$$('[data-back]').forEach(b => b.addEventListener('click', () => go('start')));

/* ─── Audio (beep con el QRS) ──────────────────────────────────────── */
let audioCtx = null, soundOn = false;
function audioInit() { if (!audioCtx) try { audioCtx = new (window.AudioContext || window.webkitAudioContext)(); } catch {} }
function beep() {
  if (!soundOn || !audioCtx) return;
  const o = audioCtx.createOscillator(), g = audioCtx.createGain();
  o.frequency.value = 880; o.type = 'sine';
  g.gain.setValueAtTime(0.0001, audioCtx.currentTime);
  g.gain.exponentialRampToValueAtTime(0.16, audioCtx.currentTime + 0.005);
  g.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + 0.09);
  o.connect(g); g.connect(audioCtx.destination);
  o.start(); o.stop(audioCtx.currentTime + 0.1);
}
$('#sound-toggle').addEventListener('click', () => {
  soundOn = !soundOn; audioInit();
  $('#sound-toggle .material-symbols-outlined').textContent = soundOn ? 'volume_up' : 'volume_off';
  $('#sound-toggle').style.color = soundOn ? 'var(--accent-dark)' : '';
});

function pulseHeart(el) { el.classList.add('beat'); setTimeout(() => el.classList.remove('beat'), 90); }

/* ════════════════════════════════════════════════════════════════════
   EXPLORADOR
═══════════════════════════════════════════════════════════════════════ */
const heartIc = $('#heart-ic');
const exploreMon = new RhythmMonitor($('#ecg-grid'), $('#ecg-trace'), { lead: 'II', onBeat: () => { pulseHeart(heartIc); beep(); } });
const ecg12 = new TwelveLead($('#ecg12'), { rhythmLead: 'II' });
let activeId = null, currentSynth = null;

// Selector de derivación del monitor
const leadPicker = $('#lead-picker');
LEAD_ORDER.forEach(name => {
  const b = document.createElement('button');
  b.textContent = name; b.dataset.lead = name;
  if (name === 'II') b.classList.add('active');
  b.addEventListener('click', () => {
    $$('#lead-picker button').forEach(x => x.classList.remove('active'));
    b.classList.add('active');
    exploreMon.setLead(name);
  });
  leadPicker.appendChild(b);
});

function buildRail() {
  const rail = $('#pattern-rail'); rail.innerHTML = '';
  for (const cat of CATEGORIES) {
    const items = PATTERNS.filter(p => p.category === cat);
    if (!items.length) continue;
    const h = document.createElement('div'); h.className = 'rail-cat'; h.textContent = cat; rail.appendChild(h);
    for (const p of items) {
      const b = document.createElement('button');
      b.className = 'rail-item'; b.dataset.id = p.id;
      b.innerHTML = `<span class="sev-dot ${p.severity}"></span><span class="rail-name">${p.name}</span><span class="rail-badge">${p.badge}</span>`;
      b.addEventListener('click', () => selectPattern(p.id));
      rail.appendChild(b);
    }
  }
}

function selectPattern(id) {
  if (id === activeId) return;
  activeId = id;
  const p = PATTERN_BY_ID[id];
  $$('.rail-item').forEach(el => el.classList.toggle('active', el.dataset.id === id));

  currentSynth = synthesize(p);
  exploreMon.setPattern(currentSynth);
  ecg12.setPattern(currentSynth);

  $('#hr-val').textContent = p.hr > 0 ? p.hr : '--';
  $('#info-sev').className = `sev-dot ${p.severity}`;
  $('#info-name').textContent = p.name;
  $('#info-badge').textContent = p.badge;
  $('#info-summary').textContent = p.summary;
  const ul = $('#info-findings'); ul.innerHTML = '';
  for (const f of p.findings) { const li = document.createElement('li'); li.textContent = f; ul.appendChild(li); }
  $('#info-pearl-text').textContent = p.pearl;

  const chips = $('#interval-chips'); chips.innerHTML = '';
  if (p.intervals) for (const [k, val] of Object.entries(p.intervals)) {
    const c = document.createElement('span'); c.className = 'ichip';
    c.innerHTML = `${k.toUpperCase()} <b>${val}</b>`; chips.appendChild(c);
  }
}
buildRail();

$('#play-btn').addEventListener('click', () => {
  if (exploreMon.running) { exploreMon.stop(); $('#play-btn .material-symbols-outlined').textContent = 'play_arrow'; }
  else { exploreMon.start(); $('#play-btn .material-symbols-outlined').textContent = 'pause'; }
});
$$('#speed-seg button').forEach(b => b.addEventListener('click', () => {
  $$('#speed-seg button').forEach(x => x.classList.remove('active'));
  b.classList.add('active');
  exploreMon.timeScale = parseFloat(b.dataset.speed);
}));

/* ════════════════════════════════════════════════════════════════════
   EXAMEN
═══════════════════════════════════════════════════════════════════════ */
const qEcg12 = new TwelveLead($('#q-ecg12'), { rhythmLead: 'II' });
const QUIZ_LEN = 10;
let quizDeck = [], quizIdx = 0, quizScore = 0, answered = false;

function shuffle(a) { a = [...a]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

function startQuiz() {
  quizDeck = shuffle(PATTERNS).slice(0, QUIZ_LEN);
  quizIdx = 0; quizScore = 0;
  $('#quiz-score').textContent = '0';
  go('quiz');
  renderQuizQ();
}

const norm = s => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim();
const taInput = $('#quiz-input'), taList = $('#quiz-suggest'), taSubmit = $('#quiz-submit'), taClear = $('#quiz-clear');
let selected = null, hi = -1, suggestions = [];

function renderQuizQ() {
  answered = false; selected = null; hi = -1; suggestions = [];
  const p = quizDeck[quizIdx];
  $('#quiz-fill').style.width = `${(quizIdx / QUIZ_LEN) * 100}%`;
  $('#quiz-count').textContent = `${quizIdx + 1} / ${QUIZ_LEN}`;
  $('#quiz-feedback').classList.remove('show');
  $('#q-hr-note').textContent = p.hr > 0 ? `FC ${p.hr} lpm` : 'FC —';

  taInput.value = ''; taInput.disabled = false; taSubmit.disabled = true;
  taList.innerHTML = ''; taList.classList.remove('open');
  $('#quiz-typeahead').classList.remove('locked', 'ok', 'no');
  setTimeout(() => taInput.focus(), 60);

  qEcg12.setPattern(synthesize(p));
  requestAnimationFrame(() => qEcg12.draw());
}

function search(q) {
  const nq = norm(q); if (!nq) return [];
  const scored = [];
  for (const p of PATTERNS) {
    let best = Infinity;
    for (const term of p.search) {
      const nt = norm(term); const idx = nt.indexOf(nq);
      if (idx >= 0) best = Math.min(best, idx + (nt === nq ? -100 : 0));
    }
    if (best !== Infinity) scored.push({ p, best });
  }
  scored.sort((a, b) => a.best - b.best || a.p.name.localeCompare(b.p.name));
  return scored.slice(0, 6).map(s => s.p);
}

function renderSuggestions() {
  taList.innerHTML = '';
  if (!suggestions.length) { taList.classList.remove('open'); return; }
  taList.classList.add('open');
  suggestions.forEach((p, i) => {
    const li = document.createElement('li');
    li.className = 'ta-item' + (i === hi ? ' hi' : '');
    li.innerHTML = `<span class="sev-dot ${p.severity}"></span><span class="ta-name">${p.name}</span><span class="ta-badge">${p.badge}</span>`;
    li.addEventListener('mousedown', e => { e.preventDefault(); choose(p); });
    li.addEventListener('mouseenter', () => { hi = i; updateHi(); });
    taList.appendChild(li);
  });
}
function updateHi() { [...taList.children].forEach((li, i) => li.classList.toggle('hi', i === hi)); }

function choose(p) {
  selected = p; taInput.value = p.name; suggestions = []; hi = -1;
  taList.classList.remove('open'); taList.innerHTML = '';
  taSubmit.disabled = false; taInput.focus();
}

taInput.addEventListener('input', () => {
  selected = null; taSubmit.disabled = true;
  suggestions = search(taInput.value); hi = -1;
  const exact = PATTERNS.find(p => norm(p.name) === norm(taInput.value));
  if (exact) { selected = exact; taSubmit.disabled = false; }
  renderSuggestions();
});
taInput.addEventListener('keydown', e => {
  if (answered) return;
  if (e.key === 'ArrowDown') { e.preventDefault(); if (suggestions.length) { hi = (hi + 1) % suggestions.length; updateHi(); } }
  else if (e.key === 'ArrowUp') { e.preventDefault(); if (suggestions.length) { hi = (hi - 1 + suggestions.length) % suggestions.length; updateHi(); } }
  else if (e.key === 'Enter') {
    e.preventDefault();
    if (hi >= 0 && suggestions[hi]) choose(suggestions[hi]);
    else if (selected) submitAnswer(selected);
    else if (suggestions.length === 1) choose(suggestions[0]);
  } else if (e.key === 'Escape') { suggestions = []; taList.classList.remove('open'); taList.innerHTML = ''; }
});
taClear.addEventListener('click', () => { taInput.value = ''; selected = null; suggestions = []; hi = -1; taList.classList.remove('open'); taList.innerHTML = ''; taSubmit.disabled = true; taInput.focus(); });
taSubmit.addEventListener('click', () => { if (selected && !answered) submitAnswer(selected); });

function submitAnswer(chosen) {
  if (answered) return; answered = true;
  const correct = quizDeck[quizIdx];
  const ok = chosen.id === correct.id;
  if (ok) { quizScore++; $('#quiz-score').textContent = quizScore; }
  taInput.disabled = true; taSubmit.disabled = true;
  taList.classList.remove('open'); taList.innerHTML = '';
  $('#quiz-typeahead').classList.add('locked', ok ? 'ok' : 'no');
  const v = $('#qf-verdict');
  v.className = 'qf-verdict ' + (ok ? 'ok' : 'no');
  v.innerHTML = `<span class="material-symbols-outlined">${ok ? 'check_circle' : 'cancel'}</span>${ok ? '¡Correcto!' : 'Incorrecto'}`;
  const yourAns = ok ? '' : `<span class="qf-your">Tu respuesta: ${chosen.name}</span>`;
  $('#qf-expl').innerHTML = `${yourAns}<b>${correct.name}.</b> ${correct.pearl}`;
  $('#quiz-feedback').classList.add('show');
  $('#quiz-fill').style.width = `${((quizIdx + 1) / QUIZ_LEN) * 100}%`;
}
$('#quiz-next').addEventListener('click', () => { quizIdx++; if (quizIdx >= QUIZ_LEN) showResults(); else renderQuizQ(); });

function showResults() {
  go('results');
  const pct = Math.round((quizScore / QUIZ_LEN) * 100);
  $('#results-pct').textContent = `${pct}%`;
  const circ = 276.46;
  requestAnimationFrame(() => { $('#results-ring').style.strokeDashoffset = circ * (1 - pct / 100); });
  let emoji = '🫀', msg = '';
  if (pct === 100) { emoji = '🏆'; msg = '¡Perfecto! Dominas los patrones del MIR.'; }
  else if (pct >= 70) { emoji = '🫀'; msg = `${quizScore} de ${QUIZ_LEN} aciertos. Muy buen nivel, repasa los fallos.`; }
  else if (pct >= 40) { emoji = '📈'; msg = `${quizScore} de ${QUIZ_LEN}. Vas por buen camino; vuelve al explorador para afianzar.`; }
  else { emoji = '📖'; msg = `${quizScore} de ${QUIZ_LEN}. Repasa los patrones en el explorador y vuelve a intentarlo.`; }
  $('#results-emoji').textContent = emoji;
  $('#results-sub').textContent = msg;
  $('#results-ring').style.stroke = pct >= 70 ? '#8BA888' : pct >= 40 ? '#D8A24A' : '#C45B4E';
}
$('#results-retry').addEventListener('click', startQuiz);
$('#results-home').addEventListener('click', () => go('start'));

/* ─── Resize global ────────────────────────────────────────────────── */
let rT;
window.addEventListener('resize', () => {
  clearTimeout(rT);
  rT = setTimeout(() => {
    if (current === 'explore') { exploreMon.resize(); ecg12.draw(); }
    if (current === 'quiz') qEcg12.draw();
  }, 150);
});
