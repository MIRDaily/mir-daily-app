import 'package:flutter/material.dart';

/// Modelo que representa una feature disponible en el Studio
class StudioFeature {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String? badge; // Para mostrar info adicional como "3 sesiones hoy"
  final bool isEnabled;
  final VoidCallback onTap;

  const StudioFeature({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.badge,
    this.isEnabled = true,
    required this.onTap,
  });
}
