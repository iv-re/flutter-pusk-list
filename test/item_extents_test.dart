import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusk_list/src/item_extents.dart';
import 'package:pusk_list/src/keys_diff.dart';

void main() {
  group('ItemExtents', () {
    test('matches a naive model under random operations', () {
      final random = Random(42);
      final extents = ItemExtents();
      final model = <double>[];

      double next() => (random.nextInt(200) + 1).toDouble();

      extents.reset(Float64List.fromList(List.generate(50, (_) => next())));
      model.addAll(List.generate(50, (i) => extents[i]));

      for (var step = 0; step < 2000; step++) {
        switch (random.nextInt(3)) {
          case 0 when model.isNotEmpty:
            final i = random.nextInt(model.length);
            final v = next();
            extents.setMeasured(i, v);
            model[i] = v;
          case _:
            final start = random.nextInt(model.length + 1);
            final remove = random.nextInt(min(5, model.length - start) + 1);
            final insert = List.generate(random.nextInt(6), (_) => next());
            extents.replaceRange(
              start,
              remove,
              Float64List.fromList(insert),
              Uint8List(insert.length),
            );
            model.replaceRange(start, start + remove, insert);
        }

        expect(extents.length, model.length);
        var sum = 0.0;
        for (var i = 0; i < model.length; i++) {
          expect(extents[i], model[i]);
          expect(extents.offsetOf(i), closeTo(sum, 1e-6));
          sum += model[i];
        }
        expect(extents.total, closeTo(sum, 1e-6));
      }
    });

    test('indexAt resolves boundaries to the later item', () {
      final extents = ItemExtents()..reset(Float64List.fromList([10, 20, 30]));
      expect(extents.indexAt(-5), 0);
      expect(extents.indexAt(0), 0);
      expect(extents.indexAt(9.9), 0);
      expect(extents.indexAt(10), 1);
      expect(extents.indexAt(29.9), 1);
      expect(extents.indexAt(30), 2);
      expect(extents.indexAt(1000), 2);
    });

    test('replaceRange keeps measured flags of untouched items', () {
      final extents = ItemExtents()
        ..reset(Float64List.fromList([10, 20, 30]))
        ..setMeasured(2, 35);
      extents.replaceRange(0, 1, Float64List.fromList([1, 2]), Uint8List(2));
      expect(extents.length, 4);
      expect(extents.isMeasured(3), isTrue);
      expect(extents[3], 35);
      expect(extents.isMeasured(0), isFalse);
    });
  });

  group('KeysDiff', () {
    KeysDiff? diff(List<Object> from, List<Object> to) =>
        KeysDiff.compute(from, to.length, (i) => to[i]);

    test('returns null when nothing changed', () {
      expect(diff(['a', 'b'], ['a', 'b']), isNull);
    });

    test('between lists matches compute', () {
      final random = Random(7);
      for (var round = 0; round < 200; round++) {
        final from = [for (var i = 0; i < random.nextInt(20); i++) i];
        final to = List.of(from);
        if (to.isNotEmpty && random.nextBool()) {
          to.removeAt(random.nextInt(to.length));
        }
        if (random.nextBool()) to.insert(random.nextInt(to.length + 1), -1);
        final a = diff(from, to);
        final b = KeysDiff.between(from, to);
        expect(b == null, a == null);
        if (a == null || b == null) continue;
        expect((b.start, b.oldEnd, b.newEnd), (a.start, a.oldEnd, a.newEnd));
      }
    });

    test('finds an insertion at the start', () {
      final d = diff(['a', 'b'], ['x', 'y', 'a', 'b'])!;
      expect((d.start, d.oldEnd, d.newEnd), (0, 0, 2));
      expect(d.newIndexOf(0), 2);
      expect(d.newIndexOf(1), 3);
    });

    test('finds a removal in the middle', () {
      final d = diff(['a', 'b', 'c', 'd'], ['a', 'd'])!;
      expect((d.start, d.oldEnd, d.newEnd), (1, 3, 1));
      expect(d.newIndexOf(1), isNull);
      expect(d.newIndexOf(3), 1);
    });

    test('matches moved keys inside the block', () {
      final d = diff(['a', 'b', 'c', 'd'], ['c', 'b', 'a', 'x'])!;
      expect(d.newIndexOf(0), 2);
      expect(d.newIndexOf(2), 0);
      expect(d.newIndexOf(3), isNull);
    });

    test('rejects duplicate keys', () {
      expect(
        () => KeysDiff.initial(2, (_) => 'same'),
        throwsA(isA<FlutterError>()),
      );
    });
  });
}
