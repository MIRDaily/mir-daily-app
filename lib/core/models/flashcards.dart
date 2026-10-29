// Flashcards: lo que no es pantalla. Ajustes de la sesión de estudio, escalera de dificultad,
// intervalos de los botones, previsión y estadísticas, temas de un grupo y asignatura reconocida
// por el nombre. Puro (sin Flutter): se prueba en test/flashcards_logica_test.dart con los mismos
// casos que la web.
//
// Puerto de la web: src/lib/flashcards/sesion.ts, src/lib/flashcards/escalera.ts,
// src/components/flashcards/GradeButtons.tsx (formatInterval), src/components/flashcards/TopicList.tsx
// (groupTopics), src/components/flashcards/SubjectList.tsx (groupSubjects) y src/lib/subjectVisuals.ts.
//
// Las REGLAS (qué nivel está abierto, qué tarjetas salen en la sesión, cuándo vuelve una tarjeta)
// son del servidor. Aquí solo se arma la petición, se avisa de cuántas van a salir y se redacta.

import '../data/mir_weights.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Niveles de dificultad del contenido
// ---------------------------------------------------------------------------

const List<int> kFlashLevels = [1, 2, 3, 4];

const Map<int, String> kFlashLevelName = {1: 'Fácil', 2: 'Media', 3: 'Difícil', 4: 'Demencial'};

String nombreNivel(int n) => kFlashLevelName[n] ?? '';

/// Orden alfabético en español: sin tildes primero y, a igualdad, el texto tal cual (como
/// `localeCompare(x, 'es')` en lo que importa aquí: que «Úlcera» no se vaya detrás de la zeta).
int compararEs(String a, String b) {
  final r = plano(a).compareTo(plano(b));
  return r != 0 ? r : a.compareTo(b);
}

const Map<String, String> _sinTilde = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n~', 'ç': 'c',
};

/// En minúsculas y sin tildes (la eñe va detrás de la ene).
String plano(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_sinTilde[ch] ?? ch);
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Escalera de dificultad (la calcula get_flashcard_ladder en el servidor)
// ---------------------------------------------------------------------------

class EscalonEscalera {
  final int level;

  /// Tarjetas de este nivel en el tema.
  final int total;
  final int mastered;

  /// Tarjetas (y dominadas) de los niveles inferiores del tema: lo que lo abre.
  final int lowerTotal;
  final int lowerMastered;

  /// Dominadas de lo inferior que hacen falta (el 80 %, redondeado hacia arriba).
  final int needed;
  final bool unlocked;

  const EscalonEscalera({
    required this.level,
    this.total = 0,
    this.mastered = 0,
    this.lowerTotal = 0,
    this.lowerMastered = 0,
    this.needed = 0,
    this.unlocked = false,
  });
}

class TemaEscalera {
  /// null = las tarjetas sin tema.
  final String? topic;
  final List<EscalonEscalera> levels;

  const TemaEscalera(this.topic, this.levels);
}

class Escalera {
  final List<TemaEscalera> topics;

  const Escalera(this.topics);
}

int _entero(dynamic v) => v is int && v >= 0 ? v : (v is num && v == v.toInt() && v >= 0 ? v.toInt() : 0);

/// Lo que manda el servidor → escalera válida (lo demás se ignora).
Escalera sanearEscalera(dynamic raw) {
  final topics = <TemaEscalera>[];
  final lista = raw is Map && raw['topics'] is List ? (raw['topics'] as List).take(500) : const [];
  for (final t in lista) {
    if (t is! Map) continue;
    final levels = <EscalonEscalera>[];
    for (final l in t['levels'] is List ? t['levels'] as List : const []) {
      if (l is! Map) continue;
      final level = Flashcard.levelDe(l['level']);
      if (level == null || levels.any((e) => e.level == level)) continue;
      levels.add(EscalonEscalera(
        level: level,
        total: _entero(l['total']),
        mastered: _entero(l['mastered']),
        lowerTotal: _entero(l['lowerTotal']),
        lowerMastered: _entero(l['lowerMastered']),
        needed: _entero(l['needed']),
        unlocked: l['unlocked'] == true,
      ));
    }
    if (levels.isEmpty) continue;
    levels.sort((a, b) => a.level - b.level);
    final topic = t['topic'];
    topics.add(TemaEscalera(
      topic is String && topic.trim().isNotEmpty ? (topic.length > 120 ? topic.substring(0, 120) : topic) : null,
      levels,
    ));
  }
  return Escalera(topics);
}

