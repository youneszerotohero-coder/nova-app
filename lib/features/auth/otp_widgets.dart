import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
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
/// WhatsApp (`.otpChannelChoice`).
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('otp.channelLabel'), style: authLabelStyle),
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
    final Color ink = selected ? NovaColors.accent : NovaColors.textStrong;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PressableScale(
        onTap: enabled ? () => onChanged(channel) : null,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? NovaColors.accentMist : NovaColors.paperCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? NovaColors.accent : NovaColors.lineStrong, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(channel == OtpChannel.whatsapp ? Icons.chat_outlined : Icons.sms_outlined, size: 17, color: ink),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _baloo(16, ink, weight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _baloo(double size, Color color, {FontWeight weight = FontWeight.w800, double height = 1.3}) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: weight,
      fontSize: size,
      height: height,
      color: color,
    );

TextStyle _body(double size, Color color, {FontWeight weight = FontWeight.w400, double height = 1.5}) => TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: weight,
      fontSize: size,
      height: height,
      color: color,
    );

/// `.authForm label > span`: the field label, Baloo 16 / 700 in ink.
TextStyle get authLabelStyle => _baloo(16, NovaColors.textStrong, weight: FontWeight.w700);

/// The text typed in an auth field and its placeholder.
TextStyle get authInputStyle => _body(16, NovaColors.textStrong);
TextStyle get authHintStyle => _body(16, NovaColors.textMuted);

/// `.authForm label`: the label, then the 56 px field (1.5 px
/// `--hx-line-strong`, radius 16, the icon at the start) that turns blue with
/// a `--hx-blue-soft` ring when focused and danger-tinted when invalid, then
/// the field error.
class AuthFieldFrame extends StatefulWidget {
  const AuthFieldFrame({
    super.key,
    required this.label,
    required this.child,
    this.icon,
    this.trailing,
    this.error,
    this.enabled = true,
  });

  final String label;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final String? error;
  final bool enabled;

  @override
  State<AuthFieldFrame> createState() => _AuthFieldFrameState();
}

class _AuthFieldFrameState extends State<AuthFieldFrame> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool invalid = widget.error != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: authLabelStyle),
          const SizedBox(height: 8),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (bool focused) => setState(() => _focused = focused),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: widget.enabled ? 1 : 0.55,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: invalid ? NovaColors.dangerBg : NovaColors.paperCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: invalid ? NovaColors.heartRed : (_focused ? NovaColors.accent : NovaColors.lineStrong),
                    width: 1.5,
                  ),
                  boxShadow: _focused ? [BoxShadow(spreadRadius: 4, color: NovaColors.accentMist)] : null,
                ),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 17, color: NovaColors.textMuted),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: widget.child),
                    ?widget.trailing,
                  ],
                ),
              ),
            ),
          ),
          if (invalid)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 6),
              child: Text(widget.error!, style: _body(14, NovaColors.heartRed, weight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

/// The bare input inside an [AuthFieldFrame].
InputDecoration authInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: authHintStyle,
      border: InputBorder.none,
      isCollapsed: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
    );

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
    this.onChanged,
    this.action,
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
        icon: Icons.lock_outline_rounded,
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
  final ValueChanged<String>? onChanged;
  final TextInputAction? action;

  @override
  Widget build(BuildContext context) {
    return AuthFieldFrame(
      label: label,
      icon: icon,
      trailing: trailing,
      error: error,
      enabled: enabled,
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        autocorrect: false,
        keyboardType: keyboard,
        textInputAction: action,
        inputFormatters: formatters,
        autofillHints: autofill == null ? null : <String>[autofill!],
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: authInputStyle,
        decoration: authInputDecoration(hint),
      ),
    );
  }
}

/// The eye of a password field: blue, a 44 px target.
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({super.key, required this.obscure, required this.onToggle});

  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onToggle,
      semanticLabel: 'Show password',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 18,
          color: NovaColors.accent,
        ),
      ),
    );
  }
}

/// `.authSubmit`: the full-width blue button, 56 high, radius 17, 17 px
/// Baloo 800 and the arrow, with its blue shadow; a spinner while busy.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({super.key, required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: busy ? null : onTap,
      pressedScale: 0.98,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: NovaColors.accent,
          borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
          boxShadow: busy ? null : const [BoxShadow(offset: Offset(0, 14), blurRadius: 26, spreadRadius: -16, color: Color(0xCC1F54D6))],
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(label, textAlign: TextAlign.center, style: _baloo(17, Colors.white, height: 1.2))),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                ],
              ),
      ),
    );
  }
}

/// `.authBack`: the outlined companion of [AuthSubmitButton] ("Previous",
/// "Send the code", "Verify").
class AuthOutlineButton extends StatelessWidget {
  const AuthOutlineButton({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.98,
        semanticLabel: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
            border: Border.all(color: NovaColors.lineStrong, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: NovaColors.textStrong), const SizedBox(width: 8)],
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: _baloo(16, NovaColors.textStrong, height: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.authLinkButton`: a blue Baloo 800 link ("Send a new code", "Change
/// the number"), grey while it cannot be used.
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(label, style: _baloo(15, onTap == null ? NovaColors.textMuted : NovaColors.accent)),
      ),
    );
  }
}

/// An error under a form (`.authError`: `--hx-danger-bg`, the danger text,
/// radius 14), or a status line (`.manualResetNote`, ink-2).
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text, {super.key, this.error = true});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Semantics(
        liveRegion: true,
        child: error
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                decoration: BoxDecoration(color: NovaColors.dangerBg, borderRadius: BorderRadius.circular(14)),
                child: Text(text, style: _body(15, NovaColors.heartRed, weight: FontWeight.w600)),
              )
            : Text(text, style: _body(15, NovaColors.textBody, height: 1.55)),
      ),
    );
  }
}

/// `.authNotice`: a success line (`--hx-success-bg`) with its check.
class AuthNotice extends StatelessWidget {
  const AuthNotice(this.text, {super.key, this.icon = Icons.check_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(color: NovaColors.liveBg, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: NovaColors.onlineGreen),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: _body(15, NovaColors.onlineGreen, weight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

/// `.authGroup legend`: a blue group title on the hairline that opens it.
class AuthGroupLegend extends StatelessWidget {
  const AuthGroupLegend(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      // The legend sits on the line, on the page's surface.
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Positioned.fill(child: Center(child: Container(height: 1, color: NovaColors.borderOnLight))),
          Container(
            color: NovaColors.paperCard,
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Text(text, style: _baloo(15, NovaColors.accent)),
          ),
        ],
      ),
    );
  }
}

/// The resend label: "New code in {seconds} s" while waiting.
String resendLabel(BuildContext context, int seconds, {String idleKey = 'otp.resend'}) => seconds > 0
    ? context.trf('otp.resendIn', <String, String>{'seconds': '$seconds'})
    : context.tr(idleKey);
