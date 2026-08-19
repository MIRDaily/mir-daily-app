import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/zoomable_image.dart';

/// Sesión de estudio de un mazo (repetición espaciada). Pide items al backend
/// (start-session → next → log → end) y da feedback inmediato tipo flashcard.
class DeckStudyScreen extends StatefulWidget {
  final Deck deck;
  final int limit;

  const DeckStudyScreen({super.key, required this.deck, required this.limit});

  @override
  State<DeckStudyScreen> createState() => _DeckStudyScreenState();
}

class _DeckStudyScreenState extends State<DeckStudyScreen> {
  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

  String? _sessionId;
  DeckCard? _current;
  int? _selected;
  bool _revealed = false;
  bool _lastCorrect = false;
  bool _busy = false;
  bool _finished = false;
  bool _loadingItem = true;
  String? _error;

  int _answered = 0;
  int _correct = 0;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    try {
      _sessionId = await _api.startDeckSession(widget.deck.id, widget.limit);
      await _loadNext();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'No se pudo iniciar la sesión de estudio.';
        _loadingItem = false;
      });
    }
  }

  Future<void> _loadNext() async {
    setState(() {
      _loadingItem = true;
      _selected = null;
      _revealed = false;
    });
    try {
      final item = await _api.getNextDeckItem(widget.deck.id, _sessionId!);
      if (!mounted) return;
      if (item == null) {
        await _finish();
        return;
      }
      setState(() {
        _current = item;
        _loadingItem = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la siguiente carta.';
        _loadingItem = false;
      });
    }
  }

  Future<void> _check() async {
    if (_selected == null || _revealed || _busy) return;
    setState(() => _busy = true);
    try {
      final correct = await _api.logDeckItem(
        deckId: widget.deck.id,
        deckItemId: _current!.itemId,
        selectedOption: _selected! + 1, // backend 1-based
        sessionId: _sessionId!,
      );
      if (!mounted) return;
      setState(() {
        _revealed = true;
        _lastCorrect = correct;
        _busy = false;
        _answered++;
        if (correct) _correct++;
      });
      if (correct) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.vibrate();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo registrar la respuesta. Reintenta.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _finish() async {
    try {
      if (_sessionId != null) await _api.endDeckSession(_sessionId!);
    } catch (_) {}
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.deck.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_finished && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$_correct/$_answered',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 56, color: AppColors.textLight),
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      );
    }

    if (_finished) return _summary();

    if (_loadingItem || _current == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final q = _current!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _questionCard(q),
                const SizedBox(height: 18),
                ..._options(q),
              ],
            ),
          ),
        ),
        _bottomBar(q),
      ],
    );
  }

  Widget _questionCard(DeckCard q) {
    return StickerCard(
      depth: 5,
      radius: 22,
      padding: const EdgeInsets.all(20),
      // Cartulina rayada: la carta que se repasa es una ficha de estudio.
      texture: ruledPaper(step: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (q.subject != null)
            DocChip(label: q.subject!, tone: DocTone.accent),
          const SizedBox(height: 12),
          Text(
            q.statement,
            style: const TextStyle(
              color: kInk,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (q.hasImage && q.imageUrl != null) ...[
            const SizedBox(height: 12),
            ZoomableImage(
                url: q.imageUrl!,
                borderRadius: BorderRadius.circular(14)),
          ],
        ],
      ),
    );
  }

  List<Widget> _options(DeckCard q) {
    final widgets = <Widget>[];
    for (var i = 0; i < q.options.length; i++) {
      final selected = _selected == i;
      final isCorrect = q.correctIndex == i;

      // En reposo la opcion lleva trazo suave; en cuanto se elige o se
      // corrige pasa a trazo de tinta con sombra dura, que es como el sistema
      // marca lo que esta "activo".
      Color border = kHairline;
      Color bg = AppColors.surface;
      Color letterBg = AppColors.surfaceVariant;
      Color letterFg = kMuted;
      bool raised = false;

      if (_revealed) {
        if (isCorrect) {
          border = kInk;
          bg = tinted(AppColors.success, 0.18);
          letterBg = AppColors.success;
          letterFg = Colors.white;
          raised = true;
        } else if (selected) {
          border = kInk;
          bg = tinted(AppColors.error, 0.16);
          letterBg = AppColors.error;
          letterFg = Colors.white;
          raised = true;
        }
      } else if (selected) {
        border = kInk;
        bg = tinted(AppColors.primary, 0.20);
        letterBg = AppColors.primary;
        letterFg = Colors.white;
        raised = true;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Pressable(
            onTap: _revealed ? null : () => setState(() => _selected = i),
            pressedScale: 0.98,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border, width: 2),
                boxShadow: raised ? inkShadow(3) : const [],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: letterBg,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: kInk, width: 1.6),
                    ),
                    child: _revealed && isCorrect
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 17)
                        : _revealed && selected
                            ? const Icon(Icons.close_rounded,
                                color: Colors.white, size: 17)
                            : Text(
                                _letters[i],
                                style: TextStyle(
                                  color: letterFg,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        q.options[i],
                        style: const TextStyle(
                          color: kInk,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _bottomBar(DeckCard q) {
    return Container(
      decoration: BoxDecoration(
        color: !_revealed
            ? AppColors.surface
            : _lastCorrect
                ? AppColors.success.withValues(alpha: 0.16)
                : AppColors.errorSoft,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textSecondary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_revealed) ...[
              Text(
                _lastCorrect
                    ? '¡Correcto!'
                    : 'La correcta era la ${_letters[q.correctIndex.clamp(0, 5)]}',
                style: TextStyle(
                  color: _lastCorrect ? AppColors.successDark : AppColors.error,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              if ((q.explanation ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: SingleChildScrollView(
                    child: Text(
                      q.explanation!,
                      style: const TextStyle(
                        color: kInk,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
            ],
            Pressable(
              onTap: _revealed
                  ? _loadNext
                  : _selected != null
                      ? _check
                      : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _revealed
                      ? (_lastCorrect ? AppColors.success : AppColors.error)
                      : _selected != null
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kInk, width: 2),
                  boxShadow:
                      _revealed || _selected != null ? inkShadow(4) : const [],
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.4),
                      )
                    : Text(
                        _revealed ? 'CONTINUAR' : 'COMPROBAR',
                        style: TextStyle(
                          color: _selected != null || _revealed
                              ? Colors.white
                              : kMuted,
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    final pct = _answered > 0 ? (_correct / _answered * 100).round() : 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              pct >= 70 ? Icons.celebration_rounded : Icons.emoji_events_rounded,
              size: 76,
              color: AppColors.primary,
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Sesión completada!',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _answered == 0
                  ? 'No quedaban cartas por repasar ahora mismo.'
                  : '$_correct de $_answered correctas',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 16),
            ),
            if (_answered > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: pct >= 70 ? AppColors.success : AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Terminar'),
            ),
          ],
        ),
      ),
    );
  }
}