/// ¿Hay escalera que enseñar? (algún tema con más de un nivel; con uno solo, todo está abierto).
bool hayEscalera(Escalera? e) => e != null && e.topics.any((t) => t.levels.length > 1);

/// «fácil», «fácil y media», «fácil, media y difícil».
String nombresNiveles(List<int> niveles) {
  final n = niveles.map((k) => nombreNivel(k).toLowerCase()).toList();
  if (n.length <= 1) return n.isEmpty ? '' : n.first;
  return '${n.sublist(0, n.length - 1).join(', ')} y ${n.last}';
}

List<int> nivelesInferiores(TemaEscalera t, int level) =>
    t.levels.where((l) => l.level < level).map((l) => l.level).toList();

/// Cuánto falta para abrir un nivel cerrado: «12 de 20 dominadas de fácil y media (hacen falta 16)».
/// Si lo de abajo ya cumple pero un escalón anterior sigue cerrado, se dice cuál.
String textoFalta(TemaEscalera t, EscalonEscalera e) {
  final de = nombresNiveles(nivelesInferiores(t, e.level));
  final base = '${e.lowerMastered} de ${e.lowerTotal} dominadas de $de';
  if (e.lowerMastered >= e.needed) {
    for (final l in t.levels) {
      if (l.level < e.level && !l.unlocked) return '$base; antes hay que abrir ${nombreNivel(l.level).toLowerCase()}';
    }
  }
  return '$base (hacen falta ${e.needed})';
}

typedef Desbloqueo = ({String? topic, int level});

/// Lo que se ha abierto entre dos fotos de la escalera (antes y después de una sesión).
List<Desbloqueo> desbloqueados(Escalera? antes, Escalera? despues) {
  if (antes == null || despues == null) return const [];
  String clave(String? topic, int level) => '${topic ?? ''}\u0000$level';
  final abiertos = <String>{
    for (final t in antes.topics)
      for (final l in t.levels)
        if (l.unlocked) clave(t.topic, l.level),
  };
  final out = <Desbloqueo>[];
  for (final t in despues.topics) {
    for (final l in t.levels) {
      // Solo si antes existía y estaba cerrado (un nivel nuevo que aparece abierto no es un logro).
      final existia = antes.topics.any((a) => a.topic == t.topic && a.levels.any((x) => x.level == l.level));
      if (l.unlocked && existia && !abiertos.contains(clave(t.topic, l.level))) out.add((topic: t.topic, level: l.level));
    }
  }
  return out;
}

/// «Has desbloqueado Difícil en Arteritis de células gigantes» (uno o varios).
String textoDesbloqueo(List<Desbloqueo> lista) {
  if (lista.isEmpty) return '';
  String uno(Desbloqueo d) => '${nombreNivel(d.level)}${d.topic != null ? ' en ${d.topic}' : ''}';
  if (lista.length == 1) return 'Has desbloqueado ${uno(lista.first)}';
  if (lista.length <= 3) {
    return 'Has desbloqueado ${lista.sublist(0, lista.length - 1).map(uno).join(', ')} y ${uno(lista.last)}';
  }
  return 'Has desbloqueado ${lista.length} niveles: ${lista.take(2).map(uno).join(', ')} y ${lista.length - 2} más';
}

/// Cuántas tarjetas abiertas y cerradas hay, y cuántos niveles cerrados.
({int abiertas, int cerradas, int nivelesCerrados}) resumenEscalera(Escalera e) {
  var abiertas = 0, cerradas = 0, nivelesCerrados = 0;
  for (final t in e.topics) {
    for (final l in t.levels) {
      if (l.unlocked) {
        abiertas += l.total;
      } else {
        cerradas += l.total;
        nivelesCerrados += 1;
      }
    }
  }
  return (abiertas: abiertas, cerradas: cerradas, nivelesCerrados: nivelesCerrados);
}

