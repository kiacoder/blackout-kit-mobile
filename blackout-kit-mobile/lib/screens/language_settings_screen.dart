import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/localization_service.dart';

/// Language selection settings screen
class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({Key? key}) : super(key: key);

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  late LocalizationService _localizationService;

  @override
  void initState() {
    super.initState();
    _localizationService = Get.find<LocalizationService>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('language'.tr()),
        elevation: 0,
      ),
      body: Obx(
        () => ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text(
              'Select Language',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ..._localizationService.getSupportedLanguages().entries.map((entry) {
              final languageCode = entry.key;
              final languageName = entry.value;
              final isSelected =
                  _localizationService.currentLanguage.value == languageCode;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                child: ListTile(
                  title: Text(languageName),
                  subtitle: Text(
                    _getLanguageNativeDescription(languageCode),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.circle_outlined),
                  onTap: () async {
                    await _localizationService.setLanguage(languageCode);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Language changed to $languageName',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              );
            }).toList(),
            const SizedBox(height: 24),
            Text(
              'Language Preferences',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Current Language',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 32.0),
                      child: Text(
                        _localizationService.currentLocaleDisplay.value,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
                    Row(
                      children: [
                        const Icon(Icons.language, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'System Language',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 32.0),
                      child: Text(
                        _getSystemLanguage(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getLanguageNativeDescription(String languageCode) {
    const descriptions = {
      'en': 'United States',
      'es': 'España / América Latina',
      'fr': 'France',
      'de': 'Deutschland',
      'zh': '中国 / 台湾',
      'ja': '日本',
      'ru': 'Россия',
      'ar': 'العالم العربي',
      'pt': 'Portugal / Brasil',
    };
    return descriptions[languageCode] ?? '';
  }

  String _getSystemLanguage() {
    final locale = Get.deviceLocale?.toString() ?? 'Unknown';
    return locale;
  }
}
