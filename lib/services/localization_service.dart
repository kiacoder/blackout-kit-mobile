import 'package:get/get.dart';
import 'package:logger/logger.dart';

/// Manages app localization and language switching
class LocalizationService extends GetxService {
  final _logger = Logger();

  // Observable current language code
  final currentLanguage = 'en'.obs;

  // Observable current locale display name
  final currentLocaleDisplay = 'English'.obs;

  // Supported languages: code -> display name
  static const supportedLanguages = {
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'zh': '中文',
    'ja': '日本語',
    'ru': 'Русский',
    'ar': 'العربية',
    'pt': 'Português',
  };

  @override
  void onInit() {
    super.onInit();
    _loadSavedLanguage();
  }

  /// Load saved language preference from storage
  void _loadSavedLanguage() {
    // TODO: Load from SharedPreferences/Hive
    // For now, default to English
    currentLanguage.value = 'en';
    currentLocaleDisplay.value = supportedLanguages['en'] ?? 'English';
  }

  /// Change app language
  Future<void> setLanguage(String languageCode) async {
    try {
      if (!supportedLanguages.containsKey(languageCode)) {
        _logger.w('Unsupported language code: $languageCode');
        return;
      }

      currentLanguage.value = languageCode;
      currentLocaleDisplay.value =
          supportedLanguages[languageCode] ?? 'English';

      // TODO: Save to persistent storage
      _logger.i('Language changed to: $languageCode');

      // Trigger UI rebuild with new locale
      // This requires integration with GetMaterialApp localizationsDelegates
      Get.updateLocale(Locale(languageCode));
    } catch (e) {
      _logger.e('Error setting language: $e');
    }
  }

  /// Get all supported languages
  Map<String, String> getSupportedLanguages() => supportedLanguages;

  /// Get string translation
  /// This is a placeholder - actual translations would come from ARB files
  String translate(String key, {String language = 'en'}) {
    return _getTranslation(key, language);
  }

