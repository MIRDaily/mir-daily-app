import 'package:flutter/material.dart';

/// Cómo se representa una asignatura en las cartas del sobre: una sigla corta
/// (el código AMIR de siempre — CD, DG, NR…, ver `mir_weights.dart`) y un icono.
///
/// Los iconos son de Material (los mismos que usa el resto de la app, en su
/// variante de línea): sin dependencia ni fuente extra, que en este repo —con
/// espacios en la ruta y la caché de pub cuatro carpetas arriba— daba
/// problemas de compilación en Android.
///
/// El backend manda `questions.subject` como texto libre y con muchas variantes
/// ("Digestivo", "Aparato digestivo", "Digestivo y Cirugía General"…). Se
/// normaliza palabra a palabra y se casa con la tabla; lo que no casa recibe
/// una sigla derivada de sus iniciales y el icono genérico.
class SubjectVisual {
  final String sigla;
  final IconData icon;
  const SubjectVisual(this.sigla, this.icon);
}

/// Clave normalizada (sin tildes, minúsculas, solo letras) -> sigla + icono.
const Map<String, SubjectVisual> _table = {
  'digestivo': SubjectVisual('DG', Icons.restaurant_outlined),
  'cardiologia': SubjectVisual('CD', Icons.monitor_heart_outlined),
  'neurologia': SubjectVisual('NR', Icons.psychology_outlined),
  'neumologia': SubjectVisual('NM', Icons.air_rounded),
  'infecciosas': SubjectVisual('IF', Icons.coronavirus_outlined),
  'endocrinologia': SubjectVisual('ED', Icons.balance_outlined),
  'ginecologia': SubjectVisual('GC', Icons.pregnant_woman_outlined),
  'estadistica': SubjectVisual('ET', Icons.insights_outlined),
  'reumatologia': SubjectVisual('RM', Icons.accessibility_new_rounded),
  'traumatologia': SubjectVisual('TM', Icons.personal_injury_outlined),
  'pediatria': SubjectVisual('PD', Icons.child_care_outlined),
  'nefrologia': SubjectVisual('NF', Icons.water_drop_outlined),
  'psiquiatria': SubjectVisual('PQ', Icons.self_improvement_rounded),
  'hematologia': SubjectVisual('HM', Icons.bloodtype_outlined),
  'otorrinolaringologia': SubjectVisual('OR', Icons.hearing_rounded),
  'dermatologia': SubjectVisual('DM', Icons.back_hand_outlined),
  'urologia': SubjectVisual('UR', Icons.water_outlined),
  'inmunologia': SubjectVisual('IM', Icons.shield_outlined),
  'oftalmologia': SubjectVisual('OF', Icons.visibility_outlined),
  'miscelanea': SubjectVisual('MC', Icons.category_outlined),
  'farmacologia': SubjectVisual('FM', Icons.medication_outlined),
  'genetica': SubjectVisual('GN', Icons.biotech_outlined),
  'anatomiapatologica': SubjectVisual('AP', Icons.science_outlined),
  'oncologia': SubjectVisual('ON', Icons.local_hospital_outlined),
};

/// Nombres alternativos con los que puede venir la asignatura -> clave de
/// [_table]. Los mismos criterios que `mir_weights.dart`.
const Map<String, String> _aliases = {
  'otorrino': 'otorrinolaringologia',
  'orl': 'otorrinolaringologia',
  'cot': 'traumatologia',
  'traumato': 'traumatologia',
  'obstetricia': 'ginecologia',
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
  'epidemiologia': 'estadistica',
  'preventiva': 'estadistica',
  'farmaco': 'farmacologia',
  'reumato': 'reumatologia',
  'cardio': 'cardiologia',
  'pediatra': 'pediatria',
};

const Map<String, String> _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

String _norm(String s) {
  final buffer = StringBuffer();
  for (final char in s.toLowerCase().split('')) {
    final plain = _accents[char] ?? char;
    final code = plain.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7A) buffer.write(plain);
  }
  return buffer.toString();
}

const _connectors = {'del', 'las', 'los', 'general', 'aparato', 'enfermedades'};

List<String> _words(String raw) => raw
    .split(RegExp(r'[\s,/&·+-]+'))
    .map(_norm)
    .where((w) => w.length > 2 && !_connectors.contains(w))
    .toList();

/// Sigla + icono para una asignatura, venga como venga escrita.
SubjectVisual subjectVisual(String raw) {
  final words = _words(raw);

  // Coincidencia exacta de palabra con clave o alias.
  for (final w in words) {
    final hit = _table[w] ?? _table[_aliases[w] ?? ''];
    if (hit != null) return hit;
  }

  // Prefijo (abreviaturas): "neumo" ~ "neumologia". Se compara palabra a
  // palabra, nunca por subcadena, para no cruzar "urologia" con "neurologia".
  for (final w in words) {
    if (w.length < 5) continue;
    for (final e in _table.entries) {
      if (e.key.startsWith(w) || w.startsWith(e.key)) return e.value;
    }
  }

  return SubjectVisual(_initials(raw), Icons.medical_services_outlined);
}

/// Sigla de urgencia para una asignatura desconocida: iniciales de sus dos
/// primeras palabras con peso, o las dos primeras letras si es una sola.
String _initials(String raw) {
  final words = _words(raw);
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}
