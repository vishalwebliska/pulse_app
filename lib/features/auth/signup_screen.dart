import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'auth_scaffold.dart';

/// Self-service sign-up — Skype-style: just name, email, password, and you're in.
/// No plan selection and no workspace setup; the backend provisions a personal,
/// Pulse-ready workspace behind the scenes.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_busy) return;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your name, email and a password.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters for your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref
        .read(authControllerProvider.notifier)
        .register(name, email, password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // On success the router redirect moves to /home automatically.
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Start chatting and meeting in seconds — no setup needed.',
      footer: AuthSwitchLink(
        prompt: 'Already have an account?',
        actionLabel: 'Sign in',
        onTap: _busy ? null : () => context.go('/login'),
      ),
      children: [
        TextField(
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _createAccount(),
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: 'At least 8 characters',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(_obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_error != null) AuthErrorText(_error!),
        const SizedBox(height: 16),
        AuthPrimaryButton(
            label: 'Create account', busy: _busy, onPressed: _createAccount),
        const SizedBox(height: 14),
        Text(
          'By continuing you agree to the Flaxxa Terms and Privacy Policy.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.outline, fontSize: 11.5, height: 1.4),
        ),
      ],
    );
  }
}
