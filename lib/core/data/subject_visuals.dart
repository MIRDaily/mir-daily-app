import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Cómo se representa una asignatura en las cartas del sobre: una sigla corta
/// (el código AMIR de siempre — CD, DG, NR…, ver `mir_weights.dart`) y un icono
/// de línea de Lucide.
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
  'digestivo': SubjectVisual('DG', LucideIcons.soup),
  'cardiologia': SubjectVisual('CD', LucideIcons.heart),
  'neurologia': SubjectVisual('NR', LucideIcons.brain),
  'neumologia': SubjectVisual('NM', LucideIcons.wind),
  'infecciosas': SubjectVisual('IF', LucideIcons.bug),
  'endocrinologia': SubjectVisual('ED', LucideIcons.scale),
  'ginecologia': SubjectVisual('GC', LucideIcons.venus),
  'estadistica': SubjectVisual('ET', LucideIcons.sigma),
  'reumatologia': SubjectVisual('RM', LucideIcons.bone),
  'traumatologia': SubjectVisual('TM', LucideIcons.bone_fracture),
  'pediatria': SubjectVisual('PD', LucideIcons.baby),
  'nefrologia': SubjectVisual('NF', LucideIcons.droplet),
  'psiquiatria': SubjectVisual('PQ', LucideIcons.brain_cog),
  'hematologia': SubjectVisual('HM', LucideIcons.droplets),
  'otorrinolaringologia': SubjectVisual('OR', LucideIcons.ear),
  'dermatologia': SubjectVisual('DM', LucideIcons.hand),
  'urologia': SubjectVisual('UR', LucideIcons.flask_round),
  'inmunologia': SubjectVisual('IM', LucideIcons.shield),
  'oftalmologia': SubjectVisual('OF', LucideIcons.eye),
  'miscelanea': SubjectVisual('MC', LucideIcons.shapes),
  'farmacologia': SubjectVisual('FM', LucideIcons.pill),
  'genetica': SubjectVisual('GN', LucideIcons.dna),
  'anatomiapatologica': SubjectVisual('AP', LucideIcons.microscope),
  'oncologia': SubjectVisual('ON', LucideIcons.ribbon),
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
    .map((w) => (raw: w, norm: _norm(w)))
    .where((w) => w.norm.length > 2 && !_connectors.contains(w.norm))
    .map((w) => w.norm)
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

  return SubjectVisual(_initials(raw), LucideIcons.stethoscope);
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
