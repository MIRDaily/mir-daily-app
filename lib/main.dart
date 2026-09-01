import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/responsive/orientation_lock.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/system_ui.dart';
import 'core/providers/quiz_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/daily_provider.dart';
import 'core/services/api_service.dart';
import 'core/services/app_warmup.dart';
import 'core/services/auth_service.dart';
import 'core/services/notification_service.dart';
import 'features/focus/providers/focus_provider.dart';
import 'features/navigation/main_navigation.dart';
import 'features/versus/services/versus_links.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/splash/loading_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientación: el móvil va bloqueado a vertical (la app es de una columna);
  // la tablet permite las 4, con el horizontal como uso principal. Sin await:
  // no debe retrasar el primer frame.
  unawaited(OrientationLock.apply());

  // Refresco alto: en Android muchos móviles capan las apps a 60 Hz por
  // defecto; pedimos el modo de mayor refresco disponible (90/120/144 Hz).
  // En iOS (ProMotion) y emuladores es no-op; por eso va en try/catch.
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {}

  // Sin barra de estado (reloj, batería, notificaciones): la app se ve limpia
  // y la barra de navegación se queda. El modo focus tiene la suya, más
  // agresiva, y al salir vuelve a esta.
  SystemUi.apply();
  SystemUi.applyStyle();
  // El modo manual no se repone solo: si el usuario baja las notificaciones o
  // cambia de app, la barra vuelve y hay que esconderla otra vez.
  StatusBarKeeper().start();

  // Las células y el logo de la pantalla de carga se van decodificando ya, en
  // paralelo al arranque: para cuando la pantalla aparezca (después de
  // restaurar la sesión) ya están listas y entran de una, en vez de ir
  // apareciendo a trompicones. Sin await: no debe retrasar el primer frame.
  unawaited(LoadingScreenImages.precache());

  final authService = AuthService();
  final apiService = ApiService(authService);

  // Notificaciones locales: inicializa y reprograma el recordatorio del daily
  // si el usuario lo tenía activado (no bloquea el arranque si falla).
  final notifications = NotificationService();
  unawaited(notifications.init().then((_) => notifications.rescheduleIfEnabled()));

  // Enlaces a una sala de Versus (el QR de otro móvil, o el mensaje de
  // WhatsApp). Se escucha desde el arranque porque el enlace puede ser justo lo
  // que ha abierto la app, y entonces llega antes que ninguna pantalla.
  unawaited(VersusLinks.instance.start());

  runApp(MIRDailyApp(authService: authService, apiService: apiService));
}

class MIRDailyApp extends StatelessWidget {
  final AuthService authService;
  final ApiService apiService;

  const MIRDailyApp({
    super.key,
    required this.authService,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Capa backend (sobre diario real)
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            authService: authService,
            apiService: apiService,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyProvider(apiService)),
        // Providers locales heredados de v10.6 (Studio, Premium, Perfil, Focus)
        ChangeNotifierProvider(create: (_) => QuizProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => FocusProvider()),
      ],
      child: MaterialApp(
        title: 'MIRDaily',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const StartupGate(),
      ),
    );
  }
}

/// Puerta de entrada: muestra la pantalla de carga de v10.5 (con su botón
/// Puerta de entrada. Orden del flujo:
///   login/registro → pantalla de carga ("Continuar") → onboarding → daily.
/// La pantalla de carga aparece SOLO una vez autenticado (tras iniciar sesión
/// o restaurar la sesión), no antes del login. Mientras se restaura la sesión
/// se muestra un splash mínimo.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  // Se ha pasado ya la pantalla de carga de ESTA sesión autenticada.
  bool _continued = false;

  // La precarga de la sesión actual: la lanza la pantalla de carga y su
  // resultado lo aprovecha _OnboardingGate. Se tira al cerrar sesión para que
  // la siguiente entrada vuelva a cargar de cero.
  AppWarmup? _warmup;

  @override
  void initState() {
    super.initState();
    // Restaura la sesión guardada (puede resolver a autenticado o no).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().bootstrap();
    });
  }

  @override
  void dispose() {
    _warmup?.dispose();
    super.dispose();
  }

  /// Solo tiene sentido con sesión: sin ella no hay daily que pedir.
  AppWarmup _warmupFor(BuildContext context) {
    return _warmup ??= AppWarmup(
      auth: context.read<AuthProvider>(),
      daily: context.read<DailyProvider>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;

    // Durante el cruce, las dos pantallas están a media opacidad y deja de
    // taparse lo que hay detrás: la ventana de Android, que en modo oscuro es
    // negra (ver NormalTheme en values-night/styles.xml). Sin este fondo, la
    // transición se oscurece por en medio.
    return ColoredBox(
      color: AppColors.background,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: switch (status) {
          // Restaurando sesión: splash breve (no la pantalla de carga completa,
          // para no mostrarla a quien va a acabar en el login).
          AuthStatus.unknown => const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          // Sin sesión: directo al login/registro (sin carga previa).
          AuthStatus.unauthenticated => _loginResettingContinue(),
          // Autenticado: primero la pantalla de carga (que es donde se carga de
          // verdad) y, al continuar, la app ya lista.
          AuthStatus.authenticated => _continued
              ? _OnboardingGate(warmup: _warmupFor(context))
              : LoadingScreen(
                  warmup: _warmupFor(context),
                  onContinue: () => setState(() => _continued = true),
                ),
        },
      ),
    );
  }

  /// Muestra el login y, si veníamos de una sesión anterior, resetea el flag
  /// para que al volver a iniciar sesión se muestre de nuevo la carga.
  Widget _loginResettingContinue() {
    if (_continued || _warmup != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Solo se suelta la referencia (la precarga de la sesión anterior ya no
        // vale): no se hace dispose porque la pantalla de carga saliente puede
        // seguir viva unos frames dentro del AnimatedSwitcher y aún escucharlo.
        _warmup = null;
        if (_continued) setState(() => _continued = false);
      });
    }
    return const LoginScreen();
  }
}

/// Entre login y la app: si el usuario aún no completó el onboarding (y no lo
/// ha pospuesto), muestra el asistente; si no, la app normal.
class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate({required this.warmup});

  final AppWarmup warmup;

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  static const _kDeferredKey = 'onboarding.deferred';
  bool _prefsLoaded = false;
  bool _deferred = false;

  @override
  void initState() {
    super.initState();

    // Camino normal: la pantalla de carga ya leyó las prefs, así que se decide
    // aquí mismo y no llega a pintarse el spinner de más abajo.
    final warm = widget.warmup.prefs;
    if (warm != null) {
      _deferred = warm.getBool(_kDeferredKey) ?? false;
      _prefsLoaded = true;
      return;
    }

    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _deferred = p.getBool(_kDeferredKey) ?? false;
        _prefsLoaded = true;
      });
    });
  }

  Future<void> _defer() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDeferredKey, true);
    if (mounted) setState(() => _deferred = true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // Esperamos a saber el estado del perfil y de las prefs.
        if (!_prefsLoaded || !auth.profileChecked) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        if (auth.needsOnboarding && !_deferred) {
          return OnboardingScreen(
            onFinished: () {}, // el cambio de perfil ya re-enruta a la app
            onSkip: _defer,
          );
        }
        // Entrada especial (marcada y lenta) solo si acaba de terminar el
        // onboarding en esta sesión.
        return MainNavigation(justOnboarded: auth.onboardingJustCompleted);
      },
    );
  }
}
