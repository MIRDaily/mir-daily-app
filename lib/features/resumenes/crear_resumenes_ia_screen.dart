import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/creditos_ia.dart';
import '../../core/models/ia.dart';
import '../../core/models/resumen.dart';
import '../../core/models/resumen_ia.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/services/carpetas.dart';
import '../../core/services/creditos_ia_service.dart';
import '../../core/services/ia_extraccion.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ia/destino_carpeta.dart';
import '../../shared/ia/precio_ia.dart';
import '../../shared/sticker/sticker.dart';
import 'resumenes_api.dart';
import 'resumenes_borrador.dart';
import 'resumenes_grupo.dart';
import 'resumenes_guardado.dart';
import 'resumenes_ia.dart';
import 'resumenes_logica.dart';
import 'widgets/parrafo_huecos.dart';

enum _Paso { documento, opciones, generando, previa, guardando, resultado }

/// Crear resúmenes activos con IA desde un documento (PDF, Word o PowerPoint).
/// El archivo se extrae EN EL DISPOSITIVO (fase 0); al servidor solo viaja el texto.
class CrearResumenesIAScreen extends StatefulWidget {
  const CrearResumenesIAScreen({super.key});

  @override
  State<CrearResumenesIAScreen> createState() => _CrearResumenesIAScreenState();
}

class _CrearResumenesIAScreenState extends State<CrearResumenesIAScreen> {
  _Paso _paso = _Paso.documento;

  // Disponibilidad de la IA (admin + interruptor, lo valida el servidor).
  bool _estadoListo = false;
  bool _iaDisponible = false;

  // Documento.
  String? _nombre;
  String? _documento; // sha256
  Extraido? _extraido;
  String? _errorExtraccion;
  bool _extrayendo = false;

  // Opciones.
  ModoResumen _modo = ModoResumen.resumen;
  Densidad _densidad = Densidad.normal;
  final List<int> _niveles = [1, 2, 3, 4];
  final TextEditingController _tituloCtrl = TextEditingController();

  // Generación. `_gen` es la generación en curso (su cobro y el id para «Cancelar»): una respuesta
  // que llega de una generación cancelada (o sustituida) se descarta.
  GeneracionIa? _gen;
  bool _cancelando = false;
  String? _info;
  String _faseLabel = '';
  ResumenGenerado? _generado;
  List<ParrafoBorrador> _lista = [];
  List<FuenteFirmada> _fuentes = [];
  String? _error;

  // Carpeta del grupo nuevo: la sugerida por el título hasta que el usuario elige otra.
  List<AsignaturaCatalogo>? _arbol;
  Carpeta? _carpetaElegida;

  // «Más de este tema» y «Rehacer» en la vista previa: qué se está pidiendo (clave del tema o del
  // párrafo), la versión anterior de cada párrafo rehecho (para «Deshacer») y el último aviso.
  String? _pidiendo;
  final Map<String, ParrafoBorrador> _anteriores = {};
  String? _avisoPrevia;

  // Guardado.
  bool _guardando = false;
  String _resultado = '';

  ResumenesApi get _api => context.read<ResumenesApi>();
  ResumenesIa get _ia => context.read<ResumenesIa>();
  CreditosIa get _creditos => context.read<CreditosIa>();
  BorradorStore get _borradores => BorradorStore();

  @override
  void initState() {
    super.initState();
    _comprobarEstado();
    // Saldo y tarifa al día al abrir (pudo gastarse en la web).
    _creditos.refrescar();
    _cargarArbol();
  }

  Future<void> _cargarArbol() async {
    try {
      final a = await context.read<CarpetasApi>().arbol();
      if (mounted) setState(() => _arbol = a);
    } catch (_) {
      // Sin catálogo no se ofrece carpeta: el grupo queda en «Sin clasificar».
    }
  }

  String get _modoId => _modo == ModoResumen.literal ? 'literal' : 'resumen';

  /// Precio de la generación con lo elegido (null sin tarifa o sin documento).
  int? get _precio {
    final e = _extraido;
    if (e == null) return null;
    return precioIa(
      _creditos.tarifa,
      clave: claveResumenes(_modoId),
      caracteres: caracteresDocumento(e.secciones),
      densidad: _densidad.id,
    );
  }

