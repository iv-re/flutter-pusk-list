## 0.1.2

- `initialPosition` is no longer cut short by the end of the list on the first frame when the target needs the padding after it, e.g. the last item aligned above `obscuredInsets`. Slivers after the list are taken into account from the second frame.
- A jump lands precisely when `estimatedExtent` overestimates the items, instead of stopping short.

## 0.1.1

- In a top-to-bottom list, an item cut by the top edge keeps its top in place when its extent changes, so its visible part no longer moves while it grows (e.g. a streamed message).

## 0.1.0

- Initial release.
