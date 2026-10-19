import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/nova_image.dart';
import '../../data/assistant_store.dart';
import 'assistant_links.dart';

/// The website's assistant tokens (`assistant-chat.css`, `--as-*`), with
/// their dark values.
class _As {
  static bool get _dark => NovaColors.current.isDark;
  static const Color ink = Color(0xFF0F1B2A);
  static const Color blue = Color(0xFF2563EB);
  static const Color sky = Color(0xFF4FACF0);
  static const Color good = Color(0xFF1F9D63);
  static const Color wait = Color(0xFFC27C16);
  static Color get panel => _dark ? const Color(0xFF151B23) : Colors.white;
  static Color get soft => _dark ? const Color(0xFF1E2630) : const Color(0xFFF2F5F9);
  static Color get line => _dark ? const Color(0xFF2A3440) : const Color(0xFFE1E6EC);
  static Color get text => _dark ? const Color(0xFFE8EDF3) : const Color(0xFF1D2733);
  static Color get muted => _dark ? const Color(0xFF9AA6B4) : const Color(0xFF6B7684);
  static Color get linkBlue => _dark ? sky : blue;
}

/// D-150: the website's floating assistant button (`.assistantFab`) in the
/// Student space and for visitors, above the tab bar on the start side.
class AssistantFab extends StatelessWidget {
  const AssistantFab({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('assistant.open'),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const AssistantScreen()),
        ),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[_As.ink, Color(0xFF1D3B5C)],
            ),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x520F1B2A), blurRadius: 34, offset: Offset(0, 14))],
          ),
          child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// D-150: the website's assistant panel as it shows on a phone (full
