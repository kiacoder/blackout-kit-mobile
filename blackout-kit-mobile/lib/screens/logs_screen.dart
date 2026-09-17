import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

import '../services/debug_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({Key? key}) : super(key: key);

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late final DebugService _debugService;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _filterLevel = 'all'; // all, info, warning, error, debug
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _debugService = Get.find<DebugService>();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<LogEntry> _getFilteredLogs() {
    final allLogs = _debugService.logEntries;

    return allLogs.where((log) {
      // Level filter
      if (_filterLevel != 'all') {
        final levelStr = log.levelName.toLowerCase();
        if (_filterLevel == 'info' && levelStr != 'info') return false;
        if (_filterLevel == 'warning' && levelStr != 'warning' && levelStr != 'warn') return false;
        if (_filterLevel == 'error' && levelStr != 'error') return false;
        if (_filterLevel == 'debug' && levelStr != 'debug') return false;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final msg = log.message.toLowerCase();
        final time = log.formattedTime.toLowerCase();
        final lvl = log.levelName.toLowerCase();
        if (!msg.contains(_searchQuery) &&
            !time.contains(_searchQuery) &&
            !lvl.contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Color _getLevelColor(Level level, bool isDark) {
    switch (level) {
      case Level.error:
        return Colors.red;
      case Level.warning:
        return Colors.amber.shade700;
      case Level.info:
        return isDark ? Colors.cyan.shade300 : Colors.blue.shade700;
      case Level.debug:
        return Colors.purple.shade300;
      default:
        return isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Logs'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy all logs',
            onPressed: () {
              final text = _debugService.exportLogsAsText();
              Clipboard.setData(ClipboardData(text: text));
              Get.snackbar(
                'Copied',
                'System logs copied to clipboard',
                backgroundColor: Colors.green,
                colorText: Colors.white,
                duration: const Duration(seconds: 2),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () async {
              final confirm = await Get.dialog<bool>(
                AlertDialog(
                  title: const Text('Clear Logs?'),
                  content: const Text('Are you sure you want to clear the in-memory log buffer?'),
                  actions: [
                    TextButton(
                      onPressed: () => Get.back(result: false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Get.back(result: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                _debugService.clearLogs();
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter controls
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? theme.cardColor : Colors.grey.shade100,
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search logs...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildLevelChip('All', 'all'),
                      _buildLevelChip('Info', 'info'),
                      _buildLevelChip('Warning', 'warning'),
                      _buildLevelChip('Error', 'error'),
                      _buildLevelChip('Debug', 'debug'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Log List
          Expanded(
            child: Obx(() {
              final logs = _getFilteredLogs();

              if (logs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.article_outlined, size: 64, color: theme.disabledColor),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No logs matching "$_searchQuery"'
                            : 'No log entries recorded',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: logs.length,
                separatorBuilder: (context, index) => const Divider(height: 1, thickness: 0.5),
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final levelColor = _getLevelColor(log.level, isDark);

                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: levelColor.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: levelColor, width: 0.8),
                              ),
                              child: Text(
                                log.levelName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: levelColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              log.formattedTime,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          log.message,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: isDark ? Colors.grey.shade200 : Colors.black87,
                          ),
                        ),
                        if (log.stackTrace != null && log.stackTrace!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black45 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: SelectableText(
                              log.stackTrace!,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Colors.red.shade300,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        tooltip: 'Scroll to bottom',
        child: const Icon(Icons.arrow_downward),
      ),
    );
  }

  Widget _buildLevelChip(String label, String value) {
    final selected = _filterLevel == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (bool isSelected) {
          if (isSelected) {
            setState(() {
              _filterLevel = value;
            });
          }
        },
      ),
    );
  }
}
