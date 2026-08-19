import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../shared/sticker/sticker.dart';

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

  const FlashcardDraft(this.front, this.back);
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

/// Alta o edición de una tarjeta (anverso y reverso).
Future<FlashcardDraft?> showFlashcardDialog(
  BuildContext context, {
  String initialFront = '',
  String initialBack = '',
}) {
  final editing = initialFront.isNotEmpty || initialBack.isNotEmpty;
  return showDialog<FlashcardDraft>(
    context: context,
    builder: (ctx) => _FlashcardDialog(
      editing: editing,
      initialFront: initialFront,
      initialBack: initialBack,
    ),
  );
}

class _FlashcardDialog extends StatefulWidget {
  final bool editing;
  final String initialFront;
  final String initialBack;

  const _FlashcardDialog({
    required this.editing,
    required this.initialFront,
    required this.initialBack,
  });

  @override
  State<_FlashcardDialog> createState() => _FlashcardDialogState();
}

class _FlashcardDialogState extends State<_FlashcardDialog> {
  late final _front = TextEditingController(text: widget.initialFront);
  late final _back = TextEditingController(text: widget.initialBack);
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
    Navigator.pop(context, FlashcardDraft(front, back));
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
