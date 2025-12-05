import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 🔐 GÜVENLİ FOOTBALL API SERVİSİ
/// Cloud Functions üzerinden API çağrısı yapar
/// API key client'ta olmaz, sadece Cloud Functions'ta
class FootballApiServiceSecure {
  static final FootballApiServiceSecure _instance = FootballApiServiceSecure._internal();
  factory FootballApiServiceSecure() => _instance;
  FootballApiServiceSecure._internal();

  // Firebase Functions instance - default region (otomatik detect eder)
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Takım bilgisi getir (isim ile arama)
  Future<Map<String, dynamic>?> searchTeam(String teamName) async {
    try {
      print('🔐 Güvenli Football API - Takım arama: $teamName');

      // Auth kontrolü
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Token'ı yenile
      try {
        await user.getIdToken(true);
        print('✅ Auth token yenilendi');
      } catch (tokenError) {
        print('⚠️ Token yenileme hatası: $tokenError');
      }

      final cleanName = _cleanTurkishChars(teamName);

      // Cloud Function'ı çağır
      final callable = _functions.httpsCallable('callFootballAPI');
      final result = await callable.call({
        'endpoint': '/teams',
        'params': {
          'search': cleanName,
        },
      });

      final data = result.data['data'];
      final teams = data['response'] as List?;

      if (teams != null && teams.isNotEmpty) {
        final team = teams.first;
        print('✅ Takım bulundu: ${team['team']['name']}');
        return team as Map<String, dynamic>;
      }

      print('❌ Takım bulunamadı: $teamName');
      return null;
    } on FirebaseFunctionsException catch (e) {
      print('❌ Firebase Functions Hatası:');
      print('   Code: ${e.code}');
      print('   Message: ${e.message}');
      
      if (e.code == 'unauthenticated') {
        throw Exception('Oturum süresi dolmuş. Lütfen çıkış yapıp tekrar giriş yapın.');
      }
      return null;
    } catch (e) {
      print('❌ Güvenli Football API Search Error: $e');
      return null;
    }
  }

  /// Takım istatistikleri
  Future<Map<String, dynamic>?> getTeamStats(int teamId, int leagueId) async {
    try {
      if (leagueId == 0) {
        print('⚠️ Lig ID yok, stats alınamıyor');
        return null;
      }

      print('🔐 Güvenli Football API - İstatistik: Team=$teamId, League=$leagueId');

      // Auth kontrolü
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      final season = DateTime.now().year;

      // Cloud Function'ı çağır
      final callable = _functions.httpsCallable('callFootballAPI');
      final result = await callable.call({
        'endpoint': '/teams/statistics',
        'params': {
          'team': teamId,
          'season': season,
          'league': leagueId,
        },
      });

      final data = result.data['data'];
      
      if (data['response'] == null || 
          (data['response'] is Map && (data['response'] as Map).isEmpty)) {
        print('⚠️ İstatistik verisi yok');
        return null;
      }

      print('✅ İstatistik alındı');
      return data['response'] as Map<String, dynamic>;
    } catch (e) {
      print('❌ Güvenli Stats Error: $e');
      return null;
    }
  }

  /// Son maçlar
  Future<List<Map<String, dynamic>>> getLastMatches(int teamId, {int limit = 5}) async {
    try {
      print('🔐 Güvenli Football API - Son maçlar: Team=$teamId');

      // Auth kontrolü
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Cloud Function'ı çağır
      final callable = _functions.httpsCallable('callFootballAPI');
      final result = await callable.call({
        'endpoint': '/fixtures',
        'params': {
          'team': teamId,
          'last': limit,
        },
      });

      final data = result.data['data'];
      final fixtures = data['response'] as List?;

      if (fixtures != null && fixtures.isNotEmpty) {
        print('✅ ${fixtures.length} maç alındı');
        return fixtures.cast<Map<String, dynamic>>();
      }

      print('⚠️ Maç verisi yok');
      return [];
    } catch (e) {
      print('❌ Güvenli Last Matches Error: $e');
      return [];
    }
  }

  /// H2H (head to head)
  Future<List<Map<String, dynamic>>> getH2H(int team1Id, int team2Id) async {
    try {
      print('🔐 Güvenli Football API - H2H: $team1Id vs $team2Id');

      // Auth kontrolü
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Cloud Function'ı çağır
      final callable = _functions.httpsCallable('callFootballAPI');
      final result = await callable.call({
        'endpoint': '/fixtures/headtohead',
        'params': {
          'h2h': '$team1Id-$team2Id',
        },
      });

      final data = result.data['data'];
      final fixtures = data['response'] as List?;

      return fixtures?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      print('❌ Güvenli H2H Error: $e');
      return [];
    }
  }

  /// Türkçe karakterleri temizle
  String _cleanTurkishChars(String text) {
    final map = {
      'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G',
      'ı': 'i', 'İ': 'I', 'ö': 'o', 'Ö': 'O',
      'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U',
    };

    var clean = text;
    map.forEach((turkish, english) {
      clean = clean.replaceAll(turkish, english);
    });

    return clean.trim().toLowerCase();
  }
}
