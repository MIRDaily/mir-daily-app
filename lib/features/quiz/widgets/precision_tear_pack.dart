import 'package:flutter/material.dart';

class PrecisionTearPack extends StatefulWidget {
  final String closedPackPath; 
  final String openPackPath;   
  final VoidCallback onOpen;   

  const PrecisionTearPack({
    super.key,
    required this.closedPackPath,
    required this.openPackPath,
    required this.onOpen,
  });

  @override
  State<PrecisionTearPack> createState() => _PrecisionTearPackState();
}

class _PrecisionTearPackState extends State<PrecisionTearPack> with SingleTickerProviderStateMixin {
  // AJUSTES ------------------------------------------------------------------
  // 1. Altura de la línea de corte (visual)
  final double _tearHeightFactor = 0.23; 
  
  // 2. Altura de la ZONA TÁCTIL (invisible)
  // Aumentado a 0.40 (40%) para que sea fácil de agarrar, pero dejando el 60% libre abajo.
  final double _touchZoneHeightFactor = 0.40; 

  // 3. MODO DEBUG: Ponlo en 'true' para ver la caja roja. Ponlo en 'false' para ocultarla.
  final bool _showDebugHitbox = true; // <--- CAMBIA A FALSE CUANDO FUNCIONE
  // --------------------------------------------------------------------------

  double _dragProgress = 0.0;
  bool _isOpened = false;
  late AnimationController _guideController;

  @override
  void initState() {
    super.initState();
    _guideController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _guideController.dispose();
    super.dispose();
  }

  // --- LÓGICA DE ARRASTRE ---
  
  // IMPORTANTE: Necesitamos esto para "ganar" el gesto al PageView
  void _onDragStart(DragStartDetails details) {
    // Solo con declararlo, Flutter sabe que este widget quiere prioridad
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isOpened) return;
    
    // Sensibilidad ajustada
    double delta = details.primaryDelta! / 200; 
    setState(() {
      _dragProgress = (_dragProgress + delta).clamp(0.0, 1.0);
    });

    if (_dragProgress >= 0.95) {
      setState(() => _isOpened = true);
      Future.delayed(const Duration(milliseconds: 300), widget.onOpen);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isOpened) return;
    _snapBack();
  }

  void _snapBack() async {
    while (_dragProgress > 0) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 16));
      setState(() {
        _dragProgress = (_dragProgress - 0.1).clamp(0.0, 1.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // CAPA 1: EL PAQUETE ABIERTO (Fondo)
        Image.asset(widget.openPackPath),

        // CAPA 2: EL CUERPO DEL PAQUETE CERRADO
        if (!_isOpened)
          ClipRect(
            clipper: BottomPartClipper(_tearHeightFactor),
            child: Image.asset(widget.closedPackPath),
          ),

        // CAPA 3: LA TAPA (Animada visualmente)
        if (!_isOpened || _dragProgress < 1.0)
          Transform.translate(
            offset: Offset(_dragProgress * 350, _dragProgress * 100), 
            child: Transform.rotate(
              angle: _dragProgress * 0.5, 
              child: Stack(
                children: [
                  ClipRect(
                    clipper: TopPartClipper(_tearHeightFactor),
                    child: Image.asset(widget.closedPackPath),
                  ),
                  // Guía visual (línea de puntos)
                  if (_dragProgress < 0.1)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: DashedLineGuide(
                          heightFactor: _tearHeightFactor,
                          opacity: _guideController,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
         // CAPA 4: TEXTO INDICADOR
         if (_dragProgress < 0.1 && !_isOpened)
           Positioned(
             bottom: 50,
             child: AnimatedBuilder(
               animation: _guideController,
               builder: (context, child) {
                 return Opacity(
                   opacity: 0.5 + (_guideController.value * 0.5),
                   child: const Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                       SizedBox(width: 8),
                       Text(
                         "Desliza en la costura",
                         style: TextStyle(
                           color: Colors.white, 
                           fontWeight: FontWeight.w600,
                           shadows: [Shadow(color: Colors.black, blurRadius: 4)]
                         ),
                       ),
                     ],
                   ),
                 );
               },
             ),
           ),

        // CAPA 5: LA ZONA TÁCTIL (HITBOX)
        // Usamos Column + Flexible para dividir el espacio matemáticamente exacto
        Positioned.fill(
          child: Column(
            children: [
              // ZONA ACTIVA (Arriba)
              Flexible(
                flex: (_touchZoneHeightFactor * 100).toInt(), // ej: 40
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque, // <--- CRUCIAL: Atrapa todos los toques
                  onHorizontalDragStart: _onDragStart, // <--- CRUCIAL: Gana la prioridad
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: Container(
                    // Si debugMode es true, se ve rojo. Si no, transparente.
                    color: _showDebugHitbox 
                        ? Colors.red.withValues(alpha: 0.5) 
                        : Colors.transparent,
                    width: double.infinity,
                    child: _showDebugHitbox 
                        ? const Center(child: Text("ZONA\nABRIR", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                        : null,
                  ),
                ),
              ),
              
              // ZONA PASIVA (Abajo)
              // Aquí NO hay GestureDetector, así que los toques pasan al PageView
              Flexible(
                flex: ((1.0 - _touchZoneHeightFactor) * 100).toInt(), // ej: 60
                child: Container(
                  // Debug visual para la zona de abajo
                  color: _showDebugHitbox 
                      ? Colors.blue.withValues(alpha: 0.3) 
                      : Colors.transparent,
                   width: double.infinity,
                   child: _showDebugHitbox 
                        ? const Center(child: Text("ZONA\nSWIPE", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                        : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -- CLIPPERS Y PAINTERS (Sin cambios) --
class TopPartClipper extends CustomClipper<Rect> {
  final double factor;
  TopPartClipper(this.factor);
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, size.height * factor);
  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => true;
}

class BottomPartClipper extends CustomClipper<Rect> {
  final double factor;
  BottomPartClipper(this.factor);
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, size.height * factor, size.width, size.height);
  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => true;
}

class DashedLineGuide extends CustomPainter {
  final double heightFactor;
  final Animation<double> opacity;

  DashedLineGuide({required this.heightFactor, required this.opacity}) : super(repaint: opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height * heightFactor;
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6 + (opacity.value * 0.4))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const double dashWidth = 6;
    const double dashSpace = 4;
    double startX = 20;

    while (startX < size.width - 20) {
      canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), paint);
      startX += dashWidth + dashSpace;
    }
  }
  @override
  bool shouldRepaint(DashedLineGuide oldDelegate) => true;
}