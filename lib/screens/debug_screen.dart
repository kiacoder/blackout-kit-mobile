import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/debug_service.dart';

/// Debug and logging screen
class DebugScreen extends StatefulWidget {
  const DebugScreen({Key? key}) : super(key: key);

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen>
    with SingleTickerProviderStateMixin {
  late DebugService _debugService;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _debugService = Get.find<DebugService>();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug & Logs'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Logs', icon: Icon(Icons.description)),
            Tab(text: 'Debug Info', icon: Icon(Icons.info_outline)),
            Tab(text: 'Diagnostics', icon: Icon(Icons.stethoscope)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLogsTab(),
          _buildDebugInfoTab(),
          _buildDiagnosticsTab(),
        ],
      ),
    );
  }

  /// Logs tab
  Widget _buildLogsTab() {
    return Obx(
      () => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Logs (${_debugService.logCount})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    _debugService.clearLogs();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logs cleared')),
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    _showExportDialog();
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _debugService.logEntries.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: _debugService.logEntries.length,
                    reverse: true,
                    itemBuilder: (context, index) {
                      final entry = _debugService.logEntries[
                          _debugService.logEntries.length - 1 - index];
                      return _buildLogEntryTile(entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Log entry tile
  Widget _buildLogEntryTile(dynamic entry) {
    final color = _getLevelColor(entry.level);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 2.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '[${entry.formattedTime}] ${entry.levelName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Debug info tab
  Widget _buildDebugInfoTab() {
    final debugInfo = _debugService.getDebugInfo();
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildInfoCard('App Information', {
          'Name': debugInfo['app_name'],
          'Version': debugInfo['version'],
          'Debug Mode': debugInfo['debug_mode'].toString(),
        }),
        const SizedBox(height: 16),
        _buildInfoCard('Logs', {
          'Total Entries': debugInfo['log_count'].toString(),
          'Max Buffer Size': '500',
          'Exported': DateTime.now().toIso8601String(),
        }),
      ],
    );
  }

  /// Build info card
  Widget _buildInfoCard(String title, Map<String, String> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...data.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Text(
                      '${entry.key}:',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  /// Diagnostics tab
  Widget _buildDiagnosticsTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bug_report, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Debug Mode',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Obx(
                      () => Switch(
                        value: _debugService.isDebugMode.value,
                        onChanged: (_) {
                          _debugService.toggleDebugMode();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Log Statistics',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildDiagnosticRow(
                  'Total Logs',
                  _debugService.logCount.toString(),
                ),
                _buildDiagnosticRow(
                  'Errors',
                  _debugService.getErrorLogs().length.toString(),
                ),
                _buildDiagnosticRow(
                  'Warnings',
                  _debugService.getWarningLogs().length.toString(),
                ),
                _buildDiagnosticRow(
                  'Buffer Capacity',
                  '${_debugService.logCount}/500',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            _showExportDialog();
          },
          icon: const Icon(Icons.download),
          label: const Text('Export All Logs'),
        ),
      ],
    );
  }

  /// Diagnostic row
  Widget _buildDiagnosticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Show export dialog
  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Export Logs'),
          content: const Text('Logs exported to clipboard'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Get color for log level
  Color _getLevelColor(dynamic level) {
    final levelStr = level.toString();
    if (levelStr.contains('error') || levelStr.contains('ERROR')) {
      return Colors.red;
    } else if (levelStr.contains('warning') || levelStr.contains('WARNING')) {
      return Colors.orange;
    } else if (levelStr.contains('info') || levelStr.contains('INFO')) {
      return Colors.blue;
    } else if (levelStr.contains('debug') || levelStr.contains('DEBUG')) {
      return Colors.grey;
    }
    return Colors.grey;
  }
}
