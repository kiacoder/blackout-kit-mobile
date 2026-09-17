import 'package:flutter/material.dart';

/// App logo widget with customizable size, subtitle, and layout.
class AppLogo extends StatelessWidget {
  final double size;
  final bool showTitle;
  final bool showSubtitle;
  final Axis direction;

  const AppLogo({
    Key? key,
    this.size = 64.0,
    this.showTitle = true,
    this.showSubtitle = true,
    this.direction = Axis.vertical,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final logoIcon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            primaryColor,
            primaryColor.withOpacity(0.7),
            const Color(0xFF4F46E5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.35),
            blurRadius: size * 0.25,
            spreadRadius: size * 0.05,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.shield_outlined,
              size: size * 0.58,
              color: Colors.white,
            ),
            Icon(
              Icons.vpn_key_rounded,
              size: size * 0.28,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );

    if (!showTitle && !showSubtitle) {
      return logoIcon;
    }

    final textColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: direction == Axis.horizontal
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (showTitle)
          Text(
            'BLACKOUT KIT',
            style: TextStyle(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: theme.textTheme.titleLarge?.color,
            ),
          ),
        if (showSubtitle) ...[
          const SizedBox(height: 2),
          Text(
            'Trustworthy Open-Source VPN',
            style: TextStyle(
              fontSize: size * 0.16,
              fontWeight: FontWeight.w500,
              color: theme.hintColor,
            ),
          ),
        ],
      ],
    );

    if (direction == Axis.horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          logoIcon,
          const SizedBox(width: 14),
          textColumn,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logoIcon,
        const SizedBox(height: 12),
        textColumn,
      ],
    );
  }
}
