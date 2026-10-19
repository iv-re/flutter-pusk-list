import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Builds the key of the item at `index`.
typedef PuskItemKeyBuilder = Object Function(int index);

/// Difference between two key lists, expressed as a single replaced block:
/// `oldKeys[start, oldEnd)` became `newKeys[start, newEnd)`, everything before
/// [start] and after the block is unchanged.
///
/// Inserts, removals and replacements in one place are found exactly. Changes
/// in several places collapse into one bigger block, which is still correct
/// (keys inside the block are matched by a map), just less cheap.
class KeysDiff {
  KeysDiff._(this.oldKeys, this.newKeys, this.start, this.oldEnd, this.newEnd);

  factory KeysDiff._withPrefix(
    List<Object> oldKeys,
    List<Object> newKeys,
    int prefix,
  ) {
    assert(_debugCheckUniqueKeys(newKeys));
    final oldLen = oldKeys.length;
    final newCount = newKeys.length;
    final minLen = oldLen < newCount ? oldLen : newCount;

    var suffix = 0;
    final maxSuffix = minLen - prefix;
    while (suffix < maxSuffix &&
        oldKeys[oldLen - 1 - suffix] == newKeys[newCount - 1 - suffix]) {
      suffix++;
    }

    return KeysDiff._(
      oldKeys,
      newKeys,
      prefix,
      oldLen - suffix,
      newCount - suffix,
    );
  }

  final List<Object> oldKeys;
  final List<Object> newKeys;
  final int start;
  final int oldEnd;
  final int newEnd;

  int get delta => newKeys.length - oldKeys.length;

  Map<Object, int>? _oldBlockIndex;
  Map<Object, int>? _newBlockIndex;

  /// Returns `null` if the keys did not change.
  static KeysDiff? compute(
    List<Object> oldKeys,
    int newCount,
    PuskItemKeyBuilder itemKey,
  ) {
    final oldLen = oldKeys.length;
    final minLen = oldLen < newCount ? oldLen : newCount;

    var prefix = 0;
    while (prefix < minLen && oldKeys[prefix] == itemKey(prefix)) {
      prefix++;
    }
    if (prefix == oldLen && prefix == newCount) return null;

    final newKeys = List<Object>.generate(
      newCount,
      (i) => i < prefix ? oldKeys[i] : itemKey(i),
      growable: false,
    );
    return KeysDiff._withPrefix(oldKeys, newKeys, prefix);
  }

  /// Like [compute], with the new keys already in a list (which the diff
  /// takes over: it must not be modified afterwards).
  static KeysDiff? between(List<Object> oldKeys, List<Object> newKeys) {
    final oldLen = oldKeys.length;
    final newCount = newKeys.length;
    final minLen = oldLen < newCount ? oldLen : newCount;
    var prefix = 0;
    while (prefix < minLen && oldKeys[prefix] == newKeys[prefix]) {
      prefix++;
    }
    if (prefix == oldLen && prefix == newCount) return null;
    return KeysDiff._withPrefix(oldKeys, newKeys, prefix);
  }

  static List<Object> initial(int count, PuskItemKeyBuilder itemKey) {
    final keys = List<Object>.generate(count, itemKey, growable: false);
    assert(_debugCheckUniqueKeys(keys));
    return keys;
  }

  /// Old index of [key] if it was inside the replaced block.
  int? oldBlockIndexOf(Object key) {
    if (oldEnd == start) return null;
    final map = _oldBlockIndex ??= _indexBlock(oldKeys, start, oldEnd);
    return map[key];
  }

  /// New index of [key] if it is inside the replaced block.
  int? newBlockIndexOf(Object key) {
    if (newEnd == start) return null;
    final map = _newBlockIndex ??= _indexBlock(newKeys, start, newEnd);
    return map[key];
  }

  /// Where the item at [oldIndex] ended up, or `null` if it was removed.
  int? newIndexOf(int oldIndex) {
    if (oldIndex < start) return oldIndex;
    if (oldIndex >= oldEnd) return oldIndex + delta;
    return newBlockIndexOf(oldKeys[oldIndex]);
  }

  static Map<Object, int> _indexBlock(List<Object> keys, int from, int to) {
    final map = HashMap<Object, int>();
    for (var i = from; i < to; i++) {
      map[keys[i]] = i;
    }
    return map;
  }

  static bool _debugCheckUniqueKeys(List<Object> keys) {
    final seen = HashSet<Object>();
    for (final key in keys) {
      if (!seen.add(key)) {
        throw FlutterError(
          'PuskSliverList: duplicate item key "$key".\n'
          'Every item must have a unique key.',
        );
      }
    }
    return true;
  }
}
