part of 'sliver_list.dart';

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
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: addRepaintBoundaries,
      addSemanticIndexes: addSemanticIndexes,
      key: null,
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
