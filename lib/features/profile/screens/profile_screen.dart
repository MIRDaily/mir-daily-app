import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/daily_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/build_info.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/responsive/adaptive_modal.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/content_shell.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../widgets/profile_card.dart';
import '../widgets/profile_card_fields.dart';
import '../widgets/profile_editor_sheet.dart';

/// Perfil con el lenguaje visual de la web: borde de tinta, sombra dura y,
/// como textura propia de esta pantalla, la de un **carné plastificado**
/// (guilloche, campos rotulados, código de barras derivado del id del usuario
/// y un destello de laminado que cruza de vez en cuando).
///
/// Conectado a los datos reales del backend (/api/profile,
/// /api/stats/activity-heatmap, /api/profile/avatar, /api/profile/academic).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ActivityHeatmap? _heatmap;

  /// Qué campos enseña el carné. Es una preferencia del teléfono, no un dato
  /// del perfil, así que se lee de local y no del backend.
  Set<CardField> _campos = CardFieldPrefs.todos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    CardFieldPrefs.load().then((c) {
      if (mounted) setState(() => _campos = c);
    });
    context.read<AuthProvider>().refreshProfile();
    try {
      final heatmap = await context.read<ApiService>().getActivityHeatmap();
      if (mounted) setState(() => _heatmap = heatmap);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final profile = auth.profile;
          final name = profile?.fullName ?? 'Doctor/a';
          final handle =
              (profile?.username != null && profile!.username!.isNotEmpty)
                  ? '@${profile.username}'
                  : '@usuario_mir';
          final avatarId = profile?.avatarId ?? 1;
          const bool isPremium = false;

          final chips = <String>[
            if (profile?.mirSpecialty != null &&
                profile!.mirSpecialty!.isNotEmpty)
              profile.mirSpecialty!,
            if (profile?.university != null && profile!.university!.isNotEmpty)
              profile.university!,
            if ((profile?.mirSpecialty == null ||
                    profile!.mirSpecialty!.isEmpty) &&
                profile?.medicalYear != null)
              '${profile!.medicalYear}º de Medicina',
          ];

          return SafeArea(
            bottom: false,
            child: BodyConstraint(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(
                    20, context.isWide ? 28 : 8, 20, 120),
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 8),
                  _buildHeader(name, handle, avatarId, isPremium, chips),
                  const SizedBox(height: 22),
                  _buildStatsRow(),
                  const SizedBox(height: 22),
                  _buildPremiumCard(isPremium),
                  const SizedBox(height: 30),
                  _buildSectionTitle('Cuenta'),
                  const SizedBox(height: 12),
                  _buildGroup([
                    _MenuItemData(
                      icon: Icons.edit_outlined,
                      color: Colors.teal,
                      title: 'Editar avatar',
                      subtitle: 'Cambia tu imagen',
                      onTap: _showAvatarSelectionSheet,
                    ),
                    _MenuItemData(
                      icon: Icons.badge_outlined,
                      color: AppColors.primary,
                      title: 'Editar tus datos',
                      subtitle: 'Usuario, bio, objetivo, curso, universidad…',
                      onTap: _openProfileEditor,
                    ),
                    _MenuItemData(
                      icon: Icons.assignment_ind_outlined,
                      color: AppColors.slate,
                      title: 'Rehacer el perfil entero',
                      subtitle: 'Vuelve a pasar por el alta',
                      onTap: _openOnboarding,
                    ),
                    _MenuItemData(
                      icon: Icons.inbox_rounded,
                      color: Colors.blueAccent,
                      title: 'Inbox',
                      subtitle: 'Mensajes y avisos',
                      trailing: _buildBadge('2'),
                      onTap: () {},
                    ),
                    _MenuItemData(
                      icon: Icons.help_outline_rounded,
                      color: Colors.purpleAccent,
                      title: 'Ayuda (FAQ)',
                      onTap: () {},
                    ),
                  ]),
                  const SizedBox(height: 26),
                  _buildSectionTitle('Preferencias'),
                  const SizedBox(height: 12),
                  _buildGroup([
                    _MenuItemData(
                      icon: Icons.notifications_outlined,
                      color: Colors.orange,
                      title: 'Notificaciones',
                      subtitle: 'Recordatorio del daily',
                      onTap: _openNotificationSettings,
                    ),
                    _MenuItemData(
                      icon: Icons.privacy_tip_outlined,
                      color: Colors.indigo,
                      title: 'Privacidad',
                      onTap: () {},
                    ),
                    _MenuItemData(
                      icon: Icons.dashboard_customize_outlined,
                      color: AppColors.primaryDark,
                      title: 'Barra de navegación',
                      subtitle: context.watch<SettingsProvider>().navBarStyle ==
                              NavBarStyle.floating
                          ? 'Flotante'
                          : 'Clásica',
                      onTap: _openNavBarStyleSettings,
                    ),
                    // MOCKUP de intro con música. Ver `intro_music.dart`.
                    _MenuItemData(
                      icon: Icons.music_note_outlined,
                      color: const Color(0xFF8E6BB8),
                      title: 'Música de la pantalla de carga',
                      trailing: Switch(
                        value: context.watch<SettingsProvider>().introMusic,
                        onChanged: (on) =>
                            context.read<SettingsProvider>().setIntroMusic(on),
                        activeColor: AppColors.primary,
                      ),
                      onTap: () {
                        final ajustes = context.read<SettingsProvider>();
                        ajustes.setIntroMusic(!ajustes.introMusic);
                      },
                    ),
                    _MenuItemData(
                      icon: Icons.dark_mode_outlined,
                      color: const Color(0xFF34495E),
                      title: 'Modo oscuro',
                      trailing: Switch(
                        value: false,
                        onChanged: (_) {},
                        activeColor: AppColors.primary,
                      ),
                      onTap: () {},
                    ),
                    _MenuItemData(
                      icon: Icons.new_releases_outlined,
                      color: AppColors.secondary,
                      title: 'Novedades',
                      subtitle: 'Versión ${BuildInfo.label}',
                      onTap: () {},
                    ),
                  ]),
                  const SizedBox(height: 30),
                  _buildLogoutButton(),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // CABECERA MODERNA
  // ===========================================================================
  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Mi perfil',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        _circleIconButton(Icons.ios_share_rounded, () {}),
      ],
    );
  }

  /// Estatus académico, a partir del curso.
  ///
  /// Solo el curso: el gorro de graduado que lleva el badge ya dice que eres
  /// estudiante, y "Estudiante de 3º" no cabía — se recortaba justo por el
  /// número, que es el único dato que aportaba.
  ///
  /// El 0 del onboarding es "Médico/a", no un curso cero.
  String? _estatusDe(UserProfile? p) {
    final year = p?.medicalYear;
    if (year == null) return null;
    if (year == 0) return 'Médico/a';
    return '$yearº';
  }

  Widget _buildHeader(
    String name,
    String handle,
    int avatarId,
    bool isPremium,
    List<String> chips,
  ) {
    final profile = context.read<AuthProvider>().profile;
    return ProfileCard(
      name: name,
      handle: handle,
      avatar: _buildRawAvatarImage(avatarId: avatarId),
      estatus: _estatusDe(profile),
      especialidad: profile?.mirSpecialty,
      universidad: profile?.university,
      bio: profile?.bio,
      isPremium: isPremium,
      campos: _campos,
      // La serie y las barras salen del id del usuario, así que son siempre
      // las mismas para la misma persona y coinciden con las de la web.
      seed: profile?.id ?? 'mirdaily',
      onTapAvatar: _showAvatarSelectionSheet,
      onTapBio: _openProfileEditor,
      onTapCampos: _openCardFieldPicker,
    );
  }

  /// Deja elegir qué datos aparecen en el carné.
  Future<void> _openCardFieldPicker() async {
    final elegidos = await showCardFieldPicker(context, _campos);
    if (elegidos == null || !mounted) return;
    setState(() => _campos = elegidos);
    CardFieldPrefs.save(elegidos);
  }

  /// Abre el editor de datos y refresca el perfil si guardó algo.
  Future<void> _openProfileEditor() async {
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;
    final saved = await showProfileEditor(context, profile);
    if (saved && mounted) context.read<AuthProvider>().refreshProfile();
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  // ===========================================================================
  // FILA DE ESTADÍSTICAS (datos reales del heatmap)
  // ===========================================================================
  Widget _buildStatsRow() {
    final current = _heatmap?.currentStreak ?? 0;
    final best = _heatmap?.longestStreak ?? 0;
    final dailys = _heatmap?.totalDailyDays ?? 0;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFEF8354),
            value: '$current',
            label: 'Racha',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.emoji_events_rounded,
            iconColor: AppColors.gold,
            value: '$best',
            label: 'Récord',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_rounded,
            iconColor: AppColors.success,
            value: '$dailys',
            label: 'Dailys',
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TARJETA PREMIUM
  // ===========================================================================
  Widget _buildPremiumCard(bool isPremium) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF2D3142), Color(0xFF1E212B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D3142).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isPremium ? Icons.workspace_premium : Icons.bolt_rounded,
                    color: AppColors.gold,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPremium ? 'MIRDaily PRO' : 'Hazte PRO',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isPremium
                            ? 'Tu plan está activo'
                            : 'Preguntas y estadísticas sin límites',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white54, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // GRUPOS DE AJUSTES
  // ===========================================================================
  Widget _buildSectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: kMuted.withOpacity(0.7),
            letterSpacing: 1.6,
          ),
        ),
      );

  Widget _buildGroup(List<_MenuItemData> items) {
    return StickerCard(
      depth: 4,
      radius: 22,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _buildMenuItem(items[i]),
            if (i != items.length - 1)
              const Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 62,
                  color: Color(0xFFF0EBE8)),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem(_MenuItemData d) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: d.onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: d.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(d.icon, color: d.color, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (d.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        d.subtitle!,
                        style:
                            TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
              d.trailing ??
                  const Icon(Icons.chevron_right,
                      size: 20, color: Color(0xFFC7C7CC)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.error, borderRadius: BorderRadius.circular(12)),
        child: Text(count,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      );

  Widget _buildLogoutButton() {
    return Center(
      child: TextButton.icon(
        onPressed: () => _handleLogout(context),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        ),
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text('Cerrar sesión',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  // ===========================================================================
  //  LÓGICA DE IMAGEN DE AVATAR (avatares reales del backend, ids 1..12)
  // ===========================================================================
  Widget _buildRawAvatarImage({required int avatarId}) {
    return Image.network(
      AppConfig.avatarUrl(avatarId),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: AppColors.primary.withOpacity(0.1),
          child: const Center(
            child: Icon(Icons.person, size: 50, color: AppColors.primary),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // SELECTOR DE AVATAR (BOTTOM SHEET)
  // ===========================================================================
  void _showAvatarSelectionSheet() {
    final auth = context.read<AuthProvider>();
    final currentId = auth.profile?.avatarId ?? 1;

    showAdaptiveModal<void>(
      context: context,
      dialogMaxWidth: 480,
      builder: (BuildContext sheetContext) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: const BoxDecoration(
                        color: Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.all(Radius.circular(2)))),
              ),
              const SizedBox(height: 20),
              const Text(
                "Elige tu avatar",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                "Selecciona una imagen que te represente.",
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: AppConfig.avatarCatalog.length,
                  itemBuilder: (context, index) {
                    final id = AppConfig.avatarCatalog[index];
                    final bool isSelected = currentId == id;
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final ok = await auth.updateAvatar(id);
                        if (!mounted) return;
                        if (!ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No se pudo actualizar el avatar'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected
                              ? Border.all(color: AppColors.primary, width: 3)
                              : Border.all(
                                  color: Colors.grey.shade200, width: 1),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: _buildRawAvatarImage(avatarId: id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openOnboarding() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OnboardingScreen(
          celebrateDaily: false,
          onFinished: () {
            // Al terminar, cerrar el asistente y refrescar la cabecera.
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            _load();
          },
          onSkip: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _openNotificationSettings() {
    showAdaptiveModal<void>(
      context: context,
      builder: (_) => const _NotificationSettingsSheet(),
    );
  }

  void _openNavBarStyleSettings() {
    final settings = context.read<SettingsProvider>();
    showAdaptiveModal<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Barra de navegación',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 19, color: kInk),
              ),
              const SizedBox(height: 4),
              const Text(
                'La clásica usa el raíl lateral en tablet horizontal. La '
                'flotante es un bocadillo despegado del borde, siempre.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              for (final style in NavBarStyle.values)
                _NavStyleOption(
                  style: style,
                  selected: settings.navBarStyle == style,
                  onTap: () {
                    settings.setNavBarStyle(style);
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context) {
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                title: const Text("Cerrar Sesión"),
                content:
                    const Text("Volverás a la pantalla de inicio de sesión."),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text("Cancelar",
                          style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white),
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        context.read<DailyProvider>().reset();
                        await context.read<AuthProvider>().signOut();
                      },
                      child: const Text("Cerrar Sesión"))
                ]));
  }
}

/// Datos de una fila de menú de ajustes.
class _MenuItemData {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItemData({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });
}

/// Una opción del selector de estilo de barra de navegación, con una
/// miniatura de cómo queda.
class _NavStyleOption extends StatelessWidget {
  const _NavStyleOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final NavBarStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final floating = style == NavBarStyle.floating;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      // Miniatura: una "pantalla" con la barra dentro. La clásica va pegada
      // al borde inferior a todo el ancho; la flotante es un bocadillo con
      // hueco por debajo.
      leading: Container(
        width: 44,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kHairline, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Padding(
              padding: floating
                  ? const EdgeInsets.fromLTRB(5, 0, 5, 4)
                  : EdgeInsets.zero,
              child: Container(
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(3),
                    bottom: Radius.circular(floating ? 3 : 0),
                  ),
                  border: Border.all(color: kHairline, width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        floating ? 'Flotante' : 'Clásica',
        style: TextStyle(
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          color: kInk,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        floating
            ? 'Bocadillo despegado del borde, estilo Apple Music. También en '
                'tablet horizontal.'
            : 'Pegada al borde. Raíl lateral en tablet horizontal.',
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 12.5),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded,
              color: AppColors.primaryDark)
          : null,
    );
  }
}

/// Tarjeta de estadística de la cabecera del perfil.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 20,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel de ajustes de notificaciones: recordatorio diario del daily.
class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  final _service = NotificationService();
  bool _loading = true;
  bool _enabled = false;
  bool _busy = false;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _service.isEnabled();
    final time = await _service.reminderTime();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _time = time;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    if (value) {
      final ok = await _service.enableDailyReminder(_time);
      if (!mounted) return;
      setState(() {
        _enabled = ok;
        _busy = false;
      });
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Activa el permiso de notificaciones para recibir el recordatorio.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      await _service.disableDailyReminder();
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Hora del recordatorio',
    );
    if (picked == null) return;
    setState(() => _time = picked);
    if (_enabled) {
      setState(() => _busy = true);
      await _service.enableDailyReminder(picked);
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Notificaciones',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Recibe un aviso diario cuando tu sobre del daily esté listo.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else ...[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _enabled,
                      onChanged: _busy ? null : _toggle,
                      activeColor: AppColors.primary,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: const Text('Recordatorio del daily',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      subtitle: const Text('Un aviso cada día',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    if (_enabled) ...[
                      const Divider(height: 1, color: AppColors.border),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        leading: const Icon(Icons.schedule_rounded,
                            color: AppColors.textSecondary),
                        title: const Text('Hora del aviso',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        trailing: Text(
                          _fmt(_time),
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        onTap: _busy ? null : _pickTime,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'El recordatorio se programa en tu dispositivo. Puedes cambiar la hora o desactivarlo cuando quieras.',
                style: TextStyle(color: AppColors.textLight, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
