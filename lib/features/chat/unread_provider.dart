import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Total unread messages across channels + DMs. The Chat tab sets this when it
/// loads conversations; the app shell watches it to badge the Chat nav item.
class UnreadTotal extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

final unreadTotalProvider = NotifierProvider<UnreadTotal, int>(UnreadTotal.new);
