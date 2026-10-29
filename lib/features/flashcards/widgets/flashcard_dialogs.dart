import 'package:flutter/material.dart';

import '../../../core/models/flashcards.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/sticker/sticker.dart';
import 'flashcards_ui.dart';

/// Lo que devuelve el diálogo de grupo.
class FlashDeckDraft {
  final String name;
  final String description;

  const FlashDeckDraft(this.name, this.description);
}

/// Lo que devuelve el diálogo de tarjeta.
class FlashcardDraft {
  final String front;
  final String back;
  final String? topic;
  final int? level;

  const FlashcardDraft(this.front, this.back, {this.topic, this.level});
}

/// Alta o renombrado de un grupo de flashcards.
Future<FlashDeckDraft?> showFlashDeckDialog(
  BuildContext context, {
  String initialName = '',
  String initialDescription = '',
}) {
  final editing = initialName.isNotEmpty;
  return showDialog<FlashDeckDraft>(
    context: context,
    builder: (ctx) => _FlashDeckDialog(
      editing: editing,
      initialName: initialName,
      initialDescription: initialDescription,
    ),
  );
}

class _FlashDeckDialog extends StatefulWidget {
  final bool editing;
  final String initialName;
  final String initialDescription;

  const _FlashDeckDialog({
    required this.editing,
    required this.initialName,
    required this.initialDescription,
  });

  @override
  State<_FlashDeckDialog> createState() => _FlashDeckDialogState();
}

