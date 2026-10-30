#!/usr/bin/env node
// Exporta GramSwipe de la web a la app: los antibióticos de src/components/minijuegos/gramswipe/data.ts
// y sus fotos de public/img/gramswipe. La fuente de verdad es la web; aquí solo se copia. NO editar a
// mano lib/core/models/gramswipe_datos.dart: se vuelve a generar con este script.
//
// Uso (Node 22.18+ o 24, que ejecutan TypeScript sin herramientas):
//   node tools/export_gramswipe.mjs "<carpeta del frontend>"
//
// Escribe:
//   lib/core/models/gramswipe_datos.dart   const antibioticosGramSwipe (generado)
//   assets/gramswipe/<id>.jpg              las fotos, tal cual

import { copyFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs'
import { writeFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import path from 'node:path'
import { pathToFileURL, fileURLToPath } from 'node:url'

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const frontend = process.argv[2]
if (!frontend) {
  console.error('Uso: node tools/export_gramswipe.mjs "<carpeta del frontend>"')
  process.exit(1)
}

const { ANTIBIOTICS } = await import(
  pathToFileURL(path.join(frontend, 'src', 'components', 'minijuegos', 'gramswipe', 'data.ts')).href
)

let commit = null
try {
  commit = execFileSync('git', ['-C', frontend, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim()
} catch {
  // Sin git: se exporta igual, sin la referencia.
}

const COBERTURA = { gram_positive: 'gramPositivo', gram_negative: 'gramNegativo', broad: 'amplio' }
const str = (s) => JSON.stringify(s).replace(/\$/g, '\\$')

const dirFotos = path.join(raiz, 'assets', 'gramswipe')
rmSync(dirFotos, { recursive: true, force: true })
mkdirSync(dirFotos, { recursive: true })

const filas = ANTIBIOTICS.map((a) => {
  const cobertura = COBERTURA[a.coverage]
  if (!cobertura) throw new Error(`Cobertura desconocida en ${a.name}: ${a.coverage}`)
  const origen = path.join(frontend, 'public', a.image.replace(/^\//, ''))
  const destino = `${a.id}${path.extname(origen)}`
  copyFileSync(origen, path.join(dirFotos, destino))
  return `  Antibiotico(
    id: ${a.id},
    nombre: ${str(a.name)},
    principioActivo: ${str(a.activeIngredient)},
    familia: ${str(a.family)},
    mecanismo: ${str(a.mechanism)},
    cobertura: Cobertura.${cobertura},
    foto: ${str(`assets/gramswipe/${destino}`)},
  ),`
})

const dart = `// GENERADO por tools/export_gramswipe.mjs desde src/components/minijuegos/gramswipe/data.ts de la web${
  commit ? ` (commit ${commit})` : ''
}.
// NO editar a mano: se vuelve a generar con el script.
// ignore_for_file: prefer_single_quotes, lines_longer_than_80_chars

import 'gramswipe.dart';

/// Los ${ANTIBIOTICS.length} antibióticos de GramSwipe, en el orden de la web.
const List<Antibiotico> antibioticosGramSwipe = [
${filas.join('\n')}
];
`
writeFileSync(path.join(raiz, 'lib', 'core', 'models', 'gramswipe_datos.dart'), dart)
console.log(`${ANTIBIOTICS.length} antibióticos y ${readdirSync(dirFotos).length} fotos${commit ? ` (web ${commit})` : ''}.`)
