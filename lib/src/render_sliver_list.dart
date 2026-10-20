part of 'sliver_list.dart';

/// Corrections smaller than this (in pixels) are ignored.
const double _kCorrectionTolerance = 1e-3;

/// Upper bound on scroll corrections requested in a row, so that a
/// misbehaving item (e.g. one that changes its extent on every layout) can't
/// make the viewport give up.
const int _kMaxConsecutiveCorrections = 5;

/// How many layout passes a jump may use to land precisely.
const int _kMaxJumpRefinements = 4;

typedef _JumpTarget = ({int index, double alignment});

class _RenderPuskSliverList extends RenderSliverMultiBoxAdaptor {
  _RenderPuskSliverList({
    required _PuskSliverListElement super.childManager,
    required List<Object> keys,
    required this._estimatedExtent,
    required this.extentEstimator,
    required this._anchoring,
    required this._controller,
    required this.extentCache,
    required this._transition,
    required this._obscuredInsets,
    required PuskPosition? initialPosition,
  }) : _keys = keys {
    final values = Float64List(keys.length);
    for (var i = 0; i < values.length; i++) {
      values[i] = _initialExtentFor(i);
    }
    _extents.reset(values);
    if (initialPosition != null) {
      _jumpTarget = (
        index: initialPosition.index,
        alignment: initialPosition.alignment,
      );
      _jumpNeedsInitialCorrection = true;
    }
  }

  final ItemExtents _extents = ItemExtents();
  List<Object> _keys;
  Map<Object, int>? _keyIndex;

  // Anchoring state captured at the end of the last completed layout.
  bool _hasLaidOut = false;
  double _lastScrollOffset = 0;
  int _anchorIndex = 0;

  /// Scroll correction caused by key changes, applied on the next layout.
  double _pendingCorrection = 0;
  int _consecutiveCorrections = 0;

  _JumpTarget? _jumpTarget;
  bool _jumpNeedsInitialCorrection = false;
  int _jumpRefinements = 0;

  /// Remaining paint extent of the last completed layout.
  double _lastPaintExtent = 0;

  /// Scroll extent reported by the last completed layout.
  double _lastScrollExtent = 0;

  // Display indices of the visible items (removed ones included).
  int? _firstVisibleIndex;
  int? _lastVisibleIndex;
  PuskVisibleRange? _visibleRange;

  // Insert/remove animations.
  final Map<Object, _ItemAnimation> _animations =
      HashMap<Object, _ItemAnimation>();
  Ticker? _ticker;
  Duration _lastTickElapsed = Duration.zero;

  /// Whether ticks are skipped while time still passes (see [TickerMode]).
  bool get tickerMuted => _tickerMuted;
  bool _tickerMuted = false;
  set tickerMuted(bool value) {
    if (value == _tickerMuted) return;
    _tickerMuted = value;
    _ticker?.muted = value;
  }

  /// Sorted display indices of the removed items that are animating out.
  List<int> _removedIndices = const [];

  /// Extent changes of items that stay, animated next to insertions and
  /// removals.
  final Map<Object, _ItemResize> _resizes = HashMap<Object, _ItemResize>();

  /// Display index ranges `[start, end)` changed by the last update. Until
  /// the next completed layout, visible items that change their extent
  /// animate it.
  List<(int, int)>? _changedRanges;
  Duration _resizeDuration = Duration.zero;
  Curve _resizeCurve = Curves.linear;

  // ---------------------------------------------------------------------------
  // Configuration

  double _estimatedExtent;
  double get estimatedExtent => _estimatedExtent;
  set estimatedExtent(double value) {
    if (_estimatedExtent == value) return;
    _estimatedExtent = value;
    if (extentEstimator == null) {
      _extents.reestimate((_) => value);
      markNeedsLayout();
    }
  }

  /// Only affects items added later, so changing it needs no layout.
  PuskExtentEstimator? extentEstimator;

  PuskAnchoring _anchoring;
  PuskAnchoring get anchoring => _anchoring;
  set anchoring(PuskAnchoring value) {
    if (_anchoring == value) return;
    _anchoring = value;
    markNeedsLayout();
  }

  PuskExtentCache? extentCache;

  PuskItemTransition? _transition;
  PuskItemTransition? get transition => _transition;
  set transition(PuskItemTransition? value) {
    if (_transition == value) return;
    _transition = value;
    // Removed items are dropped by the element when transitions turn off.
    if (value == null) _finishInsertAnimations();
    if (!(value?.animateSize ?? false)) _resizes.clear();
    markNeedsLayout();
  }

  EdgeInsets _obscuredInsets;
  EdgeInsets get obscuredInsets => _obscuredInsets;
  set obscuredInsets(EdgeInsets value) {
    if (_obscuredInsets == value) return;
    _obscuredInsets = value;
    markNeedsLayout();
  }

