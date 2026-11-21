import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pusk_list/src/keys_diff.dart';
import 'package:pusk_list/src/sliver_list.dart';

/// Wraps an item of a reorderable list in its drag decoration.
///
/// [animation] runs from `0.0` to `1.0` when the item is picked up and back
/// when it is dropped; items that aren't dragged get a dismissed animation.
/// Like a transition builder, it must return the same widget structure for
/// any animation, or items lose their state when picked up.
typedef PuskDragDecorator =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Widget child,
    );

/// Lets the user drag items of the list to new places.
///
/// Drags start from a [PuskDragStartListener] inside an item. The dragged
/// item stays in the list (it keeps its state) and follows the pointer,
/// painted over the others and clipped by the viewport; the other items
/// make room for it, and the list scrolls when it gets near an edge.
@immutable
class PuskReorder {
  const PuskReorder({
    required this.onReorder,
    this.onReorderStart,
    this.onReorderUpdate,
    this.onReorderEnd,
    this.canReorder,
    this.freeDrag = false,
    this.decorator,
    this.autoScroll = const PuskAutoScroll(),
    this.liftDuration = const Duration(milliseconds: 250),
    this.liftCurve = Curves.ease,
    this.dropDuration = const Duration(milliseconds: 250),
    this.dropCurve = Curves.ease,
    this.moveDuration = const Duration(milliseconds: 250),
    this.moveCurve = Curves.ease,
  });

  /// Called on drop when the item at `from` got a new place: it should be
  /// at index `to` (counted after the move) on the next build, e.g.
  /// `items.insert(to, items.removeAt(from))`.
  ///
  /// The order must change synchronously; if it doesn't, the item slides
  /// back to where it was.
  final void Function(int from, int to) onReorder;

  /// Called when the item at `index` gets picked up.
  final void Function(int index)? onReorderStart;

  /// Called when the dragged item, which was at `from`, takes the place `to`
  /// among the other items.
  final void Function(int from, int to)? onReorderUpdate;

  /// Called when the dropped item, now at `index`, has landed.
  final void Function(int index)? onReorderEnd;

  /// Whether the item at `from` may take the place `to`. A place that is
  /// not allowed is skipped: the item takes the nearest allowed place
  /// between it and its current one.
  final bool Function(int from, int to)? canReorder;

  /// Whether the dragged item follows the pointer across the list's axis
  /// too. Its place depends on the main axis only either way.
  final bool freeDrag;

  /// Wraps every item; see [PuskDragDecorator].
  final PuskDragDecorator? decorator;

  final PuskAutoScroll autoScroll;

  /// Duration of the decorator's animation when an item is picked up.
  final Duration liftDuration;
  final Curve liftCurve;

  /// Duration of the dropped item's move to its place and of the
  /// decorator's animation back.
  final Duration dropDuration;
  final Curve dropCurve;

  /// Duration of the other items making room for the dragged one.
  final Duration moveDuration;
  final Curve moveCurve;
}

/// How the list scrolls while an item is dragged near its edges.
///
/// The list scrolls once the dragged item gets within [edgeExtent] of an
/// edge of its visible part (without `obscuredInsets` and pinned headers),
/// faster the deeper it goes: at [maxSpeed] when it is [rampExtent] deep,
/// [curve] shaping the speed in between.
@immutable
class PuskAutoScroll {
  const PuskAutoScroll({
    this.edgeExtent = 40,
    this.rampExtent = 80,
    this.maxSpeed = 2000,
    this.curve = Curves.easeIn,
  }) : assert(rampExtent > 0);

  /// Doesn't scroll.
  static const none = PuskAutoScroll(maxSpeed: 0);

  final double edgeExtent;
  final double rampExtent;

  /// Pixels per second.
  final double maxSpeed;
  final Curve curve;

  /// Scroll speed (pixels per second) for an item [depth] pixels into the
  /// scrolling zone.
  double speedAt(double depth) {
    if (depth <= 0 || maxSpeed <= 0) return 0;
    final t = depth / rampExtent;
    return maxSpeed * curve.transform(t < 1 ? t : 1);
  }
}

