import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusk_list/pusk_list.dart';

void main() {
  setUp(_created.clear);

  /// Linear timings, so positions are easy to check.
  _Config reorder({
    required void Function(int from, int to) onReorder,
    void Function(int index)? onReorderStart,
    void Function(int from, int to)? onReorderUpdate,
    void Function(int index)? onReorderEnd,
    bool Function(int from, int to)? canReorder,
    bool freeDrag = false,
    PuskAutoScroll autoScroll = PuskAutoScroll.none,
  }) => (
    onReorder: onReorder,
    onReorderStart: onReorderStart,
    onReorderUpdate: onReorderUpdate,
    onReorderEnd: onReorderEnd,
    canReorder: canReorder,
    freeDrag: freeDrag,
    autoScroll: autoScroll,
  );

  testWidgets('a dragged item follows the pointer, others make room', (
    tester,
  ) async {
    final items = _ids(30);
    final calls = <String>[];
    await tester.pumpWidget(
      _Harness(
        items: items,
        reorder: (setState) => reorder(
          onReorderStart: (index) => calls.add('start $index'),
          onReorderUpdate: (from, to) => calls.add('update $from $to'),
          onReorderEnd: (index) => calls.add('end $index'),
          onReorder: (from, to) {
            calls.add('reorder $from $to');
            setState(() => items.insert(to, items.removeAt(from)));
          },
        ),
      ),
    );
    final created = _created.length;

    final gesture = await tester.startGesture(_handle(tester, 'item-2'));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(_top(tester, 'item-2'), 160);
    // Passed the middle of item-3 (in the list without item-2): item-3
    // starts sliding up.
    expect(calls, ['start 2', 'update 2 3']);
    expect(_top(tester, 'item-3'), 150);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_top(tester, 'item-3'), moreOrLessEquals(125));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_top(tester, 'item-3'), 100);
    expect(_top(tester, 'item-4'), 200);

    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_top(tester, 'item-2'), 220);
    expect(calls.last, 'update 2 4');
    expect(_top(tester, 'item-4'), 150);
    expect(_top(tester, 'item-5'), 250);

    await gesture.up();
    await tester.pump();
    expect(calls.last, 'reorder 2 4');
    expect(items.sublist(0, 6), [
      'item-0',
      'item-1',
      'item-3',
      'item-4',
      'item-2',
      'item-5',
    ]);
    // Flies from where it was dropped to its place.
    expect(_top(tester, 'item-2'), 220);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_top(tester, 'item-2'), moreOrLessEquals(210));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_top(tester, 'item-2'), 200);
    await tester.pump(const Duration(milliseconds: 16));
    expect(calls.last, 'end 4');
    expect(_created.length, created, reason: 'no tile should be recreated');
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('dragging back to the start reports no move', (tester) async {
    final items = _ids(30);
    final calls = <String>[];
    await tester.pumpWidget(
      _Harness(
        items: items,
        reorder: (setState) =>
            reorder(onReorder: (from, to) => calls.add('$from $to')),
      ),
    );
    final gesture = await tester.startGesture(_handle(tester, 'item-2'));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(_top(tester, 'item-2'), 100);
    expect(_top(tester, 'item-3'), 150);
  });

  testWidgets('an item slides back when the order is not changed', (
    tester,
  ) async {
    final items = _ids(30);
    await tester.pumpWidget(
      _Harness(
        items: items,
        reorder: (setState) => reorder(onReorder: (from, to) {}),
      ),
    );
    final gesture = await tester.startGesture(_handle(tester, 'item-2'));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_top(tester, 'item-3'), 100);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_top(tester, 'item-3'), moreOrLessEquals(125));
    await tester.pumpAndSettle();
    expect(_top(tester, 'item-2'), 100);
    expect(_top(tester, 'item-3'), 150);
  });

  testWidgets('the screen stays put when the first visible item moves', (
    tester,
  ) async {
    final items = _ids(100);
    final controller = PuskListController();
    await tester.pumpWidget(
      _Harness(
        items: items,
        controller: controller,
        reorder: (setState) => reorder(
          onReorder: (from, to) =>
              setState(() => items.insert(to, items.removeAt(from))),
        ),
      ),
    );
    controller.jumpToIndex(20);
    await tester.pump();
    expect(_top(tester, 'item-20'), 0);

    final gesture = await tester.startGesture(_handle(tester, 'item-20'));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_top(tester, 'item-20'), 40);
    expect(_top(tester, 'item-21'), 0);
    expect(_top(tester, 'item-22'), 100);

    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_top(tester, 'item-21'), 50);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_top(tester, 'item-20'), 0);
    expect(_top(tester, 'item-21'), 50);
  });

  testWidgets('a long press starts a drag after the delay', (tester) async {
    final items = _ids(30);
    final calls = <String>[];
    await tester.pumpWidget(
      _Harness(
        items: items,
        delay: const Duration(milliseconds: 500),
        reorder: (setState) => reorder(
          onReorderStart: (index) => calls.add('start $index'),
          onReorder: (from, to) =>
              setState(() => items.insert(to, items.removeAt(from))),
        ),
      ),
    );

    // Moving before the delay scrolls.
    var gesture = await tester.startGesture(_handle(tester, 'item-5'));
    await gesture.moveBy(const Offset(0, -40));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(_top(tester, 'item-5'), lessThan(250));

    final top = _top(tester, 'item-5');
    gesture = await tester.startGesture(_handle(tester, 'item-5'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, ['start 5']);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(_top(tester, 'item-5'), top + 30);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(items.indexOf('item-5'), 6);
  });

  testWidgets('scrolls near the edges', (tester) async {
    final items = _ids(100);
    final controller = PuskListController();
    await tester.pumpWidget(
      _Harness(
        items: items,
        controller: controller,
        reorder: (setState) => reorder(
          autoScroll: const PuskAutoScroll(
            edgeExtent: 0,
            rampExtent: 40,
            maxSpeed: 1000,
            curve: Curves.linear,
          ),
          onReorder: (from, to) =>
              setState(() => items.insert(to, items.removeAt(from))),
        ),
      ),
    );
    final gesture = await tester.startGesture(_handle(tester, 'item-9'));
    // Bottom edge 20px past the viewport: half speed.
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(_top(tester, 'item-9'), 570);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final offset = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(offset.position.pixels, moreOrLessEquals(100, epsilon: 1));
    // Stays under the pointer, takes places further down.
    expect(_top(tester, 'item-9'), 570);
    await tester.pump(const Duration(milliseconds: 200));
    expect(items.indexOf('item-9'), 9);
    await gesture.up();
    await tester.pumpAndSettle();
    final index = items.indexOf('item-9');
    expect(index, greaterThan(12));
    expect(controller.visibleItems.map((item) => item.key), contains('item-9'));
  });

  testWidgets('a reversed list drags along its axis', (tester) async {
    final items = _ids(30);
    await tester.pumpWidget(
      _Harness(
        items: items,
        reverse: true,
        reorder: (setState) => reorder(
          onReorder: (from, to) =>
              setState(() => items.insert(to, items.removeAt(from))),
        ),
      ),
    );
    // item-0 is at the bottom: 550..600.
    expect(_top(tester, 'item-2'), 450);
    final gesture = await tester.startGesture(_handle(tester, 'item-2'));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(_top(tester, 'item-2'), 370);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(items.indexOf('item-2'), 4);
    expect(_top(tester, 'item-2'), 350);
  });

  testWidgets('skips places that are not allowed', (tester) async {
    final items = _ids(30);
    await tester.pumpWidget(
      _Harness(
        items: items,
        reorder: (setState) => reorder(
          canReorder: (from, to) => to != 3,
          onReorder: (from, to) =>
              setState(() => items.insert(to, items.removeAt(from))),
        ),
      ),
    );
    final gesture = await tester.startGesture(_handle(tester, 'item-1'));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(items.indexOf('item-1'), 2);

    final second = await tester.startGesture(_handle(tester, 'item-1'));
    await second.moveBy(const Offset(0, 110));
    await tester.pump();
    await second.up();
    await tester.pumpAndSettle();
    expect(items.indexOf('item-1'), 4);
  });

  testWidgets('a free drag follows the pointer across the axis', (
    tester,
  ) async {
    final items = _ids(30);
    await tester.pumpWidget(
      _Harness(
        items: items,
        reorder: (setState) => reorder(
          freeDrag: true,
          onReorder: (from, to) =>
              setState(() => items.insert(to, items.removeAt(from))),
        ),
      ),
    );
    final left = _rect(tester, 'item-2').left;
    final gesture = await tester.startGesture(_handle(tester, 'item-2'));
    await gesture.moveBy(const Offset(-30, 20));
    await tester.pump();
    expect(_rect(tester, 'item-2').left, left - 30);
    expect(_top(tester, 'item-2'), 120);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_rect(tester, 'item-2').left, moreOrLessEquals(left - 15));
    await tester.pumpAndSettle();
    expect(_rect(tester, 'item-2').left, left);
  });

  testWidgets('a drag ends when the item is removed', (tester) async {
    final items = _ids(30);
    final harness = GlobalKey<_HarnessState>();
    final calls = <String>[];
    await tester.pumpWidget(
      _Harness(
        key: harness,
        items: items,
        reorder: (setState) => reorder(
          onReorder: (from, to) => calls.add('$from $to'),
        ),
      ),
    );
    final gesture = await tester.startGesture(_handle(tester, 'item-2'));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    harness.currentState!.update(() => items.remove('item-2'));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.byKey(const ValueKey('tile-item-2')), findsNothing);
    expect(_top(tester, 'item-3'), 100);
  });

  testWidgets('the sliver list follows the pointer after a header', (
    tester,
  ) async {
    final items = _ids(30);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) => CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
              PuskSliverList(
                itemCount: items.length,
                itemKey: (index) => items[index],
                itemBuilder: (context, index) =>
                    _Tile(id: items[index], delay: Duration.zero),
                estimatedExtent: 50,
                reorder: PuskReorder(
                  autoScroll: const PuskAutoScroll(
                    edgeExtent: 0,
                    rampExtent: 40,
                    maxSpeed: 1000,
                    curve: Curves.linear,
                  ),
                  onReorder: (from, to) =>
                      setState(() => items.insert(to, items.removeAt(from))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(_top(tester, 'item-1'), 150);
    final gesture = await tester.startGesture(_handle(tester, 'item-1'));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(_top(tester, 'item-1'), 210);
    // To the bottom edge: the list scrolls, the header goes away, the item
    // stays under the pointer.
    await gesture.moveBy(const Offset(0, 370));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_top(tester, 'item-1'), 580);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(items.indexOf('item-1'), greaterThan(12));
  });

  testWidgets('decorates the dragged item, works with transitions', (
    tester,
  ) async {
    final items = _ids(30);
    final controller = PuskListController();
    final lifts = <String, double>{};
    late void Function(VoidCallback) update;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PuskList.separated(
              controller: controller,
              itemCount: items.length,
              itemKey: (index) => items[index],
              itemBuilder: (context, index) =>
                  _Tile(id: items[index], delay: Duration.zero),
              separatorBuilder: (context, index) => const SizedBox(height: 1),
              estimatedExtent: 51,
              transition: const PuskItemTransition.sizeFade(),
              reorder: PuskReorder(
                liftDuration: const Duration(milliseconds: 100),
                liftCurve: Curves.linear,
                decorator: (context, animation, child) => AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final id = (child! as _Tile).id;
                    lifts[id] = animation.value;
                    return child;
                  },
                  child: child,
                ),
                onReorder: (from, to) =>
                    setState(() => items.insert(to, items.removeAt(from))),
              ),
            );
          },
        ),
      ),
    );
    final created = _created.length;
    final gesture = await tester.startGesture(_handle(tester, 'item-1'));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(lifts['item-1'], moreOrLessEquals(0.5));
    expect(lifts['item-2'], 0);
    // A message arrives while dragging.
    update(() => items.insert(0, 'new'));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(lifts['item-1'], 0);
    expect(items.first, 'new');
    expect(items.indexOf('item-1'), greaterThan(2));
    expect(_created.length, created + 1, reason: 'only the new item');
    expect(tester.takeException(), isNull);
  });

  testWidgets('separators stay in the gaps while dragging', (
    tester,
  ) async {
    final items = _ids(4);
    final controller = PuskListController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) => PuskList.separated(
            controller: controller,
            itemCount: items.length,
            itemKey: (index) => items[index],
            itemBuilder: (context, index) =>
                _Tile(id: items[index], delay: Duration.zero),
            separatorBuilder: (context, index) =>
                SizedBox(key: ValueKey('sep-${items[index]}'), height: 10),
            estimatedExtent: 60,
            reorder: PuskReorder(
              moveDuration: const Duration(milliseconds: 200),
              moveCurve: Curves.linear,
              dropDuration: const Duration(milliseconds: 200),
              dropCurve: Curves.linear,
              onReorder: (from, to) =>
                  setState(() => items.insert(to, items.removeAt(from))),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(_handle(tester, 'item-1'));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    // The dragged item's place keeps its separator.
    expect(find.byKey(const ValueKey('sep-item-1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.extentOf(1), 60);

    // To the last place: the former last item gets a separator.
    await gesture.moveBy(const Offset(0, 130));
    await tester.pump();
    expect(controller.indexOfKey('item-1'), 3);
    expect(find.byKey(const ValueKey('sep-item-3')), findsNothing);
    expect(find.byKey(const ValueKey('sep-item-2')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.extentOf(2), moreOrLessEquals(55));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.extentOf(2), 60);

    // Back in the middle: the drop changes no extents.
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(controller.indexOfKey('item-1'), 2);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();
    expect(items, ['item-0', 'item-2', 'item-1', 'item-3']);
    expect(find.byKey(const ValueKey('sep-item-1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.extentOf(2), 60);
    await tester.pumpAndSettle();
    expect(controller.extentOf(2), 60);
    expect(controller.extentOf(3), 50);
    expect(_top(tester, 'item-3'), 180);
    expect(tester.takeException(), isNull);
  });

  testWidgets('items know their place as shown', (tester) async {
    final items = _ids(4);
    // Per item: its index as shown, whether it is dragged, the item below.
    final places = <String, (int, bool, String?)>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) => PuskList(
            itemCount: items.length,
            itemKey: (index) => items[index],
            itemBuilder: (context, index) {
              final id = items[index];
              return Builder(
                builder: (context) {
                  final item = PuskReorderItem.of(context);
                  final below = item.index + 1 < item.count
                      ? items[item.sourceIndexAt(item.index + 1)]
                      : null;
                  places[id] = (item.index, item.isDragged, below);
                  return _Tile(id: id, delay: Duration.zero);
                },
              );
            },
            estimatedExtent: 50,
            reorder: PuskReorder(
              onReorder: (from, to) =>
                  setState(() => items.insert(to, items.removeAt(from))),
            ),
          ),
        ),
      ),
    );
    expect(places['item-1'], (1, false, 'item-2'));
    expect(places['item-3'], (3, false, null));

    final gesture = await tester.startGesture(_handle(tester, 'item-1'));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(places['item-1'], (1, true, 'item-2'));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(places['item-0'], (0, false, 'item-2'));
    expect(places['item-2'], (1, false, 'item-3'));
    expect(places['item-3'], (2, false, 'item-1'));
    expect(places['item-1'], (3, true, null));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(items, ['item-0', 'item-2', 'item-3', 'item-1']);
    expect(places['item-1'], (3, false, null));
    expect(places['item-3'], (2, false, 'item-1'));
  });
}

List<String> _ids(int count) => [for (var i = 0; i < count; i++) 'item-$i'];

final _created = <String>[];

Offset _handle(WidgetTester tester, String id) =>
    tester.getCenter(find.byKey(ValueKey('handle-$id')));

Rect _rect(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey('tile-$id')));

double _top(WidgetTester tester, String id) => _rect(tester, id).top;

typedef _Config = ({
  void Function(int from, int to) onReorder,
  void Function(int index)? onReorderStart,
  void Function(int from, int to)? onReorderUpdate,
  void Function(int index)? onReorderEnd,
  bool Function(int from, int to)? canReorder,
  bool freeDrag,
  PuskAutoScroll autoScroll,
});

class _Harness extends StatefulWidget {
  const _Harness({
    required this.items,
    required this.reorder,
    this.controller,
    this.reverse = false,
    this.delay = Duration.zero,
    super.key,
  });

  final List<String> items;
  final _Config Function(void Function(VoidCallback) setState) reorder;
  final PuskListController? controller;
  final bool reverse;
  final Duration delay;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  void update(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final config = widget.reorder(setState);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: PuskList(
            controller: widget.controller,
            reverse: widget.reverse,
            itemCount: items.length,
            itemKey: (index) => items[index],
            itemBuilder: (context, index) =>
                _Tile(id: items[index], delay: widget.delay),
            estimatedExtent: 50,
            reorder: PuskReorder(
              onReorder: config.onReorder,
              onReorderStart: config.onReorderStart,
              onReorderUpdate: config.onReorderUpdate,
              onReorderEnd: config.onReorderEnd,
              canReorder: config.canReorder,
              freeDrag: config.freeDrag,
              autoScroll: config.autoScroll,
              liftDuration: const Duration(milliseconds: 100),
              liftCurve: Curves.linear,
              dropDuration: const Duration(milliseconds: 200),
              dropCurve: Curves.linear,
              moveDuration: const Duration(milliseconds: 200),
              moveCurve: Curves.linear,
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.id, required this.delay});

  final String id;
  final Duration delay;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  @override
  void initState() {
    super.initState();
    _created.add(widget.id);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('tile-${widget.id}'),
    height: 50,
    child: Row(
      children: [
        Expanded(child: Text(widget.id)),
        PuskDragStartListener(
          delay: widget.delay,
          child: SizedBox(
            key: ValueKey('handle-${widget.id}'),
            width: 40,
            height: 50,
            child: const ColoredBox(color: Color(0xFF888888)),
          ),
        ),
      ],
    ),
  );
}
