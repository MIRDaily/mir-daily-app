import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/sticker/sticker.dart';

/// Qué se enseña en el carné.
///
/// Es una preferencia de **presentación**, no un dato del perfil: no viaja al
/// servidor ni la ve nadie más, así que vive en el propio teléfono. El backend
/// tampoco tiene dónde guardarla.
enum CardField { estatus, especialidad, universidad, bio, codigo }

extension CardFieldInfo on CardField {
  String get label => switch (this) {
        CardField.estatus => 'Estatus',
        CardField.especialidad => 'Especialidad',
        CardField.universidad => 'Universidad',
        CardField.bio => 'Sobre ti',
        CardField.codigo => 'Código de barras',
      };

  String get detalle => switch (this) {
        CardField.estatus => 'Estudiante de 3º, Médico/a…',
        CardField.especialidad => 'La que te atrae',
        CardField.universidad => 'Dónde estudias',
        CardField.bio => 'Tu presentación',
        CardField.codigo => 'Las barras del pie',
      };

  IconData get icon => switch (this) {
        CardField.estatus => Icons.school_rounded,
        CardField.especialidad => Icons.medical_services_rounded,
        CardField.universidad => Icons.account_balance_rounded,
        CardField.bio => Icons.format_quote_rounded,
        CardField.codigo => Icons.qr_code_2_rounded,
      };
}

/// Guarda y recupera la elección. Por defecto se enseña todo: quien no quiera
/// tocarlo ve el carné completo.
class CardFieldPrefs {
  CardFieldPrefs._();

  static const _key = 'perfil_carne_campos';

  static Set<CardField> get todos => CardField.values.toSet();

  static Future<Set<CardField>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getStringList(_key);
    if (guardado == null) return todos;
    return CardField.values.where((f) => guardado.contains(f.name)).toSet();
  }

  static Future<void> save(Set<CardField> campos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, campos.map((f) => f.name).toList());
  }
}

/// Hoja para elegir qué aparece en el carné.
Future<Set<CardField>?> showCardFieldPicker(
  BuildContext context,
  Set<CardField> actuales,
) {
  return showModalBottomSheet<Set<CardField>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CardFieldSheet(iniciales: actuales),
  );
}

class _CardFieldSheet extends StatefulWidget {
  final Set<CardField> iniciales;

  const _CardFieldSheet({required this.iniciales});

  @override
  State<_CardFieldSheet> createState() => _CardFieldSheetState();
}

class _CardFieldSheetState extends State<_CardFieldSheet> {
  late final Set<CardField> _sel = {...widget.iniciales};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: StickerCard(
        depth: 6,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Qué se ve en tu carné',
                    style: TextStyle(
                      color: kInk,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                ),
                InkIconButton(
                  icon: Icons.close_rounded,
                  size: 38,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final campo in CardField.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(campo.icon, size: 18, color: kMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            campo.label,
                            style: const TextStyle(
                              color: kInk,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            campo.detalle,
                            style: const TextStyle(
                              color: kMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkSwitch(
                      value: _sel.contains(campo),
                      onChanged: (v) => setState(
                        () => v ? _sel.add(campo) : _sel.remove(campo),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            StickerButton(
              label: 'Listo',
              icon: Icons.check_rounded,
              expand: true,
              onPressed: () => Navigator.pop(context, _sel),
            ),
          ],
        ),
      ),
    );
  }
}
