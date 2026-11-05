import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_repository.dart';

/// The set of online user ids for the current workspace. While it's alive
/// (watched by the app shell) it polls `GET /presence/online` and sends
/// `POST /presence/ping` heartbeats every 30s so the current user shows online.
class PresenceOnline extends Notifier<Set<int>> {
  Timer? _timer;

  @override
  Set<int> build() {
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    ref.onDispose(() => _timer?.cancel());
    return const {};
  }

  Future<void> _tick() async {
    try {
      await ChatRepository.instance.pingPresence();
      final ids = await ChatRepository.instance.onlineUserIds();
      state = ids;
    } catch (_) {
      // Best-effort; presence dots just won't update on a transient failure.
    }
  }
}

final presenceProvider =
    NotifierProvider<PresenceOnline, Set<int>>(PresenceOnline.new);
