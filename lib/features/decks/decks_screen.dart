import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/responsive/adaptive_grid.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/responsive/content_shell.dart';
import '../../core/responsive/master_detail_scaffold.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';
import 'deck_detail_screen.dart';
import 'deck_trash_screen.dart';
import 'widgets/construction_deck.dart';
import 'widgets/deck_gradient.dart';
import 'widgets/deck_sort.dart';

/// Sección Mazos — conectada al backend (/api/studio/decks): lista con estado
/// visual, crear mazo, eliminar (papelera 24h) y abrir el detalle para estudiar.
class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Deck>? _decks;
  String? _error;
  bool _loading = true;

  /// Criterio de orden de la galería. Vive en el dispositivo, no en el
  /// servidor: es una preferencia de cómo mirar la lista, y la web tiene su
  /// propio orden manual guardado en `decks.position` que este no pisa.
  DeckSort _sort = DeckSort.manual;
  static const String _sortPrefKey = 'deck_gallery_sort';

  /// La cascada de entrada ya se ha jugado: a partir de aquí ninguna tarjeta
  /// vuelve a animarse. Ver [_entrance].
  bool _entranceDone = false;
  Timer? _entranceTimer;

  /// Estilo elegido mientras el guardado viaja al servidor, para pintarlo al
  /// instante. Cuando el perfil vuelve refrescado se descarta y manda el
  /// valor real. Null = no hay nada pendiente.
  String? _pendingGalleryStyle;
  bool _savingGalleryStyle = false;

  /// Mazo abierto en el panel derecho, en maestro-detalle (tablet grande).
  /// Fuera de ese modo no se usa: se navega con `Navigator.push` como
  /// siempre.
  Deck? _selectedDeck;

  /// La lista de la izquierda está plegada (detalle a pantalla completa).
  bool _masterCollapsed = false;

  @override
  void initState() {
    super.initState();
    _restoreSort();
    _load();
  }

  Future<void> _restoreSort() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = deckSortFromId(prefs.getString(_sortPrefKey));
    if (saved != _sort) setState(() => _sort = saved);
  }

  Future<void> _applySort(DeckSort sort) async {
    setState(() => _sort = sort);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefKey, sort.id);
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _decks == null;
        _error = null;
      });
    }
    try {
      final decks = await context.read<ApiService>().getDecks();
      if (!mounted) return;
      setState(() {
        _decks = decks;
        _loading = false;
      });
      _armEntrance();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus mazos. Desliza para reintentar.';
        _loading = false;
      });
    }
  }

  Future<void> _createDeck() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nuevo mazo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Nombre del mazo (mín. 3 letras)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (name == null || name.length < 3) {
      if (name != null && name.isNotEmpty) {
        _toast('El nombre debe tener al menos 3 letras.');
      }
      return;
    }

    try {
      await context.read<ApiService>().createDeck(name);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo crear el mazo.');
    }
  }

  Future<void> _deleteDeck(Deck deck) async {
    final api = context.read<ApiService>();
    // Optimista: lo quitamos de la lista y ofrecemos deshacer. Si era el
    // abierto en el panel derecho, se cierra: seguir mostrando un mazo
    // borrado no tiene sentido.
    setState(() {
      _decks?.removeWhere((d) => d.id == deck.id);
      if (_selectedDeck?.id == deck.id) _selectedDeck = null;
    });
    try {
      await api.deleteDeck(deck.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${deck.name}" eliminado'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
          action: SnackBarAction(
            label: 'Deshacer',
            textColor: AppColors.primary,
            onPressed: () async {
              try {
                await api.restoreDeck(deck.id);
              } catch (_) {}
              _load();
            },
          ),
        ),
      );
    } catch (_) {
      _toast('No se pudo eliminar el mazo.');
      _load();
    }
  }

  /// Preferencia GLOBAL del usuario (`users.deck_gallery_style`), no por
  /// mazo — la misma que la web. Se lee del perfil que ya carga AuthProvider,
  /// así que activar el ajuste no añade ninguna petición de red.
  String _galleryStyleOf(AuthProvider auth) =>
      _pendingGalleryStyle ?? auth.profile?.deckGalleryStyle ?? 'default';

  Future<void> _openGallerySettings() async {
    // Los providers se leen ANTES del await del panel: despues de un gap
    // asincrono el context puede haber quedado fuera del arbol.
    final auth = context.read<AuthProvider>();
    final api = context.read<ApiService>();
    final current = _galleryStyleOf(auth);

    // El panel devuelve UNA elección: o un orden nuevo o una textura nueva.
    // Se cierra al tocar, que es lo que se espera de una lista de opciones.
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Text(
                  'Ajustes de la galería',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    color: kInk,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: SectionLabel('Orden'),
              ),
              for (final sort in DeckSort.values)
                _GalleryStyleOption(
                  title: sort.label,
                  subtitle: sort.hint,
                  selected: _sort == sort,
                  preview: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kHairline, width: 2),
                    ),
                    child: Icon(sort.icon, size: 17, color: kMuted),
                  ),
                  onTap: () => Navigator.pop(ctx, sort),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: SectionLabel('Textura'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Solo afecta a tus mazos. El de fallos conserva el suyo.',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              _GalleryStyleOption(
                title: 'Predeterminado',
                subtitle: 'La cartulina teñida con el estado del mazo.',
                selected: current == 'default',
                preview: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kInk, width: 2),
                  ),
                  child: const Icon(Icons.style_rounded,
                      size: 18, color: AppColors.success),
                ),
                onTap: () => Navigator.pop(ctx, 'default'),
              ),
              _GalleryStyleOption(
                title: 'Personalizado',
                subtitle: 'El degradado que cada mazo tiene en su portada.',
                selected: current == 'gradient',
                preview: const DeckGradientSwatch(id: 'blueNight', size: 34),
                onTap: () => Navigator.pop(ctx, 'gradient'),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );

    if (chosen == null || !mounted) return;

    // El orden es local e instantáneo: no hay nada que pedirle al servidor.
    if (chosen is DeckSort) {
      if (chosen != _sort) await _applySort(chosen);
      return;
    }

    final style = chosen as String;
    if (style == current || _savingGalleryStyle) return;

    setState(() {
      _pendingGalleryStyle = style;
      _savingGalleryStyle = true;
    });

    try {
      await api.updateAcademicProfile(galleryStyle: style);
      await auth.refreshProfile();
      if (!mounted) return;
      setState(() {
        _pendingGalleryStyle = null;
        _savingGalleryStyle = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingGalleryStyle = null;
        _savingGalleryStyle = false;
      });
      _toast('No se pudo guardar el ajuste.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // `watch`: si el perfil llega o cambia (otro dispositivo, recarga), la
    // galería se repinta sola con la textura correcta.
    final galleryStyle = _galleryStyleOf(context.watch<AuthProvider>());
    final twoPane = context.usesTwoPane;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      // En dos paneles, "Nuevo mazo" vive en la cabecera de la lista (el FAB
      // chocaría con el de "Estudiar" del detalle y con la barra flotante).
      floatingActionButton: twoPane
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: StickerButton(
                label: 'Nuevo mazo',
                icon: Icons.add_rounded,
                onPressed: _createDeck,
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: twoPane
            ? MasterDetailScaffold(
                masterTitle: 'Mazos',
                masterCollapsed: _masterCollapsed,
                onToggleMaster: () =>
                    setState(() => _masterCollapsed = !_masterCollapsed),
                masterActions: [
                  IconButton(
                    tooltip: 'Nuevo mazo',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_rounded),
                    color: AppColors.primaryDark,
                    onPressed: _createDeck,
                  ),
                ],
                master: _gallery(context, galleryStyle),
                detail: _selectedDeck == null
                    ? const MasterDetailEmpty(
                        icon: Icons.style_rounded,
                        title: 'Elige un mazo',
                        subtitle:
                            'Selecciónalo en la lista para ver su contenido.',
                      )
                    : DeckDetailScreen(
                        key: ValueKey(_selectedDeck!.id),
                        deck: _selectedDeck!,
                        onClose: () => setState(() {
                          if (_masterCollapsed) {
                            _masterCollapsed = false;
                          } else {
                            _selectedDeck = null;
                          }
                        }),
                      ),
              )
            : BodyConstraint(wide: true, child: _gallery(context, galleryStyle)),
      ),
    );
  }

  /// Galería: hero + secciones de mazos. Es el maestro en maestro-detalle (a
  /// ancho fijo) y el cuerpo entero fuera de ese modo (acotado por
  /// `BodyConstraint` en el llamador) — el propio contenido no sabe en cuál
  /// de los dos casos está.
  Widget _gallery(BuildContext context, String galleryStyle) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: CustomScrollView(
        physics:
            const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
              child: StickerHero(
                badge: 'Dominio',
                badgeIcon: Icons.layers_rounded,
                title: 'Tus Mazos',
                subtitle:
                    'Repaso con repetición espaciada para fijar lo que fallas.',
                aside: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Ajustes',
                      onTap: _openGallerySettings,
                    ),
                    const SizedBox(width: 10),
                    InkIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Papelera',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const DeckTrashScreen()),
                        );
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          ..._content(context, galleryStyle),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, String galleryStyle) {
    // En tablet las tarjetas van en rejilla; en móvil, lista perezosa como
    // siempre (el `SliverList` no monta las que no se ven).
    final grid = context.isWide;

    if (_loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => const _DeckSkeleton(),
              childCount: 4,
            ),
          ),
        ),
      ];
    }

    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
            child: Column(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: AppColors.textLight, size: 44),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final todos = _decks ?? const <Deck>[];

    // Dos grupos, como en la web: arriba lo que pone MIRDaily (hoy solo el
    // mazo de fallos; en el futuro también el rotatorio), abajo lo que ha
    // hecho el usuario. No es solo estética: los del sistema no se borran, no
    // se reordenan y no siguen el ajuste de textura, así que mezclarlos hacía
    // que la tarjeta de al lado se comportara distinto sin explicar por qué.
    final sistema = todos.where((d) => d.isSystemDeck).toList();
    final propios = sortDecks(
      todos.where((d) => !d.isSystemDeck).toList(),
      _sort,
    );

    // Mismo criterio que la web: si el único mazo del sistema es el de
    // fallos, se reserva el hueco del siguiente con la tarjeta precintada.
    final reservarHueco = sistema.any((d) => d.isAutoManaged) &&
        sistema.length < 2;

    // Índice continuo entre los dos grupos, para que la cascada de entrada no
    // se reinicie al cambiar de sección.
    var orden = 0;

    Widget tarjeta(Deck deck) => _entrance(
          orden++,
          DeckGalleryCard(
            deck: deck,
            // Los mazos del sistema conservan siempre su textura original: el
            // ajuste es solo para los mazos propios del usuario.
            gradientStyle: galleryStyle == 'gradient' && !deck.isSystemDeck,
            onOpen: () => _openDeck(deck),
            onDelete:
                deck.isSystemDeck ? null : () => _confirmDelete(deck),
          ),
        );

    return [
      if (sistema.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('De MIRDaily'),
                AdaptiveGrid(
                  targetItemWidth: 360,
                  maxColumns: 3,
                  // Las tarjetas ya traen su propio margen inferior (14).
                  runSpacing: 0,
                  children: [
                    ...sistema.map(tarjeta),
                    if (reservarHueco) const ConstructionDeckCard(),
                  ],
                ),
              ],
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        sliver: SliverToBoxAdapter(
          child: SectionLabel(
            'Mis mazos${propios.isEmpty ? '' : ' (${propios.length})'}',
          ),
        ),
      ),
      if (propios.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 14, 32, 0),
            child: Column(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: kInk, width: 2),
                    boxShadow: inkShadow(4),
                  ),
                  child: const Icon(Icons.style_rounded,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Aún no tienes mazos propios',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: kInk,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Crea el primero con el botón “Nuevo mazo”, o guarda una pregunta desde la revisión del daily o de un simulacro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        )
      else if (grid)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: AdaptiveGrid(
              targetItemWidth: 360,
              maxColumns: 3,
              runSpacing: 0,
              children: [for (final d in propios) tarjeta(d)],
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => tarjeta(propios[i]),
              childCount: propios.length,
            ),
          ),
        ),
    ];
  }

  /// TODAS las tarjetas se animan al aparecer — la lista construye cada una
  /// la primera vez que asoma, así que el fundido acompaña al scroll.
  ///
  /// Lo único que cambia con el tiempo es el RETARDO, no si hay animación:
  ///
  /// - Al abrir la galería, las tarjetas entran escalonadas (70 ms de
  ///   diferencia entre una y la siguiente): es la cascada de bienvenida.
  /// - Pasada esa ventana, cada tarjeta se funde en cuanto asoma, sin esperar
  ///   su turno. Mantener el escalonado aquí era justo lo que se veía raro:
  ///   una tarjeta con índice alto entraba en pantalla y se quedaba medio
  ///   segundo invisible antes de aparecer.
  ///
  /// Se intentó antes limitar la animación a las N primeras tarjetas, pero eso
  /// dejaba una costura: las de arriba parpadeaban al pasar y las de abajo no
  /// se movían nunca. El coste que se buscaba evitar estaba en realidad en el
  /// desenfoque sin cachear y en la barra de Dominio animada, las dos cosas ya
  /// corregidas; el fundido nunca llegó a quedar señalado por las mediciones.
  static const Duration _entranceWindow = Duration(milliseconds: 1100);

  /// Tope del escalonado de bienvenida: pasada media docena de tarjetas, más
  /// retardo solo sería hacer esperar.
  static const int _entranceMaxStep = 7;

  void _armEntrance() {
    if (_entranceDone || _entranceTimer != null) return;
    _entranceTimer = Timer(_entranceWindow, () {
      if (mounted) setState(() => _entranceDone = true);
    });
  }

  Widget _entrance(int index, Widget card) {
    return SlideFadeIn(
      delay: _entranceDone
          ? Duration.zero
          : Duration(milliseconds: 70 * index.clamp(0, _entranceMaxStep)),
      beginOffset: const Offset(0, 0.12),
      child: card,
    );
  }

  Future<void> _openDeck(Deck deck) async {
    // Maestro-detalle: se abre en el panel derecho, sin navegar.
    if (context.usesTwoPane) {
      setState(() => _selectedDeck = deck);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeckDetailScreen(deck: deck)),
    );
    _load();
  }

  Future<void> _confirmDelete(Deck deck) async {
    HapticFeedback.lightImpact();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error),
                title: Text('Eliminar "${deck.name}"'),
                subtitle: const Text('Podrás recuperarlo 24 h desde la papelera.'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) _deleteDeck(deck);
  }
}

