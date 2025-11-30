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
      // İlk deneme: Orijinal isim
      var result = await _searchTeamByName(teamName);
      if (result != null) return result;

      // İkinci deneme: "B" yerine "II" dene
      if (teamName.contains(' B')) {
        final altName = teamName.replaceAll(' B', ' II');
        result = await _searchTeamByName(altName);
        if (result != null) {
          print('✅ Alternatif isimle bulundu: $teamName -> $altName');
          return result;
        }
      }

      // Üçüncü deneme: "II" yerine "B" dene
      if (teamName.contains(' II')) {
        final altName = teamName.replaceAll(' II', ' B');
        result = await _searchTeamByName(altName);
        if (result != null) {
          print('✅ Alternatif isimle bulundu: $teamName -> $altName');
          return result;
        }
      }

      // Dördüncü deneme: Sadece ana takım ismi (UD, SD, CE gibi önekleri kaldır)
      final cleanName = _cleanTeamName(teamName);
      if (cleanName != teamName) {
        result = await _searchTeamByName(cleanName);
        if (result != null) {
          print('✅ Temiz isimle bulundu: $teamName -> $cleanName');
          return result;
        }
      }

      print('⚠️ Takım bulunamadı (tüm varyasyonlar denendi): $teamName');
      return null;
    } catch (e) {
      print('❌ Football API Search Error: $e');
      return null;
    }
  }

  /// Gerçek API çağrısı
  Future<Map<String, dynamic>?> _searchTeamByName(String teamName) async {
    try {
      final url = Uri.parse('$_baseUrl/teams?search=$teamName');

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
          return teams.first;
        }
        return null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Takım ismini temizle (UD, SD, CE gibi önekleri kaldır)
  String _cleanTeamName(String teamName) {
    // Önekleri kaldır
    final prefixes = ['UD ', 'SD ', 'CE ', 'CD ', 'CA ', 'UE ', 'CF '];
    for (final prefix in prefixes) {
      if (teamName.startsWith(prefix)) {
        return teamName.substring(prefix.length);
      }
    }
    return teamName;
  }

  /// Takım istatistikleri getir
  Future<Map<String, dynamic>?> getTeamStats(int teamId, int season) async {
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
  Future<List<Map<String, dynamic>>> getLastMatches(int teamId, int limit) async {
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