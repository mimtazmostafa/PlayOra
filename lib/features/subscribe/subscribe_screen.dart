import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../auth/auth_chrome.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_flow_controller.dart';

/// Marketing + OTP screen. The first thing new users see after
/// Splash. Two states:
///
///   1. **Subscribe** — mobile input, Robi/Circle carrier selector,
///      "Send OTP" CTA, "Already Subscribed? Login" secondary CTA.
///   2. **Verify OTP** — 6-digit OTP boxes, "Verify & Subscribe" CTA,
///      "Change number" back link.
///
/// Successful verify or dev-bypass → land on Home.
class SubscribeScreen extends ConsumerStatefulWidget {
  const SubscribeScreen({super.key});

  @override
  ConsumerState<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends ConsumerState<SubscribeScreen> {
  final TextEditingController _mobileCtrl = TextEditingController();
  final List<TextEditingController> _otpCtrls = List.generate(
    6,
    (_) => TextEditingController(),
  );

  /// Strict regex matching the Robi (018) / Cirkle (016) spec:
  /// `^01[68][0-9]{8}$`. Used to pre-validate before any server
  /// call so users see the spec error message under the input
  /// field (rather than a network round-trip error).
  static final RegExp _robiCirkleRegex = RegExp(r'^01[68][0-9]{8}$');
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    // Reset the flow controller on every mount so a stale `error`
    // stage from a prior failed attempt doesn't leak into the
    // freshly-opened Subscribe screen and render its error message
    // before the user has even typed a number.
    //
    // We can't call reset() synchronously here — modifying a
    // Riverpod provider during build/initState throws the
    // "Tried to modify a provider while the widget tree was
    // building" error. Defer to a post-frame callback so the
    // widget tree finishes assembling first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(subscribeFlowControllerProvider.notifier).reset();
      if (!mounted) return;
      final flow = ref.read(subscribeFlowControllerProvider);
      if (_mobileCtrl.text != flow.mobile) {
        _mobileCtrl.text = flow.mobile;
      }
    });
    _mobileCtrl.addListener(() {
      ref
          .read(subscribeFlowControllerProvider.notifier)
          .setMobile(_digitsOnly(_mobileCtrl.text));
    });
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    super.dispose();
  }

  String _digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '').substring(
            0,
            raw.replaceAll(RegExp(r'\D'), '').length.clamp(0, 11),
          );

  Future<void> _onSendOtp() async {
    final digits = _digitsOnly(_mobileCtrl.text);
    // Spec: validate the local regex before any server call. Show
    // the exact spec message under the input — no network round
    // trip for malformed numbers.
    if (digits.isEmpty || !_robiCirkleRegex.hasMatch(digits)) {
      ref
          .read(subscribeFlowControllerProvider.notifier)
          .setError('Enter a valid 11-digit Robi (018) or Cirkle (016) number');
      return;
    }
    ref.read(subscribeFlowControllerProvider.notifier).setMobile(digits);
    final ok = await ref
        .read(subscribeFlowControllerProvider.notifier)
        .sendOtp();
    if (!mounted) return;
    if (!ok) return;
    final flow = ref.read(subscribeFlowControllerProvider);
    // Bypass mobile → skip OTP stage, mark subscribed immediately.
    if (flow.mobile == kDevBypassMobile) {
      final ok2 = await ref
          .read(subscribeFlowControllerProvider.notifier)
          .verifyOtp('000000');
      if (ok2 && mounted) {
        context.go(AppRoutes.home);
      }
      return;
    }
    // "Already subscribed" shortcut — send_otp.php returned
    // S1000/REGISTERED instead of a referenceNo, so the flow
    // controller already called markSubscribed + reset() to idle. The
    // OTP stage is never shown, so we must land the user on Home
    // ourselves; otherwise they're stuck staring at the Subscribe
    // form with no visible feedback. We can't trust `flow.mobile`
    // here because reset() wipes it — pull the digit-only value
    // straight from the field.
    final typedMobile = _digitsOnly(_mobileCtrl.text);
    if (flow.stage == AuthFlowStage.idle && typedMobile.isNotEmpty) {
      context.go(AppRoutes.home);
      return;
    }
    // Real OTP flow — auto-focus the first OTP box.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _otpFocus.first.requestFocus();
    });
  }

  Future<void> _onVerifyOtp() async {
    final otp = _otpCtrls.map((c) => c.text).join();
    final ok = await ref
        .read(subscribeFlowControllerProvider.notifier)
        .verifyOtp(otp);
    if (!mounted) return;
    if (ok) context.go(AppRoutes.home);
  }

  void _onChangeNumber() {
    ref.read(subscribeFlowControllerProvider.notifier).reset();
    for (final c in _otpCtrls) {
      c.clear();
    }
    _mobileCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Two-prong dismissal:
      //   1. [FocusScope.requestFocus] on a throwaway [FocusNode]
      //      so the focus subsystem releases the original node.
      //   2. Direct platform-channel hide (`TextInput.hide`) so the
      //      IME goes down even if the focus path stalls on flaky
      //      Android IMEs (Samsung One UI 6, MIUI, GBoard cold
      //      states).
      // Either winning is fine; both together covers the common
      // stall modes that previously left the keyboard up after
      // "Change number" and could mask subsequent user input as a
      // freeze.
      FocusScope.of(context).requestFocus(FocusNode());
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(subscribeFlowControllerProvider);
    final awaitingOtp = flow.stage == AuthFlowStage.awaitingOtp;

    return Scaffold(
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
                  AuthHeader(showBack: !awaitingOtp),
                  const SizedBox(height: AppSpacing.md),
                  if (!awaitingOtp) _MarketingHero() else _OtpHero(),
                  const SizedBox(height: AppSpacing.lg),
                  if (!awaitingOtp)
                    _SubscribeForm(
                      mobileCtrl: _mobileCtrl,
                      errorMessage:
                          flow.stage == AuthFlowStage.error
                              ? flow.errorMessage
                              : '',
                      isBusy: flow.isBusy,
                      onSendOtp: _onSendOtp,
                      onLoginTap: () => context.push('/login'),
                    )
                  else
                    _OtpForm(
                      otpCtrls: _otpCtrls,
                      otpFocus: _otpFocus,
                      isBusy: flow.isBusy,
                      errorMessage:
                          flow.stage == AuthFlowStage.error
                              ? flow.errorMessage
                              : '',
                      onVerify: _onVerifyOtp,
                      onChangeNumber: _onChangeNumber,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  const PoweredByBdApps(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Marketing hero — top of the screen before the form
// ─────────────────────────────────────────────────────────────────

class _MarketingHero extends StatelessWidget {
  const _MarketingHero();

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
          // Banner row: 50+ games badge + emoji icons.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.play.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '50+',
                  style: TextStyle(
                    color: AppColors.play,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mini Games',
                      style: AppTypography.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Just for You!',
                      style: AppTypography.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Crown + Get Full Access title.
          Row(
            children: [
              const Text('👑', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 6),
              Text(
                'Get Full Access',
                style: AppTypography.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Subscribe for just ৳5.56/day(including VAT+SD+SC) and unlock all 50+ mini games!',
              style: AppTypography.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _BenefitTiles(),
          const SizedBox(height: AppSpacing.md),
          // Payment info row.
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
                        'Payment via Mobile Balance',
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
                _CarrierLogo(label: 'robi', color: const Color(0xFFE11D48)),
                const SizedBox(width: 6),
                _CarrierLogo(label: 'Cirkle', color: const Color(0xFFDC2626)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Carrier selector.
          const _CarrierSelector(),
        ],
      ),
    );
  }
}

class _BenefitTiles extends StatelessWidget {
  const _BenefitTiles();

  @override
  Widget build(BuildContext context) {
    final tiles = <_BenefitData>[
      const _BenefitData(
        icon: Icons.sports_esports_rounded,
        label: 'Play 50+',
        sub: 'Mini Games',
        color: AppColors.play,
      ),
      const _BenefitData(
        icon: Icons.flash_on_rounded,
        label: 'No Ads',
        sub: 'Pure play',
        color: Color(0xFFFBBF24),
      ),
      const _BenefitData(
        icon: Icons.workspace_premium_rounded,
        label: 'Daily',
        sub: 'Challenges',
        color: Color(0xFF9333EA),
      ),
      const _BenefitData(
        icon: Icons.star_rounded,
        label: 'New Games',
        sub: 'Every week',
        color: Color(0xFFF97316),
      ),
    ];

    return Row(
      children: [
        for (final t in tiles) ...[
          Expanded(child: _BenefitTile(data: t)),
          if (t != tiles.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _BenefitData {
  const _BenefitData({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.data});
  final _BenefitData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            data.label,
            style: AppTypography.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
          Text(
            data.sub,
            style: AppTypography.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarrierLogo extends StatelessWidget {
  const _CarrierLogo({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CarrierSelector extends StatelessWidget {
  const _CarrierSelector();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Choose Your Number',
            style: AppTypography.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF334155),
            ),
          ),
        ),
        Row(
          children: const [
            Expanded(
              child: _CarrierChip(
                label: 'Robi',
                prefix: '018',
                color: Color(0xFFE11D48),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _CarrierChip(
                label: 'Cirkle',
                prefix: '016',
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CarrierChip extends StatelessWidget {
  const _CarrierChip({
    required this.label,
    required this.prefix,
    required this.color,
  });
  final String label;
  final String prefix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // The carrier chips are decorative; the actual validation
          // happens when the user enters a number. Tapping them is a
          // soft hint to enter the matching prefix.
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  label.substring(0, 1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTypography.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      prefix,
                      style: AppTypography.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Subscribe form (mobile input + send OTP)
// ─────────────────────────────────────────────────────────────────

class _SubscribeForm extends StatelessWidget {
  const _SubscribeForm({
    required this.mobileCtrl,
    required this.errorMessage,
    required this.isBusy,
    required this.onSendOtp,
    required this.onLoginTap,
  });

  final TextEditingController mobileCtrl;
  final String errorMessage;
  final bool isBusy;
  final VoidCallback onSendOtp;
  final VoidCallback onLoginTap;

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
          _MobileField(controller: mobileCtrl, errorMessage: errorMessage),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: isBusy ? null : onSendOtp,
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
                          Icons.send_rounded,
                          color: AppColors.primaryInk,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Send OTP',
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
          const SizedBox(height: AppSpacing.md),
          // "Already subscribed" → Login — same button styling as
          // Send OTP, just with a white fill + dark ink so it reads
          // as the secondary CTA rather than disappearing into the
          // form.
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: onLoginTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0,
                side: BorderSide(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.login_rounded,
                    color: const Color(0xFF0F172A),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Already Subscribed? Login',
                    style: AppTypography.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
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
  const _MobileField({required this.controller, required this.errorMessage});
  final TextEditingController controller;
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
                  ? const Color(0xFF0F172A).withValues(alpha: 0.1)
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
                  keyboardType: TextInputType.number,
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

// ─────────────────────────────────────────────────────────────────
// OTP form
// ─────────────────────────────────────────────────────────────────

class _OtpHero extends StatelessWidget {
  const _OtpHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.play.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.sms_rounded,
              size: 32,
              color: AppColors.play,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Enter the 6-digit OTP',
            style: AppTypography.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We sent a code to your number. Enter it below to complete your subscription.',
            textAlign: TextAlign.center,
            style: AppTypography.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpForm extends StatelessWidget {
  const _OtpForm({
    required this.otpCtrls,
    required this.otpFocus,
    required this.isBusy,
    required this.errorMessage,
    required this.onVerify,
    required this.onChangeNumber,
  });

  final List<TextEditingController> otpCtrls;
  final List<FocusNode> otpFocus;
  final bool isBusy;
  final String errorMessage;
  final VoidCallback onVerify;
  final VoidCallback onChangeNumber;

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
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 6; i++)
                _OtpBox(
                  controller: otpCtrls[i],
                  focusNode: otpFocus[i],
                  onChanged: (v) {
                    if (v.isNotEmpty && i < 5) {
                      otpFocus[i + 1].requestFocus();
                    }
                    if (v.isEmpty && i > 0) {
                      otpFocus[i - 1].requestFocus();
                    }
                  },
                ),
            ],
          ),
          if (errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                errorMessage,
                style: AppTypography.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFEF4444),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
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
                  : Text(
                      'Verify & Subscribe',
                      style: AppTypography.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryInk,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onChangeNumber,
            child: Text(
              'Change number',
              style: AppTypography.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: AppTypography.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0F172A),
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: AppColors.canvasTopLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: const Color(0xFF0F172A).withValues(alpha: 0.1),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: const Color(0xFF0F172A).withValues(alpha: 0.1),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.play,
              width: 2,
            ),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
