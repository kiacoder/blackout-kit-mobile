/// Config tile widget - displays a single VPN config in a list
/// Shows protocol, address, speed, reliability, and actions

import 'package:flutter/material.dart';
import '../models/config.dart';
import '../models/test_result.dart';

class ConfigTile extends StatelessWidget {
  final Config config;
  final TestResult? testResult;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;
  final VoidCallback? onDelete;

  const ConfigTile({
    Key? key,
    required this.config,
    this.testResult,
    this.onTap,
    this.onConnect,
    this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isWorking = testResult?.isWorking ?? false;
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
                        Row(
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isWorking
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isWorking ? '✓ Working' : '✗ Failed',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isWorking
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
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
                                  'Not Tested',
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
                  if (onConnect != null)
                    SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: onConnect,
                        icon: const Icon(Icons.vpn_lock, size: 14),
                        label: const Text('Connect'),
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
                        label: const Text('Delete'),
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
