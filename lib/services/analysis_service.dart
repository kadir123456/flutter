import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/bulletin_model.dart';
import '../providers/bulletin_provider.dart';
import 'gemini_service.dart';
import 'football_api_service.dart';

class AnalysisService {
  final GeminiAnalysisService _gemini = GeminiAnalysisService();
  final FootballApiService _footballApi = FootballApiService();
  
  // Bülten analiz pipeline'ı
  Future<bool> analyzeBulletin({
    required String bulletinId,
    required String imageBase64,
    required BulletinProvider bulletinProvider,
    Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('Görsel analiz ediliyor...');
      
      // 1. ADIM: Görselden maç bilgilerini çıkar
      final matchesData = await _gemini.analyzeMatchImage(imageBase64);
      
      if (matchesData == null || matchesData['matches'] == null) {
        throw Exception('Görselden maç bilgisi çıkarılamadı');
      }
      
      final matches = matchesData['matches'] as List;
      
      if (matches.isEmpty) {
        throw Exception('Görselde maç bulunamadı');
      }
      
      onProgress?.call('${matches.length} maç bulundu, analiz ediliyor...');
      
      final predictions = <MatchPrediction>[];
      
      // 2. ADIM: Her maç için detaylı analiz
      for (int i = 0; i < matches.length; i++) {
        final match = matches[i];
        onProgress?.call('Maç ${i + 1}/${matches.length} analiz ediliyor...');
        
        try {
          // 2a. Takımları bul
          final homeTeamName = _normalizeTeamName(match['homeTeam']);
          final awayTeamName = _normalizeTeamName(match['awayTeam']);
          
          final homeTeamData = await _footballApi.searchTeam(homeTeamName);
          final awayTeamData = await _footballApi.searchTeam(awayTeamName);
          
          if (homeTeamData == null || awayTeamData == null) {
            print('⚠️ Takımlar API\'de bulunamadı: $homeTeamName vs $awayTeamName');
            
            // API'de bulunamasa bile basit analiz yap
            final basicAnalysis = await _createBasicAnalysis(
              homeTeam: match['homeTeam'],
              awayTeam: match['awayTeam'],
              userPrediction: match['userPrediction'] ?? '1',
            );
            
            predictions.add(basicAnalysis);
            continue;
          }
          
          // 2b. Maç istatistiklerini topla
          final stats = await _collectMatchStats(
            homeTeamId: homeTeamData['team']['id'],
            awayTeamId: awayTeamData['team']['id'],
            homeTeamName: homeTeamData['team']['name'],
            awayTeamName: awayTeamData['team']['name'],
          );
          
          // 2c. Gemini ile detaylı analiz
          final analysis = await _gemini.analyzeMatch(
            homeTeam: homeTeamData['team']['name'],
            awayTeam: awayTeamData['team']['name'],
            userPrediction: match['userPrediction'] ?? '1',
            matchStats: stats,
          );
          
          if (analysis != null) {
            predictions.add(_convertAnalysisToP prediction(
              homeTeam: homeTeamData['team']['name'],
              awayTeam: awayTeamData['team']['name'],
              userPrediction: match['userPrediction'] ?? '1',
              analysis: analysis,
            ));
          }
        } catch (e) {
          print('❌ Maç analiz hatası: ${match['homeTeam']} vs ${match['awayTeam']} - $e');
          
          // Hata durumunda basit analiz ekle
          final basicAnalysis = await _createBasicAnalysis(
            homeTeam: match['homeTeam'],
            awayTeam: match['awayTeam'],
            userPrediction: match['userPrediction'] ?? '1',
          );
          predictions.add(basicAnalysis);
        }
      }
      
      // 3. ADIM: Genel bülten değerlendirmesi
      onProgress?.call('Genel değerlendirme yapılıyor...');
      
      final overallSummary = await _gemini.analyzeBulletinOverall(
        predictions.map((p) => {
          'homeTeam': p.homeTeam,
          'awayTeam': p.awayTeam,
          'userPrediction': p.userPrediction,
          'confidence': p.successProbability,
        }).toList(),
      );
      
      // 4. ADIM: Sonuçları kaydet
      final analysis = BulletinAnalysis(
        extractedText: matchesData.toString(),
        predictions: predictions,
        overallSuccessRate: _calculateOverallSuccessRate(predictions),
        geminiSummary: overallSummary ?? 'Genel değerlendirme alınamadı.',
      );
      
      // Bulletin'i güncelle
      await bulletinProvider.updateBulletinAnalysis(bulletinId, analysis);
      
      onProgress?.call('Analiz tamamlandı! ✅');
      
      return true;
    } catch (e) {
      print('❌ Bülten analiz hatası: $e');
      onProgress?.call('Analiz başarısız: $e');
      return false;
    }
  }
  
