import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pusk_list/src/item_extents.dart';
import 'package:pusk_list/src/keys_diff.dart';
import 'package:pusk_list/src/types.dart';

part 'controller.dart';
part 'item_animation.dart';
part 'pusk_list.dart';
part 'render_sliver_list.dart';
part 'scroll_to_item_activity.dart';
part 'separated.dart';

/// A sliver list with key-based scroll anchoring and fast jumps to any item.
///
/// Every item is identified by [itemKey]. When the list changes, existing
/// items keep their elements and measured extents, and the first visible
/// item stays where it was on screen (see [anchoring]).
///
/// ```dart
/// CustomScrollView(
///   reverse: true,
///   slivers: [
///     PuskSliverList(
///       controller: controller,
///       itemCount: messages.length,
///       itemKey: (index) => messages[index].id,
///       itemBuilder: (context, index) => MessageTile(messages[index]),
///       estimatedExtent: 80,
///       transition: const PuskItemTransition.sizeFade(),
///     ),
///   ],
/// )
/// ```
class PuskSliverList extends SliverMultiBoxAdaptorWidget {
  PuskSliverList({
    required int itemCount,
    required PuskItemKeyBuilder itemKey,
    required IndexedWidgetBuilder itemBuilder,
    PuskListController? controller,
    double estimatedExtent = 100,
    PuskExtentEstimator? extentEstimator,
    PuskPosition? initialPosition,
    PuskAnchoring anchoring = const PuskAnchoring(),
    PuskExtentCache? extentCache,
    PuskItemTransition? transition,
    EdgeInsets obscuredInsets = EdgeInsets.zero,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    Key? key,
  }) : this._(
         itemCount: itemCount,
         itemKey: itemKey,
         itemBuilder: itemBuilder,
         controller: controller,
         estimatedExtent: estimatedExtent,
         extentEstimator: extentEstimator,
         initialPosition: initialPosition,
         anchoring: anchoring,
         extentCache: extentCache,
         transition: transition,
         obscuredInsets: obscuredInsets,
         addAutomaticKeepAlives: addAutomaticKeepAlives,
         addRepaintBoundaries: addRepaintBoundaries,
         addSemanticIndexes: addSemanticIndexes,
         key: key,
       );

  /// A list with a separator after every item but the last.
  ///
  /// `separatorBuilder(context, index)` builds the separator between the
  /// items at `index` and `index + 1`. The separator is a part of the item:
  /// it is counted in the item's extent and appears, disappears and
  /// animates together with it.
  PuskSliverList.separated({
    required int itemCount,
    required PuskItemKeyBuilder itemKey,
    required IndexedWidgetBuilder itemBuilder,
    required IndexedWidgetBuilder separatorBuilder,
    PuskListController? controller,
    double estimatedExtent = 100,
    PuskExtentEstimator? extentEstimator,
    PuskPosition? initialPosition,
    PuskAnchoring anchoring = const PuskAnchoring(),
    PuskExtentCache? extentCache,
    PuskItemTransition? transition,
    EdgeInsets obscuredInsets = EdgeInsets.zero,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    Key? key,
  }) : this._(
         itemCount: itemCount,
         itemKey: itemKey,
         itemBuilder: itemBuilder,
         separatorBuilder: separatorBuilder,
         controller: controller,
         estimatedExtent: estimatedExtent,
         extentEstimator: extentEstimator,
         initialPosition: initialPosition,
         anchoring: anchoring,
         extentCache: extentCache,
         transition: transition,
         obscuredInsets: obscuredInsets,
         addAutomaticKeepAlives: addAutomaticKeepAlives,
         addRepaintBoundaries: addRepaintBoundaries,
         addSemanticIndexes: addSemanticIndexes,
         key: key,
       );

