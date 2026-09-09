/* ════════════════════════════════════════════════════════════════════════
   Detección de metas cumplidas.

   El backend no manda "has subido de nivel": manda el ESTADO. El logro se
   deduce comparando el estado nuevo con el último que vimos. Tiene una ventaja
   que no es menor: no hace falta ningún endpoint nuevo ni ninguna tabla de
   "notificaciones de logro" que mantener sincronizada.

   LA REFERENCIA Y LA COLA VAN A DISCO, no a memoria. Esto ya falló una vez en
   la web: la referencia avanza en cuanto se detecta el logro, así que si la
   cola viviera solo en memoria, subir de nivel y cerrar la app antes de que
   hubiera permiso para celebrarlo haría desaparecer la meta para siempre —la
   comparación siguiente ya no encontraría diferencia—. Un logro se descarta
   SOLO cuando se ha enseñado de verdad.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../theme/levels.dart';
import 'progress.dart';

const String _claveReferencia = 'mirdaily.logros.referencia';
const String _claveCola = 'mirdaily.logros.pendientes';

/// Los hitos de racha se celebran; los días sueltos no. Felicitar cada día
/// convierte la celebración en ruido y deja de significar nada.
const List<int> kHitosRacha = [3, 7, 15, 30, 50, 100, 200, 365];

enum TipoLogro { rango, nivel, racha, desafio }

/// El más importante manda: es el que da titular a la celebración.
const Map<TipoLogro, int> _peso = {
  TipoLogro.rango: 4,
  TipoLogro.nivel: 3,
  TipoLogro.racha: 2,
  TipoLogro.desafio: 1,
};

var _contador = 0;

/// Identificador único dentro de esta ejecución.
///
/// Cada logro lleva identidad propia y no es burocracia: sin ella dos avisos
/// seguidos comparten clave, el framework reutiliza el nodo y cambia el texto
/// sin animar nada. Se ve como si el aviso no tuviera entrada.
String nuevoIdLogro() {
  _contador += 1;
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$_contador';
}

class Logro {
  final String id;
  final TipoLogro tipo;

  /// Nivel alcanzado (`nivel` y `rango`).
  final int nivel;

  /// Nombre del rango nuevo (`rango`).
  final String? rango;

  /// Días de racha (`racha`).
  final int dias;

  /// Título del desafío (`desafio`).
  final String? titulo;

  /// Premio en XP del desafío (`desafio`).
  final int xp;

  /// `daily` | `weekly` (`desafio`).
  final String? scope;

  /// El tramo que recorrerá la barra en la animación de subida.
  ///
  /// El logro lleva el TRAMO, no solo el resultado: sin el XP de antes no
  /// habría desde dónde contar y la barra tendría que arrancar del principio
  /// del nivel, que sería mentira.
  final int xpAntes;
  final int xpDespues;

  const Logro({
    required this.id,
    required this.tipo,
    this.nivel = 0,
    this.rango,
    this.dias = 0,
    this.titulo,
    this.xp = 0,
    this.scope,
    this.xpAntes = 0,
    this.xpDespues = 0,
  });

  bool get esSalto => tipo == TipoLogro.nivel || tipo == TipoLogro.rango;

  int get peso => _peso[tipo] ?? 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo.name,
        if (nivel != 0) 'nivel': nivel,
        if (rango != null) 'rango': rango,
        if (dias != 0) 'dias': dias,
        if (titulo != null) 'titulo': titulo,
        if (xp != 0) 'xp': xp,
        if (scope != null) 'scope': scope,
        if (xpAntes != 0) 'xpAntes': xpAntes,
        if (xpDespues != 0) 'xpDespues': xpDespues,
      };

  static Logro? fromJson(Map<String, dynamic> json) {
    TipoLogro? tipo;
    for (final t in TipoLogro.values) {
      if (t.name == json['tipo']) tipo = t;
    }
    if (tipo == null) return null;
    return Logro(
      id: (json['id'] ?? nuevoIdLogro()).toString(),
      tipo: tipo,
      nivel: (json['nivel'] as num?)?.toInt() ?? 0,
      rango: json['rango'] as String?,
      dias: (json['dias'] as num?)?.toInt() ?? 0,
      titulo: json['titulo'] as String?,
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      scope: json['scope'] as String?,
      xpAntes: (json['xpAntes'] as num?)?.toInt() ?? 0,
      xpDespues: (json['xpDespues'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Lo que hay que recordar entre visitas para poder comparar.
class Referencia {
  final int nivel;

  /// XP acumulado la última vez que se miró. Es el punto de partida de la
  /// animación de subida.
  final int xpTotal;

  final int racha;

  /// Códigos de desafío ya completados, para no repetir el aviso.
  final List<String> hechos;

  const Referencia({
    required this.nivel,
    required this.xpTotal,
    required this.racha,
    required this.hechos,
  });

  /// Foto del estado actual.
  factory Referencia.de(ProgressSnapshot datos) => Referencia(
        nivel: datos.progress.level,
        xpTotal: datos.progress.xpTotal,
        racha: datos.progress.currentStreak,
        hechos: [
          for (final c in datos.todos)
            if (c.completed) c.code,
        ],
      );

  Map<String, dynamic> toJson() => {
        'nivel': nivel,
        'xpTotal': xpTotal,
        'racha': racha,
        'hechos': hechos,
      };

  static Referencia? fromJson(Map<String, dynamic> json) {
    final nivel = json['nivel'];
    final racha = json['racha'];
    if (nivel is! num || racha is! num) return null;
    return Referencia(
      nivel: nivel.toInt(),
      // Las referencias guardadas antes de que existiera la animación no lo
      // traen. Se rellena con el principio del nivel, que es lo más honesto
      // que se puede decir sin inventar: la barra arrancará vacía.
      xpTotal: json['xpTotal'] is num
          ? (json['xpTotal'] as num).toInt()
          : xpParaNivel(nivel.toInt()),
      racha: racha.toInt(),
      hechos: json['hechos'] is List
          ? (json['hechos'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// Guarda y recupera la referencia y la cola. Si el disco falla se pierde
/// como mucho una celebración; nunca al revés.
class LogrosStore {
  const LogrosStore();

  Future<Referencia?> leerReferencia() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_claveReferencia);
      if (crudo == null) return null;
      final json = jsonDecode(crudo);
      if (json is! Map) return null;
      return Referencia.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarReferencia(Referencia ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_claveReferencia, jsonEncode(ref.toJson()));
    } catch (_) {}
  }

  Future<List<Logro>> leerPendientes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_claveCola);
      if (crudo == null) return const [];
      final json = jsonDecode(crudo);
      if (json is! List) return const [];
      final out = <Logro>[];
      for (final e in json) {
        if (e is! Map) continue;
        final l = Logro.fromJson(Map<String, dynamic>.from(e));
        if (l != null) out.add(l);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> guardarPendientes(List<Logro> logros) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (logros.isEmpty) {
        await prefs.remove(_claveCola);
      } else {
        await prefs.setString(
          _claveCola,
          jsonEncode([for (final l in logros) l.toJson()]),
        );
      }
    } catch (_) {}
  }

  /// Al cerrar sesión: la referencia es de un usuario concreto y arrastrarla a
  /// la cuenta siguiente celebraría cosas que esa cuenta no ha conseguido.
  Future<void> limpiar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_claveReferencia);
      await prefs.remove(_claveCola);
    } catch (_) {}
  }
}

/// Qué ha cambiado a mejor entre la referencia y el estado nuevo.
///
/// Solo mira hacia arriba: si el nivel baja (una reconstrucción del ledger, por
/// ejemplo) no se celebra nada, faltaría más.
List<Logro> detectarLogros(Referencia ref, ProgressSnapshot datos) {
  final out = <Logro>[];
  final p = datos.progress;

  if (p.level > ref.nivel) {
    final rangoNuevo = rankForLevel(p.level);
    final rangoViejo = rankForLevel(ref.nivel);
    // Se protege de un XP anterior mayor que el nuevo arrancando, como mucho,
    // en el XP actual.
    final xpAntes = ref.xpTotal < p.xpTotal ? ref.xpTotal : p.xpTotal;

    // Cambiar de rango pesa más que subir un nivel, así que se anuncia como
    // rango y no se duplica el aviso.
    out.add(Logro(
      id: nuevoIdLogro(),
      tipo: rangoNuevo.name != rangoViejo.name
          ? TipoLogro.rango
          : TipoLogro.nivel,
      nivel: p.level,
      rango: rangoNuevo.name,
      xpAntes: xpAntes,
      xpDespues: p.xpTotal,
    ));
  }

  if (p.currentStreak > ref.racha && kHitosRacha.contains(p.currentStreak)) {
    out.add(Logro(
      id: nuevoIdLogro(),
      tipo: TipoLogro.racha,
      dias: p.currentStreak,
    ));
  }

  final yaVistos = ref.hechos.toSet();
  for (final c in datos.todos) {
    if (c.completed && !yaVistos.contains(c.code)) {
      out.add(Logro(
        id: nuevoIdLogro(),
        tipo: TipoLogro.desafio,
        titulo: c.title,
        xp: c.xpReward,
        scope: c.scope,
      ));
    }
  }

  return out;
}

/// De más importante a menos.
List<Logro> ordenarPorPeso(List<Logro> logros) {
  final copia = [...logros];
  copia.sort((a, b) => b.peso.compareTo(a.peso));
  return copia;
}
