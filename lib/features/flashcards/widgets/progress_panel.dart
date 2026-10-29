// Panel de progreso de las flashcards: qué te espera (previsión de 30 días) y cómo lo llevas
// (madurez y retención). Puerto de src/components/flashcards/ProgressPanel.tsx; las barras van a
// mano, como en la web.

import 'package:flutter/material.dart';

import '../../../core/models/flashcards.dart';
import '../../../core/models/models.dart';
import '../../../shared/sticker/sticker.dart';
import 'flashcards_ui.dart';

const _maduraDesde = 21;

final _tramos = <({String label, Color color, int Function(FlashStats) n})>[
  (label: 'Nuevas', color: kFlashStatusTone[FlashStatus.nueva]!.fg, n: (s) => s.nuevas),
  (label: 'Aprendiendo', color: kFlashStatusTone[FlashStatus.learning]!.fg, n: (s) => s.learning),
  (label: 'Jóvenes', color: const Color(0xFF7BA7C4), n: (s) => s.young),
  (label: 'Maduras', color: kFlashStatusTone[FlashStatus.mastered]!.fg, n: (s) => s.mature),
];

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];

String _dia(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  final m = int.tryParse(p[1]) ?? 1;
  return '${int.tryParse(p[2]) ?? p[2]} ${_meses[(m - 1).clamp(0, 11)]}';
}

class FlashProgressPanel extends StatelessWidget {
  final FlashForecast? forecast;
  final FlashStats? stats;
  final Color accent;

  const FlashProgressPanel({super.key, this.forecast, this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    if (forecast == null && stats == null) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final dos = c.maxWidth >= 640;
      final a = _prevision();
      final b = _estado();
      return dos
          ? IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: a),
                const SizedBox(width: 12),
                Expanded(child: b),
              ]),
            )
          : Column(children: [a, const SizedBox(height: 12), b]);
    });
  }

  Widget _caja(Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4DCD8), width: 2),
        ),
        child: child,
      );

  Widget _prevision() {
    final f = forecast;
    final maxDia = f == null || f.days.isEmpty ? 1 : f.days.map((d) => d.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Cabecera(
        'Próximos 30 días',
        trailing: f != null && f.overdue > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: kFlashStatusTone[FlashStatus.failed]!.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kFlashStatusTone[FlashStatus.failed]!.border),
                ),
                child: Text('${f.overdue} atrasadas',
                    style: TextStyle(color: kFlashStatusTone[FlashStatus.failed]!.fg, fontSize: 11, fontWeight: FontWeight.w900)),
              )
            : null,
      ),
      if (f != null && f.days.any((d) => d.count > 0)) ...[
        Semantics(
          label: 'Repasos previstos por día: hoy ${f.days.first.count}, ${f.total} en total en 30 días',
          excludeSemantics: true,
          child: SizedBox(
            height: 96,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final d in f.days)
                Expanded(
                  child: Tooltip(
                    message: '${_dia(d.date)}: ${d.count} ${d.count == 1 ? 'tarjeta' : 'tarjetas'}',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: (96 * (d.count / maxDia)).clamp(d.count > 0 ? 6.0 : 2.0, 96.0),
                      decoration: BoxDecoration(
                        color: d.count > 0 ? accent : const Color(0xFFEFEAE7),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFB0B8BF), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          child: Row(children: [
            Text('HOY ${f.days.first.count}'),
            const Spacer(),
            Text('${f.total} EN TOTAL'),
            const Spacer(),
            const Text('+30 D'),
          ]),
        ),
      ] else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Nada programado todavía. Estudia una tarjeta y aquí verás cuándo te toca repasarla.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB0B8BF), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
    ]));
  }

  Widget _estado() {
    final s = stats;
    return _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Cabecera(
        'Tus tarjetas',
        trailing: s?.rate != null
            ? Text('${(s!.rate! * 100).round()}% de retención', style: const TextStyle(color: kInk, fontSize: 11, fontWeight: FontWeight.w900))
            : null,
      ),
      if (s != null && s.total > 0) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
            child: Row(children: [
              for (final t in _tramos)
                if (t.n(s) > 0) Expanded(flex: t.n(s), child: Container(color: t.color)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final t in _tramos)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: t.color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('${t.n(s)}', style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              Text(t.label.toUpperCase(), style: const TextStyle(color: kMuted, fontSize: 9.5, fontWeight: FontWeight.w800)),
            ]),
        ]),
        const SizedBox(height: 10),
        Text(
          s.reviews == 0
              ? 'La retención se calcula sobre tarjetas que ya tenían fecha de repaso. Aún no has repasado ninguna.'
              : '${s.passed} de ${s.reviews} ${s.reviews == 1 ? 'repaso recordado' : 'repasos recordados'}. '
                  'Maduras son las que ya te aguantan $_maduraDesde días o más.',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.w600, height: 1.35),
        ),
      ] else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Todavía no hay tarjetas que medir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB0B8BF), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
    ]));
  }
}

/// Título de una caja con algo a la derecha. No es SectionLabel: aquí el título cede (se corta) antes
/// que desbordar cuando la caja es estrecha o la letra va grande.
class _Cabecera extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const _Cabecera(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: kMuted.withOpacity(0.7)),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}