  PuskSliverList._({
    required this.itemCount,
    required this.itemKey,
    required IndexedWidgetBuilder itemBuilder,
    required this.controller,
    required this.estimatedExtent,
    required this.extentEstimator,
    required this.initialPosition,
    required this.anchoring,
    required this.extentCache,
    required this.transition,
    required this.obscuredInsets,
    required bool addAutomaticKeepAlives,
    required bool addRepaintBoundaries,
    required bool addSemanticIndexes,
    required super.key,
    IndexedWidgetBuilder? separatorBuilder,
  }) : assert(itemCount >= 0),
       assert(estimatedExtent >= 0),
       super(
         delegate: _PuskChildDelegate(
           itemCount: itemCount,
           itemBuilder: itemBuilder,
           separatorBuilder: separatorBuilder,
           transition: transition,
           addAutomaticKeepAlives: addAutomaticKeepAlives,
           addRepaintBoundaries: addRepaintBoundaries,
           addSemanticIndexes: addSemanticIndexes,
         ),
       );

  final int itemCount;

  /// Unique, stable key of the item at an index: an id, a string, anything
  /// with a meaningful `==` and `hashCode`.
  final PuskItemKeyBuilder itemKey;

  final PuskListController? controller;

  /// Extent assumed for items that haven't been laid out yet.
  final double estimatedExtent;

  /// Per-item estimate, used instead of [estimatedExtent] when given.
  ///
  /// Called for items as they are added to the list. Changing the callback
  /// doesn't re-estimate existing items.
  final PuskExtentEstimator? extentEstimator;

  /// Position to show on the first layout.
  final PuskPosition? initialPosition;

  final PuskAnchoring anchoring;

  /// Measured extents to reuse across list instances.
  final PuskExtentCache? extentCache;

  /// How items appear and disappear; `null` applies changes immediately.
  ///
  /// Removed items keep their element while they animate out: the item
  /// builder is never called for them.
  final PuskItemTransition? transition;

  /// Parts of the viewport covered by other widgets, e.g. a translucent app
  /// bar or an input field over the list.
  ///
  /// Jumps align items within the rest of the viewport, and items entirely
  /// under these insets aren't visible. Pinned headers before the list are
  /// accounted for automatically. The insets are physical (`top` is the top
  /// in a reversed list too) and add no space: use padding for that.
  final EdgeInsets obscuredInsets;

  @override
  SliverMultiBoxAdaptorElement createElement() => _PuskSliverListElement(this);

  @override
  RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context) {
    final element = context as _PuskSliverListElement;
    return _RenderPuskSliverList(
      childManager: element,
      keys: element._keys,
      estimatedExtent: estimatedExtent,
      extentEstimator: extentEstimator,
      anchoring: anchoring,
      controller: controller,
      extentCache: extentCache,
      transition: transition,
      obscuredInsets: obscuredInsets,
      initialPosition: initialPosition,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverMultiBoxAdaptor renderObject,
  ) {
    (renderObject as _RenderPuskSliverList)
      ..controller = controller
      ..estimatedExtent = estimatedExtent
      ..extentEstimator = extentEstimator
      ..anchoring = anchoring
      ..extentCache = extentCache
      ..transition = transition
      ..obscuredInsets = obscuredInsets;
  }
}

/// Item key as seen by the framework.
class _PuskItemKey extends ValueKey<Object> {
  const _PuskItemKey(super.value);
}

/// The outermost widget of every item.
///
/// Remembers what the item builder returned, so that a removed item can be
/// shown while it animates out without calling the builder.
class _PuskItem extends KeyedSubtree {
  _PuskItem({
    required Object itemKey,
    required this.content,
    required this.semanticIndex,
    required super.child,
  }) : super(key: _PuskItemKey(itemKey));

  /// What the item builder returned.
  final Widget content;

  final int semanticIndex;
}

