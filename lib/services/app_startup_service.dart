import 'package:firebase_database/firebase_database.dart';
import './match_pool_service.dart';

/// Uygulama başlangıç servisi
/// - Match Pool'u akıllıca günceller
/// - Son güncelleme zamanına göre karar verir
class AppStartupService {
  static final AppStartupService _instance = AppStartupService._internal();
  factory AppStartupService() => _instance;
  AppStartupService._internal();

  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final MatchPoolService _matchPool = MatchPoolService();

  bool _isInitialized = false;

  /// Uygulama başlangıcında çağrılacak
  Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ App Startup zaten çalıştırıldı');
      return;
    }

    try {
      print('🚀 App Startup başlatılıyor...');

      // 1. Pool metadata kontrolü
      final shouldUpdate = await _shouldUpdatePool();

      if (shouldUpdate) {
        print('🔥 Match Pool güncelleme gerekiyor...');
        
        // Background'da güncelle (UI bloklamadan)
        _updatePoolInBackground();
      } else {
        print('✅ Match Pool güncel - Güncelleme atlandı');
      }

      _isInitialized = true;
      print('✅ App Startup tamamlandı');
    } catch (e) {
      print('❌ App Startup hatası: $e');
      // Hata olsa bile uygulama açılmalı
      _isInitialized = true;
    }
  }

  /// Pool güncellemesi gerekli mi?
  Future<bool> _shouldUpdatePool() async {
    try {
      final metadataSnapshot = await _database.child('poolMetadata').get();

      if (!metadataSnapshot.exists) {
        print('📭 Pool metadata yok - İlk güncelleme gerekiyor');
        return true;
      }

      final metadata = metadataSnapshot.value as Map<dynamic, dynamic>;
      final lastUpdate = metadata['lastUpdate'] as int?;
      final nextUpdate = metadata['nextUpdate'] as int?;

      if (lastUpdate == null) {
        print('📭 lastUpdate yok - Güncelleme gerekiyor');
        return true;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      
      // nextUpdate varsa ve geçmişse güncelle
      if (nextUpdate != null && now >= nextUpdate) {
        print('⏰ nextUpdate zamanı geldi - Güncelleme gerekiyor');
        return true;
      }

      // Son güncelleme 12 saatten eskiyse güncelle
      final twelveHoursAgo = now - (12 * 60 * 60 * 1000);
      if (lastUpdate < twelveHoursAgo) {
        print('⏰ 12 saatten eski - Güncelleme gerekiyor');
        return true;
      }

      // Pool'da hiç maç yoksa güncelle
      final poolSnapshot = await _database.child('matchPool').get();
      if (!poolSnapshot.exists) {
        print('📭 Pool boş - Güncelleme gerekiyor');
        return true;
      }

      // Her şey tamam, güncelleme gereksiz
      final hoursSinceUpdate = ((now - lastUpdate) / (1000 * 60 * 60)).floor();
      print('✅ Son güncelleme: $hoursSinceUpdate saat önce');
      return false;
    } catch (e) {
      print('❌ Pool kontrol hatası: $e');
      return false; // Hata durumunda güncelleme yapma
    }
  }

  /// Background'da pool güncelle (UI bloklamadan)
  void _updatePoolInBackground() {
    // Fire and forget - UI bloklamıyor
    Future.microtask(() async {
      try {
        print('🔄 Background pool güncelleme başladı...');
        
        await _matchPool.updateMatchPool();
        
        print('✅ Background pool güncelleme tamamlandı');
      } catch (e) {
        print('❌ Background pool güncelleme hatası: $e');
      }
    });
  }

  /// Manuel pool güncelleme (Kullanıcı tetikler)
  Future<bool> forceUpdatePool() async {
    try {
      print('🔄 Manuel pool güncelleme başlatıldı...');
      
      await _matchPool.updateMatchPool();
      
      print('✅ Manuel pool güncelleme başarılı');
      return true;
    } catch (e) {
      print('❌ Manuel pool güncelleme hatası: $e');
      return false;
    }
  }

  /// Pool durumunu kontrol et
  Future<Map<String, dynamic>> getPoolStatus() async {
    try {
      final metadataSnapshot = await _database.child('poolMetadata').get();
      
      if (!metadataSnapshot.exists) {
        return {
          'exists': false,
          'message': 'Pool henüz oluşturulmamış',
        };
      }

      final metadata = metadataSnapshot.value as Map<dynamic, dynamic>;
      final lastUpdate = metadata['lastUpdate'] as int?;
      final totalMatches = metadata['totalMatches'] as int? ?? 0;
      final leagues = metadata['leagues'] as List<dynamic>? ?? [];

      final now = DateTime.now().millisecondsSinceEpoch;
      final hoursSinceUpdate = lastUpdate != null 
          ? ((now - lastUpdate) / (1000 * 60 * 60)).floor() 
          : 0;

      return {
        'exists': true,
        'totalMatches': totalMatches,
        'leagues': leagues.length,
        'lastUpdate': lastUpdate,
        'hoursSinceUpdate': hoursSinceUpdate,
        'isStale': hoursSinceUpdate > 12,
      };
    } catch (e) {
      print('❌ Pool status hatası: $e');
      return {
        'exists': false,
        'error': e.toString(),
      };
    }
  }
}
