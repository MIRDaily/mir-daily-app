import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService authService;
  final ApiService apiService;

  AuthProvider({required this.authService, required this.apiService}) {
    _listenDeepLinks();
  }

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  Timer? _oauthTimeout;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  UserProfile? _profile;
  UserProfile? get profile => _profile;

  /// Se pone a true tras el primer intento de cargar el perfil (con éxito o
  /// fallo). Sirve para no decidir el onboarding hasta tener el dato.
  bool _profileChecked = false;
  bool get profileChecked => _profileChecked;

  /// Se marca al terminar el onboarding para no volver a mostrarlo aunque la
  /// recarga del perfil tarde o falle (evita "rebotes" al asistente). También
  /// sirve para lanzar la animación de entrada especial al daily.
  bool _onboardingJustDone = false;
  bool get onboardingJustCompleted => _onboardingJustDone;

  /// El usuario está autenticado pero aún no ha completado el onboarding.
  bool get needsOnboarding =>
      !_onboardingJustDone &&
      _profile != null &&
      !_profile!.onboardingCompleted;

  /// Marca el onboarding como completado localmente (además de en el servidor).
  void markOnboardingDone() {
    if (!_onboardingJustDone) {
      _onboardingJustDone = true;
      notifyListeners();
    }
  }

  bool _loading = false;
  bool get loading => _loading;

  bool _oauthLoading = false;
  bool get oauthLoading => _oauthLoading;

  String? _error;
  String? get error => _error;

  String? _info;
  String? get info => _info;

  /// Restaura la sesión guardada al arrancar la app.
  Future<void> bootstrap() async {
    final session = await authService.loadSession();
    if (session == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    apiService.session = session;
    try {
      if (session.isExpired) {
        apiService.session = await authService.refresh(session);
      }
      _status = AuthStatus.authenticated;
      notifyListeners();
      _loadProfileSilently();
    } catch (_) {
      apiService.session = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error = null;
    _info = null;
    notifyListeners();

    try {
      final session = await authService.signInWithPassword(
        email: email,
        password: password,
      );
      _completeSignIn(session);
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
    }

    _loading = false;
    notifyListeners();
    return false;
  }

  /// Registro con email + contraseña (igual que la web).
  /// Devuelve true si la cuenta quedó creada (con o sin sesión).
  Future<bool> register(String email, String password) async {
    _loading = true;
    _error = null;
    _info = null;
    notifyListeners();

    try {
      final session = await authService.signUp(
        email: email,
        password: password,
      );
      if (session != null) {
        _info = 'Cuenta creada. Sesión iniciada.';
        _completeSignIn(session);
      } else {
        _info = 'Cuenta creada. Revisa tu correo para confirmar.';
      }
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
    }

    _loading = false;
    notifyListeners();
    return false;
  }

  Future<bool> recoverPassword(String email) async {
    _loading = true;
    _error = null;
    _info = null;
    notifyListeners();

    try {
      await authService.recoverPassword(email);
      _info = 'Te hemos enviado un email para restablecer la contraseña.';
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
    }

    _loading = false;
    notifyListeners();
    return false;
  }

  // ==========================
  // OAUTH (GOOGLE)
  // ==========================

  /// Abre el navegador con el OAuth de Supabase; el deep link de vuelta
  /// (com.mirdaily.app://auth-callback) lo captura [_listenDeepLinks].
  Future<void> signInWithGoogle() async {
    _error = null;
    _info = null;
    _oauthLoading = true;
    notifyListeners();

    final url = authService.oauthAuthorizeUrl('google');
    final launched = await launchUrl(
      url,
      mode: LaunchMode.inAppBrowserView,
    );

    if (!launched) {
      _oauthLoading = false;
      _error = 'No se pudo abrir el navegador para conectar con Google.';
      notifyListeners();
      return;
    }

    // Si el usuario cancela en el navegador no hay callback: liberamos el
    // botón pasado un tiempo prudente.
    _oauthTimeout?.cancel();
    _oauthTimeout = Timer(const Duration(minutes: 2), () {
      if (_oauthLoading) {
        _oauthLoading = false;
        notifyListeners();
      }
    });
  }

  void _listenDeepLinks() {
    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      if (uri.scheme != 'com.mirdaily.app') return;
      try {
        final session = await authService.sessionFromOAuthCallback(uri);
        if (session != null) {
          _oauthTimeout?.cancel();
          _oauthLoading = false;
          _completeSignIn(session);
          notifyListeners();
        }
      } on AuthException catch (e) {
        _oauthTimeout?.cancel();
        _oauthLoading = false;
        _error = e.message;
        notifyListeners();
      }
    });
  }

  void _completeSignIn(AuthSession session) {
    apiService.session = session;
    _status = AuthStatus.authenticated;
    _loadProfileSilently();
  }

  Future<void> signOut() async {
    await authService.clearSession();
    apiService.session = null;
    _profile = null;
    _profileChecked = false;
    _onboardingJustDone = false;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> _loadProfileSilently() async {
    try {
      _profile = await apiService.getProfile();
    } catch (_) {
      // El perfil es decorativo en la app básica: no bloquea nada.
    } finally {
      _profileChecked = true;
      notifyListeners();
    }
  }

  /// Recarga el perfil del backend (tras editar el avatar, etc.).
  Future<void> refreshProfile() => _loadProfileSilently();

  /// Cambia el avatar en el servidor y refresca el perfil.
  Future<bool> updateAvatar(int avatarId) async {
    try {
      await apiService.updateAvatar(avatarId);
      await _loadProfileSilently();
      return true;
    } catch (_) {
      return false;
    }
  }

  void clearMessages() {
    if (_error != null || _info != null) {
      _error = null;
      _info = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _oauthTimeout?.cancel();
    super.dispose();
  }
}