// ---------------------------------------------------------------------------
// Ajustes de la sesión («Estudiar» → cuántas, qué tarjetas, temas, dificultad y escalera)
// ---------------------------------------------------------------------------

enum SoloTarjetas { todas, failed, due, nueva }

extension SoloTarjetasId on SoloTarjetas {
  /// Como lo guarda la web y lo espera el servidor (`onlyStatus`).
  String get id => switch (this) {
        SoloTarjetas.todas => 'todas',
        SoloTarjetas.failed => 'failed',
        SoloTarjetas.due => 'due',
        SoloTarjetas.nueva => 'new',
      };
}

class AjustesSesion {
  /// Cuántas tarjetas distintas (null = todas las que coincidan).
  final int? cantidad;
  final SoloTarjetas solo;

  /// Temas elegidos (tal cual; '' = sin tema). null = todos.
  final List<String>? temas;
  final List<int> niveles;
  final bool escalera;

  const AjustesSesion({
    this.cantidad = 20,
    this.solo = SoloTarjetas.todas,
    this.temas,
    this.niveles = kFlashLevels,
    this.escalera = true,
  });

  AjustesSesion copyWith({
    int? Function()? cantidad,
    SoloTarjetas? solo,
    List<String>? Function()? temas,
    List<int>? niveles,
    bool? escalera,
  }) =>
      AjustesSesion(
        cantidad: cantidad != null ? cantidad() : this.cantidad,
        solo: solo ?? this.solo,
        temas: temas != null ? temas() : this.temas,
        niveles: niveles ?? this.niveles,
        escalera: escalera ?? this.escalera,
      );

  Map<String, dynamic> toJson() => {
        'cantidad': cantidad,
        'solo': solo.id,
        'temas': temas,
        'niveles': niveles,
        'escalera': escalera,
      };
}

const List<int> kCantidades = [10, 20, 50];

const List<({SoloTarjetas id, String titulo, String descripcion})> kOpcionesSolo = [
  (id: SoloTarjetas.todas, titulo: 'Todas', descripcion: 'Primero lo fallado y lo que toca repasar.'),
  (id: SoloTarjetas.due, titulo: 'Pendientes', descripcion: 'Las que ya has visto y toca repasar.'),
  (id: SoloTarjetas.failed, titulo: 'Solo falladas', descripcion: 'Las que fallaste la última vez.'),
  (id: SoloTarjetas.nueva, titulo: 'Solo nuevas', descripcion: 'Las que aún no has estudiado.'),
];

const AjustesSesion kAjustesPorDefecto = AjustesSesion();

/// ¿Entra la tarjeta en «qué tarjetas»? Las mismas definiciones que el servidor.
bool coincideSolo(Flashcard c, SoloTarjetas solo) => switch (solo) {
      SoloTarjetas.failed => c.status == FlashStatus.failed,
      SoloTarjetas.nueva => c.status == FlashStatus.nueva,
      SoloTarjetas.due => c.status != FlashStatus.nueva && c.isDue,
      SoloTarjetas.todas => true,
    };

/// Las tarjetas que coinciden con los ajustes (sin el tope). Con filtro de niveles, las que no tienen
/// nivel no entran (como en la cola). Con escalera y su foto (la del servidor), las nuevas de un nivel
/// cerrado tampoco: así el número que se avisa es el que va a salir.
List<Flashcard> coinciden(List<Flashcard> cards, AjustesSesion a, [Escalera? escalera]) {
  final todosNiveles = a.niveles.length == kFlashLevels.length;
  final temas = a.temas?.toSet();
  final cerrados = <String>{};
  if (a.escalera && escalera != null) {
    for (final t in escalera.topics) {
      for (final l in t.levels) {
        if (!l.unlocked) cerrados.add('${(t.topic ?? '').trim()}|${l.level}');
      }
    }
  }
  return cards
      .where((c) =>
          coincideSolo(c, a.solo) &&
          (temas == null || temas.contains(c.tema)) &&
          (todosNiveles || (c.level != null && a.niveles.contains(c.level))) &&
          !(c.status == FlashStatus.nueva && c.level != null && cerrados.contains('${c.tema}|${c.level}')))
      .toList();
}

