/// Config tile widget - displays a single VPN config in a list
/// Shows protocol, address, speed, reliability, and actions

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/config.dart';
import '../models/test_result.dart';

class ConfigTile extends StatelessWidget {
  final Config config;
  final TestResult? testResult;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;

  /// Non-null when this build has no engine for the protocol. The Connect
  /// button is then rendered disabled and the reason is shown inline, instead
  /// of letting the tap fail with a red "Connection Failed" banner.
  final String? connectBlockedReason;
  final VoidCallback? onDelete;

  const ConfigTile({
    Key? key,
    required this.config,
    this.testResult,
    this.onTap,
    this.onConnect,
    this.connectBlockedReason,
    this.onDelete,
  }) : super(key: key);

  static String _badgeLabel(TestStatus status) => switch (status) {
        TestStatus.success => '✓ Working'.tr,
        TestStatus.failed => '✗ Failed'.tr,
        TestStatus.timeout => '⏱ Timeout'.tr,
        TestStatus.testing => 'Testing…',
        TestStatus.notTested => 'Not tested'.tr,
      };

  static Color _badgeBackground(TestStatus status) => switch (status) {
        TestStatus.success => Colors.green.shade100,
        TestStatus.failed => Colors.red.shade100,
        TestStatus.timeout => Colors.orange.shade100,
        TestStatus.testing => Colors.blue.shade100,
        TestStatus.notTested => Colors.grey.shade200,
      };

  static Color _badgeForeground(TestStatus status) => switch (status) {
        TestStatus.success => Colors.green.shade700,
        TestStatus.failed => Colors.red.shade700,
        TestStatus.timeout => Colors.orange.shade800,
        TestStatus.testing => Colors.blue.shade700,
        TestStatus.notTested => Colors.grey.shade700,
      };

  @override
  Widget build(BuildContext context) {
    final hasResult = testResult != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Name, Protocol Badge, Status
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Wrap, not Row: the protocol chip plus the status chip
                        // are fixed width, and on a 320 dp screen (or with the
                        // system text scaled up) a Row overflows the tile.
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getProtocolColor(config.protocol),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                config.protocol.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (hasResult)
                              // Five states, not two. A config that was never
                              // tested (or is mid-test) used to render as
                              // "Failed", which is how a perfectly working
                              // tunnel ended up labelled a failure in the
                              // library.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _badgeBackground(testResult!.status),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _badgeLabel(testResult!.status),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _badgeForeground(testResult!.status),
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Not Tested'.tr,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Speed badge if available
                  if (testResult?.speedMbps != null)
                    Tooltip(
                      message: '${testResult!.speedMbps!.toStringAsFixed(1)} Mbps',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getSpeedColor(testResult!.speedMbps!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${testResult!.speedMbps!.toStringAsFixed(0)} ⚡',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Address info
              Text(
                '${config.address}:${config.port}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (connectBlockedReason != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 12, color: Colors.orange.shade300),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        connectBlockedReason!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (hasResult) ...[
                const SizedBox(height: 8),
                // Test metrics row
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            testResult!.latencyMs != null
                                ? '${testResult!.latencyMs}ms'
                                : 'N/A',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.trending_up,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${testResult!.reliability.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onConnect != null || connectBlockedReason != null)
                    SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        // A disabled button that says nothing is worse than a
                        // working one: keep the label, drop the action.
                        onPressed:
                            connectBlockedReason == null ? onConnect : null,
                        icon: Icon(
                          connectBlockedReason == null
                              ? Icons.vpn_lock
                              : Icons.block,
                          size: 14,
                        ),
                        label: Text('connect'.tr),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (onDelete != null)
                    SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete, size: 14),
                        label: Text('delete'.tr),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getProtocolColor(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'wireguard':
        return const Color(0xFF1E88E5); // Blue
      case 'openvpn':
        return const Color(0xFFEA4335); // Red
      case 'shadowsocks':
        return const Color(0xFF34A853); // Green
      case 'v2ray':
        return const Color(0xFFFBBC04); // Yellow
      case 'trojan':
        return const Color(0xFF9C27B0); // Purple
      case 'naiveproxy':
        return const Color(0xFFFF6D00); // Orange
      default:
        return Colors.grey;
    }
  }

  Color _getSpeedColor(double speedMbps) {
    if (speedMbps >= 50) return Colors.green;
    if (speedMbps >= 20) return Colors.orange;
    return Colors.red;
  }
}
