import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'remote_config_service.dart';

class FootballApiService {
  final Dio _dio = Dio();
  final RemoteConfigService _remoteConfig = RemoteConfigService();
  
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  
  // API key'i Remote Config'den al
  String get _apiKey => _remoteConfig.footballApiKey;
  
  FootballApiService() {
    // Headers her request'te dinamik olarak ayarlanacak
  }
  
  // Her request için headers'ı ayarla
  void _setHeaders() {
    _dio.options.headers = {
      'x-rapidapi-key': _apiKey,
      'x-rapidapi-host': 'v3.football.api-sports.io',
    };
  }
  
  // Takım arama (fuzzy matching ile)
  Future<Map<String, dynamic>?> searchTeam(String teamName) async {
    try {
      _setHeaders(); // Headers'ı ayarla
      final response = await _dio.get(
        '$_baseUrl/teams',
        queryParameters: {
          'search': teamName,
        },
      );
      
      if (response.data['results'] > 0) {
        final teams = response.data['response'] as List;
        
        // En iyi eşleşmeyi bul
        final bestMatch = _findBestTeamMatch(teamName, teams);
        
        return bestMatch;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Takım arama hatası: $e');
      return null;
    }
  }
  
  // Maç arama
  Future<Map<String, dynamic>?> searchMatch({
    required int homeTeamId,
    required int awayTeamId,
    String? date,
  }) async {
    try {
      _setHeaders(); // Headers'ı ayarla
      // Tarihi belirle (bugünden +/- 7 gün)
      final searchDate = date ?? DateTime.now().toIso8601String().split('T')[0];
      
      final response = await _dio.get(
        '$_baseUrl/fixtures',
        queryParameters: {
          'date': searchDate,
          'team': homeTeamId,
        },
      );
      
      if (response.data['results'] > 0) {
        final fixtures = response.data['response'] as List;
        
        // Ev sahibi ve deplasman eşleşmesini bul
        for (var fixture in fixtures) {
          final home = fixture['teams']['home']['id'];
          final away = fixture['teams']['away']['id'];
          
          if (home == homeTeamId && away == awayTeamId) {
            return fixture;
          }
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Maç arama hatası: $e');
      return null;
    }
  }
  
  // Maç istatistiklerini getir
  Future<Map<String, dynamic>?> getMatchStatistics(int fixtureId) async {
    try {
      _setHeaders(); // Headers'ı ayarla
      final response = await _dio.get(
        '$_baseUrl/fixtures/statistics',
        queryParameters: {
          'fixture': fixtureId,
        },
      );
      
      if (response.data['results'] > 0) {
        return response.data['response'][0];
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Maç istatistik hatası: $e');
      return null;
    }
  }
  
  // Takımın son maçları
  Future<List<Map<String, dynamic>>> getTeamLastMatches(int teamId, {int limit = 5}) async {
    try {
      _setHeaders(); // Headers'ı ayarla
      final response = await _dio.get(
        '$_baseUrl/fixtures',
        queryParameters: {
          'team': teamId,
          'last': limit,
        },
      );
      
      if (response.data['results'] > 0) {
        return List<Map<String, dynamic>>.from(response.data['response']);
      }
      
      return [];
    } catch (e) {
      debugPrint('❌ Son maçlar hatası: $e');
      return [];
    }
  }
  
  // H2H (Head to Head) istatistikleri
  Future<List<Map<String, dynamic>>> getH2H(int team1Id, int team2Id) async {
    try {
      _setHeaders(); // Headers'ı ayarla
      final response = await _dio.get(
        '$_baseUrl/fixtures/headtohead',
        queryParameters: {
          'h2h': '$team1Id-$team2Id',
        },
      );
      
      if (response.data['results'] > 0) {
        return List<Map<String, dynamic>>.from(response.data['response']);
      }
      
      return [];
    } catch (e) {
      debugPrint('❌ H2H hatası: $e');
      return [];
    }
  }
  
  // Takım sakatlık/ceza durumu
  Future<List<Map<String, dynamic>>> getTeamInjuries(int teamId) async {
    try {
      _setHeaders(); // Headers'ı ayarla
      final response = await _dio.get(
        '$_baseUrl/injuries',
        queryParameters: {
          'team': teamId,
        },
      );
      
      if (response.data['results'] > 0) {
        return List<Map<String, dynamic>>.from(response.data['response']);
      }
      
      return [];
    } catch (e) {
      debugPrint('❌ Sakatlık bilgisi hatası: $e');
      return [];
    }
  }
  
  // Puan durumu
  Future<Map<String, dynamic>?> getStandings(int leagueId, int season) async {
    try {
      _setHeaders(); // Headers'ı ayarla
      final response = await _dio.get(
        '$_baseUrl/standings',
        queryParameters: {
          'league': leagueId,
          'season': season,
        },
      );
      
      if (response.data['results'] > 0) {
        return response.data['response'][0];
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Puan durumu hatası: $e');
      return null;
    }
  }
  
  // En iyi takım eşleşmesini bul (Levenshtein distance)
  Map<String, dynamic>? _findBestTeamMatch(String searchTerm, List teams) {
    if (teams.isEmpty) return null;
    
    // Basit eşleşme algoritması
    // Daha gelişmiş fuzzy matching için 'fuzzywuzzy' benzeri bir paket kullanılabilir
    
    int bestScore = 0;
    Map<String, dynamic>? bestMatch;
    
    for (var team in teams) {
      final teamName = team['team']['name'].toString().toLowerCase();
      final search = searchTerm.toLowerCase();
      
      int score = 0;
      
      // Tam eşleşme
      if (teamName == search) {
        score = 100;
      }
      // İçinde geçiyor mu
      else if (teamName.contains(search) || search.contains(teamName)) {
        score = 80;
      }
      // Başlangıç eşleşmesi
      else if (teamName.startsWith(search) || search.startsWith(teamName)) {
        score = 60;
      }
      
      if (score > bestScore) {
        bestScore = score;
        bestMatch = team;
      }
    }
    
    return bestMatch;
  }
  
  // Türkçe takım isimlerini normalize et
  String normalizeTeamName(String name) {
    final normalizations = {
      // Türkiye
      'galatasaray': ['gs', 'g.s', 'g.s.', 'gala', 'galata saray'],
      'fenerbahçe': ['fb', 'f.b', 'f.b.', 'fener', 'fenerbahce'],
      'beşiktaş': ['bjk', 'b.j.k', 'besiktas', 'beşiktas', 'besiktas'],
      'trabzonspor': ['ts', 't.s', 'trabzon', 'trabzon spor'],
      
      // İngiltere
      'manchester united': ['man utd', 'man united', 'manutd', 'mu'],
      'manchester city': ['man city', 'mancity', 'mc'],
      'liverpool': ['liverpool fc', 'lfc'],
      
      // İspanya
      'barcelona': ['barca', 'fc barcelona', 'fcb'],
      'real madrid': ['madrid', 'real', 'rm'],
      
      // Almanya
      'bayern munich': ['bayern', 'fcb', 'fc bayern'],
    };
    
    final lowerName = name.toLowerCase().trim();
    
    for (var entry in normalizations.entries) {
      if (entry.value.contains(lowerName)) {
        return entry.key;
      }
    }
    
    return lowerName;
  }
}