/// Los temas del grupo con cuántas tarjetas tiene cada uno, por orden alfabético (sin tema, al final).
List<({String tema, int total})> temasDelGrupo(List<Flashcard> cards) {
  final m = <String, int>{};
  for (final c in cards) {
    m[c.tema] = (m[c.tema] ?? 0) + 1;
  }
  final out = [for (final e in m.entries) (tema: e.key, total: e.value)];
  out.sort((x, y) => x.tema.isEmpty ? 1 : (y.tema.isEmpty ? -1 : compararEs(x.tema, y.tema)));
  return out;
}

/// Ajustes → lo que se manda al empezar: los filtros (solo los que filtran algo) y el tope de servidas
/// (con las repeticiones de las falladas: el doble de las tarjetas, entre 20 y 200).
({int limit, Map<String, dynamic> opciones}) paraEmpezar(
  AjustesSesion a,
  List<Flashcard> cards,
  bool conNivel, [
  Escalera? escalera,
]) {
  final n = coinciden(cards, a.copyWith(escalera: conNivel && a.escalera), escalera).length;
  final tarjetas = a.cantidad != null ? (a.cantidad! < n ? a.cantidad! : n) : n;
  final todosTemas = a.temas == null || temasDelGrupo(cards).every((t) => a.temas!.contains(t.tema));
  final limit = (tarjetas * 2).clamp(20, 200);
  return (
    limit: limit,
    opciones: <String, dynamic>{
      if (conNivel && a.niveles.length < kFlashLevels.length) 'levels': a.niveles,
      'ladder': conNivel && a.escalera,
      if (!todosTemas && a.temas!.isNotEmpty) 'topics': a.temas,
      if (a.solo != SoloTarjetas.todas) 'onlyStatus': a.solo.id,
      if (a.cantidad != null) 'cardLimit': a.cantidad,
    },
  );
}

/// Lo leído (de las preferencias) no se da por bueno: se reconstruye con valores válidos.
AjustesSesion sanearAjustes(dynamic raw) {
  final r = raw is Map ? raw : const {};
  final cantidad = r.containsKey('cantidad') && r['cantidad'] == null
      ? null
      : (kCantidades.contains(r['cantidad']) ? r['cantidad'] as int : kAjustesPorDefecto.cantidad);
  final solo = SoloTarjetas.values.firstWhere((s) => s.id == r['solo'], orElse: () => SoloTarjetas.todas);
  final temasRaw = r['temas'] is List ? (r['temas'] as List).whereType<String>().take(200).toList() : null;
  final nivelesRaw = r['niveles'] is List ? r['niveles'] as List : const [];
  final niveles = kFlashLevels.where((n) => nivelesRaw.any((x) => x is int && x == n)).toList();
  return AjustesSesion(
    cantidad: cantidad,
    solo: solo,
    temas: temasRaw != null && temasRaw.isNotEmpty ? temasRaw : null,
    niveles: niveles.isEmpty ? kFlashLevels : niveles,
    escalera: r['escalera'] != false,
  );
}

// ---------------------------------------------------------------------------
// Intervalos de los botones de respuesta
// ---------------------------------------------------------------------------

/// Intervalo en la forma corta de Anki. Por debajo de un día se dan minutos u horas, porque
/// `scheduledDays` sale 0 en los primeros pasos y decir «0 d» no significa nada.
String formatInterval(GradePreview? p, DateTime from) {
  if (p == null) return '—';
  final days = p.scheduledDays;
  if (days >= 365) {
    final years = days / 365;
    if (years < 10) {
      final t = years.toStringAsFixed(1);
      return '${t.endsWith('.0') ? t.substring(0, t.length - 2) : t} a';
    }
    return '${years.round()} a';
  }
  if (days >= 30) return '${(days / 30).round()} m';
  if (days >= 1) return '$days d';
  final minutes = (p.due.difference(from).inMilliseconds / 60000).round();
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  return '${(minutes / 60).round()} h';
}

