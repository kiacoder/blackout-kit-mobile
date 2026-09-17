import 'package:flutter/material.dart';

/// Animated connection button with state-based visuals
class AnimatedConnectionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isConnected;
  final bool isLoading;

  const AnimatedConnectionButton({
    Key? key,
    required this.onPressed,
    required this.isConnected,
    required this.isLoading,
  }) : super(key: key);

  @override
  State<AnimatedConnectionButton> createState() =>
      _AnimatedConnectionButtonState();
}

class _AnimatedConnectionButtonState extends State<AnimatedConnectionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * 3.14159).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );

    if (widget.isLoading) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedConnectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !oldWidget.isLoading) {
      _animationController.repeat();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = widget.isConnected
        ? Colors.green
        : (widget.isLoading ? Colors.orange : Colors.blue);
    final buttonLabel = widget.isConnected
        ? 'Disconnect'
        : (widget.isLoading ? 'Connecting...' : 'Connect');

    return ScaleTransition(
      scale: widget.isLoading ? _scaleAnimation : AlwaysStoppedAnimation(1.0),
      child: GestureDetector(
        onTapDown: (_) {
          if (!widget.isLoading) {
            _animationController.forward(from: 0);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: buttonColor.withOpacity(0.4),
                blurRadius: widget.isConnected ? 20 : 10,
                spreadRadius: widget.isConnected ? 2 : 0,
              ),
            ],
          ),
          child: Material(
            color: buttonColor,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: widget.isLoading ? null : widget.onPressed,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.isLoading)
                      RotationTransition(
                        turns: _rotationAnimation as Animation<double>,
                        child: Icon(
                          Icons.cloud_queue,
                          size: 48,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(
                        widget.isConnected
                            ? Icons.check_circle
                            : Icons.cloud_off,
                        size: 48,
                        color: Colors.white,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      buttonLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