/// An item of a list with a [PuskReorder] and its place among the items as
/// shown: while an item is dragged, the others are shown in a new order,
/// but `itemBuilder` gets their indices in the unchanged one.
///
/// For what depends on the neighbours, e.g. the corners of the first and
/// last rows of a group:
///
/// ```dart
/// final item = PuskReorderItem.of(context);
/// final isLast = item.index == item.count - 1 ||
///     rows[item.sourceIndexAt(item.index + 1)].isHeader;
/// ```
///
/// Widgets that call [of] rebuild when the order changes.
@immutable
class PuskReorderItem {
  const PuskReorderItem._({
    required this.index,
    required this.count,
    required this.draggedIndex,
    required this._draggedFrom,
  });

  /// Index of the item among the items as shown.
  final int index;

  final int count;

  /// Index among the items as shown of the dragged item, if there is one.
  final int? draggedIndex;

  /// Index of the dragged item in the unchanged list.
  final int? _draggedFrom;

  bool get isDragged => draggedIndex == index;

  /// Index in the unchanged list (as `itemBuilder` gets it) of the item
  /// shown at [index].
  int sourceIndexAt(int index) {
    final to = draggedIndex;
    final from = _draggedFrom;
    if (to == null || from == null) return index;
    return _sourceIndexAt(index, from, to);
  }

  /// The item [context] is in. Only inside items of a list with a
  /// [PuskReorder].
  static PuskReorderItem of(BuildContext context) {
    final item = maybeOf(context);
    assert(item != null, 'No PuskReorderItem: not in a reorderable list.');
    return item!;
  }

  static PuskReorderItem? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemScope>()?.item;

  @override
  bool operator ==(Object other) =>
      other is PuskReorderItem &&
      other.index == index &&
      other.count == count &&
      other.draggedIndex == draggedIndex &&
      other._draggedFrom == _draggedFrom;

  @override
  int get hashCode => Object.hash(index, count, draggedIndex, _draggedFrom);
}

/// Starts dragging the item it is in when the pointer goes down on [child]
/// (a drag handle) or, with a [delay], is held there (a long press).
///
/// Works inside items of a list with a [PuskReorder].
class PuskDragStartListener extends StatelessWidget {
  const PuskDragStartListener({
    required this.child,
    this.delay = Duration.zero,
    this.enabled = true,
    super.key,
  });

  /// Starts dragging after a long press ([kLongPressTimeout]).
  const PuskDragStartListener.delayed({
    required this.child,
    this.delay = kLongPressTimeout,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// How long the pointer has to be held before the drag starts.
  final Duration delay;

  final bool enabled;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: enabled
        ? (event) => _ItemScope.maybeOf(context)?.start(context, event, delay)
        : null,
    child: child,
  );
}

/// Builds the list shown by a [PuskReorderLayer].
typedef PuskReorderListBuilder =
    Widget Function(
      BuildContext context,
      PuskShownItems items,
      PuskListController controller,
    );

/// Keeps the order of the items while one is dragged and handles the
/// drag; the list comes from [builder]. Not exported: lists build it for
/// their `reorder`.
class PuskReorderLayer extends StatefulWidget {
  const PuskReorderLayer({
    required this.reorder,
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    required this.controller,
    required this.builder,
    super.key,
  });

  final PuskReorder reorder;
  final int itemCount;
  final PuskItemKeyBuilder itemKey;
  final IndexedWidgetBuilder itemBuilder;

  /// The list's controller; the layer makes one if there is none.
  final PuskListController? controller;
  final PuskReorderListBuilder builder;

  @override
  State<PuskReorderLayer> createState() => _PuskReorderLayerState();
}

/// The items of a [PuskReorderLayer] as shown: with the dragged one at its
/// new place.
class PuskShownItems {
  PuskShownItems._(this._state);

  final _PuskReorderLayerState _state;

  int get count => _state.widget.itemCount;

  /// Index in the layer's items of the item shown at [index].
  int sourceIndex(int index) => _state._session?.sourceIndexOf(index) ?? index;

  Object key(int index) => _state.widget.itemKey(sourceIndex(index));

  /// Whether the item shown at [index] is being dragged.
  bool isDragged(int index) => _state._session?.to == index;

  Widget build(BuildContext context, int index) =>
      _state._buildItem(context, sourceIndex(index), index);
}

class _ItemScope extends InheritedWidget {
  const _ItemScope({
    required this.state,
    required this.itemKey,
    required this.item,
    required super.child,
  });

  final _PuskReorderLayerState state;
  final Object itemKey;
  final PuskReorderItem item;

  static _ItemScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ItemScope>();

  void start(BuildContext context, PointerDownEvent event, Duration delay) =>
      state._addPointer(context, event, itemKey, delay);

