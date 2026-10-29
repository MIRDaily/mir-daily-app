#!/usr/bin/env node
// Exporta las guías de estudio de la web a JSON para la app (assets/guides/). La fuente de verdad son
// los .ts de la web (src/lib/studyGuides/); aquí solo se copian. NO editar a mano los JSON: se vuelven a
// generar con este script cada vez que la web añada o corrija una guía, y se saca versión de la app.
//
// Uso (Node 22.18+ o 24, que ejecutan TypeScript sin herramientas):
//   node tools/export_study_guides.mjs "<carpeta del frontend>"
//
// Lee el registro de src/lib/studyGuides/index.ts (qué guías hay y de qué asignatura del catálogo cuelga
// cada una) e importa cada guía directamente: sus ficheros solo tienen datos y un `import type`, que Node
// borra al cargarlos.
// Node avisa de MODULE_TYPELESS_PACKAGE_JSON al importar los .ts de la web: es inofensivo.
//
// Escribe:
//   assets/guides/<clave>.json   la guía tal cual (StudyGuide de src/types/studyGuide.ts)
//   assets/guides/index.json     { version, origen, guias: [{ clave, subjectId, titulo, examen }] }
//   test/fixtures/guias_stats_web.json   las cifras de cada tema calculadas con el stats.ts REAL de la web,
//                                        con las que test/guias_test.dart comprueba que la app da lo mismo

import { readFileSync, writeFileSync, mkdirSync, readdirSync, unlinkSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import path from 'node:path'
import { pathToFileURL, fileURLToPath } from 'node:url'

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const frontend = process.argv[2]
if (!frontend) {
  console.error('Uso: node tools/export_study_guides.mjs "<carpeta del frontend>"')
  process.exit(1)
}
const dirGuias = path.join(frontend, 'src', 'lib', 'studyGuides')
const indice = readFileSync(path.join(dirGuias, 'index.ts'), 'utf8')

// ASIGNATURA_DE_GUIA = { neurologia: 1478, 'cirugia-general': 3, ... }
const bloque = indice.match(/ASIGNATURA_DE_GUIA[^=]*=\s*\{([\s\S]*?)\}/)
if (!bloque) throw new Error('No encuentro ASIGNATURA_DE_GUIA en index.ts')
const asignaturas = [...bloque[1].matchAll(/['"]?([a-z0-9-]+)['"]?\s*:\s*(\d+)/g)].map((m) => ({ clave: m[1], subjectId: Number(m[2]) }))
if (asignaturas.length === 0) throw new Error('ASIGNATURA_DE_GUIA está vacía')

// De dónde importa index.ts cada guía: import { X } from '@/lib/studyGuides/<fichero>'
const ficheroDe = new Map(
  [...indice.matchAll(/import\s*\{\s*(\w+)\s*\}\s*from\s*'@\/lib\/studyGuides\/([\w-]+)'/g)].map((m) => [m[1], m[2]]),
)
// clave → nombre exportado: STUDY_GUIDES_BY_SUBJECT = { neurologia: NEUROLOGIA_GUIDE, ... }
const registro = indice.match(/STUDY_GUIDES_BY_SUBJECT[^=]*=\s*\{([\s\S]*?)\}/)
if (!registro) throw new Error('No encuentro STUDY_GUIDES_BY_SUBJECT en index.ts')
const exportDe = new Map([...registro[1].matchAll(/['"]?([a-z0-9-]+)['"]?\s*:\s*(\w+)/g)].map((m) => [m[1], m[2]]))

const salida = path.join(raiz, 'assets', 'guides')
mkdirSync(salida, { recursive: true })
for (const f of readdirSync(salida)) if (f.endsWith('.json')) unlinkSync(path.join(salida, f))

let commit = null
try {
  commit = execFileSync('git', ['-C', frontend, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim()
} catch {
  // Sin git: se exporta igual, sin la referencia.
}

const guias = []
for (const { clave, subjectId } of asignaturas) {
  const nombre = exportDe.get(clave)
  const fichero = nombre && ficheroDe.get(nombre)
  if (!fichero) throw new Error(`No sé de qué fichero sale la guía «${clave}»`)
  const modulo = await import(pathToFileURL(path.join(dirGuias, `${fichero}.ts`)).href)
  const guia = modulo[nombre]
  if (!guia || guia.subjectId !== clave) throw new Error(`La guía «${clave}» no se ha podido leer (${nombre} en ${fichero}.ts)`)
  writeFileSync(path.join(salida, `${clave}.json`), JSON.stringify(guia) + '\n')
  guias.push({ clave, subjectId, titulo: guia.title, examen: guia.targetExam })
}

// Las cifras esperadas para los tests, con el stats.ts de la web (solo importa tipos: Node los borra).
const stats = await import(pathToFileURL(path.join(dirGuias, 'stats.ts')).href)
const esperadas = {}
for (const { clave } of guias) {
  const g = JSON.parse(readFileSync(path.join(salida, `${clave}.json`), 'utf8'))
  esperadas[clave] = {
    perYear: stats.subjectPerYear(g),
    temas: stats.withStats(g.topics).map((t) => ({ id: t.id, perYear: t.perYear, stats: t.stats, forecastTexto: stats.formatForecast(t.stats.forecast) })),
  }
}
writeFileSync(path.join(raiz, 'test', 'fixtures', 'guias_stats_web.json'), `${JSON.stringify(esperadas, null, 1)}\n`)

writeFileSync(
  path.join(salida, 'index.json'),
  JSON.stringify({ version: 1, origen: commit ? `mir-daily-frontend@${commit}` : 'mir-daily-frontend', guias }, null, 2) + '\n',
)
console.log(`${guias.length} guías exportadas a assets/guides/${commit ? ` (frontend ${commit})` : ''}:`)
for (const g of guias) console.log(`  ${g.clave} → asignatura ${g.subjectId} · ${g.titulo} · ${g.examen}`)
