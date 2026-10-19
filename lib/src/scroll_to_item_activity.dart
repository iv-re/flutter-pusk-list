part of 'sliver_list.dart';

/// Like [DrivenScrollActivity], but the destination is re-evaluated every
/// frame, so the animation follows the target item while extents get
/// measured (or items get inserted) along the way.
///
/// Every frame covers the share of the *remaining* distance that the curve
/// gives to it. A target that moves (e.g. items on the way turn out smaller
/// than estimated) is absorbed over the rest of the animation instead of
/// showing up as a jump or a reversal, and the end lands on the target.
class _ScrollToItemActivity extends ScrollActivity {
  _ScrollToItemActivity(
    ScrollPosition position, {
    required this._target,
    required Duration duration,
    required this._curve,
    required TickerProvider vsync,
  }) : _position = position,
       _lastPixels = position.pixels,
       super(position as ScrollActivityDelegate) {
    _controller = AnimationController(vsync: vsync, duration: duration)
      ..addListener(_tick)
      ..forward().whenComplete(_end);
  }

  final ScrollPosition _position;
  final double? Function() _target;
  final Curve _curve;
  late final AnimationController _controller;
  final Completer<void> _completer = Completer<void>();
  double _lastPixels;
  double _lastValue = 0;
  double _velocity = 0;

  /// Completes when the activity stops, whether it finished or got
  /// interrupted.
  Future<void> get done => _completer.future;

  /// Whether the animation ran to the end.
  bool completed = false;

  void _tick() {
    final to = _target();
    if (to == null) {
      delegate.goIdle();
      return;
    }
    final value = _curve.transform(_controller.value);
    final remaining = 1 - _lastValue;
    // The current position, including anchoring corrections since the last
    // frame.
    final current = _position.pixels;
    final pixels = _controller.isCompleted || remaining.abs() < 1e-9
        ? to
        : current + (to - current) * (value - _lastValue) / remaining;
    _lastValue = value;
    _velocity = pixels - _lastPixels;
    _lastPixels = pixels;
    if (delegate.setPixels(pixels).abs() >= precisionErrorTolerance) {
      delegate.goIdle();
    }
  }

  void _end() {
    if (_completer.isCompleted) return;
    completed = true;
    // The target already moved with us; don't carry momentum past it.
    delegate.goBallistic(0);
  }

  @override
  void dispatchOverscrollNotification(
    ScrollMetrics metrics,
    BuildContext context,
    double overscroll,
  ) {
    OverscrollNotification(
      metrics: metrics,
      context: context,
      overscroll: overscroll,
      velocity: _velocity,
    ).dispatch(context);
  }

  @override
  bool get shouldIgnorePointer => true;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => 0;

  @override
  void dispose() {
    _completer.complete();
    _controller.dispose();
    super.dispose();
  }
}
