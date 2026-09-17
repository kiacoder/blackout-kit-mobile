import 'package:flutter/material.dart' hide ConnectionState;
import '../controllers/connection_controller.dart';

/// Animated status indicator with smooth transitions
class AnimatedStatusIndicator extends StatefulWidget {
  final ConnectionState state;
  final String statusMessage;

  const AnimatedStatusIndicator({
    Key? key,
    required this.state,
    required this.statusMessage,
  }) : super(key: key);

  @override
  State<AnimatedStatusIndicator> createState() =>
      _AnimatedStatusIndicatorState();
}

class _AnimatedStatusIndicatorState extends State<AnimatedStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();
  }

  @override
  void didUpdateWidget(AnimatedStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _fadeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Color _getStatusColor() {
    switch (widget.state) {
      case ConnectionState.connected:
        return Colors.green;
      case ConnectionState.connecting:
      case ConnectionState.selecting:
      case ConnectionState.testing:
        return Colors.orange;
      case ConnectionState.disconnecting:
        return Colors.grey;
      case ConnectionState.error:
        return Colors.red;
      case ConnectionState.idle:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.state) {
      case ConnectionState.connected:
        return Icons.check_circle;
      case ConnectionState.connecting:
      case ConnectionState.selecting:
      case ConnectionState.testing:
        return Icons.hourglass_top;
      case ConnectionState.disconnecting:
        return Icons.link_off;
      case ConnectionState.error:
        return Icons.error;
      case ConnectionState.idle:
        return Icons.cloud_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _getStatusColor().withOpacity(0.1),
          border: Border.all(
            color: _getStatusColor().withOpacity(0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _getStatusIcon(),
              color: _getStatusColor(),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.statusMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
