import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Translation catalogue for the app.
///
/// Implements GetX's [Translations] so `'key'.tr` resolves against the active
/// locale. The active locale itself is **not** held here — it lives in
/// `SettingsController.selectedLanguage`, which is the single source of truth
/// and already persists to Hive. `main.dart` feeds it to `GetMaterialApp.locale`
/// inside an `Obx`, so changing the setting re-renders the whole app.
///
/// That split is deliberate. An older version kept a second copy of the
/// language in a `currentLanguage` observable, persisted it nowhere, and called
/// `Get.updateLocale` on an app with no `translations` wired up — so the picker
/// moved the radio button and changed nothing else.
///
/// ## Languages
///
/// Exactly three, by product decision: **English, Persian (فارسی), Chinese
/// (简体中文)**. Everything else that used to be listed here was a partial
/// table with English body text, which looked like a supported language and was
/// not. A locale that is missing from [supportedLanguages] cannot be selected
/// and resolves to English.
///
/// ## Coverage
///
/// Every string the UI shows goes through this table. The rule is simple: if a
/// literal English string appears in a widget, that widget does not follow the
/// language setting. `test/localization_coverage_test.dart` enforces it.
class LocalizationService extends GetxService implements Translations {
  /// Language code used when a lookup misses, and when no preference is stored.
  static const String fallbackLanguageCode = 'en';

  /// Locales the app can render, in the same order as [supportedLanguages].
  static List<Locale> get supportedLocales =>
      supportedLanguages.keys.map((code) => Locale(code)).toList();

  /// Languages written right-to-left. Selecting one of these must flip the
  /// whole widget tree, not just the strings: without a Directionality the
  /// Material widgets stayed LTR while the text ran the other way.
  static const Set<String> rtlLanguages = {'fa', 'ar', 'he', 'ur', 'ps', 'sd', 'ug', 'yi'};

  static bool isRtl(String languageCode) =>
      rtlLanguages.contains(languageCode.toLowerCase());

