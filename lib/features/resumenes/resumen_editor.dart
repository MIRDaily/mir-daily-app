import 'package:flutter/material.dart';

import '../../core/models/resumen.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import 'resumenes_huecos.dart';
import 'widgets/parrafo_huecos.dart';

/// Resultado del editor: el párrafo (texto + huecos + tema) listo para guardar.
typedef ResultadoEditor = ({String texto, List<Hueco> huecos, String tema});

/// Editar un párrafo: el texto (los huecos se recolocan solos mientras se
/// escribe), los huecos (tocando palabras) y el tema. Lo usan «Escribir un
/// párrafo» y la edición desde la lista del grupo.
class ResumenEditorScreen extends StatefulWidget {
  final String textoInicial;
  final List<Hueco> huecosIniciales;
  final String temaInicial;
  final List<String> temas;

  const ResumenEditorScreen({
    super.key,
    required this.textoInicial,
    required this.huecosIniciales,
    required this.temaInicial,
    this.temas = const [],
  });

  @override
  State<ResumenEditorScreen> createState() => _ResumenEditorScreenState();
}

class _ResumenEditorScreenState extends State<ResumenEditorScreen> {
  late String _texto = widget.textoInicial;
  late List<Hueco> _huecos = List.of(widget.huecosIniciales);
  late final TextEditingController _temaCtrl = TextEditingController(text: widget.temaInicial);
  late final TextEditingController _textoCtrl = TextEditingController(text: widget.textoInicial);
  int _nivel = 2;
  int _perdidos = 0;
  String? _aviso;

  @override
  void dispose() {
    _temaCtrl.dispose();
    _textoCtrl.dispose();
    super.dispose();
  }

  void _cambiarTexto(String nuevo) {
    final r = ajustarTrasEditar(_texto, nuevo, _huecos);
    setState(() {
      _texto = nuevo;
      _huecos = r.huecos;
      if (r.perdidos > 0) _perdidos += r.perdidos;
    });
  }

  String? get _error {
    final largo = _texto.trim().length;
    if (largo < minTextoResumen) return 'El párrafo es demasiado corto (mínimo $minTextoResumen caracteres)';
    if (largo > maxTextoResumen) return 'El párrafo es demasiado largo (máximo $maxTextoResumen)';
    return errorHuecos(_texto, _huecos);
  }

  void _guardar() {
    if (_error != null) return;
    Navigator.pop(context, (texto: _texto, huecos: _huecos, tema: _temaCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final largo = _texto.trim().length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Párrafo', style: TextStyle(color: kInk, fontWeight: FontWeight.w900)),
        actions: [
          TextButton(
            onPressed: _error == null ? _guardar : null,
            child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Tema'),
              TextField(
                controller: _temaCtrl,
                maxLength: maxTemaResumen,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'La enfermedad o el bloque', counterText: '', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Texto'),
              TextField(
                controller: _textoCtrl,
                maxLines: 5,
                minLines: 3,
                maxLength: maxTextoResumen + 200,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _cambiarTexto,
                decoration: const InputDecoration(hintText: 'Escribe el párrafo de repaso', counterText: '', border: OutlineInputBorder()),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text('$largo / $maxTextoResumen', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Huecos · toca una palabra', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w800)),
                  NivelNuevo(nivel: _nivel, onChanged: (n) => setState(() => _nivel = n)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kHairline, width: 2),
                ),
                child: ParrafoHuecos(
                  texto: _texto,
                  huecos: _huecos,
                  editable: true,
                  nivel: _nivel,
                  onChange: (h) => setState(() => _huecos = h),
                  onAviso: (m) => setState(() => _aviso = m),
                ),
              ),
              if (_perdidos > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'Al cambiar el texto se ${_perdidos == 1 ? 'ha perdido 1 hueco' : 'han perdido $_perdidos huecos'}: vuelve a marcarlo si hace falta.',
                  style: const TextStyle(color: Color(0xFF8A6418), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              if (_error != null || _aviso != null) ...[
                const SizedBox(height: 10),
                Text(_error ?? _aviso!, style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
