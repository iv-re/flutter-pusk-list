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
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _SeparatedParentData) {
      child.parentData = _SeparatedParentData();
    }
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
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
