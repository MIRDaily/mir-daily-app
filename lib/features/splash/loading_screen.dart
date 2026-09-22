import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_warmup.dart';
import '../../core/theme/app_theme.dart';
import 'intro_music.dart';

/// Pantalla de carga recuperada de v10.5: frases con humor médico, barra de
/// progreso y botón "Continuar" que es el que da paso a la app (hasta que no
/// se pulsa, no se abre nada). Fondo de células cayendo en parallax.
///
/// La barra mide trabajo real ([AppWarmup]): el sobre de hoy y los sprites del
/// juego se piden aquí, y "Continuar" no aparece hasta que están. Así el clic
/// entra en una app ya cargada en vez de arrancar entonces la espera.
class LoadingScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final AppWarmup warmup;

  const LoadingScreen({
    super.key,
    required this.onContinue,
    required this.warmup,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _progressController;
  late AnimationController _textController;
  late AnimationController _buttonController;
  late Animation<double> _logoAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _buttonFadeAnimation;

  final List<String> _phrases = [
    'Dando clase a los linfocitos...',
    'Dando de comer a las plaquetas...',
    'No olvides acariciar a tu gato...',
    'Rellenando tanques de serotonina...',
    'Convenciendo a los eritrocitos...',
    'Negociando con las neuronas...',
    'Hidratando el hipotálamo...',
    'Motivando a los macrófagos...',
    'Peinando las vellosidades intestinales...',
    'Calibrando el ojo clínico...',
    'Afilando el fonendoscopio...',
    'Despertando a la médula ósea...',
  ];

  late String _currentPhrase;
  int _phraseIndex = 0;
  Timer? _phraseTimer;
  bool _showButton = false;

  /// Manda la salida: caída de las células, disolución del logo y desaparición
  /// del texto. Al terminar, cede el paso a la app.
  late AnimationController _exitController;

  /// Se ha pulsado "Continuar". Evita repetir la salida si se vuelve a pulsar.
  bool _leaving = false;

  /// Congela el fondo. Solo al final de la cascada, cuando ya no queda ninguna
  /// célula en pantalla que animar.
  bool _frozen = false;

  /// MOCKUP de intro con música. Ver `intro_music.dart` para quitarlo.
  ///
  /// La pantalla NO es su dueña: la música tiene que seguir sonando durante el
  /// onboarding, que ya no es esta pantalla. Quien la crea y la suelta es el
  /// provider de `main.dart`, y quien la apaga es `_OnboardingGate` cuando
  /// arranca la app de verdad.
  late final IntroMusic _music = context.read<IntroMusic>();

  @override
  void initState() {
    super.initState();

    _music.start();

    _phraseIndex = Random().nextInt(_phrases.length);
    _currentPhrase = _phrases[_phraseIndex];

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _logoAnimation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // Marca el suelo de tiempo, no el trabajo: su value es "cuánto llevamos de
    // la espera mínima". Lineal a propósito, porque ahora la barra significa
    // algo. El progreso real lo pone el warmup y la barra pinta el menor de los
    // dos (ver _buildProgressBar).
    _progressController = AnimationController(
      vsync: this,
      duration: widget.warmup.minimumDuration,
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _textFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _buttonFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeOut),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _exitController.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      // El fondo ya está vacío: se apaga lo que quede animando y entra la app.
      setState(() => _frozen = true);
      _logoController.stop();
      widget.onContinue();
    });

    _progressController.forward();
    _textController.forward();

    _phraseTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _changePhrase();
    });

    widget.warmup.ready.addListener(_onWarmupReady);
    // El listener solo avisa de cambios: si la precarga ya estuviese hecha, sin
    // esto el botón no llegaría a aparecer nunca.
    if (widget.warmup.ready.value) {
      _showButton = true;
      _buttonController.value = 1;
    }
    // Empieza a cargar de verdad en cuanto esta pantalla está en pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.warmup.start());
  }

  /// Todo listo (o agotada la espera): se ofrece el paso a la app.
  void _onWarmupReady() {
    if (!mounted || !widget.warmup.ready.value || _showButton) return;
    setState(() => _showButton = true);
    _buttonController.forward();
  }

  void _handleContinue() {
    if (_leaving) return; // el botón sigue en pantalla durante la salida
    setState(() => _leaving = true);
    _phraseTimer?.cancel();

    // La intro NO se apaga aquí. Si al usuario le toca onboarding, la música
    // continúa durante él; el apagado lo hace `_OnboardingGate` cuando entra
    // la app de verdad.

    // La app entra sola al acabar (ver el listener de _exitController).
    _exitController.forward();
  }

  void _changePhrase() {
    if (!_showButton) {
      _textController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _phraseIndex = (_phraseIndex + 1) % _phrases.length;
            _currentPhrase = _phrases[_phraseIndex];
          });
          _textController.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.warmup.ready.removeListener(_onWarmupReady);
    _logoController.dispose();
    _progressController.dispose();
    _textController.dispose();
    _buttonController.dispose();
    _exitController.dispose();
    _phraseTimer?.cancel();
    // La música NO se suelta aquí: sigue durante el onboarding. La suelta el
    // provider que la creó.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // En reposo _exitController no anima, así que esto no cuesta nada hasta
    // que empieza la salida.
    return AnimatedBuilder(
      animation: _exitController,
      builder: (context, _) {
        final t = _exitController.value;
        // El texto y la barra se van enseguida; el logo aguanta y se disuelve
        // mientras la cascada barre el fondo.
        final uiGone = (t / 0.3).clamp(0.0, 1.0);
        final logoGone = Curves.easeIn.transform((t / 0.55).clamp(0.0, 1.0));

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              ParticlesBackground(
                animate: !_frozen,
                // Velocidad extra de caída, de 0 a 6 pantallas por segundo. Al
                // ir con easeIn las células se dejan caer y luego se precipitan,
                // en vez de arrancar de golpe.
                fallBoost: 6 * Curves.easeIn.transform(t),
              ),
              // MOCKUP de intro con música: poder callarla sin salir de aquí.
              // Se estudia en bibliotecas y de madrugada; una app que suena
              // sola y no se puede callar en el sitio es una app que se
              // desinstala. Se va con el resto de la interfaz al salir.
              Positioned(
                top: 4,
                right: 4,
                child: Opacity(
                  opacity: 1 - uiGone,
                  child: SafeArea(child: _buildMuteButton()),
                ),
              ),
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      _buildLogo(logoGone),
                      const Spacer(flex: 2),
                      Opacity(
                        opacity: 1 - uiGone,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_showButton)
                              FadeTransition(
                                opacity: _textFadeAnimation,
                                child: SizedBox(
                                  height: 24,
                                  child: Text(
                                    _currentPhrase,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary
                                          .withOpacity(0.7),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 50),
                              // En tablet el botón/​barra no se estira a lo
                              // ancho: se queda a medida de móvil y centrado.
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 360),
                                child: _showButton
                                    ? _buildContinueButton()
                                    : _buildProgressBar(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// [gone] va de 0 a 1 durante la salida. El logo sube un poco y se disuelve
  /// justo cuando todo lo demás se precipita hacia abajo: el contraste deja el
  /// centro despejado, que es por donde va a asomar el sobre.
  Widget _buildLogo(double gone) {
    return AnimatedBuilder(
      animation: _logoAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _logoAnimation.value - 14 * gone),
          child: Transform.scale(scale: 1 + 0.05 * gone, child: child),
        );
      },
      child: Opacity(
        opacity: 1 - gone,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2),
                blurRadius: 60,
                spreadRadius: 10,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: AppColors.primary.withOpacity(0.1),
                blurRadius: 100,
                spreadRadius: 20,
                offset: const Offset(0, 25),
              ),
            ],
          ),
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return RadialGradient(
                center: Alignment.center,
                radius: 0.9,
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.white.withOpacity(0.8),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7, 0.85, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: Image(
              image: const AssetImage(LoadingScreenImages.logo),
              width: 500,
              fit: BoxFit.contain,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// MOCKUP de intro con música. Ver `intro_music.dart` para quitarlo.
  Widget _buildMuteButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: _music.silenciada,
      builder: (context, silenciada, _) {
        return IconButton(
          onPressed: _music.toggleSilencio,
          tooltip: silenciada ? 'Activar la música' : 'Silenciar la música',
          iconSize: 20,
          color: AppColors.textSecondary.withOpacity(0.55),
          icon: Icon(
            silenciada ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          ),
        );
      },
    );
  }

  Widget _buildContinueButton() {
    return FadeTransition(
      opacity: _buttonFadeAnimation,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _handleContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 4,
            shadowColor: AppColors.primary.withOpacity(0.4),
          ),
          child: const Text(
            'Continuar',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  /// La barra avanza con el MENOR de dos progresos: el del trabajo real y el de
  /// la espera mínima. Con buena red manda el tiempo (sube fluida hasta el
  /// suelo en vez de plantarse en 100% esperando); con red mala manda el
  /// trabajo, y entonces lo que se ve es lo que de verdad queda por cargar.
  Widget _buildProgressBar() {
    return ValueListenableBuilder<double>(
      valueListenable: widget.warmup.progress,
      builder: (context, work, _) {
        // El trabajo salta por tareas (una acaba, +5%); el tween lima el salto.
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: work),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          builder: (context, smoothWork, _) {
            return AnimatedBuilder(
              animation: _progressController,
              builder: (context, _) {
                final value = min(_progressController.value, smoothWork);
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: value,
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(value * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withOpacity(0.6),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Las imágenes de esta pantalla, con su decodificación acotada y listas para
/// precargar.
///
/// Los PNG de las células son de ~1000x1000 y se pintan a 50-200: sin acotar,
/// Flutter descomprime el original entero (4 MB en memoria cada uno) y solo
/// después lo escala. Eran ~18 MB y cuatro millones de píxeles en los primeros
/// frames, y cada célula aparecía de golpe en cuanto acababa la suya.
class LoadingScreenImages {
  const LoadingScreenImages._();

  static const String logo = 'assets/images/logo_mirdaily.png';

  static const List<String> particles = [
    'assets/images/rbc.png',
    'assets/images/neutrophil.png',
    'assets/images/Virus.png',
    'assets/images/antibody.png',
    'assets/images/Bacteriofago.png',
  ];

  /// Los bichos animados del fondo. Un .lottie es un zip con el JSON dentro (y
  /// con sus PNG, en el caso de la bacteria) que el paquete abre solo, sin
  /// tener que descomprimir nada a mano. A diferencia de las células, no son
  /// imágenes: se pintan con [Lottie].
  static const String bacteria = 'assets/animations/bacteria.lottie';
  static const String covid = 'assets/animations/covid.lottie';

  /// Lo que hay que precargar de los bichos. Sale del catálogo de [Bicho] para
  /// no llevar la misma lista en dos sitios.
  static List<String> get animaciones =>
      [for (final bicho in Bicho.todos) bicho.asset];

  /// Ancho al que se decodifican las células. Da de sobra para la capa nítida
  /// (110 puntos a densidad 3) y las capas grandes ya van desenfocadas, así que
  /// no se les nota. Los archivos que ya son menores se quedan como están.
  static const int _particleDecodeWidth = 400;

  /// El proveedor de una célula. Tiene que salir de aquí en todos los sitios:
  /// la caché de imágenes distingue por ancho de decodificación, así que
  /// precargar con uno y pintar con otro se decodificaría dos veces.
  static ImageProvider particle(String path) =>
      ResizeImage(AssetImage(path), width: _particleDecodeWidth);

  /// Deja todo decodificado antes de que la pantalla aparezca. Se lanza en
  /// main() sin esperarla: lo que importa es que empiece cuanto antes.
  static Future<void> precache() {
    return Future.wait([
      ...particles.map((p) => _resolve(particle(p))),
      // El logo se pinta casi al tamaño del archivo, así que no se acota: solo
      // se adelanta su carga.
      _resolve(const AssetImage(logo)),
      ...animaciones.map(_precacheLottie),
    ]);
  }

  /// Deja un bicho montado en la caché de Lottie (`Lottie.cache`), que es la
  /// misma de la que tira `Lottie.asset`. Abrir el zip y decodificar lo que
  /// traiga dentro (la bacteria son 21 PNG) cuesta lo suyo, y hacerlo cuando le
  /// toca aparecer sería justo en medio de la caída: o llega tarde o da un
  /// tirón.
  static Future<void> _precacheLottie(String asset) {
    // Que falte un bicho no puede tumbar el arranque (igual que las células):
    // si no carga, el fondo se queda sin él y ya está.
    return AssetLottie(asset).load().then<void>((_) {}, onError: (_, __) {});
  }

  static Future<void> _resolve(ImageProvider provider) {
    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);

    late final ImageStreamListener listener;
    void finish() {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    }

    listener = ImageStreamListener(
      (_, __) => finish(),
      // Que falte una célula no puede tumbar el arranque.
      onError: (_, __) => finish(),
    );
    stream.addListener(listener);
    return completer.future;
  }
}

// Widget de partículas cayendo en 3 capas (parallax)
class ParticlesBackground extends StatefulWidget {
  /// A false se congela la caída. Se usa al salir a la app, para no gastar CPU
  /// en el fundido de un fondo que ya se está yendo.
  final bool animate;

  /// Velocidad de caída extra (pantallas por segundo) que se suma a la propia
  /// de cada célula. Por encima de cero deja de reponerlas, así que subirlo
  /// progresivamente vacía el fondo: es la salida en cascada.
  final double fallBoost;

  const ParticlesBackground({
    super.key,
    this.animate = true,
    this.fallBoost = 0,
  });

  @override
  State<ParticlesBackground> createState() => _ParticlesBackgroundState();
}

class _ParticlesBackgroundState extends State<ParticlesBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  /// El reloj de cada bicho, aparte del de la caída: cada uno se mueve a su
  /// ritmo (su [Bicho.speed]), no al de las células. La duración se les pone
  /// al cargar el .lottie, que es cuando se sabe cuánto dura una vuelta.
  final Map<Bicho, AnimationController> _relojes = {};
  final List<Particle> _particles = [];
  final Random _random = Random();
  DateTime _lastUpdate = DateTime.now();

  final List<String> _commonImages = [
    'assets/images/rbc.png',
    'assets/images/neutrophil.png',
    'assets/images/Virus.png',
    'assets/images/antibody.png',
  ];

  final String _rareImage = 'assets/images/Bacteriofago.png';

  /// Cada bicho tiene sus plazas ([Bicho.max]) y cada plaza se juega a cara o
  /// cruz. Medido sobre 200 arranques: caen 1,4 bacterias y 2 viriones de
  /// media, hay 7 como mucho, y todavía queda un 16% de arranques sin bacteria
  /// y un 6% sin virión. Bajarlo a 1 llena todas las plazas siempre, que es la
  /// forma de verlos mientras se afinan.
  static const int _bichoOdds = 2;

  /// Lo que giran las células sobre sí mismas mientras caen. Es la vara de
  /// medir del giro de los bichos, que cada uno lleva el suyo ([Bicho.spin]).
  static const double _spinCelulas = 0.03;

  final Map<int, LayerConfig> _layerConfigs = {
    0: LayerConfig(
        count: 3,
        speedRange: [0.03, 0.05],
        sizeRange: [50, 70],
        blur: 2.5,
        opacity: 0.5),
    1: LayerConfig(
        count: 3,
        speedRange: [0.05, 0.08],
        sizeRange: [80, 110],
        blur: 0,
        opacity: 0.8),
    2: LayerConfig(
        count: 2,
        speedRange: [0.08, 0.12],
        sizeRange: [140, 200],
        blur: 3,
        opacity: 0.6),
  };

  /// Con qué peso cae un bicho en cada capa. Las células se reparten 3/3/2,
  /// pero los bichos tiran a la nítida a propósito: en las otras dos salen
  /// desenfocados y ahí no se les aprecia la animación, que es lo que se ha
  /// venido a ver. Peor aún, el tamaño de la capa los lleva a los extremos —
  /// en la del fondo el virión es una mota de 15 puntos y en la de delante la
  /// bacteria es un borrón de 120. Siguen cayendo en las tres para que también
  /// tengan profundidad, pero de guarnición: dos de cada tres van a la nítida.
  static const Map<int, int> _pesoDeCapa = {0: 1, 1: 4, 2: 1};

  /// La capa que le toca a un bicho, según [_pesoDeCapa].
  int _sorteaCapa() {
    final total = _pesoDeCapa.values.fold<int>(0, (suma, peso) => suma + peso);
    var dado = _random.nextInt(total);
    for (final capa in _pesoDeCapa.entries) {
      dado -= capa.value;
      if (dado < 0) return capa.key;
    }
    return _pesoDeCapa.keys.last;
  }

  String _getRandomImage() {
    if (_random.nextInt(15) == 0) {
      return _rareImage;
    }
    return _commonImages[_random.nextInt(_commonImages.length)];
  }

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.animate) _controller.repeat();

    // Sin duración todavía: se la pone _onBichoLoaded, y hasta entonces no hay
    // ningún bicho en pantalla al que mover.
    for (final bicho in Bicho.todos) {
      _relojes[bicho] = AnimationController(vsync: this);
    }

    _layerConfigs.forEach((layer, config) {
      for (int i = 0; i < config.count; i++) {
        _particles.add(_createParticle(layer, config));
      }
    });

    // Los bichos van con plazas propias, aparte del cupo de células: así subir
    // su número no vacía de células el fondo. Por lo demás son unas células
    // más: caen en las mismas capas (con su propio reparto, ver [_pesoDeCapa])
    // y se llevan de la suya lo mismo que ellas — el tamaño, la velocidad, el
    // desenfoque y la transparencia.
    for (final bicho in Bicho.todos) {
      for (var plaza = 0; plaza < bicho.max; plaza++) {
        if (_random.nextInt(_bichoOdds) != 0) continue;
        final capa = _sorteaCapa();
        _particles
            .add(_createParticle(capa, _layerConfigs[capa]!, bicho: bicho));
      }
    }

    _particles.sort((a, b) => a.layer.compareTo(b.layer));
  }

  @override
  void didUpdateWidget(ParticlesBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == _controller.isAnimating) return;
    if (widget.animate) {
      // Sin esto, el delta acumulado mientras estuvo parado teletransportaría
      // las partículas en el primer frame.
      _lastUpdate = DateTime.now();
      _controller.repeat();
      for (final reloj in _relojes.values) {
        if (reloj.duration != null) reloj.repeat();
      }
    } else {
      _controller.stop();
      for (final reloj in _relojes.values) {
        reloj.stop();
      }
    }
  }

  /// El .lottie ya está montado y dice cuánto dura de verdad una vuelta. Aquí
  /// es donde se le aplica su [Bicho.speed]: el reloj del bicho se ajusta a
  /// esa fracción y empieza a girar.
  void _onBichoLoaded(Bicho bicho, LottieComposition composition) {
    // El .lottie puede acabar de cargar cuando la pantalla ya se ha ido (la
    // cascada de salida, o volver al login): entonces los relojes están
    // sueltos y tocarlos revienta.
    if (!mounted) return;
    final reloj = _relojes[bicho]!;
    final vuelta = composition.duration * (1 / bicho.speed);
    // Salta cada vez que aparece ese bicho, pero su composición es siempre la
    // misma: a partir de la primera no hay nada que cambiar ni que reiniciar.
    if (reloj.duration == vuelta) return;
    reloj.duration = vuelta;
    if (widget.animate) reloj.repeat();
  }

  /// Una célula (o, con [bicho], uno de los animados) de la capa [layer].
  Particle _createParticle(int layer, LayerConfig config,
      {bool startOffScreen = false, Bicho? bicho}) {
    final speed = config.speedRange[0] +
        _random.nextDouble() * (config.speedRange[1] - config.speedRange[0]);
    var size = config.sizeRange[0] +
        _random.nextDouble() * (config.sizeRange[1] - config.sizeRange[0]);

    final x = 0.2 + _random.nextDouble() * 0.6;

    if (bicho != null) size = bicho.boxFor(size);

    return Particle(
      x: x,
      y: startOffScreen ? -0.15 : _random.nextDouble() * 1.3 - 0.15,
      size: size,
      speed: speed,
      rotation: _random.nextDouble() * 2 * pi,
      // Cada uno a lo suyo: las células dan vueltas al caer y los bichos tienen
      // el giro que les pega (ver [Bicho.spin]).
      rotationSpeed:
          (_random.nextDouble() - 0.5) * (bicho?.spin ?? _spinCelulas),
      drift: (_random.nextDouble() - 0.5) * 0.001,
      layer: layer,
      imagePath: bicho?.asset ?? _getRandomImage(),
      bicho: bicho,
      blur: config.blur,
      opacity: config.opacity,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final reloj in _relojes.values) {
      reloj.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final now = DateTime.now();
        final deltaTime = now.difference(_lastUpdate).inMilliseconds / 1000.0;
        _lastUpdate = now;

        for (int i = 0; i < _particles.length; i++) {
          final p = _particles[i];
          p.y += (p.speed + widget.fallBoost) * deltaTime;
          p.x += p.drift * deltaTime * 30;
          p.rotation += p.rotationSpeed * deltaTime * 30;

          if (p.y > 1.15) {
            // En la cascada no se repone ninguna: la pantalla tiene que quedar
            // limpia para que la app entre sobre un fondo vacío.
            if (widget.fallBoost > 0) continue;
            final config = _layerConfigs[p.layer]!;
            // La plaza se repone con lo que era: un bicho vuelve a ser ese
            // bicho y una célula, una célula. Si no, el número de bichos del
            // fondo iría cambiando solo según quién se cayera antes.
            _particles[i] = _createParticle(p.layer, config,
                startOffScreen: true, bicho: p.bicho);
          }
        }

        return Stack(
          children: _particles.map((p) => _buildParticle(p)).toList(),
        );
      },
    );
  }

  Widget _buildParticle(Particle p) {
    final image = _buildParticleImage(p);

    return Positioned(
      left: p.x * MediaQuery.of(context).size.width - p.size / 2,
      top: p.y * MediaQuery.of(context).size.height - p.size / 2,
      child: Transform.rotate(
        angle: p.rotation,
        child: Opacity(
          // Los bichos llevan velo propio encima del de su capa (ver
          // [Bicho.opacity]); las células se quedan con el de la capa y ya.
          opacity: p.opacity * (p.bicho?.opacity ?? 1),
          child: p.blur > 0
              ? ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: p.blur, sigmaY: p.blur),
                  child: image,
                )
              : image,
        ),
      ),
    );
  }

  /// Un bicho animado: el mismo hueco que una célula, pero pintado con Lottie.
  ///
  /// Sale de `Lottie.cache` (la llenó la precarga de main), así que aquí no hay
  /// zip que abrir ni PNG que decodificar. Quien lo mueve es su reloj de
  /// [_relojes], no el `animate` del widget: con un controlador propio es donde
  /// se le puede cambiar la velocidad.
  Widget _buildBicho(Particle p, Bicho bicho) {
    return Lottie.asset(
      bicho.asset,
      controller: _relojes[bicho],
      onLoaded: (composition) => _onBichoLoaded(bicho, composition),
      width: p.size,
      height: p.size,
      fit: BoxFit.contain,
      frameRate: bicho.frameRate,
      delegates: bicho.delegates,
      // Si el .lottie no llegase a cargar, el fondo sigue con sus células.
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buildParticleImage(Particle p) {
    final bicho = p.bicho;
    if (bicho != null) return _buildBicho(p, bicho);

    return Image(
      image: LoadingScreenImages.particle(p.imagePath),
      width: p.size,
      height: p.size,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        // Con la precarga hecha salen de caché y entran ya pintadas. El fundido
        // es la red de seguridad: si alguna llega tarde, aparece poco a poco en
        // vez de plantarse de golpe.
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}

class Particle {
  double x;
  double y;
  double size;
  double speed;
  double rotation;
  double rotationSpeed;
  double drift;
  int layer;
  String imagePath;
  double blur;
  double opacity;

  /// Las raras del fondo: en vez de un PNG se pintan con Lottie. Caen igual que
  /// las demás (misma capa, misma velocidad, misma cascada de salida). A null,
  /// esta partícula es una célula normal.
  final Bicho? bicho;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.drift,
    required this.layer,
    required this.imagePath,
    required this.blur,
    required this.opacity,
    this.bicho,
  });
}

/// Uno de los bichos animados del fondo: cae como una célula más, pero en vez
/// de un PNG es un .lottie.
class Bicho {
  const Bicho({
    required this.asset,
    required this.fill,
    required this.scale,
    required this.max,
    required this.spin,
    required this.speed,
    required this.opacity,
    this.delegates,
  });

  /// Los que pueden salir entre las células. Cada uno se juega su aparición por
  /// separado, así que el fondo no lleva siempre los mismos ni los mismos
  /// cuántos.
  static final List<Bicho> todos = [
    const Bicho(
      asset: LoadingScreenImages.bacteria,
      // Lienzo de 596x842 con mucho aire: el bacilo pinta el ~48% central,
      // medido frame a frame.
      fill: 0.48,
      // Un 60% de la célula: unos 45-65 puntos. Es alargado y con flagelo, así
      // que por debajo de ahí deja de leerse como un bicho y pasa a ser una
      // mota.
      scale: 0.6,
      max: 3,
      // Casi sin girar: es un bicho con cabeza y cola, y dando vueltas dejaría
      // de parecer que nada para parecer que lo han tirado.
      spin: 0.008,
      // Viene a 5 s por vuelta y a esa velocidad parece un dibujo quieto: su
      // movimiento es sutil (se ladea, tiemblan los pili) y la pantalla dura
      // unos segundos, así que no da tiempo a verlo.
      speed: 4,
      // Azules y morados de saturación media, sin contorno duro: con un velo
      // suave ya cae dentro del fondo en vez de ir por delante.
      opacity: 0.8,
    ),
    Bicho(
      asset: LoadingScreenImages.covid,
      // Lienzo de 500x500 bastante lleno: el virión pinta el ~73%.
      fill: 0.73,
      // La mitad que la bacteria: ~25-33 puntos. Es compacto y redondo, así que
      // a ese tamaño se sigue leyendo, y en pequeño puede ir en grupo sin
      // comerse el fondo.
      scale: 0.3,
      max: 4,
      // Rodando como una célula más: es redondo y sin arriba ni abajo, así que
      // el giro se le ve en las espículas y no desorienta nada.
      spin: 0.03,
      // Su bucle de 5 s da ya dos vueltas al virión, o sea una cada 2,5 s. A 2x
      // queda en 1,25 s, el mismo pulso que la bacteria.
      speed: 2,
      // El que más velo necesita: rojo saturado y contorno negro grueso, que es
      // justo lo que salta a la vista sobre un fondo de pasteles.
      opacity: 0.65,
      // El virión viene con dos meneos de más en su capa raíz ("Main", de la
      // que cuelga todo lo demás): sube y baja 60 de sus 500 puntos de lienzo,
      // y se ladea de +7° a -7°. Cayendo ya se mueve, y los dos peleaban con la
      // caída. Se le clava esa capa: quieta en el centro y sin ángulo. Lo que
      // sigue vivo es lo de dentro, las espículas. El .lottie no se toca; esto
      // es un retoque en caliente.
      delegates: LottieDelegates(
        values: [
          ValueDelegate.transformPosition(
            const ['Main'],
            value: const Offset(250, 250),
          ),
          ValueDelegate.transformRotation(const ['Main'], value: 0),
        ],
      ),
    ),
  ];

  /// El .lottie, tal cual está en assets.
  final String asset;

  /// Cuánto del lienzo del .lottie pinta de verdad el dibujo. Los lienzos
  /// vienen con aire alrededor, y el tamaño que se le pasa al widget es el del
  /// lienzo: sin descontarlo, el bicho saldría más pequeño de lo que se pide.
  final double fill;

  /// Cuánto se acelera respecto a la velocidad con la que viene animado.
  final double speed;

  /// Retoques sobre la animación tal cual viene, sin tocar el archivo. Aquí se
  /// usan para clavar en su sitio a los que se menean dentro de su lienzo: el
  /// bicho ya se mueve cayendo, y ese meneo pelea con la caída.
  final LottieDelegates? delegates;

  /// Velo propio, que multiplica al de su capa (0,5 el fondo, 0,8 el medio,
  /// 0,6 el de delante). Los bichos vienen con colores más saturados y contorno
  /// negro que las células, que son pasteles pálidos: con la opacidad de la
  /// capa a secas se plantaban delante del fondo en vez de caer dentro de él.
  final double opacity;

  /// Lo que se ve del bicho respecto a una célula de su misma capa. Pequeños al
  /// lado de ellas, que es el contraste que se busca; cuánto, depende de la
  /// forma de cada uno. Como se mide contra la capa, un bicho de la capa del
  /// fondo sale pequeño y uno de la de delante, grande, igual que las células.
  final double scale;

  /// Cuántos caen a la vez como mucho. Cada plaza se juega su aparición por
  /// separado (ver `_bichoOdds`), así que este es el techo, no la cuenta.
  final int max;

  /// Cuánto gira sobre sí mismo mientras cae, en la misma escala que las
  /// células (que van a 0,03). No tiene nada que ver con lo que haga la
  /// animación por dentro: esto es la partícula dando vueltas.
  final double spin;

  /// El tamaño que hay que darle al widget para que el dibujo se vea a [scale]
  /// de una célula de [celula] puntos.
  double boxFor(double celula) => celula * scale / fill;

  /// Techo de 30 repintados por segundo de reloj: son bichos de 50 puntos en un
  /// fondo, y a 60 no se nota la diferencia pero sí el doble de trabajo en la
  /// CPU justo mientras se carga la app. Lottie cuenta la tasa en fotogramas de
  /// la propia animación, así que al ir [speed] veces más rápido hay que
  /// pedirla otras tantas veces más baja para que salgan esos 30.
  FrameRate get frameRate => FrameRate(30 / speed);
}

class LayerConfig {
  final int count;
  final List<double> speedRange;
  final List<double> sizeRange;
  final double blur;
  final double opacity;

  LayerConfig({
    required this.count,
    required this.speedRange,
    required this.sizeRange,
    required this.blur,
    required this.opacity,
  });
}
