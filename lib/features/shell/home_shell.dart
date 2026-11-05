import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../activity/activity_page.dart';
import '../chat/chat_page.dart';
import '../chat/presence_provider.dart';
import '../chat/unread_provider.dart';
import '../me/me_page.dart';
import '../meetings/meetings_page.dart';

/// App shell. On wide screens (desktop/tablet) a collapsible left sidebar
/// (Teams/Slack style, Pulse colours); on phones the familiar bottom nav.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const Color _brand = Color(0xFFF97316);

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _expanded = false;
  // One nested navigator per tab (desktop) so sub-pages open beside the fixed
  // sidebar instead of covering it.
  final List<GlobalKey<NavigatorState>> _navKeys =
      List.generate(4, (_) => GlobalKey<NavigatorState>());

  static const List<Widget> _pages = [
    ChatPage(),
    ActivityPage(),
    MeetingsPage(),
    MePage(),
  ];

  static const List<_NavItem> _items = [
    _NavItem(Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
    _NavItem(Icons.notifications_outlined, Icons.notifications, 'Activity'),
    _NavItem(Icons.videocam_outlined, Icons.videocam, 'Meetings'),
    _NavItem(Icons.person_outline, Icons.person, 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadTotalProvider);
    ref.watch(presenceProvider); // keep presence alive (ping + poll) app-wide
    final wide = MediaQuery.sizeOf(context).width >= 640;
    if (!wide) {
      // Phones keep the bottom nav — a left rail there would be cramped.
      return Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (int i = 0; i < _items.length; i++)
              NavigationDestination(
                icon: _maybeBadge(i, Icon(_items[i].icon), unread),
                selectedIcon:
                    _maybeBadge(i, Icon(_items[i].selectedIcon), unread),
                label: _items[i].label,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          _sidebar(context, unread),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (int i = 0; i < _pages.length; i++)
                  Navigator(
                    key: _navKeys[i],
                    onGenerateRoute: (settings) =>
                        MaterialPageRoute(builder: (_) => _pages[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _maybeBadge(int i, Widget child, int unread) {
    if (i != 0 || unread <= 0) return child;
    return Badge(
      backgroundColor: _brand,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: child,
    );
  }

  Widget _sidebar(BuildContext context, int unread) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: _expanded ? 220 : 68,
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — Pulse orb + name.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFBBF24), _brand],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.graphic_eq,
                      color: Colors.white, size: 18),
                ),
                if (_expanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Pulse',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            color: cs.onSurface),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < _items.length; i++) _navTile(context, i, unread),
          const Spacer(),
          const Divider(height: 1),
          const SizedBox(height: 6),
          _toolTile(
            context,
            _expanded ? Icons.chevron_left : Icons.chevron_right,
            _expanded ? 'Collapse' : 'Expand',
            () => setState(() => _expanded = !_expanded),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _navTile(BuildContext context, int i, int unread) {
    final cs = Theme.of(context).colorScheme;
    final selected = _index == i;
    final it = _items[i];
    final tile = Material(
      color: selected ? _brand.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (i == _index) {
            _navKeys[i].currentState?.popUntil((r) => r.isFirst);
          } else {
            setState(() => _index = i);
          }
        },
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: _expanded ? 14 : 0),
          child: Row(
            mainAxisAlignment:
                _expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              _maybeBadge(
                  i,
                  Icon(selected ? it.selectedIcon : it.icon,
                      size: 22, color: selected ? _brand : cs.outline),
                  unread),
              if (_expanded) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(it.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? _brand : cs.onSurface),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: _expanded ? tile : Tooltip(message: it.label, child: tile),
    );
  }

  Widget _toolTile(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: _expanded ? 14 : 0),
            child: Row(
              mainAxisAlignment:
                  _expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: cs.outline),
                if (_expanded) ...[
                  const SizedBox(width: 14),
                  Text(label,
                      style: TextStyle(fontSize: 13, color: cs.outline)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
