import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../state/app_info.dart';
import '../common/fade_in.dart';
import '../shell/brand_wordmark.dart';
import '../theme/theme.dart';
import 'onboarding_scaffold.dart';
import 'usage_notice_row.dart';

/// First screen on a fresh install: mostly empty space, the brand mark easing
/// in, one sentence and one button. Over the button, the one thing everyone
/// is told on first run: anonymous usage statistics, with their switch. The
/// slogan sits quietly at the bottom.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    return OnboardingScaffold(
      children: [
        const Spacer(flex: 5),
        const Center(child: _BrandArrival()),
        const SizedBox(height: 20),
        FadeSlideIn(
          delay: const Duration(milliseconds: 220),
          child: Text(
            l10n.shellWelcomeMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(height: 1.35),
          ),
        ),
        const Spacer(flex: 6),
        const FadeSlideIn(delay: Duration(milliseconds: 280), child: UsageNoticeRow()),
        const SizedBox(height: 20),
        FadeSlideIn(
          delay: const Duration(milliseconds: 320),
          child: FilledButton(onPressed: onStart, child: Text(l10n.shellGetStarted)),
        ),
        const SizedBox(height: 16),
        Text(
          AppInfo.slogan,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

/// The wordmark over a soft glow, easing in (fade + a slight grow) the first time the
/// page shows. Still under reduced motion.
class _BrandArrival extends StatefulWidget {
  const _BrandArrival();

  @override
  State<_BrandArrival> createState() => _BrandArrivalState();
}

class _BrandArrivalState extends State<_BrandArrival> with SingleTickerProviderStateMixin {
  late final AnimationController _arrive = AnimationController(vsync: this, duration: AppMotion.slow);
  late final Animation<double> _curve = CurvedAnimation(parent: _arrive, curve: AppMotion.enter);

  /// The hero tier: 44 tall (239 wide), the widest that stays under two thirds of a
  /// 360dp screen.
  static const _height = 44.0;
  static const _glowWidth = 340.0;
  static const _glowHeight = 150.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _arrive.value = 1;
    } else if (_arrive.isDismissed) {
      _arrive.forward();
    }
  }

  @override
  void dispose() {
    _arrive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return SizedBox(
      // Layout keeps the wordmark's size; the glow spills around it unclipped.
      width: _height * BrandWordmark.aspect,
      height: _height,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Opacity(
          opacity: _curve.value,
          child: Transform.scale(scale: 0.92 + 0.08 * _curve.value, child: child),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              // An oval behind the whole word: a round glow under a wide mark reads as
              // a smudge.
              child: OverflowBox(
                maxWidth: _glowWidth,
                maxHeight: _glowHeight,
                child: IgnorePointer(
                  child: SizedBox(
                    width: _glowWidth,
                    height: _glowHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            scheme.primary.withValues(alpha: dark ? 0.22 : 0.16),
                            scheme.primary.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const BrandWordmark(height: _height),
          ],
        ),
      ),
    );
  }
}
