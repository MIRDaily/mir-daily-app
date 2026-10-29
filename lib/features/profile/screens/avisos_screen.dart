import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/avisos.dart';
import '../../../core/responsive/content_shell.dart';
import '../../../core/services/avisos_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../navigation/pestana_pedida.dart';

const _iconos = <String, IconData>{
  'mail': Icons.mail_rounded,
  'hourglass_bottom': Icons.hourglass_bottom_rounded,
  'fact_check': Icons.fact_check_rounded,
  'notifications': Icons.notifications_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'military_tech': Icons.military_tech_rounded,
  'star': Icons.star_rounded,
  'bolt': Icons.bolt_rounded,
  'check_circle': Icons.check_circle_rounded,
  'info': Icons.info_rounded,
  'campaign': Icons.campaign_rounded,
};

IconData iconoDeAviso(Aviso a) => _iconos[iconoAviso(a)] ?? Icons.notifications_rounded;

/// «Notificaciones» (Perfil → Inbox): los avisos que escribe el servidor, con «Todas» / «No leídas» y
/// «Marcar todo como leído». Puerto de /notifications de la web. El contador lo comparte [Avisos].
class AvisosScreen extends StatefulWidget {
  const AvisosScreen({super.key});

  @override
  State<AvisosScreen> createState() => _AvisosScreenState();
}

class _AvisosScreenState extends State<AvisosScreen> {
  FiltroAvisos _filtro = FiltroAvisos.todos;
  List<Aviso> _avisos = const [];
  bool _cargando = true;
  String? _error;
  int _peticion = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final yo = ++_peticion;
    setState(() {
      _cargando = _avisos.isEmpty;
      _error = null;
    });
    final avisos = context.read<Avisos>();
    try {
      final r = await avisos.api.lista(filtro: _filtro);
      if (!mounted || yo != _peticion) return;
      avisos.poner(r.noLeidas);
      setState(() => _avisos = r.avisos);
    } catch (e) {
      if (mounted && yo == _peticion) {
        setState(() => _error = e is AvisosException ? e.message : 'No se pudieron cargar las notificaciones');
      }
    } finally {
      if (mounted && yo == _peticion) setState(() => _cargando = false);
    }
  }

  void _cambiarFiltro(FiltroAvisos f) {
    if (f == _filtro) return;
    setState(() {
      _filtro = f;
      _avisos = const [];
    });
    _cargar();
  }

  /// Optimista, como la web: se marca ya y se deshace si el servidor falla.
  Future<void> _marcarLeido(Aviso a) async {
    if (!a.unread) return;
    final avisos = context.read<Avisos>();
    setState(() => _avisos = [for (final x in _avisos) x.id == a.id ? x.leido() : x]);
    avisos.restarUno();
    try {
      await avisos.api.marcarLeido(a.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _avisos = [for (final x in _avisos) x.id == a.id ? a : x]);
      avisos.refrescar();
    }
  }

  Future<void> _marcarTodos() async {
    final avisos = context.read<Avisos>();
    final antes = _avisos;
    setState(() => _avisos = [for (final x in _avisos) x.unread ? x.leido() : x]);
    final contador = avisos.noLeidas;
    avisos.poner(0);
    try {
      await avisos.api.marcarTodos(filtro: _filtro);
    } catch (_) {
      if (!mounted) return;
      setState(() => _avisos = antes);
      avisos.poner(contador);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudieron marcar como leídas')));
    }
  }

  Future<void> _abrir(Aviso a) async {
    await _marcarLeido(a);
    if (!mounted) return;
    if (destinoAviso(a.actionUrl) == DestinoAviso.daily) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      pestanaPedida.value = PestanaApp.quiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    final noLeidas = context.watch<Avisos>().noLeidas;
    final enVista = _avisos.where((a) => a.unread).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Notificaciones', style: TextStyle(color: kInk, fontWeight: FontWeight.w900)),
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
                  noLeidas == 0 ? 'Lo tienes todo leído' : '$noLeidas sin leer',
                  style: const TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final f in FiltroAvisos.values)
                      ChoiceChip(
                        label: Text(f == FiltroAvisos.todos ? 'Todas' : 'No leídas'),
                        selected: _filtro == f,
                        onSelected: (_) => _cambiarFiltro(f),
                        showCheckmark: false,
                        selectedColor: kInk,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: _filtro == f ? kInk : kHairline, width: 1.5),
                        labelStyle: TextStyle(
                          color: _filtro == f ? Colors.white : kInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    if (enVista > 0)
                      TextButton(
                        onPressed: _marcarTodos,
                        child: const Text('Marcar todo como leído',
                            style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._cuerpo(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _cuerpo() {
    if (_cargando) {
      return [
        for (var i = 0; i < 3; i++)
          Container(
            height: 64,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(18)),
          ),
      ];
    }
    if (_error != null) {
      return [
        Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 14)),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: GhostButton(label: 'Reintentar', compact: true, onPressed: _cargar)),
      ];
    }
    if (_avisos.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text(
            'No hay notificaciones para este filtro.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted, fontSize: 14),
          ),
        ),
      ];
    }
    return [for (final a in _avisos) _TarjetaAviso(aviso: a, onTap: () => _abrir(a), onLeido: () => _marcarLeido(a))];
  }
}

class _TarjetaAviso extends StatelessWidget {
  final Aviso aviso;
  final VoidCallback onTap;
  final VoidCallback onLeido;

  const _TarjetaAviso({required this.aviso, required this.onTap, required this.onLeido});

  @override
  Widget build(BuildContext context) {
    final a = aviso;
    final metrica = a.metrica;
    return StickerCard(
      depth: a.unread ? 4 : 2,
      radius: 18,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      background: a.unread ? const Color(0xFFFFF7F5) : Colors.white,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: a.unread ? const Color(0xFFFFE9E4) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconoDeAviso(a), size: 20, color: a.unread ? AppColors.error : kMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(a.title,
                        style: TextStyle(color: kInk, fontSize: 14.5, fontWeight: a.unread ? FontWeight.w900 : FontWeight.w700)),
                  ),
                  if (a.unread)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    ),
                ]),
                if (a.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(a.body, style: const TextStyle(color: kMuted, fontSize: 13, height: 1.4)),
                ],
                if (metrica.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(metrica, style: const TextStyle(color: kMuted, fontSize: 12)),
                ],
                const SizedBox(height: 6),
                // Wrap: a 360 px la fecha y «Marcar leída» no caben en una fila.
                Wrap(spacing: 12, runSpacing: 4, children: [
                  Text(horaAviso(a.createdAt), style: const TextStyle(color: AppColors.textLight, fontSize: 11.5)),
                  if (a.unread) ...[
                    GestureDetector(
                      onTap: onLeido,
                      child: const Text('Marcar leída',
                          style: TextStyle(color: AppColors.primaryDark, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Globo coral con el número de no leídas, para colgar de un icono (Perfil en la barra, Inbox).
/// Sin [Avisos] en el árbol (tests de pantallas sueltas) no pinta nada.
class GloboAvisos extends StatelessWidget {
  final Widget child;
  const GloboAvisos({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final texto = textoGlobo(context.watch<Avisos?>()?.noLeidas ?? 0);
    if (texto == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -8,
          child: Semantics(
            label: '$texto notificaciones sin leer',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4.5),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(texto,
                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900, height: 1.1)),
            ),
          ),
        ),
      ],
    );
  }
}