  @override
  bool updateShouldNotify(_ItemScope oldWidget) => item != oldWidget.item;
}

/// A drag in progress.
class _Session {
  _Session(this.key, this.from, this.position) : to = from;

  final Object key;

  /// Index of the dragged item in the layer's items.
  int from;

  /// Index of the dragged item among the shown ones.
  int to;

  final ScrollPosition? position;

  int sourceIndexOf(int index) => _sourceIndexAt(index, from, to);
}

class _Drag implements Drag {
  _Drag(this._state);

  final _PuskReorderLayerState _state;

  @override
  void update(DragUpdateDetails details) => _state._update(details.delta);

  @override
  void end(DragEndDetails details) => _state._end();

  @override
  void cancel() => _state._end(cancelled: true);
}

class _PuskReorderLayerState extends State<PuskReorderLayer>
    with TickerProviderStateMixin {
  late final PuskShownItems _items = PuskShownItems._(this);
  late final AnimationController _lift = AnimationController(vsync: this);
  late final CurvedAnimation _liftAnimation = CurvedAnimation(
    parent: _lift,
    curve: _reorder.liftCurve,
    reverseCurve: _reorder.dropCurve,
  );
  late final Ticker _autoScrollTicker = createTicker(_onAutoScrollTick);
  Duration _lastAutoScrollTick = Duration.zero;

  PuskListController? _ownController;

  _Session? _session;

  /// The item that is dragged or landing: it gets the lift animation.
  Object? _liftedKey;

  MultiDragGestureRecognizer? _recognizer;

  PuskReorder get _reorder => widget.reorder;

  PuskListController get _controller =>
      widget.controller ?? (_ownController ??= PuskListController());

  @override
  void didUpdateWidget(PuskReorderLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _liftAnimation
      ..curve = _reorder.liftCurve
      ..reverseCurve = _reorder.dropCurve;
  }

  @override
  void dispose() {
    _recognizer?.dispose();
    _autoScrollTicker.dispose();
    _liftAnimation.dispose();
    _lift.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  Widget _buildItem(BuildContext context, int index, int shownIndex) {
    final key = widget.itemKey(index);
    var child = widget.itemBuilder(context, index);
    final decorator = _reorder.decorator;
    if (decorator != null) {
      child = decorator(
        context,
        key == _liftedKey ? _liftAnimation : kAlwaysDismissedAnimation,
        child,
      );
    }
    final session = _session;
    return _ItemScope(
      state: this,
      itemKey: key,
      item: PuskReorderItem._(
        index: shownIndex,
        count: widget.itemCount,
        draggedIndex: session?.to,
        draggedFrom: session?.from,
      ),
      child: child,
    );
  }

  int _indexOfKey(Object key) {
    for (var i = 0; i < widget.itemCount; i++) {
      if (widget.itemKey(i) == key) return i;
    }
    return -1;
  }

  /// Finds the dragged item among the layer's items; ends the drag when it
  /// is gone.
  void _syncSession() {
    final session = _session;
    if (session == null) return;
    var from = session.from;
    if (from >= widget.itemCount || widget.itemKey(from) != session.key) {
      from = _indexOfKey(session.key);
    }
    if (from < 0) {
      _session = null;
      _autoScrollTicker.stop();
      _controller.releaseHeldItem(duration: Duration.zero);
      _liftedKey = null;
      _lift.value = 0;
      return;
    }
    session
      ..from = from
      ..to = session.to.clamp(0, widget.itemCount - 1);
  }

  void _addPointer(
    BuildContext context,
    PointerDownEvent event,
    Object key,
    Duration delay,
  ) {
    if (_session != null) return;
    final position = Scrollable.maybeOf(context)?.position;
    _recognizer?.dispose();
    final recognizer = delay > Duration.zero
        ? DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this)
        : ImmediateMultiDragGestureRecognizer(debugOwner: this);
    recognizer
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
      ..onStart = ((_) => _start(key, position));
    _recognizer = recognizer;
    recognizer.addPointer(event);
  }

  Drag? _start(Object key, ScrollPosition? position) {
    if (_session != null || !mounted) return null;
    final reorder = _reorder;
    final index = _indexOfKey(key);
    if (index < 0 ||
        !_controller.holdItem(
          key,
          moveDuration: reorder.moveDuration,
          moveCurve: reorder.moveCurve,
        )) {
      return null;
    }
    _session = _Session(key, index, position);
    setState(() => _liftedKey = key);
    _lift
      ..duration = reorder.liftDuration
      ..forward();
    reorder.onReorderStart?.call(index);
    return _Drag(this);
  }

  void _update(Offset delta) {
    if (_session == null) return;
    _controller.moveHeldItem(delta, crossAxis: _reorder.freeDrag);
    _updateTarget();
    if (_autoScrollSpeed != 0 && !_autoScrollTicker.isActive) {
      _lastAutoScrollTick = Duration.zero;
      _autoScrollTicker.start();
    }
  }

  /// Where the held item belongs: after every item whose middle its leading
  /// edge passed, counting in the list without it. Only places next to the
  /// visible part of the list count, so that the item stays laid out.
  int? _proposedTarget() {
    final controller = _controller;
    final held = controller.heldItem;
    if (held == null) return null;
    final extent = held.extent;
    final low = held.visibleStart - extent;
    final position = held.leadingEdge.clamp(
      low,
      held.visibleEnd < low ? low : held.visibleEnd,
    );
    final count = controller.itemCount;
    var moves = 0;
    for (var i = held.index + 1; i < count; i++) {
      final offset = controller.offsetOf(i);
      final itemExtent = controller.extentOf(i);
      if (offset == null || itemExtent == null) break;
      if (position <= offset - extent + itemExtent / 2) break;
      moves++;
    }
    if (moves == 0) {
      for (var i = held.index - 1; i >= 0; i--) {
        final offset = controller.offsetOf(i);
        final itemExtent = controller.extentOf(i);
        if (offset == null || itemExtent == null) break;
        if (position >= offset + itemExtent / 2) break;
        moves--;
      }
    }
    return held.index + moves;
  }

  void _updateTarget() {
    final session = _session;
    final proposed = _proposedTarget();
    if (session == null || proposed == null) return;
    final reorder = _reorder;
    var target = proposed.clamp(0, widget.itemCount - 1);
    if (target == session.to) return;
    final canReorder = reorder.canReorder;
    if (canReorder != null) {
      final step = target > session.to ? -1 : 1;
      while (target != session.to && !canReorder(session.from, target)) {
        target += step;
      }
      if (target == session.to) return;
    }
    setState(() => session.to = target);
    reorder.onReorderUpdate?.call(session.from, target);
  }

  double get _autoScrollSpeed {
    final held = _controller.heldItem;
    if (held == null) return 0;
    final autoScroll = _reorder.autoScroll;
    final leading = held.visibleStart - held.leadingEdge;
    final trailing = held.leadingEdge + held.extent - held.visibleEnd;
    return autoScroll.speedAt(trailing + autoScroll.edgeExtent) -
        autoScroll.speedAt(leading + autoScroll.edgeExtent);
  }

  void _onAutoScrollTick(Duration elapsed) {
    final delta = elapsed - _lastAutoScrollTick;
    _lastAutoScrollTick = elapsed;
    final position = _session?.position;
    final speed = _autoScrollSpeed;
    if (position == null || speed == 0 || !position.hasContentDimensions) {
      _autoScrollTicker.stop();
      return;
    }
    final pixels = (position.pixels + speed * delta.inMicroseconds / 1e6).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (pixels != position.pixels) position.jumpTo(pixels);
    // As of the last layout: one frame behind the scroll.
    _updateTarget();
  }

  void _end({bool cancelled = false}) {
    final session = _session;
    if (session == null) return;
    _session = null;
    _autoScrollTicker.stop();
    final reorder = _reorder;
    _controller.releaseHeldItem(
      duration: reorder.dropDuration,
      curve: reorder.dropCurve,
    );
    // Shows the layer's order: the new one, or the old one if the move was
    // cancelled or not applied.
    setState(() {});
    final key = session.key;
    _lift.reverseDuration = reorder.dropDuration;
    _lift.reverse().whenCompleteOrCancel(() {
      if (!mounted || _liftedKey != key || _session != null) return;
      setState(() => _liftedKey = null);
      final index = _indexOfKey(key);
      if (index >= 0) _reorder.onReorderEnd?.call(index);
    });
    if (!cancelled && session.from != session.to) {
      reorder.onReorder(session.from, session.to);
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncSession();
    return widget.builder(context, _items, _controller);
  }
}

/// Index in the unchanged list of the item shown at [index], the item at
/// [from] being shown at [to].
int _sourceIndexAt(int index, int from, int to) {
  if (index == to) return from;
  if (from < to && index >= from && index < to) return index + 1;
  if (to < from && index > to && index <= from) return index - 1;
  return index;
}