/// screen): the navy head, the conversation with its cards and links, the
/// first-visit suggestions, and the composer.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.store});

  /// Tests pass their own store; the app builds one on its API.
  final AssistantStore? store;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  AssistantStore? _store;
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store != null) return;
    final AppState app = AppScope.of(context);
    final AssistantStore store = widget.store ?? AssistantStore(app.api!, signedIn: app.session.signedIn);
    _store = store..addListener(_changed);
    if (!store.loaded) store.load();
  }

  @override
  void dispose() {
    _store?.removeListener(_changed);
    if (widget.store == null) _store?.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send([String? suggestion]) async {
    final String text = suggestion ?? _text.text;
    if (text.trim().isEmpty) return;
    if (suggestion == null) _text.clear();
    final String? back = await _store!.send(text);
    if (back != null && suggestion == null && mounted) _text.text = back;
  }

  void _go(String href) => openAssistantHref(context, href);

  String _errorText(ApiException error, AssistantStore store) {
    if ((error.status >= 400 && error.status < 500) || error.code.startsWith('ASSISTANT_')) return apiErrorText(context, error);
    return context.tr(store.loadFailed ? 'assistant.loadError' : 'assistant.sendError');
  }

  @override
  Widget build(BuildContext context) {
    final AssistantStore store = _store!;
    final ApiException? error = store.error;
    final bool empty = store.loaded && store.messages.isEmpty;
    return Scaffold(
      backgroundColor: _As.panel,
      body: Column(
        children: [
          _Head(onReset: store.sending ? null : store.reset, onClose: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              children: [
                if (empty) _Welcome(signedIn: store.signedIn, onPick: _send),
                if (!store.loaded && error == null) const Align(alignment: AlignmentDirectional.centerStart, child: _Typing()),
                for (final AssistantMessage message in store.messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _Message(message: message, onGo: _go),
                  ),
                if (store.sending) const Align(alignment: AlignmentDirectional.centerStart, child: _Typing()),
              ],
            ),
          ),
          if (error != null)
            Container(
              width: double.infinity,
              color: const Color(0x14DC2626),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_errorText(error, store), style: const TextStyle(color: Color(0xFFC62828), fontSize: 12.5)),
                  ),
                  if (store.loadFailed)
                    TextButton(onPressed: store.load, child: Text(context.tr('common.retry'))),
                ],
              ),
            ),
          _Composer(controller: _text, sending: store.sending, onSend: () => _send()),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.onReset, required this.onClose});

  final VoidCallback? onReset;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[_As.ink, Color(0xFF17324F)]),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: const Color(0x2E4FACF0), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Color(0xFF8FD0FA)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.tr('assistant.title'), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('assistant.subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFB6C6D8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onReset,
                tooltip: context.tr('assistant.reset'),
                icon: const Icon(Icons.restart_alt_rounded, size: 20, color: Color(0xFFC9D6E4)),
              ),
              IconButton(
                onPressed: onClose,
                tooltip: context.tr('common.close'),
                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFFC9D6E4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.signedIn, required this.onPick});

  final bool signedIn;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final List<String> suggestions = signedIn
        ? <String>['assistant.suggestMissing', 'assistant.suggestBuy', 'assistant.suggestVideo']
        : <String>['assistant.suggestLevel', 'assistant.suggestBuy', 'assistant.suggestAccountHow'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: _As.soft, borderRadius: BorderRadius.circular(16)),
            child: Text(context.tr('assistant.welcome'), style: TextStyle(color: _As.text, fontSize: 14, height: 1.5)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final String key in suggestions)
                OutlinedButton(
                  onPressed: () => onPick(context.tr(key)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _As.linkBlue,
                    backgroundColor: _As.panel,
                    side: BorderSide(color: _As.line),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  child: Text(context.tr(key)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onGo});

  final AssistantMessage message;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context) {
    final bool mine = message.student;
    return Opacity(
      opacity: message.pending ? 0.65 : 1,
      child: Align(
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.92),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < message.blocks.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _block(context, message.blocks[i], mine),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(BuildContext context, AssistantBlock block, bool mine) => switch (block.type) {
        'text' => _TextBubble(text: block.text, mine: mine),
        'product' => _ProductCard(block: block, onGo: onGo),
        'link' => _LinkChip(block: block, onGo: onGo),
        _ => _OrderCard(block: block, onGo: onGo),
      };
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    const Radius round = Radius.circular(16);
    const Radius tail = Radius.circular(5);
    final Color ink = mine ? Colors.white : _As.text;
    final TextStyle style = TextStyle(color: ink, fontSize: 14, height: 1.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? _As.blue : _As.soft,
        borderRadius: BorderRadiusDirectional.only(
          topStart: round,
          topEnd: round,
          bottomStart: mine ? round : tail,
          bottomEnd: mine ? tail : round,
        ),
      ),
      child: Directionality(
        textDirection: assistantTextDirection(text) ?? Directionality.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final AssistantLine line in assistantLines(text))
              Padding(
                padding: EdgeInsets.only(top: line.gap ? 6 : (line.bullet ? 3 : 0)),
                child: line.bullet
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: style),
                          Expanded(child: Text.rich(TextSpan(children: assistantSpans(line.text)), style: style)),
                        ],
                      )
                    : Text.rich(TextSpan(children: assistantSpans(line.text)), style: style),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.block, required this.onGo});

  final AssistantBlock block;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context) {
    final String? cover = block.coverUrl;
    final String subtitle = block.isOffer && block.subtitle.isNotEmpty && K.containsKey('offer.type_${block.subtitle}')
        ? context.tr('offer.type_${block.subtitle}')
        : block.subtitle;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _As.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: block.owned ? _As.good.withValues(alpha: 0.45) : _As.line),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x0F0F1B2A), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: NovaColors.current.isDark
                            ? const <Color>[Color(0xFF1D2C3E), Color(0xFF16324F)]
                            : const <Color>[Color(0xFFE8F2FD), Color(0xFFD7E7FB)],
                      ),
                    ),
                    child: Icon(block.isOffer ? Icons.inventory_2_outlined : Icons.menu_book_outlined, size: 28, color: _As.linkBlue),
                  ),
                  if (cover != null) Image(image: novaImageProvider(cover, cacheWidth: 276), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  PositionedDirectional(
                    top: 7,
                    start: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xC70F1B2A), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        context.tr(block.isOffer ? 'kind.offer' : 'assistant.kindUnit'),
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(block.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _As.text, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _As.muted, fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: block.owned
                              ? Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline_rounded, size: 14, color: _As.good),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(context.tr('assistant.owned'), style: const TextStyle(color: _As.good, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                )
                              : Text(
                                  block.price == 0 ? context.tr('assistant.free') : formatDaPrice(block.price),
                                  style: TextStyle(color: _As.text, fontSize: 13.5, fontWeight: FontWeight.w800),
                                ),
                        ),
                        _DarkButton(label: context.tr(block.owned ? 'assistant.openCourse' : 'assistant.view'), onTap: () => onGo(block.href)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkButton extends StatelessWidget {
  const _DarkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NovaColors.current.isDark ? _As.blue : _As.ink,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const _Arrow(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// lucide `ArrowUpRight`, mirrored in Arabic.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Transform.flip(flipX: rtl, child: Icon(Icons.north_east_rounded, size: 14, color: color));
  }
}

/// The website's link labels (`LINK_LABELS`); an unknown target shows as is.
const Map<String, String> _linkLabels = <String, String>{
  'my_courses': 'assistant.linkMyCourses',
  'my_orders': 'assistant.linkMyOrders',
  'my_lives': 'assistant.linkMyLives',
  'my_chats': 'chat.title',
  'account_settings': 'assistant.linkSettings',
  'packs': 'assistant.linkPacks',
  'courses': 'assistant.linkCourses',
  'cart': 'assistant.linkCart',
  'device_check': 'assistant.linkDeviceCheck',
  'forgot_password': 'assistant.linkForgotPassword',
  'login': 'assistant.linkLogin',
  'register': 'assistant.linkRegister',
};

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.block, required this.onGo});

  final AssistantBlock block;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context) {
    final String? key = _linkLabels[block.target];
    return Material(
      color: _As.soft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: _As.line)),
      child: InkWell(
        onTap: () => onGo(block.href),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(key == null ? block.target : context.tr(key), style: TextStyle(color: _As.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              _Arrow(color: _As.text),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.block, required this.onGo});

  final AssistantBlock block;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context) {
    final Color tone = block.paid ? _As.good : _As.wait;
    final TextStyle small = TextStyle(color: _As.muted, fontSize: 12);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(color: _As.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: _As.line)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: Icon(block.paid ? Icons.check_circle_outline_rounded : Icons.schedule_rounded, size: 19, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${context.tr('assistant.order')} ${block.orderNumber}', style: small),
                if (block.title.isNotEmpty)
                  Text(block.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _As.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(
                  '${formatDaPrice(block.amount)} · ${context.tr(block.paid ? 'assistant.orderPaid' : 'assistant.orderReview')}',
                  style: small,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onGo(block.href),
            tooltip: context.tr('assistant.linkMyOrders'),
            style: IconButton.styleFrom(
              side: BorderSide(color: _As.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              minimumSize: const Size(32, 32),
            ),
            icon: _Arrow(color: _As.text),
          ),
        ],
      ),
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('assistant.typing'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _As.soft, borderRadius: BorderRadius.circular(16)),
        child: AnimatedBuilder(
          animation: _dots,
          builder: (BuildContext context, Widget? _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 4),
                  child: Opacity(
                    opacity: 0.35 + 0.65 * (1 - ((_dots.value - i * 0.15) % 1 - 0.5).abs() * 2).clamp(0.0, 1.0),
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(color: _As.muted, shape: BoxShape.circle)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: _As.panel, border: Border(top: BorderSide(color: _As.line))),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
          decoration: BoxDecoration(color: _As.soft, borderRadius: BorderRadius.circular(16), border: Border.all(color: _As.line)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: AssistantStore.maxTextLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  buildCounter: (_, {required int currentLength, required bool isFocused, required int? maxLength}) => null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontFamily: NovaTypography.body, fontFamilyFallback: NovaTypography.fallback, fontSize: 15, height: 1.4, color: _As.text),
                  decoration: InputDecoration(
                    hintText: context.tr('assistant.placeholder'),
                    hintStyle: TextStyle(color: _As.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (BuildContext context, TextEditingValue value, Widget? _) {
                  final bool enabled = !sending && value.text.trim().isNotEmpty;
                  return Semantics(
                    button: true,
                    label: context.tr('assistant.send'),
                    child: GestureDetector(
                      onTap: enabled ? onSend : null,
                      child: Opacity(
                        opacity: enabled ? 1 : 0.4,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: _As.blue, borderRadius: BorderRadius.circular(NovaDimens.radiusSmall)),
                          child: const Icon(Icons.send_rounded, size: 17, color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of an assistant text: a paragraph or a `-` bullet; [gap] when
/// it starts a new paragraph or list after another one (the website's 6 px).
@immutable
class AssistantLine {
  const AssistantLine(this.text, {required this.bullet, required this.gap});

  final String text;
  final bool bullet;
  final bool gap;
}

/// The website's `formatText`: paragraphs and `-`/`*`/`•` bullet lines.
List<AssistantLine> assistantLines(String text) {
  final RegExp bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
  final List<AssistantLine> lines = <AssistantLine>[];
  bool? previousBullet;
  for (final String line in text.split('\n')) {
    final RegExpMatch? match = bullet.firstMatch(line);
    if (match == null && line.trim().isEmpty) continue;
    final bool isBullet = match != null;
    final bool gap = previousBullet != null && !(isBullet && previousBullet);
    lines.add(AssistantLine(isBullet ? match.group(1)! : line, bullet: isBullet, gap: gap));
    previousBullet = isBullet;
  }
  return lines;
}

/// The website's `bold`: `**bold**`, `*emphasis*` and `` `code` `` marks.
List<InlineSpan> assistantSpans(String line) {
  final RegExp marks = RegExp(r'(\*\*[^*]+\*\*|\*[^*\s][^*]*\*|`[^`]+`)');
  final List<InlineSpan> spans = <InlineSpan>[];
  int start = 0;
  for (final RegExpMatch match in marks.allMatches(line)) {
    if (match.start > start) spans.add(TextSpan(text: line.substring(start, match.start)));
    final String part = match.group(0)!;
    if (part.length > 4 && part.startsWith('**')) {
      spans.add(TextSpan(text: part.substring(2, part.length - 2), style: const TextStyle(fontWeight: FontWeight.w700)));
    } else if (part.startsWith('`')) {
      spans.add(TextSpan(text: part.substring(1, part.length - 1)));
    } else {
      spans.add(TextSpan(text: part.substring(1, part.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
    }
    start = match.end;
  }
  if (start < line.length) spans.add(TextSpan(text: line.substring(start)));
  return spans;
}

/// The website's `dir="auto"`: the first strong letter decides; null when
/// there is none (digits only), so the page's direction applies.
TextDirection? assistantTextDirection(String text) {
  for (final int code in text.runes) {
    if ((code >= 0x0590 && code <= 0x08FF) || (code >= 0xFB1D && code <= 0xFEFC)) return TextDirection.rtl;
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) || (code >= 0xC0 && code <= 0x024F)) return TextDirection.ltr;
  }
  return null;
}
