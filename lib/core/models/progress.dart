/* ════════════════════════════════════════════════════════════════════════
   Nivel, XP, racha y desafíos: lo que devuelve `GET /api/progress`.

   Todo llega RESUELTO por el servidor. La app no calcula el nivel ni el XP en
   ningún sitio: solo lee. No existe ningún endpoint para sumar XP a propósito
   —lo concede el disparador de Postgres y los cierres de sesión—, así que aquí
   no hay nada que escribir.
═══════════════════════════════════════════════════════════════════════════ */

int _int(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _double(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

class UserProgress {
  /// 1..100, ya resuelto por el servidor.
  final int level;
  final int maxLevel;

  /// XP acumulado de toda la vida.
  final int xpTotal;

  /// XP conseguido DENTRO del nivel actual.
  final int xpIntoLevel;

  /// Lo que cuesta el nivel actual entero.
  final int xpForNext;

  final int currentStreak;
  final int longestStreak;

  /// Protectores de racha disponibles: cada uno cubre un hueco sin romperla.
  final int streakFreezes;

  /// De ×1,00 el primer día a ×1,50 el día 30, y ahí se queda.
  final double streakMultiplier;

  final String? lastActiveDay;

  /// XP de hoy que CONSUME tope. Es lo que mide la barra del tope, y solo eso.
  final int xpToday;

  /// TODO el XP ganado hoy, premios semanales incluidos.
  ///
  /// No es lo mismo que [xpToday] y confundirlos ya costó un fallo en la web:
  /// los premios semanales caen todos el mismo día y viven FUERA del tope, así
  /// que un domingo con los tres retos cerrados la pantalla decía "300 / 300"
  /// habiendo ganado 800. Esta es la cifra que se le enseña al usuario.
  final int xpTodayTotal;

  final int dailyCap;

  const UserProgress({
    required this.level,
    required this.maxLevel,
    required this.xpTotal,
    required this.xpIntoLevel,
    required this.xpForNext,
    required this.currentStreak,
    required this.longestStreak,
    required this.streakFreezes,
    required this.streakMultiplier,
    required this.lastActiveDay,
    required this.xpToday,
    required this.xpTodayTotal,
    required this.dailyCap,
  });

  factory UserProgress.fromJson(Map<String, dynamic> json) {
    final xpToday = _int(json['xpToday']);
    return UserProgress(
      level: _int(json['level'], 1),
      maxLevel: _int(json['maxLevel'], 100),
      xpTotal: _int(json['xpTotal']),
      xpIntoLevel: _int(json['xpIntoLevel']),
      xpForNext: _int(json['xpForNext'], 200),
      currentStreak: _int(json['currentStreak']),
      longestStreak: _int(json['longestStreak']),
      streakFreezes: _int(json['streakFreezes']),
      streakMultiplier: _double(json['streakMultiplier'], 1),
      lastActiveDay: json['lastActiveDay'] as String?,
      xpToday: xpToday,
      // Las respuestas antiguas del backend no lo traen. Caer en xpToday es lo
      // más honesto que se puede decir sin inventar: como mucho se queda corto.
      xpTodayTotal: json.containsKey('xpTodayTotal')
          ? _int(json['xpTodayTotal'], xpToday)
          : xpToday,
      dailyCap: _int(json['dailyCap'], 300),
    );
  }

  /// Estado de partida, para pintar algo mientras llega la primera respuesta.
  static const vacio = UserProgress(
    level: 1,
    maxLevel: 100,
    xpTotal: 0,
    xpIntoLevel: 0,
    xpForNext: 200,
    currentStreak: 0,
    longestStreak: 0,
    streakFreezes: 0,
    streakMultiplier: 1,
    lastActiveDay: null,
    xpToday: 0,
    xpTodayTotal: 0,
    dailyCap: 300,
  );

  bool get esTope => level >= maxLevel;

  /// Lo que falta para el siguiente peldaño.
  int get xpRestante {
    final n = xpForNext - xpIntoLevel;
    return n < 0 ? 0 : n;
  }

  /// Avance dentro del nivel, de 0 a 1.
  double get fraccionNivel {
    if (esTope) return 1;
    final coste = xpForNext <= 0 ? 1 : xpForNext;
    return (xpIntoLevel / coste).clamp(0.0, 1.0);
  }

  /// Cuánto del tope diario se ha gastado, de 0 a 1.
  double get fraccionTope {
    final cap = dailyCap <= 0 ? 1 : dailyCap;
    return (xpToday / cap).clamp(0.0, 1.0);
  }

  /// XP de hoy que NO ha gastado tope (premios semanales).
  int get xpFueraDeTope {
    final n = xpTodayTotal - xpToday;
    return n < 0 ? 0 : n;
  }
}

class Challenge {
  final String code;

  /// `daily` | `weekly`.
  final String scope;

  /// Qué mide.
  ///
  /// **Cuidado con `all_daily`**: el desafío "Día redondo" es el BONO por
  /// completar los otros tres, no un cuarto desafío. Al contar "cuántos llevas
  /// hoy" hay que excluirlo, o el usuario verá "1/4" cuando en pantalla solo
  /// hay tres tareas de verdad. Se muestra en la lista, pero no se cuenta.
  final String metric;

  final String title;
  final String description;
  final int progress;
  final int target;
  final int xpReward;
  final bool completed;
  final int sortOrder;

  /// Solo en el desafío personalizado: `topic_id`, `topic_name`,
  /// `subject_name` y `accuracy` del tema más flojo del usuario.
  final Map<String, dynamic>? meta;

  const Challenge({
    required this.code,
    required this.scope,
    required this.metric,
    required this.title,
    required this.description,
    required this.progress,
    required this.target,
    required this.xpReward,
    required this.completed,
    required this.sortOrder,
    required this.meta,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      code: (json['code'] ?? '').toString(),
      scope: (json['scope'] ?? 'daily').toString(),
      metric: (json['metric'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      progress: _int(json['progress']),
      target: _int(json['target'], 1),
      xpReward: _int(json['xpReward']),
      completed: json['completed'] == true,
      sortOrder: _int(json['sortOrder']),
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : null,
    );
  }

  /// El bono de "Día redondo", que no cuenta como tarea.
  bool get esBono => metric == 'all_daily';

  bool get esSemanal => scope == 'weekly';

  /// Avance, de 0 a 1.
  double get fraccion {
    final t = target <= 0 ? 1 : target;
    return (progress / t).clamp(0.0, 1.0);
  }
}

/// La respuesta entera de `/api/progress`: es la única llamada que hace falta
/// para pintar toda la pantalla de progreso.
class ProgressSnapshot {
  final UserProgress progress;
  final List<Challenge> daily;
  final List<Challenge> weekly;

  const ProgressSnapshot({
    required this.progress,
    required this.daily,
    required this.weekly,
  });

  factory ProgressSnapshot.fromJson(Map<String, dynamic> json) {
    List<Challenge> lista(dynamic v) => (v is List)
        ? v
            .whereType<Map>()
            .map((e) => Challenge.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <Challenge>[];

    return ProgressSnapshot(
      progress: json['progress'] is Map
          ? UserProgress.fromJson(
              Map<String, dynamic>.from(json['progress'] as Map))
          : UserProgress.vacio,
      daily: lista(json['daily']),
      weekly: lista(json['weekly']),
    );
  }

  /// Los desafíos del día que SON tareas (sin el bono de "Día redondo").
  List<Challenge> get dailyReales =>
      daily.where((c) => !c.esBono).toList(growable: false);

  int get dailyHechos => dailyReales.where((c) => c.completed).length;

  List<Challenge> get todos => [...daily, ...weekly];
}

/// Un día de la serie de `/api/progress/history`.
class XpHistoryDay {
  final String day;
  final int xp;

  /// De dónde salió: `question`, `daily_complete`, `daily_perfect`,
  /// `challenge_daily`, `recovery`…
  final Map<String, int> bySource;

  const XpHistoryDay({
    required this.day,
    required this.xp,
    required this.bySource,
  });

  factory XpHistoryDay.fromJson(Map<String, dynamic> json) {
    final fuentes = <String, int>{};
    final raw = json['by_source'];
    if (raw is Map) {
      raw.forEach((k, v) => fuentes[k.toString()] = _int(v));
    }
    return XpHistoryDay(
      day: (json['day'] ?? '').toString(),
      xp: _int(json['xp']),
      bySource: fuentes,
    );
  }
}
