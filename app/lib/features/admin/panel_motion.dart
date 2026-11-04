import 'package:flutter/material.dart';

/// Brief event highlight. Does not repeat on refresh or intercept input.
class PanelSignal extends StatelessWidget {
  const PanelSignal({super.key, required this.child, required this.active});
  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(active),
    tween: Tween(
      begin: active && !MediaQuery.disableAnimationsOf(context) ? 1 : 0,
      end: 0,
    ),
    duration: panelDuration(context, 700),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, glow, child) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: glow == 0
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF00A788).withValues(alpha: .24 * glow),
                  blurRadius: 18 * glow,
                  spreadRadius: 3 * glow,
                ),
              ],
      ),
      child: child,
    ),
  );
}

Duration panelDuration(BuildContext context, [int milliseconds = 240]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// A single entrance, not a looping effect. Key by section or event, never poll.
class PanelEntrance extends StatelessWidget {
  const PanelEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0,
      end: 1,
    ),
    duration: panelDuration(context, 280),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - value)),
        child: child,
      ),
    ),
  );
}

Widget panelButtonFeedback(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => AnimatedScale(
  scale:
      states.contains(WidgetState.pressed) &&
          !states.contains(WidgetState.disabled) &&
          !MediaQuery.disableAnimationsOf(context)
      ? .96
      : 1,
  duration: panelDuration(context, 140),
  curve: Curves.easeOutCubic,
  child: child,
);

class PanelPageTransitions extends PageTransitionsBuilder {
  const PanelPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: eased.drive(
          Tween(begin: const Offset(.025, 0), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
