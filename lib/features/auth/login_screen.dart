import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'auth_chrome.dart';
import 'auth_flow_controller.dart';

/// Login surface for users who **already subscribed** to PlayNest —
/// typically from the marketing landing page — and just need to prove
/// it to the carrier before the app unlocks.
///
/// Input rules (tight, spec-driven):
///   * Phone keyboard, digits only. Letters, spaces, `+`, dashes,
///     parentheses — anything that isn't a digit — are stripped at
///     the formatter level so the user can't type them in the first
///     place, and a pasted non-digit string lands as just the digits.
///   * Maximum 11 characters — anything past 11 is silently dropped
///     by the length limiter.
///   * Only `01[68]\d{8}` is accepted: a Robi (`018`) or Cirkle
///     (`016`) Bangladeshi mobile. The app does NOT add a country
///     code (`+88`/`88`) on the user's behalf — the user types the
///     full 11 digits themselves.
///
/// Every Verify & Continue tap round-trips the upstream
/// `check_subscription.php`. There is no local cache fast-path on
/// Login — the carrier is the source of truth for "did this user
/// pay the initial charge?".
///
/// Failure surface:
///   * Local validation fail       → inline field error:
///       "Enter a valid 11-digit Robi (018) or Cirkle (016) number"
///   * Server says not subscribed  → red panel below the form with a
///       "Subscribe" deep-link CTA.
///   * Server `success:false`      → inline field error shows the
///       server's `message` text verbatim (e.g. "Invalid mobile
///       number format", "Network error"). The Retry panel also
///       appears below the form.
///
/// Visually mirrors [SubscribeScreen] (same dark-navy backdrop +
/// header + footer) so the user feels they're inside one auth surface.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _mobileCtrl = TextEditingController();

  /// Dedicated [FocusNode] for the mobile [TextField]. Owning it on
  /// the State gives us a deterministic handle for the keyboard-
  /// dismissal path: after the upstream verdict lands, we call
  /// [_mobileFocusNode.unfocus()] directly (FocusNode-level — IME-
  /// independent) and then fire-and-forget
  /// `SystemChannels.textInput.invokeMethod('TextInput.hide')`
  /// (platform-channel-level — bypasses [FocusScope] traversal
  /// entirely).
  ///
  /// Why both: on real Android devices (Samsung One UI 6, MIUI,
  /// GBoard cold states) the implicit [FocusScope.unfocus()] path
  /// defers to the same platform channel and can stall, leaving
  /// the keyboard up and starving the engine's vsync dispatcher
  /// until Android issues signal 3 / ANR. We belt-and-braces it.
  late final FocusNode _mobileFocusNode;

  /// Strict regex for the Robi (018) / Cirkle (016) carriers.
  /// Spec: `^01[68][0-9]{8}$`.
  static final RegExp _robiCirkleRegex = RegExp(r'^01[68][0-9]{8}$');

  @override
  void initState() {
    super.initState();
    _mobileFocusNode = FocusNode(debugLabel: 'login_mobile');
    // Reset the flow controller on every mount so a stale `error`
    // stage from a prior failed attempt doesn't leak into the
    // freshly-opened Login screen.
    //
    // We can't call reset() synchronously here — modifying a
    // Riverpod provider during build/initState throws the
    // "Tried to modify a provider while the widget tree was
    // building" error. Defer to a post-frame callback so the
    // widget tree finishes assembling first.
    //
    // DO NOT overwrite `_mobileCtrl.text` after reset(). The
    // `_syncFlowState` listener below keeps `_mobileCtrl.text`
    // and `state.mobile` in sync from the first user keystroke,
    // so an overwrite here would silently wipe whatever the
    // user typed before the screen was unmounted — which on a
    // re-mount (e.g. coming back from Subscribe) the user would
    // experience as their typed number vanishing the moment the
    // error panel appears, often mistaken for a freeze/ANR.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(loginFlowControllerProvider.notifier).reset();
    });
    _mobileCtrl.addListener(_syncFlowState);
  }

  @override
  void dispose() {
    _mobileCtrl.removeListener(_syncFlowState);
    _mobileCtrl.dispose();
    _mobileFocusNode.dispose();
    super.dispose();
  }

  void _syncFlowState() {
    ref
        .read(loginFlowControllerProvider.notifier)
        .setMobile(_digitsOnly(_mobileCtrl.text));
  }

  /// Keep only digits — strips `+88`, spaces, dashes, parentheses,
  /// letters — anything that isn't `0-9`. The length limiter caps
  /// at 11 in the UI; this defensive strip handles the case where
  /// the formatter pipeline runs out-of-band (initial value, paste
  /// that bypasses the formatter, etc.).
  String _digitsOnly(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) return digits.substring(0, 11);
    return digits;
  }

  /// Local format check before any API call. Returns `null` if the
  /// input matches `^01[68][0-9]{8}$`, otherwise returns the exact
  /// spec-mandated message. **Never** auto-prepends a country code.
  String? _localFormatError(String digits) {
    if (digits.isEmpty || !_robiCirkleRegex.hasMatch(digits)) {
      return 'Enter a valid 11-digit Robi (018) or Cirkle (016) number';
    }
    return null;
  }

  Future<void> _onVerify() async {
    final digits = _digitsOnly(_mobileCtrl.text);
    // Keep the TextField in sync with whatever we stripped — the
    // user sees exactly the canonical digits they sent, no country
    // code inserted, no `+88` left dangling.
    if (_mobileCtrl.text != digits) {
      _mobileCtrl.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    final formatErr = _localFormatError(digits);
    if (formatErr != null) {
      // Reflect the validation message back into the flow state so
      // the inline field error lights up. We never make an API
      // call when local validation fails.
      ref.read(loginFlowControllerProvider.notifier).setMobile(digits);
      ref.read(loginFlowControllerProvider.notifier).setError(formatErr);
      return;
    }
    ref.read(loginFlowControllerProvider.notifier).setMobile(digits);
    final ok = await ref
        .read(loginFlowControllerProvider.notifier)
        .verifyAndContinue();
    if (!mounted) return;
    if (ok) {
      // The router's auth-gate redirect (`subscriptionControllerProvider`
      // → `refreshListenable`) usually beats us to the punch and
      // unmounts the Login screen before this line runs. The
      // explicit `context.go` is a defensive fallback for the
      // edge case where the redirect hasn't fired yet (rare, but
      // possible during a cold start with cached state).
      context.go(AppRoutes.home);
    }
  }

  void _onSubscribeTap() {
    // Reset our flow so we don't carry state into the Subscribe screen.
    ref.read(loginFlowControllerProvider.notifier).reset();
    context.go('/subscribe');
  }

  @override
  Widget build(BuildContext context) {
    // ── Side-effect: dismiss the soft keyboard when the verdict lands ──
    //
    // The user-reported "Login screen freeze" (signal 3 / ANR
    // tombstone) was caused by the soft keyboard staying up after
    // the verdict landed — the red "not subscribed" panel below the
    // form was hidden behind the IME, the user saw no visible UI
    // change for 5 s, and Android SIGQUIT'd the process.
    //
    // The fix is a TWO-PRONG dismissal scheduled on a
    // [scheduleMicrotask] (not [addPostFrameCallback] — see below):
    //   1. [_mobileFocusNode.unfocus()] — FocusNode-level; tells
    //      Flutter's focus subsystem directly, IME-independent.
    //   2. `SystemChannels.textInput.invokeMethod('TextInput.hide')`
    //      — platform-channel-level; bypasses [FocusScope]
    //      traversal entirely.
    //
    // Why both: on flaky Android IMEs (Samsung One UI 6, MIUI,
    // GBoard cold states) the implicit [FocusScope.unfocus] path
    // defers to the same `TextInput.hide` platform call and can
    // stall — leaving the keyboard up and starving the engine's
    // vsync dispatcher until Android issues signal 3. Belt-and-
    // braces: invoke each dismissal path separately; whichever
    // wins, the keyboard goes down.
    //
    // Why [scheduleMicrotask] instead of
    // [WidgetsBinding.instance.addPostFrameCallback]: a post-frame
    // callback is queued behind any pending IME show-animation
    // frame on Android, which can push it past the 5 s ANR
    // threshold when the underlying IME is slow. A microtask runs
    // on the very next event-loop tick — no frame dependency.
    ref.listen<AuthFlowState>(loginFlowControllerProvider, (prev, next) {
      final wasVerifying = prev?.stage == AuthFlowStage.verifying;
      final isTerminal = next.stage == AuthFlowStage.error;
      if (!(wasVerifying && isTerminal)) return;
      scheduleMicrotask(() {
        if (!mounted) return;
        _mobileFocusNode.unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      });
    });

    final flow = ref.watch(loginFlowControllerProvider);
    // Inline field error = any error message that should appear
    // immediately under the input. Three sources:
    //   1. Local input validation (always).
    //   2. Server `success:false` `message` text.
    // We deliberately do NOT use the field for the "not subscribed"
    // outcome — that goes to the panel below with a Subscribe CTA,
    // not into the input's error text.
    // ── Panel / field-error routing ─────────────────────────────────
    //
    // The user's mobile verification has exactly two terminal
    // outcomes on the Login screen:
    //
    //   1. SUBSCRIBED — upstream returned subscriptionStatus
    //      "REGISTERED" → router redirects to Home.
    //
    //   2. NOT SUBSCRIBED — anything else. We collapse three
    //      sub-cases ("notSubscribed" verdict, "retryable"
    //      verdict from a transport blip, and any non-S1000
    //      upstream error like "Format of the address is invalid
    //      Or User Already UnRegistered") into a single visual:
    //      the red panel below the form with a Subscribe button
    //      that takes the user to /subscribe. The user's mental
    //      model is "the number I typed didn't unlock Home →
    //      here's a button to subscribe". The previous build
    //      showed a Retry button for transport errors, which the
    //      user explicitly removed — the right next step is
    //      always Subscribe, never a network retry, because if
    //      the carrier hasn't confirmed the user, the only fix
    //      on this device is to subscribe.
    //
    //   3. INVALID (local input validation) — only the inline
    //      field error lights up; no panel below the form.
    //      Verdict cannot reach here from the controller —
    //      `_localFormatError` catches bad input before the
    //      network round-trip — but the route is still defined
    //      for completeness.
    //
    // The previous build parsed `flow.errorMessage` to decide
    // whether to render the not-subscribed vs retry panel. Any
    // change to the error message string would silently change
    // which panel rendered — a coupling the audit flagged as a
    // rebuild-loop risk. We now use the typed `verdict` field
    // directly.
    final fieldError = (flow.stage == AuthFlowStage.error &&
            flow.verdict == LoginVerdict.invalid)
        ? flow.errorMessage
        : '';
    final showingNotSubscribedPanel = flow.stage == AuthFlowStage.error &&
        (flow.verdict == LoginVerdict.notSubscribed ||
            flow.verdict == LoginVerdict.retryable);

    final scaffold = Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DarkNavyBackdrop(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeader(showBack: true),
                  const SizedBox(height: AppSpacing.md),
                  const _LoginHero(),
                  const SizedBox(height: AppSpacing.lg),
                  _LoginForm(
                    mobileCtrl: _mobileCtrl,
                    focusNode: _mobileFocusNode,
                    errorMessage: fieldError,
                    isBusy: flow.isBusy,
                    onVerify: _onVerify,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (showingNotSubscribedPanel)
                    _NotSubscribedFoundPanel(
                      onSubscribeTap: _onSubscribeTap,
                      upstreamMessage: flow.verdict ==
                              LoginVerdict.notSubscribed
                          ? null
                          : flow.errorMessage,
                    )
                  else
                    _NotSubscribedCard(onSubscribeTap: _onSubscribeTap),
                  const SizedBox(height: AppSpacing.lg),
                  const PoweredByBdApps(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return scaffold;
  }
}

// ─────────────────────────────────────────────────────────────────
// Hero card — "Welcome back" + login explainer
// ─────────────────────────────────────────────────────────────────

class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top icon row.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.play.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.lock_open_rounded,
              size: 32,
              color: AppColors.play,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Welcome Back!',
            style: AppTypography.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter your mobile number to verify your existing subscription and jump back into PlayNest.',
            textAlign: TextAlign.center,
            style: AppTypography.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Carrier chip row — same chips as Subscribe so the user
          // recognises the carriers they should use.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.play.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.phone_iphone_rounded,
                    color: AppColors.play,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Verified via Carrier',
                        style: AppTypography.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Only Robi (018) or Cirkle (016)',
                        style: AppTypography.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'robi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Cirkle',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
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

// ─────────────────────────────────────────────────────────────────
// Login form (mobile input + verify CTA)
// ─────────────────────────────────────────────────────────────────

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.mobileCtrl,
    required this.focusNode,
    required this.errorMessage,
    required this.isBusy,
    required this.onVerify,
  });

  final TextEditingController mobileCtrl;
  final FocusNode focusNode;
  final String errorMessage;
  final bool isBusy;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Mobile Number',
            style: AppTypography.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileField(
            controller: mobileCtrl,
            focusNode: focusNode,
            errorMessage: errorMessage,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: isBusy ? null : onVerify,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFBBF24),
                disabledBackgroundColor:
                    const Color(0xFFFBBF24).withValues(alpha: 0.45),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primaryInk,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.login_rounded,
                          color: AppColors.primaryInk,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Verify & Continue',
                          style: AppTypography.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryInk,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileField extends StatelessWidget {
  const _MobileField({
    required this.controller,
    required this.focusNode,
    required this.errorMessage,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: AppColors.canvasTopLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: errorMessage.isEmpty
                  ? AppColors.primaryInk.withValues(alpha: 0.1)
                  : const Color(0xFFEF4444),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.phone_iphone_rounded,
                  size: 18,
                  color: AppColors.play,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  // Hard rules:
                  //   * digits only — letters / spaces / `+` /
                  //     dashes / parentheses all get stripped at the
                  //     keystroke level (and at paste time too, so a
                  //     pasted "+88018XXXXXXX" lands as the digits
                  //     inside, capped to 11).
                  //   * maximum 11 characters — past the 11th digit
                  //     the input is silently truncated.
                  //   * no country-code rewriting. The user types the
                  //     full 01XXXXXXXXX themselves.
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  style: AppTypography.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: '01XXXXXXXXX',
                    hintStyle: AppTypography.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Inline field error — exact spec wording for the local
        // validation path; verbatim server `message` text for the
        // upstream-failure path. Always rendered directly under
        // the input, never in the panel below.
        if (errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 6),
            child: Text(
              errorMessage,
              style: AppTypography.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFEF4444),
              ),
            ),
          ),
      ],
    );
  }
}

