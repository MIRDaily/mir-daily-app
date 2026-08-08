import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/misc_widgets.dart';
import '../../shared/widgets/pressable.dart';
import 'widgets/falling_background.dart';
import 'widgets/google_logo.dart';

enum _AuthMode { login, register, recover }

/// Pantalla de acceso, réplica del AuthCard de la web: logo, células
/// cayendo de fondo, slider pill elástico entre Iniciar sesión/Registrarse,
/// morph animado entre formularios y acceso con Google.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  _AuthMode _mode = _AuthMode.login;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _remember = true;

  late final AnimationController _errorShake;

  static const _border = Color(0xFFE4DEDC);

  @override
  void initState() {
    super.initState();
    _errorShake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Precargar email/contraseña si se marcó "Recordar mis datos".
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRemembered());
  }

  Future<void> _loadRemembered() async {
    final creds =
        await context.read<AuthProvider>().authService.loadRememberedCredentials();
    if (creds != null && mounted) {
      setState(() {
        _emailController.text = creds['email'] ?? '';
        _passwordController.text = creds['password'] ?? '';
        _remember = true;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _errorShake.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (mode == _mode) return;
    context.read<AuthProvider>().clearMessages();
    setState(() => _mode = mode);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    bool ok;
    switch (_mode) {
      case _AuthMode.login:
        if (email.isEmpty || password.isEmpty) return;
        ok = await auth.signIn(email, password);
        if (ok) {
          if (_remember) {
            await auth.authService.saveRememberedCredentials(email, password);
          } else {
            await auth.authService.clearRememberedCredentials();
          }
        }
      case _AuthMode.register:
        if (email.isEmpty || password.isEmpty) return;
        if (password != _confirmController.text) {
          auth.clearMessages();
          setState(() {});
          _showLocalError('Las contraseñas no coinciden');
          return;
        }
        ok = await auth.register(email, password);
        if (ok && mounted) {
          _passwordController.clear();
          _confirmController.clear();
        }
      case _AuthMode.recover:
        if (email.isEmpty) return;
        ok = await auth.recoverPassword(email);
    }

    if (!ok && mounted) _errorShake.forward(from: 0);
  }

  String? _localError;
  void _showLocalError(String message) {
    setState(() => _localError = message);
    _errorShake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(child: FallingBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    children: [
                      _header(),
                      const SizedBox(height: 18),
                      _card(auth),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return SlideFadeIn(
      child: Column(
        children: [
          Image.asset(
            'assets/images/logo_mirdaily_web.png',
            height: 110,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const MirDailyLogo(fontSize: 40),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.4),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              switch (_mode) {
                _AuthMode.login => 'Bienvenido de nuevo',
                _AuthMode.register => 'Crea tu cuenta',
                _AuthMode.recover => 'Recupera tu acceso',
              },
              key: ValueKey(_mode),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(AuthProvider auth) {
    return SlideFadeIn(
      delay: const Duration(milliseconds: 150),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Slider pill (oculto en modo recuperar)
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: _mode == _AuthMode.recover
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: _modeSlider(),
                    ),
            ),

            // Formularios con morph
            AnimatedSize(
              duration: const Duration(milliseconds: 450),
              curve: const Cubic(0.7, 0, 0.3, 1),
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                switchInCurve: const Cubic(0.7, 0, 0.3, 1),
                switchOutCurve: const Cubic(0.7, 0, 0.3, 1),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: ScaleTransition(
                      scale: Tween(begin: 0.98, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_mode),
                  child: switch (_mode) {
                    _AuthMode.login => _loginForm(auth),
                    _AuthMode.register => _registerForm(auth),
                    _AuthMode.recover => _recoverForm(auth),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pestañas "Iniciar sesión / Registrarse" con pill deslizante elástica,
  /// como el AuthCard web (cubic-bezier con rebote).
  Widget _modeSlider() {
    final isLogin = _mode == _AuthMode.login;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            alignment:
                isLogin ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _sliderTab('Iniciar sesión', _AuthMode.login),
              _sliderTab('Registrarse', _AuthMode.register),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sliderTab(String label, _AuthMode mode) {
    final active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _switchMode(mode),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 500),
            curve: const Cubic(0.7, 0, 0.3, 1),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: active
                  ? const Color(0xFF171312)
                  : AppColors.textSecondary,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  // ==========================
  // FORMULARIOS
  // ==========================

  Widget _loginForm(AuthProvider auth) {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _input(
          controller: _emailController,
          hint: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _input(
          controller: _passwordController,
          hint: 'Contraseña',
          obscure: _obscurePassword,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          onSubmitted: _submit,
        ),
        _rememberRow(),
        _messages(auth),
        const SizedBox(height: 16),
        _primaryButton(
          label: auth.loading ? 'Entrando...' : 'Iniciar sesión',
          loading: auth.loading,
          onTap: auth.loading ? null : _submit,
        ),
        _divider('o continúa con'),
        _oauthRow(auth),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => _switchMode(_AuthMode.recover),
            child: const Text(
              '¿Olvidaste tu contraseña?',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        _switchLink(
          '¿No tienes cuenta? ',
          'Crear cuenta',
          () => _switchMode(_AuthMode.register),
        ),
      ],
    );
  }

  Widget _registerForm(AuthProvider auth) {
    return Column(
      key: const ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _input(
          controller: _emailController,
          hint: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _input(
          controller: _passwordController,
          hint: 'Contraseña',
          obscure: _obscurePassword,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        const SizedBox(height: 14),
        _input(
          controller: _confirmController,
          hint: 'Repite la contraseña',
          obscure: _obscureConfirm,
          onToggleObscure: () =>
              setState(() => _obscureConfirm = !_obscureConfirm),
          onSubmitted: _submit,
        ),
        _messages(auth),
        const SizedBox(height: 16),
        _primaryButton(
          label: auth.loading ? 'Creando cuenta...' : 'Crear cuenta',
          loading: auth.loading,
          onTap: auth.loading ? null : _submit,
        ),
        _divider('o regístrate con'),
        _oauthRow(auth),
        const SizedBox(height: 10),
        _switchLink(
          '¿Ya tienes cuenta? ',
          'Inicia sesión',
          () => _switchMode(_AuthMode.login),
        ),
      ],
    );
  }

  Widget _recoverForm(AuthProvider auth) {
    return Column(
      key: const ValueKey('recover'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Introduce tu email y te enviaremos un enlace para restablecer tu contraseña.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _input(
          controller: _emailController,
          hint: 'Email',
          keyboardType: TextInputType.emailAddress,
          onSubmitted: _submit,
        ),
        _messages(auth),
        const SizedBox(height: 16),
        _primaryButton(
          label: auth.loading ? 'Enviando...' : 'Enviar enlace',
          loading: auth.loading,
          onTap: auth.loading ? null : _submit,
        ),
        const SizedBox(height: 10),
        _switchLink(
          '',
          '← Volver a iniciar sesión',
          () => _switchMode(_AuthMode.login),
        ),
      ],
    );
  }

  // ==========================
  // PIEZAS
  // ==========================

  Widget _input({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool? obscure,
    VoidCallback? onToggleObscure,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure ?? false,
      autocorrect: false,
      onChanged: (_) {
        context.read<AuthProvider>().clearMessages();
        if (_localError != null) setState(() => _localError = null);
      },
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      style: const TextStyle(fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  (obscure ?? true)
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
      ),
    );
  }

  Widget _rememberRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _remember = !_remember),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Recordar mis datos',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messages(AuthProvider auth) {
    final error = _localError ?? auth.error;
    final info = auth.info;
    if (error == null && info == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _errorShake,
      builder: (context, child) {
        final t = _errorShake.value;
        final dx = (error == null || t == 0)
            ? 0.0
            : (1 - t) * 8 * ((t * 20).floor() % 2 == 0 ? 1 : -1);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          error ?? info!,
          style: TextStyle(
            color: error != null ? AppColors.error : AppColors.success,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required bool loading,
    VoidCallback? onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          color: loading ? AppColors.primaryHover : AppColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.4,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
      ),
    );
  }

  Widget _divider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border, height: 1)),
        ],
      ),
    );
  }

  Widget _oauthRow(AuthProvider auth) {
    return Row(
      children: [
        Expanded(
          child: _oauthButton(
            icon: const GoogleLogo(size: 19),
            label: auth.oauthLoading ? 'Conectando...' : 'Google',
            onTap: auth.oauthLoading
                ? null
                : () => context.read<AuthProvider>().signInWithGoogle(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _oauthButton(
            icon: const Icon(Icons.apple_rounded,
                size: 22, color: AppColors.textPrimary),
            label: 'Apple',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Apple estará disponible próximamente.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _oauthButton({
    required Widget icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap == null
                    ? AppColors.textLight
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchLink(String prefix, String action, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: GestureDetector(
          onTap: onTap,
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              children: [
                TextSpan(text: prefix),
                TextSpan(
                  text: action,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
