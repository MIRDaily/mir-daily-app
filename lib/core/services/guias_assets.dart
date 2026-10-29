import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/guias.dart';

/// Las guías de estudio van dentro de la app (assets/guides/, generadas desde la web con
/// tools/export_study_guides.mjs): no hay red. Se leen una vez y se guardan en memoria.
class GuiasAssets {
  GuiasAssets._();

  static IndiceGuias? _indice;
  static final Map<String, StudyGuide> _guias = {};

  /// Para los tests: otro paquete de assets y sin caché.
  static AssetBundle bundle = rootBundle;

  static void olvidar() {
    _indice = null;
    _guias.clear();
  }

  static Future<IndiceGuias> indice() async =>
      _indice ??= IndiceGuias.fromJson(jsonDecode(await bundle.loadString('assets/guides/index.json')) as Map<String, dynamic>);

  static Future<StudyGuide> guia(String clave) async {
    final ya = _guias[clave];
    if (ya != null) return ya;
    final g = StudyGuide.fromJson(jsonDecode(await bundle.loadString('assets/guides/$clave.json')) as Map<String, dynamic>);
    return _guias[clave] = g;
  }
}
