/// The beginner guide: six steps, no jargon.
///
/// Written for someone who has never used a VPN and does not want to learn
/// what a protocol is. Every sentence either tells them what to tap or what
/// they will see afterwards. The technical explanation lives in the code
/// comments, not on this screen — that is the whole point of it.
///
/// All copy comes from the translation catalogue (`guide_*` keys), so the
/// screen follows the language setting like everything else.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({Key? key}) : super(key: key);

  /// Step key pairs, in order. Title and body keys stay separate so a
  /// translation can reorder or reflow the body without touching the number.
  static const List<List<String>> _steps = [
    ['guide_step1_title', 'guide_step1_body'],
    ['guide_step2_title', 'guide_step2_body'],
    ['guide_step3_title', 'guide_step3_body'],
    ['guide_step4_title', 'guide_step4_body'],
    ['guide_step5_title', 'guide_step5_body'],
    ['guide_step6_title', 'guide_step6_body'],
  ];

  /// Icons are visual anchors for people skimming: each step gets one that
  /// matches the action, not the concept.
  static const List<IconData> _icons = [
    Icons.link,
    Icons.library_add_outlined,
    Icons.power_settings_new,
    Icons.public,
    Icons.dns_outlined,
    Icons.tune,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('guide_title'.tr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'guide_subtitle'.tr,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'guide_intro'.tr,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < _steps.length; i++) ...[
            _StepCard(
              icon: _icons[i],
              title: _steps[i][0].tr,
              body: _steps[i][1].tr,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.support_agent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'guide_need_help'.tr,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'guide_need_help_body'.tr,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: Get.back,
              child: Text('guide_got_it'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
