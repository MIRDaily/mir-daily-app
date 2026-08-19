// Peso de cada asignatura dentro del MIR, para el botón "MIR" del creador de
// simulacros: en vez de repartir las preguntas a partes iguales, se reparten
// como caen en el examen real.
//
// Port de `src/lib/simulacro/mirWeights.ts` de la web. Los números y las
// reglas de emparejado son los mismos a propósito: si cambian allí, cambian
// aquí, o los dos clientes generarían simulacros distintos con el mismo botón.
//
// ─────────────────────────────────────────────────────────────────────────────
// OJO AL MANTENERLO
//
// Los porcentajes salen del gráfico "Importancia de la asignatura dentro del
// MIR" y suman 100. Las claves son NOMBRES de asignatura y se comparan sin
// tildes ni mayúsculas.
//
// Una asignatura de la base de datos que no aparezca aquí NO se queda fuera:
// recibe [kDefaultWeight]. Y los pesos se renormalizan sobre las asignaturas
// que existan, así que mientras no estén todas subidas el reparto sigue siendo
// proporcional entre las que hay.
// ─────────────────────────────────────────────────────────────────────────────

/// Ordenado de mayor a menor. El código AMIR del gráfico va en el comentario
/// para poder cotejarlo de un vistazo con la fuente.
const Map<String, double> kMirWeights = {
  'digestivo': 9.8, // DG
  'miscelanea': 8.4, // MC
  'cardiologia': 7.7, // CD
  'infecciosas': 7.2, // IF
  'neurologia': 6.4, // NR
  'neumologia': 6.3, // NM
  'endocrinologia': 6.1, // ED
  'ginecologia': 5.6, // GC
  'estadistica': 5.4, // ET
  'reumatologia': 4.7, // RM
  'traumatologia': 4.5, // TM
  'pediatria': 4.3, // PD
  'nefrologia': 4.3, // NF
  'psiquiatria': 4.2, // PQ
  'hematologia': 3.8, // HM
  'otorrinolaringologia': 2.8, // OR
  'dermatologia': 2.5, // DM
  'urologia': 2.4, // UR
  'inmunologia': 2.1, // IM
  'oftalmologia': 1.6, // OF
};

/// Nombres alternativos con los que puede venir una asignatura de la base.
const Map<String, String> _aliases = {
  'otorrino': 'otorrinolaringologia',
  'orl': 'otorrinolaringologia',
  'cot': 'traumatologia',
  'traumato': 'traumatologia',
  'obstetricia': 'ginecologia',
  'ginecologiayobstetricia': 'ginecologia',
  'epidemiologia': 'estadistica',
  'endocrino': 'endocrinologia',
  'neumo': 'neumologia',
  'nefro': 'nefrologia',
  'neuro': 'neurologia',
  'hemato': 'hematologia',
  'derma': 'dermatologia',
  'psiquiatra': 'psiquiatria',
  'uro': 'urologia',
  'oftalmo': 'oftalmologia',
  'inmuno': 'inmunologia',
  'infeccioso': 'infecciosas',
  'microbiologia': 'infecciosas',
};

/// Peso para una asignatura que no esté en la tabla.
const double kDefaultWeight = 3;

/// Vocales acentuadas y eñe, a pelo.
///
/// Dart no trae normalización Unicode en la biblioteca estándar (la web usa
/// `normalize('NFD')` y un rango de diacríticos), y para nombres de asignatura
/// en español esto cubre todo lo que puede aparecer.
const Map<String, String> _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

String _normalize(String s) {
  final lower = s.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    final plain = _accents[char] ?? char;
    // Fuera todo lo que no sea una letra: espacios, guiones, dígitos…
    if (plain.codeUnitAt(0) >= 0x61 && plain.codeUnitAt(0) <= 0x7A) {
      buffer.write(plain);
    }
  }
  return buffer.toString();
}

/// Palabras sueltas del nombre, ya normalizadas y sin conectores.
List<String> _wordsOf(String name) => name
    .split(RegExp(r'[\s,/&·+-]+'))
    .map(_normalize)
    .where((w) => w.length > 2 && w != 'del' && w != 'las' && w != 'los')
    .toList();

/// Peso de una asignatura por su nombre.
///
/// Se compara PALABRA a palabra, no por subcadenas: "urologia" está dentro de
/// "neurologia", así que una comparación laxa cruzaría las dos asignaturas y el
/// reparto saldría mal sin que se note.
double weightForSubject(String name) {
  final words = _wordsOf(name);
  if (words.isEmpty) return kDefaultWeight;

  for (final word in words) {
    // Coincidencia exacta de la palabra con una clave o con un alias.
    final direct = kMirWeights[word] ?? kMirWeights[_aliases[word] ?? ''];
    if (direct != null) return direct;

    // Abreviaturas y variantes: "neumo" ~ "neumologia", "traumato" ~ …
    for (final entry in kMirWeights.entries) {
      if (word.length >= 5 &&
          (entry.key.startsWith(word) || word.startsWith(entry.key))) {
        return entry.value;
      }
    }
  }
  return kDefaultWeight;
}

/// Cuántas preguntas le tocan a una asignatura en el reparto ponderado.
class MirAllocation {
  final int subjectId;
  final String name;
  final int count;

  const MirAllocation({
    required this.subjectId,
    required this.name,
    required this.count,
  });
}

/// Reparte [total] preguntas entre [subjects] según su peso en el MIR.
///
/// Usa el método del resto mayor: reparte la parte entera y luego da las que
/// sobran a quienes tienen el decimal más alto, de modo que la suma cuadra
/// exactamente con [total] (con un reparto proporcional simple casi siempre
/// faltarían o sobrarían una o dos).
List<MirAllocation> allocateByWeight(
  int total,
  List<({int id, String name})> subjects,
) {
  if (subjects.isEmpty || total <= 0) return const [];

  final weights = [
    for (final s in subjects) (id: s.id, name: s.name, w: weightForSubject(s.name))
  ];
  final sum = weights.fold<double>(0, (acc, e) => acc + e.w);
  if (sum <= 0) {
    return [
      for (final s in subjects)
        MirAllocation(subjectId: s.id, name: s.name, count: 0)
    ];
  }

  final base = [
    for (final e in weights)
      (
        id: e.id,
        name: e.name,
        count: ((e.w / sum) * total).floor(),
        rest: (e.w / sum) * total - ((e.w / sum) * total).floor(),
      )
  ];

  final counts = {for (final b in base) b.id: b.count};
  var left = total - counts.values.fold<int>(0, (a, b) => a + b);

  final byRest = [...base]..sort((a, b) => b.rest.compareTo(a.rest));
  for (var i = 0; left > 0 && i < byRest.length; i++, left--) {
    counts[byRest[i].id] = counts[byRest[i].id]! + 1;
  }
  // Si aún sobran (más preguntas que asignaturas), se da otra vuelta.
  for (var i = 0; left > 0; i = (i + 1) % byRest.length, left--) {
    counts[byRest[i].id] = counts[byRest[i].id]! + 1;
  }

  return [
    for (final b in base)
      MirAllocation(subjectId: b.id, name: b.name, count: counts[b.id]!)
  ];
}
