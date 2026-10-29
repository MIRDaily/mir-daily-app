import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/flashcards.dart';
import '../../core/models/models.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/responsive/content_shell.dart';
import '../../core/responsive/master_detail_scaffold.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'flashcard_deck_screen.dart';
import 'widgets/flashcard_dialogs.dart';
import 'widgets/flashcards_ui.dart';
import 'widgets/progress_panel.dart';

/// Flashcards personalizadas: los grupos («asignaturas») de tarjetas del usuario.
///
/// Van en lista tipo Anki, por categoría (Básicas, Médicas, Quirúrgicas, Otros) y con tres
/// columnas siempre en el mismo sitio: nuevas, falladas y repasos. Encima, la previsión de los
/// próximos 30 días y el estado de las tarjetas. Son mazos con `kind='flashcards'` en el backend,
/// con endpoints propios, y **no cuentan para las estadísticas globales**.
/// Puerto del nivel raíz de src/app/flashcards/page.tsx.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

/// Preferencias de la lista (orden y secciones plegadas): si se pliega una categoría, se espera
/// encontrarla plegada al volver.
const _prefsKey = 'mirdaily.flashcards.listPrefs';

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  List<FlashDeck>? _decks;
  String? _error;
  bool _loading = true;
  FlashForecast? _forecast;
  FlashStats? _stats;

  final _query = TextEditingController();
  OrdenAsignaturas _orden = OrdenAsignaturas.pendientes;
  final Set<CategoriaAsignatura> _plegadas = {};

  /// Grupo abierto en el panel derecho, en maestro-detalle (tablet grande).
  FlashDeck? _selectedDeck;

  /// La lista de la izquierda está plegada (detalle a pantalla completa).
  bool _masterCollapsed = false;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _leerPrefs();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _leerPrefs() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      setState(() {
        _orden = OrdenAsignaturas.values.firstWhere((o) => o.name == j['orden'], orElse: () => _orden);
        _plegadas
          ..clear()
          ..addAll(CategoriaAsignatura.values.where((c) => (j['plegadas'] is List) && (j['plegadas'] as List).contains(c.name)));
      });
    } catch (_) {
      // Unas preferencias viejas no deben tumbar la pantalla.
    }
  }

  Future<void> _guardarPrefs() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _prefsKey,
        jsonEncode({'orden': _orden.name, 'plegadas': _plegadas.map((c) => c.name).toList()}),
      );
    } catch (_) {}
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _decks == null;
        _error = null;
      });
    }
    // El panel es informativo: si falla, la pantalla sigue siendo usable.
    _api.getFlashcardForecast().then((f) {
      if (mounted) setState(() => _forecast = f);
    }).catchError((_) {});
    _api.getFlashcardStats().then((s) {
      if (mounted) setState(() => _stats = s);
    }).catchError((_) {});
    try {
      final decks = await _api.getFlashDecks();
      if (!mounted) return;
      setState(() {
        _decks = decks;
        _loading = false;
        if (_selectedDeck != null) {
          _selectedDeck = decks.where((d) => d.id == _selectedDeck!.id).firstOrNull;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'No se pudieron cargar tus grupos. Desliza para reintentar.';
        _loading = false;
      });
    }
  }

  Future<void> _createDeck() async {
    final data = await showFlashDeckDialog(context);
    if (data == null) return;
    try {
      await _api.createFlashDeck(data.name, description: data.description);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo crear el grupo.');
    }
  }

  Future<void> _renameDeck(FlashDeck deck) async {
    final data = await showFlashDeckDialog(
      context,
      initialName: deck.name,
      initialDescription: deck.description ?? '',
    );
    if (data == null) return;
    try {
      await _api.updateFlashDeck(deck.id, name: data.name, description: data.description);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('No se pudo actualizar el grupo.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: kInk),
    );
  }

  Future<void> _open(FlashDeck deck, {bool estudiar = false}) async {
    if (context.usesTwoPane && !estudiar) {
      setState(() => _selectedDeck = deck);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FlashcardDeckScreen(deck: deck, autoStudy: estudiar, onChanged: _load)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final decks = _decks ?? const <FlashDeck>[];
    final twoPane = context.usesTwoPane;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: twoPane
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
      floatingActionButton: twoPane
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: StickerButton(
                label: 'Nueva asignatura',
                icon: Icons.add_rounded,
                onPressed: _createDeck,
              ),
            ),
      body: SafeArea(
        top: false,
        child: twoPane
            ? MasterDetailScaffold(
                masterTitle: 'Flashcards',
                onBack: () => Navigator.of(context).maybePop(),
                masterCollapsed: _masterCollapsed,
                onToggleMaster: () => setState(() => _masterCollapsed = !_masterCollapsed),
                masterActions: [
                  IconButton(
                    tooltip: 'Nueva asignatura',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_rounded),
                    color: AppColors.primaryDark,
                    onPressed: _createDeck,
                  ),
                ],
                master: _gallery(decks),
                detail: _selectedDeck == null
                    ? const MasterDetailEmpty(
                        icon: Icons.style_rounded,
                        title: 'Elige un grupo',
                        subtitle: 'Selecciónalo en la lista para ver sus tarjetas.',
                      )
                    : FlashcardDeckScreen(
                        key: ValueKey(_selectedDeck!.id),
                        deck: _selectedDeck!,
                        onChanged: _load,
                        onClose: () => setState(() {
                          if (_masterCollapsed) {
                            _masterCollapsed = false;
                          } else {
                            _selectedDeck = null;
                          }
                        }),
                      ),
              )
            : BodyConstraint(child: _gallery(decks)),
      ),
    );
  }

  Widget _gallery(List<FlashDeck> decks) {
    final total = decks.fold<int>(0, (a, d) => a + d.totalCards);
    final due = decks.fold<int>(0, (a, d) => a + d.dueCards);
    final secciones = agruparAsignaturas(decks, _query.text, _orden);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 100),
        children: [
          StickerHero(
            badge: 'Repaso espaciado',
            badgeIcon: Icons.style_rounded,
            title: 'Mis flashcards',
            subtitle: 'Tus propias tarjetas, por asignatura y tema. Cada repaso las reprograma para que vuelvan justo cuando toca.',
            aside: due > 0 ? StatChip(value: '$due', label: 'para hoy') : const _CardStackArt(),
          ),
          if (decks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              DocChip(label: '${decks.length} ${decks.length == 1 ? 'asignatura' : 'asignaturas'}', icon: Icons.folder_rounded),
              DocChip(label: '$total tarjetas', icon: Icons.style_rounded),
            ]),
          ],
          const SizedBox(height: 18),
          if (_loading)
            for (var i = 0; i < 3; i++) const _FlashDeckSkeleton()
          else if (_error != null)
            _ErrorBox(message: _error!, onRetry: _load)
          else if (decks.isEmpty)
            const _EmptyFlashcards()
          else ...[
            FlashProgressPanel(forecast: _forecast, stats: _stats, accent: const Color(0xFFE8A598)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: InkInput(
                  controller: _query,
                  hint: 'Buscar asignatura…',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<OrdenAsignaturas>(
                tooltip: 'Orden',
                initialValue: _orden,
                onSelected: (o) {
                  setState(() => _orden = o);
                  _guardarPrefs();
                },
                itemBuilder: (_) => [
                  for (final o in OrdenAsignaturas.values) PopupMenuItem(value: o, child: Text(kNombreOrden[o]!)),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kHairline, width: 2),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.sort_rounded, size: 18, color: kMuted),
                    const SizedBox(width: 4),
                    Text(kNombreOrden[_orden]!, style: const TextStyle(color: kInk, fontSize: 13, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            if (secciones.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Ninguna asignatura coincide con «${_query.text.trim()}».',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.w700),
                ),
              )
            else ...[
              const WorkCountsHeader(trailing: 38),
              for (final s in secciones) ..._seccion(s.categoria, s.grupos),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _seccion(CategoriaAsignatura cat, List<FlashDeck> grupos) {
    final plegada = _plegadas.contains(cat);
    final nuevas = grupos.fold<int>(0, (n, d) => n + d.summary.nuevas);
    final falladas = grupos.fold<int>(0, (n, d) => n + d.summary.failed);
    final repasos = grupos.fold<int>(0, (n, d) => n + d.repasos);
    return [
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() => plegada ? _plegadas.remove(cat) : _plegadas.add(cat));
          _guardarPrefs();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Row(children: [
            Icon(plegada ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 20, color: kMuted),
            const SizedBox(width: 2),
            Text(
              '${kNombreCategoria[cat]!.toUpperCase()} · ${grupos.length}',
              style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4),
            ),
            const Spacer(),
            if (plegada)
              Text.rich(TextSpan(style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900), children: [
                TextSpan(text: '$nuevas', style: TextStyle(color: kFlashStatusTone[FlashStatus.nueva]!.fg)),
                const TextSpan(text: ' · ', style: TextStyle(color: kMuted)),
                TextSpan(text: '$falladas', style: TextStyle(color: kFlashStatusTone[FlashStatus.failed]!.fg)),
                const TextSpan(text: ' · ', style: TextStyle(color: kMuted)),
                TextSpan(text: '$repasos', style: const TextStyle(color: Color(0xFF5C7A59))),
              ])),
          ]),
        ),
      ),
      if (!plegada)
        for (final d in grupos)
          _DeckRow(
            deck: d,
            selected: _selectedDeck?.id == d.id,
            onTap: () => _open(d),
            onStudy: d.totalCards == 0 ? null : () => _open(d, estudiar: true),
            onRename: () => _renameDeck(d),
          ),
    ];
  }
}

