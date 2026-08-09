import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confetti_overlay.dart';

// Mismas reglas que la web / backend.
final RegExp _usernameRegex = RegExp(r'^[a-z0-9._]{3,20}$');
final RegExp _displayNameRegex = RegExp(r'^[A-Za-z0-9 ]{2,16}$');

enum _UserStatus { idle, invalid, checking, available, taken, error }

/// Asistente de onboarding para usuarios nuevos, adaptado del de la web.
/// Recoge nombre visible, usuario, avatar, objetivo, curso, especialidad y
/// universidad, y los envía a /api/profile/onboarding (que marca el onboarding
/// como completado). [onFinished] se llama al terminar; [onSkip] al posponer.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  final VoidCallback onSkip;

  /// true en el alta (celebra "tu primer daily"); false al reeditar desde
  /// Ajustes (texto neutro).
  final bool celebrateDaily;

  const OnboardingScreen({
    super.key,
    required this.onFinished,
    required this.onSkip,
    this.celebrateDaily = true,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  ApiService get _api => context.read<ApiService>();

  int _step = 0; // 0..3
  bool _forward = true; // dirección de la transición entre pasos

  // Logo flotando (paso 0), igual que en la pantalla de carga.
  late final AnimationController _logoFloatCtrl;
  late final Animation<double> _logoFloat;

  // Subrayado handwritten de "Por médicos" / "para médicos" (paso 0):
  // se dibuja UNA vez, despacio, primero una frase y luego la otra.
  late final AnimationController _underlineCtrl;

  // Entrada escalonada (fade + desplazamiento) de los bloques del paso 0.
  late final AnimationController _welcomeEntryCtrl;

  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _customUniCtrl = TextEditingController();
  final _customUniFocus = FocusNode();

  // Carrusel infinito de avatares: arranca en mitad de un rango enorme (no
  // en el índice 0), así el usuario nunca llega a un principio/final real —
  // siempre hay un avatar cortado a cada lado, en ambas direcciones.
  static const _avatarItemExtent = 62.0; // 52 (avatar) + 10 (separación)
  // 60 vueltas × 12 avatares = 720 elementos: de sobra para que nadie llegue
  // a notar un principio/final, sin usar offsets/itemCount extremos.
  static const _avatarCycles = 60;
  late final ScrollController _avatarScrollCtrl;

  int _avatarId = 1;
  String? _mainGoal;
  int? _medicalYear; // 0 = "Médico", 1..6 = curso, null = sin indicar
  MirSpecialty? _specialty;
  University? _university;
  bool _useCustomUni = false;
  final bool _profilePublic = false;

  _UserStatus _userStatus = _UserStatus.idle;
  Timer? _userDebounce;

  List<University> _universities = [];
  List<MirSpecialty> _specialties = [];

  bool _submitting = false;
  bool _celebrating = false;
  String? _submitError;

  static const _goals = <Map<String, dynamic>>[
    {
      'value': 'prepare_mir',
      'label': 'Preparar el MIR',
      'desc': 'Voy a por la plaza.',
      'icon': Icons.school_rounded,
    },
    {
      'value': 'reinforce_degree',
      'label': 'Reforzar la carrera',
      'desc': 'Fijar lo importante del grado.',
      'icon': Icons.trending_up_rounded,
    },
    {
      'value': 'explore',
      'label': 'Explorar',
      'desc': 'Curiosear y aprender.',
      'icon': Icons.explore_rounded,
    },
  ];

  static const _years = <Map<String, dynamic>>[
    {'value': 1, 'label': '1º'},
    {'value': 2, 'label': '2º'},
    {'value': 3, 'label': '3º'},
    {'value': 4, 'label': '4º'},
    {'value': 5, 'label': '5º'},
    {'value': 6, 'label': '6º'},
    {'value': 0, 'label': 'Médico 😎'},
  ];

  @override
  void initState() {
    super.initState();
    _logoFloatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _logoFloat = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _logoFloatCtrl, curve: Curves.easeInOut),
    );
    _underlineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Se dibuja una vez, con un pequeño respiro tras aparecer la pantalla.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _underlineCtrl.forward();
    });
    _welcomeEntryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    // Arranca en mitad del rango "infinito" de avatares.
    final avatarStartIndex =
        (_avatarCycles ~/ 2) * AppConfig.avatarCatalog.length;
    _avatarScrollCtrl = ScrollController(
      initialScrollOffset: avatarStartIndex * _avatarItemExtent,
    );
    final profile = context.read<AuthProvider>().profile;
    _avatarId = profile?.avatarId ?? 1;
    if (profile?.displayName != null && profile!.displayName!.isNotEmpty) {
      // Saneamos el prellenado (el alta pone el prefijo del email, que puede
      // tener puntos u otros caracteres no válidos para el nombre visible).
      final clean = profile.displayName!
          .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      _nameCtrl.text = clean.length > 16 ? clean.substring(0, 16) : clean;
    }
    _nameCtrl.addListener(() => setState(() {}));
    // Prellenado de campos ya guardados (útil al reeditar desde Ajustes; así no
    // se pierden al reenviar el onboarding).
    _medicalYear = profile?.medicalYear;
    _mainGoal = profile?.mainGoal;
    _prefUniversityName = profile?.university;
    _prefSpecialtyName = profile?.mirSpecialty;
    final preUser = profile?.username;
    if (preUser != null && preUser.isNotEmpty) {
      _userCtrl.text = preUser;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onUsernameChanged(preUser));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCatalogs());
    // Precarga TODO lo pesado (los 12 avatares + el logo) desde YA, mientras
    // el usuario todavía está leyendo el paso de bienvenida — así, al llegar
    // al paso de identidad, los avatares ya están descargados/decodificados
    // y no compiten por red/CPU justo durante la animación de transición
    // (eso era el lag: antes se disparaban ~12 peticiones de golpe la
    // primera vez que se construía ese paso).
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAssets());
  }

  Future<void> _precacheAssets() async {
    if (!mounted) return;
    final futures = <Future<void>>[
      precacheImage(const AssetImage('assets/images/logo_mirdaily.png'), context),
      for (final id in AppConfig.avatarCatalog)
        precacheImage(NetworkImage(AppConfig.avatarUrl(id)), context)
            // Un avatar que falle (sin red, 404...) no debe romper el resto.
            .catchError((_) {}),
    ];
    await Future.wait(futures);
  }

  String? _prefUniversityName;
  String? _prefSpecialtyName;

  Future<void> _loadCatalogs() async {
    try {
      final results = await Future.wait([
        _api.getUniversities(),
        _api.getMirSpecialties(),
      ]);
      if (!mounted) return;
      setState(() {
        _universities = results[0] as List<University>;
        _specialties = results[1] as List<MirSpecialty>;
        // Casar por nombre lo que ya tenía el perfil.
        if (_specialty == null && _prefSpecialtyName != null) {
          for (final s in _specialties) {
            if (s.name == _prefSpecialtyName) {
              _specialty = s;
              break;
            }
          }
        }
        if (_university == null &&
            !_useCustomUni &&
            _prefUniversityName != null) {
          University? match;
          for (final u in _universities) {
            if (u.name == _prefUniversityName) {
              match = u;
              break;
            }
          }
          if (match != null) {
            _university = match;
          } else {
            // No está en el catálogo => era una universidad personalizada.
            _useCustomUni = true;
            _customUniCtrl.text = _prefUniversityName!;
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _logoFloatCtrl.dispose();
    _underlineCtrl.dispose();
    _welcomeEntryCtrl.dispose();
    _avatarScrollCtrl.dispose();
    _userDebounce?.cancel();
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _customUniCtrl.dispose();
    _customUniFocus.dispose();
    super.dispose();
  }

  // ---- Username: validación + disponibilidad con debounce ----
  void _onUsernameChanged(String raw) {
    final value = raw.toLowerCase().trim();
    if (value != raw) {
      _userCtrl.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _userDebounce?.cancel();
    if (!_usernameRegex.hasMatch(value)) {
      setState(() => _userStatus =
          value.isEmpty ? _UserStatus.idle : _UserStatus.invalid);
      return;
    }
    setState(() => _userStatus = _UserStatus.checking);
    _userDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final available = await _api.checkUsername(value);
        if (!mounted || _userCtrl.text.trim() != value) return;
        setState(() =>
            _userStatus = available ? _UserStatus.available : _UserStatus.taken);
      } catch (_) {
        if (mounted) setState(() => _userStatus = _UserStatus.error);
      }
    });
  }

  bool get _step1Valid =>
      _displayNameRegex.hasMatch(_nameCtrl.text.trim()) &&
      _userStatus == _UserStatus.available;

  bool get _canAdvance {
    switch (_step) {
      case 0:
        return true;
      case 1:
        return _step1Valid;
      case 2:
        return _mainGoal != null;
      case 3:
        if (_useCustomUni) {
          final u = _customUniCtrl.text.trim();
          return u.isEmpty || (u.length >= 2 && u.length <= 100);
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (_step < 3) {
      setState(() {
        _forward = true;
        _step++;
      });
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() {
        _forward = false;
        _step--;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      if (_avatarId != (auth.profile?.avatarId ?? 1)) {
        await _api.updateAvatar(_avatarId);
      }
      final custom = _customUniCtrl.text.trim();
      await _api.submitOnboarding(
        displayName: _nameCtrl.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        username: _userCtrl.text.toLowerCase().trim(),
        medicalYear: _medicalYear,
        mirSpecialtyId: _specialty?.id,
        mainGoal: _mainGoal,
        universityId: _useCustomUni ? null : _university?.id,
        customUniversity:
            _useCustomUni ? (custom.isEmpty ? null : custom) : null,
        profilePublic: _profilePublic,
      );
      if (!mounted) return;
      // El onboarding ya está guardado en el servidor. Mostramos la celebración
      // ANTES de entrar a la app; al terminar, refrescamos el perfil (lo que
      // re-enruta al daily desde _OnboardingGate).
      setState(() {
        _submitting = false;
        _celebrating = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = e.toString();
        });
      }
    }
  }

  List<_SummaryItem> _summaryItems() {
    final items = <_SummaryItem>[];
    if (_mainGoal != null) {
      final g = _goals.firstWhere((e) => e['value'] == _mainGoal);
      items.add(_SummaryItem(g['icon'] as IconData, g['label'] as String));
    }
    if (_medicalYear != null) {
      final y = _years.firstWhere((e) => e['value'] == _medicalYear);
      items.add(_SummaryItem(
          Icons.school_outlined,
          _medicalYear == 0
              ? 'Médico'
              : '${y['label']} de Medicina'));
    }
    if (_specialty != null) {
      items.add(_SummaryItem(Icons.medical_services_outlined, _specialty!.name));
    }
    final uni = _useCustomUni ? _customUniCtrl.text.trim() : _university?.name;
    if (uni != null && uni.isNotEmpty) {
      items.add(_SummaryItem(Icons.account_balance_outlined, uni));
    }
    return items;
  }

  Future<void> _finishAfterCelebration() async {
    final auth = context.read<AuthProvider>();
    // Marca local inmediata: aunque la recarga falle, no se vuelve al asistente.
    auth.markOnboardingDone();
    await auth.refreshProfile();
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    if (_celebrating) {
      return _CelebrationView(
        name: _nameCtrl.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        username: _userCtrl.text.trim(),
        avatarId: _avatarId,
        items: _summaryItems(),
        celebrateDaily: widget.celebrateDaily,
        onDone: _finishAfterCelebration,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera: barra de progreso + saltar. Empieza en 25% porque
            // crear la cuenta ya es la primera parte hecha.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: _ProgressBar(
                      fraction: 0.25 + 0.75 * (_step / 3),
                    ),
                  ),
                  if (_step == 0)
                    TextButton(
                      onPressed: widget.onSkip,
                      child: const Text('Más tarde',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            Expanded(
              // La barra de progreso actúa de BARRERA: justo debajo de ella
              // hay una franja CORTA y fija (no proporcional a la pantalla)
              // donde el contenido que sale se desvanece del todo y queda
              // recortado — así nunca se ve "flotando" ni solapado con la
              // cabecera al salir.
              child: ClipRect(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) {
                    const barrierPx = 20.0;
                    final stop = (barrierPx / rect.height).clamp(0.0, 1.0);
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Colors.transparent, Colors.black],
                      stops: [0.0, stop],
                    ).createShader(rect);
                  },
                  child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                // Misma curva en ambos sentidos => misma velocidad de entrada
                // y salida, sensación de scroll continuo (no un "push" con
                // timings distintos).
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                // Efecto "scroll de página": el paso saliente sube y sale por
                // arriba mientras el entrante sube desde abajo, EN LA MISMA
                // DIRECCIÓN y al mismo ritmo (misma curva/duración en ambos).
                // El desvanecido va LIGADO al propio recorrido de cada
                // pantalla (no a una máscara fija del hueco): cada una se
                // desvanece solo durante el primer/último tramo de SU
                // trayecto — justo cuando está cerca del borde por el que
                // entra o sale — así nunca emborrona contenido en reposo.
                //
                // OJO: AnimatedSwitcher solo llama a `transitionBuilder` UNA
                // VEZ por entrada (al crearla), no en cada frame — así que
                // comprobar `anim.status` aquí fuera se queda congelado para
                // siempre con el valor de cuando la pantalla estaba ENTRANDO.
                // Por eso la pantalla saliente "caía" en la dirección de
                // entrada en vez de salir por arriba: `entering` nunca
                // pasaba a false. La solución es reevaluarlo en cada frame
                // dentro de un AnimatedBuilder que escucha `anim`.
                transitionBuilder: (child, anim) {
                  // Dirección de ENTRADA de esta pantalla, fija para toda su
                  // vida (aunque _forward cambie después con otros pasos).
                  final entryForward = _forward;
                  const edgeFrac = 0.22;
                  return AnimatedBuilder(
                    animation: anim,
                    child: child,
                    builder: (context, transitionChild) {
                      final entering = anim.status != AnimationStatus.reverse;
                      final Offset begin;
                      if (entryForward) {
                        begin = entering
                            ? const Offset(0, 1)
                            : const Offset(0, -1);
                      } else {
                        begin = entering
                            ? const Offset(0, -1)
                            : const Offset(0, 1);
                      }
                      final t = anim.value;
                      final fade = (t / edgeFrac).clamp(0.0, 1.0);
                      // Desenfoque máximo justo en el borde (fade≈0) y nítido
                      // ya asentada (fade=1): se difumina al salir/entrar.
                      final blur = (1 - fade) * 7.0;
                      return Opacity(
                        opacity: fade,
                        child: ImageFiltered(
                          imageFilter:
                              ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                          child: FractionalTranslation(
                            translation: Offset(
                              begin.dx * (1 - t),
                              begin.dy * (1 - t),
                            ),
                            child: transitionChild,
                          ),
                        ),
                      );
                    },
                  );
                },
                // Cada paso fluye de arriba abajo, sin centrado artificial.
                // El SingleChildScrollView aquí NO es para poder desplazar el
                // contenido a propósito (con el teclado cerrado no hay nada
                // que desplazar, se ve igual que un Column normal): es la red
                // de seguridad para cuando aparece el TECLADO — sin ella, el
                // campo que estás editando (nombre/usuario) podía quedar
                // tapado/recortado fuera de la pantalla y no se veía lo que
                // escribías. Los menús deslizables (universidad/especialidad)
                // siguen siendo listas aparte en su propia hoja — esto no los
                // afecta.
                //
                // El paso 0 (bienvenida) es la excepción: no tiene ningún
                // campo de texto (no hay riesgo de teclado), y necesita alto
                // ACOTADO para poder repartir el espacio con Spacer entre sus
                // bloques — un Padding normal (sin scroll) se lo da.
                child: _step == 0
                    ? Padding(
                        key: const ValueKey(0),
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        child: _stepWelcome(),
                      )
                    : SingleChildScrollView(
                        key: ValueKey(_step),
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        child: _buildStep(),
                      ),
                  ),
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _stepWelcome();
      case 1:
        return _stepIdentity();
      case 2:
        return _stepGoal();
      case 3:
      default:
        return _stepExtra();
    }
  }

  // ===========================================================================
  // PASO 0 · BIENVENIDA
  // ===========================================================================
  Widget _stepWelcome() {
    return AnimatedBuilder(
      animation: _welcomeEntryCtrl,
      builder: (context, _) {
        // Sin recortar (0..1): para easeOutBack esto puede pasar de 1 por un
        // instante — es justo lo que da el "rebote" al hacer el pop del logo.
        double stageRaw(double start, double end,
                [Curve c = Curves.easeOutCubic]) =>
            c.transform(
                ((_welcomeEntryCtrl.value - start) / (end - start))
                    .clamp(0.0, 1.0));

        // Entrada escalonada: la frase de arriba aparece primero, luego el
        // bloque logo+título (con un "pop" elástico), y por último los
        // textos de abajo — para que se sienta dinámico, no todo de golpe.
        final topStage = stageRaw(0.0, 0.4).clamp(0.0, 1.0);
        // Sin recortar, para la ESCALA (permite el rebote); recortada aparte
        // para la OPACIDAD (que no puede pasar de 1).
        final centerStageRaw = stageRaw(0.10, 0.62, Curves.easeOutBack);
        final centerStage = centerStageRaw.clamp(0.0, 1.0);
        final bottomStage = stageRaw(0.55, 1.0).clamp(0.0, 1.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 2),
            // "POR MÉDICOS, PARA MÉDICOS" — arriba del todo, en mayúscula y
            // con la letra pequeña (no es el titular, es una coletilla).
            Opacity(
              opacity: topStage,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - topStage)),
                child: AnimatedBuilder(
                  animation: _underlineCtrl,
                  builder: (context, _) {
                    const p1Curve = Interval(0.0, 0.5, curve: Curves.easeOut);
                    const p2Curve = Interval(0.5, 1.0, curve: Curves.easeOut);
                    final p1 = p1Curve.transform(_underlineCtrl.value);
                    final p2 = p2Curve.transform(_underlineCtrl.value);
                    return Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _HandwrittenPhrase(
                            text: 'POR MÉDICOS', progress: p1, fontSize: 13),
                        const Text(', ',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: AppColors.textSecondary)),
                        _HandwrittenPhrase(
                            text: 'PARA MÉDICOS', progress: p2, fontSize: 13),
                        const Text('.',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Spacer(flex: 2),
            // Título + logo: flotan JUNTOS (mismo Transform), con un margen
            // ligero entre ambos. Logo bastante más grande que antes.
            Transform.scale(
              scale: 0.75 + 0.25 * centerStageRaw,
              child: Opacity(
                opacity: centerStage,
                child: AnimatedBuilder(
                  animation: _logoFloat,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _logoFloat.value),
                    child: child,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Bienvenid@ a',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                      // El PNG del logo trae bastante margen transparente
                      // interno, así que "pegado" de verdad (visualmente, no
                      // solo por la caja del widget) significa subirlo hacia
                      // el título compensando ese margen — si no, se ve
                      // "lejos" aunque el hueco de layout sea pequeño. Es
                      // seguro tirar de él así porque debajo hay un Spacer
                      // flexible que absorbe la diferencia sin dejar huecos.
                      Transform.translate(
                        offset: const Offset(0, -34),
                        child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.22),
                              blurRadius: 54,
                              spreadRadius: 10,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return const RadialGradient(
                              center: Alignment.center,
                              radius: 0.9,
                              colors: [
                                Colors.white,
                                Colors.white,
                                Color(0xCCFFFFFF),
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.7, 0.85, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: Image.asset(
                            'assets/images/logo_mirdaily.png',
                            width: 300,
                            fit: BoxFit.contain,
                          ),
                        ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(flex: 3),
            // Abajo de la pantalla: "Sabemos..." + "Y QUEREMOS AYUDARTE".
            Opacity(
              opacity: bottomStage,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - bottomStage)),
                child: const Column(
                  children: [
                    Text(
                      'Sabemos lo que es preparar el MIR.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                          height: 1.35),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Y QUEREMOS AYUDARTE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(flex: 1),
            // Justo encima del botón "Continuar" (que va fuera, en el pie).
            Opacity(
              opacity: bottomStage,
              child: const Text(
                'Vamos a configurar tu perfil en un minuto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 2),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // PASO 1 · IDENTIDAD (avatar + nombre + usuario)
  // ===========================================================================
  Widget _stepIdentity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Tu perfil', 'Así te verán en el ranking.'),
        const SizedBox(height: 20),
        Center(child: _avatarPicker()),
        const SizedBox(height: 24),
        _label('Nombre visible'),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          maxLength: 16,
          decoration: _fieldDecoration(
            hint: 'Ej. Ana G.',
            counter: '',
          ).copyWith(counterText: ''),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
          ],
        ),
        if (_nameCtrl.text.isNotEmpty &&
            !_displayNameRegex.hasMatch(_nameCtrl.text.trim()))
          _hint('Entre 2 y 16 caracteres (letras, números y espacios).',
              AppColors.error),
        const SizedBox(height: 16),
        _label('Nombre de usuario'),
        const SizedBox(height: 8),
        TextField(
          controller: _userCtrl,
          maxLength: 20,
          onChanged: _onUsernameChanged,
          decoration: _fieldDecoration(hint: 'tu_usuario').copyWith(
            counterText: '',
            prefixText: '@ ',
            prefixStyle: const TextStyle(
                color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            suffixIcon: _userSuffix(),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
          ],
        ),
        _userStatusHint(),
      ],
    );
  }

  Widget _avatarPicker() {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipOval(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(3),
              child: ClipOval(child: _avatarImage(_avatarId)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Carrusel INFINITO (envuelve con módulo sobre el catálogo real) que
        // arranca en mitad de un rango grande: el usuario nunca ve un
        // principio ni un final, así que SIEMPRE hay un avatar cortado a
        // cada lado, sea cual sea la posición de scroll — sin necesidad de
        // sangrados con padding negativo (causaban un crash del framework al
        // interactuar con el carrusel).
        //
        // El ShaderMask es solo una capa de PINTADO (no toca constraints ni
        // el layout del Scrollable), así que es seguro: los avatares se
        // desvanecen suavemente al acercarse a los bordes, como una ruleta.
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.14, 0.86, 1.0],
          ).createShader(rect),
          child: SizedBox(
            height: 56,
            child: ListView.builder(
              controller: _avatarScrollCtrl,
              scrollDirection: Axis.horizontal,
              itemExtent: _avatarItemExtent,
              itemCount: _avatarCycles * AppConfig.avatarCatalog.length,
              itemBuilder: (context, i) {
                final id = AppConfig.avatarCatalog[i % AppConfig.avatarCatalog.length];
                final selected = id == _avatarId;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _avatarId = id),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              selected ? AppColors.primary : Colors.grey.shade200,
                          width: selected ? 3 : 1.5,
                        ),
                      ),
                      child: ClipOval(child: _avatarImage(id)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatarImage(int id) => Image.network(
        AppConfig.avatarUrl(id),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.primary.withValues(alpha: 0.1),
          child: const Icon(Icons.person, color: AppColors.primary),
        ),
      );

  Widget? _userSuffix() {
    switch (_userStatus) {
      case _UserStatus.checking:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary)),
        );
      case _UserStatus.available:
        return const Icon(Icons.check_circle, color: AppColors.success);
      case _UserStatus.taken:
      case _UserStatus.invalid:
        return const Icon(Icons.error_outline, color: AppColors.error);
      default:
        return null;
    }
  }

  Widget _userStatusHint() {
    switch (_userStatus) {
      case _UserStatus.invalid:
        return _hint('3-20 caracteres: minúsculas, números, "." y "_".',
            AppColors.error);
      case _UserStatus.taken:
        return _hint('Ese usuario ya está cogido.', AppColors.error);
      case _UserStatus.available:
        return _hint('¡Disponible!', AppColors.success);
      case _UserStatus.error:
        return _hint('No se pudo comprobar. Reintenta.', AppColors.textLight);
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // PASO 2 · OBJETIVO + CURSO
  // ===========================================================================
  Widget _stepGoal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('¿Cuál es tu objetivo?', 'Adaptaremos tu experiencia.'),
        const SizedBox(height: 20),
        for (final g in _goals) ...[
          _goalCard(g),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        _label('¿En qué curso estás? (opcional)'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final y in _years)
              _choiceChip(
                label: y['label'] as String,
                selected: _medicalYear == y['value'],
                onTap: () => setState(() => _medicalYear =
                    _medicalYear == y['value'] ? null : y['value'] as int),
              ),
          ],
        ),
      ],
    );
  }

  Widget _goalCard(Map<String, dynamic> g) {
    final selected = _mainGoal == g['value'];
    return GestureDetector(
      onTap: () => setState(() => _mainGoal = g['value'] as String),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: selected ? 0.16 : 0.09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(g['icon'] as IconData,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g['label'] as String,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(g['desc'] as String,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PASO 3 · ESPECIALIDAD + UNIVERSIDAD + PRIVACIDAD
  // ===========================================================================
  Widget _stepExtra() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Un par de cosas más', 'Todo esto es opcional.'),
        const SizedBox(height: 20),
        _label('Especialidad que te atrae'),
        const SizedBox(height: 8),
        _pickerField(
          value: _specialty?.name,
          hint: 'Elegir especialidad',
          onTap: () => _openPicker<MirSpecialty>(
            title: 'Especialidad MIR',
            items: _specialties,
            labelOf: (s) => s.name,
            onSelected: (s) => setState(() => _specialty = s),
            onClear: () => setState(() => _specialty = null),
          ),
        ),
        const SizedBox(height: 16),
        _label('Universidad'),
        const SizedBox(height: 8),
        if (_useCustomUni)
          TextField(
            controller: _customUniCtrl,
            focusNode: _customUniFocus,
            autofocus: true,
            maxLength: 100,
            onChanged: (_) => setState(() {}),
            decoration:
                _fieldDecoration(hint: 'Escribe tu universidad').copyWith(
              counterText: '',
              suffixIcon: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() {
                  _useCustomUni = false;
                  _customUniCtrl.clear();
                }),
              ),
            ),
          )
        else
          _pickerField(
            value: _university?.name,
            hint: 'Elegir universidad',
            onTap: () => _openPicker<University>(
              title: 'Universidad',
              items: _universities,
              labelOf: (u) => u.name,
              onSelected: (u) => setState(() => _university = u),
              onClear: () => setState(() => _university = null),
              extraAction: _PickerExtra(
                label: 'Mi universidad no está / Otra',
                onTap: () {
                  setState(() {
                    _useCustomUni = true;
                    _university = null;
                  });
                  // Enfoca la caja y abre el teclado nada más elegir "Otra".
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _customUniFocus.requestFocus();
                  });
                },
              ),
            ),
          ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: SwitchListTile(
            // Bloqueado en OFF: por ahora todos los perfiles son privados.
            value: false,
            onChanged: null,
            activeColor: AppColors.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Row(
              children: const [
                Text('Perfil público',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                SizedBox(width: 8),
                Icon(Icons.lock_outline, size: 15, color: AppColors.textLight),
              ],
            ),
            subtitle: const Text('Próximamente · ahora todos son privados',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_submitError!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ],
    );
  }

  Widget _pickerField({
    required String? value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: value == null
                      ? AppColors.textLight
                      : AppColors.textPrimary,
                  fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _openPicker<T>({
    required String title,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelected,
    required VoidCallback onClear,
    _PickerExtra? extraAction,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PickerSheet<T>(
        title: title,
        items: items,
        labelOf: labelOf,
        onSelected: onSelected,
        onClear: onClear,
        extraAction: extraAction,
      ),
    );
  }

  // ===========================================================================
  // FOOTER (atrás / continuar)
  // ===========================================================================
  Widget _buildFooter() {
    final isLast = _step == 3;
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 12 + MediaQuery.of(context).padding.bottom * 0),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(
                onPressed: _submitting ? null : _back,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textSecondary),
              ),
            ),
          Expanded(
            child: ElevatedButton(
              onPressed:
                  (_canAdvance && !_submitting) ? _next : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Text(
                      _step == 0
                          ? 'Empezar'
                          : (isLast ? 'Finalizar' : 'Continuar'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- helpers de estilo ----
  Widget _title(String t, String s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.4)),
          const SizedBox(height: 4),
          Text(s,
              style:
                  const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        ],
      );

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary));

  Widget _hint(String t, Color c) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(t, style: TextStyle(fontSize: 12.5, color: c)),
      );

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary)),
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint, String? counter}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textLight),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      );
}

// ---- Barra de progreso animada (empieza en 25% = cuenta creada) ----
// ---- Frase con subrayado "a mano", dibujado progresivamente ----
// Frase donde la negrita se va revelando de izquierda a derecha a la vez
// que el subrayado avanza por debajo — como si se fuera escribiendo.
class _HandwrittenPhrase extends StatelessWidget {
  final String text;
  final double progress; // 0..1
  final double fontSize;

  const _HandwrittenPhrase({
    required this.text,
    required this.progress,
    this.fontSize = 16,
  });

  static const _dimColor = Color(0xFFD8D2CC);

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final letters = text.split('');
    final n = letters.length;
    // Ventana de aparición de CADA letra (fracción del recorrido total).
    // Se solapan entre sí (varias letras a la vez, a distinto punto de su
    // propio fundido) para que la cascada sea fluida y no a trompicones.
    // Con esta fórmula la primera letra siempre empieza en 0 y la última
    // termina exactamente en 1, sea cual sea el largo de la palabra.
    const window = 0.42;
    final step = n > 1 ? (1 - window) / (n - 1) : 0.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i++)
              _letter(letters[i], clamped, i * step, window, fontSize),
          ],
        ),
        Positioned(
          left: 1,
          right: 1,
          bottom: -6,
          child: SizedBox(
            height: 8,
            child: CustomPaint(
              painter: _HandwrittenUnderlinePainter(progress: clamped),
            ),
          ),
        ),
      ],
    );
  }

  // Cada letra hace un fundido + un pequeño ascenso al aparecer (suave,
  // easeOut), pasando de un tono tenue a la negrita final.
  Widget _letter(String ch, double progress, double start, double window,
      double fontSize) {
    final t = ((progress - start) / window).clamp(0.0, 1.0);
    final eased = Curves.easeOut.transform(t);
    return Transform.translate(
      offset: Offset(0, (1 - eased) * 7),
      child: Opacity(
        opacity: eased,
        child: Text(
          ch,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: Color.lerp(_dimColor, AppColors.textPrimary, eased),
          ),
        ),
      ),
    );
  }
}

