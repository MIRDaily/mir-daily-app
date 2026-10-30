#!/usr/bin/env node
// Genera los «blips» con los que habla la mascota de los tutoriales. La web los sintetiza al vuelo con
// WebAudio (src/lib/tutorials/mascotAudio.ts); Flutter no tiene un oscilador a mano, así que aquí se
// escriben como WAV, uno por grado de la escala, con la MISMA voz: onda triangular, do5 de base,
// pentatónica [0, 2, 4, 7, 9], ataque de 5 ms y caída exponencial hasta 0,0001 a los 80 ms.
//
// El volumen de la web (0,05) NO va dentro del fichero: el WAV sale a buena amplitud y el que lo
// rebaja es el reproductor (ver lib/features/tutorial/voz_mascota.dart). Así se puede ajustar sin
// regenerar nada.
//
// Uso:  node tools/generar_voz_mascota.mjs
// Escribe assets/audio/mascota/blip_0.wav … blip_4.wav

import { mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const salida = path.join(raiz, 'assets', 'audio', 'mascota')
mkdirSync(salida, { recursive: true })

const FS = 44100
const BASE_HZ = 523.25
const GRADOS = [0, 2, 4, 7, 9]
const ATAQUE_S = 0.005
const COLA_S = 0.08
const PICO = 0.6
const N = Math.round((COLA_S + 0.01) * FS) // el osc.stop de la web: cola + 10 ms

function triangular(fase) {
  const x = fase - Math.floor(fase)
  return 4 * Math.abs(x - 0.5) - 1
}

/** La envolvente de la web: rampa lineal a PICO y exponencial hasta 0,0001 en COLA_S. */
function envolvente(t) {
  if (t < ATAQUE_S) return (PICO * t) / ATAQUE_S
  if (t >= COLA_S) return 0
  const k = (t - ATAQUE_S) / (COLA_S - ATAQUE_S)
  return PICO * Math.pow(0.0001 / PICO, k)
}

GRADOS.forEach((semitono, i) => {
  const hz = BASE_HZ * Math.pow(2, semitono / 12)
  const datos = Buffer.alloc(N * 2)
  for (let n = 0; n < N; n++) {
    const t = n / FS
    const v = triangular(hz * t + 0.25) * envolvente(t)
    datos.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), n * 2)
  }
  const cab = Buffer.alloc(44)
  cab.write('RIFF', 0)
  cab.writeUInt32LE(36 + datos.length, 4)
  cab.write('WAVE', 8)
  cab.write('fmt ', 12)
  cab.writeUInt32LE(16, 16)
  cab.writeUInt16LE(1, 20) // PCM
  cab.writeUInt16LE(1, 22) // mono
  cab.writeUInt32LE(FS, 24)
  cab.writeUInt32LE(FS * 2, 28)
  cab.writeUInt16LE(2, 32)
  cab.writeUInt16LE(16, 34)
  cab.write('data', 36)
  cab.writeUInt32LE(datos.length, 40)
  writeFileSync(path.join(salida, `blip_${i}.wav`), Buffer.concat([cab, datos]))
})
console.log(`${GRADOS.length} blips en ${path.relative(raiz, salida)}`)
