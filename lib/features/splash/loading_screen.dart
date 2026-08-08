import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/services/app_warmup.dart';
import '../../core/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();

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
                              child: _showButton
                                  ? _buildContinueButton()
                                  : _buildProgressBar(),
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
    'assets/images/kidneys.png',
    'assets/images/Bacteriofago.png',
  ];

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
    ]);
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
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();
  DateTime _lastUpdate = DateTime.now();

  final List<String> _commonImages = [
    'assets/images/rbc.png',
    'assets/images/neutrophil.png',
    'assets/images/Virus.png',
    'assets/images/kidneys.png',
  ];

  final String _rareImage = 'assets/images/Bacteriofago.png';

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

    _layerConfigs.forEach((layer, config) {
      for (int i = 0; i < config.count; i++) {
        _particles.add(_createParticle(layer, config));
      }
    });

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
    } else {
      _controller.stop();
    }
  }

  Particle _createParticle(int layer, LayerConfig config,
      {bool startOffScreen = false}) {
    final speed = config.speedRange[0] +
        _random.nextDouble() * (config.speedRange[1] - config.speedRange[0]);
    final size = config.sizeRange[0] +
        _random.nextDouble() * (config.sizeRange[1] - config.sizeRange[0]);

    final x = 0.2 + _random.nextDouble() * 0.6;

    return Particle(
      x: x,
      y: startOffScreen ? -0.15 : _random.nextDouble() * 1.3 - 0.15,
      size: size,
      speed: speed,
      rotation: _random.nextDouble() * 2 * pi,
      rotationSpeed: (_random.nextDouble() - 0.5) * 0.03,
      drift: (_random.nextDouble() - 0.5) * 0.001,
      layer: layer,
      imagePath: _getRandomImage(),
      blur: config.blur,
      opacity: config.opacity,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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
            _particles[i] =
                _createParticle(p.layer, config, startOffScreen: true);
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
          opacity: p.opacity,
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

  Widget _buildParticleImage(Particle p) {
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
  });
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