// ---------------------------------------------------------------------------
// Previsión y estado (GET /flashcards/forecast y /flashcards/stats)
// ---------------------------------------------------------------------------

class FlashForecast {
  /// Vencidas de días anteriores. Van aparte para que no escondan el atasco.
  final int overdue;

  /// Un día por fila (fecha de Madrid, YYYY-MM-DD), empezando hoy.
  final List<({String date, int count})> days;

  const FlashForecast({this.overdue = 0, this.days = const []});

  int get total => days.fold(0, (n, d) => n + d.count);

  factory FlashForecast.fromJson(Map<String, dynamic> j) => FlashForecast(
        overdue: _entero(j['overdue']),
        days: [
          for (final d in j['days'] is List ? (j['days'] as List).take(120) : const [])
            if (d is Map && d['date'] is String) (date: d['date'] as String, count: _entero(d['count'])),
        ],
      );
}

class FlashStats {
  /// Reparto por intervalo asignado (no por racha).
  final int nuevas, learning, young, mature;
  final int reviews, passed, matureReviews;

  /// Null mientras no haya repasos sobre tarjetas ya programadas.
  final double? rate;
  final double? matureRate;

  const FlashStats({
    this.nuevas = 0,
    this.learning = 0,
    this.young = 0,
    this.mature = 0,
    this.reviews = 0,
    this.passed = 0,
    this.matureReviews = 0,
    this.rate,
    this.matureRate,
  });

  int get total => nuevas + learning + young + mature;

  factory FlashStats.fromJson(Map<String, dynamic> j) {
    final m = j['maturity'] is Map ? j['maturity'] as Map : const {};
    final r = j['retention'] is Map ? j['retention'] as Map : const {};
    double? tasa(dynamic v) => v is num && v.isFinite ? v.toDouble().clamp(0, 1) : null;
    return FlashStats(
      nuevas: _entero(m['new']),
      learning: _entero(m['learning']),
      young: _entero(m['young']),
      mature: _entero(m['mature']),
      reviews: _entero(r['reviews']),
      passed: _entero(r['passed']),
      matureReviews: _entero(r['matureReviews']),
      rate: tasa(r['rate']),
      matureRate: tasa(r['matureRate']),
    );
  }
}

// ---------------------------------------------------------------------------
// Temas de un grupo
// ---------------------------------------------------------------------------

class TopicRow {
  /// null = las tarjetas sin tema.
  final String? key;
  final String label;
  final int total;
  final int dueCards;
  final FlashSummary summary;

  const TopicRow({required this.key, required this.label, required this.total, required this.dueCards, required this.summary});

  int get dominio => total > 0 ? (summary.mastered * 100 / total).round() : 0;

  /// Lo que toca repasar sin nuevas ni falladas (cada tarjeta, en una sola columna).
  int get repasos {
    final r = dueCards - summary.nuevas - summary.failed;
    return r < 0 ? 0 : r;
  }
}

/// Agrupa las tarjetas por tema y cuenta sus cubos (el estado viene del servidor). Sin tema, al final.
List<TopicRow> groupTopics(List<Flashcard> cards) {
  final porTema = <String, List<Flashcard>>{};
  for (final c in cards) {
    (porTema[c.tema] ??= []).add(c);
  }
  final rows = [
    for (final e in porTema.entries)
      TopicRow(
        key: e.key.isEmpty ? null : e.key,
        label: e.key.isEmpty ? 'Sin tema' : e.key,
        total: e.value.length,
        dueCards: e.value.where((c) => c.isDue).length,
        summary: FlashSummary(
          nuevas: e.value.where((c) => c.status == FlashStatus.nueva).length,
          failed: e.value.where((c) => c.status == FlashStatus.failed).length,
          learning: e.value.where((c) => c.status == FlashStatus.learning).length,
          mastered: e.value.where((c) => c.status == FlashStatus.mastered).length,
        ),
      ),
  ];
  rows.sort((a, b) => a.key == null ? 1 : (b.key == null ? -1 : compararEs(a.label, b.label)));
  return rows;
}

