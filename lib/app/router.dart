import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/shell/home_shell.dart';

/// App router. Redirects between the login screen and the main shell based on
/// auth state, and re-evaluates whenever that state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/login',
    redirect: (context, state) {
      // The Google-connect in-app browser returns to the app via the custom
      // scheme flaxxapulse://google/?connected=1. go_router has no GoRoute for
      // it, so without this it renders "Page Not Found". Send any flaxxapulse://
      // deep link into the app — GoogleConnect's own AppLinks listener handles
      // the connected flag separately.
      if (state.uri.scheme == 'flaxxapulse' ||
          state.uri.toString().startsWith('flaxxapulse:')) {
        return ref.read(authControllerProvider).status == AuthStatus.signedIn
            ? '/home'
            : '/login';
      }

      final status = ref.read(authControllerProvider).status;
      if (status == AuthStatus.unknown) return null;

      const authPaths = {'/login', '/signup'};
      final atAuth = authPaths.contains(state.matchedLocation);
      if (status == AuthStatus.signedOut) return atAuth ? null : '/login';
      if (status == AuthStatus.signedIn && atAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (c, s) => const SignupScreen()),
      GoRoute(path: '/home', builder: (c, s) => const HomeShell()),
    ],
  );
});
