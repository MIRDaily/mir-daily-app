import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/models.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/sticker/textures.dart';

/// Editor de los datos del perfil: objetivo, curso, especialidad,
/// universidad, bio, visibilidad y username.
///
/// Escribe contra `/api/profile/academic` (edición parcial) y, para el
/// username, contra `/api/profile/username`. **No** usa `/onboarding`, que
/// reescribe el perfil entero y reiniciaría el bloqueo de 30 días del
/// username sin que el usuario lo haya pedido.
///
/// Devuelve true si algo se guardó, para que quien lo abre refresque.
Future<bool> showProfileEditor(BuildContext context, UserProfile profile) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileEditorSheet(profile: profile),
  );
  return saved ?? false;
}

class _ProfileEditorSheet extends StatefulWidget {
  final UserProfile profile;

  const _ProfileEditorSheet({required this.profile});

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  static const _goals = {
    'prepare_mir': 'Preparar el MIR',
    'reinforce_degree': 'Reforzar la carrera',
    'explore': 'Explorar',
  };

  late final TextEditingController _bio =
      TextEditingController(text: widget.profile.bio ?? '');
  late final TextEditingController _username =
      TextEditingController(text: widget.profile.username ?? '');

  late String? _goal = widget.profile.mainGoal;
  late int? _year = widget.profile.medicalYear;
  late int? _specialtyId = widget.profile.mirSpecialtyId;
  late int? _universityId = widget.profile.universityId;
  late bool _public = widget.profile.profilePublic;

  List<University> _universities = [];
  List<MirSpecialty> _specialties = [];
  bool _loadingCatalogs = true;
  bool _saving = false;
  String? _error;
  String? _usernameError;

  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  @override
  void dispose() {
    _bio.dispose();
    _username.dispose();
    super.dispose();
  }

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
        _loadingCatalogs = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Sin catálogos se puede editar igual todo lo demás; solo se ocultan
      // los dos desplegables.
      setState(() => _loadingCatalogs = false);
    }
  }

  bool get _usernameChanged {
    final next = _username.text.toLowerCase().trim();
    return next.isNotEmpty && next != (widget.profile.username ?? '');
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _usernameError = null;
    });

    // El username va primero y por separado: si lo rechazan (bloqueo o
    // repetido) el resto de datos se guarda igual, y así el usuario no pierde
    // lo que acaba de escribir.
    if (_usernameChanged) {
      try {
        await _api.updateUsername(_username.text);
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _usernameError = e.message);
      } catch (_) {
        if (!mounted) return;
        setState(() => _usernameError = 'No se pudo cambiar el username.');
      }
    }

    try {
      await _api.updateAcademicProfile(
        mainGoal: _goal,
        medicalYear: _year,
        mirSpecialtyId: _specialtyId,
        universityId: _universityId,
        profilePublic: _public,
        bio: _bio.text.trim(),
      );
      if (!mounted) return;
      // Si el username falló, se queda abierto enseñando por qué.
      if (_usernameError != null) {
        setState(() => _saving = false);
        return;
      }
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron guardar los cambios.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.profile.usernameLocked;
    final bioLen = _bio.text.characters.length;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: StickerCard(
          depth: 6,
          texture: laminatedPaper(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tus datos',
                      style: TextStyle(
                        color: kInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  InkIconButton(
                    icon: Icons.close_rounded,
                    size: 38,
                    onTap: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Label('Nombre de usuario'),
                      InkInput(
                        controller: _username,
                        prefix: '@',
                        maxLength: 20,
                        enabled: !locked,
                        invalid: _usernameError != null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _usernameError ??
                            (locked
                                ? 'Solo se puede cambiar cada '
                                    '${ApiService.usernameCooldownDays} días. '
                                    'Podrás volver a hacerlo el '
                                    '${_formatDate(widget.profile.usernameNextChangeAt!)}.'
                                : 'Solo se puede cambiar cada '
                                    '${ApiService.usernameCooldownDays} días.'),
                        style: TextStyle(
                          color: _usernameError != null
                              ? const Color(0xFFC4655A)
                              : kMuted.withOpacity(0.9),
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),

                      _Label('Sobre ti  ·  $bioLen/${ApiService.maxBioLength}'),
                      InkInput(
                        controller: _bio,
                        hint: 'Una línea sobre ti (opcional)',
                        maxLines: 3,
                        maxLength: ApiService.maxBioLength,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 18),

                      const _Label('Tu objetivo'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in _goals.entries)
                            _Choice(
                              label: entry.value,
                              active: _goal == entry.key,
                              onTap: () => setState(
                                () => _goal = _goal == entry.key ? null : entry.key,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      const _Label('Curso'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var y = 1; y <= 6; y++)
                            _Choice(
                              label: '$yº',
                              active: _year == y,
                              onTap: () =>
                                  setState(() => _year = _year == y ? null : y),
                            ),
                          _Choice(
                            label: 'Médico/a',
                            active: _year == 0,
                            onTap: () =>
                                setState(() => _year = _year == 0 ? null : 0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      if (_loadingCatalogs)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: AppColors.primary),
                            ),
                          ),
                        )
                      else ...[
                        if (_specialties.isNotEmpty) ...[
                          const _Label('Especialidad que te atrae'),
                          _Dropdown<int>(
                            value: _specialtyId,
                            hint: 'Sin decidir',
                            items: [
                              for (final s in _specialties)
                                DropdownMenuItem(value: s.id, child: Text(s.name)),
                            ],
                            onChanged: (v) => setState(() => _specialtyId = v),
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (_universities.isNotEmpty) ...[
                          const _Label('Universidad'),
                          _Dropdown<int>(
                            value: _universityId,
                            hint: 'Sin indicar',
                            items: [
                              for (final u in _universities)
                                DropdownMenuItem(value: u.id, child: Text(u.name)),
                            ],
                            onChanged: (v) => setState(() => _universityId = v),
                          ),
                          const SizedBox(height: 18),
                        ],
                      ],

                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Perfil público',
                                  style: TextStyle(
                                    color: kInk,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Otros usuarios podrán verte.',
                                  style: TextStyle(color: kMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          InkSwitch(
                            value: _public,
                            onChanged: (v) => setState(() => _public = v),
                          ),
                        ],
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFC4655A),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              StickerButton(
                label: _saving ? 'Guardando…' : 'Guardar cambios',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return '${d.day} de ${months[d.month - 1]} de ${d.year}';
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          color: kMuted.withOpacity(0.85),
        ),
      ),
    );
  }
}

/// Pastilla elegible, con el trazo de tinta al activarse.
class _Choice extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? kInk : kHairline, width: 2),
          boxShadow: active ? inkShadow(2) : const [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : kMuted,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline, width: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          hint: Text(hint, style: const TextStyle(color: kMuted, fontSize: 14)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kMuted),
          style: const TextStyle(
            color: kInk,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          items: [
            DropdownMenuItem<T>(
              value: null,
              child: Text(hint, style: const TextStyle(color: kMuted)),
            ),
            ...items,
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