  /// Translation data by language
  static const _translations = {
    'en': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'Trustworthy VPN',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'connecting': 'Connecting...',
      'disconnecting': 'Disconnecting...',
      'connect': 'Connect',
      'disconnect': 'Disconnect',
      'settings': 'Settings',
      'library': 'Library',
      'configs': 'Configs',
      'speed': 'Speed',
      'reliability': 'Reliability',
      'protocol': 'Protocol',
      'kill_switch': 'Kill Switch',
      'dns_leak_prevention': 'DNS Leak Prevention',
      'split_tunneling': 'Split Tunneling',
      'language': 'Language',
      'about': 'About',
      'close': 'Close',
      'cancel': 'Cancel',
      'save': 'Save',
      'error': 'Error',
      'success': 'Success',
      'loading': 'Loading...',
    },
    'es': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'VPN Confiable',
      'connected': 'Conectado',
      'disconnected': 'Desconectado',
      'connecting': 'Conectando...',
      'disconnecting': 'Desconectando...',
      'connect': 'Conectar',
      'disconnect': 'Desconectar',
      'settings': 'Configuración',
      'library': 'Biblioteca',
      'configs': 'Configuraciones',
      'speed': 'Velocidad',
      'reliability': 'Confiabilidad',
      'protocol': 'Protocolo',
      'kill_switch': 'Kill Switch',
      'dns_leak_prevention': 'Prevención de Fugas DNS',
      'split_tunneling': 'Tunelización Dividida',
      'language': 'Idioma',
      'about': 'Acerca de',
      'close': 'Cerrar',
      'cancel': 'Cancelar',
      'save': 'Guardar',
      'error': 'Error',
      'success': 'Éxito',
      'loading': 'Cargando...',
    },
    'fr': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'VPN de Confiance',
      'connected': 'Connecté',
      'disconnected': 'Déconnecté',
      'connecting': 'Connexion...',
      'disconnecting': 'Déconnexion...',
      'connect': 'Connecter',
      'disconnect': 'Déconnecter',
      'settings': 'Paramètres',
      'library': 'Bibliothèque',
      'configs': 'Configurations',
      'speed': 'Vitesse',
      'reliability': 'Fiabilité',
      'protocol': 'Protocole',
      'kill_switch': 'Kill Switch',
      'dns_leak_prevention': 'Prévention des Fuites DNS',
      'split_tunneling': 'Tunnelisation Fractionnée',
      'language': 'Langue',
      'about': 'À Propos',
      'close': 'Fermer',
      'cancel': 'Annuler',
      'save': 'Enregistrer',
      'error': 'Erreur',
      'success': 'Succès',
      'loading': 'Chargement...',
    },
    'de': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'Vertrauenswürdiges VPN',
      'connected': 'Verbunden',
      'disconnected': 'Getrennt',
      'connecting': 'Verbindung wird hergestellt...',
      'disconnecting': 'Trennung läuft...',
      'connect': 'Verbinden',
      'disconnect': 'Trennen',
      'settings': 'Einstellungen',
      'library': 'Bibliothek',
      'configs': 'Konfigurationen',
      'speed': 'Geschwindigkeit',
      'reliability': 'Zuverlässigkeit',
      'protocol': 'Protokoll',
      'kill_switch': 'Kill Switch',
      'dns_leak_prevention': 'DNS-Leck-Prävention',
      'split_tunneling': 'Split Tunneling',
      'language': 'Sprache',
      'about': 'Über',
      'close': 'Schließen',
      'cancel': 'Abbrechen',
      'save': 'Speichern',
      'error': 'Fehler',
      'success': 'Erfolg',
      'loading': 'Wird geladen...',
    },
    'zh': {
      'app_title': 'Blackout Kit',
      'app_subtitle': '可信赖的 VPN',
      'connected': '已连接',
      'disconnected': '已断开',
      'connecting': '正在连接...',
      'disconnecting': '正在断开...',
      'connect': '连接',
      'disconnect': '断开',
      'settings': '设置',
      'library': '库',
      'configs': '配置',
      'speed': '速度',
      'reliability': '可靠性',
      'protocol': '协议',
      'kill_switch': '断流开关',
      'dns_leak_prevention': 'DNS 泄露防止',
      'split_tunneling': '分割隧道',
      'language': '语言',
      'about': '关于',
      'close': '关闭',
      'cancel': '取消',
      'save': '保存',
      'error': '错误',
      'success': '成功',
      'loading': '正在加载...',
    },
    'ja': {
      'app_title': 'Blackout Kit',
      'app_subtitle': '信頼できる VPN',
      'connected': '接続済み',
      'disconnected': '切断',
      'connecting': '接続中...',
      'disconnecting': '切断中...',
      'connect': '接続',
      'disconnect': '切断',
      'settings': '設定',
      'library': 'ライブラリ',
      'configs': '設定',
      'speed': '速度',
      'reliability': '信頼性',
      'protocol': 'プロトコル',
      'kill_switch': 'キルスイッチ',
      'dns_leak_prevention': 'DNS リーク防止',
      'split_tunneling': 'スプリットトンネリング',
      'language': '言語',
      'about': 'について',
      'close': '閉じる',
      'cancel': 'キャンセル',
      'save': '保存',
      'error': 'エラー',
      'success': '成功',
      'loading': 'ロード中...',
    },
    'ru': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'Надежный VPN',
      'connected': 'Подключено',
      'disconnected': 'Отключено',
      'connecting': 'Подключение...',
      'disconnecting': 'Отключение...',
      'connect': 'Подключить',
      'disconnect': 'Отключить',
      'settings': 'Параметры',
      'library': 'Библиотека',
      'configs': 'Конфигурации',
      'speed': 'Скорость',
      'reliability': 'Надежность',
      'protocol': 'Протокол',
      'kill_switch': 'Kill Switch',
      'dns_leak_prevention': 'Защита от утечек DNS',
      'split_tunneling': 'Разделенный туннель',
      'language': 'Язык',
      'about': 'О приложении',
      'close': 'Закрыть',
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'error': 'Ошибка',
      'success': 'Успех',
      'loading': 'Загрузка...',
    },
    'ar': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'VPN موثوق',
      'connected': 'متصل',
      'disconnected': 'غير متصل',
      'connecting': 'جاري الاتصال...',
      'disconnecting': 'جاري قطع الاتصال...',
      'connect': 'اتصال',
      'disconnect': 'قطع الاتصال',
      'settings': 'الإعدادات',
      'library': 'المكتبة',
      'configs': 'الإعدادات',
      'speed': 'السرعة',
      'reliability': 'الموثوقية',
      'protocol': 'البروتوكول',
      'kill_switch': 'Kill Switch',
      'dns_leak_prevention': 'منع تسرب DNS',
      'split_tunneling': 'النفق المقسم',
      'language': 'اللغة',
      'about': 'حول',
      'close': 'إغلاق',
      'cancel': 'إلغاء',
      'save': 'حفظ',
      'error': 'خطأ',
      'success': 'نجاح',
      'loading': 'جاري التحميل...',
    },
    'pt': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'VPN Confiável',
      'connected': 'Conectado',
      'disconnected': 'Desconectado',
      'connecting': 'Conectando...',
      'disconnecting': 'Desconectando...',
      'connect': 'Conectar',
      'disconnect': 'Desconectar',
      'settings': 'Configurações',
      'library': 'Biblioteca',
      'configs': 'Configurações',
      'speed': 'Velocidade',
      'reliability': 'Confiabilidade',
      'protocol': 'Protocolo',
      'kill_switch': 'Kill Switch',
      'dns_leak_prevention': 'Prevenção de Vazamento de DNS',
      'split_tunneling': 'Tunelamento Dividido',
      'language': 'Idioma',
      'about': 'Sobre',
      'close': 'Fechar',
      'cancel': 'Cancelar',
      'save': 'Salvar',
      'error': 'Erro',
      'success': 'Sucesso',
      'loading': 'Carregando...',
    },
  };

  /// Get translation for a key in a specific language
  static String _getTranslation(String key, String language) {
    final languageTranslations = _translations[language] ?? _translations['en'];
    return languageTranslations?[key] ?? key;
  }
}

/// Extension for easy translation access
extension TranslationExtension on String {
  String tr({String? lang}) {
    final language = lang ?? Get.find<LocalizationService>().currentLanguage.value;
    return LocalizationService._getTranslation(this, language);
  }
}
