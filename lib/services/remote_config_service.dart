import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  late FirebaseRemoteConfig _remoteConfig;
  bool _initialized = false;

  // Varsayılan değerler (fallback)
  final Map<String, dynamic> _defaults = {
    'GEMINI_API_KEY': '',
    'API_FOOTBALL_KEY': '',
    'min_app_version': '1.0.0',
    'force_update': false,
    'maintenance_mode': false,
  };

  /// Remote Config'i başlat
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _remoteConfig = FirebaseRemoteConfig.instance;

      // Ayarlar
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(minutes: 1), // Dev: 1 dakika, Prod: 12 saat
        ),
      );

      // Varsayılan değerleri ayarla
      await _remoteConfig.setDefaults(_defaults);

      // Config'i çek ve aktive et
      await _remoteConfig.fetchAndActivate();

      _initialized = true;
      print('✅ Remote Config initialized');
    } catch (e) {
      print('❌ Remote Config initialization error: $e');
      // Hata olsa bile devam et (varsayılan değerler kullanılır)
      _initialized = true;
    }
  }

  /// Gemini API Key
  String get geminiApiKey {
    try {
      final key = _remoteConfig.getString('GEMINI_API_KEY');
      if (key.isEmpty) {
        throw Exception('GEMINI_API_KEY is empty in Remote Config');
      }
      return key;
    } catch (e) {
      print('❌ Error getting Gemini API key: $e');
      throw Exception('Gemini API key not configured');
    }
  }

  /// Football API Key
  String get footballApiKey {
    try {
      final key = _remoteConfig.getString('API_FOOTBALL_KEY');
      if (key.isEmpty) {
        throw Exception('API_FOOTBALL_KEY is empty in Remote Config');
      }
      return key;
    } catch (e) {
      print('❌ Error getting Football API key: $e');
      throw Exception('Football API key not configured');
    }
  }

  /// Minimum app version (force update için)
  String get minAppVersion => _remoteConfig.getString('min_app_version');

  /// Force update gerekli mi?
  bool get forceUpdate => _remoteConfig.getBool('force_update');

  /// Bakım modu aktif mi?
  bool get maintenanceMode => _remoteConfig.getBool('maintenance_mode');

  /// Config'i manuel yenile (opsiyonel)
  Future<void> refresh() async {
    try {
      await _remoteConfig.fetchAndActivate();
      print('✅ Remote Config refreshed');
    } catch (e) {
      print('❌ Remote Config refresh error: $e');
    }
  }

  /// Debug için tüm config değerlerini göster
  void printAllConfigs() {
    print('=== Remote Config Values ===');
    print('GEMINI_API_KEY: ${geminiApiKey.substring(0, 10)}...');
    print('API_FOOTBALL_KEY: ${footballApiKey.substring(0, 10)}...');
    print('min_app_version: $minAppVersion');
    print('force_update: $forceUpdate');
    print('maintenance_mode: $maintenanceMode');
    print('============================');
  }
}