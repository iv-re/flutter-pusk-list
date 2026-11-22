import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusk_list/pusk_list.dart';

void main() {
  testWidgets('dropped in place, nothing changes its extent', (tester) async {
    final list = _List();
    await list.show(tester);
    final gesture = await list.lift(tester, 1);
    expect(list.extents, [60, 60, 60, 50]);
    await gesture.up();
    await tester.pump();
    expect(list.extents, [60, 60, 60, 50]);
  });

  testWidgets('dropped in a new place, different separators animate', (
    tester,
  ) async {
    late final _List list;
    list = _List(separator: (index) => list.items[index] == 1 ? 30 : 10);
    await list.show(tester);
    final gesture = await list.lift(tester, 1);
    await list.drag(tester, gesture, 80);
    await gesture.up();
    await tester.pump();
    expect(list.top(tester, 1), 140);
    await tester.pumpAndSettle();
    expect(list.top(tester, 1), 120);
  });

  testWidgets('a cancelled move slides back from right in its place', (
    tester,
  ) async {
    final list = _List();
    await list.show(tester);
    final gesture = await list.lift(tester, 2);
    await list.drag(tester, gesture, 60);
    await gesture.cancel();
    await tester.pump();
    expect(list.top(tester, 2), 180);
    await tester.pumpAndSettle();
    expect(list.top(tester, 2), 120);
  });

  testWidgets('with a transition, the last separator animates with no jump', (
    tester,
  ) async {
    final list = _List(transition: const PuskItemTransition.sizeFade());
    await list.show(tester);
    final gesture = await list.lift(tester, 2);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(list.top(tester, 3), 180);
    await tester.pump(_ms(100));
    expect(list.extents, [60, 60, 55, 55]);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  for (final (from, distance) in [(2, 60.0), (3, -120.0)]) {
    testWidgets('separatorBuilder gets gaps only, dragging $from', (
      tester,
    ) async {
      final list = _List();
      await list.show(tester);
      final gesture = await list.lift(tester, from);
      await list.drag(tester, gesture, distance);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(list.built, {0, 1, 2});
    });
  }

  testWidgets('the target keeps still at the last place', (tester) async {
    final list = _List();
    await list.show(tester);
    final gesture = await list.lift(tester, 2);
    await list.drag(tester, gesture, 30.2);
    await list.tremble(tester, gesture);
    expect(list.targets, [3]);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('scrolled, the screen and the target keep still', (tester) async {
    final list = _List(
      count: 13,
      separator: (index) => const <double>[0, 4, 24, 10][index % 4],
    );
    await list.show(tester);
    list.scroll.jumpTo(130);
    await tester.pumpAndSettle();
    final gesture = await list.lift(tester, 3);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await list.tremble(tester, gesture);
    expect(list.scroll.offset, 130);
    expect(list.targets, [2]);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('an item measured above the screen keeps the screen', (
    tester,
  ) async {
    final list = _List(count: 200, estimate: 20);
    await list.show(tester);
    list.scroll.jumpTo(130);
    await tester.pumpAndSettle();
    expect(list.controller.holdItem(6), isTrue);
    final top = list.top(tester, 4);
    list.update(() => list.items.insert(0, list.items.removeAt(150)));
    await tester.pump();
    await tester.pump(_ms(250));
    expect(list.top(tester, 4), top);
    list.controller.releaseHeldItem();
    await tester.pumpAndSettle();
  });

  testWidgets('autoscroll starts by the item, not by its separator', (
    tester,
  ) async {
    final list = _List(count: 20, autoScroll: const PuskAutoScroll());
    await list.show(tester);
    final gesture = await list.lift(tester, 5);
    // The item ends 41 px from the edge, with the separator it would be 31.
    await list.drag(tester, gesture, 109);
    expect(list.scroll.offset, 0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  for (final layer in [false, true]) {
    testWidgets('the line hides until the landing, layer inside: $layer', (
      tester,
    ) async {
      final list = _List(lineLayer: layer);
      await list.show(tester);
      expect(await list.pixel(tester, 115), _line);
      final gesture = await list.lift(tester, 1);
      await list.drag(tester, gesture, -22);
      // Neither in its place nor after the preview.
      expect(await list.pixel(tester, 115), _background);
      expect(await list.pixel(tester, 93), _background);
      await gesture.up();
      await tester.pump();
      await tester.pump(_ms(100));
      expect(await list.pixel(tester, 104), _background);
      await tester.pumpAndSettle();
      expect(await list.pixel(tester, 115), _line);
    });
  }

  testWidgets('the hidden line takes no taps', (tester) async {
    final list = _List();
    await list.show(tester);
    final gesture = await list.lift(tester, 1);
    await list.drag(tester, gesture, -24);
    await tester.tapAt(const Offset(150, 91));
    expect(list.taps, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}

const _line = Color(0xFFFF0000);
const _background = Color(0xFFFFFFFF);

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// A separated list of 50 px items and 10 px lines in a 300 by 500 box.
class _List {
  _List({
    int count = 4,
    this.separator,
    this.transition,
    this.estimate = 60,
    this.autoScroll = PuskAutoScroll.none,
    this.lineLayer = false,
  }) : items = List.generate(count, (i) => i);

  final List<int> items;
  final double Function(int index)? separator;
  final PuskItemTransition? transition;
  final double estimate;
  final PuskAutoScroll autoScroll;
  final bool lineLayer;

  final PuskListController controller = PuskListController();
  final ScrollController scroll = ScrollController();
  final GlobalKey _screen = GlobalKey();
  final targets = <int>[];
  final built = <int>{};
  final taps = <int>[];
  late StateSetter update;

  List<double> get extents => [
    for (var i = 0; i < items.length; i++) controller.extentOf(i)!,
  ];

  double top(WidgetTester tester, int id) =>
      tester.getTopLeft(find.byKey(ValueKey(id))).dy;

  Future<void> show(WidgetTester tester) async {
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 500,
            child: RepaintBoundary(
              key: _screen,
              child: ColoredBox(
                color: _background,
                child: StatefulBuilder(builder: _build),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _build(BuildContext context, StateSetter setState) {
    update = setState;
    return PuskList.separated(
      controller: controller,
      scrollController: scroll,
      itemCount: items.length,
      itemKey: (index) => items[index],
      itemBuilder: (context, index) => PuskDragStartListener.delayed(
        child: SizedBox(
          key: ValueKey(items[index]),
          height: 50,
          child: const ColoredBox(color: Color(0xFF00AA55)),
        ),
      ),
      separatorBuilder: (context, index) {
        built.add(index);
        final line = GestureDetector(
          onTap: () => taps.add(index),
          child: SizedBox(
            height: separator?.call(index) ?? 10,
            child: const ColoredBox(color: _line),
          ),
        );
        return lineLayer ? RepaintBoundary(child: line) : line;
      },
      estimatedExtent: estimate,
      transition: transition,
      reorder: PuskReorder(
        autoScroll: autoScroll,
        moveDuration: _ms(200),
        moveCurve: Curves.linear,
        dropDuration: _ms(200),
        dropCurve: Curves.linear,
        onReorderUpdate: (_, to) => targets.add(to),
        onReorder: (from, to) =>
            setState(() => items.insert(to, items.removeAt(from))),
      ),
    );
  }

  Future<TestGesture> lift(WidgetTester tester, int id) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey(id))),
    );
    await tester.pump(kLongPressTimeout + _ms(50));
    await tester.pump();
    return gesture;
  }

  /// Moves the pointer and lets the others make room.
  Future<void> drag(
    WidgetTester tester,
    TestGesture gesture,
    double distance,
  ) async {
    await gesture.moveBy(Offset(0, distance));
    await tester.pump();
    await tester.pump(_ms(200));
    await tester.pump();
  }

  Future<void> tremble(WidgetTester tester, TestGesture gesture) async {
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(Offset(0, i.isEven ? 0.1 : -0.1));
      await tester.pump(_ms(16));
    }
  }

  /// The color painted at [main] along the list.
  Future<Color> pixel(WidgetTester tester, int main) async {
    final boundary =
        _screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final color = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final at = (main * image.width + 150) * 4;
      image.dispose();
      return Color.fromARGB(
        data!.getUint8(at + 3),
        data.getUint8(at),
        data.getUint8(at + 1),
        data.getUint8(at + 2),
      );
    });
    return color!;
  }
}