class _PuskChildDelegate extends SliverChildDelegate {
  _PuskChildDelegate({
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
    required this.transition,
    required this.addAutomaticKeepAlives,
    required this.addRepaintBoundaries,
    required this.addSemanticIndexes,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final PuskItemTransition? transition;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;

  /// Number of displayed items: [itemCount] plus removed items that are
  /// still animating out. Set by the element.
  int? displayCount;

  /// New indices of the existing children whose index changed, by item key.
  ///
  /// Filled by the element right before it rebuilds with this delegate.
  /// Children that are absent keep their index (and get replaced if their
  /// key no longer matches).
  Map<Object, int>? movedChildren;

  @override
  Widget? build(BuildContext context, int index) {
    final element = context as _PuskSliverListElement;
    final keys = element._keys;
    if (index < 0 || index >= keys.length) return null;
    final key = keys[index];

    final removed = element._removedItems.isEmpty
        ? null
        : element._removedItems[key];
    if (removed != null) {
      // Same widget as before: the item doesn't rebuild at all.
      if (transition?.builder == null) return removed;
      return _wrap(context, key, removed.semanticIndex, removed.content);
    }

    final itemIndex = element._itemIndexOf(index);
    Widget content;
    try {
      content = itemBuilder(context, itemIndex);
      final separatorBuilder = this.separatorBuilder;
      if (separatorBuilder != null) {
        // Always wrapped, so that the item keeps its element when it
        // becomes or stops being the last one.
        content = _Separated(
          item: content,
          separator: itemIndex < itemCount - 1
              ? separatorBuilder(context, itemIndex)
              : null,
        );
      }
    } catch (exception, stackTrace) {
      final details = FlutterErrorDetails(
        exception: exception,
        stack: stackTrace,
        library: 'pusk_list',
        context: ErrorDescription('building item $itemIndex'),
      );
      FlutterError.reportError(details);
      content = ErrorWidget.builder(details);
    }
    return _wrap(context, key, itemIndex, content);
  }

  Widget _wrap(
    BuildContext context,
    Object key,
    int semanticIndex,
    Widget content,
  ) {
    var child = content;
    if (addRepaintBoundaries) child = RepaintBoundary(child: child);
    final builder = transition?.builder;
    if (builder != null) {
      final element = context as _PuskSliverListElement;
      final animation = element.renderObject.animationOf(key);
      child = builder(
        context,
        animation ?? kAlwaysCompleteAnimation,
        key,
        child,
      );
    }
    if (addSemanticIndexes) {
      child = IndexedSemantics(index: semanticIndex, child: child);
    }
    if (addAutomaticKeepAlives) child = AutomaticKeepAlive(child: child);
    // The key is the outermost widget, so findIndexByKey receives it as is.
    return _PuskItem(
      itemKey: key,
      content: content,
      semanticIndex: semanticIndex,
      child: child,
    );
  }

  @override
  int? findIndexByKey(Key key) {
    if (key is! _PuskItemKey) return null;
    return movedChildren?[key.value];
  }

  @override
  int get estimatedChildCount => displayCount ?? itemCount;

  @override
  bool shouldRebuild(covariant SliverChildDelegate oldDelegate) => true;
}

/// A removed item that is animating out, and where it ends up.
typedef _Removed = ({Object key, int oldIndex});

class _PuskSliverListElement extends SliverMultiBoxAdaptorElement {
  _PuskSliverListElement(PuskSliverList super.widget)
    : _itemKeys = KeysDiff.initial(widget.itemCount, widget.itemKey) {
    _keys = _itemKeys;
  }

  /// Keys of the current items. Replaced (never mutated) on change.
  List<Object> _itemKeys;

  /// Keys of the displayed items: the current items plus the removed items
  /// that are animating out. Children, the render object and the extents
  /// all use indices into this list ("display indices").
  late List<Object> _keys;

  /// Sorted display indices of the removed items that are animating out.
  List<int> _removedIndices = const [];

  /// Last widgets of the removed items that are animating out.
  final Map<Object, _PuskItem> _removedItems = HashMap<Object, _PuskItem>();

  /// Removed items whose animation has finished, to be dropped on the next
  /// rebuild.
  final Set<Object> _finishedRemovals = HashSet<Object>();

  @override
  _RenderPuskSliverList get renderObject =>
      super.renderObject as _RenderPuskSliverList;

  _PuskChildDelegate get _delegate =>
      (widget as PuskSliverList).delegate as _PuskChildDelegate;

  int _itemIndexOf(int displayIndex) =>
      displayIndex - _countBelow(_removedIndices, displayIndex);

  void _onRemovalsFinished(Iterable<Object> keys) {
    _finishedRemovals.addAll(keys);
    markNeedsBuild();
  }

  /// Mutes the list's animations where tickers are disabled (e.g. under a
  /// route that is covered by another one), like [TickerProviderStateMixin].
  ValueListenable<TickerModeData>? _tickerMode;

  void _updateTickerMode() {
    final notifier = TickerMode.getValuesNotifier(this);
    if (notifier == _tickerMode) return;
    _tickerMode?.removeListener(_onTickerModeChanged);
    _tickerMode = notifier..addListener(_onTickerModeChanged);
    _onTickerModeChanged();
  }

  void _onTickerModeChanged() {
    renderObject.tickerMuted = !_tickerMode!.value.enabled;
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _updateTickerMode();
  }

  @override
  void activate() {
    super.activate();
    _updateTickerMode();
  }

  @override
  void unmount() {
    _tickerMode?.removeListener(_onTickerModeChanged);
    _tickerMode = null;
    super.unmount();
  }

  @override
  void performRebuild() {
    _updateTickerMode();
    _reconcile();
    _delegate.displayCount = _keys.length;
    super.performRebuild();
    _delegate.movedChildren = null;
  }

  /// Brings the displayed keys in line with the widget's items.
  void _reconcile() {
    final widget = this.widget as PuskSliverList;
    final animate = widget.transition != null;
    final hadRemovals = _removedIndices.isNotEmpty;
    final oldItemKeys = _itemKeys;
    final diff = KeysDiff.compute(
      oldItemKeys,
      widget.itemCount,
      widget.itemKey,
    );
    final dropRemovals =
        hadRemovals && (!animate || _finishedRemovals.isNotEmpty);
    if (diff == null && !dropRemovals) return;
    if (diff != null) _itemKeys = diff.newKeys;

    final removed = animate && diff != null && oldItemKeys.isNotEmpty
        ? _collectVisibleRemovals(diff)
        : const <_Removed>[];

    if (!hadRemovals && removed.isEmpty) {
      // The displayed keys are the items' keys.
      _apply(
        diff,
        animateInserts: animate && oldItemKeys.isNotEmpty,
        removedIndices: const [],
        newlyRemoved: const [],
        reinserted: const [],
      );
      return;
    }

    // Removed items that keep animating out, in display order, and the
    // ones that came back.
    final oldKeys = _keys;
    final oldRemovedIndices = _removedIndices;
    final staying = <_Removed>[];
    final reinserted = <Object>[];
    var next = 0;
    void addNewRemovalsBefore(int oldIndex) {
      while (next < removed.length && removed[next].oldIndex < oldIndex) {
        staying.add(removed[next]);
        next++;
      }
    }

    for (final oldIndex in oldRemovedIndices) {
      addNewRemovalsBefore(oldIndex);
      final key = oldKeys[oldIndex];
      if (diff?.newBlockIndexOf(key) != null) {
        reinserted.add(key);
        _removedItems.remove(key);
      } else if (!animate || _finishedRemovals.contains(key)) {
        _removedItems.remove(key);
      } else {
        staying.add((key: key, oldIndex: oldIndex));
      }
    }
    addNewRemovalsBefore(oldKeys.length);
    _finishedRemovals.clear();

    // New index of the first item in old display indices [from, to) that is
    // still there.
    int? firstRemainingIn(int from, int to) {
      for (var i = from; i < to; i++) {
        final int? newIndex;
        if (_contains(oldRemovedIndices, i)) {
          // A removed item that came back or is dropped now.
          newIndex = diff?.newBlockIndexOf(oldKeys[i]);
        } else {
          final itemIndex = i - _countBelow(oldRemovedIndices, i);
          newIndex = diff == null ? itemIndex : diff.newIndexOf(itemIndex);
        }
        if (newIndex != null) return newIndex;
      }
      return null;
    }

    // Each removed item stays right before the item that followed it.
    // Walking back from the last one, each search stops where the previous
    // one started, so this is a single pass even when everything is gone.
    final at = List<int>.filled(staying.length, 0);
    var following = _itemKeys.length;
    var searchEnd = oldKeys.length;
    for (var k = staying.length - 1; k >= 0; k--) {
      final oldIndex = staying[k].oldIndex;
      following = firstRemainingIn(oldIndex + 1, searchEnd) ?? following;
      at[k] = following;
      searchEnd = oldIndex;
    }
    final positions = [
      for (var k = 0; k < staying.length; k++) (key: staying[k].key, at: at[k]),
    ];
    mergeSort(positions, compare: (a, b) => a.at.compareTo(b.at));

    final itemKeys = _itemKeys;
    final keys = <Object>[];
    final removedIndices = <int>[];
    final displayIndexOfKey = HashMap<Object, int>();
    var p = 0;
    for (var i = 0; i <= itemKeys.length; i++) {
      while (p < positions.length && positions[p].at == i) {
        displayIndexOfKey[positions[p].key] = keys.length;
        removedIndices.add(keys.length);
        keys.add(positions[p].key);
        p++;
      }
      if (i < itemKeys.length) keys.add(itemKeys[i]);
    }

    final displayDiff = KeysDiff.between(oldKeys, keys);
    _removedIndices = removedIndices;
    int displayIndexOfItem(int itemIndex) {
      var index = itemIndex;
      for (final r in removedIndices) {
        if (r > index) break;
        index++;
      }
      return index;
    }

    _apply(
      displayDiff,
      animateInserts: animate && oldItemKeys.isNotEmpty,
      removedIndices: removedIndices,
      newlyRemoved: [for (final r in removed) displayIndexOfKey[r.key]!],
      reinserted: [
        for (final key in reinserted)
          displayIndexOfItem(diff!.newBlockIndexOf(key)!),
      ],
    );
  }

  /// Removed items that are visible become animated removals; their last
  /// widgets are kept to show them while they animate out.
  List<_Removed> _collectVisibleRemovals(KeysDiff diff) {
    final range = renderObject.visibleDisplayRange;
    if (range == null) return const [];
    Map<int, Element>? children;
    final removed = <_Removed>[];
    for (var index = range.first; index <= range.last; index++) {
      if (_contains(_removedIndices, index)) continue;
      final itemIndex = _itemIndexOf(index);
      if (itemIndex < diff.start || itemIndex >= diff.oldEnd) continue;
      final key = diff.oldKeys[itemIndex];
      if (diff.newBlockIndexOf(key) != null) continue;
      children ??= () {
        final map = HashMap<int, Element>();
        visitChildren((child) => map[child.slot! as int] = child);
        return map;
      }();
      final item = children[index]?.widget;
      if (item is! _PuskItem) continue;
      _removedItems[key] = item;
      removed.add((key: key, oldIndex: index));
    }
    return removed;
  }

  void _apply(
    KeysDiff? diff, {
    required bool animateInserts,
    required List<int> removedIndices,
    required List<int> newlyRemoved,
    required List<int> reinserted,
  }) {
    _removedIndices = removedIndices;
    if (diff != null) {
      final moved = HashMap<Object, int>();
      visitChildren((child) {
        final oldIndex = child.slot! as int;
        final newIndex = diff.newIndexOf(oldIndex);
        if (newIndex != null && newIndex != oldIndex) {
          moved[diff.oldKeys[oldIndex]] = newIndex;
        }
      });
      _delegate.movedChildren = moved;
      _keys = diff.newKeys;
      renderObject.applyKeysDiff(
        diff,
        removedIndices: removedIndices,
        animateInserts: animateInserts,
      );
    }
    renderObject.updateRemovals(
      removedIndices: removedIndices,
      newlyRemoved: newlyRemoved,
      reinserted: reinserted,
    );
  }
}

/// Number of elements of the sorted [list] that are smaller than [value].
int _countBelow(List<int> list, int value) {
  var low = 0;
  var high = list.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (list[mid] < value) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

bool _contains(List<int> sorted, int value) {
  final i = _countBelow(sorted, value);
  return i < sorted.length && sorted[i] == value;
}
