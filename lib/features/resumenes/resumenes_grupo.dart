// Color, icono y estados de un grupo de resúmenes activos, con la misma paleta
// que las asignaturas de flashcards (la clave del color se guarda en la BD).
//
// Puerto de la web: src/lib/flashcardTheme.ts y src/lib/resumenes/grupo.ts.

import 'package:flutter/material.dart';

import '../../core/models/resumen.dart';

/// Color de un grupo (clave + tonos concretos).
class SubjectColor {
  final String key;
  final String label;
  final Color bg;
  final Color soft;
  final Color text;
  final Color ring;

  const SubjectColor({
    required this.key,
    required this.label,
    required this.bg,
    required this.soft,
    required this.text,
    required this.ring,
  });
}

const List<SubjectColor> subjectColorsResumen = [
  SubjectColor(key: 'coral', label: 'Coral', bg: Color(0xFFE8A598), soft: Color(0xFFFBEDE9), text: Color(0xFFB5675A), ring: Color(0xFFE8A598)),
  SubjectColor(key: 'sage', label: 'Salvia', bg: Color(0xFF8BA888), soft: Color(0xFFEAF1E9), text: Color(0xFF5C7A59), ring: Color(0xFF8BA888)),
  SubjectColor(key: 'sky', label: 'Cielo', bg: Color(0xFF7BA7C4), soft: Color(0xFFE7F0F6), text: Color(0xFF4E7C9B), ring: Color(0xFF7BA7C4)),
  SubjectColor(key: 'gold', label: 'Ámbar', bg: Color(0xFFE0B15A), soft: Color(0xFFFBF1DC), text: Color(0xFFA87E28), ring: Color(0xFFE0B15A)),
  SubjectColor(key: 'lavender', label: 'Lavanda', bg: Color(0xFF9B8BC4), soft: Color(0xFFEFEBF7), text: Color(0xFF6E5EA0), ring: Color(0xFF9B8BC4)),
  SubjectColor(key: 'rose', label: 'Rosa', bg: Color(0xFFD48DA8), soft: Color(0xFFF9EAF0), text: Color(0xFFA85C78), ring: Color(0xFFD48DA8)),
  SubjectColor(key: 'teal', label: 'Verde azulado', bg: Color(0xFF6FB3A8), soft: Color(0xFFE4F2EF), text: Color(0xFF478C81), ring: Color(0xFF6FB3A8)),
  SubjectColor(key: 'slate', label: 'Pizarra', bg: Color(0xFF7D8A96), soft: Color(0xFFECEEF1), text: Color(0xFF586573), ring: Color(0xFF7D8A96)),
];

const String colorGrupoPorDefecto = 'coral';

SubjectColor resolveColorResumen(String? key) =>
    subjectColorsResumen.firstWhere((c) => c.key == key, orElse: () => subjectColorsResumen.first);

/// Iconos elegibles (claves de la web) y el de por defecto.
const String iconoResumenPorDefecto = 'menu_book';

const List<String> iconosResumen = [
  'style', 'cardiology', 'neurology', 'pulmonology', 'gastroenterology', 'orthopedics',
  'medication', 'vaccines', 'psychology', 'biotech', 'healing', 'science', 'bloodtype',
  'coronavirus', 'dentistry', 'menu_book',
];

/// El icono de un grupo; si no es uno de la paleta, el de por defecto.
IconData iconoGrupoResumen(String? icon) =>
    _iconoDe(icon != null && iconosResumen.contains(icon) ? icon : iconoResumenPorDefecto);

IconData _iconoDe(String key) {
  switch (key) {
    case 'style':
      return Icons.style_rounded;
    case 'cardiology':
      return Icons.favorite_rounded;
    case 'neurology':
      return Icons.psychology_rounded;
    case 'pulmonology':
      return Icons.air_rounded;
    case 'gastroenterology':
      return Icons.restaurant_rounded;
    case 'orthopedics':
      return Icons.accessible_rounded;
    case 'medication':
      return Icons.medication_rounded;
    case 'vaccines':
      return Icons.vaccines_rounded;
    case 'psychology':
      return Icons.mood_rounded;
    case 'biotech':
      return Icons.biotech_rounded;
    case 'healing':
      return Icons.healing_rounded;
    case 'science':
      return Icons.science_rounded;
    case 'bloodtype':
      return Icons.bloodtype_rounded;
    case 'coronavirus':
      return Icons.coronavirus_rounded;
    case 'dentistry':
      return Icons.medical_services_rounded;
    case 'menu_book':
      return Icons.menu_book_rounded;
    default:
      return Icons.menu_book_rounded;
  }
}

/// Nombre y color de cada estado de repaso (los mismos de la lista de grupos).
const Map<EstadoParrafoSrs, ({String nombre, Color color})> estadoRepasoResumen = {
  EstadoParrafoSrs.new_: (nombre: 'Nuevo', color: Color(0xFF7D8A96)),
  EstadoParrafoSrs.failed: (nombre: 'Fallado', color: Color(0xFFB04A5E)),
  EstadoParrafoSrs.learning: (nombre: 'Aprendiendo', color: Color(0xFFB07A1E)),
  EstadoParrafoSrs.mastered: (nombre: 'Dominado', color: Color(0xFF5E8C5A)),
};

/// Los cuatro estados en orden para pintar la barra y la leyenda.
const List<EstadoParrafoSrs> ordenEstadosResumen = [
  EstadoParrafoSrs.new_,
  EstadoParrafoSrs.failed,
  EstadoParrafoSrs.learning,
  EstadoParrafoSrs.mastered,
];

int cuentaEstadoResumen(ResumenEstados r, EstadoParrafoSrs e) {
  switch (e) {
    case EstadoParrafoSrs.new_:
      return r.nuevo;
    case EstadoParrafoSrs.failed:
      return r.failed;
    case EstadoParrafoSrs.learning:
      return r.learning;
    case EstadoParrafoSrs.mastered:
      return r.mastered;
  }
}

/// Dificultad del contenido de un hueco (nivel 1-4), con su nombre y colores.
class NivelInfo {
  final String nombre;
  final Color color;
  final Color soft;
  const NivelInfo({required this.nombre, required this.color, required this.soft});
}

const Map<int, NivelInfo> nivelInfoResumen = {
  1: NivelInfo(nombre: 'Fácil', color: Color(0xFF5E8C5A), soft: Color(0xFFE7F0E5)),
  2: NivelInfo(nombre: 'Media', color: Color(0xFF3F7EA6), soft: Color(0xFFE3EEF5)),
  3: NivelInfo(nombre: 'Difícil', color: Color(0xFFB07A1E), soft: Color(0xFFFBF0DA)),
  4: NivelInfo(nombre: 'Demencial', color: Color(0xFFB04A5E), soft: Color(0xFFFAE3E8)),
};
