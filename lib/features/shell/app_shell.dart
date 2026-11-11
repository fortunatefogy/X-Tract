import 'package:flutter/material.dart';

import '../../services/shell_navigation.dart';
import '../../theme/app_theme.dart';
import '../downloads/downloads_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    ShellNavigation.instance.requestedTab.addListener(_handleRequestedTab);
  }

  @override
  void dispose() {
    ShellNavigation.instance.requestedTab.removeListener(_handleRequestedTab);
    super.dispose();
  }

  void _handleRequestedTab() {
    final requested = ShellNavigation.instance.requestedTab.value;
    if (requested == null || !mounted) return;
    ShellNavigation.instance.consume();
    setState(() => _index = requested);
  }

  void _openTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onOpenTab: _openTab),
          const DownloadsScreen(),
          const LibraryScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: LinkyBottomBar(
        index: _index,
        onTap: _openTab,
      ),
    );
  }
}

class LinkyBottomBar extends StatelessWidget {
  const LinkyBottomBar({
    super.key,
    required this.index,
    required this.onTap,
  });

  final int index;
  final ValueChanged<int> onTap;

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.download_outlined, Icons.download_rounded, 'Downloads'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Library'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: _items[i].$1,
                    activeIcon: _items[i].$2,
                    label: _items[i].$3,
                    selected: index == i,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? AppColors.primary : palette.mutedForeground;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.inner),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: selected ? 1 : 0),
              duration: const Duration(milliseconds: 180),
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, -2 * t),
                child: child,
              ),
              child: Icon(
                selected ? activeIcon : icon,
                size: 24,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppText.body(
                11,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