/// Una asignatura en la lista: sigla en su color, nombre, dominio, las tres columnas y Estudiar.
class _DeckRow extends StatelessWidget {
  final FlashDeck deck;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onStudy;
  final VoidCallback onRename;

  const _DeckRow({required this.deck, required this.selected, required this.onTap, required this.onStudy, required this.onRename});

  @override
  Widget build(BuildContext context) {
    final v = visualAsignatura(deck.name, deck.color, deck.icon);
    final color = colorDeGrupo(deck);
    final idle = deck.dueCards == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? color.soft : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onRename,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? kInk : (idle ? const Color(0xFFEFEAE7) : const Color(0xFFE4DCD8)), width: 2),
            ),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.bg.withOpacity(idle ? 0.55 : 1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kInk, width: 1.5),
                ),
                child: Text(v.sigla, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    deck.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: idle ? const Color(0xFF9CA3AF) : kInk, fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  MasteryBar(percent: deck.dominio, total: deck.totalCards),
                ]),
              ),
              const SizedBox(width: 8),
              WorkCounts(nuevas: deck.summary.nuevas, falladas: deck.summary.failed, repasos: deck.repasos),
              IconButton(
                tooltip: 'Estudiar ${deck.name}',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.play_arrow_rounded),
                color: AppColors.primaryDark,
                onPressed: onStudy,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pila de fichas: la misma ilustración que abre las flashcards en la web.