  PuskListController? _controller;
  PuskListController? get controller => _controller;
  set controller(PuskListController? value) {
    if (identical(_controller, value)) return;
    if (attached) _controller?._detach(this);
    _controller = value;
    if (attached) {
      value?._attach(this);
      value?._publishVisibleRange();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller?._attach(this);
    _updateTicker();
  }

  @override
  void detach() {
    _controller?._detach(this);
    _ticker?.stop();
    super.detach();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    for (final animation in _animations.values) {
      animation.dispose();
    }
    _animations.clear();
    _resizes.clear();
    super.dispose();
  }

  double _initialExtentFor(int index) =>
      extentCache?[_keys[index]] ?? _estimateExtent(index);

  double _estimateExtent(int index) =>
      extentEstimator?.call(index) ?? _estimatedExtent;

  // ---------------------------------------------------------------------------
  // Key changes

  /// [removedIndices] are the display indices of removed items in
  /// [KeysDiff.newKeys], used to give [extentEstimator] item indices.
  void applyKeysDiff(
    KeysDiff diff, {
    List<int> removedIndices = const [],
    bool animateInserts = false,
  }) {
    final oldLength = diff.oldKeys.length;
    final newLength = diff.newKeys.length;

    // Find the anchor and its current offset before touching the extents.
    final oldAnchor = math.min(_anchorIndex, oldLength);
    int? newAnchor;
    var oldAnchorOffset = 0.0;
    if (_hasLaidOut && oldLength > 0 && !_isAtStartEdge) {
      if (oldAnchor >= diff.oldEnd) {
        newAnchor = oldAnchor + diff.delta;
        oldAnchorOffset = _extents.offsetOf(oldAnchor);
      } else if (oldAnchor >= diff.start) {
        newAnchor = diff.newBlockIndexOf(diff.oldKeys[oldAnchor]);
        if (newAnchor != null) {
          oldAnchorOffset = _extents.offsetOf(oldAnchor);
        } else if (diff.oldEnd < oldLength) {
          // The anchor is gone: keep the first item after the block in place.
          newAnchor = diff.newEnd;
          oldAnchorOffset = _extents.offsetOf(diff.oldEnd);
        }
      }
      // An anchor before the block doesn't move.
    }

    final blockLength = diff.newEnd - diff.start;
    final values = Float64List(blockLength);
    final measured = Uint8List(blockLength);
    for (var i = 0; i < blockLength; i++) {
      final index = diff.start + i;
      final key = diff.newKeys[index];
      final oldIndex = diff.oldBlockIndexOf(key);
      if (oldIndex != null) {
        values[i] = _extents[oldIndex];
        measured[i] = _extents.isMeasured(oldIndex) ? 1 : 0;
      } else {
        values[i] =
            extentCache?[key] ??
            _estimateExtent(index - _countBelow(removedIndices, index));
      }
    }
    _extents.replaceRange(
      diff.start,
      diff.oldEnd - diff.start,
      values,
      measured,
    );
    _keys = diff.newKeys;
    _keyIndex = null;
    _remapAnimations(diff);
    if (animateInserts) _armResizes([(diff.start, diff.newEnd)]);

    double anchorShift() =>
        newAnchor == null ? 0 : _extents.offsetOf(newAnchor) - oldAnchorOffset;
    if (animateInserts && _transition != null && _hasLaidOut) {
      _animateVisibleInserts(diff, _pendingCorrection + anchorShift());
    }
    _pendingCorrection += anchorShift();
    _anchorIndex =
        newAnchor ??
        diff.newIndexOf(oldAnchor) ??
        math.min(oldAnchor, newLength);

    final jumpTarget = _jumpTarget;
    if (jumpTarget != null) {
      final index = jumpTarget.index < oldLength
          ? diff.newIndexOf(jumpTarget.index)
          : null;
      _jumpTarget = index == null
          ? null
          : (index: index, alignment: jumpTarget.alignment);
    }

    markNeedsLayout();
  }

  void _remapAnimations(KeysDiff diff) {
    if (_animations.isEmpty) return;
    _animations.removeWhere((key, animation) {
      final index = diff.newIndexOf(animation.index);
      if (index != null) {
        animation.index = index;
        return false;
      }
      animation.dispose();
      return true;
    });
  }

  /// Starts insert animations for new items that land in the visible part
  /// of the list, [scrollShift] being the correction the change causes.
  void _animateVisibleInserts(KeysDiff diff, double scrollShift) {
    final transition = _transition!;
    final start = _lastScrollOffset + scrollShift;
    final end = start + _lastPaintExtent;
    final inserted = <int>[];
    for (
      var i = math.max(diff.start, _extents.indexAt(start));
      i < diff.newEnd && _extents.offsetOf(i) < end;
      i++
    ) {
      if (diff.oldBlockIndexOf(diff.newKeys[i]) == null) inserted.add(i);
    }
    for (final index in inserted) {
      final key = _keys[index];
      final animation = _ItemAnimation(
        key: key,
        index: index,
        fullExtent: _extents[index],
        value: 0,
      );
      _animations[key]?.dispose();
      _animations[key] = animation;
      animation.run(
        target: 1,
        duration: transition.insertDuration,
        curve: transition.insertCurve,
      );
      // The caller compensates for this through the anchor's offset.
      if (transition.animateSize) {
        _extents.setExtent(index, animation.fullExtent * animation.value);
      }
    }
    _updateTicker();
  }

  /// Updates which items are being removed: [newlyRemoved] start animating
  /// out, [reinserted] animate back in. All are display indices.
  void updateRemovals({
    required List<int> removedIndices,
    required List<int> newlyRemoved,
    required List<int> reinserted,
  }) {
    _removedIndices = removedIndices;
    final transition = _transition;
    if (transition == null) return;
    for (final index in newlyRemoved) {
      final key = _keys[index];
      final animation = _animations[key] ??= _ItemAnimation(
        key: key,
        index: index,
        fullExtent: _extents[index],
        value: 1,
      );
      animation.run(
        target: 0,
        duration: transition.removeDuration,
        curve: transition.removeCurve,
      );
    }
    for (final index in reinserted) {
      final key = _keys[index];
      final animation = _animations[key] ??= _ItemAnimation(
        key: key,
        index: index,
        fullExtent: _extents[index],
        value: 0,
      );
      animation.run(
        target: 1,
        duration: transition.insertDuration,
        curve: transition.insertCurve,
      );
    }
    if (newlyRemoved.isNotEmpty || reinserted.isNotEmpty) {
      _armResizes(
        [
          for (final index in newlyRemoved) (index, index + 1),
          for (final index in reinserted) (index, index + 1),
        ],
        removal: newlyRemoved.isNotEmpty,
      );
      _updateTicker();
      markNeedsLayout();
    }
  }

  /// Makes extent changes that come with the update of [ranges] animate,
  /// following the removal's timing when there is one.
  void _armResizes(List<(int, int)> ranges, {bool removal = false}) {
    final transition = _transition;
    if (transition == null || !transition.animateSize || !_hasLaidOut) return;
    if (_changedRanges == null || removal) {
      _resizeDuration = removal
          ? transition.removeDuration
          : transition.insertDuration;
      _resizeCurve = removal ? transition.removeCurve : transition.insertCurve;
    }
    (_changedRanges ??= []).addAll(ranges);
  }

  /// Extent [index] takes in this layout, given its [extent] without a
  /// resize, starting a resize when the item changed next to an update.
  double _resizedExtent(
    int index,
    double extent,
    double offset,
    double scrollOffset,
  ) {
    final key = _keys[index];
    final resize = _resizes[key];
    if (resize != null) {
      if (!resize.isRunning || _animations.containsKey(key)) {
        // Done, or the item is inserted or removed again and that animation
        // takes over.
        _resizes.remove(key);
        return extent;
      }
      if ((resize.to - extent).abs() > _kCorrectionTolerance) {
        resize.retarget(extent);
      }
      return resize.extent;
    }
    final ranges = _changedRanges;
    if (ranges == null ||
        _animations.containsKey(key) ||
        !_extents.isMeasured(index)) {
      return extent;
    }
    final old = _extents[index];
    if ((old - extent).abs() <= _kCorrectionTolerance) return extent;
    final paintEnd = scrollOffset + constraints.remainingPaintExtent;
    if (offset >= paintEnd || offset + math.max(old, extent) <= scrollOffset) {
      return extent;
    }
    _resizes[key] = _ItemResize(
      from: old,
      to: extent,
      pinLeading: _pinsLeading(index, ranges),
      duration: _resizeDuration,
      curve: _resizeCurve,
    );
    _updateTicker();
    return old;
  }

  /// Whether the change nearest to [index] is on its trailing side.
  static bool _pinsLeading(int index, List<(int, int)> ranges) {
    int? best;
    var leading = false;
    for (final (start, end) in ranges) {
      final distance = index < start
          ? start - index
          : index >= end
          ? index - end + 1
          : 0;
      if (best == null || distance < best) {
        best = distance;
        leading = index < start;
      }
    }
    return leading;
  }

  void _updateTicker() {
    final running =
        _resizes.values.any((r) => r.isRunning) ||
        _animations.values.any((a) => a.isRunning);
    if (!running || !attached) {
      _ticker?.stop();
      return;
    }
    final ticker = _ticker ??= Ticker(_tick, debugLabel: 'PuskSliverList')
      ..muted = _tickerMuted;
    if (!ticker.isActive) {
      _lastTickElapsed = Duration.zero;
      ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _lastTickElapsed;
    _lastTickElapsed = elapsed;
    List<Object>? finishedInserts;
    List<Object>? finishedRemovals;
    for (final animation in _animations.values) {
      if (!animation.isRunning) continue;
      if (!animation.tick(delta)) {
        if (animation.isRemoving) {
          (finishedRemovals ??= []).add(animation.key);
        } else {
          (finishedInserts ??= []).add(animation.key);
        }
      }
      _applyAnimatedExtent(animation);
    }
    if (finishedInserts != null) {
      for (final key in finishedInserts) {
        _animations.remove(key)!.dispose();
      }
    }
    // Finished removals stay (at zero extent) until the element drops them.
    if (finishedRemovals != null) {
      (childManager as _PuskSliverListElement)._onRemovalsFinished(
        finishedRemovals,
      );
    }
    // Finished resizes are dropped by the next layout, which stores their
    // final extent.
    var resized = false;
    for (final resize in _resizes.values) {
      if (resize.isRunning) {
        resize.tick(delta);
        resized = true;
      }
    }
    _updateTicker();
    if (resized || (_transition?.animateSize ?? false)) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  /// Stores the animated extent of an item, compensating for it like for
  /// any extent change before the anchor.
  void _applyAnimatedExtent(_ItemAnimation animation) {
    if (!(_transition?.animateSize ?? false)) return;
    final index = animation.index;
    final extent = animation.fullExtent * animation.value;
    final delta = extent - _extents[index];
    if (delta == 0) return;
    if (_hasLaidOut && !_isAtStartEdge && index < _anchorIndex) {
      _pendingCorrection += delta;
    }
    _extents.setExtent(index, extent);
  }

  void _finishInsertAnimations() {
    _animations.removeWhere((key, animation) {
      if (animation.isRemoving) return false;
      animation.finish();
      _applyAnimatedExtent(animation);
      animation.dispose();
      return true;
    });
    _updateTicker();
  }

  Animation<double>? animationOf(Object key) => _animations[key];

  /// Extent an item takes in the list given its laid out extent.
  double _displayedExtent(int index, double fullExtent) {
    final animation = _animations[_keys[index]];
    if (animation == null) return fullExtent;
    animation.fullExtent = fullExtent;
    return (_transition?.animateSize ?? false)
        ? fullExtent * animation.value
        : fullExtent;
  }

  bool get _isAtStartEdge =>
      anchoring.stickToStartEdge &&
      _lastScrollOffset <= anchoring.edgeThreshold;

  /// The item whose leading edge stays in place when extents change.
  ///
  /// That is the first item starting inside the viewport, so an item cut by
  /// the viewport's leading edge grows or shrinks off-screen instead of
  /// moving what the user is looking at (except in a top-to-bottom list, see
  /// [_cutIndexFor]). At the start edge it is item 0, so
  /// a growing first item (e.g. a streamed chat message) pushes the content.
  /// When no item starts inside the viewport but the end of the list is
  /// above its trailing edge (e.g. the list is scrolled past), it is
  /// `length`: the end of the list stays in place, and so does the content
  /// after it.
  ///
  /// A removed item that animates out is never the anchor (it is going
  /// away): the item after it is.
  int _anchorIndexFor(double scrollOffset) {
    if (anchoring.stickToStartEdge && scrollOffset <= anchoring.edgeThreshold) {
      return 0;
    }
    var index = _extents.indexAt(scrollOffset);
    if (index < _extents.length &&
        _extents.offsetOf(index) < scrollOffset - _kCorrectionTolerance) {
      // An item taller than the viewport has no successor starting inside it.
      final next = _extents.offsetOf(index + 1);
      if (next < scrollOffset + constraints.remainingPaintExtent) index++;
    }
    while (index + 1 < _extents.length && _isRemoved(index)) {
      index++;
    }
    return index;
  }

  /// The item cut by the viewport's leading edge whose own extent changes
  /// are not compensated for, or -1.
  ///
  /// Content usually grows towards the visual bottom (appended text,
  /// expanded details), so in a top-to-bottom list such an item keeps its
  /// top in place: its visible part stays still and grows downwards, as in
  /// a reversed list, where the anchor already keeps the visual top of an
  /// item cut by the bottom edge. Inserted, removed and resizing neighbour
  /// items are still compensated for, so their transitions stay off-screen.
  int _cutIndexFor(double scrollOffset, int anchorIndex) {
    final direction = applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    );
    if (direction != AxisDirection.down || anchorIndex == 0) return -1;
    final index = _extents.indexAt(scrollOffset);
    if (index >= anchorIndex ||
        _extents.offsetOf(index) >= scrollOffset - _kCorrectionTolerance) {
      return -1;
    }
    final key = _keys[index];
    if (_animations.containsKey(key) || _resizes.containsKey(key)) return -1;
    return index;
  }

  // ---------------------------------------------------------------------------
  // Layout

  double _extentOf(RenderBox child) => switch (constraints.axis) {
    Axis.vertical => child.size.height,
    Axis.horizontal => child.size.width,
  };

  /// Main axis direction of the last layout.
  AxisDirection? _lastDirection;

  /// Separators follow the direction but get the same box constraints in
  /// any direction, so they wouldn't be laid out again on their own.
  void _relayoutSeparatorsOnDirectionChange() {
    final direction = applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    );
    final changed = _lastDirection != null && _lastDirection != direction;
    _lastDirection = direction;
    if (!changed) return;
    void visit(RenderObject node) {
      if (node is _RenderSeparated) {
        node.markNeedsLayout();
      } else {
        node.visitChildren(visit);
      }
    }

    invokeLayoutCallback<SliverConstraints>((_) => visitChildren(visit));
  }

  @override
  void performLayout() {
    _relayoutSeparatorsOnDirectionChange();
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);
    _layout();
    childManager.didFinishLayout();
  }