// ---------------------------------------------------------------------------
// La asignatura de un grupo, reconocida por su nombre (categoría, sigla, color e icono)
// ---------------------------------------------------------------------------

enum CategoriaAsignatura { basica, medica, quirurgica, personal }

const Map<CategoriaAsignatura, String> kNombreCategoria = {
  CategoriaAsignatura.basica: 'Básicas',
  CategoriaAsignatura.medica: 'Médicas',
  CategoriaAsignatura.quirurgica: 'Quirúrgicas',
  // «Otros» y no «Personales»: agrupa todo lo que no se reconoce como asignatura del MIR.
  CategoriaAsignatura.personal: 'Otros',
};

typedef _Visual = ({String sigla, String icon, String color, CategoriaAsignatura cat});

const Map<String, _Visual> _visuales = {
  // Básicas
  'estadistica': (sigla: 'ES', icon: 'analytics', color: 'slate', cat: CategoriaAsignatura.basica),
  'inmunologia': (sigla: 'IM', icon: 'biotech', color: 'lavender', cat: CategoriaAsignatura.basica),
  'miscelanea': (sigla: 'MO', icon: 'menu_book', color: 'slate', cat: CategoriaAsignatura.basica),
  'farmacologia': (sigla: 'FM', icon: 'medication', color: 'gold', cat: CategoriaAsignatura.basica),
  'bioetica': (sigla: 'BE', icon: 'menu_book', color: 'lavender', cat: CategoriaAsignatura.basica),
  // Médicas
  'cardiologia': (sigla: 'CD', icon: 'cardiology', color: 'coral', cat: CategoriaAsignatura.medica),
  'dermatologia': (sigla: 'DM', icon: 'dermatology', color: 'rose', cat: CategoriaAsignatura.medica),
  'endocrinologia': (sigla: 'ED', icon: 'monitor_weight', color: 'gold', cat: CategoriaAsignatura.medica),
  'hematologia': (sigla: 'HM', icon: 'bloodtype', color: 'coral', cat: CategoriaAsignatura.medica),
  'infecciosas': (sigla: 'IF', icon: 'coronavirus', color: 'teal', cat: CategoriaAsignatura.medica),
  'nefrologia': (sigla: 'NF', icon: 'water_drop', color: 'sky', cat: CategoriaAsignatura.medica),
  'neumologia': (sigla: 'NM', icon: 'pulmonology', color: 'sky', cat: CategoriaAsignatura.medica),
  'neurologia': (sigla: 'NR', icon: 'neurology', color: 'lavender', cat: CategoriaAsignatura.medica),
  'pediatria': (sigla: 'PD', icon: 'child_care', color: 'gold', cat: CategoriaAsignatura.medica),
  'psiquiatria': (sigla: 'PQ', icon: 'psychology', color: 'lavender', cat: CategoriaAsignatura.medica),
  'reumatologia': (sigla: 'RM', icon: 'rheumatology', color: 'sage', cat: CategoriaAsignatura.medica),
  // Quirúrgicas
  'digestivo': (sigla: 'DG', icon: 'gastroenterology', color: 'sage', cat: CategoriaAsignatura.quirurgica),
  'ginecologia': (sigla: 'GO', icon: 'pregnant_woman', color: 'rose', cat: CategoriaAsignatura.quirurgica),
  'oftalmologia': (sigla: 'OF', icon: 'visibility', color: 'sky', cat: CategoriaAsignatura.quirurgica),
  'otorrinolaringologia': (sigla: 'OR', icon: 'hearing', color: 'teal', cat: CategoriaAsignatura.quirurgica),
  'traumatologia': (sigla: 'TR', icon: 'orthopedics', color: 'slate', cat: CategoriaAsignatura.quirurgica),
  'urologia': (sigla: 'UR', icon: 'water_drop', color: 'teal', cat: CategoriaAsignatura.quirurgica),
  // «plastica» y no «cirugiaplastica»: el emparejador acepta prefijos de 5+ letras y «cirugia» se
  // llevaría «Cirugía General y Digestivo».
  'plastica': (sigla: 'CP', icon: 'healing', color: 'rose', cat: CategoriaAsignatura.quirurgica),
};

