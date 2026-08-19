import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/widgets/zoomable_image.dart';
import '../models/versus_models.dart';
import '../providers/versus_room_controller.dart';
import 'versus_avatar.dart';
import 'versus_combat.dart';
import 'versus_score_chart.dart';
import 'versus_scoreboard_overlay.dart';

/// La partida en curso: cuenta atrás, pregunta, bloqueo de respuestas,
/// revelado y marcador.
///
/// No decide nada: pinta la fase que dice el controlador. La corrección solo
/// existe cuando llega el revelado, así que hasta entonces no hay forma de que
/// la pantalla sepa (ni filtre) cuál era la buena.
class VersusRunner extends StatefulWidget {
  final VersusRoomController controller;

  /// Sale del podio para montar otra sala. Sin esto la partida terminaba en un
  /// callejón sin salida: el marcador, y ninguna forma evidente de irse que no
  /// fuera la X de la barra.
  final VoidCallback onPlayAgain;

  /// Sale del podio de vuelta a la pestaña de Versus.
  final VoidCallback onExit;

  const VersusRunner({
    super.key,
    required this.controller,
    required this.onPlayAgain,
    required this.onExit,
  });

  @override
  State<VersusRunner> createState() => _VersusRunnerState();
}

class _VersusRunnerState extends State<VersusRunner> {
  static const List<String> _letters = ['A', 'B', 'C', 'D', 'E'];

  Timer? _ticker;

  /// Rondas cuyo marcador animado ya se ha visto. Una vez por ronda: si no, el
  /// tic de 100 ms lo relanzaría sin parar.
  final Set<int> _scoreboardDone = {};

  /// Si toca enseñar el marcador antes de la explicación.
  ///
  /// Se salta cuando quedan menos de 10 s de revelado: eso significa que se ha
  /// entrado tarde (una reconexión), y gastarlos en el marcador dejaría sin ver
  /// la explicación.
  bool _wantsScoreboard(VersusRoomController c, VersusPhase phase) {
    if (phase is! VersusRevealPhase) return false;
    if (c.isSurvival || c.strike != null) return false;
    if (_scoreboardDone.contains(phase.idx)) return false;
    return phase.endsAt - c.serverNow > 10000;
  }