class _HandwrittenUnderlinePainter extends CustomPainter {
  final double progress;
  const _HandwrittenUnderlinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.width <= 0) return;
    final midY = size.height * 0.5;
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Trazo recto, crece de izquierda a derecha con el progreso.
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width * progress, midY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HandwrittenUnderlinePainter old) =>
      old.progress != progress;
}

class _ProgressBar extends StatelessWidget {
  final double fraction; // 0..1
  const _ProgressBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.25, end: fraction.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECE5E1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      height: 9,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 38,
              child: Text(
                '${(value * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PickerExtra {
  final String label;
  final VoidCallback onTap;
  const _PickerExtra({required this.label, required this.onTap});
}

/// Un dato del resumen mostrado en la celebración.
class _SummaryItem {
  final IconData icon;
  final String label;
  const _SummaryItem(this.icon, this.label);
}

/// Pantalla de celebración tras el onboarding: muestra el resumen elegido con
/// entrada escalonada (bouncy) + avatar + confeti, y en la parte inferior un
/// "oleaje" de coral. El usuario desliza hacia arriba para que el oleaje suba,
/// cubra la pantalla y se deslice hacia arriba revelando el fondo del daily.
class _CelebrationView extends StatefulWidget {
  final String name;
  final String username;
  final int avatarId;
  final List<_SummaryItem> items;
  final bool celebrateDaily;
  final VoidCallback onDone;

