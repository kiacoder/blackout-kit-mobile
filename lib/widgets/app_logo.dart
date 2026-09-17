import 'package:flutter/material.dart';

/// Official Blackout Kit Logo Widget
class AppLogo extends StatelessWidget {
  final double size;
  final bool showTitle;
  final bool showSubtitle;
  final bool useFullLogoImage;
  final Axis direction;

  const AppLogo({
    Key? key,
    this.size = 64.0,
    this.showTitle = true,
    this.showSubtitle = true,
    this.useFullLogoImage = false,
    this.direction = Axis.vertical,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If using full logo image asset (B mark + text on black background)
    if (useFullLogoImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: Image.asset(
          'assets/images/logo.png',
          width: size * 2.5,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallbackLogo(context),
        ),
      );
    }

    final logoIcon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: size * 0.2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/icons/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackLogo(context),
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
            'blackout kit',
            style: TextStyle(
              fontSize: size * 0.35,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
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

  Widget _buildFallbackLogo(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Center(
        child: Icon(
          Icons.flash_on_rounded,
          size: size * 0.6,
          color: primaryColor,
        ),
      ),
    );
  }
}
