import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pusk_list/pusk_list.dart';

/// Items dragged by a handle (sliding along the list) or after a long press
/// (lifted, following the finger freely).
class ReorderDemo extends StatefulWidget {
  const ReorderDemo({super.key});

  @override
  State<ReorderDemo> createState() => _ReorderDemoState();
}

/// A row of the list: a section header or a task.
typedef _Row = ({String id, String title, bool header});

class _ReorderDemoState extends State<ReorderDemo> {
  final List<_Row> _grouped = [
    (id: 'h-today', title: 'Today', header: true),
    for (var i = 1; i <= 6; i++) (id: 't$i', title: 'Task $i', header: false),
    (id: 'h-later', title: 'Later', header: true),
    for (var i = 7; i <= 30; i++) (id: 't$i', title: 'Task $i', header: false),
  ];

  final List<_Row> _plain = [
    for (var i = 1; i <= 40; i++) (id: 'p$i', title: 'Item $i', header: false),
  ];

  void _move(List<_Row> rows, int from, int to) =>
      setState(() => rows.insert(to, rows.removeAt(from)));

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Reorder'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Handles'),
            Tab(text: 'Long press'),
          ],
        ),
      ),
      body: TabBarView(
        physics: const NeverScrollableScrollPhysics(),
        children: [_handles(context), _longPress(context)],
      ),
    ),
  );

  /// Raises the picked up item above the others.
  Widget _lift(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) => AnimatedBuilder(
    animation: animation,
    // Material for any value: items keep their state.
    builder: (context, child) => Material(
      elevation: 8 * animation.value,
      color: Theme.of(context).colorScheme.surface,
      child: child,
    ),
    child: child,
  );

  Widget _handles(BuildContext context) {
    final rows = _grouped;
    return PuskList.separated(
      estimatedExtent: 57,
      itemCount: rows.length,
      itemKey: (index) => rows[index].id,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.header) return _Header(row.title);
        return ListTile(
          title: Text(row.title),
          trailing: const PuskDragStartListener(
            child: Icon(Icons.drag_handle_rounded),
          ),
        );
      },
      separatorBuilder: (context, index) => const Divider(height: 1),
      reorder: PuskReorder(
        // The first header stays first.
        canReorder: (from, to) => to > 0,
        decorator: _lift,
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorderUpdate: (_, _) => HapticFeedback.selectionClick(),
        onReorder: (from, to) => _move(rows, from, to),
      ),
    );
  }

  Widget _longPress(BuildContext context) {
    final rows = _plain;
    return PuskList(
      estimatedExtent: 56,
      itemCount: rows.length,
      itemKey: (index) => rows[index].id,
      itemBuilder: (context, index) => PuskDragStartListener.delayed(
        child: ListTile(
          leading: CircleAvatar(child: Text(rows[index].id.substring(1))),
          title: Text(rows[index].title),
          onTap: () {},
        ),
      ),
      reorder: PuskReorder(
        freeDrag: true,
        decorator: _lift,
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorder: (from, to) => _move(rows, from, to),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
