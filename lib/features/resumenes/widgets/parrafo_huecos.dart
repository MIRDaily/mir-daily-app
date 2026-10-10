import 'package:flutter/material.dart';

import '../../../core/models/resumen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../resumenes_grupo.dart';
import '../resumenes_huecos.dart';

/// Un párrafo con sus huecos, para VER (lista, estudio) o EDITAR (marcar huecos).
///
/// Editando: tocar una palabra que no está tapada la convierte en hueco (con el
/// nivel elegido); tocar un hueco abre su menú (cambiar nivel o quitarlo). El
/// texto es siempre texto de Flutter: lo que venga de la IA no puede inyectar nada.
class ParrafoHuecos extends StatelessWidget {
  final String texto;
  final List<Hueco> huecos;
  final bool editable;

  /// Nivel de los huecos nuevos (solo en modo edición).
  final int nivel;
  final void Function(List<Hueco>)? onChange;
  final void Function(String)? onAviso;

  const ParrafoHuecos({
    super.key,
    required this.texto,
    required this.huecos,
    this.editable = false,
    this.nivel = 2,
    this.onChange,
    this.onAviso,
  });

  void _tocarPalabra(int pos) {
    if (!editable) return;
    final r = alternarPalabra(texto, huecos, pos, nivel);
    if (r.error != null) {
      onAviso?.call(r.error!);
    } else {
      onChange?.call(r.huecos);
    }
  }

  Future<void> _abrirMenu(BuildContext context, int k) async {
    final accion = await showModalBottomSheet<_AccionHueco>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nivel del hueco', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kInk)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in nivelesResumen)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, _AccionNivel(n)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: huecos[k].n == n ? nivelInfoResumen[n]!.color : nivelInfoResumen[n]!.soft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          nivelInfoResumen[n]!.nombre,
                          style: TextStyle(
                            color: huecos[k].n == n ? Colors.white : nivelInfoResumen[n]!.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, const _AccionQuitar()),
                icon: const Icon(Icons.backspace_rounded, color: AppColors.error, size: 18),
                label: const Text('Quitar hueco', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
    if (accion is _AccionNivel) {
      onChange?.call(cambiarNivel(huecos, k, accion.nivel));
    } else if (accion is _AccionQuitar) {
      onChange?.call(quitarHueco(huecos, k));
    }
  }

  @override
  Widget build(BuildContext context) {
    const sup = ['¹', '²', '³', '⁴'];
    final segs = segmentos(texto, huecos);
    final children = <InlineSpan>[];
    var pos = 0;

    for (final s in segs) {
      final desde = pos;
      pos += s.t.length;
      if (s.k == null) {
        for (final tk in _tokens(s.t, desde)) {
          if (tk.espacio || !editable) {
            children.add(TextSpan(text: tk.t));
          } else {
            children.add(WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => _tocarPalabra(tk.pos),
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
                  child: Text(tk.t, style: _palabraStyle),
                ),
              ),
            ));
          }
        }
      } else {
        final k = s.k!;
        final h = huecos[k];
        final info = nivelInfoResumen[h.n]!;
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: editable ? () => _abrirMenu(context, k) : null,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(color: info.soft, borderRadius: BorderRadius.circular(4)),
              child: Text(
                '${s.t}${sup[h.n - 1]}',
                style: TextStyle(color: info.color, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
        ));
      }
    }

    return Text.rich(
      TextSpan(children: children),
      style: const TextStyle(fontSize: 14, height: 1.9, color: kInk),
    );
  }

  static const TextStyle _palabraStyle = TextStyle(fontSize: 14, color: kInk);
}

sealed class _AccionHueco {
  const _AccionHueco();
}

class _AccionNivel extends _AccionHueco {
  final int nivel;
  const _AccionNivel(this.nivel);
}

class _AccionQuitar extends _AccionHueco {
  const _AccionQuitar();
}

/// Selector del nivel con el que se marcan los huecos nuevos.
class NivelNuevo extends StatelessWidget {
  final int nivel;
  final ValueChanged<int> onChanged;

  const NivelNuevo({super.key, required this.nivel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in nivelesResumen)
          GestureDetector(
            onTap: () => onChanged(n),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: nivel == n ? nivelInfoResumen[n]!.color : nivelInfoResumen[n]!.soft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                nivelInfoResumen[n]!.nombre,
                style: TextStyle(
                  color: nivel == n ? Colors.white : nivelInfoResumen[n]!.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Palabras (o huecos de espacio) con su posición en el texto.
List<({String t, int pos, bool espacio})> _tokens(String t, int desde) {
  final out = <({String t, int pos, bool espacio})>[];
  for (final m in RegExp(r'\s+|[^\s]+').allMatches(t)) {
    out.add((t: m.group(0)!, pos: desde + m.start, espacio: RegExp(r'^\s').hasMatch(m.group(0)!)));
  }
  return out;
}
