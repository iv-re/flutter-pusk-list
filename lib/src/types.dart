import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Estimates the extent of an item that hasn't been laid out yet.
typedef PuskExtentEstimator = double Function(int index);

/// `first` and `last` indices of the items visible in the viewport.
typedef PuskVisibleRange = ({int first, int last});

/// A scroll position expressed as an item and where it sits in the viewport.
@immutable
class PuskPosition {
  const PuskPosition({required this.index, this.alignment = 0.0});

  final int index;

  /// `0.0` puts the item's leading edge at the viewport's leading edge,
  /// `0.5` centers it, `1.0` puts its trailing edge at the trailing edge.
  final double alignment;

  @override
  bool operator ==(Object other) =>
      other is PuskPosition &&
      other.index == index &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(index, alignment);

  @override
  String toString() => 'PuskPosition(index: $index, alignment: $alignment)';
}

/// How the list keeps its scroll position when items change.
///
/// The first visible item is the anchor: when items are inserted or removed
/// before it, or items before it change their extent, the scroll offset is
/// corrected so that the anchor stays where it was on screen.
@immutable
class PuskAnchoring {
  const PuskAnchoring({
    this.stickToStartEdge = true,
    this.edgeThreshold = 1.0,
  });

  /// When the list is scrolled to its start (within [edgeThreshold]), items
  /// inserted at the start become visible instead of being compensated for.
  ///
  /// This is what a chat wants for new messages when the user is at the
  /// latest message.
  final bool stickToStartEdge;

  /// Distance from the start edge, in pixels, that still counts as "at the
  /// start".
  final double edgeThreshold;

  @override
  bool operator ==(Object other) =>
      other is PuskAnchoring &&
      other.stickToStartEdge == stickToStartEdge &&
      other.edgeThreshold == edgeThreshold;

  @override
  int get hashCode => Object.hash(stickToStartEdge, edgeThreshold);
}

/// Where a visible item sits in the viewport.
///
/// Edges are fractions of the viewport's main-axis extent: `0.0` is the
/// viewport's leading edge, `1.0` its trailing edge. Parts covered by
/// `obscuredInsets` and pinned headers are left out, as for jump alignment.
@immutable
class PuskItemPosition {
  const PuskItemPosition({
    required this.index,
    required this.key,
    required this.leadingEdge,
    required this.trailingEdge,
  });

  final int index;
  final Object key;
  final double leadingEdge;
  final double trailingEdge;

  /// The alignment that would put this item where it currently is.
  double get alignment {
    final extent = trailingEdge - leadingEdge;
    if ((1.0 - extent).abs() < 1e-6) return leadingEdge;
    return leadingEdge / (1.0 - extent);
  }

  @override
  String toString() =>
      'PuskItemPosition(index: $index, key: $key, '
      '$leadingEdge → $trailingEdge)';
}

/// Wraps an item in its insert/remove transition.
///
/// [key] is the item's key (from `itemKey`), also for a removed item that
/// is animating out, when its index no longer exists. Use it to animate
/// items differently, e.g. a chat bubble from its own corner.
///
/// [animation] runs from `0.0` to `1.0` when the item is inserted and from
/// its current value to `0.0` when it is removed. Items that don't animate
/// get a completed animation, so the builder must return the same widget
/// structure for any animation (otherwise items lose their state when their
/// animation starts or ends).
///
/// The builder runs when the item gets built, not on every frame: use
/// widgets that listen to [animation], like [FadeTransition] or
/// [SlideTransition].
typedef PuskItemTransitionBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Object key,
      Widget child,
    );

/// How items appear and disappear.
///
/// Only items inserted into or removed from the visible part of the list
/// animate. Changes outside of it, and the first items of an empty list,
/// apply immediately, so anchoring and jumps stay exact.
///
/// When [animateSize] is on, the item's extent grows from zero (or shrinks to
/// zero) and the item slides in from the list's leading edge: in a reversed
/// chat a new message rises from the bottom. It isn't clipped to its growing
/// space: while it doesn't fit, it sticks out from under its neighbour (or
/// from behind the viewport's edge), since animating items paint first.
/// Anchoring sees the animated extent, so nothing moves on screen when the
/// change is above the anchor.
///
/// Visible items whose extent changes in the same update (e.g. a chat
/// message that gains its author's name when the one above it is deleted)
/// animate it too. Other extent changes, like streamed text, apply
/// immediately.
@immutable
class PuskItemTransition {
  /// The item's space opens (or closes) while the item fades in (or out)
  /// in place: the item doesn't scale or slide relative to its neighbour on
  /// the trailing side.
  ///
  /// Both follow one animation value; with a [fadeStart] above zero the
  /// item stays transparent until the value passes it (and on removal is
  /// gone before its space closes). Done entirely by the list's render
  /// object, without extra widgets.
  const PuskItemTransition.sizeFade({
    this.insertDuration = const Duration(milliseconds: 350),
    this.removeDuration = const Duration(milliseconds: 350),
    this.insertCurve = Curves.ease,
    this.removeCurve = Curves.ease,
    this.fadeStart = 0,
  }) : assert(fadeStart >= 0 && fadeStart < 1),
       builder = null,
       animateSize = true,
       fade = true;

  /// Items are wrapped with [builder]; the list animates their size when
  /// [animateSize] is on.
  const PuskItemTransition.custom({
    required PuskItemTransitionBuilder this.builder,
    this.animateSize = true,
    this.insertDuration = const Duration(milliseconds: 350),
    this.removeDuration = const Duration(milliseconds: 350),
    this.insertCurve = Curves.ease,
    this.removeCurve = Curves.ease,
  }) : fade = false,
       fadeStart = 0;

  final Duration insertDuration;
  final Duration removeDuration;
  final Curve insertCurve;

  /// Applied to the time of the removal, like [insertCurve]: the default
  /// starts fast and settles, so the space closes without a jerk at the end.
  final Curve removeCurve;

  /// Whether the extent of items animates.
  final bool animateSize;

  /// Whether the list fades items itself.
  final bool fade;

  /// Animation value below which a fading item is fully transparent; the
  /// opacity goes from 0 to 1 between it and `1.0`.
  final double fadeStart;

  final PuskItemTransitionBuilder? builder;

  @override
  bool operator ==(Object other) =>
      other is PuskItemTransition &&
      other.insertDuration == insertDuration &&
      other.removeDuration == removeDuration &&
      other.insertCurve == insertCurve &&
      other.removeCurve == removeCurve &&
      other.animateSize == animateSize &&
      other.fade == fade &&
      other.fadeStart == fadeStart &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    insertDuration,
    removeDuration,
    insertCurve,
    removeCurve,
    animateSize,
    fade,
    fadeStart,
    builder,
  );
}

/// Measured item extents keyed by item key.
///
/// Pass the same cache to a list that gets recreated (e.g. reopening a chat)
/// so that previously measured items don't fall back to estimates.
class PuskExtentCache {
  final Map<Object, double> _extents = HashMap<Object, double>();

  double? operator [](Object key) => _extents[key];

  void operator []=(Object key, double extent) => _extents[key] = extent;

  int get length => _extents.length;

  void remove(Object key) => _extents.remove(key);

  void clear() => _extents.clear();
}