  /// Supported languages: language code -> display name, in menu order.
  ///
  /// Each name is written in its own script, which is what a user looking for
  /// their language actually recognises.
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'fa': 'فارسی',
    'zh': '简体中文',
  };

  /// GetX reads this to resolve `'key'.tr`.
  @override
  Map<String, Map<String, String>> get keys => _translations;

  /// Display name for a language code, falling back to the code itself.
  static String displayName(String languageCode) =>
      supportedLanguages[languageCode] ?? languageCode;

  /// True when [languageCode] is one this app ships translations for.
  static bool isSupported(String languageCode) =>
      supportedLanguages.containsKey(languageCode);

  /// Resolve [key] in an explicit language, for callers that are not inside a
  /// widget tree (services, log lines, tests). Widgets should use `'key'.tr`.
  static String translate(
    String key, {
    String language = fallbackLanguageCode,
  }) {
    final table = _translations[language] ?? _translations[fallbackLanguageCode];
    // Returning the key itself on a miss is deliberate: a visible `foo_bar` in
    // the UI is easier to notice and fix than a silently blank string.
    return table?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    // ───────────────────────────── English ─────────────────────────────
    'en': {
      'app_title': 'Blackout Kit',
      'app_subtitle': 'Trustworthy VPN',

      // Connection state
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'not_connected': 'Not Connected',
      'connecting': 'Connecting...',
      'disconnecting': 'Disconnecting...',
      'selecting': 'Selecting...',
      'testing': 'Testing...',
      'connected_to': 'Connected to',
      'connect': 'Connect',
      'disconnect': 'Disconnect',
      'dns_only_connected': 'DNS only',

      // Navigation
      'settings': 'Settings',
      'library': 'Library',
      'configs': 'Configs',
      'speed': 'Speed',
      'latency': 'Latency',
      'reliability': 'Reliability',
      'protocol': 'Protocol',
      'guide': 'Guide',

      // Settings — network features
      'kill_switch': 'Kill Switch',
      'kill_switch_desc': 'Block all traffic if VPN disconnects',
      'dns_leak_prevention': 'DNS leak prevention',
      'dns_leak_prevention_on': 'DNS queries are resolved inside the tunnel.',
      'dns_leak_prevention_off': 'Off - your provider can see which domains you resolve.',
      'split_tunneling': 'Split Tunneling',
      'split_tunneling_desc': 'Route selected apps outside VPN',
      'engine_hub': 'Blackout Engine Hub',
      'preferred_protocol': 'Preferred Protocol',
      'language': 'Language',
      'about': 'About',

      // Settings — DNS
      'dns_resolver': 'DNS resolver',
      'dns_only_mode': 'Change DNS only',
      'dns_only_mode_desc': 'Use the chosen resolver without a VPN. Your traffic still goes out directly.',
      'check_resolvers': 'Check resolvers',
      'check_resolvers_desc': 'Opens a TCP connection to port 53 on each address. A resolver that fails here can still work over UDP - this is a hint, not a verdict.',
      'resolver_reachability': 'Resolver reachability',
      'resolver_tcp_ok': 'TCP 53 answered',
      'resolver_tcp_miss': 'No TCP 53 answer - it may still work over UDP',
      'no_resolver_selected': 'No resolver is selected.',
      'use_global': 'Use global',
      'resolver_mismatch_title': 'Resolver does not match your exit',

      // Settings — general
      'auto_connect': 'Auto-Connect on Launch',
      'auto_connect_desc': 'Automatically connect to VPN when app starts',
      'block_non_vpn': 'Block Non-VPN Traffic',
      'block_non_vpn_desc': 'Block all traffic if VPN disconnects',
      'auto_select_fastest': 'Auto-Select Fastest',
      'auto_select_fastest_desc': 'Automatically use fastest working config',
      'auto_test_interval': 'Auto-Test Interval',
      'show_speed_status_bar': 'Show Speed in Status Bar',
      'show_my_location': 'Show my location',
      'keep_screen_awake': 'Keep Screen Awake',
      'keep_screen_awake_desc': 'Prevent screen from turning off during config testing or active VPN',
      'theme': 'Theme',
      'theme_system': 'System Default',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'select_theme': 'Select Theme',
      'select_language': 'Select Language',
      'app_version': 'App Version',
      'privacy_policy': 'Privacy Policy',
      'analytics': 'Analytics',
      'analytics_desc': 'No data collection. Open source & transparent.',
      'debug_logs': 'Debug & Logs',
      'debug_logs_desc': 'View, filter, copy, and export real-time application logs',
      'site_check': 'Site Check',
      'site_check_websites': 'Site Check Websites',
      'verbose_core_logs': 'Verbose core logs',
      'reset_to_defaults': 'Reset to Defaults',
      'reset_to_defaults_confirm': 'Reset to Defaults?',
      'reset_to_defaults_desc': 'This clears every setting and cannot be undone.',
      'update': 'Update',
      'github': 'GitHub',

      // Configs / library
      'config_library': 'Config Library',
      'configs_found': 'Configs Found',
      'import_vpn_config': 'Import VPN Config',
      'import_all': 'Import All',
      'add_custom_source': 'Add Custom Source',
      'browse_files': 'Browse Files',
      'paste': 'Paste',
      'fetch_configs': 'Fetch Configs',
      'refresh_configs': 'Refresh Configs',
      'no_repositories': 'No repositories loaded',
      'loading_repos': 'Loading repositories & configs...',
      'add_to_library': 'Add to Library',
      'copy_config': 'Copy Config',
      'show_qr': 'Show QR Code',
      'qr_code': 'QR Code',
      'edit_config': 'Edit',
      'delete_config': 'Delete',
      'delete_config_confirm': 'Delete Config?',
      'remove_config_confirm': 'Remove this config?',
      'save_config': 'Save Config',
      'valid_config_detected': 'Valid Config Detected',
      'speed_benchmark': 'Speed & Latency Benchmark',
      'test_all': 'Test All',
      'no_configs_benchmark': 'No configs to benchmark',
      'rescan': 'Rescan',

      // Split tunneling
      'split_tunneling_apps': 'Split Tunneling Apps',
      'select_apps': 'Select Apps for Split Tunneling',
      'split_mode_whitelist': 'Whitelist (VPN Only)',
      'split_mode_bypass': 'Bypass (Direct)',
      'apps_selected': 'apps selected',
      'mode_label': 'Mode:',

      // Logs
      'system_logs': 'System Logs',
      'system_logs_inspector': 'System Logs & Inspector',
      'clear_logs': 'Clear Logs?',
      'clear_logs_confirm': 'Are you sure you want to clear the in-memory log buffer?',
      'export_logs': 'Export Logs',
      'export_all_logs': 'Export All Logs',
      'logs_cleared': 'Logs cleared',
      'logs_exported': 'Logs exported to clipboard',

      // Engine hub
      'engine_hub_desc': 'See which engines this build can actually run',
      'requirements': 'Requirements:',
      'supported_protocols': 'Supported Protocols:',
      'requires_singbox': 'Requires the sing-box runtime',

      // Common
      'close': 'Close',
      'cancel': 'Cancel',
      'save': 'Save',
      'done': 'Done',
      'add': 'Add',
      'delete': 'Delete',
      'import': 'Import',
      'export': 'Export',
      'install': 'Install',
      'retry': 'Retry',
      'refresh': 'Refresh',
      'clear': 'Clear',
      'reset': 'Reset',
      'error': 'Error',
      'success': 'Success',
      'loading': 'Loading...',
      'reconnect_to_apply': 'Reconnect to apply',

      // ── Guide ────────────────────────────────────────────────────────
      'guide_title': 'How to use Blackout Kit',
      'guide_subtitle': 'Six short steps. No technical words.',
      'guide_open': 'Open the guide',
      'guide_intro':
          'Blackout Kit hides what you do online by sending it through a server '
          'somewhere else. You need one "config" - a small text code that tells '
          'the app which server to use. That is the only thing you have to find.',
      'guide_step1_title': '1. Get a config',
      'guide_step1_body':
          'A config starts with letters like vless:// or ss:// or hy2://. You '
          'can get one from a friend, a group, or a provider you trust. Copy the '
          'whole line - it is long, do not cut it.',
      'guide_step2_title': '2. Add it to the app',
      'guide_step2_body':
          'Open Library, press "Import VPN Config", and paste the line. If it '
          'says "Valid Config Detected", it worked. If it says invalid, the line '
          'was cut short - copy it again.',
      'guide_step3_title': '3. Connect',
      'guide_step3_body':
          'Go back to the first screen and press the big button. The first time, '
          'Android asks "Allow VPN connection?". Press OK. That is Android, not '
          'us, and it only asks once.',
      'guide_step4_title': '4. Check it works',
      'guide_step4_body':
          'When the button says Connected, open a website. If it loads, you are '
          'done. If nothing loads, try another config from the list - some '
          'servers are dead.',
      'guide_step5_title': '5. If a site is slow or asks for a captcha',
      'guide_step5_body':
          'That is usually the server, not the app. Go to Settings, DNS, and '
          'pick a resolver that matches the country of your server. A German '
          'server with an Iranian resolver confuses websites.',
      'guide_step6_title': '6. If you only want a different DNS',
      'guide_step6_body':
          'You do not need a config for that. Turn on "Change DNS only" in '
          'Settings, DNS, and press Connect. Your internet stays direct - only '
          'the name lookups change. Use this when your provider blocks sites by '
          'name.',
      'guide_need_help': 'Still stuck?',
      'guide_need_help_body':
          'Open Settings, Debug & Logs, and press Export Logs. That text tells '
          'exactly what failed.',
      'guide_got_it': 'Got it',

      // DNS-only notices
      'dns_only_started': 'DNS only - traffic still goes out directly',
      'dns_only_needs_resolver': 'Pick a resolver first (Settings, DNS).',
      'dns_only_no_config_needed': 'No config needed for DNS only.',
    },

    // ───────────────────────────── Persian ─────────────────────────────
    'fa': {
      'app_title': 'بلک‌اوت کیت',
      'app_subtitle': 'VPN قابل اعتماد',

      'connected': 'متصل',
      'disconnected': 'قطع شد',
      'not_connected': 'وصل نیست',
      'connecting': 'در حال اتصال...',
      'disconnecting': 'در حال قطع...',
      'selecting': 'در حال انتخاب...',
      'testing': 'در حال آزمایش...',
      'connected_to': 'متصل به',
      'connect': 'اتصال',
      'disconnect': 'قطع اتصال',
      'dns_only_connected': 'فقط DNS',

      'settings': 'تنظیمات',
      'library': 'کتابخانه',
      'configs': 'کانفیگ‌ها',
      'speed': 'سرعت',
      'latency': 'تأخیر',
      'reliability': 'پایداری',
      'protocol': 'پروتکل',
      'guide': 'راهنما',

      'kill_switch': 'کلید قطع',
      'kill_switch_desc': 'اگر VPN قطع شد، همه ترافیک مسدود شود',
      'dns_leak_prevention': 'جلوگیری از نشت DNS',
      'dns_leak_prevention_on': 'پرسش‌های DNS داخل تونل پاسخ داده می‌شوند.',
      'dns_leak_prevention_off': 'خاموش - اپراتور می‌تواند ببیند کدام سایت‌ها را باز می‌کنید.',
      'split_tunneling': 'تونل تفکیکی',
      'split_tunneling_desc': 'برنامه‌های انتخاب‌شده خارج از VPN بروند',
      'engine_hub': 'مرکز موتورها',
      'preferred_protocol': 'پروتکل ترجیحی',
      'language': 'زبان',
      'about': 'درباره',

      'dns_resolver': 'سرور DNS',
      'dns_only_mode': 'فقط DNS را عوض کن',
      'dns_only_mode_desc': 'از سرور DNS انتخابی بدون VPN استفاده کن. ترافیک شما مستقیم می‌رود.',
      'check_resolvers': 'بررسی سرورهای DNS',
      'check_resolvers_desc': 'به پورت 53 هر آدرس با TCP وصل می‌شود. اگر جواب نداد، ممکن است با UDP کار کند - این فقط یک نشانه است.',
      'resolver_reachability': 'دسترسی‌پذیری سرور DNS',
      'resolver_tcp_ok': 'TCP 53 جواب داد',
      'resolver_tcp_miss': 'TCP 53 جواب نداد - ممکن است با UDP کار کند',
      'no_resolver_selected': 'هیچ سرور DNS انتخاب نشده.',
      'use_global': 'استفاده از سرور عمومی',
      'resolver_mismatch_title': 'سرور DNS با کشور خروجی هم‌خوان نیست',

      'auto_connect': 'اتصال خودکار در شروع',
      'auto_connect_desc': 'هنگام باز شدن برنامه خودکار وصل شو',
      'block_non_vpn': 'مسدود کردن ترافیک بدون VPN',
      'block_non_vpn_desc': 'اگر VPN قطع شد، همه ترافیک مسدود شود',
      'auto_select_fastest': 'انتخاب خودکار سریع‌ترین',
      'auto_select_fastest_desc': 'خودکار سریع‌ترین کانفیگ سالم استفاده شود',
      'auto_test_interval': 'فاصله آزمایش خودکار',
      'show_speed_status_bar': 'نمایش سرعت در نوار وضعیت',
      'show_my_location': 'نمایش موقعیت من',
      'keep_screen_awake': 'روشن نگه داشتن صفحه',
      'keep_screen_awake_desc': 'در زمان آزمایش یا اتصال، صفحه خاموش نشود',
      'theme': 'پوسته',
      'theme_system': 'پیش‌فرض سیستم',
      'theme_light': 'روشن',
      'theme_dark': 'تیره',
      'select_theme': 'انتخاب پوسته',
      'select_language': 'انتخاب زبان',
      'app_version': 'نسخه برنامه',
      'privacy_policy': 'سیاست حفظ حریم خصوصی',
      'analytics': 'آمار',
      'analytics_desc': 'هیچ داده‌ای جمع نمی‌شود. متن‌باز و شفاف.',
      'debug_logs': 'اشکال‌زدایی و گزارش‌ها',
      'debug_logs_desc': 'دیدن، فیلتر، کپی و خروجی گرفتن از گزارش‌های زنده',
      'site_check': 'بررسی سایت',
      'site_check_websites': 'سایت‌های بررسی',
      'verbose_core_logs': 'گزارش کامل هسته',
      'reset_to_defaults': 'بازگشت به تنظیمات پیش‌فرض',
      'reset_to_defaults_confirm': 'به پیش‌فرض برگردد؟',
      'reset_to_defaults_desc': 'همه تنظیمات پاک می‌شود و قابل بازگشت نیست.',
      'update': 'به‌روزرسانی',
      'github': 'گیت‌هاب',

      'config_library': 'کتابخانه کانفیگ',
      'configs_found': 'کانفیگ پیدا شد',
      'import_vpn_config': 'افزودن کانفیگ VPN',
      'import_all': 'افزودن همه',
      'add_custom_source': 'افزودن منبع دلخواه',
      'browse_files': 'انتخاب فایل',
      'paste': 'چسباندن',
      'fetch_configs': 'گرفتن کانفیگ‌ها',
      'refresh_configs': 'تازه‌سازی کانفیگ‌ها',
      'no_repositories': 'هیچ منبعی بارگذاری نشده',
      'loading_repos': 'در حال بارگذاری منابع و کانفیگ‌ها...',
      'add_to_library': 'افزودن به کتابخانه',
      'copy_config': 'کپی کانفیگ',
      'show_qr': 'نمایش QR',
      'qr_code': 'کد QR',
      'edit_config': 'ویرایش',
      'delete_config': 'حذف',
      'delete_config_confirm': 'کانفیگ حذف شود؟',
      'remove_config_confirm': 'این کانفیگ حذف شود؟',
      'save_config': 'ذخیره کانفیگ',
      'valid_config_detected': 'کانفیگ معتبر است',
      'speed_benchmark': 'آزمایش سرعت و تأخیر',
      'test_all': 'آزمایش همه',
      'no_configs_benchmark': 'کانفیگی برای آزمایش نیست',
      'rescan': 'اسکن دوباره',

      'split_tunneling_apps': 'برنامه‌های تونل تفکیکی',
      'select_apps': 'انتخاب برنامه‌ها',
      'split_mode_whitelist': 'لیست سفید (فقط VPN)',
      'split_mode_bypass': 'عبور مستقیم',
      'apps_selected': 'برنامه انتخاب شد',
      'mode_label': 'حالت:',

      'system_logs': 'گزارش‌های سیستم',
      'system_logs_inspector': 'گزارش‌ها و بازرسی',
      'clear_logs': 'گزارش‌ها پاک شود؟',
      'clear_logs_confirm': 'گزارش‌های داخل حافظه پاک شوند؟',
      'export_logs': 'خروجی گزارش',
      'export_all_logs': 'خروجی همه گزارش‌ها',
      'logs_cleared': 'گزارش‌ها پاک شد',
      'logs_exported': 'گزارش‌ها در کلیپ‌بورد کپی شد',

      'engine_hub_desc': 'ببینید این نسخه کدام موتورها را اجرا می‌کند',
      'requirements': 'نیازمندی‌ها:',
      'supported_protocols': 'پروتکل‌های پشتیبانی‌شده:',
      'requires_singbox': 'به هسته sing-box نیاز دارد',

      'close': 'بستن',
      'cancel': 'انصراف',
      'save': 'ذخیره',
      'done': 'تمام',
      'add': 'افزودن',
      'delete': 'حذف',
      'import': 'ورود',
      'export': 'خروجی',
      'install': 'نصب',
      'retry': 'تلاش دوباره',
      'refresh': 'تازه‌سازی',
      'clear': 'پاک کردن',
      'reset': 'بازنشانی',
      'error': 'خطا',
      'success': 'موفق',
      'loading': 'در حال بارگذاری...',
      'reconnect_to_apply': 'برای اعمال، دوباره وصل شوید',

      'guide_title': 'چطور از بلک‌اوت کیت استفاده کنیم',
      'guide_subtitle': 'شش قدم کوتاه. بدون اصطلاح فنی.',
      'guide_open': 'باز کردن راهنما',
      'guide_intro':
          'بلک‌اوت کیت کاری را که انجام می‌دهید از یک سرور در جای دیگر رد می‌کند تا '
          'پنهان بماند. فقط به یک «کانفیگ» نیاز دارید؛ یک خط متن که می‌گوید از کدام '
          'سرور استفاده شود. تنها چیزی که باید پیدا کنید همین است.',
      'guide_step1_title': '۱. یک کانفیگ بگیرید',
      'guide_step1_body':
          'کانفیگ با حروفی مثل vless:// یا ss:// یا hy2:// شروع می‌شود. از دوست، '
          'گروه یا فروشنده‌ای که به آن اعتماد دارید بگیرید. کل خط را کپی کنید - '
          'طولانی است، نصفه‌اش نکنید.',
      'guide_step2_title': '۲. آن را به برنامه اضافه کنید',
      'guide_step2_body':
          'کتابخانه را باز کنید، «افزودن کانفیگ VPN» را بزنید و خط را بچسبانید. '
          'اگر «کانفیگ معتبر است» آمد، درست بوده. اگر گفت نامعتبر، خط نصفه کپی '
          'شده - دوباره کپی کنید.',
      'guide_step3_title': '۳. وصل شوید',
      'guide_step3_body':
          'به صفحه اول برگردید و دکمه بزرگ را بزنید. بار اول اندروید می‌پرسد '
          '«اجازه اتصال VPN؟». OK را بزنید. این پیام از اندروید است، نه ما، و '
          'فقط یک بار می‌آید.',
      'guide_step4_title': '۴. مطمئن شوید کار می‌کند',
      'guide_step4_body':
          'وقتی دکمه «متصل» شد، یک سایت باز کنید. اگر باز شد، تمام است. اگر هیچ '
          'چیزی باز نشد، کانفیگ دیگری را امتحان کنید - بعضی سرورها خراب‌اند.',
      'guide_step5_title': '۵. اگر سایتی کند بود یا کپچا خواست',
      'guide_step5_body':
          'معمولاً تقصیر سرور است نه برنامه. به تنظیمات، DNS بروید و سروری انتخاب '
          'کنید که با کشور سرور شما هم‌خوان باشد. سرور آلمانی با DNS ایرانی، '
          'سایت‌ها را گیج می‌کند.',
      'guide_step6_title': '۶. اگر فقط DNS را می‌خواهید عوض کنید',
      'guide_step6_body':
          'برای این کار به کانفیگ نیازی نیست. در تنظیمات، DNS، «فقط DNS را عوض کن» '
          'را روشن کنید و اتصال را بزنید. اینترنت شما مستقیم می‌ماند و فقط '
          'تبدیل نام عوض می‌شود. وقتی اپراتور سایت‌ها را با نام می‌بندد به کار می‌آید.',
      'guide_need_help': 'هنوز گیر کرده‌اید؟',
      'guide_need_help_body':
          'تنظیمات، اشکال‌زدایی و گزارش‌ها را باز کنید و «خروجی گزارش» را بزنید. '
          'آن متن دقیقاً می‌گوید چه چیزی خراب شده.',
      'guide_got_it': 'فهمیدم',

      'dns_only_started': 'فقط DNS - ترافیک همچنان مستقیم می‌رود',
      'dns_only_needs_resolver': 'اول یک سرور DNS انتخاب کنید (تنظیمات، DNS).',
      'dns_only_no_config_needed': 'برای فقط DNS به کانفیگ نیازی نیست.',
    },

    // ───────────────────────────── Chinese ─────────────────────────────
    'zh': {
      'app_title': 'Blackout Kit',
      'app_subtitle': '值得信赖的 VPN',

      'connected': '已连接',
      'disconnected': '已断开',
      'not_connected': '未连接',
      'connecting': '正在连接...',
      'disconnecting': '正在断开...',
      'selecting': '正在选择...',
      'testing': '正在测试...',
      'connected_to': '已连接到',
      'connect': '连接',
      'disconnect': '断开',
      'dns_only_connected': '仅 DNS',

      'settings': '设置',
      'library': '配置库',
      'configs': '配置',
      'speed': '速度',
      'latency': '延迟',
      'reliability': '稳定性',
      'protocol': '协议',
      'guide': '使用指南',

      'kill_switch': '断网保护',
      'kill_switch_desc': 'VPN 断开时阻断全部流量',
      'dns_leak_prevention': '防止 DNS 泄漏',
      'dns_leak_prevention_on': 'DNS 查询在隧道内解析。',
      'dns_leak_prevention_off': '关闭 - 运营商可以看到你访问了哪些域名。',
      'split_tunneling': '分流',
      'split_tunneling_desc': '让选定的应用不走 VPN',
      'engine_hub': '引擎中心',
      'preferred_protocol': '首选协议',
      'language': '语言',
      'about': '关于',

      'dns_resolver': 'DNS 服务器',
      'dns_only_mode': '只修改 DNS',
      'dns_only_mode_desc': '使用选定的 DNS 而不建立 VPN，流量仍然直连。',
      'check_resolvers': '检测 DNS 服务器',
      'check_resolvers_desc': '对每个地址的 53 端口发起 TCP 连接。失败不代表不能用，很多服务器只支持 UDP - 仅供参考。',
      'resolver_reachability': 'DNS 可达性',
      'resolver_tcp_ok': 'TCP 53 有响应',
      'resolver_tcp_miss': 'TCP 53 无响应 - 可能仍支持 UDP',
      'no_resolver_selected': '尚未选择 DNS 服务器。',
      'use_global': '改用通用服务器',
      'resolver_mismatch_title': 'DNS 与出口国家不匹配',

      'auto_connect': '启动时自动连接',
      'auto_connect_desc': '打开应用时自动连接 VPN',
      'block_non_vpn': '阻断非 VPN 流量',
      'block_non_vpn_desc': 'VPN 断开时阻断全部流量',
      'auto_select_fastest': '自动选择最快',
      'auto_select_fastest_desc': '自动使用最快的可用配置',
      'auto_test_interval': '自动测试间隔',
      'show_speed_status_bar': '在状态栏显示速度',
      'show_my_location': '显示我的位置',
      'keep_screen_awake': '保持屏幕常亮',
      'keep_screen_awake_desc': '测试或连接时屏幕不自动关闭',
      'theme': '主题',
      'theme_system': '跟随系统',
      'theme_light': '浅色',
      'theme_dark': '深色',
      'select_theme': '选择主题',
      'select_language': '选择语言',
      'app_version': '应用版本',
      'privacy_policy': '隐私政策',
      'analytics': '统计',
      'analytics_desc': '不收集任何数据。开源透明。',
      'debug_logs': '调试与日志',
      'debug_logs_desc': '查看、筛选、复制和导出实时日志',
      'site_check': '站点检测',
      'site_check_websites': '检测站点',
      'verbose_core_logs': '内核详细日志',
      'reset_to_defaults': '恢复默认设置',
      'reset_to_defaults_confirm': '恢复默认设置？',
      'reset_to_defaults_desc': '所有设置将被清除，且无法撤销。',
      'update': '更新',
      'github': 'GitHub',

      'config_library': '配置库',
      'configs_found': '个配置',
      'import_vpn_config': '导入 VPN 配置',
      'import_all': '全部导入',
      'add_custom_source': '添加自定义来源',
      'browse_files': '选择文件',
      'paste': '粘贴',
      'fetch_configs': '获取配置',
      'refresh_configs': '刷新配置',
      'no_repositories': '未加载任何来源',
      'loading_repos': '正在加载来源和配置...',
      'add_to_library': '添加到配置库',
      'copy_config': '复制配置',
      'show_qr': '显示二维码',
      'qr_code': '二维码',
      'edit_config': '编辑',
      'delete_config': '删除',
      'delete_config_confirm': '删除配置？',
      'remove_config_confirm': '移除该配置？',
      'save_config': '保存配置',
      'valid_config_detected': '配置有效',
      'speed_benchmark': '速度与延迟测试',
      'test_all': '全部测试',
      'no_configs_benchmark': '没有可测试的配置',
      'rescan': '重新扫描',

      'split_tunneling_apps': '分流应用',
      'select_apps': '选择应用',
      'split_mode_whitelist': '白名单（仅这些走 VPN）',
      'split_mode_bypass': '绕过（这些不走 VPN）',
      'apps_selected': '个应用已选择',
      'mode_label': '模式：',

      'system_logs': '系统日志',
      'system_logs_inspector': '日志与检查器',
      'clear_logs': '清除日志？',
      'clear_logs_confirm': '确定清除内存中的日志吗？',
      'export_logs': '导出日志',
      'export_all_logs': '导出全部日志',
      'logs_cleared': '日志已清除',
      'logs_exported': '日志已复制到剪贴板',

      'engine_hub_desc': '查看此版本可以运行哪些引擎',
      'requirements': '要求：',
      'supported_protocols': '支持的协议：',
      'requires_singbox': '需要 sing-box 内核',

      'close': '关闭',
      'cancel': '取消',
      'save': '保存',
      'done': '完成',
      'add': '添加',
      'delete': '删除',
      'import': '导入',
      'export': '导出',
      'install': '安装',
      'retry': '重试',
      'refresh': '刷新',
      'clear': '清除',
      'reset': '重置',
      'error': '错误',
      'success': '成功',
      'loading': '加载中...',
      'reconnect_to_apply': '重新连接后生效',

      'guide_title': '如何使用 Blackout Kit',
      'guide_subtitle': '六个步骤，没有技术术语。',
      'guide_open': '打开使用指南',
      'guide_intro':
          'Blackout Kit 会把你的上网内容先送到另一台服务器，从而隐藏你的真实位置。'
          '你只需要一份“配置”——一段文本，告诉应用用哪台服务器。这是你唯一要找的东西。',
      'guide_step1_title': '1. 获取配置',
      'guide_step1_body':
          '配置以 vless:// 或 ss:// 或 hy2:// 开头。可以从朋友、群组或你信任的服务商获取。'
          '请复制整行——它很长，不要只复制一半。',
      'guide_step2_title': '2. 添加到应用',
      'guide_step2_body':
          '打开配置库，点“导入 VPN 配置”，粘贴那一行。如果显示“配置有效”，就成功了。'
          '如果提示无效，说明复制不完整，请重新复制。',
      'guide_step3_title': '3. 连接',
      'guide_step3_body':
          '回到首页，按那个大按钮。第一次 Android 会问“允许 VPN 连接？”，点确定。'
          '这是 Android 在问，不是我们，而且只问一次。',
      'guide_step4_title': '4. 确认能用',
      'guide_step4_body':
          '按钮显示“已连接”后，打开一个网站。能打开就完成了。如果一个都打不开，'
          '换列表里的另一个配置——有些服务器已经失效。',
      'guide_step5_title': '5. 如果网站很慢或一直要验证码',
      'guide_step5_body':
          '通常是服务器的问题，不是应用。进入设置 → DNS，选一个和你服务器国家一致的 DNS。'
          '德国服务器配伊朗 DNS 会让网站搞不清你从哪来。',
      'guide_step6_title': '6. 如果你只想换 DNS',
      'guide_step6_body':
          '这种情况不需要配置。在设置 → DNS 打开“只修改 DNS”，然后按连接。'
          '网络仍然直连，只是域名解析换了。当运营商用域名封锁网站时很有用。',
      'guide_need_help': '还是不行？',
      'guide_need_help_body':
          '打开设置 → 调试与日志，点“导出日志”。那段文字会说明到底哪里失败了。',
      'guide_got_it': '明白了',

      'dns_only_started': '仅 DNS - 流量仍然直连',
      'dns_only_needs_resolver': '请先选择一个 DNS 服务器（设置 → DNS）。',
      'dns_only_no_config_needed': '仅 DNS 不需要配置。',
    },
  };
}
