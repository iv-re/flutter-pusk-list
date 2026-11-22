part of 'sliver_list.dart';

/// An item followed by its separator along the list's main axis.
///
/// Reads the axis from the enclosing sliver during layout, so it follows
/// `scrollDirection` and `reverse` without depending on anything.
class _Separated extends MultiChildRenderObjectWidget {
  _Separated({required Widget item, required Widget? separator})
    : super(children: [item, ?separator]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSeparated();
}

class _SeparatedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSeparated extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SeparatedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SeparatedParentData> {
  /// The list and the parent data of its child that this is in.
  _RenderPuskSliverList? _list;
  _ItemParentData? _itemData;

  /// Main axis extent of the separator, as of the last layout.
  double separatorExtent = 0;

  /// The held item's separator only keeps its room: it would follow the
  /// pointer with the item otherwise.
  bool get _hidesSeparator {
    final list = _list;
    return list != null && list._holds(_itemData!);
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _SeparatedParentData) {
      child.parentData = _SeparatedParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject child = this;
    while (child.parent is RenderBox) {
      child = child.parent!;
    }
    final list = child.parent;
    if (list is! _RenderPuskSliverList) return;
    _list = list;
    _itemData = (child.parentData! as _ItemParentData)..separated = this;
  }

  @override
  void detach() {
    if (identical(_itemData?.separated, this)) _itemData!.separated = null;
    _itemData = null;
    _list = null;
    super.detach();
  }

  AxisDirection get _mainAxisDirection {
    var node = parent;
    while (node is! RenderSliver) {
      node = node!.parent;
    }
    final constraints = node.constraints;
    return applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    );
  }

  @override
  void performLayout() {
    final item = firstChild!;
    final separator = childAfter(item);
    if (separator == null) {
      separatorExtent = 0;
      item.layout(constraints, parentUsesSize: true);
      size = item.size;
      (item.parentData! as _SeparatedParentData).offset = Offset.zero;
      return;
    }
    final direction = _mainAxisDirection;
    final axis = axisDirectionToAxis(direction);
    final childConstraints = switch (axis) {
      Axis.vertical => BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      Axis.horizontal => BoxConstraints(
        minHeight: constraints.minHeight,
        maxHeight: constraints.maxHeight,
      ),
    };
    item.layout(childConstraints, parentUsesSize: true);
    separator.layout(childConstraints, parentUsesSize: true);
    separatorExtent = switch (axis) {
      Axis.vertical => separator.size.height,
      Axis.horizontal => separator.size.width,
    };

    // The separator goes towards the next item: up or left when reversed.
    final reversed = axisDirectionIsReversed(direction);
    final first = reversed ? separator : item;
    final second = reversed ? item : separator;
    (first.parentData! as _SeparatedParentData).offset = Offset.zero;
    final secondData = second.parentData! as _SeparatedParentData;
    switch (axis) {
      case Axis.vertical:
        secondData.offset = Offset(0, first.size.height);
        size = constraints.constrain(
          Size(
            math.max(item.size.width, separator.size.width),
            item.size.height + separator.size.height,
          ),
        );
      case Axis.horizontal:
        secondData.offset = Offset(first.size.width, 0);
        size = constraints.constrain(
          Size(
            item.size.width + separator.size.width,
            math.max(item.size.height, separator.size.height),
          ),
        );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hidesSeparator) return defaultPaint(context, offset);
    final item = firstChild!;
    final data = item.parentData! as _SeparatedParentData;
    context.paintChild(item, offset + data.offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_hidesSeparator) {
      return defaultHitTestChildren(result, position: position);
    }
    final item = firstChild!;
    return result.addWithPaintOffset(
      offset: (item.parentData! as _SeparatedParentData).offset,
      position: position,
      hitTest: (result, position) => item.hitTest(result, position: position),
    );
  }
}