  // Maç istatistiklerini topla
  Future<Map<String, dynamic>> _collectMatchStats({
    required int homeTeamId,
    required int awayTeamId,
    required String homeTeamName,
    required String awayTeamName,
  }) async {
    final stats = <String, dynamic>{};
    
    try {
      // Son 5 maç
      final homeLast = await _footballApi.getTeamLastMatches(homeTeamId, limit: 5);
      final awayLast = await _footballApi.getTeamLastMatches(awayTeamId, limit: 5);
      
      stats['last5Matches'] = {
        'home': _formatLastMatches(homeLast, homeTeamId),
        'away': _formatLastMatches(awayLast, awayTeamId),
      };
      
      // Gol ortalamaları
      stats['goalStats'] = {
        'homeAvg': _calculateGoalAverage(homeLast, homeTeamId),
        'awayAvg': _calculateGoalAverage(awayLast, awayTeamId),
      };
      
      // H2H
      final h2h = await _footballApi.getH2H(homeTeamId, awayTeamId);
      stats['h2h'] = _formatH2H(h2h, homeTeamId);
      
      // Sakatlıklar
      final homeInjuries = await _footballApi.getTeamInjuries(homeTeamId);
      final awayInjuries = await _footballApi.getTeamInjuries(awayTeamId);
      
      stats['injuries'] = {
        'home': homeInjuries.length,
        'away': awayInjuries.length,
        'details': '${homeTeamName}: ${homeInjuries.length} sakatlık, ${awayTeamName}: ${awayInjuries.length} sakatlık',
      };
    } catch (e) {
      print('⚠️ İstatistik toplama hatası: $e');
    }
    
    return stats;
  }
  
  // Son maçları formatla (WWLDW formatında)
  String _formatLastMatches(List<Map<String, dynamic>> matches, int teamId) {
    if (matches.isEmpty) return 'Veri yok';
    
    final results = matches.take(5).map((match) {
      final homeTeam = match['teams']['home'];
      final awayTeam = match['teams']['away'];
      final homeGoals = match['goals']['home'] ?? 0;
      final awayGoals = match['goals']['away'] ?? 0;
      
      final isHome = homeTeam['id'] == teamId;
      final teamGoals = isHome ? homeGoals : awayGoals;
      final opponentGoals = isHome ? awayGoals : homeGoals;
      
      if (teamGoals > opponentGoals) return 'W';
      if (teamGoals < opponentGoals) return 'L';
      return 'D';
    }).join('');
    
    return results;
  }
  
  // Gol ortalaması hesapla
  double _calculateGoalAverage(List<Map<String, dynamic>> matches, int teamId) {
    if (matches.isEmpty) return 0.0;
    
    int totalGoals = 0;
    
    for (var match in matches.take(5)) {
      final homeTeam = match['teams']['home'];
      final awayTeam = match['teams']['away'];
      final homeGoals = match['goals']['home'] ?? 0;
      final awayGoals = match['goals']['away'] ?? 0;
      
      final isHome = homeTeam['id'] == teamId;
      totalGoals += isHome ? homeGoals : awayGoals;
    }
    
    return totalGoals / matches.length;
  }
  
  // H2H formatla
  String _formatH2H(List<Map<String, dynamic>> h2h, int homeTeamId) {
    if (h2h.isEmpty) return 'Önceki karşılaşma yok';
    
    int homeWins = 0;
    int draws = 0;
    int awayWins = 0;
    
    for (var match in h2h.take(5)) {
      final homeId = match['teams']['home']['id'];
      final homeGoals = match['goals']['home'] ?? 0;
      final awayGoals = match['goals']['away'] ?? 0;
      
      if (homeGoals > awayGoals) {
        if (homeId == homeTeamId) {
          homeWins++;
        } else {
          awayWins++;
        }
      } else if (homeGoals < awayGoals) {
        if (homeId == homeTeamId) {
          awayWins++;
        } else {
          homeWins++;
        }
      } else {
        draws++;
      }
    }
    
    return 'Son ${h2h.length} maç: $homeWins galibiyet, $draws beraberlik, $awayWins mağlubiyet';
  }
  
  // Analiz sonucunu MatchPrediction'a çevir
  MatchPrediction _convertAnalysisToPrediction({
    required String homeTeam,
    required String awayTeam,
    required String userPrediction,
    required Map<String, dynamic> analysis,
  }) {
    return MatchPrediction(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      userPrediction: userPrediction,
      geminiPrediction: analysis['prediction']['type'] ?? userPrediction,
      successProbability: (analysis['prediction']['confidence'] ?? 50).toDouble(),
      reasoning: analysis['reasoning'] ?? 'Detaylı analiz yapılamadı.',
    );
  }
  
  // Basit analiz oluştur (API bulunamadığında)
  Future<MatchPrediction> _createBasicAnalysis({
    required String homeTeam,
    required String awayTeam,
    required String userPrediction,
  }) async {
    return MatchPrediction(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      userPrediction: userPrediction,
      geminiPrediction: userPrediction,
      successProbability: 50.0,
      reasoning: 'Bu maç için detaylı istatistik bulunamadı. Tahmininiz orta risk seviyesinde.',
    );
  }
  
  // Genel başarı oranı hesapla
  double _calculateOverallSuccessRate(List<MatchPrediction> predictions) {
    if (predictions.isEmpty) return 0.0;
    
    final total = predictions.fold<double>(
      0.0,
      (sum, p) => sum + p.successProbability,
    );
    
    return total / predictions.length;
  }
  
  // Takım ismini normalize et
  String _normalizeTeamName(String name) {
    return _footballApi.normalizeTeamName(name);
  }
}