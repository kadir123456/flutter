import 'package:http/http.dart' as http;
import 'dart:convert';
import './remote_config_service.dart';

class FootballApiService {
  static final FootballApiService _instance = FootballApiService._internal();
  factory FootballApiService() => _instance;
  FootballApiService._internal();

  final String _baseUrl = 'https://v3.football.api-sports.io';
  final RemoteConfigService _remoteConfig = RemoteConfigService();
  
  String get _apiKey => _remoteConfig.footballApiKey;

  /// Takım bilgisi getir (isim ile arama - akıllı arama)
  Future<Map<String, dynamic>?> searchTeam(String teamName) async {
    try {
      // ⭐ YENİ: Türkçe karakterleri temizle
      final cleanName = _cleanTurkishChars(teamName);
      print('🔍 Aranıyor: $teamName → $cleanName');
      
      final url = Uri.parse('$_baseUrl/teams?search=$cleanName');

      final response = await http.get(
        url,
        headers: {
          'x-rapidapi-host': 'v3.football.api-sports.io',
          'x-rapidapi-key': _apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final teams = data['response'] as List?;
        
        if (teams != null && teams.isNotEmpty) {
          print('✅ Bulundu: ${teams.first['team']['name']}');
          return teams.first;
        }
        
        print('❌ Bulunamadı: $teamName');
        return null;
      } else if (response.statusCode == 429) {
        // ⭐ YENİ: Rate limit handling
        print('⚠️ Rate limit! 2 saniye bekleniyor...');
        await Future.delayed(const Duration(seconds: 2));
        return null;
      } else {
        throw Exception('Football API error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Football API Search Error: $e');
      return null;
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
    
    return clean;
  }

  /// Takım istatistikleri getir
  Future<Map<String, dynamic>?> getTeamStats(int teamId, {int? season}) async {
    season ??= DateTime.now().year;
    try {
      final url = Uri.parse('$_baseUrl/teams/statistics?team=$teamId&season=$season&league=203'); // Türkiye Süper Lig

      final response = await http.get(
        url,
        headers: {
          'x-rapidapi-host': 'v3.football.api-sports.io',
          'x-rapidapi-key': _apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'];
      } else {
        throw Exception('Football API error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Football API Stats Error: $e');
      return null;
    }
  }

  /// Son 5 maç sonucu
  Future<List<Map<String, dynamic>>> getLastMatches(int teamId, {int limit = 5}) async {
    try {
      final url = Uri.parse('$_baseUrl/fixtures?team=$teamId&last=$limit');

      final response = await http.get(
        url,
        headers: {
          'x-rapidapi-host': 'v3.football.api-sports.io',
          'x-rapidapi-key': _apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List?;
        return fixtures?.cast<Map<String, dynamic>>() ?? [];
      } else {
        throw Exception('Football API error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Football API Matches Error: $e');
      return [];
    }
  }

  /// İki takım arasındaki H2H (head to head)
  Future<List<Map<String, dynamic>>> getH2H(int team1Id, int team2Id) async {
    try {
      final url = Uri.parse('$_baseUrl/fixtures/headtohead?h2h=$team1Id-$team2Id');

      final response = await http.get(
        url,
        headers: {
          'x-rapidapi-host': 'v3.football.api-sports.io',
          'x-rapidapi-key': _apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fixtures = data['response'] as List?;
        return fixtures?.cast<Map<String, dynamic>>() ?? [];
      } else {
        throw Exception('Football API error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Football API H2H Error: $e');
      return [];
    }
  }

  /// API quota kontrolü
  Future<Map<String, dynamic>?> getApiStatus() async {
    try {
      final url = Uri.parse('$_baseUrl/status');

      final response = await http.get(
        url,
        headers: {
          'x-rapidapi-host': 'v3.football.api-sports.io',
          'x-rapidapi-key': _apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'];
      }
      return null;
    } catch (e) {
      print('❌ Football API Status Error: $e');
      return null;
    }
  }
}