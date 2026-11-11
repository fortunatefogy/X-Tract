import 'package:flutter/material.dart';

import '../../services/shell_navigation.dart';
import '../../services/shared_link_channel.dart';
import '../shell/app_shell.dart';
import 'share_popup_screen.dart';

class ShareHost extends StatefulWidget {
  const ShareHost({
    super.key,
    this.startInShareMode = false,
    this.initialText,
  });

  final bool startInShareMode;
  final String? initialText;

  @override
  State<ShareHost> createState() => _ShareHostState();
}

class _ShareHostState extends State<ShareHost> with WidgetsBindingObserver {
  late final SharedLinkChannel _channel;
  late bool _shareMode = widget.startInShareMode;
  late String? _text = widget.initialText;
  bool _minimizedAfterDownload = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel = SharedLinkChannel(listen: true);
    _channel.onSharedText = _handleSharedText;
    _channel.onLaunchModeChanged = _handleLaunchModeChanged;
    _channel.onOpenDownloads = _handleOpenDownloads;
    _channel.onAppHidden = _handleAppHidden;
    if (_shareMode) _notifyReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_shareMode) return;
    if (_minimizedAfterDownload) {
      setState(() {
        _minimizedAfterDownload = false;
        _shareMode = false;
      });
      return;
    }
    _notifyReady();
  }

  void _notifyReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shareMode) SharedLinkChannel.shareReady();
    });
  }

  void _handleSharedText(String text) {
    if (!mounted) return;
    setState(() {
      _shareMode = true;
      _hidden = false;
      _text = text;
    });
    _notifyReady();
  }

  void _handleLaunchModeChanged(bool shareMode) {
    if (!mounted) return;
    if (shareMode && _shareMode) {
      if (_hidden) setState(() => _hidden = false);
      _notifyReady();
      return;
    }
    setState(() {
      _shareMode = shareMode;
      _hidden = false;
      _minimizedAfterDownload = false;
    });
    if (shareMode) _notifyReady();
  }

  void _handleAppHidden(bool hidden) {
    if (!mounted || _hidden == hidden) return;
    setState(() => _hidden = hidden);
  }

  void _handleOpenDownloads(bool _) {
    if (_shareMode) setState(() => _shareMode = false);
    setState(() => _hidden = false);
    ShellNavigation.instance.openTab(1);
  }

  Future<void> _closePopup() async {
    await SharedLinkChannel.closePopup();
  }

  Future<void> _minimizeAfterDownload(int _) async {
    setState(() => _minimizedAfterDownload = true);
    await SharedLinkChannel.minimizePopup();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden && !_shareMode) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.expand(),
      );
    }
    if (!_shareMode) return const AppShell();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SharePopupScreen(
        initialText: _text,
        onClose: _closePopup,
        onDownloadQueued: _minimizeAfterDownload,
      ),
    );
  }
}
