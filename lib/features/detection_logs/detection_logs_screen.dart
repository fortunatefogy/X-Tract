import 'package:flutter/material.dart';

import '../../services/detection_log_service.dart';

class DetectionLogsScreen extends StatelessWidget {
  const DetectionLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DetectionLogService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection logs'),
        actions: [
          IconButton(
            tooltip: 'Clear logs',
            onPressed: service.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final entries = service.entries;
          if (entries.isEmpty) {
            return const Center(
              child: Text('No detection activity yet.'),
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final time = entry.time;
              final label =
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
              return ListTile(
                dense: true,
                title: Text('${entry.source} · ${entry.event}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.detail != null)
                      Text(
                        entry.detail!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.red.shade400),
                      ),
                  ],
                ),
                trailing: Text(label),
              );
            },
          );
        },
      ),
    );
  }
}
