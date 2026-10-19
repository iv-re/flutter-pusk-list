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

`itemKey` must return a unique key per item that stays the same while the
item exists: state, anchoring and animations follow it.

- Items keep their state and measured extents across list changes.
- The first visible item stays in place when items are inserted/removed
  before it or change extent; at the start edge new items are shown instead
  (`PuskAnchoring`).
- `PuskExtentCache` keeps measured extents across list instances.

`PuskList` takes the scroll view's parameters too (`padding`, `physics`,
`scrollController`, ...).

## Slivers

`PuskSliverList` is the same list for a `CustomScrollView`.

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

`PuskSliverList.separated` is the same for slivers. Indices count items
only: the separator after an item is a part of it.

## Controller

```dart
final controller = PuskListController();

controller.jumpToIndex(500, alignment: 0.5);
controller.jumpToKey(id);
await controller.animateToKey(id, duration: d, curve: Curves.easeInOut);
controller.visibleRange; // ValueListenable<({int first, int last})?>
```

`alignment` is relative to the viewport. If other widgets cover a part of it
(e.g. a translucent app bar), pass `obscuredInsets`: jumps align items within
the rest, and items entirely under the insets aren't visible. Pinned headers
are accounted for automatically.

## Transitions

```dart
// Size + fade, done by the list itself.
transition: const PuskItemTransition.sizeFade(),

// Your own widgets; the list still animates the size.
// `key` is the item key, also for removed items.
transition: PuskItemTransition.custom(
  builder: (context, animation, key, child) => ScaleTransition(
    scale: animation,
    child: child,
  ),
),
```

Only changes in the visible part of the list animate. A `custom` builder
must return the same widget structure for any `animation`, or items lose
their state when it starts or ends.

`example/` is a chat demo.
