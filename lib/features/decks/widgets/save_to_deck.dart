/* ════════════════════════════════════════════════════════════════════════
   "Guardar en mazo", disponible desde cualquier sitio donde se vea una
   pregunta: durante el daily y su revisión, durante un simulacro y en el
   repaso de uno guardado.

   El popup es el mismo de la web (`src/components/simulacro/SaveToDeckButton.tsx`):
   una tarjeta flotante que enseña TODOS los mazos y, en cada uno, si la
   pregunta ya está dentro. Tocar un mazo la guarda; tocar uno donde ya está,
   la quita. Se puede guardar en varios sin cerrar, y el aviso de lo que ha
   pasado sale dentro del propio popup en vez de en un mensaje de abajo.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/models.dart';
import '../../../core/providers/saved_questions_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import 'deck_gradient.dart';

/// Abre el popup de mazos para [questionId].
///
/// Devuelve true si, al cerrarlo, la pregunta está guardada en algún mazo —
/// así el botón que lo abrió puede quedarse marcado.
Future<bool> showSaveToDeckSheet(
  BuildContext context, {
  required String questionId,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierColor: kInk.withValues(alpha: 0.35),
    builder: (_) => _SaveToDeckDialog(questionId: questionId),
  );
  return saved ?? false;
}

class _SaveToDeckDialog extends StatefulWidget {
  final String questionId;

  const _SaveToDeckDialog({required this.questionId});

  @override
  State<_SaveToDeckDialog> createState() => _SaveToDeckDialogState();
}

class _SaveToDeckDialogState extends State<_SaveToDeckDialog> {
  List<Deck>? _decks;
  String? _error;

  /// deckId -> itemId de la pregunta dentro de ese mazo. Si no está la clave,
  /// la pregunta no está en ese mazo.
  Map<String, String> _membership = {};
  bool _checking = true;

  /// Mazos con una operación en curso, para que cada fila tenga su propio
  /// indicador sin bloquear el resto del popup.
  final Set<String> _pending = {};

  bool _showCreate = false;
  bool _creating = false;
  final TextEditingController _nameCtrl = TextEditingController();

  ({bool ok, String text})? _feedback;
  Timer? _feedbackTimer;

  ApiService get _api => context.read<ApiService>();

  bool get _savedAnywhere => _membership.isNotEmpty;

  /// Cuenta al resto de la app si la pregunta está guardada, para que el
  /// icono siga en verde aunque su widget se reconstruya (al pulsar
  /// "Comprobar", al pasar a la revisión final...).
  void _publishSaved() {
    context
        .read<SavedQuestionsProvider>()
        .setSaved(widget.questionId, _savedAnywhere);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _say(bool ok, String text) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = (ok: ok, text: text));
    _feedbackTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  Future<void> _load() async {
    try {
      // Una sola petición: los mazos Y en cuáles está ya la pregunta. Antes
      // eran dos pasos en serie, y el segundo recorría paginando los items de
      // todos los mazos: de ahí salían las dos esperas al abrir esto.
      final res = await _api.getDecksWithSaved(widget.questionId);
      if (!mounted) return;
      // El mazo automático de fallos no admite preguntas a mano (403 en el
      // backend), así que no se ofrece.
      final propios = res.decks.where((d) => !d.isAutoManaged).toList();
      setState(() {
        _decks = propios;
        _membership = {...res.membership};
        _error = null;
        _checking = false;
      });
      _publishSaved();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus mazos.';
        _checking = false;
      });
    }
  }

  Future<void> _toggle(Deck deck) async {
    if (_pending.contains(deck.id)) return;
    setState(() => _pending.add(deck.id));

    final itemId = _membership[deck.id];
    try {
      if (itemId != null) {
        await _api.removeDeckItem(deck.id, itemId);
        if (!mounted) return;
        setState(() => _membership.remove(deck.id));
        _publishSaved();
        _say(true, 'Quitada de "${deck.name}"');
      } else {
        // La propia respuesta trae el id de la fila creada: sin él no se
        // podría deshacer sin cerrar y volver a abrir, y antes costaba releer
        // el mazo entero para averiguarlo.
        final creados = await _api.addDeckItems(deck.id, [widget.questionId]);
        if (!mounted) return;
        setState(() {
          final nuevo = creados[widget.questionId];
          if (nuevo != null) _membership[deck.id] = nuevo;
        });
        _publishSaved();
        _say(true, 'Guardada en "${deck.name}"');
      }
    } catch (e) {
      if (!mounted) return;
      _say(false, e is ApiException ? e.message : 'No se pudo actualizar.');
    } finally {
      if (mounted) setState(() => _pending.remove(deck.id));
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 3) {
      _say(false, 'El nombre necesita al menos 3 letras.');
      return;
    }
    setState(() => _creating = true);
    try {
      await _api.createDeck(name);
      final res = await _api.getDecksWithSaved(widget.questionId);
      if (!mounted) return;
      final propios = res.decks.where((d) => !d.isAutoManaged).toList();
      final creado = propios.where((d) => d.name == name).firstOrNull;
      setState(() {
        _decks = propios;
        _showCreate = false;
        _creating = false;
      });
      _nameCtrl.clear();
      if (creado != null) {
        // Recién creado: se guarda dentro directamente, que es a lo que venía.
        await _toggle(creado);
      } else {
        _say(true, 'Mazo "$name" creado');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      _say(false, e is ApiException ? e.message : 'No se pudo crear el mazo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(6),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'GUARDAR EN MAZO',
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, _savedAnywhere),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_showCreate) _createForm() else _createButton(),
            const SizedBox(height: 10),
            Flexible(child: _deckList()),
            if (_feedback != null) ...[
              const SizedBox(height: 10),
              _feedbackBanner(_feedback!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _createButton() {
    return GestureDetector(
      onTap: () => setState(() => _showCreate = true),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: kHairline,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 17, color: AppColors.textSecondary),
            SizedBox(width: 6),
            Text(
              'NUEVO MAZO',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _createForm() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CREAR MAZO',
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _showCreate = false;
                  _nameCtrl.clear();
                }),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kHairline, width: 2),
                  ),
                  child: Center(
                    child: TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _create(),
                      style: const TextStyle(
                        color: kInk,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Nombre del mazo...',
                        hintStyle: TextStyle(
                          color: AppColors.textLight,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _creating ? null : _create,
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kInk, width: 2),
                  ),
                  child: _creating
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Icon(Icons.keyboard_return_rounded,
                          size: 17, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deckList() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    final decks = _decks;
    if (decks == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.primary),
          ),
        ),
      );
    }

    if (decks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18, horizontal: 6),
        child: Text(
          'Aún no tienes mazos propios. Crea el primero aquí arriba.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      itemCount: decks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final deck = decks[i];
        return _DeckRow(
          deck: deck,
          saved: _membership.containsKey(deck.id),
          // Mientras se comprueba, la fila no promete nada: enseñar "GUARDAR"
          // antes de saberlo haría creer que no está cuando quizá sí.
          checking: _checking,
          busy: _pending.contains(deck.id),
          onTap: () => _toggle(deck),
        );
      },
    );
  }

  Widget _feedbackBanner(({bool ok, String text}) f) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: f.ok ? const Color(0xFFEEF7EE) : const Color(0xFFFFF0EE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            f.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 15,
            color: f.ok ? AppColors.successDark : AppColors.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              f.text,
              style: TextStyle(
                color: f.ok ? AppColors.successDark : AppColors.error,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckRow extends StatelessWidget {
  final Deck deck;
  final bool saved;
  final bool checking;
  final bool busy;
  final VoidCallback onTap;

  const _DeckRow({
    required this.deck,
    required this.saved,
    required this.checking,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: checking ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: saved ? const Color(0xFFEEF7EE) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: saved ? AppColors.success : kHairline,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // La muestra de color de su portada: lo reconoces por lo mismo que
            // en la galería.
            DeckGradientSwatch(id: deck.bannerGradient ?? '', size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                deck.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: saved ? AppColors.successDark : kInk,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (busy || checking)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
            else ...[
              Text(
                saved ? 'QUITAR' : 'GUARDAR',
                style: TextStyle(
                  color: saved ? AppColors.successDark : AppColors.textSecondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                saved
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                size: 17,
                color: saved ? AppColors.successDark : AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Botón de "guardar en mazo" para la cabecera de una pregunta.
///
/// No guarda estado propio: si la pregunta está en algún mazo lo dice
/// [SavedQuestionsProvider]. Cuando lo guardaba aquí dentro, la marca verde
/// se perdía en cuanto Flutter reconstruía el widget — al pulsar "Comprobar"
/// o al pasar a la revisión final del simulacro.
class SaveToDeckButton extends StatelessWidget {
  final String? questionId;

  /// Color del icono, para que encaje con la cabecera donde se coloque.
  final Color color;
  final double size;

  const SaveToDeckButton({
    super.key,
    required this.questionId,
    this.color = AppColors.textSecondary,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final id = questionId;
    if (id == null || id.isEmpty) return const SizedBox.shrink();

    // Por pregunta, así que tampoco se arrastra a la siguiente.
    final saved = context.watch<SavedQuestionsProvider>().isSaved(id);

    return IconButton(
      onPressed: () => showSaveToDeckSheet(context, questionId: id),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: 'Guardar en un mazo',
      icon: Icon(
        saved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
        size: size,
        color: saved ? AppColors.successDark : color,
      ),
    );
  }
}
