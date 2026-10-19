import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusk_list/pusk_list.dart';

void main() {
  setUp(() {
    _createdTiles = 0;
    _createdById.clear();
    _builds.clear();
  });

  group('PuskSliverList', () {
    testWidgets('builds only items around the viewport', (tester) async {
      await tester.pumpWidget(_Harness(items: _items(10000)));
      // 600px viewport + 250px cache, 50px items.
      expect(_createdTiles, lessThan(20));
      expect(_rect(tester, 'item-0').top, 0);
      expect(_rect(tester, 'item-11').bottom, 600);
    });

    testWidgets('keeps item states when items are inserted above', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(key: harness, items: _items(100), controller: controller),
      );
      controller.jumpToIndex(20);
      await tester.pump();
      expect(_rect(tester, 'item-20').top, 0);

      final created = _createdTiles;
      harness.currentState!.update(
        (items) => items.insertAll(0, _items(5, prefix: 'new')),
      );
      await tester.pump();

      expect(_createdTiles, created, reason: 'no tile should be recreated');
      expect(_rect(tester, 'item-20').top, 0);
    });

    testWidgets('shows items inserted at the start edge', (tester) async {
      final harness = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: harness, items: _items(100)));

      final created = _createdTiles;
      harness.currentState!.update(
        (items) => items.insertAll(0, _items(2, prefix: 'new')),
      );
      await tester.pump();

      expect(_rect(tester, 'new-0').top, 0);
      expect(_rect(tester, 'item-0').top, 100);
      expect(_createdTiles, created + 2);
    });

    testWidgets('anchors on removals above and of the first visible item', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(key: harness, items: _items(100), controller: controller),
      );
      controller.jumpToIndex(20);
      await tester.pump();

      harness.currentState!.update((items) => items.removeRange(0, 5));
      await tester.pump();
      expect(_rect(tester, 'item-20').top, 0);

      harness.currentState!.update(
        (items) => items.removeWhere((item) => item.id == 'item-20'),
      );
      await tester.pump();
      expect(_rect(tester, 'item-21').top, 50);
    });

    testWidgets('anchors when an item above the viewport grows', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(key: harness, items: _items(100), controller: controller),
      );
      controller.jumpToIndex(20);
      await tester.pump();

      // item-19 is in the cache area above the viewport.
      harness.currentState!.update((items) => items[19].height = 120);
      await tester.pump();
      expect(_rect(tester, 'item-20').top, 0);
    });

    testWidgets('scrolls through unmeasured items without jumps', (
      tester,
    ) async {
      final controller = PuskListController();
      final scrollController = ScrollController();
      await tester.pumpWidget(
        _Harness(
          items: _items(1000, height: (i) => 20.0 + (i * 37) % 130),
          controller: controller,
          scrollController: scrollController,
        ),
      );
      controller.jumpToIndex(500);
      await tester.pump();

      for (var step = 0; step < 60; step++) {
        final visible = controller.visibleItems;
        final probe = 'item-${visible[visible.length ~/ 2].index}';
        final before = _rect(tester, probe).top;

        scrollController.jumpTo(scrollController.offset - 40);
        await tester.pump();

        expect(_rect(tester, probe).top, moreOrLessEquals(before + 40));
      }
    });

    testWidgets('jumps precisely with every alignment', (tester) async {
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          items: _items(1000, height: (i) => 20.0 + (i * 37) % 130),
          controller: controller,
        ),
      );

      controller.jumpToIndex(700);
      await tester.pump();
      expect(_rect(tester, 'item-700').top, moreOrLessEquals(0));

      controller.jumpToIndex(300, alignment: 0.5);
      await tester.pump();
      expect(_rect(tester, 'item-300').center.dy, moreOrLessEquals(300));

      controller.jumpToIndex(900, alignment: 1);
      await tester.pump();
      expect(_rect(tester, 'item-900').bottom, moreOrLessEquals(600));
    });

    testWidgets('lands on the initial position in the first frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(
          items: _items(1000, height: (i) => 20.0 + (i * 37) % 130),
          initialPosition: const PuskPosition(index: 400, alignment: 0.5),
        ),
      );
      expect(_rect(tester, 'item-400').center.dy, moreOrLessEquals(300));
    });

    testWidgets('animates to a key while items are inserted above it', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(1000, height: (i) => 20.0 + (i * 37) % 130),
          controller: controller,
        ),
      );

      final done = controller.animateToKey(
        'item-400',
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      await tester.pump(const Duration(milliseconds: 100));
      harness.currentState!.update(
        (items) => items.insertAll(0, _items(10, prefix: 'new')),
      );
      await tester.pumpAndSettle();
      await done;

      expect(_rect(tester, 'item-400').top, moreOrLessEquals(0));
    });

    testWidgets('animates to a far item smoothly, without jumps', (
      tester,
    ) async {
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          // Mostly smaller than the 100px estimate, so the target moves
          // closer while the items on the way get measured.
          items: _items(5000, height: (i) => 20.0 + (i * 37) % 130),
          controller: controller,
        ),
      );
      unawaited(
        controller.animateToIndex(
          3000,
          duration: const Duration(milliseconds: 600),
          curve: Curves.linear,
        ),
      );
      final firsts = <int>[];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        firsts.add(controller.visibleItems.first.index);
      }
      await tester.pumpAndSettle();
      expect(controller.visibleItems.first.index, 3000);
      for (var i = 1; i < firsts.length; i++) {
        expect(firsts[i], greaterThanOrEqualTo(firsts[i - 1]), reason: '$i');
        // ~38 frames for 3000 items: about 80 items per frame.
        expect(firsts[i] - firsts[i - 1], lessThan(200), reason: '$i');
      }
      expect(firsts.first, lessThan(200));
    });

    testWidgets('reports the visible range', (tester) async {
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(items: _items(1000), controller: controller),
      );
      await tester.pump();
      expect(controller.visibleRange.value, (first: 0, last: 11));

      controller.jumpToIndex(100);
      await tester.pump();
      await tester.pump();
      expect(controller.visibleRange.value, (first: 100, last: 111));
    });

    testWidgets('works as a reversed chat', (tester) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          controller: controller,
          reverse: true,
        ),
      );
      expect(_rect(tester, 'item-0').bottom, 600);

      // At the bottom: a new message shows up.
      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-0', 70)),
      );
      await tester.pump();
      expect(_rect(tester, 'new-0').bottom, 600);

      // Scrolled up: the screen stays put.
      controller.jumpToIndex(30);
      await tester.pump();
      final before = _rect(tester, 'item-30');
      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-1', 70)),
      );
      await tester.pump();
      expect(_rect(tester, 'item-30'), before);
    });

    testWidgets('a growing bottom message pushes content only at the edge', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final scrollController = ScrollController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          scrollController: scrollController,
          reverse: true,
        ),
      );

      // At the bottom: the message grows upwards and pushes older ones.
      harness.currentState!.update((items) => items[0].height = 100);
      await tester.pump();
      expect(_rect(tester, 'item-0').bottom, 600);
      expect(_rect(tester, 'item-1').bottom, 500);

      // Scrolled up a bit, the message is still partially visible: what the
      // user reads must not move while it keeps growing.
      scrollController.jumpTo(30);
      await tester.pump();
      final before = _rect(tester, 'item-1');
      for (var height = 120.0; height <= 400; height += 20) {
        harness.currentState!.update((items) => items[0].height = height);
        await tester.pump();
        expect(_rect(tester, 'item-1'), before);
      }
    });

    testWidgets('reuses measured extents through the cache', (tester) async {
      final cache = PuskExtentCache();
      final items = _items(100, height: (i) => 30.0 + i);
      await tester.pumpWidget(_Harness(items: items, extentCache: cache));

      final controller = PuskListController();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _Harness(
          items: items,
          extentCache: cache,
          controller: controller,
          initialPosition: const PuskPosition(index: 80),
        ),
      );
      // Measured by the first list, not laid out by this one.
      expect(controller.isMeasured(10), isFalse);
      expect(controller.extentOf(10), 40);
      // Never measured at all.
      expect(controller.extentOf(50), 100);
    });

    testWidgets('handles becoming empty and refilling', (tester) async {
      final harness = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: harness, items: _items(20)));

      harness.currentState!.update((items) => items.clear());
      await tester.pump();
      expect(find.byType(_Tile), findsNothing);

      harness.currentState!.update((items) => items.addAll(_items(3)));
      await tester.pump();
      expect(_rect(tester, 'item-2').top, 100);
    });
  });

  testWidgets('visibleRange listeners may rebuild when the list goes away', (
    tester,
  ) async {
    final controller = PuskListController();
    Widget app({required bool showList}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          ValueListenableBuilder(
            valueListenable: controller.visibleRange,
            builder: (context, range, _) => Text('${range?.first}'),
          ),
          Expanded(
            child: showList
                ? _Harness(items: _items(100), controller: controller)
                : const SizedBox(),
          ),
        ],
      ),
    );
    await tester.pumpWidget(app(showList: true));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);

    await tester.pumpWidget(app(showList: false));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('null'), findsOneWidget);
  });

  group('separated', () {
    Widget list(
      List<String> ids, {
      PuskListController? controller,
      bool reverse = false,
      Axis scrollDirection = Axis.vertical,
      PuskItemTransition? transition,
    }) {
      final vertical = scrollDirection == Axis.vertical;
      Widget box(String key, double extent) => SizedBox(
        key: ValueKey(key),
        width: vertical ? null : extent,
        height: vertical ? extent : null,
      );
      return Directionality(
        textDirection: TextDirection.ltr,
        child: PuskList.separated(
          controller: controller,
          reverse: reverse,
          scrollDirection: scrollDirection,
          transition: transition,
          itemCount: ids.length,
          itemKey: (index) => ids[index],
          itemBuilder: (context, index) => box('tile-${ids[index]}', 50),
          separatorBuilder: (context, index) => box('sep-$index', 10),
        ),
      );
    }

    Rect sep(WidgetTester tester, int index) =>
        tester.getRect(find.byKey(ValueKey('sep-$index')));

    testWidgets('moves separators when the list gets reversed', (
      tester,
    ) async {
      await tester.pumpWidget(list(['a', 'b']));
      expect(sep(tester, 0).top, 50);
      await tester.pumpWidget(list(['a', 'b'], reverse: true));
      // Item 0 is at the bottom, its separator above it.
      expect(sep(tester, 0).bottom, 600 - 50);
    });

    testWidgets('puts a separator after every item but the last', (
      tester,
    ) async {
      final controller = PuskListController();
      await tester.pumpWidget(list(['a', 'b', 'c'], controller: controller));
      expect(_rect(tester, 'a').top, 0);
      expect(sep(tester, 0).top, 50);
      expect(_rect(tester, 'b').top, 60);
      expect(_rect(tester, 'c').top, 120);
      expect(find.byKey(const ValueKey('sep-2')), findsNothing);
      expect(controller.extentOf(0), 60);
      expect(controller.extentOf(2), 50);

      // The previous last item gets its separator.
      await tester.pumpWidget(
        list(['a', 'b', 'c', 'd'], controller: controller),
      );
      expect(controller.extentOf(2), 60);
      expect(_rect(tester, 'd').top, 180);
    });

    testWidgets('keeps the state of the item that gets a separator', (
      tester,
    ) async {
      final items = [_Item('a', 50), _Item('b', 50)];
      Widget build() => Directionality(
        textDirection: TextDirection.ltr,
        child: PuskList.separated(
          itemCount: items.length,
          itemKey: (index) => items[index].id,
          itemBuilder: (context, index) => _Tile(items[index]),
          separatorBuilder: (context, index) => const SizedBox(height: 10),
        ),
      );
      await tester.pumpWidget(build());
      items.add(_Item('c', 50));
      await tester.pumpWidget(build());
      items.removeLast();
      await tester.pumpWidget(build());
      expect(_createdById, {'a': 1, 'b': 1, 'c': 1});
    });

    testWidgets('places separators towards the next item when reversed', (
      tester,
    ) async {
      await tester.pumpWidget(list(['a', 'b'], reverse: true));
      expect(_rect(tester, 'a').bottom, 600);
      expect(sep(tester, 0).bottom, 550);
      expect(_rect(tester, 'b').bottom, 540);
    });

    testWidgets('follows a horizontal axis', (tester) async {
      await tester.pumpWidget(
        list(['a', 'b'], scrollDirection: Axis.horizontal),
      );
      expect(sep(tester, 0).left, 50);
      expect(_rect(tester, 'b').left, 60);
      expect(_rect(tester, 'b').height, 600);
    });

    testWidgets('animates a separator with its item', (tester) async {
      const transition = PuskItemTransition.sizeFade(
        insertDuration: Duration(milliseconds: 200),
        insertCurve: Curves.linear,
      );
      await tester.pumpWidget(list(['b'], transition: transition));
      await tester.pumpWidget(list(['a', 'b'], transition: transition));
      await tester.pump(const Duration(milliseconds: 100));
      // Half of the 60px item with its separator.
      expect(_rect(tester, 'b').top, moreOrLessEquals(30));
      await tester.pumpAndSettle();
      expect(_rect(tester, 'b').top, 60);
    });
  });

  group('transitions', () {
    const linear = PuskItemTransition.sizeFade(
      insertDuration: Duration(milliseconds: 200),
      removeDuration: Duration(milliseconds: 200),
      insertCurve: Curves.linear,
      removeCurve: Curves.linear,
    );

    testWidgets('an inserted item fades in together with its space', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(key: harness, items: _items(100), transition: linear),
      );
      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-0', 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_rect(tester, 'item-0').top, moreOrLessEquals(12.5));
      expect(
        [
          for (final layer in tester.layers.whereType<OpacityLayer>())
            layer.alpha,
        ],
        [(0.25 * 255).round()],
      );
    });

    testWidgets('animations wait while tickers are disabled', (tester) async {
      final harness = GlobalKey<_HarnessState>();
      Widget app({required bool enabled}) => TickerMode(
        enabled: enabled,
        child: _Harness(key: harness, items: _items(100), transition: linear),
      );
      await tester.pumpWidget(app(enabled: false));
      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-0', 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_rect(tester, 'item-0').top, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Time passes while muted, as for other tickers: 66 of 200 ms.
      await tester.pumpWidget(app(enabled: true));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_rect(tester, 'item-0').top, moreOrLessEquals(16.5));
    });

    testWidgets(
      'an item inserted at the start edge is visible while it grows',
      (
        tester,
      ) async {
        final harness = GlobalKey<_HarnessState>();
        final controller = PuskListController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _Harness(
            key: harness,
            items: _items(100),
            controller: controller,
            transition: linear,
          ),
        );
        expect(controller.visibleRange.value?.first, 0);
        harness.currentState!.update(
          (items) => items.insert(0, _Item('new-0', 50)),
        );
        await tester.pump();
        expect(controller.visibleRange.value?.first, 0);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(controller.visibleRange.value?.first, 0);
        }
      },
    );

    testWidgets(
      'with fadeStart, an inserted item fades in after its space opens',
      (
        tester,
      ) async {
        final harness = GlobalKey<_HarnessState>();
        await tester.pumpWidget(
          _Harness(
            key: harness,
            items: _items(100),
            transition: const PuskItemTransition.sizeFade(
              insertDuration: Duration(milliseconds: 200),
              insertCurve: Curves.linear,
              fadeStart: 0.4,
            ),
          ),
        );
        harness.currentState!.update(
          (items) => items.insert(0, _Item('new-0', 50)),
        );
        await tester.pump();
        List<int?> alphas() => [
          for (final layer in tester.layers.whereType<OpacityLayer>())
            layer.alpha,
        ];

        // Value 0.25 < fadeStart 0.4: the space opens, nothing is painted.
        await tester.pump(const Duration(milliseconds: 50));
        expect(_rect(tester, 'item-0').top, moreOrLessEquals(12.5));
        expect(alphas(), isEmpty);

        // Value 0.75: (0.75 - 0.4) / 0.6 of the full opacity.
        await tester.pump(const Duration(milliseconds: 100));
        expect(alphas(), [(0.35 / 0.6 * 255).round()]);

        await tester.pumpAndSettle();
        expect(alphas(), isEmpty);
      },
    );

    testWidgets('a neighbour changing with a removal animates its extent', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          reverse: true,
          transition: linear,
        ),
      );
      var lastTop = _rect(tester, 'item-4').top;
      // Like a chat message gaining its author's name when the message
      // above it is deleted.
      harness.currentState!.update((items) {
        items.removeAt(3);
        items[2].height = 80;
      });
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(
          frame == 0 ? null : const Duration(milliseconds: 16),
        );
        // The changed item keeps its edge away from the removal.
        expect(_rect(tester, 'item-2').bottom, 500);
        // The items above only move down: no jump up first.
        final top = _rect(tester, 'item-4').top;
        expect(top, greaterThanOrEqualTo(lastTop - 1e-6));
        lastTop = top;
      }
      await tester.pumpAndSettle();
      expect(_rect(tester, 'item-2'), const Rect.fromLTRB(0, 420, 800, 500));
      expect(_rect(tester, 'item-4').top, 370);
    });

    testWidgets('extent changes without insertions or removals are not '
        'animated', (tester) async {
      final harness = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          reverse: true,
          transition: linear,
        ),
      );
      harness.currentState!.update((items) => items[2].height = 80);
      await tester.pump();
      expect(_rect(tester, 'item-2'), const Rect.fromLTRB(0, 420, 800, 500));
      expect(_rect(tester, 'item-4').top, 320);
    });

    testWidgets('the estimator gets item indices while items animate out', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          controller: controller,
          transition: linear,
          estimate: true,
        ),
      );
      harness.currentState!.update((items) => items.removeAt(2));
      await tester.pump(const Duration(milliseconds: 50));
      harness.currentState!.update(
        (items) => items.add(_Item('last', 77)),
      );
      await tester.pump();
      expect(controller.isMeasured(99), isFalse);
      expect(controller.extentOf(99), 77);
    });

    testWidgets('an item inserted at the start edge grows in', (tester) async {
      final harness = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(key: harness, items: _items(100), transition: linear),
      );
      final created = _createdTiles;

      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-0', 50)),
      );
      await tester.pump();
      expect(_rect(tester, 'item-0').top, 0);

      await tester.pump(const Duration(milliseconds: 100));
      expect(_rect(tester, 'item-0').top, moreOrLessEquals(25));
      // Slides in from the leading edge.
      expect(_rect(tester, 'new-0').bottom, moreOrLessEquals(25));

      await tester.pumpAndSettle();
      expect(_rect(tester, 'new-0').top, 0);
      expect(_rect(tester, 'item-0').top, 50);
      expect(_createdTiles, created + 1);
    });

    testWidgets('a removed item shrinks out without being rebuilt', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          controller: controller,
          transition: linear,
        ),
      );
      final created = _createdTiles;
      final builds = _builds['item-3'];

      harness.currentState!.update(
        (items) => items.removeWhere((item) => item.id == 'item-3'),
      );
      await tester.pump();
      expect(controller.itemCount, 99);
      expect(controller.indexOfKey('item-3'), isNull);
      expect(controller.indexOfKey('item-4'), 3);
      expect(_rect(tester, 'item-4').top, 200);

      await tester.pump(const Duration(milliseconds: 100));
      expect(_rect(tester, 'item-4').top, moreOrLessEquals(175));
      expect(
        controller.visibleItems.map((i) => i.key),
        isNot(contains('item-3')),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-item-3')), findsNothing);
      expect(_rect(tester, 'item-4').top, 150);
      expect(_builds['item-3'], builds, reason: 'never built after removal');
      expect(_createdTiles, created + 1, reason: 'only item-12 scrolled in');
    });

    testWidgets('changes outside the viewport apply immediately', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          controller: controller,
          transition: linear,
        ),
      );
      controller.jumpToIndex(20);
      await tester.pump();

      harness.currentState!.update((items) {
        items
          ..removeRange(60, 70)
          ..insertAll(0, _items(5, prefix: 'new'));
      });
      await tester.pump();
      expect(_rect(tester, 'item-20').top, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a removal cut by the leading edge keeps the screen still', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      final scrollController = ScrollController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          controller: controller,
          scrollController: scrollController,
          transition: linear,
        ),
      );
      controller.jumpToIndex(20);
      await tester.pump();
      scrollController.jumpTo(scrollController.offset + 20);
      await tester.pump();
      expect(_rect(tester, 'item-21').top, 30);

      harness.currentState!.update(
        (items) => items.removeWhere((item) => item.id == 'item-20'),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_rect(tester, 'item-21').top, moreOrLessEquals(30));
      }
      await tester.pumpAndSettle();
      expect(_rect(tester, 'item-21').top, moreOrLessEquals(30));
    });

    testWidgets('an item re-inserted while animating out comes back', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(key: harness, items: _items(100), transition: linear),
      );
      late _Item removed;

      harness.currentState!.update((items) => removed = items.removeAt(3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_rect(tester, 'item-4').top, moreOrLessEquals(175));

      // Continues from where it was: half way in 100ms.
      harness.currentState!.update((items) => items.insert(3, removed));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_rect(tester, 'item-4').top, moreOrLessEquals(187.5));

      await tester.pumpAndSettle();
      expect(_rect(tester, 'item-4').top, 200);
      expect(_createdById['item-3'], 1, reason: 'the item kept its state');
    });

    testWidgets('a reversed chat: new messages rise only at the bottom', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      final scrollController = ScrollController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          scrollController: scrollController,
          reverse: true,
          transition: linear,
        ),
      );

      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-0', 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_rect(tester, 'item-0').bottom, moreOrLessEquals(575));
      expect(_rect(tester, 'new-0').top, moreOrLessEquals(575));
      await tester.pumpAndSettle();
      expect(_rect(tester, 'new-0').bottom, 600);

      // Scrolled up: a new message neither animates nor moves anything.
      scrollController.jumpTo(30);
      await tester.pump();
      final before = _rect(tester, 'item-5');
      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-1', 50)),
      );
      await tester.pump();
      expect(_rect(tester, 'item-5'), before);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_rect(tester, 'item-5'), before);
    });

    testWidgets('custom transitions are built once and driven by the list', (
      tester,
    ) async {
      final harness = GlobalKey<_HarnessState>();
      var builderCalls = 0;
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(100),
          transition: PuskItemTransition.custom(
            animateSize: false,
            insertDuration: const Duration(milliseconds: 200),
            insertCurve: Curves.linear,
            builder: (context, animation, key, child) {
              builderCalls++;
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        ),
      );

      harness.currentState!.update(
        (items) => items.insert(0, _Item('new-0', 50)),
      );
      await tester.pump();
      builderCalls = 0;
      await tester.pump(const Duration(milliseconds: 100));
      final fade = tester.widget<FadeTransition>(
        find.ancestor(
          of: find.byKey(const ValueKey('tile-new-0')),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, moreOrLessEquals(0.5));
      expect(_rect(tester, 'item-0').top, 50, reason: 'size not animated');

      await tester.pumpAndSettle();
      expect(builderCalls, 0, reason: 'no rebuilds while animating');
      expect(fade.opacity.value, 1);
    });

    testWidgets('removing every item animates them all out', (tester) async {
      final harness = GlobalKey<_HarnessState>();
      final controller = PuskListController();
      await tester.pumpWidget(
        _Harness(
          key: harness,
          items: _items(20),
          controller: controller,
          transition: linear,
        ),
      );

      harness.currentState!.update((items) => items.clear());
      await tester.pump();
      expect(controller.itemCount, 0);
      expect(find.byType(_Tile), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.byType(_Tile), findsNothing);

      harness.currentState!.update((items) => items.addAll(_items(3)));
      await tester.pump();
      expect(_rect(tester, 'item-2').top, 100);
    });
  });

  group('next to other slivers', () {
    Widget scrollView(
      List<Widget> slivers, {
      bool reverse = false,
      ScrollController? controller,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(
        controller: controller,
        reverse: reverse,
        slivers: slivers,
      ),
    );

    Widget list(
      List<_Item> items, {
      PuskListController? controller,
      PuskPosition? initialPosition,
    }) => PuskSliverList(
      controller: controller,
      itemCount: items.length,
      itemKey: (index) => items[index].id,
      itemBuilder: (context, index) => _Tile(items[index]),
      initialPosition: initialPosition,
    );

    const footer = SliverToBoxAdapter(child: SizedBox(height: 600));

    testWidgets('jumps to the last items with content after the list', (
      tester,
    ) async {
      final controller = PuskListController();
      await tester.pumpWidget(
        scrollView([list(_items(100), controller: controller), footer]),
      );

      controller.jumpToIndex(99);
      await tester.pump();
      expect(_rect(tester, 'item-99').top, moreOrLessEquals(0));

      controller.jumpToIndex(98, alignment: 0.5);
      await tester.pump();
      expect(_rect(tester, 'item-98').center.dy, moreOrLessEquals(300));
    });

    testWidgets('jumps to the last items of a reversed list with content '
        'after it', (tester) async {
      final controller = PuskListController();
      await tester.pumpWidget(
        scrollView([
          list(_items(100), controller: controller),
          footer,
        ], reverse: true),
      );

      controller.jumpToIndex(99);
      await tester.pump();
      expect(_rect(tester, 'item-99').bottom, moreOrLessEquals(600));
    });

    testWidgets('aligns the first items with content before the list', (
      tester,
    ) async {
      final controller = PuskListController();
      await tester.pumpWidget(
        scrollView([
          list(_items(20, prefix: 'a')),
          // Estimated at 100, so the first jump misses.
          list(_items(100, height: (_) => 30), controller: controller),
        ]),
      );

      controller.jumpToIndex(0, alignment: 0.5);
      await tester.pump();
      expect(_rect(tester, 'item-0').center.dy, moreOrLessEquals(300));

      controller.jumpToIndex(1, alignment: 1);
      await tester.pump();
      expect(_rect(tester, 'item-1').bottom, moreOrLessEquals(600));
    });

    testWidgets('lands on the initial position with content before the list', (
      tester,
    ) async {
      await tester.pumpWidget(
        scrollView([
          const SliverToBoxAdapter(child: SizedBox(height: 1000)),
          list(
            _items(100, height: (_) => 30),
            initialPosition: const PuskPosition(index: 0, alignment: 0.5),
          ),
        ]),
      );
      expect(_rect(tester, 'item-0').center.dy, moreOrLessEquals(300));
    });

    testWidgets('a list scrolled past keeps the content after it in place', (
      tester,
    ) async {
      final above = _items(20, prefix: 'a');
      late StateSetter setState;
      final controller = PuskListController();
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, set) {
            setState = set;
            return scrollView([
              list(above),
              list(_items(100), controller: controller),
            ]);
          },
        ),
      );
      controller.jumpToIndex(30);
      await tester.pump();
      expect(_rect(tester, 'item-30').top, 0);

      setState(() => above.add(_Item('a-new', 50)));
      await tester.pump();
      expect(_rect(tester, 'item-30').top, 0);

      setState(() => above.removeRange(15, 21));
      await tester.pump();
      expect(_rect(tester, 'item-30').top, 0);
    });

    testWidgets('the last item cut by the leading edge grows off-screen', (
      tester,
    ) async {
      final above = _items(20, prefix: 'a');
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      late StateSetter setState;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, set) {
            setState = set;
            return scrollView([
              list(above),
              list(_items(100)),
            ], controller: scrollController);
          },
        ),
      );
      // Measure the items first: they are estimated at 100.
      scrollController.jumpTo(975);
      await tester.pump();
      scrollController.jumpTo(
        scrollController.offset + _rect(tester, 'a-19').top + 25,
      );
      await tester.pump();
      expect(_rect(tester, 'a-19').top, -25);
      final before = _rect(tester, 'item-0').top;

      setState(() => above.last.height = 150);
      await tester.pump();
      expect(_rect(tester, 'item-0').top, before);
    });
  });

  group('obscured parts of the viewport', () {
    Widget chat({
      required PuskListController controller,
      ScrollController? scrollController,
    }) {
      const insets = EdgeInsets.only(top: 100, bottom: 60);
      final items = _items(1000);
      return Directionality(
        textDirection: TextDirection.ltr,
        child: PuskList(
          reverse: true,
          controller: controller,
          scrollController: scrollController,
          padding: insets,
          obscuredInsets: insets,
          itemCount: items.length,
          itemKey: (index) => items[index].id,
          itemBuilder: (context, index) => _Tile(items[index]),
        ),
      );
    }

    testWidgets('jumps align items between the insets', (tester) async {
      final controller = PuskListController();
      await tester.pumpWidget(chat(controller: controller));

      controller.jumpToIndex(500);
      await tester.pump();
      expect(_rect(tester, 'item-500').bottom, moreOrLessEquals(540));

      controller.jumpToIndex(300, alignment: 1);
      await tester.pump();
      expect(_rect(tester, 'item-300').top, moreOrLessEquals(100));

      controller.jumpToIndex(700, alignment: 0.5);
      await tester.pump();
      expect(_rect(tester, 'item-700').center.dy, moreOrLessEquals(320));

      controller.jumpToIndex(0);
      await tester.pump();
      expect(_rect(tester, 'item-0').bottom, moreOrLessEquals(540));
    });

    testWidgets('visible items restore the position between the insets', (
      tester,
    ) async {
      final controller = PuskListController();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        chat(controller: controller, scrollController: scrollController),
      );
      scrollController.jumpTo(5037);
      await tester.pump();
      final item = controller.visibleItems[3];
      final top = _rect(tester, 'item-${item.index}').top;

      controller.jumpToIndex(0);
      await tester.pump();
      controller.jumpToIndex(item.index, alignment: item.alignment);
      await tester.pump();
      expect(_rect(tester, 'item-${item.index}').top, moreOrLessEquals(top));
    });

    testWidgets('items under the insets are not visible', (tester) async {
      final controller = PuskListController();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        chat(controller: controller, scrollController: scrollController),
      );
      await tester.pump();
      // 440px between the insets: items 0-8, the 9th is cut by the top one.
      expect(controller.visibleRange.value, (first: 0, last: 8));

      // Item 0 goes under the bottom inset, item 10 comes out of the top one.
      scrollController.jumpTo(60);
      await tester.pump();
      await tester.pump();
      expect(controller.visibleRange.value, (first: 1, last: 9));
    });

    Widget withHeader(
      PuskListController controller, {
      bool floating = false,
      double minExtent = 80,
    }) {
      final items = _items(1000);
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: !floating,
              floating: floating,
              delegate: _Header(minExtent: minExtent, maxExtent: 80),
            ),
            PuskSliverList(
              controller: controller,
              itemCount: items.length,
              itemKey: (index) => items[index].id,
              itemBuilder: (context, index) => _Tile(items[index]),
            ),
          ],
        ),
      );
    }

    testWidgets('jumps align items below a pinned header', (tester) async {
      final controller = PuskListController();
      await tester.pumpWidget(withHeader(controller));

      controller.jumpToIndex(500);
      await tester.pump();
      expect(_rect(tester, 'item-500').top, moreOrLessEquals(80));

      controller.jumpToIndex(300, alignment: 0.5);
      await tester.pump();
      expect(_rect(tester, 'item-300').center.dy, moreOrLessEquals(340));
      await tester.pump();
      // Item 294 (15-65) is under the header, 295 (65-115) is cut by it.
      expect(controller.visibleRange.value?.first, 295);

      final item = controller.visibleItems.first;
      expect(item.index, 295);
      controller.jumpToIndex(0);
      await tester.pump();
      expect(_rect(tester, 'item-0').top, moreOrLessEquals(80));

      controller.jumpToIndex(item.index, alignment: item.alignment);
      await tester.pump();
      expect(_rect(tester, 'item-295').top, moreOrLessEquals(65));
    });

    testWidgets('jumps align items below a collapsing header', (tester) async {
      final controller = PuskListController();
      final items = _items(1000);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _Header(minExtent: 60, maxExtent: 200),
              ),
              PuskSliverList(
                controller: controller,
                itemCount: items.length,
                itemKey: (index) => items[index].id,
                itemBuilder: (context, index) => _Tile(items[index]),
              ),
            ],
          ),
        ),
      );

      controller.jumpToIndex(500);
      await tester.pump();
      expect(_rect(tester, 'item-500').top, moreOrLessEquals(60));
    });

    testWidgets('a jump lands with a floating header', (tester) async {
      final controller = PuskListController();
      await tester.pumpWidget(withHeader(controller, floating: true));

      controller.jumpToIndex(500);
      await tester.pump();
      final top = _rect(tester, 'item-500').top;
      await tester.pump();
      expect(_rect(tester, 'item-500').top, top);
      expect(top == 0 || top == 80, isTrue, reason: 'top: $top');
    });
  });
}

