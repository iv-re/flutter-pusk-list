import 'package:flutter/widgets.dart';
import 'package:pusk_list/src/keys_diff.dart';
import 'package:pusk_list/src/reorderable.dart';
import 'package:pusk_list/src/sliver_list.dart';
import 'package:pusk_list/src/types.dart';

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
class PuskSliverList extends StatelessWidget {
  const PuskSliverList({
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    this.controller,
    this.estimatedExtent = 100,
    this.extentEstimator,
    this.initialPosition,
    this.anchoring = const PuskAnchoring(),
    this.extentCache,
    this.transition,
    this.obscuredInsets = EdgeInsets.zero,
    this.reorder,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    super.key,
  }) : separatorBuilder = null;

  /// A list with a separator after every item but the last.
  ///
  /// `separatorBuilder(context, index)` builds the separator between the
  /// items at `index` and `index + 1`. The separator is a part of the item:
  /// it is counted in the item's extent and appears, disappears and
  /// animates together with it.
  const PuskSliverList.separated({
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
    this.controller,
    this.estimatedExtent = 100,
    this.extentEstimator,
    this.initialPosition,
    this.anchoring = const PuskAnchoring(),
    this.extentCache,
    this.transition,
    this.obscuredInsets = EdgeInsets.zero,
    this.reorder,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    super.key,
  });

  const PuskSliverList._({
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    required this.separatorBuilder,
    required this.controller,
    required this.estimatedExtent,
    required this.extentEstimator,
    required this.initialPosition,
    required this.anchoring,
    required this.extentCache,
    required this.transition,
    required this.obscuredInsets,
    required this.reorder,
    required this.addAutomaticKeepAlives,
    required this.addRepaintBoundaries,
    required this.addSemanticIndexes,
  }) : super(key: null);

  final int itemCount;

  /// Unique, stable key of the item at an index: an id, a string, anything
  /// with a meaningful `==` and `hashCode`.
  final PuskItemKeyBuilder itemKey;

  final IndexedWidgetBuilder itemBuilder;

  final IndexedWidgetBuilder? separatorBuilder;

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

  /// Lets the user drag items to new places; see [PuskReorder].
  ///
  /// While an item is dragged, [itemBuilder] and [extentEstimator] get
  /// indices of the unchanged list, [separatorBuilder] that of the gap (the
  /// same gaps as without dragging), and [controller] indices of the list as
  /// shown. Switching between `null` and a value
  /// rebuilds the items: to turn dragging on and off (e.g. an edit mode),
  /// keep it and show or hide the [PuskDragStartListener]s.
  final PuskReorder? reorder;

  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;

  @override
  Widget build(BuildContext context) {
    final reorder = this.reorder;
    if (reorder == null) {
      return _raw(
        itemCount: itemCount,
        itemKey: itemKey,
        itemBuilder: itemBuilder,
        separatorBuilder: separatorBuilder,
        extentEstimator: extentEstimator,
        controller: controller,
      );
    }
    return PuskReorderLayer(
      reorder: reorder,
      itemCount: itemCount,
      itemKey: itemKey,
      itemBuilder: itemBuilder,
      controller: controller,
      builder: (context, items, controller) {
        final estimator = extentEstimator;
        return _raw(
          itemCount: items.count,
          itemKey: items.key,
          itemBuilder: items.build,
          // Not mapped: a separator belongs to the gap between two places.
          separatorBuilder: separatorBuilder,
          extentEstimator: estimator == null
              ? null
              : (index) => estimator(items.sourceIndex(index)),
          controller: controller,
        );
      },
    );
  }

  Widget _raw({
    required int itemCount,
    required PuskItemKeyBuilder itemKey,
    required IndexedWidgetBuilder itemBuilder,
    required IndexedWidgetBuilder? separatorBuilder,
    required PuskExtentEstimator? extentEstimator,
    required PuskListController? controller,
  }) => PuskRawSliverList(
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
  );
}

/// A scroll view with a single [PuskSliverList].
///
/// ```dart
/// PuskList(
///   reverse: true,
///   controller: controller,
///   itemCount: messages.length,
///   itemKey: (index) => messages[index].id,
///   itemBuilder: (context, index) => MessageTile(messages[index]),
/// )
/// ```
///
/// Use [PuskSliverList] in a [CustomScrollView] to combine the list with
/// other slivers.
class PuskList extends StatelessWidget {
  const PuskList({
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    this.controller,
    this.estimatedExtent = 100,
    this.extentEstimator,
    this.initialPosition,
    this.anchoring = const PuskAnchoring(),
    this.extentCache,
    this.transition,
    this.obscuredInsets = EdgeInsets.zero,
    this.reorder,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.scrollController,
    this.primary,
    this.physics,
    this.padding,
    this.scrollCacheExtent,
    this.keyboardDismissBehavior,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  }) : separatorBuilder = null;

  /// A list with a separator after every item but the last; see
  /// [PuskSliverList.separated].
  const PuskList.separated({
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
    this.controller,
    this.estimatedExtent = 100,
    this.extentEstimator,
    this.initialPosition,
    this.anchoring = const PuskAnchoring(),
    this.extentCache,
    this.transition,
    this.obscuredInsets = EdgeInsets.zero,
    this.reorder,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.scrollController,
    this.primary,
    this.physics,
    this.padding,
    this.scrollCacheExtent,
    this.keyboardDismissBehavior,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  });

  final int itemCount;
  final PuskItemKeyBuilder itemKey;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final PuskListController? controller;
  final double estimatedExtent;
  final PuskExtentEstimator? extentEstimator;
  final PuskPosition? initialPosition;
  final PuskAnchoring anchoring;
  final PuskExtentCache? extentCache;
  final PuskItemTransition? transition;
  final EdgeInsets obscuredInsets;

  /// See [PuskSliverList.reorder].
  final PuskReorder? reorder;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;

  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? scrollController;
  final bool? primary;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final ScrollCacheExtent? scrollCacheExtent;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    Widget sliver = PuskSliverList._(
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
      reorder: reorder,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: addRepaintBoundaries,
      addSemanticIndexes: addSemanticIndexes,
    );
    final padding = this.padding;
    if (padding != null) {
      sliver = SliverPadding(padding: padding, sliver: sliver);
    }
    return CustomScrollView(
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: scrollController,
      primary: primary,
      physics: physics,
      scrollCacheExtent: scrollCacheExtent,
      keyboardDismissBehavior: keyboardDismissBehavior,
      restorationId: restorationId,
      clipBehavior: clipBehavior,
      slivers: [sliver],
    );
  }
}