class _FlashDeckDialogState extends State<_FlashDeckDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _description =
      TextEditingController(text: widget.initialDescription);
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    // El backend exige 3 caracteres; avisamos antes para no gastar un viaje.
    if (name.length < 3) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop(context, FlashDeckDraft(name, _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _tried && _name.text.trim().length < 3;

    return _StickerDialog(
      title: widget.editing ? 'Editar grupo' : 'Nuevo grupo',
      icon: Icons.folder_rounded,
      onConfirm: _submit,
      confirmLabel: widget.editing ? 'Guardar' : 'Crear',
      children: [
        InkInput(
          controller: _name,
          hint: 'Nombre (mín. 3 letras)',
          autofocus: true,
          maxLength: 60,
          invalid: invalid,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        if (invalid) ...[
          const SizedBox(height: 6),
          const Text(
            'El nombre debe tener al menos 3 letras.',
            style: TextStyle(
              color: Color(0xFFC4655A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 12),
        InkInput(
          controller: _description,
          hint: 'Descripción (opcional)',
          maxLength: 140,
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Alta o edición de una tarjeta (anverso, reverso y dificultad).
Future<FlashcardDraft?> showFlashcardDialog(
  BuildContext context, {
  String initialFront = '',
  String initialBack = '',
  int? initialLevel,
}) {
  final editing = initialFront.isNotEmpty || initialBack.isNotEmpty;
  return showDialog<FlashcardDraft>(
    context: context,
    builder: (ctx) => _FlashcardDialog(
      editing: editing,
      initialFront: initialFront,
      initialBack: initialBack,
      initialLevel: initialLevel,
    ),
  );
}

class _FlashcardDialog extends StatefulWidget {
  final bool editing;
  final String initialFront;
  final String initialBack;
  final int? initialLevel;

  const _FlashcardDialog({
    required this.editing,
    required this.initialFront,
    required this.initialBack,
    this.initialLevel,
  });

  @override
  State<_FlashcardDialog> createState() => _FlashcardDialogState();
}

class _FlashcardDialogState extends State<_FlashcardDialog> {
  late final _front = TextEditingController(text: widget.initialFront);
  late final _back = TextEditingController(text: widget.initialBack);
  late int? _level = widget.initialLevel;
  bool _tried = false;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  void _submit() {
    final front = _front.text.trim();
    final back = _back.text.trim();
    if (front.isEmpty || back.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop(context, FlashcardDraft(front, back, level: _level));
  }

  @override
  Widget build(BuildContext context) {
    final frontEmpty = _tried && _front.text.trim().isEmpty;
    final backEmpty = _tried && _back.text.trim().isEmpty;

    return _StickerDialog(
      title: widget.editing ? 'Editar tarjeta' : 'Nueva tarjeta',
      icon: Icons.style_rounded,
      onConfirm: _submit,
      confirmLabel: widget.editing ? 'Guardar' : 'Crear',
      children: [
        const _FieldLabel('Anverso'),
        InkInput(
          controller: _front,
          hint: 'La pregunta o el concepto',
          autofocus: true,
          maxLines: 3,
          maxLength: ApiService.maxFlashcardChars,
          invalid: frontEmpty,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        const _FieldLabel('Reverso'),
        InkInput(
          controller: _back,
          hint: 'La respuesta',
          maxLines: 4,
          maxLength: ApiService.maxFlashcardChars,
          invalid: backEmpty,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        const _FieldLabel('Dificultad'),
        _NivelPicker(value: _level, onChanged: (v) => setState(() => _level = v)),
        if (frontEmpty || backEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Las dos caras son obligatorias.',
            style: TextStyle(
              color: Color(0xFFC4655A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

/// «Sin nivel» o uno de los cuatro niveles de dificultad.
class _NivelPicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _NivelPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(int? n) {
      final on = value == n;
      final c = n == null ? null : kLevelColor[n];
      return GestureDetector(
        onTap: () => onChanged(n),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? (c?.soft ?? const Color(0xFFF2EFED)) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? (c?.color ?? kInk) : const Color(0xFFE4DCD8), width: 2),
          ),
          child: Text(
            n == null ? 'Sin nivel' : nombreNivel(n),
            style: TextStyle(color: on ? (c?.color ?? kInk) : kMuted, fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return Wrap(spacing: 6, runSpacing: 6, children: [chip(null), for (final n in kFlashLevels) chip(n)]);
  }
}

/// Alta rápida: se queda abierto para ir creando tarjetas seguidas. El tema se
/// mantiene entre una y otra; [onSave] guarda una y devuelve el error (o null).
/// Devuelve cuántas se crearon. Puerto de FlashcardCreateModal de la web.
Future<int> showFlashcardCreator(
  BuildContext context, {
  required String deckName,
  required int initialCount,
  required Future<String?> Function(FlashcardDraft draft) onSave,
  String initialTopic = '',
}) async {
  final n = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _FlashcardCreator(
      deckName: deckName,
      initialCount: initialCount,
      initialTopic: initialTopic,
      onSave: onSave,
    ),
  );
  return n ?? 0;
}

class _FlashcardCreator extends StatefulWidget {
  final String deckName;
  final int initialCount;
  final String initialTopic;
  final Future<String?> Function(FlashcardDraft draft) onSave;

  const _FlashcardCreator({
    required this.deckName,
    required this.initialCount,
    required this.initialTopic,
    required this.onSave,
  });

  @override
  State<_FlashcardCreator> createState() => _FlashcardCreatorState();
}

class _FlashcardCreatorState extends State<_FlashcardCreator> {
  late final _topic = TextEditingController(text: widget.initialTopic);
  final _front = TextEditingController();
  final _back = TextEditingController();
  final _frontFocus = FocusNode();
  int? _level;
  late int _count = widget.initialCount;
  int _creadas = 0;
  bool _saving = false;
  String? _error;

  bool get _lleno => _count >= ApiService.maxFlashcardsPerDeck;

  @override
  void dispose() {
    _topic.dispose();
    _front.dispose();
    _back.dispose();
    _frontFocus.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_saving || _lleno) return;
    final front = _front.text.trim();
    final back = _back.text.trim();
    if (front.isEmpty || back.isEmpty) {
      setState(() => _error = 'Rellena anverso y reverso.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(FlashcardDraft(front, back, topic: _topic.text.trim(), level: _level));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      if (error == null) {
        _count++;
        _creadas++;
        _front.clear();
        _back.clear();
      }
    });
    if (error == null) _frontFocus.requestFocus();
  }

  Future<void> _cerrar() async {
    final pendiente = _front.text.trim().isNotEmpty || _back.text.trim().isNotEmpty;
    if (pendiente) {
      final salir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Salir sin guardar esta tarjeta?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
          ],
        ),
      );
      if (salir != true || !mounted) return;
    }
    Navigator.pop(context, _creadas);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cerrar();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: SingleChildScrollView(
          child: StickerCard(
            depth: 6,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Crear tarjetas', style: TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 18)),
                      Text(
                        '${widget.deckName} · $_count de ${ApiService.maxFlashcardsPerDeck}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 12.5),
                      ),
                    ]),
                  ),
                  if (_creadas > 0) DocChip(label: '$_creadas creadas', icon: Icons.check_rounded, tone: DocTone.accent),
                ]),
                const SizedBox(height: 16),
                const _FieldLabel('Tema (opcional)'),
                InkInput(controller: _topic, hint: 'p. ej. Gota', maxLength: 120),
                const SizedBox(height: 12),
                const _FieldLabel('Anverso'),
                InkInput(
                  controller: _front,
                  focusNode: _frontFocus,
                  hint: 'La pregunta o el concepto',
                  autofocus: true,
                  maxLines: 3,
                  maxLength: ApiService.maxFlashcardChars,
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Reverso'),
                InkInput(
                  controller: _back,
                  hint: 'La respuesta',
                  maxLines: 4,
                  maxLength: ApiService.maxFlashcardChars,
                ),
                const SizedBox(height: 12),
                const _FieldLabel('Dificultad'),
                _NivelPicker(value: _level, onChanged: (v) => setState(() => _level = v)),
                if (_error != null || _lleno) ...[
                  const SizedBox(height: 10),
                  Text(
                    _lleno ? 'Este grupo ya tiene el máximo de ${ApiService.maxFlashcardsPerDeck} tarjetas.' : _error!,
                    style: const TextStyle(color: Color(0xFFC4655A), fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: GhostButton(label: 'Cerrar', expand: true, onPressed: _cerrar)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StickerButton(
                      label: _saving ? 'Guardando…' : 'Guardar y otra',
                      icon: Icons.add_rounded,
                      expand: true,
                      onPressed: _saving || _lleno ? null : _guardar,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          color: kMuted.withOpacity(0.8),
        ),
      ),
    );
  }
}

/// Diálogo con el trazo del sistema, para no caer en el AlertDialog de serie.
class _StickerDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final List<Widget> children;

  const _StickerDialog({
    required this.title,
    required this.icon,
    required this.confirmLabel,
    required this.onConfirm,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        child: StickerCard(
          depth: 6,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    height: 36,
                    width: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kAccent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kInk, width: 2),
                    ),
                    child: Icon(icon, color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: kInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...children,
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Cancelar',
                      expand: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StickerButton(
                      label: confirmLabel,
                      expand: true,
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