class _Header extends SliverPersistentHeaderDelegate {
  _Header({required this.minExtent, required this.maxExtent});

  @override
  final double minExtent;

  @override
  final double maxExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      const SizedBox.expand();

  @override
  bool shouldRebuild(_Header oldDelegate) =>
      minExtent != oldDelegate.minExtent || maxExtent != oldDelegate.maxExtent;
}

int _createdTiles = 0;

/// How many times a tile was created, by item id.
final Map<String, int> _createdById = {};

/// How many times the item builder was called, by item id.
final Map<String, int> _builds = {};

class _Item {
  _Item(this.id, this.height);

  final String id;
  double height;
}

List<_Item> _items(
  int count, {
  String prefix = 'item',
  double Function(int index)? height,
}) => List.generate(
  count,
  (i) => _Item('$prefix-$i', height?.call(i) ?? 50),
);

Rect _rect(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey('tile-$id')));

class _Tile extends StatefulWidget {
  const _Tile(this.item);

  final _Item item;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  @override
  void initState() {
    super.initState();
    _createdTiles++;
    _createdById[widget.item.id] = (_createdById[widget.item.id] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('tile-${widget.item.id}'),
      height: widget.item.height,
      child: Text(widget.item.id),
    );
  }
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.items,
    this.controller,
    this.scrollController,
    this.reverse = false,
    this.initialPosition,
    this.extentCache,
    this.transition,
    this.estimate = false,
    super.key,
  });

  final List<_Item> items;
  final PuskListController? controller;
  final ScrollController? scrollController;
  final bool reverse;
  final PuskPosition? initialPosition;
  final PuskExtentCache? extentCache;
  final PuskItemTransition? transition;

  /// Estimates every item at its real extent through `extentEstimator`.
  final bool estimate;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final List<_Item> items = List.of(widget.items);

  void update(void Function(List<_Item> items) change) {
    setState(() => change(items));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(
        controller: widget.scrollController,
        reverse: widget.reverse,
        slivers: [
          PuskSliverList(
            controller: widget.controller,
            itemCount: items.length,
            itemKey: (index) => items[index].id,
            itemBuilder: (context, index) {
              final item = items[index];
              _builds[item.id] = (_builds[item.id] ?? 0) + 1;
              return _Tile(item);
            },
            initialPosition: widget.initialPosition,
            extentCache: widget.extentCache,
            transition: widget.transition,
            extentEstimator: widget.estimate
                ? (index) => items[index].height
                : null,
          ),
        ],
      ),
    );
  }
}