  Sugerencia? get _sugerencia {
    final arbol = _arbol;
    if (arbol == null || arbol.isEmpty) return null;
    final titulo = _tituloCtrl.text.trim().isNotEmpty ? _tituloCtrl.text.trim() : (_extraido?.titulo ?? '');
    return sugerirCarpeta(arbol, textosDocumento(titulo));
  }

  Carpeta get _carpeta => _carpetaElegida ?? _sugerencia?.carpeta ?? Carpeta.sinClasificar;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    super.dispose();
  }

  Future<void> _comprobarEstado() async {
    final e = await _ia.estado();
    if (!mounted) return;
    setState(() {
      _estadoListo = true;
      _iaDisponible = e != null && e['disponible'] == true;
    });
  }

  Future<void> _elegirDocumento() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'pptx'],
    );
    if (files.isEmpty) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) return;

    setState(() {
      _nombre = f.name;
      _documento = sha256Hex(bytes);
      _extrayendo = true;
      _errorExtraccion = null;
      _extraido = null;
    });

    try {
      final e = await extraerDocumento(bytes: bytes, nombre: f.name, maxChars: 200000);
      if (!mounted) return;
      setState(() {
        _extraido = e;
        _extrayendo = false;
        _tituloCtrl.text = e.titulo;
        _paso = _Paso.opciones;
      });
    } on ExtractException catch (e) {
      if (!mounted) return;
      setState(() {
        _extrayendo = false;
        _errorExtraccion = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _extrayendo = false;
        _errorExtraccion = 'No se pudo leer el documento.';
      });
    }
  }

  Future<void> _generar() async {
    final e = _extraido!;
    final gen = _creditos.nuevaGeneracion(_precio);
    setState(() {
      _gen = gen;
      _paso = _Paso.generando;
      _faseLabel = 'Preparando…';
      _error = null;
      _info = null;
    });
    try {
      final g = await _ia.generar(
        titulo: _tituloCtrl.text.trim(),
        modo: _modo,
        niveles: _niveles,
        densidad: _densidad,
        secciones: e.secciones,
        paginas: e.paginas,
        unidad: e.unidad == 'diapositiva' ? 'diapositiva' : null,
        cobro: gen.cobro,
        onEvento: (ev) {
          if (ev is EventoReserva) gen.anotar(ev);
          if (!identical(_gen, gen)) return;
          if (ev is EventoFase) {
            if (mounted) setState(() => _faseLabel = _labelFase(ev.fase));
          }
        },
      );
      if (!mounted || !identical(_gen, gen)) return;
      final lista = g.esLibro
          ? g.temas.expand((t) => t.parrafos).toList()
          : g.parrafos;
      setState(() {
        _generado = g;
        _lista = lista;
        _fuentes = g.fuentes;
        _paso = _Paso.previa;
      });
      await _guardarBorradorLocal();
    } catch (err) {
      if (!mounted || !identical(_gen, gen)) return;
      setState(() {
        _error = mensajeErrorIa(err, 'No se pudo generar. Inténtalo de nuevo.');
        _paso = _Paso.opciones;
      });
    } finally {
      if (mounted) _creditos.refrescar();
    }
  }

  /// «Cancelar»: avisa al servidor ANTES de dar la generación por perdida (así cuenta como cancelación
  /// del usuario y devuelve lo que toque) y vuelve a las opciones. La respuesta, si llega, se descarta.
  Future<void> _cancelar() async {
    final gen = _gen;
    if (gen == null || _cancelando) return;
    final creditos = _creditos;
    final aviso = creditos.activo ? avisoAntesDeCancelar(gen, creditos.saldo, creditos.tarifa) : null;
    if (aviso != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Text(aviso),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Seguir')),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Cancelar')),
          ],
        ),
      );
      if (ok != true || !mounted || !identical(_gen, gen)) return;
    }
    setState(() => _cancelando = true);
    PrevisionCancelacion? prevision;
    if (creditos.activo && gen.cobro != null && gen.usageId != null) {
      try {
        prevision = await creditos.api.cancelar(gen.usageId!);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _gen = null;
      _cancelando = false;
      _paso = _Paso.opciones;
      _error = null;
      _info = gen.cobro != null ? mensajeCancelacion(prevision, gen) : 'Generación cancelada.';
    });
    // La liquidación llega al servidor un instante después del corte.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _creditos.refrescar();
    });
  }

  Future<void> _guardarBorradorLocal() async {
    final usuario = context.read<AuthProvider>().userId;
    if (usuario == null || _documento == null) return;
    final ahora = DateTime.now().millisecondsSinceEpoch;
    await _borradores.guardar(usuario, BorradorResumen(
      clave: claveBorradorResumen(usuario, _documento!),
      usuario: usuario,
      documento: _documento!,
      titulo: _tituloCtrl.text.trim(),
      nombreGrupo: _tituloCtrl.text.trim(),
      modo: _modo,
      fuenteNombre: _nombre,
      fuenteUnidad: _extraido?.unidad == 'diapositiva' ? 'diapositiva' : (_extraido?.unidad == 'página' ? 'pagina' : null),
      fuentes: _fuentes,
      lista: _lista,
      fallidos: _generado?.fallidos.map((f) => f.titulo).toList() ?? const [],
      creado: ahora,
      actualizado: ahora,
      caduca: ahora + diasBorradorResumen * 86400000,
    ));
  }

  Future<void> _guardarEnGrupo() async {
    if (_lista.isEmpty || _guardando) return;
    final grupos = await _api.listarGrupos();
    if (!mounted) return;
    final destino = await _elegirDestino(grupos);
    if (destino == null || !mounted) return;

    setState(() {
      _paso = _Paso.guardando;
      _guardando = true;
    });

    try {
      final incluidos = _lista.where((p) => p.incluir).toList();
      final textos = incluidos.map((p) => p.texto).toList();
      final r = await _api.buscarParecidos(destino.id, textos, _fuentes);
      final parecidos = <String, Parecido?>{};
      for (var i = 0; i < incluidos.length && i < r.parecidos.length; i++) {
        parecidos[incluidos[i].key] = r.parecidos[i];
      }
      final tandas = tandasDeGuardado(_lista, _aNuevo, _fuentes, parecidos);
      final res = await _api.anadirParrafosIA(destino.id, tandas);
      if (!mounted) return;
      setState(() {
        _paso = _Paso.resultado;
        _guardando = false;
        _resultado = '${res.creados} ${res.creados == 1 ? 'párrafo guardado' : 'párrafos guardados'}'
            '${res.duplicados > 0 ? ' · ${res.duplicados} ya estaban' : ''}'
            '${res.parecidos > 0 ? ' · ${res.parecidos} casi duplicados' : ''} en «${destino.name}».';
      });
      final usuario = context.read<AuthProvider>().userId;
      if (usuario != null && _documento != null) await _borradores.borrar(usuario, _documento!);
    } on ResumenesApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _paso = _Paso.previa;
        _guardando = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paso = _Paso.previa;
        _guardando = false;
        _error = 'No se pudieron guardar los párrafos.';
      });
    }
  }

  ParrafoNuevo _aNuevo(ParrafoBorrador p) => ParrafoNuevo(
        texto: p.texto,
        huecos: p.huecos,
        tema: p.tema.isNotEmpty ? p.tema : null,
        modo: _modo,
        origen: (p.ia == null && _nombre == null)
            ? null
            : OrigenGuardado(
                name: _nombre,
                page: p.ia?.pagina ?? p.ia?.diapositiva,
                unit: p.ia?.diapositiva != null ? 'diapositiva' : (p.ia?.pagina != null ? 'pagina' : null),
                fragmento: p.ia?.fragmento,
              ),
      );

  Future<GrupoResumen?> _elegirDestino(List<GrupoResumen> grupos) async {
    return showAdaptiveModal<GrupoResumen>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Guardar en', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: kInk)),
              const SizedBox(height: 14),
              ListTile(
                onTap: () async {
                  final nombre = await _pedirNombreGrupo(ctx);
                  if (nombre == null) return;
                  try {
                    final g = await _api.crearGrupo(nombre);
                    // A su carpeta. Si falla, el grupo ya está creado y queda en «Sin clasificar».
                    await _archivar(g.id);
                    if (ctx.mounted) Navigator.pop(ctx, g);
                  } on ResumenesApiError catch (e) {
                    if (ctx.mounted) _aviso(ctx, e.message);
                  } catch (_) {
                    if (ctx.mounted) _aviso(ctx, 'No se pudo crear el grupo.');
                  }
                },
                leading: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(10), border: Border.all(color: kInk, width: 2)),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                ),
                title: const Text('Nuevo grupo', style: TextStyle(color: kInk, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  _arbol == null || _arbol!.isEmpty ? 'Créalo ahora y guarda aquí lo generado' : 'Créalo ahora · irá a ${nombreCarpeta(_arbol, _carpeta)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              for (final g in grupos)
                ListTile(
                  onTap: () => Navigator.pop(ctx, g),
                  leading: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: resolveColorResumen(g.color).bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kInk, width: 2)),
                    child: Icon(iconoGrupoResumen(g.icon), color: Colors.white, size: 18),
                  ),
                  title: Text(g.name, style: const TextStyle(color: kInk, fontWeight: FontWeight.w700)),
                  subtitle: Text('${g.total} párrafos', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              if (grupos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No tienes grupos todavía. Crea uno con el botón de arriba.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// El grupo recién creado, a la carpeta elegida (o a la sugerida, si no se tocó).
  Future<void> _archivar(String grupoId) async {
    final c = _carpeta;
    if (c.subjectId == null) return;
    try {
      await context.read<CarpetasApi>().mover('resumenes', [grupoId], c, origen: _carpetaElegida == null ? 'sugerencia' : 'usuario');
    } catch (_) {}
  }

  Future<String?> _pedirNombreGrupo(BuildContext ctx) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nuevo grupo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nombre del grupo (mín. 3 letras)', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _aviso(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: AppColors.textPrimary));
  }

  String _labelFase(FaseIa f) {
    switch (f) {
      case FaseIa.leyendo:
        return 'Leyendo el documento…';
      case FaseIa.estructura:
        return 'Estructurando…';
      case FaseIa.tablas:
        return 'Leyendo tablas…';
      case FaseIa.parrafos:
        return 'Escribiendo párrafos…';
      case FaseIa.ordenando:
        return 'Ordenando…';
      default:
        return 'Generando…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Crear con IA', style: TextStyle(color: kInk, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    if (!_estadoListo) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (!_iaDisponible) {
      final creditos = context.watch<CreditosIa>();
      final sinPlan = creditos.activo && creditos.saldo != null && !creditos.saldo!.puedeUsar;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            sinPlan ? 'Necesitas un plan con IA para usar esta función.' : 'La IA no está disponible para tu cuenta de momento.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
        ),
      );
    }

    switch (_paso) {
      case _Paso.documento:
        return _pasoDocumento();
      case _Paso.opciones:
        return _pasoOpciones();
      case _Paso.generando:
        return _pasoGenerando();
      case _Paso.previa:
        return _pasoPrevia();
      case _Paso.guardando:
        return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text('Guardando…', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ]));
      case _Paso.resultado:
        return _pasoResultado();
    }
  }

  Widget _pasoDocumento() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StickerHero(
            badge: 'IA',
            badgeIcon: Icons.auto_awesome_rounded,
            title: 'Resúmenes con IA',
            subtitle: 'Elige un PDF, Word o PowerPoint: la IA lo convierte en párrafos de repaso con los datos clave tapados. El archivo nunca sale de tu dispositivo.',
          ),
          const SizedBox(height: 24),
          StickerButton(
            label: 'Elegir documento',
            icon: Icons.upload_file_rounded,
            expand: true,
            onPressed: _extrayendo ? null : _elegirDocumento,
          ),
          if (_extrayendo) ...[
            const SizedBox(height: 16),
            const Row(children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
              SizedBox(width: 10),
              Text('Leyendo el documento…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ]),
          ],
          if (_errorExtraccion != null) ...[
            const SizedBox(height: 14),
            Text(_errorExtraccion!, style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  Widget _pasoOpciones() {
    final e = _extraido!;
    final creditos = context.watch<CreditosIa>();
    // Sin créditos encendidos (o mientras llegan) no hay precio que enseñar.
    final linea = creditos.activo ? lineaPrecio(_precio, creditos.saldo) : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(_nombre ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        Text('${e.caracteres} caracteres · ${e.secciones.length} ${e.unidad == 'diapositiva' ? 'diapositivas' : 'páginas'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 14),
        const SectionLabel('Título'),
        TextField(
          controller: _tituloCtrl,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          // La carpeta sugerida sale del título.
          onChanged: (_) => setState(() {}),
        ),
        if (_arbol != null && _arbol!.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionLabel('Dónde lo guardamos'),
          DestinoCarpeta(
            arbol: _arbol!,
            valor: _carpeta,
            sugerida: _sugerencia?.carpeta,
            candidatas: _sugerencia?.candidatas ?? const [],
            onChanged: (c) => setState(() => _carpetaElegida = c),
          ),
          const SizedBox(height: 6),
          const Text('Es la carpeta del grupo nuevo; si lo guardas en uno que ya tienes, se queda donde esté.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
        ],
        const SizedBox(height: 18),
        const SectionLabel('Modo'),
        Wrap(spacing: 8, children: [
          _chipOpcion('Resumen', 'Condensa cada apartado', _modo == ModoResumen.resumen, () => setState(() => _modo = ModoResumen.resumen)),
          _chipOpcion('Texto original', 'Párrafos tal cual', _modo == ModoResumen.literal, () => setState(() => _modo = ModoResumen.literal)),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('Densidad'),
        Wrap(spacing: 8, children: [
          _chipOpcion('Pocos', null, _densidad == Densidad.pocas, () => setState(() => _densidad = Densidad.pocas)),
          _chipOpcion('Normal', null, _densidad == Densidad.normal, () => setState(() => _densidad = Densidad.normal)),
          _chipOpcion('Muchos', null, _densidad == Densidad.muchas, () => setState(() => _densidad = Densidad.muchas)),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('Niveles de los huecos'),
        NivelNuevo(nivel: 2, onChanged: (_) {}), // los 4 niveles van siempre
        const SizedBox(height: 6),
        const Text('Se generan huecos de los cuatro niveles.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 20),
        if (linea != null) ...[
          PrecioIa(linea: linea),
          const SizedBox(height: 12),
        ],
        StickerButton(
          label: 'Generar',
          icon: Icons.auto_awesome_rounded,
          expand: true,
          onPressed: (linea?.suficiente ?? true) ? _generar : null,
        ),
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!, style: const TextStyle(color: AppColors.successDark, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }

  Widget _chipOpcion(String titulo, String? sub, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? kInk : kHairline, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: TextStyle(color: sel ? Colors.white : kInk, fontSize: 13, fontWeight: FontWeight.w800)),
          if (sub != null) Text(sub, style: TextStyle(color: sel ? Colors.white70 : AppColors.textSecondary, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _pasoGenerando() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppColors.primary)),
        const SizedBox(height: 16),
        Text(_faseLabel, style: const TextStyle(color: kInk, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _cancelando ? null : _cancelar,
          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          label: Text(_cancelando ? 'Cancelando…' : 'Cancelar', style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _pasoPrevia() {
    final incluidos = _lista.where((p) => p.incluir).length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            children: [
              Row(children: [
                Expanded(child: Text('Vista previa · ${_lista.length} párrafos', style: const TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 17))),
                Text('$incluidos incluidos', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              ]),
              const SizedBox(height: 6),
              const Text('Desmarca los que no quieras guardar y toca una palabra para ajustar los huecos.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
              if (_avisoPrevia != null) ...[
                const SizedBox(height: 10),
                Text(_avisoPrevia!, style: const TextStyle(color: kInk, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
              if (_extraido == null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Para «Más» y «Rehacer» hace falta el documento: vuelve a elegirlo desde el principio.',
                  style: TextStyle(color: kGrisAA, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              for (var i = 0; i < _lista.length; i++) ...[
                if (i == 0 || _lista[i].tema != _lista[i - 1].tema || _lista[i].grupo != _lista[i - 1].grupo) _cabeceraTema(_lista[i]),
                _tarjetaBorrador(i),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: StickerButton(
            label: incluidos == 0 ? 'Nada que guardar' : 'Guardar en un grupo',
            icon: Icons.save_rounded,
            expand: true,
            onPressed: incluidos == 0 ? null : _guardarEnGrupo,
          ),
        ),
      ],
    );
  }

  int? get _precioMas => precioIa(_creditos.tarifa, clave: 'resumenes_mas');
  int? get _precioRehacer => precioIa(_creditos.tarifa, clave: 'resumenes_rehacer');

  /// Cabecera de un tema en la vista previa: su nombre y «Más de este tema».
  Widget _cabeceraTema(ParrafoBorrador p) {
    final clave = 'mas:${p.grupo ?? ''}|${p.tema}';
    final cargando = _pidiendo == clave;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(p.tema.toUpperCase(), style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
        TextButton.icon(
          onPressed: _extraido == null || _pidiendo != null ? null : () => _pedirMas(p.grupo ?? '', p.tema),
          icon: cargando
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: Text(cargando ? 'Pidiendo…' : 'Más'),
        ),
      ]),
    );
  }

  /// «Más de este tema»: qué (de todo, más difíciles, más fáciles) y cuántos, con su precio; los
  /// nuevos entran tras el último del tema, marcados como nuevos.
  Future<void> _pedirMas(String grupo, String tema) async {
    final e = _extraido;
    if (e == null) return;
    final generacion = nivelesDeLista(_lista);
    var opcion = OpcionMas.todo;
    var cantidad = 5;
    final precio = _precioMas;
    final elegido = await showAdaptiveModal<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Más de «$tema»', style: const TextStyle(color: kInk, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final o in kOpcionesMas)
                RadioListTile<OpcionMas>(
                  contentPadding: EdgeInsets.zero,
                  value: o.id,
                  groupValue: opcion,
                  onChanged: (v) => setM(() => opcion = v!),
                  title: Text(o.titulo, style: const TextStyle(color: kInk, fontWeight: FontWeight.w800)),
                  subtitle: Text(o.descripcion),
                ),
              const SizedBox(height: 4),
              Wrap(spacing: 8, children: [
                for (final c in kCantidadesMas)
                  ChoiceChip(label: Text('$c párrafos'), selected: cantidad == c, onSelected: (_) => setM(() => cantidad = c)),
              ]),
              const SizedBox(height: 12),
              if (_creditos.activo) PrecioIa(linea: lineaPrecio(precio, _creditos.saldo)),
              const SizedBox(height: 12),
              StickerButton(
                label: 'Pedir',
                icon: Icons.auto_awesome_rounded,
                expand: true,
                onPressed: _creditos.activo && !lineaPrecio(precio, _creditos.saldo).suficiente ? null : () => Navigator.pop(ctx, true),
              ),
            ]),
          ),
        ),
      ),
    );
    if (elegido != true || !mounted) return;
    final clave = 'mas:$grupo|$tema';
    final delTema = parrafosDeTema(_lista, grupo, tema);
    setState(() {
      _pidiendo = clave;
      _avisoPrevia = null;
    });
    try {
      // Solo el fragmento de ese tema: las páginas de sus párrafos, con margen.
      final secciones = fragmentoDeTema(e.secciones, tema, delTema);
      final r = await _ia.mas(
        titulo: _generado?.titulo ?? _tituloCtrl.text.trim(),
        modo: _modo,
        secciones: secciones,
        paginas: paginasDeFragmento(secciones),
        unidad: e.unidad == 'diapositiva' ? 'diapositiva' : null,
        niveles: nivelesDeOpcion(opcion, generacion),
        tema: tema,
        cantidad: cantidad,
        existentes: delTema.map((p) => p.texto).toList(),
        vecinos: vecinosDeTema(_lista, grupo, tema),
        cobro: _creditos.nuevaGeneracion(precio).cobro,
      );
      if (!mounted) return;
      final quitados = r.repetidos + r.casiDuplicados;
      if (r.parrafos.isEmpty) {
        setState(() => _avisoPrevia = 'No han salido párrafos nuevos de este tema${quitados > 0 ? ' ($quitados repetían uno que ya tenías)' : ''}.');
      } else {
        final x = insertarNuevos(_lista, grupo, tema, r.parrafos, DateTime.now().millisecondsSinceEpoch.toRadixString(36));
        setState(() {
          _lista = x.lista;
          _avisoPrevia = textoMas(r.parrafos.length, quitados);
        });
        await _guardarBorradorLocal();
      }
    } catch (err) {
      if (mounted) setState(() => _avisoPrevia = mensajeErrorIa(err, 'No se pudieron generar más párrafos.'));
    } finally {
      if (mounted) setState(() => _pidiendo = null);
      _creditos.refrescar();
    }
  }

  /// «Rehacer este párrafo»: otra versión con los mismos datos en los huecos, en su sitio.
  Future<void> _rehacer(ParrafoBorrador p) async {
    final e = _extraido;
    if (e == null || _pidiendo != null) return;
    final precio = _precioRehacer;
    if (_creditos.activo && !lineaPrecio(precio, _creditos.saldo).suficiente) {
      setState(() => _avisoPrevia = 'No te llegan los créditos para rehacer un párrafo.');
      return;
    }
    setState(() {
      _pidiendo = p.key;
      _avisoPrevia = null;
    });
    try {
      final secciones = fragmentoDeParrafo(e.secciones, p, parrafosDeTema(_lista, p.grupo ?? '', p.tema));
      final nuevo = await _ia.rehacer(
        titulo: _generado?.titulo ?? _tituloCtrl.text.trim(),
        modo: _modo,
        secciones: secciones,
        paginas: paginasDeFragmento(secciones),
        unidad: e.unidad == 'diapositiva' ? 'diapositiva' : null,
        tema: p.tema,
        texto: p.texto,
        huecos: p.huecos,
        cobro: _creditos.nuevaGeneracion(precio).cobro,
      );
      if (!mounted) return;
      setState(() {
        _anteriores[p.key] = p;
        _lista = rehacerEnSitio(_lista, p.key, nuevo);
      });
      await _guardarBorradorLocal();
    } catch (err) {
      if (mounted) setState(() => _avisoPrevia = mensajeErrorIa(err, 'No se pudo rehacer el párrafo.'));
    } finally {
      if (mounted) setState(() => _pidiendo = null);
      _creditos.refrescar();
    }
  }

  void _deshacerRehacer(ParrafoBorrador p) {
    final anterior = _anteriores.remove(p.key);
    if (anterior == null) return;
    setState(() => _lista = deshacerEnSitio(_lista, p.key, anterior));
    _guardarBorradorLocal();
  }

  Widget _tarjetaBorrador(int i) {
    final p = _lista[i];
    return StickerCard(
      margin: const EdgeInsets.only(bottom: 12),
      depth: 3,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _lista[i] = p.copyWith(incluir: !p.incluir)),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: p.incluir ? kInk : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kInk, width: 2),
                  ),
                  child: p.incluir ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.tema, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              if (p.nuevo)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(6)),
                  child: const Text('NUEVO', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                ),
              if (p.ia?.dudoso != null)
                const Tooltip(message: 'La IA lo marcó como dudoso', child: Icon(Icons.help_outline_rounded, size: 16, color: AppColors.warning)),
              Text('${p.huecos.length} huecos', style: TextStyle(color: kTintaNivel[2], fontSize: 11.5, fontWeight: FontWeight.w700)),
              if (_anteriores.containsKey(p.key))
                IconButton(
                  tooltip: 'Deshacer: volver a la versión anterior',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.undo_rounded, size: 19),
                  onPressed: _pidiendo != null ? null : () => _deshacerRehacer(p),
                ),
              IconButton(
                tooltip: 'Rehacer este párrafo',
                visualDensity: VisualDensity.compact,
                icon: _pidiendo == p.key
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.autorenew_rounded, size: 19),
                onPressed: _extraido == null || _pidiendo != null ? null : () => _rehacer(p),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ParrafoHuecos(
            texto: p.texto,
            huecos: p.huecos,
            editable: true,
            nivel: 2,
            onChange: (h) => setState(() => _lista[i] = p.copyWith(huecos: h)),
          ),
        ],
      ),
    );
  }

  Widget _pasoResultado() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20), border: Border.all(color: kInk, width: 2), boxShadow: inkShadow(3)),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 18),
          Text(_resultado, textAlign: TextAlign.center, style: const TextStyle(color: kInk, fontWeight: FontWeight.w700, fontSize: 15, height: 1.5)),
          const SizedBox(height: 20),
          StickerButton(label: 'Volver', icon: Icons.check_rounded, expand: true, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
