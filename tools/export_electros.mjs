#!/usr/bin/env node
// Exporta el catálogo de patrones ECG de la web a Dart para el Explorador de la app. La fuente de verdad
// es src/lib/electros/patterns.ts de la web (texto clínico, sinónimos y directivas de síntesis); aquí
// solo se copia. NO editar a mano lib/core/models/ecg_patrones.dart: se vuelve a generar con este
// script cuando la web añada o corrija un patrón, y se saca versión de la app.
//
// Uso (Node 22.18+ o 24, que ejecutan TypeScript sin herramientas):
//   node tools/export_electros.mjs "<carpeta del frontend>"
//
// Los .ts de la web se importan con rutas sin extensión (`from './leads'`), que Node no resuelve: se
// copian a una carpeta temporal con la extensión puesta y se importan desde ahí.
//
// Escribe:
//   lib/core/models/ecg_patrones.dart     const patronesEcg / categoriasEcg (generado)
//   test/fixtures/ecg_sintesis_web.json   la síntesis REAL de la web de cada patrón (latidos y una
//                                         muestra de voltajes por derivación) y normalizeAnswer de unos
//                                         textos, con los que test/ecg_test.dart comprueba que la app
//                                         dibuja exactamente lo mismo.

import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import os from 'node:os'
import path from 'node:path'
import { pathToFileURL, fileURLToPath } from 'node:url'

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const frontend = process.argv[2]
if (!frontend) {
  console.error('Uso: node tools/export_electros.mjs "<carpeta del frontend>"')
  process.exit(1)
}
const dirElectros = path.join(frontend, 'src', 'lib', 'electros')

const tmp = mkdtempSync(path.join(os.tmpdir(), 'electros-'))
for (const f of ['ecgCore', 'leads', 'patterns']) {
  const src = readFileSync(path.join(dirElectros, `${f}.ts`), 'utf8').replace(/from '\.\/(\w+)'/g, "from './$1.ts'")
  writeFileSync(path.join(tmp, `${f}.ts`), src)
}
writeFileSync(path.join(tmp, 'package.json'), '{"type":"module"}\n')
// Node guarda los módulos en memoria: la carpeta temporal se borra al final sin problema.
const modulos = {
  core: await import(pathToFileURL(path.join(tmp, 'ecgCore.ts')).href),
  patterns: await import(pathToFileURL(path.join(tmp, 'patterns.ts')).href),
}

const { PATTERNS, CATEGORIES, normalizeAnswer } = modulos.patterns
const { synthesize, FS, DUR } = modulos.core

let commit = null
try {
  commit = execFileSync('git', ['-C', frontend, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim()
} catch {
  // Sin git: se exporta igual, sin la referencia.
}

/* ── Dart ──────────────────────────────────────────────────────────────── */
const str = (s) => JSON.stringify(s).replace(/\$/g, '\\$')
const num = (n) => `${n}`
const lista = (xs) => `[${xs.map(str).join(', ')}]`

const CAMPOS_MORPH = ['qrsWidth', 'tWidth', 'qtScale', 'pWidth', 'pNotch', 'pPeak', 'pr', 'qrsMag', 'qrsAxis', 'pMag', 'pAxis', 'tMag', 'tAxis']

function morph(m = {}) {
  const partes = []
  for (const k of CAMPOS_MORPH) if (m[k] !== undefined) partes.push(`${k}: ${num(m[k])}`)
  for (const k of Object.keys(m)) {
    if (k !== 'mods' && !CAMPOS_MORPH.includes(k)) throw new Error(`Campo de morph desconocido: ${k}`)
  }
  if (m.mods?.length) partes.push(`mods: ${lista(m.mods)}`)
  return `MorfologiaEcg(${partes.join(', ')})`
}

function patron(p) {
  const intervalos = Object.entries(p.intervals).map(([k, v]) => `IntervaloEcg(${str(k)}, ${str(v)})`)
  const ritmo = Object.entries(p.rhythm || {}).map(([k, v]) => `${str(k)}: ${num(v)}`)
  return `  PatronEcg(
    id: ${str(p.id)},
    nombre: ${str(p.name)},
    sigla: ${str(p.badge)},
    categoria: ${str(p.category)},
    gravedad: GravedadEcg.${p.severity},
    fc: ${p.hr},
    ritmo: ${str(p.gen || 'regular')},
    morfologia: ${morph(p.morph)},
    parametrosRitmo: {${ritmo.join(', ')}},
    intervalos: [${intervalos.join(', ')}],
    resumen: ${str(p.summary)},
    claves: ${lista(p.findings)},
    perla: ${str(p.pearl)},
    busqueda: ${lista(p.search)},
  ),`
}

const dart = `// GENERADO por tools/export_electros.mjs desde src/lib/electros/patterns.ts de la web${commit ? ` (commit ${commit})` : ''}.
// NO editar a mano: se vuelve a generar con el script.
// ignore_for_file: prefer_single_quotes, lines_longer_than_80_chars

import 'ecg_core.dart';

/// Los ${PATTERNS.length} patrones del Explorador, en el orden de la web.
const List<PatronEcg> patronesEcg = [
${PATTERNS.map(patron).join('\n')}
];

/// Las categorías, en el orden en que se enseñan.
const List<String> categoriasEcg = ${lista(CATEGORIES)};
`
writeFileSync(path.join(raiz, 'lib', 'core', 'models', 'ecg_patrones.dart'), dart)

/* ── Fixture de la síntesis ───────────────────────────────────────────── */
const PASO = 97 // una muestra de cada 97: ~52 por derivación, repartidas por toda la tira
const r6 = (x) => Math.round(x * 1e6) / 1e6
const sintesis = {}
for (const p of PATTERNS) {
  const s = synthesize(p)
  const leads = {}
  for (const [nombre, buf] of Object.entries(s.leads)) {
    let suma = 0
    let min = Infinity
    let max = -Infinity
    for (const v of buf) {
      suma += v
      if (v < min) min = v
      if (v > max) max = v
    }
    const muestras = []
    for (let i = 0; i < buf.length; i += PASO) muestras.push(r6(buf[i]))
    leads[nombre] = { suma: r6(suma), min: r6(min), max: r6(max), muestras }
  }
  sintesis[p.id] = { beats: s.beats.map(r6), fs: s.fs, dur: s.dur, hr: s.hr, leads }
}
const textos = ['Fibrilación Auricular', '  BRD!! ', 'Síndrome de QT-largo', 'IAM ínfero-posterior', 'Ñandú 2:1']
const fixture = {
  origen: commit,
  fs: FS,
  dur: DUR,
  paso: PASO,
  sintesis,
  normalizar: Object.fromEntries(textos.map((t) => [t, normalizeAnswer(t)])),
}
writeFileSync(path.join(raiz, 'test', 'fixtures', 'ecg_sintesis_web.json'), JSON.stringify(fixture) + '\n')

rmSync(tmp, { recursive: true, force: true })
console.log(`${PATTERNS.length} patrones exportados${commit ? ` (web ${commit})` : ''}.`)