/// Una opción del ajuste de textura de la galería.
class _GalleryStyleOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final Widget preview;
  final VoidCallback onTap;

  const _GalleryStyleOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: preview,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          color: kInk,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primaryDark)
          : null,
    );
  }
}

/// Color de la barra de Dominio, con los mismos cortes que la web
/// (rojo < 40 % < naranja < 70 % < amarillo < 85 % < verde).
Color _domainColor(int percent) {
  if (percent < 40) return const Color(0xFFF87171);
  if (percent < 70) return const Color(0xFFFB923C);
  if (percent < 85) return const Color(0xFFFACC15);
  return const Color(0xFF10B981);
}

/// Pastilla blanca con borde de tinta: se lee igual sobre la cartulina teñida
/// y sobre el degradado, que es lo que permite que las dos texturas compartan
/// exactamente el mismo contenido de tarjeta.
class _CardPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? accent;

  const _CardPill({required this.label, this.icon, this.accent});


  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kInk, width: 1.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          // Flexible + ellipsis: con un estado largo ("NECESITA REPASO") más
          // el contador y la papelera, la fila se salía de la tarjeta por la
          // derecha en pantallas estrechas. Ahora la etiqueta cede primero.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 9.5,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DeckGalleryCard extends StatelessWidget {
  final Deck deck;

  /// True cuando este mazo debe pintarse con su degradado en vez de con la
  /// cartulina teñida. Lo decide la pantalla, no la tarjeta: los mazos del
  /// sistema no siguen el ajuste.
  final bool gradientStyle;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const DeckGalleryCard({
    super.key,
    required this.deck,
    required this.gradientStyle,
    required this.onOpen,
    required this.onDelete,
  });

  ({Color accent, Color bg, IconData icon, String label}) get _style {
    switch (deck.visualState) {
      case 'failed':
        return (
          accent: const Color(0xFFC4655A),
          bg: const Color(0xFFFDF1EF),
          icon: Icons.local_fire_department_rounded,
          label: 'MAZO DE FALLOS',
        );
      case 'perfect':
        return (
          accent: const Color(0xFFC9A227),
          bg: const Color(0xFFFFFBEF),
          icon: Icons.workspace_premium_rounded,
          label: 'PERFECTO',
        );
      case 'destroyed':
        return (
          accent: const Color(0xFFB3543F),
          bg: const Color(0xFFFBF3F0),
          icon: Icons.healing_rounded,
          label: 'NECESITA REPASO',
        );
      default:
        return (
          accent: AppColors.success,
          bg: Colors.white,
          icon: Icons.style_rounded,
          label: 'EN FORMA',
        );
    }
  }

  void _explainMastery(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'El dominio se estima con tus últimas 25 respuestas en este mazo. '
            'Responde al menos 25 preguntas para calcularlo.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
          duration: Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final mastery = deck.masteryPercent;
    // La bio del mazo (o el aviso fijo del automático de fallos) en vez de una
    // etiqueta que salía igual en todos los mazos propios.
    final subtitle = deck.isAutoManaged
        ? 'Tus fallos recientes, listos para repasar.'
        : deck.description;

    return Pressable(
      onTap: onOpen,
      pressedScale: 0.97,
      child: StickerCard(
        margin: const EdgeInsets.only(bottom: 14),
        depth: 4,
        radius: 20,
        background: gradientStyle ? Colors.white : style.bg,
        padding: const EdgeInsets.fromLTRB(15, 13, 12, 15),
        // Predeterminado: cartulina teñida con el estado del mazo, la trama
        // dice de un vistazo si está en forma o si pide repaso.
        // Personalizado: el mismo degradado de su portada, congelado (ver
        // DeckBannerGradient) — mismo aspecto, sin nada animándose por cada
        // tarjeta de la lista.
        texture: gradientStyle
            ? deckGradientTexture(deck.bannerGradient)
            : tintedPaper(style.accent, step: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Expanded, no Spacer: así el hueco sobrante se lo queda la
                // etiqueta de estado y, cuando no cabe, se recorta ella en vez
                // de empujar al contador fuera de la tarjeta.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _CardPill(
                      label: style.label,
                      icon: style.icon,
                      accent: style.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _CardPill(
                  label: '${deck.totalItems}',
                  icon: Icons.style_rounded,
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 6),
                  // Fondo blanco: en modo Personalizado esta esquina cae sobre
                  // la banda oscura del degradado, y un icono suelto ahi se
                  // pierde.
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: kInk, width: 1.6),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.error, size: 16),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              deck.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kInk,
                fontWeight: FontWeight.w900,
                fontSize: 17,
                height: 1.2,
              ),
            ),
            // El hueco de la bio va SIEMPRE reservado (2 líneas), tenga o no
            // tenga texto el mazo: si no, un mazo sin bio dejaba la barra de
            // Dominio pegada al título mientras que uno con bio la empujaba
            // más abajo — la misma pieza en un sitio distinto según el mazo.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // El mazo de fallos no tiene Dominio: su contenido cambia solo con
            // cada acierto o fallo, así que un % de largo plazo no significa
            // nada ahí (mismo criterio que en su propia pantalla).
            if (!deck.isAutoManaged) ...[
              const SizedBox(height: 8),
              // El % va pegado a su etiqueta, a la izquierda, y no en el
              // extremo derecho como en la web: en una tarjeta de móvil ese
              // borde cae justo sobre la banda oscura del degradado, y el
              // dato se perdía en el modo Personalizado.
              Row(
                children: [
                  const Text(
                    'Dominio',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 7),
                  if (mastery == null)
                    GestureDetector(
                      onTap: () => _explainMastery(context),
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: kHairline, width: 1.6),
                        ),
                        child: const Text(
                          '?',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      '$mastery%',
                      style: const TextStyle(
                        color: kInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 6),
              // Sin animación de llenado a propósito: la barra se pintaba
              // con un `TweenAnimationBuilder` de 700 ms que arrancaba cada
              // vez que la tarjeta se construía —o sea, cada vez que asomaba
              // al hacer scroll—, ensuciando la tarjeta entera durante 42
              // fotogramas. El dato es fijo; no gana nada por llegar rodando.
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 8,
                  color: const Color(0xFFEFEAE7),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: ((mastery ?? 0) / 100).clamp(0.0, 1.0),
                      child: Container(color: _domainColor(mastery ?? 0)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeckSkeleton extends StatefulWidget {
  const _DeckSkeleton();

  @override
  State<_DeckSkeleton> createState() => _DeckSkeletonState();
}

class _DeckSkeletonState extends State<_DeckSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_shimmer),
      child: Container(
        height: 94,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(4),
        ),
      ),
    );
  }
}
