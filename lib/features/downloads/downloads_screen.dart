import 'package:hugeicons/hugeicons.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/download_service.dart';
import '../../services/shell_navigation.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final Map<String, DateTime> _speedSampledAt = {};
  final Map<String, double> _speedProgress = {};
  final Map<String, double> _speeds = {};

  @override
  void initState() {
    super.initState();
    DownloadService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(_sampleSpeeds);
  }

  void _sampleSpeeds() {
    final now = DateTime.now();
    final running = <String>{};
    for (final record in DownloadService.instance.records
        .where((record) => record.state == DownloadState.running)) {
      running.add(record.taskId);
      final previousProgress = _speedProgress[record.taskId];
      final previousTime = _speedSampledAt[record.taskId];
      if (previousProgress != null &&
          previousTime != null &&
          record.expectedBytes > 0) {
        final seconds = now.difference(previousTime).inMilliseconds / 1000;
        final delta = record.progress - previousProgress;
        if (seconds > 0.2 && delta >= 0) {
          _speeds[record.taskId] = delta * record.expectedBytes / seconds;
        }
      }
      _speedProgress[record.taskId] = record.progress;
      _speedSampledAt[record.taskId] = now;
    }
    _speeds.removeWhere((id, _) => !running.contains(id));
    _speedProgress.removeWhere((id, _) => !running.contains(id));
    _speedSampledAt.removeWhere((id, _) => !running.contains(id));
  }

  Future<void> _openFolder() async {
    final opened = await StorageService.instance.openFolder();
    if (!mounted) return;
    _toast(opened
        ? 'Opening the downloads folder.'
        : 'No file manager could open the downloads folder.');
  }

  Future<void> _moveDownloads() async {
    if (DownloadService.instance.active.isNotEmpty) {
      _toast('Finish or cancel active downloads before moving files.');
      return;
    }
    try {
      final moved = await StorageService.instance.moveExistingDownloads();
      final target = await StorageService.instance.downloadDirectory();
      await DownloadService.instance.relocateDownloads(target.path);
      if (!mounted) return;
      setState(() {});
      _toast(moved == 0
          ? 'No files needed to be moved.'
          : 'Moved $moved file(s) to the current downloads location.');
    } catch (error) {
      _toast('Could not move downloads: $error');
    }
  }

  Future<void> _exportQueue() async {
    final raw = DownloadService.instance.exportQueuedTasks();
    final count = (jsonDecode(raw) as List).length;
    if (count == 0) {
      _toast('No queued downloads to export.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: raw));
    if (!mounted) return;
    _toast('Copied $count queued task(s) to the clipboard.');
  }

  Future<void> _importQueue() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim();
    if (raw == null || raw.isEmpty) {
      _toast('The clipboard does not contain a task list.');
      return;
    }
    try {
      final imported = await DownloadService.instance.importQueuedTasks(raw);
      if (!mounted) return;
      _toast(imported == 0
          ? 'No new tasks were imported.'
          : 'Imported $imported queued task(s).');
    } catch (error) {
      _toast('Could not import the task list: $error');
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _cancelWithConfirm(DownloadRecord record) async {
    final confirmed = await _confirm(
      'Cancel download?',
      '"${record.title}" will stop and be removed from the queue. '
          'Any partial file is discarded.',
    );
    if (confirmed && mounted) {
      DownloadService.instance.cancel(record);
    }
  }

  Future<void> _clearFinishedWithConfirm() async {
    final confirmed = await _confirm(
      'Clear finished downloads?',
      'Completed and failed entries will be removed from this list. '
          'Saved files are kept in your library.',
    );
    if (confirmed && mounted) {
      DownloadService.instance.clearFinished();
    }
  }

  Future<void> _retry(DownloadRecord record) async {
    try {
      await DownloadService.instance.retry(record);
    } catch (error) {
      _toast('Could not retry the download: $error');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatSpeed(double bytesPerSecond) =>
      '${_formatBytes(bytesPerSecond.round())}/s';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final downloads = DownloadService.instance;
    final all = downloads.records;
    final active =
        all.where((record) => record.state.isActive).toList(growable: false);
    final failures = all
        .where((record) =>
            record.state == DownloadState.failed ||
            record.state == DownloadState.canceled)
        .toList(growable: false);
    final completed = all
        .where((record) => record.state == DownloadState.complete)
        .toList(growable: false);

    final overall = active.isEmpty
        ? 0.0
        : active.map((record) => record.progress).reduce((a, b) => a + b) /
            active.length;
    final speed = _speeds.values
        .where((value) => value.isFinite && value > 0)
        .fold<double>(0, (sum, value) => sum + value);
    Duration? remaining;
    for (final record in active) {
      final rate = _speeds[record.taskId];
      if (rate == null || !rate.isFinite || rate <= 0) continue;
      if (record.expectedBytes <= 0) continue;
      final bytesLeft = (record.expectedBytes * (1 - record.progress)).round();
      final eta = Duration(seconds: (bytesLeft / rate).round());
      if (remaining == null || eta > remaining) remaining = eta;
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          key: const PageStorageKey('downloads-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Downloads',
                          style:
                              AppText.display(30, color: palette.foreground)),
                      const SizedBox(height: 2),
                      Text(
                          failures.isEmpty
                              ? '${active.length} active'
                              : '${active.length} active · ${failures.length} need attention',
                          style:
                              AppText.body(12, color: palette.mutedForeground)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Queue tools',
                  icon:
                      HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontal, color: palette.foreground),
                  onSelected: (value) {
                    if (value == 'pauseAll') downloads.pauseAll();
                    if (value == 'resumeAll') downloads.resumeAll();
                    if (value == 'retryAll') downloads.retryAll();
                    if (value == 'clear') _clearFinishedWithConfirm();
                    if (value == 'export') _exportQueue();
                    if (value == 'import') _importQueue();
                    if (value == 'openFolder') _openFolder();
                    if (value == 'move') _moveDownloads();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'pauseAll',
                      enabled: active.any((record) =>
                          record.state == DownloadState.running ||
                          record.state == DownloadState.queued ||
                          record.state == DownloadState.retrying),
                      child: const Text('Pause all'),
                    ),
                    PopupMenuItem(
                      value: 'resumeAll',
                      enabled: active.any(
                          (record) => record.state == DownloadState.paused),
                      child: const Text('Resume all'),
                    ),
                    PopupMenuItem(
                      value: 'retryAll',
                      enabled: failures.isNotEmpty,
                      child: const Text('Retry all failed'),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      enabled: completed.isNotEmpty || failures.isNotEmpty,
                      child: const Text('Clear finished'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'openFolder',
                      child: Text('Open downloads folder'),
                    ),
                    const PopupMenuItem(
                      value: 'move',
                      child: Text('Move downloads'),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: Text('Export queue'),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Text('Import queue'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Progress',
                    value: '${(overall * 100).clamp(0, 100).round()}%',
                    icon: HugeIcons.strokeRoundedTrendingUp,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Speed',
                    value: speed > 0 ? _formatSpeed(speed) : '—',
                    icon: HugeIcons.strokeRoundedZap,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Remaining',
                    value: remaining == null
                        ? '—'
                        : remaining.inMinutes > 0
                            ? '${remaining.inMinutes} min'
                            : '${remaining.inSeconds}s',
                    icon: HugeIcons.strokeRoundedTimer01,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(
                children: [
                  HugeIcon(icon: HugeIcons.strokeRoundedFolder02,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Downloaded files are saved in your Library.',
                      style:
                          AppText.body(12, color: palette.mutedForeground),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ShellNavigation.instance.openTab(2),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _activeSection(active, failures),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _activeSection(
    List<DownloadRecord> active,
    List<DownloadRecord> failures,
  ) {
    if (active.isEmpty && failures.isEmpty) {
      return [
        const SizedBox(height: 24),
        const EmptyState(
          icon: HugeIcons.strokeRoundedDownload04,
          title: 'No active downloads',
          message:
              'Queue media from Home. Finished files are saved in your Library.',
        ),
      ];
    }
    final downloading = active
        .where((record) => record.state == DownloadState.running)
        .toList(growable: false);
    final pending = active
        .where((record) => record.state != DownloadState.running)
        .toList(growable: false);
    return [
      if (downloading.isNotEmpty) ...[
        SectionLabel('Downloading · ${downloading.length}'),
        for (final record in downloading) _transferCard(record),
        const SizedBox(height: 12),
      ],
      if (pending.isNotEmpty) ...[
        SectionLabel('Queued · ${pending.length}'),
        for (final record in pending) _transferCard(record),
        const SizedBox(height: 12),
      ],
      if (failures.isNotEmpty) ...[
        SectionLabel('Needs attention · ${failures.length}'),
        for (final record in failures) _transferCard(record),
      ],
    ];
  }

  Widget _transferCard(DownloadRecord record) {
    final palette = context.palette;
    final canPause = record.state == DownloadState.running;
    final canResume = record.state == DownloadState.paused;
    final canRetry = record.state == DownloadState.failed ||
        record.state == DownloadState.canceled;
    final canCancel = record.state.isActive;
    final failed = record.state == DownloadState.failed;
    final isPaused = record.state == DownloadState.paused ||
        record.state == DownloadState.queued ||
        record.state == DownloadState.retrying;
    final ringColor = failed
        ? palette.destructive
        : isPaused
            ? AppColors.amber
            : AppColors.primary;
    final percent = (record.progress * 100).clamp(0, 100).round();
    final sizeDetail = record.expectedBytes > 0
        ? '${_formatBytes((record.expectedBytes * record.progress).round())} of ${_formatBytes(record.expectedBytes)}'
        : 'Preparing…';
    final rate = _speeds[record.taskId];
    final speedLabel = rate != null && rate.isFinite && rate > 0
        ? ' · ${_formatSpeed(rate)}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(icon: 
                    record.type == 'audio'
                        ? HugeIcons.strokeRoundedMusicNote01
                        : record.type == 'image'
                            ? HugeIcons.strokeRoundedImage01
                            : HugeIcons.strokeRoundedPlayCircle02,
                    color: palette.accentForeground,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(record.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    AppText.body(14, weight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                                record.isLive && record.state.isActive
                                    ? 'LIVE'
                                    : '$percent%',
                                style: AppText.body(11,
                                    weight: FontWeight.w700,
                                    color: palette.accentForeground)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _transferSubtitle(record, sizeDetail, speedLabel),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(12, color: palette.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: record.progress > 0 ? record.progress : null,
                minHeight: 6,
                color: ringColor,
                backgroundColor: palette.muted,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: canPause
                      ? OutlinedButton.icon(
                          onPressed: () =>
                              DownloadService.instance.pause(record),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: palette.secondary,
                            side: BorderSide.none,
                            minimumSize: const Size(0, 44),
                          ),
                          icon: HugeIcon(icon: 
                            record.isLive
                                ? HugeIcons.strokeRoundedStopCircle
                                : HugeIcons.strokeRoundedPause,
                            size: 18,
                          ),
                          label: Text(record.isLive ? 'Stop & save' : 'Pause'),
                        )
                      : canResume || canRetry
                          ? FilledButton.icon(
                              onPressed: canResume
                                  ? () =>
                                      DownloadService.instance.resume(record)
                                  : () => _retry(record),
                              icon: HugeIcon(icon: 
                                canResume
                                    ? HugeIcons.strokeRoundedPlay
                                    : HugeIcons.strokeRoundedRefresh,
                                size: 18,
                              ),
                              label: Text(canResume ? 'Resume' : 'Retry'),
                            )
                          : OutlinedButton.icon(
                              onPressed: null,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: palette.secondary,
                                side: BorderSide.none,
                                minimumSize: const Size(0, 44),
                              ),
                              icon:
                                  const HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 18),
                              label: Text(_stateLabel(record.state)),
                            ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: canCancel
                        ? () => _cancelWithConfirm(record)
                        : () => DownloadService.instance.dismiss(record),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      side: BorderSide(color: palette.border),
                      foregroundColor: palette.destructive,
                      minimumSize: const Size(44, 44),
                    ),
                    child: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(DownloadState state) => switch (state) {
        DownloadState.queued => 'Queued',
        DownloadState.running => 'Downloading',
        DownloadState.paused => 'Paused',
        DownloadState.retrying => 'Retrying',
        DownloadState.complete => 'Completed',
        DownloadState.failed => 'Failed',
        DownloadState.canceled => 'Canceled',
      };

  String _transferSubtitle(
    DownloadRecord record,
    String sizeDetail,
    String speedLabel,
  ) =>
      record.isLive && record.state.isActive
          ? 'Recording live stream… tap Stop & save to finish'
          : switch (record.state) {
              DownloadState.queued => '$sizeDetail · Waiting',
              DownloadState.running => '$sizeDetail$speedLabel',
              DownloadState.paused => '$sizeDetail · Paused',
              DownloadState.retrying => '$sizeDetail · Waiting to retry',
              DownloadState.complete => 'Completed',
              DownloadState.failed => record.error ?? 'Failed',
              DownloadState.canceled => 'Canceled',
            };
}
