import 'package:example/chat_data.dart';
import 'package:flutter/widgets.dart';
import 'package:pusk_list/pusk_list.dart';

/// Messages of the chat, newest first.
class ChatModel extends ChangeNotifier {
  ChatModel(this.messages);

  final List<Message> messages;

  /// Id of the message to highlight.
  final highlighted = ValueNotifier<String?>(null);

  void add(Message message) {
    messages.insert(0, message);
    notifyListeners();
  }

  void remove(Message message) {
    messages.remove(message);
    notifyListeners();
  }

  @override
  void dispose() {
    highlighted.dispose();
    super.dispose();
  }
}

/// Provides the chat to the widgets below, so they rebuild by themselves
/// when it changes.
class ChatScope extends InheritedNotifier<ChatModel> {
  const ChatScope({
    required ChatModel chat,
    required this.controller,
    required super.child,
    super.key,
  }) : super(notifier: chat);

  final PuskListController controller;

  ChatModel get chat => notifier!;

  /// Rebuilds the caller when the chat changes.
  static ChatScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatScope>()!;

  /// Doesn't rebuild the caller: for callbacks.
  static ChatScope read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatScope>()!;
}