const Map<String, String> _aliasVisuales = {
  'bioestadistica': 'estadistica',
  'cirugiaplastica': 'plastica',
  'farmaco': 'farmacologia',
  'farmacia': 'farmacologia',
  'legislacion': 'bioetica',
  'mosaico': 'miscelanea',
};

class VisualAsignatura {
  /// Clave canónica, o null si el grupo no es una asignatura reconocida.
  final String? key;
  final String sigla;

  /// Clave del icono de la web (Material Symbol) y del color de la paleta.
  final String icon;
  final String color;
  final CategoriaAsignatura categoria;
  final double mirWeight;

  const VisualAsignatura({
    required this.key,
    required this.sigla,
    required this.icon,
    required this.color,
    required this.categoria,
    required this.mirWeight,
  });
}

/// Identidad visual de un grupo. El color y el icono elegidos a mano mandan sobre los de la
/// asignatura; la categoría no se toca.
VisualAsignatura visualAsignatura(String name, [String? storedColor, String? storedIcon]) {
  final key = matchSubjectKey(name, _visuales.keys.toList(), _aliasVisuales);
  final e = key == null ? null : _visuales[key];
  return VisualAsignatura(
    key: key,
    sigla: e?.sigla ?? _siglaDe(name),
    icon: (storedIcon != null && storedIcon.isNotEmpty) ? storedIcon : (e?.icon ?? 'style'),
    color: (storedColor != null && storedColor.isNotEmpty) ? storedColor : (e?.color ?? 'coral'),
    categoria: e?.cat ?? CategoriaAsignatura.personal,
    mirWeight: weightForSubject(name),
  );
}

String _siglaDe(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '??';
  if (words.length == 1) return (words.first.length > 2 ? words.first.substring(0, 2) : words.first).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

enum OrdenAsignaturas { pendientes, nombre, dominio, mir }

const Map<OrdenAsignaturas, String> kNombreOrden = {
  OrdenAsignaturas.pendientes: 'Pendientes',
  OrdenAsignaturas.nombre: 'Alfabético',
  OrdenAsignaturas.dominio: 'Dominio',
  OrdenAsignaturas.mir: 'Peso MIR',
};

/// Grupos en secciones por categoría (Básicas, Médicas, Quirúrgicas, Otros), filtrados por el
/// buscador y ordenados dentro de cada sección. Las secciones vacías no salen.
List<({CategoriaAsignatura categoria, List<FlashDeck> grupos})> agruparAsignaturas(
  List<FlashDeck> decks,
  String query,
  OrdenAsignaturas orden,
) {
  final needle = query.trim().toLowerCase();
  final filas = [
    for (final d in decks)
      if (needle.isEmpty || d.name.toLowerCase().contains(needle)) (deck: d, v: visualAsignatura(d.name, d.color, d.icon)),
  ];
  int cmp(({FlashDeck deck, VisualAsignatura v}) a, ({FlashDeck deck, VisualAsignatura v}) b) {
    final porNombre = compararEs(a.deck.name, b.deck.name);
    final r = switch (orden) {
      OrdenAsignaturas.nombre => 0,
      OrdenAsignaturas.dominio => a.deck.dominio - b.deck.dominio,
      OrdenAsignaturas.mir => b.v.mirWeight.compareTo(a.v.mirWeight),
      // Más pendientes primero: es la pregunta que trae al usuario aquí.
      OrdenAsignaturas.pendientes => b.deck.dueCards - a.deck.dueCards,
    };
    return r != 0 ? r : porNombre;
  }

  return [
    for (final c in CategoriaAsignatura.values)
      if (filas.any((f) => f.v.categoria == c))
        (
          categoria: c,
          grupos: (filas.where((f) => f.v.categoria == c).toList()..sort(cmp)).map((f) => f.deck).toList(),
        ),
  ];
}
