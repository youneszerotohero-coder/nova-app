import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/otp.dart';

/// Shared pieces of the D-093/D-096 code flows: forgotten password,
/// registration phone verification and password change.

/// "SMS" or "WhatsApp", for the "a code was sent by {channel}" texts.
String otpChannelName(BuildContext context, OtpChannel channel) =>
    context.tr(channel == OtpChannel.whatsapp ? 'otp.channelWhatsapp' : 'otp.channelSms');

/// Seconds left before a new code may be asked (one code a minute per
/// number, D-093); the server's `resend_in` / `retry_after` starts it.
mixin ResendCountdown<T extends StatefulWidget> on State<T> {
  int resendIn = 0;
  Timer? _resendTimer;

  void startResend(int seconds) {
    _resendTimer?.cancel();
    setState(() => resendIn = seconds < 0 ? 0 : seconds);
    if (resendIn == 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted || resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => resendIn = 0);
        return;
      }
      setState(() => resendIn--);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }
}

/// D-096: the Student chooses how the code arrives, SMS (default) or
/// WhatsApp.
class OtpChannelChoice extends StatelessWidget {
  const OtpChannelChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final OtpChannel value;
  final ValueChanged<OtpChannel> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('otp.channelLabel'), style: NovaTypography.textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final OtpChannel channel in OtpChannel.values) ...[
                if (channel != OtpChannel.values.first) const SizedBox(width: 10),
                Expanded(child: _option(context, channel)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, OtpChannel channel) {
    final bool selected = channel == value;
    final String label = otpChannelName(context, channel);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PressableScale(
        onTap: enabled ? () => onChanged(channel) : null,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? NovaColors.accentMist : NovaColors.paperCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? NovaColors.accent : NovaColors.borderOnLight,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                channel == OtpChannel.whatsapp ? Icons.chat_rounded : Icons.sms_outlined,
                size: 18,
                color: selected ? NovaColors.accentDeep : NovaColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: selected ? NovaColors.accentDeep : NovaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled auth input with its field error underneath.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.icon,
    required this.label,
    required this.hint,
    this.obscure = false,
    this.keyboard,
    this.autofill,
    this.formatters,
    this.trailing,
    this.error,
    this.enabled = true,
    this.onSubmitted,
  });

  /// The 6-digit code input.
  factory AuthTextField.code({
    Key? key,
    required TextEditingController controller,
    required String label,
    String? error,
    ValueChanged<String>? onSubmitted,
  }) =>
      AuthTextField(
        key: key,
        controller: controller,
        icon: Icons.password_rounded,
        label: label,
        hint: '••••••',
        keyboard: TextInputType.number,
        autofill: AutofillHints.oneTimeCode,
        formatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        error: error,
        onSubmitted: onSubmitted,
      );

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hint;
  final bool obscure;
  final TextInputType? keyboard;
  final String? autofill;
  final List<TextInputFormatter>? formatters;
  final Widget? trailing;
  final String? error;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: NovaTypography.textTheme.labelMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: NovaColors.paperCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: error == null
                    ? NovaColors.borderOnLight
                    : NovaHue.rose.solid.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: NovaColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    obscureText: obscure,
                    autocorrect: false,
                    keyboardType: keyboard,
                    inputFormatters: formatters,
                    autofillHints: autofill == null ? null : <String>[autofill!],
                    onSubmitted: onSubmitted,
                    style: NovaTypography.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                error!,
                style: NovaTypography.textTheme.labelSmall!.copyWith(color: NovaHue.rose.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}

/// The eye toggle of a password field.
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({super.key, required this.obscure, required this.onToggle});

  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onToggle,
      semanticLabel: 'Show password',
      child: Icon(
        obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 20,
        color: NovaColors.textMuted,
      ),
    );
  }
}

/// The dark full-width pill of the auth screens, with a spinner while busy.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({super.key, required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: busy ? null : onTap,
      pressedScale: 0.97,
      semanticLabel: label,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: NovaColors.ink950,
          borderRadius: BorderRadius.circular(100),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: NovaColors.textOnDark),
              )
            : Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: NovaColors.textOnDark,
                ),
              ),
      ),
    );
  }
}

/// A small accent text button ("Send a new code", "Change the number").
class AuthTextAction extends StatelessWidget {
  const AuthTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: onTap == null ? NovaColors.textMuted : NovaColors.accentDeep,
          ),
        ),
      ),
    );
  }
}

/// An error (rose) or status (accent) line under a form.
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text, {super.key, this.error = true});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: NovaTypography.textTheme.bodySmall!.copyWith(
            color: error ? NovaHue.rose.onSurface : NovaColors.accentDeep,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The resend label: "New code in {seconds} s" while waiting.
String resendLabel(BuildContext context, int seconds, {String idleKey = 'otp.resend'}) => seconds > 0
    ? context.trf('otp.resendIn', <String, String>{'seconds': '$seconds'})
    : context.tr(idleKey);