  void _layout() {
    final constraints = this.constraints;
    final itemCount = _extents.length;
    final scrollOffset = constraints.scrollOffset;

    if (itemCount == 0) {
      _removeAllChildren();
      geometry = SliverGeometry.zero;
      _didCompleteLayout(scrollOffset);
      return;
    }

    if (_applyEarlyCorrection(scrollOffset)) return;

    final cacheStart = math.max<double>(
      0,
      scrollOffset + constraints.cacheOrigin,
    );
    final cacheEnd = scrollOffset + constraints.remainingCacheExtent;
    final total = _extents.total;

    if (cacheEnd <= cacheStart || cacheStart >= total) {
      // Nothing of this sliver is in the cache area.
      _removeAllChildren();
      geometry = SliverGeometry(scrollExtent: total, maxPaintExtent: total);
      _didCompleteLayout(scrollOffset);
      return;
    }

    // Items before this one changing their extent shift the visible content,
    // so they are compensated for.
    final anchorIndex = _anchorIndexFor(scrollOffset);
    final cutIndex = _cutIndexFor(scrollOffset, anchorIndex);
    final startIndex = _extents.indexAt(cacheStart);
    final childConstraints = constraints.asBoxConstraints();

    // Drop children that are certainly out of range (e.g. after a jump).
    if (firstChild != null) {
      final endIndex = _extents.indexAt(cacheEnd);
      if (indexOf(firstChild!) > endIndex || indexOf(lastChild!) < startIndex) {
        _removeAllChildren();
      }
    }

    var leadingGarbage = 0;
    for (
      var child = firstChild;
      child != null && indexOf(child) < startIndex;
      child = childAfter(child)
    ) {
      leadingGarbage++;
    }
    if (leadingGarbage > 0) collectGarbage(leadingGarbage, 0);

    if (firstChild == null) {
      if (!addInitialChild(
        index: startIndex,
        layoutOffset: _extents.offsetOf(startIndex),
      )) {
        geometry = SliverGeometry(scrollExtent: total, maxPaintExtent: total);
        _didCompleteLayout(scrollOffset);
        return;
      }
      firstChild!.layout(childConstraints, parentUsesSize: true);
    }

    while (indexOf(firstChild!) > startIndex) {
      if (insertAndLayoutLeadingChild(
            childConstraints,
            parentUsesSize: true,
          ) ==
          null) {
        break;
      }
    }

    // Lay out from the first child forward, recording measured extents and
    // computing every offset from the extents tree.
    var correction = 0.0;
    var child = firstChild!;
    var index = indexOf(child);
    var offset = _extents.offsetOf(index);
    while (true) {
      child.layout(childConstraints, parentUsesSize: true);
      final fullExtent = _extentOf(child);
      var extent = _animations.isEmpty
          ? fullExtent
          : _displayedExtent(index, fullExtent);
      if (_resizes.isNotEmpty || _changedRanges != null) {
        extent = _resizedExtent(index, extent, offset, scrollOffset);
      }
      if (!_extents.isMeasured(index) || _extents[index] != extent) {
        if (index < anchorIndex && index != cutIndex) {
          correction += extent - _extents[index];
        }
        _extents.setMeasured(index, extent);
        extentCache?[_keys[index]] = fullExtent;
      }
      (child.parentData! as SliverMultiBoxAdaptorParentData).layoutOffset =
          offset;
      offset += extent;

      if (offset >= cacheEnd || index + 1 >= itemCount) break;
      var next = childAfter(child);
      if (next == null || indexOf(next) != index + 1) {
        next = insertAndLayoutChild(
          childConstraints,
          after: child,
          parentUsesSize: true,
        );
        if (next == null) break;
      }
      child = next;
      index++;
    }
    final lastLaidOut = child;
    final endOffset = offset;

    var trailingGarbage = 0;
    for (var c = childAfter(lastLaidOut); c != null; c = childAfter(c)) {
      trailingGarbage++;
    }
    if (trailingGarbage > 0) collectGarbage(0, trailingGarbage);

    final jumpCorrection = _jumpTargetCorrection(scrollOffset);
    if (_requestCorrection(
      scrollOffset,
      jumpCorrection ?? correction,
      isJump: jumpCorrection != null,
    )) {
      return;
    }

    final startOffset = childScrollOffset(firstChild!)!;
    final paintExtent = calculatePaintOffset(
      constraints,
      from: startOffset,
      to: endOffset,
    );
    final cacheExtent = calculateCacheOffset(
      constraints,
      from: startOffset,
      to: endOffset,
    );
    final scrollExtent = _extents.total;
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: scrollExtent,
      hasVisualOverflow:
          endOffset > scrollOffset + constraints.remainingPaintExtent ||
          scrollOffset > 0.0,
    );
    _didCompleteLayout(scrollOffset);
  }

  /// Applies corrections known before laying out any child: from key changes
  /// and from the initial position.
  bool _applyEarlyCorrection(double scrollOffset) {
    final correction = _pendingCorrection;
    _pendingCorrection = 0;
    final target = _jumpTarget;
    if (target != null && _jumpNeedsInitialCorrection) {
      _jumpNeedsInitialCorrection = false;
      if (target.index >= _extents.length) {
        _jumpTarget = null;
      } else {
        return _requestCorrection(
          scrollOffset,
          _clampToContent(_alignedOffset(target)) -
              _unclampedScrollOffset(scrollOffset),
          isJump: true,
        );
      }
    }
    return _requestCorrection(scrollOffset, correction);
  }

  /// Correction needed to put the jump target at its alignment, using the
  /// extents measured in this pass. `null` when there is no jump in progress.
  double? _jumpTargetCorrection(double scrollOffset) {
    final target = _jumpTarget;
    if (target == null) return null;
    if (target.index >= _extents.length) {
      _jumpTarget = null;
      return null;
    }
    final correction =
        _clampToContent(_alignedOffset(target)) -
        _unclampedScrollOffset(scrollOffset);
    final isLaidOut =
        target.index >= indexOf(firstChild!) &&
        target.index <= indexOf(lastChild!);
    _jumpRefinements++;
    if ((isLaidOut && correction.abs() <= _kCorrectionTolerance) ||
        _jumpRefinements >= _kMaxJumpRefinements) {
      _jumpTarget = null;
    }
    return correction;
  }

  /// A jump's [correction] is already kept within the scrollable content
  /// ([_clampToContent]), other ones within this sliver.
  bool _requestCorrection(
    double scrollOffset,
    double correction, {
    bool isJump = false,
  }) {
    var c = correction;
    if (!isJump && scrollOffset + c < 0) c = -scrollOffset;
    if (c.abs() <= _kCorrectionTolerance) return false;
    if (_consecutiveCorrections >= _kMaxConsecutiveCorrections) return false;
    _consecutiveCorrections++;
    geometry = SliverGeometry(scrollOffsetCorrection: c);
    return true;
  }

  void _didCompleteLayout(double scrollOffset) {
    _hasLaidOut = true;
    _changedRanges = null;
    // Finished resizes of items that weren't laid out.
    if (_resizes.isNotEmpty) _resizes.removeWhere((_, r) => !r.isRunning);
    _consecutiveCorrections = 0;
    _lastScrollOffset = scrollOffset;
    _lastPaintExtent = constraints.remainingPaintExtent;
    _lastScrollExtent = geometry!.scrollExtent;
    _anchorIndex = _anchorIndexFor(scrollOffset);
    _updateVisibleRange(scrollOffset);
  }

  void _removeAllChildren() {
    var count = 0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      count++;
    }
    if (count > 0) collectGarbage(count, 0);
  }

  // ---------------------------------------------------------------------------
  // Offsets and navigation

  /// Sliver-local scroll offset that puts [target] at its alignment within
  /// the part of the viewport not covered by [obscuredInsets] and pinned
  /// headers.
  double _alignedOffset(_JumpTarget target) {
    final obscured = _obscuredExtents;
    final leading = obscured.leading + _pinnedExtentBefore;
    final visible =
        constraints.viewportMainAxisExtent - leading - obscured.trailing;
    final extent = _extents[target.index];
    return _extents.offsetOf(target.index) -
        leading -
        target.alignment * (visible - extent);
  }

  /// Extent of the pinned headers before this sliver, the way the viewport
  /// reveals its children ([RenderViewportBase.getOffsetToReveal]): it
  /// doesn't depend on the scroll position.
  double get _pinnedExtentBefore {
    if (constraints.growthDirection != GrowthDirection.forward) return 0;
    RenderObject child = this;
    var parent = child.parent;
    while (parent != null && parent is! RenderViewportBase) {
      child = parent;
      parent = parent.parent;
    }
    if (parent is! RenderViewportBase) return 0;
    // As in `RenderViewportBase.maxScrollObstructionExtentBefore`.
    var extent = 0.0;
    for (
      var sliver = parent is RenderViewport ? parent.center : parent.firstChild;
      sliver != null && sliver != child;
      sliver = parent.childAfter(sliver)
    ) {
      extent += sliver.geometry?.maxScrollObstructionExtent ?? 0;
    }
    return extent;
  }

  /// [obscuredInsets] at the viewport's leading and trailing edges.
  ({double leading, double trailing}) get _obscuredExtents {
    final insets = _obscuredInsets;
    return switch (constraints.axisDirection) {
      AxisDirection.down => (leading: insets.top, trailing: insets.bottom),
      AxisDirection.up => (leading: insets.bottom, trailing: insets.top),
      AxisDirection.right => (leading: insets.left, trailing: insets.right),
      AxisDirection.left => (leading: insets.right, trailing: insets.left),
    };
  }

  /// Sliver-local offsets of the painted part of this sliver that isn't
  /// covered by [obscuredInsets] or pinned headers.
  ({double start, double end}) _visibleArea(double scrollOffset) {
    var start = scrollOffset + math.max(0, constraints.overlap);
    var end = scrollOffset + constraints.remainingPaintExtent;
    final obscured = _obscuredExtents;
    if (obscured.leading > 0 || obscured.trailing > 0) {
      final viewportStart = _unclampedScrollOffset(scrollOffset);
      start = math.max(start, viewportStart + obscured.leading);
      end = math.min(
        end,
        viewportStart + constraints.viewportMainAxisExtent - obscured.trailing,
      );
    }
    return (start: start, end: end);
  }

  /// Keeps a sliver-local scroll offset within the scrollable content,
  /// including other slivers before and after this one.
  double _clampToContent(double offset) {
    final viewportExtent = constraints.viewportMainAxisExtent;
    final position = _scrollPosition;
    if (position == null ||
        constraints.growthDirection != GrowthDirection.forward) {
      return offset.clamp(
        0.0,
        math.max<double>(0, _extents.total - viewportExtent),
      );
    }
    final preceding = constraints.precedingScrollExtent;
    if (!position.hasContentDimensions) {
      // First layout: what follows this sliver is unknown yet.
      return offset.clamp(
        -preceding,
        math.max<double>(-preceding, _extents.total - viewportExtent),
      );
    }
    final min = position.minScrollExtent - preceding;
    // Content after this sliver, as of the viewport's last layout.
    final following = math.max<double>(
      0,
      position.maxScrollExtent + viewportExtent - preceding - _lastScrollExtent,
    );
    final max = _extents.total + following - viewportExtent;
    return offset.clamp(min, math.max(min, max));
  }

  /// [scrollOffset] without the clamp to zero: negative while this sliver
  /// starts inside the viewport.
  double _unclampedScrollOffset(double scrollOffset) {
    if (scrollOffset > 0 ||
        constraints.growthDirection != GrowthDirection.forward) {
      return scrollOffset;
    }
    final position = _scrollPosition;
    if (position == null || !position.hasPixels) return scrollOffset;
    return math.min(0, position.pixels - constraints.precedingScrollExtent);
  }

  ScrollPosition? get _scrollPosition {
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderViewportBase) return null;
    final offset = viewport.offset;
    return offset is ScrollPosition ? offset : null;
  }

  /// Scroll position (in the viewport's coordinates) that puts [target] at
  /// its alignment, or `null` if the list hasn't been laid out yet.
  double? _scrollPositionFor(_JumpTarget target, ScrollPosition position) {
    if (!_hasLaidOut || target.index >= _extents.length) return null;
    final offset = constraints.precedingScrollExtent + _alignedOffset(target);
    if (!position.hasContentDimensions) return math.max(0, offset);
    return offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Display index of the item at [itemIndex] (removed items that are
  /// animating out have display indices but no item index).
  int _displayIndexOf(int itemIndex) {
    var index = itemIndex;
    for (final removed in _removedIndices) {
      if (removed > index) break;
      index++;
    }
    return index;
  }

  int _itemIndexOf(int displayIndex) =>
      displayIndex - _countBelow(_removedIndices, displayIndex);

  bool _isRemoved(int displayIndex) =>
      _removedIndices.isNotEmpty && _contains(_removedIndices, displayIndex);

  void jumpToIndex(int itemIndex, double alignment) {
    if (itemIndex < 0 || itemIndex >= itemCount) return;
    _jumpToDisplayIndex(_displayIndexOf(itemIndex), alignment);
  }

  void _jumpToDisplayIndex(int index, double alignment) {
    final target = (index: index, alignment: alignment);
    _jumpTarget = target;
    _jumpRefinements = 0;

    final position = _scrollPosition;
    final pixels = position == null
        ? null
        : _scrollPositionFor(target, position);
    if (position == null || pixels == null) {
      // Not laid out yet: land on the first layout.
      _jumpNeedsInitialCorrection = true;
    } else {
      position.jumpTo(pixels);
    }
    markNeedsLayout();
  }

  Future<void> animateToIndex(
    int? Function() resolveItemIndex, {
    required double alignment,
    required Duration duration,
    required Curve curve,
  }) async {
    int? resolveIndex() {
      final itemIndex = resolveItemIndex();
      if (itemIndex == null || itemIndex < 0 || itemIndex >= itemCount) {
        return null;
      }
      return _displayIndexOf(itemIndex);
    }

    final position = _scrollPosition;
    final index = resolveIndex();
    if (index == null) return;
    if (position == null ||
        !_hasLaidOut ||
        duration == Duration.zero ||
        position is! ScrollActivityDelegate) {
      _jumpToDisplayIndex(index, alignment);
      return;
    }

    double? target() {
      final index = resolveIndex();
      if (!attached || index == null) return null;
      return _scrollPositionFor((index: index, alignment: alignment), position);
    }

    if (target() == null) return;

    final activity = _ScrollToItemActivity(
      position,
      target: target,
      duration: duration,
      curve: curve,
      vsync: position.context.vsync,
    );
    position.beginActivity(activity);
    await activity.done;

    // Land precisely once the animation wasn't interrupted.
    final finalIndex = resolveIndex();
    if (activity.completed && attached && finalIndex != null) {
      _jumpTarget = (index: finalIndex, alignment: alignment);
      _jumpRefinements = 0;
      markNeedsLayout();
    }
  }

  // ---------------------------------------------------------------------------
  // Queries

  // Queries take and return item indices, which skip removed items that
  // are animating out.

  int get itemCount => _extents.length - _removedIndices.length;

  double get totalExtent => _extents.total;

  double? extentOf(int itemIndex) => itemIndex >= 0 && itemIndex < itemCount
      ? _extents[_displayIndexOf(itemIndex)]
      : null;

  bool isMeasured(int itemIndex) =>
      itemIndex >= 0 &&
      itemIndex < itemCount &&
      _extents.isMeasured(_displayIndexOf(itemIndex));

  int? indexOfKey(Object key) {
    final map = _keyIndex ??= () {
      final map = HashMap<Object, int>();
      for (var i = 0; i < _keys.length; i++) {
        map[_keys[i]] = i;
      }
      return map;
    }();
    final index = map[key];
    if (index == null || _isRemoved(index)) return null;
    return _itemIndexOf(index);
  }

  /// Display indices of the visible items, removed ones included.
  PuskVisibleRange? get visibleDisplayRange {
    final first = _firstVisibleIndex;
    final last = _lastVisibleIndex;
    if (first == null || last == null) return null;
    return (first: first, last: last);
  }

  void _updateVisibleRange(double scrollOffset) {
    int? first;
    int? last;
    int? firstItem;
    int? lastItem;
    final area = _visibleArea(scrollOffset);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      final start = childScrollOffset(child)!;
      final end = start + _extents[index];
      if (start >= area.end) break;
      // `start >= area.start`: an item that is just starting to grow
      // (zero extent) at the leading edge is visible too.
      if (end > area.start || start >= area.start) {
        first ??= index;
        last = index;
        if (!_isRemoved(index)) {
          firstItem ??= _itemIndexOf(index);
          lastItem = _itemIndexOf(index);
        }
      }
    }
    _firstVisibleIndex = first;
    _lastVisibleIndex = last;
    _visibleRange = firstItem == null || lastItem == null
        ? null
        : (first: firstItem, last: lastItem);

    final controller = _controller;
    if (controller != null && controller._visibleRange.value != _visibleRange) {
      controller._publishVisibleRange();
    }
  }

  List<PuskItemPosition> get visibleItems {
    if (!_hasLaidOut || firstChild == null) return const [];
    final viewportExtent = constraints.viewportMainAxisExtent;
    if (viewportExtent <= 0) return const [];
    final scrollOffset = constraints.scrollOffset;
    // Where this sliver's scroll offset 0 sits when slivers before it are
    // still visible.
    final origin = viewportExtent - constraints.remainingPaintExtent;
    final area = _visibleArea(scrollOffset);
    // Edges are relative to the part of the viewport jumps align within.
    final obscured = _obscuredExtents;
    final leading = obscured.leading + _pinnedExtentBefore;
    final extent = viewportExtent - leading - obscured.trailing;
    if (extent <= 0) return const [];

    final items = <PuskItemPosition>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      final start = childScrollOffset(child)!;
      final end = start + _extents[index];
      if (start >= area.end) break;
      if (end <= area.start || _isRemoved(index)) continue;
      items.add(
        PuskItemPosition(
          index: _itemIndexOf(index),
          key: _keys[index],
          leadingEdge: (origin + start - scrollOffset - leading) / extent,
          trailingEdge: (origin + end - scrollOffset - leading) / extent,
        ),
      );
    }
    return items;
  }

  // ---------------------------------------------------------------------------
  // Painting and hit testing
  //
  // An item whose extent animates is laid out at full size and takes a
  // different room: it is shifted so that its trailing edge follows the
  // trailing edge of its room (it slides in from the leading edge), or for a
  // resize pinned to the leading edge, its leading edge. It isn't clipped.

  @override
  double? childScrollOffset(covariant RenderObject child) =>
      (child.parentData! as SliverMultiBoxAdaptorParentData).layoutOffset;

  _ItemAnimation? _animationOfChild(RenderBox child) =>
      _animations.isEmpty ? null : _animations[_keys[indexOf(child)]];

  bool _isAnimating(RenderBox child) =>
      _animationOfChild(child) != null ||
      (_resizes.isNotEmpty && _resizes.containsKey(_keys[indexOf(child)]));

  @override
  double childMainAxisPosition(RenderBox child) {
    final position = childScrollOffset(child)! - constraints.scrollOffset;
    if (_animations.isEmpty && _resizes.isEmpty) return position;
    final index = indexOf(child);
    final resize = _resizes[_keys[index]];
    if (resize != null && resize.pinLeading) return position;
    if (resize == null && _animations[_keys[index]] == null) return position;
    return position + _extents[index] - _extentOf(child);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;
    if (_animations.isEmpty && _resizes.isEmpty) {
      super.paint(context, offset);
      return;
    }
    // Same as the superclass, but animated items are faded, and painted
    // first: an item that doesn't fit its slot yet sticks out towards the
    // leading edge, under its neighbour (or past the viewport's edge), with
    // no clip of its own.
    final Offset mainAxisUnit;
    final Offset crossAxisUnit;
    final Offset originOffset;
    final bool reversed;
    switch (applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    )) {
      case AxisDirection.up:
        mainAxisUnit = const Offset(0, -1);
        crossAxisUnit = const Offset(1, 0);
        originOffset = offset + Offset(0, geometry!.paintExtent);
        reversed = true;
      case AxisDirection.right:
        mainAxisUnit = const Offset(1, 0);
        crossAxisUnit = const Offset(0, 1);
        originOffset = offset;
        reversed = false;
      case AxisDirection.down:
        mainAxisUnit = const Offset(0, 1);
        crossAxisUnit = const Offset(1, 0);
        originOffset = offset;
        reversed = false;
      case AxisDirection.left:
        mainAxisUnit = const Offset(-1, 0);
        crossAxisUnit = const Offset(0, 1);
        originOffset = offset + Offset(geometry!.paintExtent, 0);
        reversed = true;
    }
    for (final animated in const [true, false]) {
      for (var child = firstChild; child != null; child = childAfter(child)) {
        final index = indexOf(child);
        final key = _keys[index];
        final animation = _animations[key];
        if ((animation != null || _resizes.containsKey(key)) != animated) {
          continue;
        }
        final mainAxisDelta = childMainAxisPosition(child);
        final extent = paintExtentOf(child);
        if (mainAxisDelta >= constraints.remainingPaintExtent ||
            mainAxisDelta + extent <= 0) {
          continue;
        }
        final crossAxisDelta = childCrossAxisPosition(child);
        var childOffset =
            originOffset +
            mainAxisUnit * mainAxisDelta +
            crossAxisUnit * crossAxisDelta;
        if (reversed) childOffset += mainAxisUnit * extent;
        if (animation == null) {
          context.paintChild(child, childOffset);
        } else {
          _paintAnimatedChild(context, child, childOffset, animation);
        }
      }
    }
  }

  void _paintAnimatedChild(
    PaintingContext context,
    RenderBox child,
    Offset offset,
    _ItemAnimation animation,
  ) {
    final transition = _transition;
    var opacity = 1.0;
    if (transition != null && transition.fade) {
      final start = transition.fadeStart;
      opacity = ((animation.value - start) / (1 - start)).clamp(0.0, 1.0);
    }
    final alpha = (opacity * 255).round();
    if (alpha == 0) {
      animation.opacityLayer.layer = null;
    } else if (alpha == 255) {
      animation.opacityLayer.layer = null;
      context.paintChild(child, offset);
    } else {
      animation.opacityLayer.layer = context.pushOpacity(
        offset,
        alpha,
        (context, offset) => context.paintChild(child, offset),
        oldLayer: animation.opacityLayer.layer,
      );
    }
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    if (_animations.isEmpty && _resizes.isEmpty) {
      return super.hitTestChildren(
        result,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      );
    }
    final boxResult = BoxHitTestResult.wrap(result);
    for (var child = lastChild; child != null; child = childBefore(child)) {
      if (_isAnimating(child)) {
        // Items that are going away can't be interacted with.
        if (_animationOfChild(child)?.isRemoving ?? false) continue;
        final slotStart = childScrollOffset(child)! - constraints.scrollOffset;
        final slotEnd = slotStart + _extents[indexOf(child)];
        if (mainAxisPosition < slotStart || mainAxisPosition >= slotEnd) {
          continue;
        }
      }
      if (hitTestBoxChild(
        boxResult,
        child,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_removedIndices.isEmpty) {
      super.visitChildrenForSemantics(visitor);
      return;
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (!_isRemoved(indexOf(child))) visitor(child);
    }
  }
}
