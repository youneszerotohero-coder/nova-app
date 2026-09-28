import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/pressable_scale.dart';

/// D-073: a Live needs the Student's first and last name (the teaching
/// team sees them on questions and raised hands). Asked when the server
/// answers 422 `PROFILE_NAME_REQUIRED`, saved through `PUT /onboarding`
/// with the current references, then the Live continues (web
/// `live-name-required.tsx`).
class LiveNameForm extends StatefulWidget {
  const LiveNameForm({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<LiveNameForm> createState() => _LiveNameFormState();
}

class _LiveNameFormState extends State<LiveNameForm> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  String? _firstError;
  String? _lastError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final (String first, String last) = AppState.instance.session.storedName;
    _first = TextEditingController(text: first);
    _last = TextEditingController(text: last);
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String first = _first.text.trim();
    final String last = _last.text.trim();
    setState(() {
      _firstError = first.isEmpty ? context.tr('live.firstNameRequired') : null;
      _lastError = last.isEmpty ? context.tr('live.lastNameRequired') : null;
      _error = null;
    });
    if (first.isEmpty || last.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await AppState.instance.session.saveLiveName(firstName: first, lastName: last);
      if (mounted) widget.onSaved();
    } on ApiException catch (error) {
      if (!mounted) return;
      final Map<String, String> fields = error.fieldErrors;
      setState(() {
        _firstError = fields['first_name'];
        _lastError = fields['last_name'];
        _error = context.tr('live.nameError');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, String? error) => InputDecoration(
          labelText: label,
          errorText: error,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: NovaColors.textMutedOnDark),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        );

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: NovaColors.ink950.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.badge_rounded, size: 30, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              context.tr('live.nameTitle'),
              textAlign: TextAlign.center,
              style: NovaTypography.textTheme.titleMedium!.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('live.nameBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                height: 1.45,
                color: NovaColors.textMutedOnDark,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _first,
              maxLength: 255,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.givenName],
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NovaColors.textOnDark),
              decoration: field(context.tr('live.firstName'), _firstError).copyWith(counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _last,
              maxLength: 255,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.familyName],
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: NovaColors.textOnDark),
              decoration: field(context.tr('live.lastName'), _lastError).copyWith(counterText: ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: NovaColors.heartRed),
              ),
            ],
            const SizedBox(height: 16),
            PressableScale(
              onTap: _busy ? null : _submit,
              semanticLabel: context.tr('live.nameSubmit'),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: NovaColors.accentGradient,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : Text(
                        context.tr('live.nameSubmit'),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
