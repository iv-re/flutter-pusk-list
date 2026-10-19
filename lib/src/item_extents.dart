import 'dart:typed_data';

/// Item extents backed by a Fenwick tree.
///
/// Gives O(log N) offset of an item, item at an offset and single extent
/// updates. Structural changes (insert/remove/replace a range) are O(N).
class ItemExtents {
  Float64List _values = Float64List(0);
  Uint8List _measured = Uint8List(0);

  /// 1-based Fenwick tree over [_values].
  Float64List _tree = Float64List(1);
  int _length = 0;

  int get length => _length;

  @pragma('vm:prefer-inline')
  double operator [](int index) => _values[index];

  /// Whether the extent at [index] was measured by laying out the item
  /// (as opposed to estimated).
  @pragma('vm:prefer-inline')
  bool isMeasured(int index) => _measured[index] != 0;

  /// Sum of all extents.
  double get total => offsetOf(_length);

  /// Replaces all extents with [values], all marked as estimated.
  void reset(Float64List values) {
    _ensureCapacity(values.length);
    _length = values.length;
    _values.setRange(0, _length, values);
    _measured.fillRange(0, _length, 0);
    _rebuildTree();
  }

  /// Stores a measured extent for [index].
  void setMeasured(int index, double extent) {
    _measured[index] = 1;
    setExtent(index, extent);
  }

  /// Changes the extent at [index], keeping whether it counts as measured.
  void setExtent(int index, double extent) {
    final delta = extent - _values[index];
    if (delta == 0) return;
    _values[index] = extent;
    for (var i = index + 1; i <= _length; i += i & -i) {
      _tree[i] += delta;
    }
  }

  /// Replaces `removeCount` items starting at [start] with [values].
  void replaceRange(
    int start,
    int removeCount,
    Float64List values,
    Uint8List measured,
  ) {
    final insertCount = values.length;
    final newLength = _length - removeCount + insertCount;
    final tailStart = start + removeCount;

    if (insertCount != removeCount) {
      if (newLength > _values.length) {
        // Grow and move the tail in one copy.
        final newValues = Float64List(_grownCapacity(newLength))
          ..setRange(0, start, _values);
        final newMeasured = Uint8List(newValues.length)
          ..setRange(0, start, _measured);
        newValues.setRange(start + insertCount, newLength, _values, tailStart);
        newMeasured.setRange(
          start + insertCount,
          newLength,
          _measured,
          tailStart,
        );
        _values = newValues;
        _measured = newMeasured;
        _tree = Float64List(newValues.length + 1);
      } else {
        // setRange handles overlapping ranges within the same list.
        _values.setRange(start + insertCount, newLength, _values, tailStart);
        _measured.setRange(
          start + insertCount,
          newLength,
          _measured,
          tailStart,
        );
      }
    }

    _values.setRange(start, start + insertCount, values);
    _measured.setRange(start, start + insertCount, measured);
    _length = newLength;
    _rebuildTree();
  }

  /// Re-estimates every item that hasn't been measured yet.
  void reestimate(double Function(int index) estimate) {
    for (var i = 0; i < _length; i++) {
      if (_measured[i] == 0) _values[i] = estimate(i);
    }
    _rebuildTree();
  }

  /// Leading offset of the item at [index] (sum of extents before it).
  ///
  /// `offsetOf(length)` is the total extent.
  double offsetOf(int index) {
    var sum = 0.0;
    for (var i = index < _length ? index : _length; i > 0; i -= i & -i) {
      sum += _tree[i];
    }
    return sum;
  }

  /// Index of the item that contains [offset], clamped to `[0, length - 1]`.
  ///
  /// An offset exactly on the boundary between two items resolves to the
  /// later one.
  int indexAt(double offset) {
    if (_length == 0 || offset <= 0) return 0;
    var pos = 0;
    var remaining = offset;
    for (var step = 1 << (_length.bitLength - 1); step > 0; step >>= 1) {
      final next = pos + step;
      if (next <= _length && _tree[next] <= remaining) {
        pos = next;
        remaining -= _tree[next];
      }
    }
    return pos < _length ? pos : _length - 1;
  }

  void _ensureCapacity(int capacity) {
    if (capacity <= _values.length) return;
    final newCapacity = _grownCapacity(capacity);
    _values = Float64List(newCapacity)..setRange(0, _length, _values);
    _measured = Uint8List(newCapacity)..setRange(0, _length, _measured);
    _tree = Float64List(newCapacity + 1);
  }

  int _grownCapacity(int required) {
    var capacity = _values.length < 16 ? 16 : _values.length;
    while (capacity < required) {
      capacity *= 2;
    }
    return capacity;
  }

  void _rebuildTree() {
    final n = _length;
    final tree = _tree;
    tree.setRange(1, n + 1, _values);
    for (var i = 1; i <= n; i++) {
      final parent = i + (i & -i);
      if (parent <= n) tree[parent] += tree[i];
    }
  }
}
