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

   ─── CONTRATO COMÚN CON LA WEB (src/lib/logros.ts) ──────────────────────
   Este fichero y su gemelo de la web implementan la misma especificación, y
   los dos deben cambiar a la vez. Salió del incidente del 21/09/2026, cuando
   entrar al perfil disparó varios avisos de subida de nivel seguidos:

   1. REFERENCIA Y COLA POR USUARIO. La clave lleva el id de quien la produjo.
      Antes eran globales: cambiar de cuenta en el mismo aparato celebraba en
      la cuenta nueva los logros de la anterior.
   2. UNA FOTO ANÓMALA NO SE GUARDA NI SE PINTA (ver [fotoAnomala]). Un 200 con
      nivel 1 y cero XP encima de una referencia de nivel 12 no es un dato: es
      el servidor tragándose un error, o un cuerpo que no era JSON. Tomarlo por
      bueno era lo que hacía volver a celebrar el nivel entero después.
   3. LOS SALTOS SE FUNDEN (ver [fusionarSaltos]). Un usuario no sube dos
      veces: sube UNA VEZ, de un sitio a otro. Dos entradas "Nivel 11" y
      "Nivel 12" son dos recargas, no dos logros.
   4. EL PERMISO DE CELEBRAR CADUCA. Lo vigila el provider, no este fichero.
   5. LOS DESAFÍOS SE RECUERDAN POR CÓDIGO **Y PERIODO**. "Haz el Daily" de
      ayer y el de hoy son dos logros distintos; con solo el código, el segundo
      día dejaba de celebrarse.
   6. LA REFERENCIA ESTÁ VERSIONADA. Una guardada por el código viejo no se
      puede reinterpretar (sus `hechos` no llevan periodo), así que se descarta
      y se vuelve a tomar la foto en silencio: se pierde como mucho una
      celebración pendiente, nunca al revés.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../theme/levels.dart';
import 'progress.dart';

/// Formato de la referencia guardada. Se sube cuando su contenido deja de ser
/// interpretable por el código nuevo; una referencia de otra versión se tira.
const int kVersionReferencia = 2;

/// Las claves de antes del 21/09/2026: una sola para todo el aparato, sin
/// dueño. Se borran al arrancar porque no hay forma de saber de quién eran.
const String _claveReferenciaHeredada = 'mirdaily.logros.referencia';
const String _claveColaHeredada = 'mirdaily.logros.pendientes';

String _claveReferencia(String usuario) =>
    'mirdaily.logros.referencia.$usuario';
String _claveCola(String usuario) => 'mirdaily.logros.pendientes.$usuario';

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

  /// Desafíos ya celebrados, como `código|periodo` (ver [Challenge.claveHecho]).
  ///
  /// El periodo NO es adorno: sin él, "Haz el Daily" solo se celebraba el
  /// primer día y nunca más, porque el código ya estaba en la lista.
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
            if (c.completed) c.claveHecho,
        ],
      );

  Map<String, dynamic> toJson() => {
        'v': kVersionReferencia,
        'nivel': nivel,
        'xpTotal': xpTotal,
        'racha': racha,
        'hechos': hechos,
      };

  static Referencia? fromJson(Map<String, dynamic> json) {
    // Una referencia de otra versión no se puede reinterpretar: la v1 guardaba
    // los desafíos sin periodo, y tomarla por buena celebraría de golpe todos
    // los desafíos del día. Se descarta y se vuelve a fotografiar en silencio.
    final v = json['v'];
    if (v is! num || v.toInt() != kVersionReferencia) return null;

    final nivel = json['nivel'];
    final racha = json['racha'];
    if (nivel is! num || racha is! num) return null;
    return Referencia(
      nivel: nivel.toInt(),
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

/// Guarda y recupera la referencia y la cola, SIEMPRE bajo el id de su dueño.
/// Si el disco falla se pierde como mucho una celebración; nunca al revés.
class LogrosStore {
  const LogrosStore();

  Future<Referencia?> leerReferencia(String usuario) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_claveReferencia(usuario));
      if (crudo == null) return null;
      final json = jsonDecode(crudo);
      if (json is! Map) return null;
      return Referencia.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarReferencia(String usuario, Referencia ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _claveReferencia(usuario), jsonEncode(ref.toJson()));
    } catch (_) {}
  }

  Future<List<Logro>> leerPendientes(String usuario) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_claveCola(usuario));
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

  Future<void> guardarPendientes(String usuario, List<Logro> logros) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (logros.isEmpty) {
        await prefs.remove(_claveCola(usuario));
      } else {
        await prefs.setString(
          _claveCola(usuario),
          jsonEncode([for (final l in logros) l.toJson()]),
        );
      }
    } catch (_) {}
  }

  /// Borra lo de UN usuario. Ya no hace falta al cerrar sesión —cada cuenta
  /// tiene su sitio—, pero sigue existiendo para un borrado explícito.
  Future<void> limpiar(String usuario) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_claveReferencia(usuario));
      await prefs.remove(_claveCola(usuario));
    } catch (_) {}
  }

  /// Tira las claves globales de antes del 21/09/2026.
  ///
  /// No se pueden adoptar: no llevan dueño, y en un aparato donde se han usado
  /// dos cuentas no hay manera de saber de quién era la referencia. Lo que se
  /// pierde es, como mucho, una celebración pendiente. Lo que se evita es
  /// celebrarle a alguien el nivel de otro.
  Future<void> purgarSinDuenno() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_claveReferenciaHeredada);
      await prefs.remove(_claveColaHeredada);
    } catch (_) {}
  }
}

