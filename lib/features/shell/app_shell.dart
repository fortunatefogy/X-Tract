import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/download_service.dart';
import '../../services/shell_navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
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
  final Set<int> _loaded = {0};

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
    _openTab(requested);
  }

  void _openTab(int index) {
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = index;
      _loaded.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedTabView(
        index: _index,
        children: [
          _loaded.contains(0)
              ? HomeScreen(onOpenTab: _openTab)
              : const SizedBox.shrink(),
          _loaded.contains(1)
              ? const DownloadsScreen()
              : const SizedBox.shrink(),
          _loaded.contains(2) ? const LibraryScreen() : const SizedBox.shrink(),
          _loaded.contains(3)
              ? const SettingsScreen()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: LinkyBottomBar(
        index: _index,
        onTap: _openTab,
      ),
    );
  }
}

class LinkyBottomBar extends StatefulWidget {
  const LinkyBottomBar({
    super.key,
    required this.index,
    required this.onTap,
  });

  final int index;
  final ValueChanged<int> onTap;

  @override
  State<LinkyBottomBar> createState() => _LinkyBottomBarState();
}

class _LinkyBottomBarState extends State<LinkyBottomBar> {
  @override
  void initState() {
    super.initState();
    DownloadService.instance.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.download_outlined, Icons.download_rounded, 'Downloads'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Library'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activeDownloads = DownloadService.instance.active.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.border),
            boxShadow: AppShadow.floating,
          ),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: _items[i].$1,
                    activeIcon: _items[i].$2,
                    label: _items[i].$3,
                    selected: widget.index == i,
                    badge: i == 1 ? activeDownloads : 0,
                    onTap: () => widget.onTap(i),
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
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? AppColors.primary : palette.mutedForeground;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0
          ? '$label, $badge active download${badge == 1 ? '' : 's'}'
          : label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.inner),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected ? palette.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      selected ? activeIcon : icon,
                      size: 19,
                      color: color,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -4,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: palette.card, width: 1.5),
                        ),
                        child: Text(
                          '$badge',
                          style: AppText.body(9,
                              weight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppText.body(
                  10,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
