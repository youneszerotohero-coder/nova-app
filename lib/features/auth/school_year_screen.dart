import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/account_store.dart';
import '../../data/models.dart';
import 'auth_hero.dart';
import 'otp_widgets.dart';
import 'register_screen.dart';

/// D-098: a new school year was opened, so the Student keeps or changes
/// their level and filière before anything else
/// (`next_required_step: school_year`, `PUT /auth/school-year`).
class SchoolYearScreen extends StatefulWidget {
  const SchoolYearScreen({super.key});

  @override
  State<SchoolYearScreen> createState() => _SchoolYearScreenState();
}

class _SchoolYearScreenState extends State<SchoolYearScreen> {
  List<RefItem> _levels = const <RefItem>[];
  List<RefItem> _tracks = const <RefItem>[];
  RefItem? _level;
  RefItem? _track;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const <String, String>{};

  List<RefItem> get _levelTracks => _level?.tracksFrom(_tracks) ?? const <RefItem>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Active levels and filières, preselected with the Student's current ones.
  Future<void> _load() async {
    final AppState app = AppScope.of(context);
    final ReferenceStore? references = app.references;
    if (references == null) return;
    final (int? levelId, int? trackId) = app.session.schoolReferences;
    try {
      final List<List<RefItem>> lists =
          await Future.wait(<Future<List<RefItem>>>[references.levels(), references.tracks()]);
      if (!mounted) return;
      setState(() {
        _levels = lists[0];
        _tracks = lists[1];
        _level = _levels.where((RefItem l) => l.id == levelId).firstOrNull;
        _track = _levelTracks.where((RefItem t) => t.id == trackId).firstOrNull;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(context, error));
    }
  }

  Future<void> _confirm() async {
    final String required = context.tr('auth.fieldRequired');
    final Map<String, String> local = <String, String>{
      if (_level == null) 'level_id': required,
      if (_level != null && _level!.hasTracks && _track == null) 'track_id': required,
    };
    if (local.isNotEmpty) {
      setState(() {
        _fieldErrors = local;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const <String, String>{};
    });
    try {
      // The root gate moves on once the step is done.
      await AppScope.of(context).session.confirmSchoolYear(
            levelId: _level!.id,
            trackId: _level!.hasTracks ? _track?.id : null,
          );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        final Map<String, String> fields =
            error.code == ApiException.validationFailed ? error.fieldErrors : const <String, String>{};
        // A field error is shown next to its field only.
        _fieldErrors = fields;
        _error = fields.isEmpty ? apiErrorText(context, error) : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AuthHero(
            title: context.tr('schoolYear.title'),
            subtitle: context.tr('schoolYear.subtitle'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RefPickerField(
                  label: context.tr('auth.level'),
                  value: _level,
                  options: _levels,
                  icon: Icons.school_rounded,
                  error: _fieldErrors['level_id'],
                  onChanged: (RefItem? value) => setState(() {
                    _level = value;
                    if (!_levelTracks.any((RefItem t) => t.id == _track?.id)) _track = null;
                  }),
                ),
                RefPickerField(
                  label: context.tr('settings.track'),
                  value: _track,
                  options: _levelTracks,
                  icon: Icons.account_tree_rounded,
                  enabled: _level?.hasTracks ?? false,
                  emptyHint: (_level?.hasTracks ?? false) ? null : context.tr('auth.trackNotRequired'),
                  error: _fieldErrors['track_id'],
                  onChanged: (RefItem? value) => setState(() => _track = value),
                ),
                if (_error != null) AuthMessage(_error!),
                const SizedBox(height: 6),
                AuthSubmitButton(
                  label: context.tr('schoolYear.confirm'),
                  busy: _busy,
                  onTap: _confirm,
                ),
                const SizedBox(height: 14),
                Center(
                  child: PressableScale(
                    onTap: () => AppScope.of(context).session.logout(),
                    semanticLabel: 'Sign out',
                    child: Text(
                      context.tr('settings.signOut'),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: NovaColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
