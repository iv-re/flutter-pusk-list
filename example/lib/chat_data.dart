import 'dart:math';

import 'package:flutter/material.dart';

class Author {
  const Author(this.name, this.color);

  final String name;
  final Color color;

  bool get isMe => identical(this, me);

  static const me = Author('Me', Colors.indigo);
  static const others = [
    Author('Anna', Color(0xFFE57373)),
    Author('Leo', Color(0xFF4DB6AC)),
    Author('Mia', Color(0xFFFFB74D)),
    Author('Oscar', Color(0xFF9575CD)),
  ];
}

class Message {
  Message({
    required this.id,
    required this.author,
    required this.text,
    required this.time,
  });

  final String id;
  final Author author;
  final DateTime time;
  final String text;
}

/// Generates a believable chat history, newest first.
class ChatGenerator {
  ChatGenerator() : _oldest = DateTime.now();

  final _random = Random(7);
  var _nextId = 0;
  DateTime _oldest;

  static const List<String> _phrases = [
    'Hey! How is it going?',
    'Sounds good 👍',
    'I will be there in 10 minutes',
    'Did you see the new release notes?',
    'Haha, exactly',
    'Can we move the call to tomorrow?',
    'Sure, no problem',
    'Just pushed the fix, could you take a look when you have a minute?',
    'Lunch?',
    _long0,
    'ok',
    'Thanks!',
    'Let me check and get back to you',
    _long1,
    'Agreed',
    'What time works for you?',
    'Morning is better for me',
    '🎉🎉🎉',
    'Nice, that is way better than before',
    'Could you send me the link?',
    _long2,
    'On my way',
    'Good night!',
    'See you tomorrow',
  ];

  String _phrase() => _phrases[_random.nextInt(_phrases.length)];

  String _id() => 'm${_nextId++}';

  /// [count] messages older than everything generated so far, newest first.
  List<Message> older(int count) {
    final result = <Message>[];
    for (var i = 0; i < count; i++) {
      final gap = _random.nextDouble() < 0.15
          ? Duration(hours: 2 + _random.nextInt(14))
          : Duration(seconds: 20 + _random.nextInt(600));
      _oldest = _oldest.subtract(gap);
      result.add(
        Message(
          id: _id(),
          author: _randomAuthor(),
          text: _phrase(),
          time: _oldest,
        ),
      );
    }
    return result;
  }

  Message mine(String text) =>
      Message(id: _id(), author: Author.me, text: text, time: DateTime.now());

  Message incoming() => Message(
    id: _id(),
    author: Author.others[_random.nextInt(Author.others.length)],
    text: _phrase(),
    time: DateTime.now(),
  );

  Author _randomAuthor() => _random.nextDouble() < 0.4
      ? Author.me
      : Author.others[_random.nextInt(Author.others.length)];
}

const _long0 =
    'The list finally scrolls smoothly on Android, even with heavy tiles '
    'and transitions turned on. Measured build p99 went from 45 ms to '
    'around 13 ms on a Pixel 9.';
const _long1 =
    'I think the problem is that every insert recreates the visible items, '
    'so anything expensive in initState runs again and again.';
const _long2 =
    'Anchoring is the tricky part: when items above the viewport change '
    'size, the visible ones must not move at all.';

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String formatDay(DateTime day) {
  final now = DateTime.now();
  if (isSameDay(day, now)) return 'Today';
  if (isSameDay(day, now.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  final date =
      '${_weekdays[day.weekday - 1]}, ${day.day} '
      '${_months[day.month - 1]}';
  return day.year == now.year ? date : '$date ${day.year}';
}

String formatTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