  const _CelebrationView({
    required this.name,
    required this.username,
    required this.avatarId,
    required this.items,
    required this.celebrateDaily,
    required this.onDone,
  });

  @override
  State<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends State<_CelebrationView>
    with TickerProviderStateMixin {
  bool _play = false;
  bool _locked = false; // true cuando la transición final ya está en marcha
  int _hapticsFired = 0; // nº de vibraciones lanzadas (una por tarjeta)

  late final AnimationController _entry; // entrada escalonada del contenido
  late final AnimationController _phase; // fase continua del oleaje
  late final AnimationController _reveal; // 0=abajo, 1=cubre y sale por arriba
  // Ciclo de aparición/ausencia de la flecha de "desliza": no está siempre
  // visible, aparece de vez en cuando con huecos de ausencia entre medias.
  late final AnimationController _hintCtrl;
  // Fase final: las burbujas (más lentas que la ola) terminan de cruzar la
  // parte superior de la pantalla. El daily NO carga hasta que esto termina.
  late final AnimationController _tail;
  bool _tailStarted = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200))
      ..addListener(_maybeHaptic)
      ..forward();
    _phase = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5200))
      ..repeat();
    _hintCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3600))
      ..repeat();
    _reveal = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..addStatusListener((s) {
        // El oleaje ya cubrió y salió; ahora dejamos que las burbujas
        // rezagadas terminen su propio recorrido antes de avisar.
        if (s == AnimationStatus.completed && !_tailStarted) {
          _tailStarted = true;
          _tail.forward(from: 0);
        }
      });
    _tail = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Vibración FUERTE justo con la explosión de confeti.
        HapticsService.strong();
        setState(() => _play = true);
      }
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    _phase.dispose();
    _reveal.dispose();
    _tail.dispose();
    _hintCtrl.dispose();
    super.dispose();
  }

  // Progreso de una "etapa" [start,end] del controlador de entrada, con curva.
  double _stage(double start, double end, Curve c) =>
      c.transform(((_entry.value - start) / (end - start)).clamp(0.0, 1.0));

  // Ventana de entrada de la tarjeta [index] dentro del timeline de _entry
  // (misma fórmula que usa _summaryRow para su animación: 4 tarjetas caben
  // dentro de [0,1]).
  static double _cardStart(int index) => 0.30 + index * 0.12;
  static const double _cardSpan = 0.32;

  // Una vibración por tarjeta cuando SE POSICIONA (dx≈0, escala≈1), no cuando
  // termina toda la animación de esa tarjeta (brillo/destello incluidos).
  // Curves.elasticOut (período 0.4) cruza exactamente 1.0 la primera vez en
  // t=0.5 de su propia ventana — ese es el instante en que la tarjeta llega a
  // su sitio por primera vez, antes de los micro-rebotes residuales.
  void _maybeHaptic() {
    final n = widget.items.length;
    while (_hapticsFired < n) {
      final landing = _cardStart(_hapticsFired) + _cardSpan * 0.5;
      if (_entry.value >= landing) {
        // Intensidad BAJA (una por tarjeta) — la fuerte es la del confeti.
        HapticsService.light();
        _hapticsFired++;
      } else {
        break;
      }
    }
  }

  void _onDragUpdate(DragUpdateDetails d, double h) {
    if (_locked) return;
    // Divisor grande => el oleaje sigue al dedo casi 1:1 y hace falta más
    // distancia de arrastre para avanzar la transición.
    final delta = -(d.primaryDelta ?? 0) / (h * 2.2);
    _reveal.value = (_reveal.value + delta).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_locked) return;
    final v = d.primaryVelocity ?? 0;
    // Hace falta arrastrar bastante (o un impulso claro) para confirmar.
    if (_reveal.value > 0.34 || v < -1100) {
      _locked = true;
      _reveal.animateTo(1,
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic);
    } else {
      _reveal.animateBack(0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final first =
        widget.name.isNotEmpty ? widget.name.split(' ').first : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
          animation:
              Listenable.merge([_entry, _phase, _reveal, _tail, _hintCtrl]),
          builder: (context, _) {
            final reveal = _reveal.value;
            final tail = _tail.value;
            // El contenido se desvanece a medida que sube el oleaje.
            final contentOpacity = (1 - reveal * 1.8).clamp(0.0, 1.0);
            return Stack(
              children: [
                // Contenido (resumen).
                Positioned.fill(
                  child: Opacity(
                    opacity: contentOpacity,
                    child: SafeArea(
                      child: Padding(
                        // Sin Center: el header (avatar+nombre+@) queda FIJO
                        // arriba y las tarjetas fluyen debajo sin desplazarlo.
                        padding: const EdgeInsets.fromLTRB(28, 36, 28, 160),
                        child: SingleChildScrollView(
                          child: _buildContent(first),
                        ),
                      ),
                    ),
                  ),
                ),
                // Confeti (se desvanece con la subida).
                Positioned.fill(
                  child: Opacity(
                    opacity: contentOpacity,
                    child: ConfettiOverlay(play: _play),
                  ),
                ),
                // Oleaje de coral (multi-capa) que sube y sale por arriba.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _WavePainter(
                        phase: _phase.value,
                        reveal: reveal,
                        tail: tail,
                      ),
                    ),
                  ),
                ),
                // Indicación de deslizar (sobre el oleaje), se oculta al subir.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 40,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - reveal * 3).clamp(0.0, 1.0),
                      child: _swipeHint(),
                    ),
                  ),
                ),
                // Captador del gesto: SOLO en la zona inferior (el oleaje), para
                // no chocar con el scroll del resumen. El arrastre continúa
                // aunque el dedo suba fuera de esta zona.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 300,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) => _onDragUpdate(d, h),
                    onVerticalDragEnd: _onDragEnd,
                  ),
                ),
              ],
            );
          },
      ),
    );
  }

  Widget _buildContent(String? first) {
    final avatarScale = _stage(0.0, 0.45, Curves.elasticOut).clamp(0.0, 1.25);
    final headStage = _stage(0.22, 0.55, Curves.easeOutCubic);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar con insignia de check.
        Transform.scale(
          scale: avatarScale,
          child: SizedBox(
            width: 116,
            height: 116,
            child: Stack(
              children: [
                Container(
                  width: 116,
                  height: 116,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: Image.network(
                          AppConfig.avatarUrl(widget.avatarId),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.person,
                                color: AppColors.primary, size: 48),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.background, width: 3),
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Título + usuario.
        Opacity(
          opacity: headStage,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - headStage)),
            child: Column(
              children: [
                Text(
                  first != null ? '¡Listo, $first!' : '¡Todo listo!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                if (widget.username.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('@${widget.username}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600])),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Resumen de datos, escalonado y bouncy.
        for (var i = 0; i < widget.items.length; i++) ...[
          _summaryRow(widget.items[i], i),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _summaryRow(_SummaryItem item, int index) {
    // Ventanas dentro de [0,1] (hasta 4 tarjetas) para que la última también
    // llegue a su sitio (antes se quedaba pillada pasada a la derecha). Misma
    // fórmula que usa _maybeHaptic para disparar la vibración en el momento
    // justo en el que la tarjeta se solidifica.
    final start = _cardStart(index);
    final end = start + _cardSpan;
    // Rebote extremo para el movimiento; progreso lineal para opacidad y brillo.
    final tPos = _stage(start, end, Curves.elasticOut); // puede pasar de 1
    final sp = _stage(start, end, Curves.linear);
    final op = (sp / 0.16).clamp(0.0, 1.0);
    if (op <= 0.0) return const SizedBox(height: 0);
    // Entra desde la IZQUIERDA; elasticOut hace que se pase y vuelva (goo).
    final dx = 72 * (tPos - 1);
    final scale = 0.7 + 0.3 * tPos; // pequeña -> se hincha -> asienta (goo)
    // Brillo momentáneo que barre al aterrizar.
    final flash = (1 - (sp - 0.55).abs() * 3.6).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: op,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
                // Resplandor coral que destella al aterrizar.
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5 * flash),
                  blurRadius: 22 * flash,
                  spreadRadius: 1.5 * flash,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    color: Colors.white,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(item.icon,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Barrido de brillo diagonal (izquierda -> derecha).
                  if (flash > 0.02)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Transform.rotate(
                          angle: 0.4,
                          child: FractionallySizedBox(
                            alignment: Alignment(-1.3 + 2.6 * sp, 0),
                            widthFactor: 0.3,
                            heightFactor: 2.4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.55 * flash),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Solo la flecha (sin texto), apareciendo de vez en cuando: dentro de cada
  // vuelta de _hintCtrl hay una ventana visible (fade in, espera, fade out) y
  // el resto del ciclo está completamente ausente.
  Widget _swipeHint() {
    final bounce = math.sin(_phase.value * 2 * math.pi) * 5;
    final t = _hintCtrl.value;
    double opacity;
    if (t < 0.10) {
      opacity = t / 0.10;
    } else if (t < 0.35) {
      opacity = 1.0;
    } else if (t < 0.45) {
      opacity = 1 - (t - 0.35) / 0.10;
    } else {
      opacity = 0.0;
    }
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, -bounce.abs()),
        child: const Icon(Icons.keyboard_arrow_up_rounded,
            color: Colors.white, size: 34),
      ),
    );
  }
}

/// Pinta el "oleaje" de coral multi-capa. Cada capa es una banda con borde
/// ONDULADO arriba y abajo, y avanza a distinta velocidad/dirección para dar
/// sensación de agua viva. [phase] 0..1 (fase continua, en "vueltas"),
/// [reveal] 0..1: 0 = olas abajo; sube cubriendo y luego sale por arriba
/// dejando ver el borde ondulado inferior según se desliza. [tail] 0..1: fase
/// final (tras reveal=1) en la que las burbujas rezagadas terminan de cruzar
/// la parte superior, cada una con su propio retraso.
class _WavePainter extends CustomPainter {
  final double phase;
  final double reveal;
  final double tail;

  _WavePainter({required this.phase, required this.reveal, this.tail = 0});

  // Por capa (de atrás hacia delante; la última es el relleno opaco):
  // color, opacidad, offset cresta, offset base, amplitud, ciclos/vuelta
  // (ENTERO => bucle sin saltos; signo = dirección), factor de longitud de onda.
  static const _layers = [
    [0xFFFFC7B0, 0.45, -26.0, 28.0, 17.0, 2.0, 1.2],
    [0xFFFFAB91, 0.62, -15.0, 16.0, 14.0, -3.0, 1.7],
    [0xFFF08D75, 0.85, -6.0, 7.0, 11.0, 1.0, 2.3],
    [0xFFE8A598, 1.0, 0.0, 0.0, 10.0, -2.0, 1.0],
  ];

  static const _bubbleColors = [
    0xFFFFC7B0,
    0xFFFFAB91,
    0xFFF08D75,
    0xFFE8A598,
  ];

  // Se generan una sola vez (deterministas) para que no salten entre frames.
  static final List<_Bubble> _bubbles = List.generate(18, (i) {
    final rnd = math.Random(i * 13 + 5);
    return _Bubble(
      x: rnd.nextDouble(),
      offset: rnd.nextDouble(),
      speed: (1 + rnd.nextInt(2)).toDouble(), // 1 o 2
      r: 3 + rnd.nextDouble() * 6,
      drift: 4 + rnd.nextDouble() * 9,
      // Cada burbuja sigue al oleaje a una fracción distinta de su velocidad
      // (siempre <1 => van más lentas y se quedan atrás, con variabilidad).
      follow: 0.55 + rnd.nextDouble() * 0.32, // 0.55..0.87
      // Retraso para arrancar su tramo final (fase "tail"): con esto cruzan
      // la parte superior escalonadas, no todas a la vez.
      chaseDelay: rnd.nextDouble() * 0.5, // 0..0.5
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Movimiento LINEAL respecto a [reveal]: así, al arrastrar, el oleaje
    // acompaña al dedo a ritmo constante (sin aceleraciones extrañas). La banda
    // es más alta que la pantalla para cubrir y luego salir por arriba.
    final bandTop = _lerp(h - 132, -(h + 300), reveal);
    final bandHeight = h + 260;

    for (final l in _layers) {
      final color = Color(l[0] as int).withValues(alpha: l[1] as double);
      final topOff = l[2] as double;
      final botOff = l[3] as double;
      final amp = l[4] as double;
      final cycles = l[5] as double;
      final lenF = l[6] as double;
      final k = (2 * math.pi) / (w / lenF);
      // Fases temporales distintas para arriba y abajo (más "vida").
      final tPhaseTop = phase * cycles * 2 * math.pi;
      final tPhaseBot = phase * cycles * 2 * math.pi + 1.9;

      double topY(double x) =>
          bandTop + topOff + amp * math.sin(x * k + tPhaseTop);
      double botY(double x) =>
          bandTop + bandHeight + botOff + amp * 0.85 * math.sin(x * k + tPhaseBot);

      final path = Path()..moveTo(0, topY(0));
      for (double x = 6; x <= w; x += 6) {
        path.lineTo(x, topY(x));
      }
      path.lineTo(w, botY(w));
      for (double x = w - 6; x >= 0; x -= 6) {
        path.lineTo(x, botY(x));
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    _paintBubbles(canvas, w, h);
  }

  // Burbujas circulares (goo) que suben con el oleaje pero MÁS LENTAS (se
  // quedan atrás, cada una a su ritmo). Al llegar reveal=1 el oleaje ya salió
  // de la pantalla; las burbujas rezagadas siguen su recorrido en la fase
  // [tail], escalonadas, hasta que TODAS cruzan la parte superior — solo
  // entonces se considera terminada la celebración (ver [_maybeFinish]).
  void _paintBubbles(Canvas canvas, double w, double h) {
    // Grupo SUPERIOR: nace en la cresta del oleaje y viaja con ella (rezagado).
    if (reveal > 0.001 || tail > 0.001) {
      final entryGate = (reveal * 20).clamp(0.0, 1.0);
      _drawBubbles(canvas, w,
          fromY: h - 118,
          toY: -(h + 260),
          span: 78,
          below: false,
          entryGate: entryGate,
          seedShift: 0);
    }

    // Grupo INFERIOR: en la sección que se revela al subir el oleaje, junto a
    // su borde inferior ondulado (que asciende dejando ver el fondo).
    if (reveal > 0.40 || tail > 0.001) {
      final entryGate = reveal < 1.0
          ? ((reveal - 0.40) / 0.14).clamp(0.0, 1.0)
          : 1.0;
      _drawBubbles(canvas, w,
          fromY: 2 * h + 128,
          toY: -60,
          span: 92,
          below: true,
          entryGate: entryGate,
          seedShift: 9);
    }
  }

  /// Progreso 0..1 de la burbuja en su recorrido TOTAL (misma escala que
  /// [reveal]): mientras se arrastra, avanza a `follow` de la velocidad de la
  /// ola (más lenta, se queda atrás); al soltar y entrar en la fase [tail],
  /// completa el tramo que le falta con su propio retraso (`chaseDelay`), de
  /// modo que todas acaban cruzando la parte de arriba, escalonadas.
  double _bubbleProgress(_Bubble b) {
    if (reveal < 1.0) return reveal * b.follow;
    final local =
        Interval(b.chaseDelay, 1.0, curve: Curves.easeInQuad).transform(tail);
    return b.follow + (1 - b.follow) * local;
  }

  void _drawBubbles(Canvas canvas, double w,
      {required double fromY,
      required double toY,
      required double span,
      required bool below,
      required double entryGate,
      required int seedShift}) {
    final n = _bubbles.length;
    for (var i = 0; i < n; i++) {
      final b = _bubbles[(i + seedShift) % n];
      final progress = _bubbleProgress(b);
      final anchorY = _lerp(fromY, toY, progress);
      final life = (phase * b.speed + b.offset) % 1.0;
      final env = math.sin(life * math.pi); // 0..1..0 (aparece y desaparece)
      if (env <= 0.02) continue;
      // Superior: flotan sobre la cresta (suben). Inferior: están por debajo
      // del borde y ascienden hacia él (sección revelada).
      final by = below ? anchorY + (1 - life) * span : anchorY - life * span;
      final bx = b.x * w + math.sin(life * math.pi * 2 + b.offset * 6) * b.drift;
      final r = b.r * (0.35 + 0.65 * env);
      // Se desvanecen justo al terminar de cruzar (evita el "pop" al salir).
      final exitFade =
          progress < 0.88 ? 1.0 : (1 - (progress - 0.88) / 0.12).clamp(0.0, 1.0);
      final op = env * 0.5 * entryGate * exitFade;
      if (op <= 0.01) continue;
      final color = Color(_bubbleColors[(i + seedShift) % _bubbleColors.length]);
      canvas.drawCircle(
          Offset(bx, by), r, Paint()..color = color.withValues(alpha: op));
      // Brillo tipo burbuja (goo).
      canvas.drawCircle(
        Offset(bx - r * 0.3, by - r * 0.32),
        r * 0.34,
        Paint()..color = Colors.white.withValues(alpha: op * 0.7),
      );
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.phase != phase || old.reveal != reveal || old.tail != tail;
}

/// Una burbuja del oleaje. [speed] es ENTERO (1/2) para que el ciclo de subida
/// encaje con la vuelta de la fase y no dé saltos.
class _Bubble {
  final double x; // 0..1 (fracción del ancho)
  final double offset; // desfase 0..1
  final double speed; // ciclos de subida por vuelta (entero)
  final double r; // radio máximo
  final double drift; // amplitud del bamboleo horizontal
  final double follow; // <1: fracción de la velocidad del oleaje (van más lentas)
  final double chaseDelay; // 0..~0.5: retraso al arrancar el tramo final
  const _Bubble({
    required this.x,
    required this.offset,
    required this.speed,
    required this.r,
    required this.drift,
    required this.follow,
    required this.chaseDelay,
  });
}

/// Hoja inferior con buscador para elegir de una lista larga.
class _PickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final VoidCallback onClear;
  final _PickerExtra? extraAction;

  const _PickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.onSelected,
    required this.onClear,
    this.extraAction,
  });

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((e) => widget.labelOf(e).toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                    ),
                    TextButton(
                      onPressed: () {
                        widget.onClear();
                        Navigator.pop(context);
                      },
                      child: const Text('Quitar'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (widget.extraAction != null)
                      ListTile(
                        leading: const Icon(Icons.add_circle_outline,
                            color: AppColors.primary),
                        title: Text(widget.extraAction!.label,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                        onTap: () {
                          widget.extraAction!.onTap();
                          Navigator.pop(context);
                        },
                      ),
                    for (final item in filtered)
                      ListTile(
                        title: Text(widget.labelOf(item)),
                        onTap: () {
                          widget.onSelected(item);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