class _CardStackArt extends StatelessWidget {
  const _CardStackArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 58,
      child: Stack(
        children: [
          for (var i = 2; i >= 0; i--)
            Positioned(
              left: i * 4.0,
              top: i * 3.0,
              child: Transform.rotate(
                angle: (i - 1) * 0.07,
                child: Container(
                  width: 40,
                  height: 50,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: i == 0 ? Colors.white : const Color(0xFFFFF5F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kInk, width: 1.8),
                  ),
                  child: i == 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 4,
                              width: 16,
                              decoration: BoxDecoration(
                                color: kAccent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final w in [22.0, 18.0, 13.0]) ...[
                              Container(
                                height: 2.4,
                                width: w,
                                color: const Color(0xFFD9D2CE),
                              ),
                              const SizedBox(height: 4),
                            ],
                          ],
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyFlashcards extends StatelessWidget {
  const _EmptyFlashcards();

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(24),
      texture: ruledPaper(step: 26),
      child: Column(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: kAccent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(4),
            ),
            child: const Icon(Icons.style_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aún no tienes flashcards',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kInk,
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea un grupo (por ejemplo, una asignatura) y ve metiendo dentro '
            'tus tarjetas. Se repasan con repetición espaciada.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMuted.withOpacity(0.95),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: kMuted, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kInk, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          GhostButton(
            label: 'Reintentar',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _FlashDeckSkeleton extends StatelessWidget {
  const _FlashDeckSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(4),
      ),
    );
  }
}
