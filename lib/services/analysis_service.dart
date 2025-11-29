import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/bulletin_model.dart';
import '../providers/bulletin_provider.dart';
import 'gemini_service.dart';
import 'football_api_service.dart';

class AnalysisService {
  final GeminiService _gemini = GeminiService();
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
      final geminiResponse = await _gemini.analyzeImage(imageBase64);
      
      if (geminiResponse.isEmpty) {
        throw Exception('Görselden maç bilgisi çıkarılamadı');
      }
      
      // JSON parse et
      final matchesData = _parseGeminiResponse(geminiResponse);
      
      if (matchesData == null || matchesData['matches'] == null) {
        throw Exception('Görsel analizi başarısız oldu');
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
            if (kDebugMode) {
              print('⚠️ Takımlar API\'de bulunamadı: $homeTeamName vs $awayTeamName');
            }
            
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
          final analysisPrompt = _buildAnalysisPrompt(
            homeTeam: homeTeamData['team']['name'],
            awayTeam: awayTeamData['team']['name'],
            userPrediction: match['userPrediction'] ?? '1',
            matchStats: stats,
          );
          
          final analysisResponse = await _gemini.analyzeText(analysisPrompt);
          final analysis = _parseAnalysisResponse(analysisResponse);
          
          if (analysis != null) {
            predictions.add(_convertAnalysisToPrediction(
              homeTeam: homeTeamData['team']['name'],
              awayTeam: awayTeamData['team']['name'],
              userPrediction: match['userPrediction'] ?? '1',
              analysis: analysis,
            ));
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Maç analiz hatası: ${match['homeTeam']} vs ${match['awayTeam']} - $e');
          }
          
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
      
      final overallPrompt = _buildOverallPrompt(predictions);
      final overallResponse = await _gemini.analyzeText(overallPrompt);
      final overallSummary = overallResponse.isNotEmpty 
          ? overallResponse 
          : 'Genel değerlendirme alınamadı.';
      
      // 4. ADIM: Sonuçları kaydet
      final overallSuccessRate = _calculateOverallSuccessRate(predictions);
      final analysis = BulletinAnalysis(
        predictions: predictions,
        overall: OverallAssessment(
          successProbability: overallSuccessRate,
          riskiestPicks: _findRiskiestPicks(predictions),
          strategy: overallSummary,
        ),
      );
      
      // Bulletin'i güncelle
      await bulletinProvider.updateBulletinAnalysis(bulletinId, analysis.toMap());
      
      onProgress?.call('Analiz tamamlandı! ✅');
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Bülten analiz hatası: $e');
      }
      onProgress?.call('Analiz başarısız: $e');
      return false;
    }
  }
  
  // Gemini response'unu parse et
  Map<String, dynamic>? _parseGeminiResponse(String response) {
    try {
      // JSON bloğunu bul
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!);
      }
      
      // Alternatif: code block içinde JSON
      final codeBlockMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(response);
      if (codeBlockMatch != null) {
        return jsonDecode(codeBlockMatch.group(1)!);
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ JSON parse hatası: $e');
      }
      return null;
    }
  }
  
  // Analiz response'unu parse et
  Map<String, dynamic>? _parseAnalysisResponse(String response) {
    try {
      final parsed = _parseGeminiResponse(response);
      if (parsed != null) return parsed;
      
      // Basit text yanıt döndüyse, varsayılan yapı oluştur
      return {
        'prediction': {'type': '1', 'confidence': 50},
        'reasoning': response,
        'alternatives': [],
        'risk': {'level': 'medium', 'factors': []},
      };
    } catch (e) {
      return null;
    }
  }
  
  // Analiz prompt'u oluştur
  String _buildAnalysisPrompt({
    required String homeTeam,
    required String awayTeam,
    required String userPrediction,
    required Map<String, dynamic> matchStats,
  }) {
    return '''
Futbol maçı analizi yap ve JSON formatında yanıt ver.

Maç: $homeTeam vs $awayTeam
Kullanıcı Tahmini: $userPrediction (1=Ev Sahibi, X=Beraberlik, 2=Deplasman)

İstatistikler:
${jsonEncode(matchStats)}

Şu formatta JSON yanıt ver:
{
  "prediction": {
    "type": "1", // 1, X veya 2
    "confidence": 75 // 0-100 arası
  },
  "reasoning": "Detaylı açıklama...",
  "alternatives": ["X", "2"],
  "risk": {
    "level": "low", // low, medium, high
    "factors": ["Risk faktörleri listesi"]
  }
}
''';
  }
  
  // Genel değerlendirme prompt'u
  String _buildOverallPrompt(List<MatchPrediction> predictions) {
    final summary = predictions.map((p) => 
      '${p.homeTeam} vs ${p.awayTeam}: Tahmin ${p.userPrediction}, Güven %${p.confidence.toInt()}'
    ).join('\n');
    
    return '''
Şu bülten için genel strateji önerisi ver:

$summary

Kısa ve öz bir değerlendirme yap (max 3 cümle).
''';
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
      final homeLast = await _footballApi.getLastMatches(homeTeamId, 5);
      final awayLast = await _footballApi.getLastMatches(awayTeamId, 5);
      
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
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ İstatistik toplama hatası: $e');
      }
    }
    
    return stats;
  }
  
  // Son maçları formatla (WWLDW formatında)
  String _formatLastMatches(List<Map<String, dynamic>> matches, int teamId) {
    if (matches.isEmpty) return 'Veri yok';
    
    final results = matches.take(5).map((match) {
      final homeTeam = match['teams']['home'];
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
      final homeGoals = match['goals']['home'] ?? 0;
      final awayGoals = match['goals']['away'] ?? 0;
      
      final isHome = homeTeam['id'] == teamId;
      totalGoals += (isHome ? homeGoals : awayGoals) as int;
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
      aiPrediction: analysis['prediction']['type'] ?? userPrediction,
      confidence: (analysis['prediction']['confidence'] ?? 50).toDouble(),
      reasoning: analysis['reasoning'] ?? 'Detaylı analiz yapılamadı.',
      alternativePredictions: List<String>.from(analysis['alternatives'] ?? []),
      risk: RiskAnalysis(
        level: analysis['risk']['level'] ?? 'medium',
        factors: List<String>.from(analysis['risk']['factors'] ?? []),
      ),
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
      aiPrediction: userPrediction,
      confidence: 50.0,
      reasoning: 'Bu maç için detaylı istatistik bulunamadı. Tahmininiz orta risk seviyesinde.',
      alternativePredictions: [],
      risk: RiskAnalysis(
        level: 'medium',
        factors: ['Veri eksikliği'],
      ),
    );
  }
  
  // Genel başarı oranı hesapla
  double _calculateOverallSuccessRate(List<MatchPrediction> predictions) {
    if (predictions.isEmpty) return 0.0;
    
    final total = predictions.fold<double>(
      0.0,
      (sum, p) => sum + p.confidence,
    );
    
    return total / predictions.length;
  }
  
  // En riskli tahminleri bul
  List<String> _findRiskiestPicks(List<MatchPrediction> predictions) {
    final risky = predictions
        .where((p) => p.confidence < 60.0)
        .map((p) => '${p.homeTeam} vs ${p.awayTeam}')
        .toList();
    return risky;
  }
  
  // Takım ismini normalize et
  String _normalizeTeamName(String name) {
    // Türkçe karakterleri temizle
    final normalized = name
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'I')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 'S')
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'G')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'O')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C')
        .trim();
    
    return normalized;
  }
}
