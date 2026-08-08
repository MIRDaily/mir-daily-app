import 'package:flutter/material.dart';

import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/versus_models.dart';
import '../providers/versus_room_controller.dart';
import 'versus_avatar.dart';

/// El marcador entre la pregunta y la explicación, en modo clásico.
///
/// Dura unos segundos y es donde se juega la tensión del modo: los puntos de la
/// ronda se suman contando hacia arriba y las filas se adelantan y se quedan
/// atrás mientras suben. Sin esto, ganar posiciones era una línea de texto que
/// nadie miraba.
///
/// Los puntos DE PARTIDA se calculan restando al total lo que cada uno acaba de
/// sumar: el revelado trae el acumulado, no el antes y el después.
class VersusScoreboardOverlay extends StatefulWidget {
  final VersusRoomController controller;
  final VersusRevealPhase phase;
  final VoidCallback onDone;

  const VersusScoreboardOverlay({
    super.key,
    required this.controller,
    required this.phase,
    required this.onDone,
  });

  @override
  State<VersusScoreboardOverlay> createState() =>
      _VersusScoreboardOverlayState();
}

class _VersusScoreboardOverlayState extends State<VersusScoreboardOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _total = Duration(milliseconds: 5000);

  /// Tramo en el que los puntos suben. Antes hay una entrada corta y después un
  /// respiro para leer el orden final antes de irse.
  static const double _countFrom = 0.16;
  static const double _countTo = 0.68;

  static const double _rowHeight = 62;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _total,
  );

  /// Puntos de cada jugador antes y después de esta ronda.
  late final Map<String, int> _before;
  late final Map<String, int> _after;

  /// Puesto que ocupaba en la última vuelta, para vibrar solo cuando cambia.
  int? _myLastRank;

  @override
  void initState() {
    super.initState();

    final ganados = <String, int>{};
    for (final r in widget.phase.results) {
      ganados[r.playerId] = r.points;
    }

    _after = {for (final s in widget.phase.scores) s.playerId: s.score};
    _before = {
      for (final s in widget.phase.scores)
        s.playerId: s.score - (ganados[s.playerId] ?? 0),
    };

    _c.addListener(_feelRankChange);
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.removeListener(_feelRankChange);
    _c.dispose();
    super.dispose();
  }

  /// Adelantar a alguien se nota en la mano. Es el momento del modo clásico.
  void _feelRankChange() {
    final me = widget.controller.playerId;
    if (me == null) return;

    final rank = _ranking(_c.value).indexWhere((e) => e.playerId == me);
    if (rank == -1) return;

    if (_myLastRank != null && rank != _myLastRank) {
      HapticsService.medium();
    }
    _myLastRank = rank;
  }

  /// Interpolación de los puntos en el instante [t], ya ordenada. El orden sale
  /// de los puntos INTERPOLADOS, no de los finales: por eso las filas se
  /// adelantan a mitad de la cuenta y no de golpe al final.
  List<({String playerId, int score})> _ranking(double t) {
    final progress =
        ((t - _countFrom) / (_countTo - _countFrom)).clamp(0.0, 1.0);
    // Arranca despacio, coge velocidad y frena al llegar. Con un easeOut los
    // números salían disparados desde el primer frame y el final se arrastraba.
    final eased = Curves.easeInOutCubic.transform(progress);

    final rows = _after.keys.map((id) {
      final from = _before[id] ?? 0;
      final to = _after[id] ?? 0;
      return (playerId: id, score: (from + (to - from) * eased).round());
    }).toList();

    rows.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      // Desempate estable por id: sin él, dos empatados se intercambian de
      // sitio en cada frame y la fila tiembla.
      return byScore != 0 ? byScore : a.playerId.compareTo(b.playerId);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Entra rápido y se va al final, para que el paso a la explicación no
        // sea un corte seco.
        final fade = t < 0.08
            ? t / 0.08
            : t > 0.93
                ? (1 - (t - 0.93) / 0.07).clamp(0.0, 1.0)
                : 1.0;

        final rows = _ranking(t);

        return Opacity(
          opacity: fade,
          child: DecoratedBox(
            // Fondo con color propio: esto es el momento de la ronda, no una
            // lista más sobre el beige de siempre.
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.background,
                  AppColors.secondary.withValues(alpha: 0.12),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primary],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Text(
                      'MARCADOR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Stack(
                        children: [
                          for (int i = 0; i < rows.length; i++)
                            AnimatedPositioned(
                              // La posición se anima sola: cuando el orden
                              // cambia, la fila viaja a su sitio nuevo en vez
                              // de saltar.
                              key: ValueKey(rows[i].playerId),
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              top: i * _rowHeight,
                              left: 0,
                              right: 0,
                              child: _ScoreboardRow(
                                position: i + 1,
                                player: c.playerById(rows[i].playerId),
                                score: rows[i].score,
                                isMe: rows[i].playerId == c.playerId,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreboardRow extends StatelessWidget {
  final int position;
  final VersusPlayer? player;
  final int score;
  final bool isMe;

  const _ScoreboardRow({
    required this.position,
    required this.player,
    required this.score,
    required this.isMe,
  });

  /// Color del puesto: oro, plata, bronce y, a partir de ahí, el gris de la
  /// paleta. Es lo que hace que un vistazo baste para saber dónde vas.
  static const List<List<Color>> _podium = [
    [Color(0xFFF6D87A), Color(0xFFE0B94A)],
    [Color(0xFFCBD3DA), Color(0xFFA8B3BD)],
    [Color(0xFFD9A47A), Color(0xFFB98356)],
  ];

  @override
  Widget build(BuildContext context) {
    final leader = position == 1;
    final medal = position <= _podium.length ? _podium[position - 1] : null;

    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isMe
              ? [
                  AppColors.primary.withValues(alpha: 0.28),
                  AppColors.primary.withValues(alpha: 0.08),
                ]
              : [AppColors.surface, AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? AppColors.primary
              : medal != null
                  ? medal[1].withValues(alpha: 0.55)
                  : AppColors.border,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (leader ? AppColors.gold : AppColors.secondary)
                .withValues(alpha: leader ? 0.32 : 0.12),
            blurRadius: leader ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Chapa del puesto, con el color de la medalla.
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: medal == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: medal,
                    ),
              color: medal == null ? AppColors.surfaceVariant : null,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '$position',
              style: TextStyle(
                color: medal == null ? AppColors.textLight : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (player != null) ...[
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: leader ? AppColors.gold : Colors.transparent,
                  width: 2,
                ),
              ),
              child: VersusAvatar(player: player!, size: 32),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              player?.nickname ?? 'Jugador',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              color: leader ? AppColors.primaryDark : AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
