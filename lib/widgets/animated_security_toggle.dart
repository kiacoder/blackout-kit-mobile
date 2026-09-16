import 'package:flutter/material.dart';

/// Animated toggle for security features with smooth transitions
class AnimatedSecurityToggle extends StatefulWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData icon;
  final bool isLoading;

  const AnimatedSecurityToggle({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.icon,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<AnimatedSecurityToggle> createState() =>
      _AnimatedSecurityToggleState();
}

class _AnimatedSecurityToggleState extends State<AnimatedSecurityToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _toggleController;
  late Animation<double> _slideAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _toggleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(parent: _toggleController, curve: Curves.easeInOut),
    );

    _colorAnimation = ColorTween(
      begin: Colors.grey[400],
      end: Colors.green,
    ).animate(CurvedAnimation(parent: _toggleController, curve: Curves.easeInOut));

    if (widget.value) {
      _toggleController.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedSecurityToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _toggleController.forward();
      } else {
        _toggleController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _toggleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isLoading ? null : () => widget.onChanged(!widget.value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: Colors.grey[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.value ? 'Enabled' : 'Disabled',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.isLoading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.grey[700]),
                ),
              )
            else
              AnimatedBuilder(
                animation: _toggleController,
                builder: (context, child) {
                  return Container(
                    width: 54,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _colorAnimation.value ?? Colors.grey[400],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 4 + _slideAnimation.value,
                          top: 4,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
