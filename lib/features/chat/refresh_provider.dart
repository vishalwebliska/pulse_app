import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A monotonic counter bumped when the user taps the sidebar refresh button.
/// Pages (e.g. the Chat list) watch it and reload their data on change.
class RefreshTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final refreshTickProvider = NotifierProvider<RefreshTick, int>(RefreshTick.new);