  @override
  void initState() {
    super.initState();
    // Un único temporizador para todas las cuentas atrás de la pantalla.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final phase = c.phase;
    if (phase == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    _feedbackForReveal(c, phase);

    // Modo clásico: entre la pregunta y la explicación va el marcador animado.
    // En Guardia no, porque ahí no se juega por puntos y su momento es el golpe.
    if (_wantsScoreboard(c, phase)) {
      final reveal = phase as VersusRevealPhase;
      return VersusScoreboardOverlay(
        key: ValueKey('marcador-${reveal.idx}'),
        controller: c,
        phase: reveal,
        onDone: () => setState(() => _scoreboardDone.add(reveal.idx)),
      );
    }

    // El golpe va POR ENCIMA de la fase que toque: perder una vida tiene que
    // interrumpir lo que estés mirando, no esperar su turno.
    final strike = c.strike;
    if (strike != null) {
      return Stack(
        children: [
          _buildPhase(c, phase),
          Positioned.fill(
            child: VersusStrikeOverlay(
              key: ValueKey('strike-${strike.kind}-${strike.idx}'),
              strike: strike,
              onDone: c.consumeStrike,
            ),
          ),
        ],
      );
    }

    return _buildPhase(c, phase);
  }

  /// Acierto o fallo se notan en la mano en cuanto se destapa la respuesta.
  /// Fuera de Guardia es lo único que marca el momento, porque ahí no hay
  /// golpe que enseñar. Se dispara una sola vez por ronda: el revelado llega
  /// por broadcast y otra vez por el refresco.
  int? _feltReveal;

  void _feedbackForReveal(VersusRoomController c, VersusPhase phase) {
    if (phase is! VersusRevealPhase || _feltReveal == phase.idx) return;
    _feltReveal = phase.idx;

    // En Guardia el golpe trae su propia vibración, más fuerte y con su
    // momento; doblarla aquí solo la emborronaría.
    if (c.strike != null) return;

    VersusResult? mine;
    for (final r in phase.results) {
      if (r.playerId == c.playerId) mine = r;
    }
    if (mine == null || mine.selected == null) return;

    final ok = mine.isCorrect == true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ok) {
        HapticsService.light();
      } else {
        HapticsService.medium();
        SystemSound.play(SystemSoundType.alert);
      }
    });
  }

  Widget _buildPhase(VersusRoomController c, VersusPhase phase) {
    if (phase is VersusEndedPhase) return _buildEnded(c, phase);

    // Los 3 segundos antes de cada pregunta no son adorno: absorben la latencia
    // dispar de cada móvil para que el enunciado aparezca a la vez en todas las
    // pantallas. El plazo de respuesta se mide desde el final de esta cuenta.
    if (phase is VersusQuestionPhase && c.serverNow < phase.startsAt) {
      return _buildCountdown(c, phase);
    }

    return _buildRound(c, phase);
  }

  // ==========================
  // Cuenta atrás previa
  // ==========================

  Widget _buildCountdown(VersusRoomController c, VersusQuestionPhase phase) {
    final remaining = ((phase.startsAt - c.serverNow) / 1000).ceil();

    // Antes de la PRIMERA pregunta, la cuenta atrás se usa para presentar a los
    // combatientes: es un hueco de 3 s que ya existía y en el que solo había un
    // número. En las siguientes rondas manda el número, que ahí lo que hace
    // falta es saber cuándo vuelve a empezar.
    if (phase.idx == 0 && c.players.length >= 2) {
      return VersusIntro(
        players: c.players,
        meId: c.playerId,
        survival: c.isSurvival,
        lives: c.room?.config.lives ?? 1,
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pregunta ${phase.idx + 1} de ${phase.total}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textLight,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.5, end: 1).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Text(
              '$remaining',
              key: ValueKey(remaining),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 96,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================
  // Ronda (pregunta / bloqueo / revelado)
  // ==========================

  Widget _buildRound(VersusRoomController c, VersusPhase phase) {
    final question = c.question;
    final answering = phase is VersusQuestionPhase;
    final revealPhase = phase is VersusRevealPhase ? phase : null;

    // En 'picks' se ve qué eligió cada uno pero todavía no cuál era la buena.
    final picksByOption = <int, List<VersusPlayer>>{};
    if (phase is VersusPicksPhase) {
      for (final pick in phase.picks) {
        _addPick(c, picksByOption, pick.playerId, pick.selected);
      }
    } else if (revealPhase != null) {
      for (final result in revealPhase.results) {
        _addPick(c, picksByOption, result.playerId, result.selected);
      }
    }

    final int? secondsLeft = answering && question != null
        ? ((question.endsAt - c.serverNow) / 1000).ceil().clamp(0, 9999)
        : null;

    final double timeRatio = answering && question != null
        ? ((question.endsAt - c.serverNow) /
                (question.endsAt - question.startsAt))
            .clamp(0.0, 1.0)
        : 0;

    // Cabecera y HUD viven FUERA del carrusel: al deslizar a la corrección
    // tienen que quedarse quietos, porque el HUD es de donde se despega el
    // corazón que cae. Si viajaran con la página, la animación se iría de la
    // pantalla justo cuando hay que mirarla.
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El margen derecho deja libre la esquina donde flota la X de salir;
          // sin él, la cuenta atrás se le montaba encima.
          Padding(
            padding: const EdgeInsets.only(right: 34),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexibles los dos: con "Respuestas bloqueadas" y una cuenta
                // de preguntas larga, en una pantalla estrecha el Row
                // desbordaba y Flutter pinta las rayas de aviso.
                Flexible(
                  child: Text(
                    question != null
                        ? 'Pregunta ${phase.idx + 1} de ${question.total}'
                        : 'Pregunta ${phase.idx + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    secondsLeft != null
                        ? '${secondsLeft}s'
                        : phase is VersusPicksPhase
                            ? 'Respuestas bloqueadas'
                            : 'Solución',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: secondsLeft != null && secondsLeft <= 5
                          ? AppColors.error
                          : AppColors.textLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Guardia: las vidas, siempre a la vista y siempre en el mismo sitio.
          if (c.isSurvival) ...[
            const SizedBox(height: 12),
            _LivesStrip(controller: c),
          ],

          if (answering) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: timeRatio,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(
                  timeRatio < 0.2 ? AppColors.error : AppColors.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
      ),
    );

    final content = ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        // Enunciado
        if (question != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (question.subject != null) ...[
                  Text(
                    question.subject!.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  question.statement,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                // Sin el "revelar" del simulacro: aquí el reloj corre y esconder
                // la imagen solo penalizaría.
                if (question.hasImage && question.imageUrl != null) ...[
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ZoomableImage(
                      url: question.imageUrl!,
                      fit: BoxFit.contain,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Opciones
        ...List.generate(question?.options.length ?? 0, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionTile(
              letter: index < _letters.length
                  ? _letters[index]
                  : '${index + 1}',
              text: question!.options[index],
              here: picksByOption[index] ?? const [],
              isMine: c.selected == index,
              isCorrect:
                  revealPhase == null ? null : revealPhase.correctIndex == index,
              enabled: answering && !c.answered && !c.amEliminated,
              onTap: () {
                // Confirmación en la mano de que la respuesta ha salido: en
                // Kahoot el bloqueo es definitivo y tiene que notarse.
                HapticsService.medium();
                SystemSound.play(SystemSoundType.click);
                c.answer(index);
              },
            ),
          );
        }),

        const SizedBox(height: 8),

        if (answering) _buildAnsweringFooter(c),
        if (phase is VersusPicksPhase)
          const Center(
            child: Text(
              'Esto ha elegido cada uno… ¿quién tiene razón?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );

    // La corrección vive en una página a la DERECHA de la pregunta, igual que
    // en el simulacro: se desliza para ir y volver, y las opciones siguen ahí
    // detrás para comprobar cuál era la buena.
    return Column(
      children: [
        header,
        Expanded(
          // La clave por ronda le da al carrusel un controlador y un estado
          // limpios en cada pregunta. Compartir uno solo entre rondas era el
          // fallo: entre pregunta y pregunta el PageView no existe (manda la
          // cuenta atrás), así que el `jumpToPage(0)` se perdía por no haber
          // clientes y el controlador se quedaba descolocado — de ahí que el
          // deslizamiento automático solo funcionara en la primera.
          child: _RoundCarousel(
            key: ValueKey('carrusel-${phase.idx}'),
            question: content,
            correction: revealPhase == null
                ? null
                : _CorrectionPage(controller: c, phase: revealPhase),
          ),
        ),
      ],
    );
  }

  void _addPick(
    VersusRoomController c,
    Map<int, List<VersusPlayer>> byOption,
    String playerId,
    int? selected,
  ) {
    if (selected == null) return;
    final player = c.playerById(playerId);
    if (player == null) return;
    byOption.putIfAbsent(selected, () => []).add(player);
  }

  Widget _buildAnsweringFooter(VersusRoomController c) {
    final String text;
    if (c.amEliminated) {
      text = 'Estás eliminado. Mira cómo cae el resto.';
    } else if (c.answered) {
      text = 'Respuesta enviada. Esperando al resto…';
    } else if (c.answeredCount != null && c.aliveCount != null) {
      text = '${c.answeredCount} de ${c.aliveCount} han respondido';
    } else {
      text = 'Elige una opción';
    }

    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }


  /// Votación de la revancha, con su cuenta atrás. No pide avanzar nada: el
  /// plazo lo cierra el servidor, aquí solo se pinta cuánto queda.
  Widget _buildRematch(VersusRoomController c) {
    final left = ((c.rematchUntil! - c.serverNow) / 1000).ceil();
    final expired = left <= 0;
    final voted = c.votedRematch;

    // Solo cuentan los que siguen delante de la pantalla, que es el mismo
    // criterio con el que el servidor decide cerrar la votación.
    final present =
        c.players.where((p) => !p.left && p.connected).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tinted(AppColors.primary, 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(4),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.replay_rounded,
                  size: 20, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '¿Revancha?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!expired)
                Text(
                  '${left}s',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            expired
                ? 'Se acabó el tiempo de votar.'
                : '${c.rematchVotes.length} de $present quieren repetir. '
                    'Si votáis todos, la sala se abre sola.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: voted || expired || c.votingRematch
                  ? null
                  : c.voteRematch,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: AppColors.surfaceVariant,
                disabledForegroundColor: AppColors.textLight,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              icon: Icon(
                voted ? Icons.check_rounded : Icons.replay_rounded,
                size: 19,
              ),
              label: Text(
                voted
                    ? 'Has votado. Esperando al resto…'
                    : expired
                        ? 'Votación cerrada'
                        : 'Quiero revancha',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Clasificación de Guardia: primero los que siguen en pie, y detrás los
  /// caídos en orden inverso de caída — el que aguantó más, más arriba. Es el
  /// mismo criterio que usa el backend (`eliminated_at_idx`), y no los puntos.
  List<Widget> _buildSurvivors(VersusRoomController c) {
    final rows = [...c.players]..sort((a, b) {
        if (a.eliminated != b.eliminated) return a.eliminated ? 1 : -1;
        if (!a.eliminated) return 0;
        return (b.eliminatedAtIdx ?? 0).compareTo(a.eliminatedAtIdx ?? 0);
      });

    return [
      for (int i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SurvivorRow(
            position: i + 1,
            player: rows[i],
            isMe: rows[i].id == c.playerId,
          ),
        ),
    ];
  }

  // ==========================
  // Final de partida
  // ==========================

  Widget _buildEnded(VersusRoomController c, VersusEndedPhase phase) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryHover],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(4),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Se acabó',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // En Guardia no se gana por puntos sino por quedar en pie, así que el
        // podio lo cuenta con vidas y con hasta dónde llegó cada uno. La gráfica
        // de puntuación tampoco dice nada ahí.
        if (c.isSurvival)
          ..._buildSurvivors(c)
        else ...[
          ..._buildScoreboard(c, phase.scores, compact: false),
          if (phase.series.isNotEmpty) ...[
            const SizedBox(height: 26),
            VersusScoreChart(
              series: phase.series,
              players: c.players,
              meId: c.playerId,
            ),
          ],
        ],

        const SizedBox(height: 24),

        // Revancha votada: la sala nueva la monta el servidor cuando han votado
        // todos los que siguen delante de la pantalla, y los votantes entran ya
        // dentro sin pasarse el código.
        if (c.rematchUntil != null) _buildRematch(c),

        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onPlayAgain,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            icon: const Icon(Icons.bolt_rounded, size: 20),
            label: const Text('Otra partida'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onExit,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.home_rounded, size: 20),
            label: const Text('Salir del Versus'),
          ),
        ),
      ],
    );
  }
}

/// Marcador ordenado. Lo comparten el revelado (compacto, entre preguntas) y el
/// podio final.
List<Widget> _buildScoreboard(
  VersusRoomController c,
  List<VersusScore> scores, {
  required bool compact,
}) {
  final rows = c.ranking(scores);
  return List.generate(rows.length, (position) {
    final row = rows[position];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _ScoreRow(
        position: position + 1,
        player: row.player,
        score: row.score,
        isMe: row.score.playerId == c.playerId,
        compact: compact,
      ),
    );
  });
}

/// Carrusel de UNA ronda: enunciado a la izquierda, corrección a la derecha.
///
/// Vive con clave por ronda, así que nace y muere con la pregunta y tiene su
/// propio controlador. Eso es lo que hace que el deslizamiento automático se
/// arme de nuevo en cada una: con un controlador compartido, la cuenta atrás
/// entre rondas desmontaba el PageView y lo dejaba en un estado del que no se
/// recuperaba.
class _RoundCarousel extends StatefulWidget {
  final Widget question;

  /// null mientras no se ha destapado la respuesta.
  final Widget? correction;

  const _RoundCarousel({
    super.key,
    required this.question,
    required this.correction,
  });

  @override
  State<_RoundCarousel> createState() => _RoundCarouselState();
}

class _RoundCarouselState extends State<_RoundCarousel> {
  late final PageController _carousel;
  int _page = 0;

  /// Ya se ha ido solo a la corrección. Una vez por ronda: si se repitiera con
  /// cada evento, volver a la pregunta a mano sería imposible porque el
  /// carrusel te devolvería al instante.
  bool _slid = false;

  @override
  void didUpdateWidget(covariant _RoundCarousel old) {
    super.didUpdateWidget(old);
    // La corrección acaba de aparecer: se va sola a enseñarla.
    if (old.correction == null && widget.correction != null && !_slid) {
      _slid = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_carousel.hasClients) return;
        _carousel.animateToPage(
          1,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // El carrusel puede nacer con la corrección ya puesta: al volver del
    // marcador animado, o al reconectar a mitad del revelado. Entonces no hay
    // transición que detectar y hay que arrancar YA en ella — de ahí el
    // initialPage, y no un salto después del primer frame, que se veía como un
    // parpadeo de la pregunta.
    _slid = widget.correction != null;
    _page = _slid ? 1 : 0;
    _carousel = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _carousel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      widget.question,
      if (widget.correction != null) widget.correction!,
    ];

    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _carousel,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (p) => setState(() => _page = p),
            children: pages,
          ),
        ),
        if (pages.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? kInk : kHairline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Botón de "continuar" del revelado.
///
/// El revelado dura un minuto entero para que dé tiempo a leer la explicación,
/// y se corta antes por MAYORÍA de los que siguen jugando: nadie decide solo.
/// Antes del suelo `skipFrom` se enseña deshabilitado en vez de escondido, para
/// que no parezca que no funciona — ese suelo existe para que dos toques
/// rápidos no se coman la cinemática de caída de Guardia.
class _ContinueButton extends StatelessWidget {
  final VersusRoomController controller;
  final VersusRevealPhase phase;

  const _ContinueButton({required this.controller, required this.phase});

  @override
  Widget build(BuildContext context) {
    // Los eliminados miran: pueden esperar, pero no meter prisa a quien juega.
    if (!controller.canVoteContinue) {
      return const Center(
        child: Text(
          'Estás eliminado: el resto decide cuándo se sigue.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textLight,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final voted = controller.votedContinue(phase.idx);
    final tooSoon = controller.serverNow < phase.skipFrom;
    final enabled = !voted && !tooSoon && !controller.votingContinue;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: enabled
                ? () {
                    HapticsService.light();
                    controller.voteContinue();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: AppColors.surfaceVariant,
              disabledForegroundColor: AppColors.textLight,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: Icon(
              voted ? Icons.check_rounded : Icons.skip_next_rounded,
              size: 20,
            ),
            label: Text(voted ? 'Esperando al resto…' : 'Continuar'),
          ),
        ),
        if (phase.continueTotal > 0) ...[
          const SizedBox(height: 8),
          Text(
            phase.continueVotes == 0
                ? 'Hacen falta ${phase.continueNeeded} para pasar'
                : '${phase.continueVotes} '
                    '${phase.continueVotes == 1 ? 'listo' : 'listos'} '
                    'de ${phase.continueNeeded}',
            style: TextStyle(
              color: phase.continueVotes > 0
                  ? AppColors.primaryDark
                  : AppColors.textLight,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Página de corrección: vive a la DERECHA de la pregunta dentro del carrusel,
/// igual que en el simulacro. Se llega deslizando (o sola, al destaparse la
/// respuesta) y se vuelve deslizando, con las opciones intactas detrás.
class _CorrectionPage extends StatelessWidget {
  final VersusRoomController controller;
  final VersusRevealPhase phase;

  const _CorrectionPage({required this.controller, required this.phase});

  String _names(List<String> ids) => ids
      .map((id) => controller.playerById(id)?.nickname)
      .whereType<String>()
      .join(', ');

  List<Widget> _buildCasualties() {
    final fallen = _names(phase.eliminated);
    final hurt = _names(phase.wounded);
    if (fallen.isEmpty && hurt.isEmpty) return const [];

    return [
      const SizedBox(height: 12),
      if (hurt.isNotEmpty)
        _CasualtyLine(
          icon: Icons.heart_broken_rounded,
          color: AppColors.warning,
          text: '$hurt ${phase.wounded.length == 1 ? 'pierde' : 'pierden'} '
              'una vida',
        ),
      if (fallen.isNotEmpty)
        _CasualtyLine(
          icon: Icons.dangerous_rounded,
          color: AppColors.error,
          text: '$fallen ${phase.eliminated.length == 1 ? 'cae' : 'caen'}',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    VersusResult? mine;
    for (final r in phase.results) {
      if (r.playerId == controller.playerId) mine = r;
    }

    final String headline;
    final Color headlineColor;
    final IconData icon;
    if (mine == null || mine.selected == null) {
      headline = 'Sin respuesta';
      headlineColor = AppColors.textSecondary;
      icon = Icons.remove_circle_outline_rounded;
    } else if (mine.isCorrect == true) {
      headline = '¡Correcto!  +${mine.points}';
      headlineColor = AppColors.successDark;
      icon = Icons.check_circle_rounded;
    } else {
      headline = 'Fallaste';
      headlineColor = AppColors.error;
      icon = Icons.cancel_rounded;
    }

    final explanation = phase.explanation?.trim() ?? '';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            const Icon(Icons.chevron_left_rounded,
                size: 20, color: AppColors.textLight),
            Text(
              'Vuelve deslizando a la pregunta',
              style: TextStyle(
                color: AppColors.textLight.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Veredicto, con el color del resultado.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tinted(headlineColor, 0.18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kInk, width: 2),
            boxShadow: inkShadow(4),
          ),
          child: Row(
            children: [
              Icon(icon, color: headlineColor, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: headlineColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Guardia: quién ha perdido vida y quién ha caído en esta ronda.
        ..._buildCasualties(),

        const SizedBox(height: 18),
        const Text(
          'EXPLICACIÓN',
          style: TextStyle(
            color: AppColors.textLight,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          explanation.isNotEmpty
              ? explanation
              : 'No hay explicación disponible para esta pregunta.',
          style: TextStyle(
            color: explanation.isNotEmpty
                ? AppColors.textPrimary
                : AppColors.textLight,
            fontSize: 14,
            height: 1.55,
          ),
        ),

        const SizedBox(height: 20),
        _ContinueButton(controller: controller, phase: phase),

        // Aquí NO va el marcador: en clásico ya se ha visto en su propia
        // pantalla, con los puntos subiendo, y en Guardia lo dicen los
        // corazones. Repetirlo solo robaba sitio a la explicación.
      ],
    );
  }
}

// ==========================
// Piezas
// ==========================

class _OptionTile extends StatelessWidget {
  final String letter;
  final String text;
  final List<VersusPlayer> here;
  final bool isMine;

  /// null mientras no se ha revelado.
  final bool? isCorrect;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionTile({
    required this.letter,
    required this.text,
    required this.here,
    required this.isMine,
    required this.isCorrect,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = kHairline;
    Color background = AppColors.surface;
    Color letterBg = AppColors.surfaceVariant;
    Color letterFg = kInk;
    double opacity = 1;
    bool raised = false;

    if (isCorrect != null) {
      if (isCorrect!) {
        border = kInk;
        background = tinted(AppColors.success, 0.18);
        letterBg = AppColors.success;
        letterFg = Colors.white;
        raised = true;
      } else if (isMine) {
        border = kInk;
        background = tinted(AppColors.error, 0.16);
        letterBg = AppColors.error;
        letterFg = Colors.white;
        raised = true;
      } else {
        opacity = 0.55;
      }
    } else if (isMine) {
      border = kInk;
      background = tinted(AppColors.primary, 0.20);
      letterBg = AppColors.primary;
      letterFg = Colors.white;
      raised = true;
    }

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 2),
            boxShadow: raised ? inkShadow(3) : const [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: letterBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kInk, width: 1.6),
                ),
                child: Text(
                  letter,
                  style: TextStyle(
                    color: letterFg,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: kInk,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              // Los avatares solo aparecen en 'picks' y 'reveal': verlos
              // durante la pregunta sería copiar.
              if (here.isNotEmpty) ...[
                const SizedBox(width: 8),
                _AvatarStack(players: here),
              ],
              if (isCorrect == true) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatares superpuestos, como en la web. Se cortan a 4 para que la fila no
/// empuje el texto de la opción.
class _AvatarStack extends StatelessWidget {
  final List<VersusPlayer> players;

  const _AvatarStack({required this.players});

  @override
  Widget build(BuildContext context) {
    const double size = 26;
    const double overlap = 8;
    final shown = players.take(4).toList();
    final extra = players.length - shown.length;

    return SizedBox(
      height: size,
      width: shown.length * (size - overlap) + overlap + (extra > 0 ? 20 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(1.5),
                child: VersusAvatar(player: shown[i], size: size - 3),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceVariant,
                ),
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Guardia: corazones de cada jugador, siempre a la vista durante la ronda.
class _LivesStrip extends StatelessWidget {
  final VersusRoomController controller;

  const _LivesStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    // Los caídos van al final: los que siguen en pie son lo que importa mirar.
    final players = [...controller.players]..sort((a, b) {
        if (a.eliminated == b.eliminated) return 0;
        return a.eliminated ? 1 : -1;
      });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (final player in players)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              // La clave es imprescindible: la tira manda a los caídos al final,
              // así que sin ella Flutter reutilizaría el estado de una ficha
              // para OTRO jugador y la sacudida saltaría en quien no es.
              child: _LifeChip(
                key: ValueKey(player.id),
                player: player,
                isMe: player.id == controller.playerId,
                // Con cuántas vidas se repartió, para dibujar los huecos.
                maxLives: controller.room?.config.lives ?? 1,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ficha de un jugador en el HUD. Sacude y destella cuando pierde una vida:
/// que el número baje sin más no se ve, y era justo lo que hacía que las bajas
/// pasaran desapercibidas.
class _LifeChip extends StatefulWidget {
  final VersusPlayer player;
  final bool isMe;

  /// Vidas con las que arrancó la partida. Marca cuántos corazones se pintan,
  /// llenos o vacíos.
  final int maxLives;

  const _LifeChip({
    super.key,
    required this.player,
    required this.isMe,
    required this.maxLives,
  });

  @override
  State<_LifeChip> createState() => _LifeChipState();
}

class _LifeChipState extends State<_LifeChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void didUpdateWidget(covariant _LifeChip old) {
    super.didUpdateWidget(old);
    final before = old.player.lives ?? 0;
    final now = widget.player.lives ?? 0;
    final justFell = !old.player.eliminated && widget.player.eliminated;
    if (now >= before && !justFell) return;

    _hit.forward(from: 0);

    // Un corazón por cada vida perdida, despegándose de ESTA ficha. Se lanza
    // tras el frame porque hasta entonces la ficha no tiene posición en
    // pantalla que darle al Overlay.
    final lost = (before - now).clamp(1, 5);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (int i = 0; i < lost; i++) {
        Future.delayed(Duration(milliseconds: 90 * i), () {
          if (mounted) dropHeartFrom(context, size: widget.isMe ? 30 : 22);
        });
      }
    });
  }

  @override
  void dispose() {
    _hit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _hit,
      builder: (context, child) {
        final t = _hit.value;
        // Sacudida corta y decreciente, como un impacto.
        final shake = t == 0 ? 0.0 : math.sin(t * 38) * 6 * (1 - t);
        final flash = t == 0 ? 0.0 : (1 - t) * 0.5;

        return Transform.translate(
          offset: Offset(shake, 0),
          child: Stack(
            children: [
              child!,
              if (flash > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: flash),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: _buildChip(),
    );
  }

  Widget _buildChip() {
    final player = widget.player;
    final isMe = widget.isMe;
    final down = player.eliminated;
    final lives = player.lives ?? 0;
    // Cuántos corazones caben en la ficha: los que se repartieron, no los que
    // quedan. Así se ve el hueco de lo que ya has gastado.
    final huecos = lives > widget.maxLives ? lives : widget.maxLives;

    return Opacity(
      opacity: down ? 0.45 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isMe ? kInk : kHairline,
            width: isMe ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VersusAvatar(player: player, size: 22, dimmed: down || player.away),
            const SizedBox(width: 6),
            if (down)
              const Icon(Icons.dangerous_rounded,
                  size: 15, color: AppColors.error)
            else
              // Más de tres vidas en corazones ocuparía media pantalla.
              huecos > 3
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite_rounded,
                            size: 13, color: AppColors.error),
                        const SizedBox(width: 3),
                        Text(
                          '×$lives/$huecos',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  // Los corazones perdidos NO se quitan: se quedan en el sitio,
                  // vacíos. Pintar solo los que quedaban escondía cuánto
                  // llevabas gastado, que es media tensión de una Guardia.
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < huecos; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Icon(
                              i < lives
                                  ? Icons.favorite_rounded
                                  : Icons.heart_broken_rounded,
                              size: 13,
                              color: i < lives
                                  ? AppColors.error
                                  : AppColors.border,
                            ),
                          ),
                      ],
                    ),
          ],
        ),
      ),
    );
  }
}

/// Fila del podio de Guardia: en pie con sus corazones, o caído y en qué
/// pregunta se quedó.
class _SurvivorRow extends StatelessWidget {
  final int position;
  final VersusPlayer player;
  final bool isMe;

  const _SurvivorRow({
    required this.position,
    required this.player,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final down = player.eliminated;
    final winner = position == 1 && !down;

    return Opacity(
      opacity: down ? 0.62 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: winner
              ? AppColors.success.withValues(alpha: 0.1)
              : isMe
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: winner
                ? AppColors.success
                : isMe
                    ? AppColors.primary
                    : AppColors.border,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: winner
                  ? const Icon(Icons.emoji_events_rounded,
                      size: 19, color: AppColors.success)
                  : Text(
                      '$position',
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 4),
            VersusAvatar(player: player, size: 36, dimmed: down),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                player.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (down)
              Text(
                'cayó en la ${(player.eliminatedAtIdx ?? 0) + 1}',
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 12,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < (player.lives ?? 0); i++)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.favorite_rounded,
                          size: 15, color: AppColors.error),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CasualtyLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _CasualtyLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final int position;
  final VersusPlayer? player;
  final VersusScore score;
  final bool isMe;
  final bool compact;

  const _ScoreRow({
    required this.position,
    required this.player,
    required this.score,
    required this.isMe,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final away = player?.away ?? false;
    // "Se fue" es definitivo; "sin señal" se deshace solo si vuelve a latir.
    final awayLabel = player == null
        ? null
        : player!.left
            ? 'se fue'
            : player!.connected
                ? null
                : 'sin señal';

    return Opacity(
      opacity: away ? 0.5 : 1,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 10 : 14,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe ? kInk : kHairline,
            width: compact ? 1 : 2,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$position',
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (player != null) ...[
              VersusAvatar(
                player: player!,
                size: compact ? 28 : 36,
                dimmed: away,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      player?.nickname ?? 'Jugador',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (awayLabel != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      awayLabel,
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!compact) ...[
              Text(
                '${score.correct} aciertos',
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              '${score.score}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
