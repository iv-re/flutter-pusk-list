part of 'sliver_list.dart';

/// Insert or remove animation of one item, driven by the list's ticker.
///
/// Also serves as the [Animation] given to [PuskItemTransition.builder].
class _ItemAnimation extends Animation<double>
    with
        AnimationEagerListenerMixin,
        AnimationLocalListenersMixin,
        AnimationLocalStatusListenersMixin {
  _ItemAnimation({
    required this.key,
    required this.index,
    required this.fullExtent,
    required this._value,
  });

  final Object key;

  /// Display index of the item, kept up to date when keys change.
  int index;

  /// Extent of the item at full size: measured, or estimated until then.
  double fullExtent;

  final LayerHandle<OpacityLayer> opacityLayer = LayerHandle<OpacityLayer>();

  double _value;
  double _from = 0;
  double _target = 1;
  Curve _curve = Curves.linear;
  int _durationMicros = 0;

  /// Progress of the current run, from 0 to 1.
  double _progress = 1;

  @override
  double get value => _value;

  bool get isRunning => _progress < 1;

  /// Whether the item was removed and is animating out (or has finished
  /// doing so and is waiting to be dropped).
  bool get isRemoving => _target == 0;

  @override
  AnimationStatus get status => switch ((isRunning, isRemoving)) {
    (true, false) => AnimationStatus.forward,
    (true, true) => AnimationStatus.reverse,
    (false, false) => AnimationStatus.completed,
    (false, true) => AnimationStatus.dismissed,
  };

  /// Runs from the current value to [target]. The duration is shortened in
  /// proportion when the animation starts midway (e.g. an item re-inserted
  /// while it was being removed).
  void run({
    required double target,
    required Duration duration,
    required Curve curve,
  }) {
    _from = _value;
    _target = target;
    _curve = curve;
    _durationMicros = (duration.inMicroseconds * (target - _value).abs())
        .round();
    if (_durationMicros <= 0) {
      _progress = 1;
      _value = target;
      notifyListeners();
    } else {
      _progress = 0;
    }
    notifyStatusListeners(status);
  }

  /// Advances by [elapsed]. Returns whether the animation is still running.
  bool tick(Duration elapsed) {
    if (!isRunning) return false;
    _progress = math.min(
      1,
      _progress + elapsed.inMicroseconds / _durationMicros,
    );
    _value = _from + (_target - _from) * _curve.transform(_progress);
    notifyListeners();
    if (isRunning) return true;
    notifyStatusListeners(status);
    return false;
  }

  /// Jumps to the end of the current run.
  void finish() {
    if (!isRunning) return;
    _progress = 1;
    _value = _target;
    notifyListeners();
    notifyStatusListeners(status);
  }

  @override
  void dispose() {
    clearListeners();
    clearStatusListeners();
    opacityLayer.layer = null;
    super.dispose();
  }
}

/// Extent change of an item that stays, animated because it came with an
/// insertion or removal next to it (e.g. a chat message gaining its author's
/// name when the message above it is deleted).
///
/// The item is laid out at its new size right away; only the room it takes
/// animates. It is pinned to the edge away from the change ([pinLeading]),
/// so that the part that appeared or went away is the one sliding under its
/// neighbour.
class _ItemResize {
  _ItemResize({
    required this.from,
    required this.to,
    required this.pinLeading,
    required this.duration,
    required this.curve,
  });

  double from;
  double to;
  final bool pinLeading;
  Duration duration;
  Curve curve;
  double _progress = 0;

  double get extent => from + (to - from) * curve.transform(_progress);

  bool get isRunning => _progress < 1;

  /// Animates from the current extent to [target] over a full duration.
  void retarget(double target) {
    from = extent;
    to = target;
    _progress = 0;
  }

  void tick(Duration elapsed) {
    final micros = duration.inMicroseconds;
    _progress = micros <= 0
        ? 1
        : math.min(1, _progress + elapsed.inMicroseconds / micros);
  }
}
