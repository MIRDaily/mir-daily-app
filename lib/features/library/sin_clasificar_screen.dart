import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/biblioteca.dart';
import '../../core/responsive/content_shell.dart';
import '../../core/services/carpetas.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ia/destino_carpeta.dart' show elegirCarpeta;
import '../../shared/sticker/sticker.dart';
import 'carpeta_biblioteca_screen.dart';
import 'widgets/biblioteca_ui.dart';

/// «Sin clasificar»: lo que no tiene carpeta. Cada elemento tiene «Mover a…» y, si el emparejador ve a
/// qué tema se parece (título, temas de sus tarjetas o párrafos, documento de origen), un atajo de un
/// toque «¿A Reumatología › Lupus?». Mantener pulsado (o la casilla) selecciona varios para moverlos a la
/// vez. NUNCA se mueve nada solo. Puerto de src/app/library/sin-clasificar/page.tsx.
class SinClasificarScreen extends StatefulWidget {
  const SinClasificarScreen({super.key});

  @override
  State<SinClasificarScreen> createState() => _SinClasificarScreenState();
}

String _clave(ElementoMaterial e) => '${e.tipo.valor}:${e.id}';

class _SinClasificarScreenState extends State<SinClasificarScreen> {
  List<AsignaturaCatalogo>? _arbol;
  List<ElementoMaterial>? _elementos;
  Map<String, Carpeta> _sugerencias = const {};
  String? _error;
  final Set<String> _seleccion = {};
  String? _ocupado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final carpetas = context.read<CarpetasApi>();
    setState(() => _error = null);
    try {
      final r = await Future.wait([carpetas.arbol(), carpetas.sinClasificar()]);
      if (!mounted) return;
      final arbol = r[0] as List<AsignaturaCatalogo>;
      final elementos = r[1] as List<ElementoMaterial>;
      setState(() {
        _arbol = arbol;
        _elementos = elementos;
        // La sugerencia se calcula aquí, en el teléfono y sin coste (como la web en el navegador).
        _sugerencias = {
          for (final e in elementos)
            if (sugerenciaDe(arbol, e) case final s?) _clave(e): s,
        };
        _seleccion.removeWhere((k) => !elementos.any((e) => _clave(e) == k));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  void _quitar(Iterable<ElementoMaterial> movidos, Carpeta destino) {
    final fuera = {for (final e in movidos) _clave(e)};
    setState(() {
      _elementos = _elementos?.where((e) => !fuera.contains(_clave(e))).toList();
      _seleccion.removeAll(fuera);
    });
    final n = fuera.length;
    final asig = _arbol?.where((a) => a.id == destino.subjectId).firstOrNull;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${n == 1 ? 'Movido' : '$n movidos'} a ${nombreCarpeta(_arbol, destino, corto: true)}'),
        behavior: SnackBarBehavior.floating,
        action: asig == null
            ? null
            : SnackBarAction(
                label: 'Ver la carpeta',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CarpetaBibliotecaScreen(asignatura: asig, topicId: destino.topicId),
                )),
              ),
      ));
  }

  /// Mueve una selección (de uno o de varios tipos: el servidor mueve un tipo cada vez).
  Future<void> _moverA(List<ElementoMaterial> elegidos, Carpeta destino, {String origen = 'usuario'}) async {
    final carpetas = context.read<CarpetasApi>();
    final hechos = <ElementoMaterial>[];
    try {
      for (final MapEntry(key: tipo, value: ids) in agruparPorTipo(elegidos).entries) {
        await carpetas.mover(tipo.valor, ids, destino, origen: origen);
        hechos.addAll(elegidos.where((e) => e.tipo == tipo));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && hechos.isNotEmpty) _quitar(hechos, destino);
    }
  }

  Future<void> _elegirYMover(List<ElementoMaterial> elegidos) async {
    final arbol = _arbol;
    if (arbol == null || elegidos.isEmpty) return;
    // Si todos comparten sugerencia, se ofrece como atajo en el selector.
    final ss = elegidos.map((e) => _sugerencias[_clave(e)]).toList();
    final comun = ss.every((s) => s != null && s == ss.first) ? ss.first : null;
    final destino = await elegirCarpeta(context, arbol: arbol, valor: Carpeta.sinClasificar, sugerida: comun);
    if (destino == null || destino.subjectId == null || !mounted) return;
    await _moverA(elegidos, destino, origen: destino == comun ? 'sugerencia' : 'usuario');
  }

  Future<void> _aceptarSugerencia(ElementoMaterial e, Carpeta c) async {
    setState(() {
      _ocupado = _clave(e);
      _error = null;
    });
    await _moverA([e], c, origen: 'sugerencia');
    if (mounted) setState(() => _ocupado = null);
  }

  void _alternar(ElementoMaterial e) => setState(() {
        final k = _clave(e);
        if (!_seleccion.remove(k)) _seleccion.add(k);
      });

  @override
  Widget build(BuildContext context) {
    final lista = _elementos ?? const <ElementoMaterial>[];
    final elegidos = lista.where((e) => _seleccion.contains(_clave(e))).toList();
    final todas = lista.isNotEmpty && elegidos.length == lista.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Sin clasificar', style: TextStyle(color: kInk, fontWeight: FontWeight.w900)),
      ),
      bottomNavigationBar: elegidos.isEmpty
          ? null
          : SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kInk, width: 2),
                  boxShadow: inkShadow(4),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text('${elegidos.length} ${elegidos.length == 1 ? 'seleccionado' : 'seleccionados'}',
                        style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
                  ),
                  TextButton(onPressed: () => setState(_seleccion.clear), child: const Text('Quitar')),
                  StickerButton(
                    label: 'Mover a…',
                    icon: Icons.drive_file_move_outline,
                    compact: true,
                    onPressed: _arbol == null ? null : () => _elegirYMover(elegidos),
                  ),
                ]),
              ),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _cargar,
          child: BodyConstraint(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                Text(
                  _elementos == null
                      ? 'Buscando lo que no tiene carpeta…'
                      : lista.isNotEmpty
                          ? '${textoCuenta(cuentaDe(lista))}. Muévelos a su asignatura o tema: allí se ven junto a sus preguntas MIR.'
                          : 'Nada por ordenar: todo tu material está en su carpeta.',
                  style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                  ),
                if (_elementos == null && _error == null) const EstadoBiblioteca('Cargando…'),
                if (lista.isNotEmpty) ...[
                  // Toda la fila marca o desmarca, no solo la casilla.
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      if (todas) {
                        _seleccion.clear();
                      } else {
                        _seleccion.addAll(lista.map(_clave));
                      }
                    }),
                    child: Row(children: [
                    Checkbox(
                      value: todas ? true : (elegidos.isEmpty ? false : null),
                      tristate: true,
                      activeColor: kInk,
                      onChanged: (_) => setState(() {
                        if (todas) {
                          _seleccion.clear();
                        } else {
                          _seleccion.addAll(lista.map(_clave));
                        }
                      }),
                    ),
                    Expanded(
                      child: Text(
                        elegidos.isEmpty ? 'Seleccionar todo' : '${elegidos.length} ${elegidos.length == 1 ? 'seleccionado' : 'seleccionados'}',
                        style: const TextStyle(color: kInk, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ]),
                  ),
                  const SizedBox(height: 4),
                  SectionLabel('${lista.length} sin carpeta'),
                  for (final e in lista) _fila(e),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fila(ElementoMaterial e) {
    final k = _clave(e);
    final s = _sugerencias[k];
    return GestureDetector(
      onLongPress: () => _alternar(e),
      child: FilaElemento(
        e: e,
        inicio: Checkbox(
          value: _seleccion.contains(k),
          activeColor: kInk,
          visualDensity: VisualDensity.compact,
          onChanged: (_) => _alternar(e),
        ),
        extra: s == null || _arbol == null
            ? null
            : Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _ocupado != null ? null : () => _aceptarSugerencia(e, s),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(
                    _ocupado == k ? 'Moviendo…' : '¿A ${nombreCarpeta(_arbol, s, corto: true)}?',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    backgroundColor: const Color(0xFFFFF4EF),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
        acciones: [
          TextButton.icon(
            onPressed: () => _elegirYMover([e]),
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('Mover a…'),
            style: TextButton.styleFrom(foregroundColor: kMuted, visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }
}
