import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';

/// Estudio de un grupo de flashcards.
///
/// La cola es propia (`/flashcard-decks/:id/next`) pero el motor de repetición
/// espaciada es el mismo de los mazos: se abre sesión con `start-session`, se
/// registra cada tarjeta con `log` y se cierra con `end`. La diferencia con un
/// mazo de preguntas es quién corrige: aquí lo dice el usuario, porque no hay
/// opciones que comparar.
class FlashcardStudyScreen extends StatefulWidget {
  final FlashDeck deck;
  final int limit;

  const FlashcardStudyScreen({
    super.key,
    required this.deck,
    required this.limit,
  });

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> {
  String? _sessionId;
  Flashcard? _card;
  bool _loading = true;
  bool _busy = false;
  bool _revealed = false;
  String? _error;

  /// Cómo terminó la sesión, para explicarlo bien al usuario.
  FlashNextKind? _finished;

  int _seen = 0;
  int _known = 0;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // Cerrar la sesión es "best-effort": si falla, el backend la caduca sola.
    final id = _sessionId;
    if (id != null) _api.endDeckSession(id).catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final id = await _api.startDeckSession(widget.deck.id, widget.limit);
      if (!mounted) return;
      _sessionId = id;
      await _next();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudo empezar la sesión de estudio.';
        _loading = false;
      });
    }
  }

  Future<void> _next() async {
    final id = _sessionId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _revealed = false;
    });
    try {
      final res = await _api.getNextFlashcard(widget.deck.id, id);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res.kind == FlashNextKind.card) {
          _card = res.card;
        } else {
          _card = null;
          _finished = res.kind;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudo cargar la siguiente tarjeta.';
        _loading = false;
      });
    }
  }

  Future<void> _answer(bool isCorrect) async {
    final id = _sessionId;
    final card = _card;
    if (id == null || card == null || _busy) return;

    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      await _api.logFlashcard(
        deckId: widget.deck.id,
        deckItemId: card.itemId,
        isCorrect: isCorrect,
        sessionId: id,
      );
      if (!mounted) return;
      setState(() {
        _seen++;
        if (isCorrect) _known++;
        _busy = false;
      });
      await _next();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo registrar la respuesta.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.deck.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_seen > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: DocChip(label: '$_known / $_seen', tone: DocTone.accent),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _error != null
            ? _Message(
                icon: Icons.cloud_off_rounded,
                title: 'Algo ha fallado',
                body: _error!,
                actionLabel: 'Volver',
                onAction: () => Navigator.of(context).pop(),
              )
            : _finished != null
                ? _finishedView()
                : _loading || _card == null
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary))
                    : _studyView(_card!),
      ),
    );
  }

  Widget _studyView(Flashcard card) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: _FlipCard(
              revealed: _revealed,
              front: card.front,
              back: card.back,
              onTap: () => setState(() => _revealed = !_revealed),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: kInk, width: 2)),
          ),
          child: SafeArea(
            top: false,
            child: _revealed
                // Ya vista la respuesta, la corrección la pone el usuario.
                ? Row(
                    children: [
                      Expanded(
                        child: StickerButton(
                          label: 'No me la sabía',
                          icon: Icons.close_rounded,
                          color: AppColors.error,
                          expand: true,
                          onPressed: _busy ? null : () => _answer(false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StickerButton(
                          label: 'Me la sabía',
                          icon: Icons.check_rounded,
                          color: AppColors.success,
                          expand: true,
                          onPressed: _busy ? null : () => _answer(true),
                        ),
                      ),
                    ],
                  )
                : StickerButton(
                    label: 'Ver la respuesta',
                    icon: Icons.flip_rounded,
                    expand: true,
                    onPressed: () => setState(() => _revealed = true),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _finishedView() {
    final (title, body) = switch (_finished!) {
      FlashNextKind.limit => (
          'Objetivo cumplido',
          'Has llegado al número de tarjetas que te habías propuesto para esta sesión.'
        ),
      FlashNextKind.expired => (
          'La sesión ha caducado',
          'Llevaba demasiado tiempo abierta. Empieza otra cuando quieras.'
        ),
      _ => (
          'No queda nada por repasar',
          'Has repasado todas las tarjetas que tocaban hoy en este grupo.'
        ),
    };

    return _Message(
      icon: Icons.check_circle_rounded,
      title: title,
      body: _seen == 0
          ? body
          : '$body\n\nTe sabías $_known de las $_seen que has visto.',
      actionLabel: 'Volver al grupo',
      onAction: () => Navigator.of(context).pop(),
    );
  }
}

/// La tarjeta que se voltea. El giro es de verdad (3D con perspectiva), y a
/// mitad de camino se cambia la cara para que nunca se lea el texto del revés.
///
/// Las dos caras se construyen **una vez** y solo se mueven: antes se volvían a
/// montar en cada fotograma, y con ellas la textura de la cartulina, que son
/// varias decenas de líneas por repintado.
class _FlipCard extends StatefulWidget {
  final bool revealed;
  final String front;
  final String back;
  final VoidCallback onTap;

  const _FlipCard({
    required this.revealed,
    required this.front,
    required this.back,
    required this.onTap,
  });

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.revealed ? 1 : 0,
  );

  late final CurvedAnimation _t =
      CurvedAnimation(parent: _c, curve: kEaseOut);

  // Las caras, cacheadas. Solo se rehacen si cambia el texto, o sea al pasar
  // de tarjeta.
  Widget? _frontFace;
  Widget? _backFace;

  @override
  void initState() {
    super.initState();
    _buildFaces();
  }

  @override
  void didUpdateWidget(covariant _FlipCard old) {
    super.didUpdateWidget(old);
    if (old.front != widget.front || old.back != widget.back) _buildFaces();
    if (old.revealed != widget.revealed) {
      widget.revealed ? _c.forward() : _c.reverse();
    }
  }

  void _buildFaces() {
    _frontFace = _face(
      text: widget.front,
      label: 'ANVERSO',
      accent: kAccent,
    );
    _backFace = _face(
      text: widget.back,
      label: 'REVERSO',
      accent: AppColors.success,
    );
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final angle = _t.value * math.pi;
            final showBack = _t.value > 0.5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012) // perspectiva
                ..rotateY(angle),
              child: Transform(
                alignment: Alignment.center,
                // La cara de atrás se contragira, o saldría en espejo.
                transform: Matrix4.identity()..rotateY(showBack ? math.pi : 0),
                // Al ser la MISMA instancia de widget entre fotogramas, Flutter
                // se salta el rebuild del subárbol.
                child: showBack ? _backFace! : _frontFace!,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _face({
    required String text,
    required String label,
    required Color accent,
  }) {
    return StickerCard(
      depth: 6,
      radius: 24,
      padding: const EdgeInsets.all(22),
      texture: tintedPaper(accent, step: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: kInk, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  color: kMuted.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                text,
                style: const TextStyle(
                  color: kInk,
                  fontSize: 18,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              'Toca la tarjeta para girarla',
              style: TextStyle(
                color: kMuted.withOpacity(0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: StickerCard(
          depth: 5,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: kInk, width: 2),
                  boxShadow: inkShadow(4),
                ),
                child: Icon(icon, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kInk,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kMuted.withOpacity(0.95),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              StickerButton(
                label: actionLabel,
                expand: true,
                onPressed: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
