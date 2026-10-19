import 'dart:async';
import 'dart:math';

import 'package:example/chat_data.dart';
import 'package:example/chat_scope.dart';
import 'package:example/message_tile.dart';
import 'package:example/perf_hud.dart';
import 'package:flutter/material.dart';
import 'package:pusk_list/pusk_list.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5B5BD6),
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: 'pusk_list',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _generator = ChatGenerator();
  late final _chat = ChatModel(_generator.older(1000));
  final _controller = PuskListController();
  final _input = TextEditingController();
  final _random = Random(3);

  final ValueNotifier<int> _unread = ValueNotifier(0);
  FrameStats? _stats;
  final _timers = <Timer>{};

  @override
  void initState() {
    super.initState();
    _controller.visibleRange.addListener(_onVisibleRangeChanged);
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _controller.visibleRange.removeListener(_onVisibleRangeChanged);
    _controller.dispose();
    _chat.dispose();
    _unread.dispose();
    _input.dispose();
    _stats?.dispose();
    super.dispose();
  }

  bool get _atLatest => (_controller.visibleRange.value?.first ?? 0) == 0;

  void _onVisibleRangeChanged() {
    if (_atLatest) _unread.value = 0;
  }

  void _later(Duration delay, VoidCallback callback) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (mounted) callback();
    });
    _timers.add(timer);
  }

  void _receive(Message message) {
    _chat.add(message);
    if (!_atLatest) _unread.value++;
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _chat.add(_generator.mine(text));
    if (!_atLatest) _scrollToLatest();
  }

  /// Many incoming messages in quick succession.
  void _burst() {
    for (var i = 0; i < 20; i++) {
      _later(Duration(milliseconds: 120 * i), () {
        _receive(_generator.incoming());
      });
    }
  }

  void _toggleStats() {
    setState(() {
      _stats?.dispose();
      _stats = _stats == null ? FrameStats() : null;
    });
  }

  void _scrollToLatest() {
    unawaited(
      _controller.animateToIndex(
        0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Animates to a message far away, through items that were never laid
  /// out, and highlights it.
  Future<void> _jumpToRandom() async {
    final messages = _chat.messages;
    final message = messages[_random.nextInt(messages.length)];
    await _controller.animateToKey(
      message,
      alignment: 0.5,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
    final highlighted = _chat.highlighted..value = message.id;
    _later(const Duration(milliseconds: 1200), () {
      if (highlighted.value == message.id) highlighted.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChatScope(
      chat: _chat,
      controller: _controller,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: _ChatAppBar(
          onJump: _jumpToRandom,
          onBurst: _burst,
          statsVisible: _stats != null,
          onToggleStats: _toggleStats,
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  const _ChatList(),
                  if (_stats case final stats?)
                    Positioned(top: 8, right: 8, child: PerfHud(stats: stats)),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    // Listens by itself: scrolling doesn't rebuild the list.
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        _controller.visibleRange,
                        _unread,
                      ]),
                      builder: (context, _) => _ScrollToLatestButton(
                        visible: !_atLatest,
                        unread: _unread.value,
                        onPressed: _scrollToLatest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _Composer(controller: _input, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({
    required this.onJump,
    required this.onBurst,
    required this.statsVisible,
    required this.onToggleStats,
  });

  final VoidCallback onJump;
  final VoidCallback onBurst;
  final bool statsVisible;
  final VoidCallback onToggleStats;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      titleSpacing: 0,
      leading: const Padding(
        padding: EdgeInsets.all(10),
        child: CircleAvatar(child: Icon(Icons.forum_rounded, size: 20)),
      ),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text('Team chat'), _MessageCount()],
      ),
      actions: [
        IconButton(
          tooltip: 'Jump to a random message',
          icon: const Icon(Icons.shuffle_rounded),
          onPressed: onJump,
        ),
        PopupMenuButton<VoidCallback>(
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: onBurst,
              child: const ListTile(
                leading: Icon(Icons.bolt_rounded),
                title: Text('Burst of 20 messages'),
              ),
            ),
            const PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: onToggleStats,
              checked: statsVisible,
              child: const Text('Frame stats'),
            ),
          ],
        ),
      ],
    );
  }
}

class _MessageCount extends StatelessWidget {
  const _MessageCount();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '${ChatScope.of(context).chat.messages.length} messages',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList();

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final chat = scope.chat;
    final messages = chat.messages;
    return PuskList.separated(
      controller: scope.controller,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 12),
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length,
      itemKey: (index) => messages[index],
      estimatedExtent: 64,
      transition: const PuskItemTransition.sizeFade(),
      itemBuilder: (context, index) {
        final message = messages[index];
        return MessageTile(
          message: message,
          highlighted: chat.highlighted,
          onLongPress: () => chat.remove(message),
        );
      },
      separatorBuilder: (context, index) => MessageSeparator(
        newer: messages[index],
        older: messages[index + 1],
      ),
    );
  }
}

class _ScrollToLatestButton extends StatelessWidget {
  const _ScrollToLatestButton({
    required this.visible,
    required this.unread,
    required this.onPressed,
  });

  final bool visible;
  final int unread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: FloatingActionButton.small(
          heroTag: null,
          onPressed: onPressed,
          child: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: onSend,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
