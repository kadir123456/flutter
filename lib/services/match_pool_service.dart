import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/match_pool_model.dart';
import './football_api_service.dart';
import './remote_config_service.dart';

class MatchPoolService {
  static final MatchPoolService _instance = MatchPoolService._internal();
  factory MatchPoolService() => _instance;
  MatchPoolService._internal();

  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FootballApiService _footballApi = FootballApiService();
  final RemoteConfigService _remoteConfig = RemoteConfigService();

  String get _apiKey => _remoteConfig.footballApiKey;
  final String _baseUrl = 'https://v3.football.api-sports.io';

  /// 🔥 FIREBASE HAVUZUNU GÜNCELLE (24 saatlik maçlar)
  Future<void> updateMatchPool() async {
    try {
      print('🔄 Maç havuzu güncelleniyor...');
      
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(hours: 24));
      
      // Türkiye Süper Lig + Büyük Avrupa ligleri
      final leagueIds = [
        203, // Türkiye Süper Lig
        39,  // İngiltere Premier League
        140, // İspanya La Liga
        78,  // Almanya Bundesliga
        135, // İtalya Serie A
        61,  // Fransa Ligue 1
      ];

      int totalMatches = 0;
      
      for (final leagueId in leagueIds) {
        await Future.delayed(const Duration(milliseconds: 500)); // Rate limit koruması
        
        final matches = await _fetchFixturesForLeague(
          leagueId,
          now,
          tomorrow,
        );
        
        if (matches.isNotEmpty) {
          await _saveMatchesToFirebase(matches);
          totalMatches += matches.length;
          print('✅ Lig $leagueId: ${matches.length} maç eklendi');
        }
      }

      // Metadata güncelle
      await _updatePoolMetadata(totalMatches, leagueIds);
      
      print('🎉 Havuz güncellendi: $totalMatches maç');
    } catch (e) {
      print('❌ Havuz güncelleme hatası: $e');
      rethrow;
    }
  }

  /// Belirli bir lig için 24 saatlik maçları çek
  Future<List<MatchPoolModel>> _fetchFixturesForLeague(
    int leagueId,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final fromStr = _formatDate(from);
      final toStr = _formatDate(to);
      
      final url = Uri.parse(
        '$_baseUrl/fixtures?league=$leagueId&from=$fromStr&to=$toStr&season=${from.year}',
      );

      final response = await http.get(url, headers: {
        'x-rapidapi-host': 'v3.football.api-sports.io',
        'x-rapidapi-key': _apiKey,
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List? ?? [];
        
        List<MatchPoolModel> matches = [];
        
        for (var fixture in fixtures) {
          // Her maç için stats çek (rate limit dikkat)
          await Future.delayed(const Duration(milliseconds: 400));
          
          final homeTeamId = fixture['teams']['home']['id'];
          final awayTeamId = fixture['teams']['away']['id'];
          
          // Stats çek
          final homeStats = await _footballApi.getTeamStats(homeTeamId, leagueId);
          await Future.delayed(const Duration(milliseconds: 400));
          
          final awayStats = await _footballApi.getTeamStats(awayTeamId, leagueId);
          await Future.delayed(const Duration(milliseconds: 400));
          
          // H2H çek
          final h2h = await _footballApi.getH2H(homeTeamId, awayTeamId);
          
          final match = MatchPoolModel(
            fixtureId: fixture['fixture']['id'],
            homeTeam: _cleanTeamName(fixture['teams']['home']['name']),
            awayTeam: _cleanTeamName(fixture['teams']['away']['name']),
            homeTeamId: homeTeamId,
            awayTeamId: awayTeamId,
            league: fixture['league']['name'],
            leagueId: leagueId,
            date: fixture['fixture']['date'].split('T')[0],
            time: fixture['fixture']['date'].split('T')[1].substring(0, 5),
            timestamp: DateTime.parse(fixture['fixture']['date']).millisecondsSinceEpoch,
            status: fixture['fixture']['status']['short'],
            homeStats: homeStats,
            awayStats: awayStats,
            h2h: h2h,
            lastUpdated: DateTime.now().millisecondsSinceEpoch,
          );
          
          matches.add(match);
        }
        
        return matches;
      }
      
      return [];
    } catch (e) {
      print('❌ Fixtures fetch error (League $leagueId): $e');
      return [];
    }
  }

  /// Firebase'e maçları kaydet
  Future<void> _saveMatchesToFirebase(List<MatchPoolModel> matches) async {
    try {
      for (var match in matches) {
        final date = match.date;
        final fixtureId = match.fixtureId.toString();
        
        await _database
            .child('matchPool')
            .child(date)
            .child(fixtureId)
            .set(match.toJson());
      }
    } catch (e) {
      print('❌ Firebase kayıt hatası: $e');
    }
  }

  /// Pool metadata güncelle
  Future<void> _updatePoolMetadata(int totalMatches, List<int> leagues) async {
    try {
      await _database.child('poolMetadata').set({
        'lastUpdate': DateTime.now().millisecondsSinceEpoch,
        'totalMatches': totalMatches,
        'leagues': leagues,
        'nextUpdate': DateTime.now().add(const Duration(hours: 6)).millisecondsSinceEpoch,
      });
    } catch (e) {
      print('❌ Metadata güncelleme hatası: $e');
    }
  }

  /// 🔍 HAVUZDA MAÇ ARA (Fuzzy Matching)
  Future<MatchPoolModel?> findMatchInPool(String homeTeam, String awayTeam) async {
    try {
      print('🔍 Havuzda aranıyor: $homeTeam vs $awayTeam');
      
      // Son 2 günlük maçlara bak
      final dates = _getLast2Days();
      
      for (var date in dates) {
        final snapshot = await _database
            .child('matchPool')
            .child(date)
            .get();
        
        if (snapshot.exists) {
          final matchesMap = snapshot.value as Map<dynamic, dynamic>;
          
          for (var entry in matchesMap.entries) {
            final matchData = entry.value as Map<dynamic, dynamic>;
            final match = MatchPoolModel.fromJson(
              Map<String, dynamic>.from(matchData),
            );
            
            // Fuzzy matching (%85 benzerlik)
            if (_isMatchingSimilar(homeTeam, match.homeTeam, 0.85) &&
                _isMatchingSimilar(awayTeam, match.awayTeam, 0.85)) {
              print('✅ Eşleşme bulundu: ${match.getMatchSummary()}');
              return match;
            }
          }
        }
      }
      
      print('⚠️ Havuzda bulunamadı: $homeTeam vs $awayTeam');
      return null;
    } catch (e) {
      print('❌ Havuz arama hatası: $e');
      return null;
    }
  }

  /// 🗑️ BİTEN MAÇLARI TEMİZLE
  Future<void> cleanOldMatches() async {
    try {
      print('🗑️ Eski maçlar temizleniyor...');
      
      final now = DateTime.now();
      final cutoffDate = now.subtract(const Duration(hours: 3)); // 3 saat önceki maçları sil
      
      final snapshot = await _database.child('matchPool').get();
      
      if (snapshot.exists) {
        final datesMap = snapshot.value as Map<dynamic, dynamic>;
        int deletedCount = 0;
        
        for (var dateEntry in datesMap.entries) {
          final date = dateEntry.key as String;
          final matchesMap = dateEntry.value as Map<dynamic, dynamic>;
          
          for (var matchEntry in matchesMap.entries) {
            final matchData = matchEntry.value as Map<dynamic, dynamic>;
            final timestamp = matchData['timestamp'] as int;
            
            // Maç 3 saat önceyse sil
            if (timestamp < cutoffDate.millisecondsSinceEpoch) {
              await _database
                  .child('matchPool')
                  .child(date)
                  .child(matchEntry.key)
                  .remove();
              deletedCount++;
            }
          }
          
          // Eğer o günün tüm maçları silindiyse tarihi de sil
          final remainingMatches = await _database
              .child('matchPool')
              .child(date)
              .get();
          
          if (!remainingMatches.exists || 
              (remainingMatches.value as Map).isEmpty) {
            await _database.child('matchPool').child(date).remove();
          }
        }
        
        print('✅ $deletedCount eski maç temizlendi');
      }
    } catch (e) {
      print('❌ Temizlik hatası: $e');
    }
  }

  /// 📊 HAVUZ İSTATİSTİKLERİ
  Future<Map<String, dynamic>> getPoolStats() async {
    try {
      final metadataSnapshot = await _database.child('poolMetadata').get();
      
      if (metadataSnapshot.exists) {
        return Map<String, dynamic>.from(metadataSnapshot.value as Map);
      }
      
      return {};
    } catch (e) {
      print('❌ Stats alma hatası: $e');
      return {};
    }
  }

  // ============= HELPER METHODS =============

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<String> _getLast2Days() {
    final now = DateTime.now();
    return [
      _formatDate(now),
      _formatDate(now.add(const Duration(days: 1))),
    ];
  }

  String _cleanTeamName(String name) {
    // Türkçe karakterleri temizle ve normalize et
    final map = {
      'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G',
      'ı': 'i', 'İ': 'I', 'ö': 'o', 'Ö': 'O',
      'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U',
    };
    
    var clean = name;
    map.forEach((turkish, english) {
      clean = clean.replaceAll(turkish, english);
    });
    
    return clean.trim();
  }

  /// Fuzzy string matching (Levenshtein distance)
  bool _isMatchingSimilar(String str1, String str2, double threshold) {
    str1 = _cleanTeamName(str1.toLowerCase());
    str2 = _cleanTeamName(str2.toLowerCase());
    
    final distance = _levenshteinDistance(str1, str2);
    final maxLength = str1.length > str2.length ? str1.length : str2.length;
    
    if (maxLength == 0) return true;
    
    final similarity = 1.0 - (distance / maxLength);
    return similarity >= threshold;
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }

      List<int> temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }
}
