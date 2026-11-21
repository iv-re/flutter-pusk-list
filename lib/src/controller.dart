part of 'sliver_list.dart';

/// Controls a `PuskSliverList`: jumps and animations to items, visibility.
///
/// ```dart
/// final controller = PuskListController();
///
/// controller.jumpToIndex(500, alignment: 0.5);
/// await controller.animateToKey(
///   messageId,
///   duration: const Duration(milliseconds: 400),
///   curve: Curves.easeInOut,
/// );
///
/// ValueListenableBuilder(
///   valueListenable: controller.visibleRange,
///   builder: (context, range, _) => Text('$range'),
/// );
/// ```
class PuskListController {
  _RenderPuskSliverList? _render;
  final ValueNotifier<PuskVisibleRange?> _visibleRange = ValueNotifier(null);

  /// Whether the controller is attached to a `PuskSliverList`.
  bool get isAttached => _render != null;

  void _attach(_RenderPuskSliverList render) {
    assert(
      _render == null || identical(_render, render),
      'PuskListController is already attached to another PuskSliverList.',
    );
    _render = render;
  }

  void _detach(_RenderPuskSliverList render) {
    if (!identical(_render, render)) return;
    _render = null;
    _publishVisibleRange();
  }

  bool _publishScheduled = false;
  bool _disposed = false;

  /// Updates [visibleRange] from the attached list after the current frame.
  ///
  /// Never synchronous: attach, detach and layout happen while widgets are
  /// built or laid out, and listeners may rebuild widgets.
  void _publishVisibleRange() {
    if (_publishScheduled) return;
    _publishScheduled = true;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      _publishScheduled = false;
      if (!_disposed) _visibleRange.value = _render?._visibleRange;
    });
    if (scheduler.schedulerPhase == SchedulerPhase.idle) {
      scheduler.scheduleFrame();
    }
  }

  _RenderPuskSliverList get _attached {
    assert(isAttached, 'PuskListController is not attached to a list.');
    return _render!;
  }

  // ---------------------------------------------------------------------------
  // Navigation

  /// Jumps so that the item at [index] is at [alignment] (`0.0` leading edge,
  /// `0.5` center, `1.0` trailing edge).
  void jumpToIndex(int index, {double alignment = 0.0}) {
    _attached.jumpToIndex(index, alignment);
  }

  /// Jumps to the item with [key]. Does nothing if there is no such item.
  void jumpToKey(Object key, {double alignment = 0.0}) {
    final index = indexOfKey(key);
    if (index != null) jumpToIndex(index, alignment: alignment);
  }

  /// Animates to the item at [index].
  ///
  /// Completes when the animation ends or gets interrupted (e.g. by the
  /// user touching the list).
  Future<void> animateToIndex(
    int index, {
    required Duration duration,
    required Curve curve,
    double alignment = 0.0,
  }) {
    final render = _attached;
    return render.animateToIndex(
      () => index < render.itemCount ? index : null,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }

  /// Animates to the item with [key], following it if items get inserted or
  /// removed during the animation. Stops if the item is removed.
  Future<void> animateToKey(
    Object key, {
    required Duration duration,
    required Curve curve,
    double alignment = 0.0,
  }) {
    final render = _attached;
    return render.animateToIndex(
      () => render.indexOfKey(key),
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }

  // ---------------------------------------------------------------------------
  // Visibility

  /// Indices of the first and last visible items, updated after each frame
  /// in which they changed.
  ValueListenable<PuskVisibleRange?> get visibleRange => _visibleRange;

  /// Snapshot of the visible items and where they are in the viewport.
  List<PuskItemPosition> get visibleItems => _render?.visibleItems ?? const [];

  // ---------------------------------------------------------------------------
  // Items

  int get itemCount => _render?.itemCount ?? 0;

  int? indexOfKey(Object key) => _render?.indexOfKey(key);

  /// Distance from the start of the list to the item at [index], from
  /// measured and estimated extents.
  double? offsetOf(int index) => _render?.offsetOf(index);

  /// Extent of the item at [index]: measured if it was laid out, estimated
  /// otherwise.
  double? extentOf(int index) => _render?.extentOf(index);

  /// Whether the item at [index] has been laid out at least once.
  bool isMeasured(int index) => _render?.isMeasured(index) ?? false;

  /// Sum of all item extents (measured or estimated).
  double get estimatedScrollExtent => _render?.totalExtent ?? 0;

  // ---------------------------------------------------------------------------
  // Holding an item
  //
  // For dragging items with your own gestures: the caller moves the held
  // item and changes the data. `reorder` is built on these.

  /// Holds the visible item with [key]: it stays where it is on screen,
  /// over the other items, when the list scrolls or changes, until
  /// [releaseHeldItem]. Returns `false` if the item isn't laid out or an
  /// item is already held.
  ///
  /// While it is held, items that change their place (e.g. the held item
  /// moved to a new place in the data) slide there over
  /// [moveDuration] with [moveCurve], and the items it passes don't shift
  /// the screen. Items that change their extent (e.g. gaining a separator)
  /// animate it the same way, until the held item lands.
  bool holdItem(
    Object key, {
    Duration moveDuration = const Duration(milliseconds: 250),
    Curve moveCurve = Curves.ease,
  }) => _attached.holdItem(
    key,
    moveDuration: moveDuration,
    moveCurve: moveCurve,
  );

  /// The held item and where it is, as of the last layout.
  PuskHeldItem? get heldItem => _render?.heldItem;

  /// Moves the held item by a pointer's [delta] (global coordinates) along
  /// the list's axis, and across it too if [crossAxis] is on. The item is
  /// clipped by the viewport.
  void moveHeldItem(Offset delta, {bool crossAxis = false}) =>
      _render?.moveHeldItem(delta, crossAxis: crossAxis);

  /// Lets the held item go: it moves from where it is to its place in the
  /// list over [duration] with [curve].
  void releaseHeldItem({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.ease,
  }) => _render?.releaseHeldItem(duration: duration, curve: curve);

  void dispose() {
    _disposed = true;
    _visibleRange.dispose();
  }
}
