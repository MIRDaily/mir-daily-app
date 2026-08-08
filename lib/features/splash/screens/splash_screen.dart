import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  
  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _progressController;
  late AnimationController _textController;
  late AnimationController _buttonController;
  late Animation<double> _logoAnimation;
  late Animation<double> _progressAnimation;
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

  @override
  void initState() {
    super.initState();
    
    // Seleccionar frase inicial aleatoria
    _phraseIndex = Random().nextInt(_phrases.length);
    _currentPhrase = _phrases[_phraseIndex];
    
    // Controlador del logo (flotación suave)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    
    _logoAnimation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );
    
    // Controlador de progreso (3 segundos)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );
    
    // Controlador del texto
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _textFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    
    // Controlador del botón
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _buttonFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeOut),
    );
    
    // Iniciar animaciones
    _progressController.forward();
    _textController.forward();
    
    // Cambiar frase cada 700ms
    _phraseTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _changePhrase();
    });
    
    // Mostrar botón cuando termine la carga
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _showButton = true;
        });
        _buttonController.forward();
      }
    });
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

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => widget.nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _progressController.dispose();
    _textController.dispose();
    _buttonController.dispose();
    _phraseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Capa de partículas cayendo (fondo)
          const ParticlesBackground(),
          
          // Contenido principal
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  
                  // Logo animado con flotación
                  AnimatedBuilder(
                    animation: _logoAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _logoAnimation.value),
                        child: child,
                      );
                    },
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
                        child: Image.asset(
                          'assets/images/logo_mirdaily.png',
                          width: 500,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  
                  const Spacer(flex: 2),
                  
                  // Frase humorística (solo durante la carga)
                  if (!_showButton)
                    FadeTransition(
                      opacity: _textFadeAnimation,
                      child: SizedBox(
                        height: 24,
                        child: Text(
                          _currentPhrase,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary.withOpacity(0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Barra de progreso o botón
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    child: AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        if (_showButton) {
                          return FadeTransition(
                            opacity: _buttonFadeAnimation,
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _navigateToHome,
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
                        
                        return Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: _progressAnimation.value,
                                backgroundColor: AppColors.primary.withOpacity(0.15),
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${(_progressAnimation.value * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary.withOpacity(0.6),
                              ),
                            ),
                          ],
                        );
                      },
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
  }
}

// Widget de partículas cayendo en 3 capas
class ParticlesBackground extends StatefulWidget {
  const ParticlesBackground({super.key});

  @override
  State<ParticlesBackground> createState() => _ParticlesBackgroundState();
}

class _ParticlesBackgroundState extends State<ParticlesBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();
  DateTime _lastUpdate = DateTime.now();
  
  // Imágenes disponibles (sin bacteriófago, se añade raramente)
  final List<String> _commonImages = [
    'assets/images/rbc.png',
    'assets/images/neutrophil.png',
    'assets/images/Virus.png',
    'assets/images/kidneys.png',
  ];
  
  final String _rareImage = 'assets/images/Bacteriofago.png';

  // Configuración por capa - REDUCIDO cantidad de partículas
  // Layer 0 = back (lejos, pequeñas, lentas, blur)
  // Layer 1 = mid (media, enfocadas)
  // Layer 2 = front (cerca, grandes, rápidas, blur)
  
  final Map<int, LayerConfig> _layerConfigs = {
    0: LayerConfig(count: 3, speedRange: [0.03, 0.05], sizeRange: [50, 70], blur: 2.5, opacity: 0.5),
    1: LayerConfig(count: 3, speedRange: [0.05, 0.08], sizeRange: [80, 110], blur: 0, opacity: 0.8),
    2: LayerConfig(count: 2, speedRange: [0.08, 0.12], sizeRange: [140, 200], blur: 3, opacity: 0.6),
  };

  String _getRandomImage() {
    // 1/15 de probabilidad para bacteriófago
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
    )..repeat();
    
    // Crear partículas para cada capa
    _layerConfigs.forEach((layer, config) {
      for (int i = 0; i < config.count; i++) {
        _particles.add(_createParticle(layer, config));
      }
    });
    
    // Ordenar por capa (back primero)
    _particles.sort((a, b) => a.layer.compareTo(b.layer));
  }

  Particle _createParticle(int layer, LayerConfig config, {bool startOffScreen = false}) {
    final speed = config.speedRange[0] + _random.nextDouble() * (config.speedRange[1] - config.speedRange[0]);
    final size = config.sizeRange[0] + _random.nextDouble() * (config.sizeRange[1] - config.sizeRange[0]);
    
    // Posición horizontal más centrada (entre 20% y 80% de la pantalla)
    final x = 0.2 + _random.nextDouble() * 0.6;
    
    return Particle(
      x: x,
      y: startOffScreen ? -0.15 : _random.nextDouble() * 1.3 - 0.15,
      size: size,
      speed: speed,
      rotation: _random.nextDouble() * 2 * pi,
      rotationSpeed: (_random.nextDouble() - 0.5) * 0.03,
      drift: (_random.nextDouble() - 0.5) * 0.001, // Reducido drift lateral
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
        // Calcular delta time para velocidad consistente
        final now = DateTime.now();
        final deltaTime = now.difference(_lastUpdate).inMilliseconds / 1000.0;
        _lastUpdate = now;
        
        // Actualizar posiciones usando delta time
        for (int i = 0; i < _particles.length; i++) {
          final p = _particles[i];
          p.y += p.speed * deltaTime;
          p.x += p.drift * deltaTime * 30;
          p.rotation += p.rotationSpeed * deltaTime * 30;
          
          // Reiniciar si sale de pantalla
          if (p.y > 1.15) {
            final config = _layerConfigs[p.layer]!;
            _particles[i] = _createParticle(p.layer, config, startOffScreen: true);
          }
        }
        
        return Stack(
          children: _particles.map((p) => _buildParticle(p)).toList(),
        );
      },
    );
  }

  Widget _buildParticle(Particle p) {
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
                  child: Image.asset(
                    p.imagePath,
                    width: p.size,
                    height: p.size,
                    fit: BoxFit.contain,
                  ),
                )
              : Image.asset(
                  p.imagePath,
                  width: p.size,
                  height: p.size,
                  fit: BoxFit.contain,
                ),
        ),
      ),
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