/// ¿Esta respuesta puede creerse?
///
/// Solo se rechaza lo que NO puede ser verdad, no cualquier cosa rara: si el
/// ledger se reconstruye y el nivel baja de verdad, hay que enseñarlo (sin
/// celebrarlo, de eso ya se encarga [detectarLogros], que solo mira hacia
/// arriba). Lo que se rechaza es la firma exacta de las dos averías conocidas:
///
///   · el fallback que devolvía `/api/progress` cuando `tryRpc` se tragaba un
///     error de Supabase: 200 con nivel 1, cero XP y sin desafíos;
///   · un 2xx cuyo cuerpo no era JSON, que `ApiService` convierte en `{}` y el
///     modelo en ese mismo estado de usuario recién nacido.
///
/// Las dos son indistinguibles de un usuario nuevo de verdad MIRANDO SOLO la
/// respuesta. Por eso hace falta la referencia: un usuario que ayer iba por el
/// nivel 12 no amanece en el 1.
bool fotoAnomala(Referencia? ref, ProgressSnapshot datos) {
  // Sin referencia no hay con qué comparar: es la primera vez que se ve a esta
  // cuenta y nivel 1 con cero XP es exactamente lo que le toca.
  if (ref == null) return false;

  final p = datos.progress;

  if (p.level <= 1 && p.xpTotal <= 0 && (ref.nivel > 1 || ref.xpTotal > 0)) {
    return true;
  }

  // Los desafíos desaparecidos: tenía alguno hecho y ahora no llega ni la
  // lista. Guardar esa foto vaciaría `hechos` y al volver la lista se
  // celebrarían todos otra vez.
  if (datos.todos.isEmpty && ref.hechos.isNotEmpty) return true;

  return false;
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
    if (c.completed && !yaVistos.contains(c.claveHecho)) {
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

/// Deja UN solo salto de nivel en la cola, del principio del primero al final
/// del último.
///
/// La referencia avanza en cuanto se detecta el logro, así que cada recarga
/// solo ve SU trocito: recargar tres veces mientras se sube del 9 al 12
/// encolaba "Nivel 10", "Nivel 11" y "Nivel 12", tres tarjetas seguidas para
/// una sola subida. Y al usar la app y la web a la vez pasa constantemente,
/// porque cada una lleva su propia referencia.
///
/// Conserva el id del primero a propósito: si la tarjeta ya está en pantalla,
/// cambiar el id cambiaría su `ValueKey` y el framework la remontaría a mitad
/// de animación.
List<Logro> fusionarSaltos(List<Logro> cola) {
  final out = <Logro>[];
  var indiceSalto = -1;

  for (final l in cola) {
    if (!l.esSalto) {
      out.add(l);
      continue;
    }
    if (indiceSalto < 0) {
      indiceSalto = out.length;
      out.add(l);
      continue;
    }
    out[indiceSalto] = _fundir(out[indiceSalto], l);
  }

  return out;
}

Logro _fundir(Logro a, Logro b) {
  final nivel = a.nivel >= b.nivel ? a.nivel : b.nivel;

  // Si CUALQUIERA de los peldaños cruzó un rango, el tramo entero lo cruzó.
  final esRango = a.tipo == TipoLogro.rango || b.tipo == TipoLogro.rango;

  // Un `xpAntes` a cero es "no se sabe" (el campo se omite al serializar
  // cuando vale 0), no "empezó de cero": tomarlo por el mínimo mandaría la
  // barra al principio de la curva.
  final candidatos = [a.xpAntes, b.xpAntes].where((x) => x > 0);
  final xpAntes = candidatos.isEmpty
      ? 0
      : candidatos.reduce((x, y) => x < y ? x : y);

  return Logro(
    id: a.id,
    tipo: esRango ? TipoLogro.rango : TipoLogro.nivel,
    nivel: nivel,
    rango: rankForLevel(nivel).name,
    xpAntes: xpAntes,
    xpDespues: a.xpDespues >= b.xpDespues ? a.xpDespues : b.xpDespues,
  );
}

/// De más importante a menos.
List<Logro> ordenarPorPeso(List<Logro> logros) {
  final copia = [...logros];
  copia.sort((a, b) => b.peso.compareTo(a.peso));
  return copia;
}
