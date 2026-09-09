/* ════════════════════════════════════════════════════════════════════════
   Rangos y curva del sistema de niveles.

   Portado literal de `src/lib/levels.ts` de la web. Los nombres, los cortes y
   los colores tienen que coincidir EXACTAMENTE con los de allí: es el mismo
   usuario contra el mismo backend, y dos tablas distintas significarían que
   alguien ve "Residente R1" en el ordenador y "Graduado" en el móvil.

   El nombre importa tanto como el número: "Nivel 22" no dice nada, "R1" sitúa
   al usuario en la carrera que está preparando.

   OJO: esto es un rótulo de CONSTANCIA, no de conocimiento. El nivel dice
   cuántos días has aparecido; el porcentaje de acierto dice si vas a aprobar.
   No deben mezclarse nunca en la misma tarjeta.
═══════════════════════════════════════════════════════════════════════════ */
import 'package:flutter/material.dart';

/// Tope de la escala. Subió de 50 a 100 el 07-09-2026.
const int kMaxLevel = 100;

@immutable
class Rank {
  final String name;
  final int minLevel;

  /// Color del texto y del anillo.
  final Color color;

  const Rank(this.name, this.minLevel, this.color);
}

/// Doce escalones sobre 100 niveles. Los cuatro primeros se agolpan en las
/// tres primeras semanas —que son el onboarding— y la residencia (R1-R5) ocupa
/// del 20 al 70, que es el grueso del camino.
const List<Rank> kRanks = [
  Rank('Novato', 1, Color(0xFF7D8A96)),
  Rank('Estudiante', 6, Color(0xFF6E8CA0)),
  Rank('Graduado', 12, Color(0xFF5E9AA8)),
  Rank('Residente R1', 20, Color(0xFF8BA888)),
  Rank('Residente R2', 30, Color(0xFF7EA57A)),
  Rank('Residente R3', 40, Color(0xFF6E9B6B)),
  Rank('Residente R4', 50, Color(0xFFC9A227)),
  Rank('Residente R5', 60, Color(0xFFD18D80)),
  Rank('Jefe de residentes', 70, Color(0xFFC4655A)),
  Rank('Adjunto', 80, Color(0xFFA8524F)),
  Rank('Jefe de sección', 90, Color(0xFF7C4A63)),
  Rank('Jefe de servicio', 100, Color(0xFF2C3E50)),
];

/// El rango de un nivel es el escalón más alto cuyo mínimo no lo supera.
Rank rankForLevel(int level) {
  var found = kRanks.first;
  for (final r in kRanks) {
    if (level >= r.minLevel) found = r;
  }
  return found;
}

/// Siguiente rango, o `null` si ya está en el último.
Rank? nextRank(int level) {
  for (final r in kRanks) {
    if (r.minLevel > level) return r;
  }
  return null;
}

/* ─── La curva, replicada en cliente ──────────────────────────────────────
   El servidor manda el nivel ya resuelto y con eso basta para pintar la
   tarjeta. La ANIMACIÓN de subida necesita más: hay que saber dónde empieza y
   acaba CUALQUIER nivel para poder recorrer la barra desde el XP anterior
   hasta el nuevo, cruzando los peldaños que haga falta.

   OJO: esto DEBE coincidir con `mirdaily_xp_for_level` de la base de datos
   (sql/2026-09-niveles.sql) y con `src/lib/levels.ts` de la web. Si algún día
   cambia la fórmula, cambia en los TRES sitios o la animación acabará en un
   número distinto del que enseña el servidor.

   Comprobaciones: nivel 12 = 3.575 XP, nivel 20 = 8.075, nivel 100 = 141.075.
   Al ser el coste lineal, el nivel es la raíz cuadrada del tiempo: decelera,
   pero sin muro. */

/// Lo que cuesta pasar del nivel [n] al n+1.
int costeNivel(int n) => 200 + 25 * (n - 1);

/// XP acumulado necesario para ESTAR en el nivel [nivel].
int xpParaNivel(int nivel) {
  if (nivel <= 1) return 0;
  return 200 * (nivel - 1) + (25 * (nivel - 1) * (nivel - 2)) ~/ 2;
}

/// Nivel que corresponde a un XP acumulado.
int nivelParaXp(num xp) {
  final objetivo = xp < 0 ? 0 : xp;
  var nivel = 1;
  while (nivel < kMaxLevel && xpParaNivel(nivel + 1) <= objetivo) {
    nivel += 1;
  }
  return nivel;
}
