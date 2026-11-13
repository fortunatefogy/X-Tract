import 'package:flutter/material.dart';

import '../../services/detection_log_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';

class DetectionLogsScreen extends StatelessWidget {
  const DetectionLogsScreen({super.key});

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final service = DetectionLogService.instance;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final entries = service.entries;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      size: 40,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Detection logs',
                              style: AppText.display(30,
                                  color: palette.foreground)),
                          const SizedBox(height: 2),
                          Text(
                            '${entries.length} event${entries.length == 1 ? '' : 's'} recorded',
                            style: AppText.body(13,
                                color: palette.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.delete_sweep_outlined,
                      tooltip: 'Clear logs',
                      color: palette.destructive,
                      onPressed: entries.isEmpty ? null : service.clear,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.radar_rounded,
                      title: 'No detection activity',
                      message:
                          'Extraction and detection events will show up here as you browse.',
                    ),
                  )
                else
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: palette.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.travel_explore_rounded,
                                  size: 19,
                                  color: palette.accentForeground),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${entry.source} · ${entry.event}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body(13,
                                        weight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.url,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body(11,
                                        color: palette.mutedForeground),
                                  ),
                                  if (entry.detail != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.detail!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.body(11,
                                          color: palette.destructive),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _time(entry.time),
                              style: AppText.body(10,
                                  weight: FontWeight.w600,
                                  color: palette.mutedForeground),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
