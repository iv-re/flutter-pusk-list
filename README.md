# pusk_list

List with key-based scroll anchoring and fast jumps to any item.

```dart
import 'package:pusk_list/pusk_list.dart';

PuskList(
  reverse: true,
  itemCount: messages.length,
  itemKey: (index) => messages[index].id,
  itemBuilder: (context, index) => MessageTile(messages[index]),
  estimatedExtent: 80,
  transition: const PuskItemTransition.sizeFade(), // optional
  initialPosition: const PuskPosition(index: 120, alignment: 0.5), // optional
)
```

- `itemKey` must be unique and stable for the item's lifetime: state,
  anchoring and animations follow it.
- The first visible item stays in place when items before it change; at the
  start edge new items are shown instead (`PuskAnchoring`).
- `PuskExtentCache` keeps measured extents across list instances.

## Slivers

```dart
CustomScrollView(
  slivers: [
    const SliverAppBar(title: Text('Chat')),
    PuskSliverList(
      itemCount: messages.length,
      itemKey: (index) => messages[index].id,
      itemBuilder: (context, index) => MessageTile(messages[index]),
      estimatedExtent: 80,
    ),
  ],
)
```

## Separators

```dart
PuskList.separated(
  itemCount: messages.length,
  itemKey: (index) => messages[index].id,
  itemBuilder: (context, index) => MessageTile(messages[index]),
  separatorBuilder: (context, index) => const SizedBox(height: 8),
)
```

Indices count items only: the separator is a part of the item before it.

## Controller

```dart
final controller = PuskListController();

controller.jumpToIndex(500, alignment: 0.5);
controller.jumpToKey(id);
await controller.animateToKey(id, duration: d, curve: Curves.easeInOut);
controller.visibleRange; // ValueListenable<({int first, int last})?>
```

If a translucent app bar or similar covers the list, pass `obscuredInsets`:
jumps and visibility then use the uncovered part. Pinned headers are
accounted for automatically.

## Transitions

```dart
transition: const PuskItemTransition.sizeFade(),

// Own widgets; the list still animates the size. `key` is the item key.
transition: PuskItemTransition.custom(
  builder: (context, animation, key, child) {
    return ScaleTransition(scale: animation, child: child);
  },
),
```

- Only changes in the visible part animate.
- Reordered items slide to their new places (`moveDuration`, `moveCurve`).
- A `custom` builder must return the same structure for any `animation`,
  or items lose their state.

## Reordering

```dart
PuskList(
  itemCount: tasks.length,
  itemKey: (index) => tasks[index].id,
  itemBuilder: (context, index) => ListTile(
    title: Text(tasks[index].title),
    // PuskDragStartListener.delayed for a long press.
    trailing: const PuskDragStartListener(child: Icon(Icons.drag_handle)),
  ),
  reorder: PuskReorder(
    // `to` is the index after the move.
    onReorder: (from, to) {
      setState(() {
        final task = tasks.removeAt(from);
        tasks.insert(to, task);
      });
    },
  ),
)
```

- Change the order synchronously in `onReorder`, or the item slides back.
- Switching `reorder` between `null` and a value rebuilds the items. For an
  edit mode, keep it and show or hide the `PuskDragStartListener`s.
- While dragging, `itemBuilder` and `separatorBuilder` get indices of the
  unchanged list, the controller those of the list as shown. For what
  depends on the neighbours (corners, dividers of a group), use
  `PuskReorderItem.of(context)` inside the item: `index` as shown,
  `sourceIndexAt(i)` for the item shown at `i`.
- `decorator` must return the same structure for any animation.
- The dragged item is clipped by the viewport.
- Separators taking up space animate their appearance; draw them over the
  item to keep heights fixed.

`example/` has a chat demo and a reorder demo.
