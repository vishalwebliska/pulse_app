import 'package:flutter/material.dart';

/// Shared, professional auth chrome for sign-in / sign-up — Teams/Skype style.
///
/// Phones: a centered, scrollable single column with the Flaxxa wordmark on top.
/// Wide screens (tablet/desktop): a split layout — an orange Pulse brand panel on
/// the left, the form on the right. Flaxxa-branded throughout.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;

  static const brand = Color(0xFFF97316);
  static const brandDeep = Color(0xFFEA580C);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;

    final form = _AuthForm(
      title: title,
      subtitle: subtitle,
      footer: footer,
      showWordmark: !wide, // on wide screens the brand panel carries the identity
      children: children,
    );

    if (!wide) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: form,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          const Expanded(child: _BrandPanel()),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: form,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.showWordmark,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showWordmark;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showWordmark) ...[
          const Center(child: FlaxxaWordmark(height: 34)),
          const SizedBox(height: 28),
        ],
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: cs.outline, height: 1.4)),
        const SizedBox(height: 28),
        ...children,
        if (footer != null) ...[
          const SizedBox(height: 24),
          Center(child: footer!),
        ],
      ],
    );
  }
}

/// The left brand panel on wide layouts: an orange gradient with the Pulse promise.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuthScaffold.brand, AuthScaffold.brandDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FlaxxaWordmark(height: 30, onDark: true),
            const SizedBox(height: 40),
            const Text(
              'Pulse',
              style: TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Team chat, calls and meetings —\nall in one place.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 18,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            ..._features.map(_feature),
          ],
        ),
      ),
    );
  }

  static const _features = [
    (Icons.chat_bubble_outline, 'Message anyone, instantly'),
    (Icons.videocam_outlined, 'Start a call or meeting in a tap'),
    (Icons.group_outlined, 'Bring your contacts along'),
  ];

  Widget _feature((IconData, String) f) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Icon(f.$1, color: Colors.white, size: 22),
            const SizedBox(width: 14),
            Text(
              f.$2,
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
            ),
          ],
        ),
      );
}

/// The Flaxxa wordmark, theme-aware (white on dark surfaces / the brand panel).
class FlaxxaWordmark extends StatelessWidget {
  const FlaxxaWordmark({super.key, this.height = 34, this.onDark = false});

  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? 'assets/images/flaxxa-logo-neg.png' : 'assets/images/flaxxa-logo.png',
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
    );
  }
}

/// Full-width primary action with an inline busy spinner.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Inline, dismissable-looking error line under the fields.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: cs.error, fontSize: 13.5, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// "New to Pulse? Create account" style switch link under the form.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.prompt,
    required this.actionLabel,
    required this.onTap,
  });

  final String prompt;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prompt, style: TextStyle(color: cs.outline)),
        TextButton(
          onPressed: onTap,
          child: Text(actionLabel,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