class _NotSubscribedFoundPanel extends StatelessWidget {
  const _NotSubscribedFoundPanel({
    required this.onSubscribeTap,
    this.upstreamMessage,
  });
  final VoidCallback onSubscribeTap;

  /// Optional upstream message surfaced verbatim. When the upstream
  /// returns a non-REGISTERED verdict (e.g. "Format of the address
  /// is invalid Or User Already UnRegistered"), we show that text
  /// inside the panel so the user understands WHY their number
  /// didn't unlock Home. When the upstream confirms UNREGISTERED,
  /// we show a neutral "this number is not subscribed yet" copy.
  final String? upstreamMessage;

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX (real-device ANR / infinite exception loop):
    //
    // The previous build used `Row(children: [Icon, SizedBox,
    // ElevatedButton, SizedBox, Expanded(Text)])`. On real
    // Android devices — Samsung One UI 6, MIUI, GBoard cold
    // states — Flutter's Row layout algorithm sometimes measures
    // the `ElevatedButton` (a non-flex child) BEFORE the Row
    // receives its bounded width from the `Column(crossAxis-
    // Alignment: stretch)` ancestor. That yields
    // `BoxConstraints(w=Infinity)` and the `_RenderInputPadding`
    // assertion `BoxConstraints forces an infinite width`. Once
    // that assertion fires, the Flutter error reporter itself
    // throws `!semantics.parentDataDirty` on every subsequent
    // frame, the error reporter re-throws in a tight loop, the
    // main isolate saturates, and Android issues signal 3 (the
    // 5-second "PlayNest isn't responding" ANR).
    //
    // The defensive fix: stop using `Row` + `Expanded` for a
    // text-plus-button panel. Restructure as a `Column` where
    // the button lives below the text — a vertical stack has
    // no cross-axis arithmetic to do, every child receives the
    // full bounded width from the parent `Column(stretch)`, and
    // there is no way to accidentally feed `Infinity` to an
    // inflexible child. The visual order is preserved (icon
    // header → text body → action button) and the panel is
    // fully tappable on small viewports without horizontal
    // overflow.
    final hasUpstreamMessage =
        upstreamMessage != null && upstreamMessage!.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.report_gmailerrorred_rounded,
                color: Color(0xFFEF4444),
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            hasUpstreamMessage
                ? upstreamMessage!.trim()
                : "This number is not subscribed yet.",
            style: AppTypography.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFEE2E2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap below to subscribe and unlock PlayNest.',
            style: AppTypography.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFFECACA),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: onSubscribeTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFBBF24),
                foregroundColor: AppColors.primaryInk,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Subscribe',
                style: AppTypography.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// "Not subscribed yet?" deep-link card (shown when the last attempt
// was either successful or has no error).
// ─────────────────────────────────────────────────────────────────

class _NotSubscribedCard extends StatelessWidget {
  const _NotSubscribedCard({required this.onSubscribeTap});

  final VoidCallback onSubscribeTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Not subscribed yet?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to subscribe and unlock 50+ games',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onSubscribeTap,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: AppColors.primaryInk,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 8,
              ),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Subscribe',
              style: AppTypography.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
