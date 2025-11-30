import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bulletin_provider.dart';
import '../../services/gemini_service.dart';
import '../../services/football_api_service.dart';
import '../../services/match_pool_service.dart';

class AnalysisScreen extends StatefulWidget {
  final String bulletinId;
  final String base64Image;

  const AnalysisScreen({
    super.key,
    required this.bulletinId,
    required this.base64Image,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final GeminiService _geminiService = GeminiService();
  final FootballApiService _footballApi = FootballApiService();
  final MatchPoolService _matchPool = MatchPoolService();
  final BulletinProvider _bulletinProvider = BulletinProvider();

  bool _isAnalyzing = true;
  String _statusMessage = 'Görsel analiz ediliyor...';
  List<Map<String, dynamic>> _matches = [];
  List<Map<String, dynamic>> _analysisResults = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  Future<void> _startAnalysis() async {
    try {
      // 1. Görseli Gemini ile analiz et (maçları çıkar)
      await _updateStatus('analyzing', 'Görsel analiz ediliyor...');
      final geminiResponse = await _geminiService.analyzeImage(widget.base64Image);
      
      // JSON parse
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(geminiResponse);
      if (jsonMatch == null) {
        throw Exception('Gemini\'den geçersiz JSON yanıtı');
      }

      final jsonData = jsonDecode(jsonMatch.group(0)!);
      final matches = (jsonData['matches'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (matches.isEmpty) {
        throw Exception('Görselde maç bulunamadı');
      }

      // Debug: Gemini'nin çıkardığı isimleri göster
      print('📋 Gemini\'den gelen maçlar:');
      for (var match in matches) {
        print('  - ${match['homeTeam']} vs ${match['awayTeam']}');
      }

      setState(() {
        _matches = matches;
        _statusMessage = '${matches.length} maç bulundu. Analiz ediliyor...';
      });

      // 2. TÜM MAÇLARI TEK BATCH'TE ANALİZ ET (Rate Limit Çözümü)
      await _analyzeAllMatchesInBatch(matches);

      // 3. Başarılı - Firestore'a kaydet
      await _updateStatus('completed', 'Analiz tamamlandı!');
      
      setState(() {
        _isAnalyzing = false;
        _statusMessage = 'Analiz başarıyla tamamlandı!';
      });

    } catch (e) {
      print('❌ Analiz hatası: $e');
      await _updateStatus('failed', 'Analiz başarısız');
      
      setState(() {
        _isAnalyzing = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// ⭐ YENİ: Firebase Pool Öncelikli Sistem (Google Search Opsiyonel)
  Future<void> _analyzeAllMatchesInBatch(List<Map<String, dynamic>> matches) async {
    try {
      setState(() {
        _statusMessage = '🔥 Firebase havuzundan veriler alınıyor...';
      });

      // 1️⃣ ÖNCELİK: Firebase Pool
      List<Map<String, dynamic>> matchesWithData = [];
      int poolFoundCount = 0;
      int apiFoundCount = 0;
      
      for (int i = 0; i < matches.length; i++) {
        final match = matches[i];
        final homeTeam = match['homeTeam'] ?? '';
        final awayTeam = match['awayTeam'] ?? '';
        final userPrediction = match['userPrediction'] ?? '?';

        setState(() {
          _statusMessage = 'Maç ${i + 1}/${matches.length}: $homeTeam vs $awayTeam';
        });

        // 1️⃣ ÖNCELİK: Firebase Pool
        final poolMatch = await _matchPool.findMatchInPool(homeTeam, awayTeam);
        
        if (poolMatch != null) {
          // ✅ Pool'dan bulundu (EN HIZLI)
          poolFoundCount++;
          
          matchesWithData.add({
            'homeTeam': poolMatch.homeTeam,
            'awayTeam': poolMatch.awayTeam,
            'userPrediction': userPrediction,
            'homeStats': poolMatch.homeStats,
            'awayStats': poolMatch.awayStats,
            'h2h': poolMatch.h2h,
            'dataSource': 'firebase-pool',
          });
          
          print('✅ Maç ${i + 1}: Firebase Pool - $homeTeam vs $awayTeam');
          continue;
        }
        
        // 2️⃣ FALLBACK: Football API (rate limit ile)
        print('⚠️ Maç ${i + 1}: Havuzda yok, Football API kullanılıyor...');
        
        await Future.delayed(const Duration(milliseconds: 800));
        final homeData = await _getTeamDataFromFootballApi(homeTeam);
        
        await Future.delayed(const Duration(milliseconds: 800));
        final awayData = await _getTeamDataFromFootballApi(awayTeam);
        
        if (homeData['found']) apiFoundCount++;
        if (awayData['found']) apiFoundCount++;
        
        matchesWithData.add({
          'homeTeam': homeTeam,
          'awayTeam': awayTeam,
          'userPrediction': userPrediction,
          'homeData': homeData,
          'awayData': awayData,
          'dataSource': 'football-api',
        });
      }

      print('📊 Firebase Pool: $poolFoundCount/${matches.length} maç bulundu');
      print('📊 Football API: $apiFoundCount takım verisi çekildi');

      // 3️⃣ Gemini ile analiz (Basitleştirilmiş prompt)
      setState(() {
        _statusMessage = 'AI analizi yapılıyor...';
      });

      await Future.delayed(const Duration(seconds: 1));

      final prompt = _buildSimplePrompt(matchesWithData);
      
      final batchResponse = await _retryGeminiRequest(
        () => _geminiService.analyzeText(prompt), // ✅ Google Search YOK
        maxRetries: 3,
      );

      // 4️⃣ Yanıtı parse et
      final results = _parseBatchAnalysisResponse(batchResponse, matchesWithData);
      
      setState(() {
        _analysisResults = results;
      });

      // 5️⃣ Realtime Database'e kaydet
      await _saveBatchResults(results);

    } catch (e) {
      print('❌ Batch analiz hatası: $e');
      rethrow;
    }
  }

  /// Football API'den takım verisi al
  Future<Map<String, dynamic>> _getTeamDataFromFootballApi(String teamName) async {
    try {
      final teamInfo = await _footballApi.searchTeam(teamName);
      
      if (teamInfo == null) {
        return {'found': false, 'name': teamName};
      }

      final teamId = teamInfo['team']?['id'];
      final leagues = teamInfo['leagues'] as List<int>? ?? [];
      
      // ⭐ Lig yoksa istatistik alınamaz
      if (leagues.isEmpty) {
        print('⚠️ $teamName için lig bilgisi yok');
        return {
          'found': true,
          'name': teamInfo['team']?['name'] ?? teamName,
          'teamId': teamId,
          'stats': null,
          'lastMatches': [],
        };
      }

      // İlk ligi kullan (genelde en önemli lig)
      final leagueId = leagues.first;
      
      // İstatistikleri al (league parametresi ile)
      final stats = await _footballApi.getTeamStats(teamId, leagueId);
      final lastMatches = await _footballApi.getLastMatches(teamId, limit: 5);

      return {
        'found': true,
        'name': teamInfo['team']?['name'] ?? teamName,
        'teamId': teamId,
        'leagueId': leagueId,
        'stats': stats,
        'lastMatches': lastMatches,
      };
    } catch (e) {
      print('❌ Team data error ($teamName): $e');
      return {'found': false, 'name': teamName};
    }
  }

  /// ✅ Basitleştirilmiş prompt (Google Search olmadan)
  String _buildSimplePrompt(List<Map<String, dynamic>> matches) {
    final matchesInfo = matches.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final match = entry.value;
      
      String matchInfo = 'MAÇ $index: ${match['homeTeam']} vs ${match['awayTeam']}\n';
      matchInfo += 'Kullanıcı Tahmini: ${match['userPrediction']}\n';
      
      if (match['dataSource'] == 'firebase-pool') {
        // Firebase Pool'dan gelen veriler
        final homeStats = match['homeStats'];
        final awayStats = match['awayStats'];
        
        matchInfo += '\nEv Sahibi Form: ${homeStats?['form'] ?? 'Bilinmiyor'}\n';
        matchInfo += 'Deplasman Form: ${awayStats?['form'] ?? 'Bilinmiyor'}\n';
      } else {
        // Football API'den gelen veriler
        final homeData = match['homeData'];
        final awayData = match['awayData'];
        
        matchInfo += '\n${_formatTeamStats(homeData)}\n';
        matchInfo += '${_formatTeamStats(awayData)}\n';
      }
      
      return matchInfo;
    }).join('\n---\n');

    return '''
Profesyonel futbol analisti olarak analiz yap.

$matchesInfo

JSON formatında yanıt ver:
{
  "analyses": [
    {
      "matchIndex": 1,
      "homeTeam": "Takım Adı",
      "awayTeam": "Takım Adı",
      "aiPrediction": "1",
      "confidence": 75,
      "reasoning": "Kısa analiz (max 100 karakter)"
    }
  ]
}

Kurallar:
- aiPrediction: "1" (Ev Sahibi), "X" (Beraberlik), "2" (Deplasman)
- confidence: 0-100 arası
- reasoning: Maksimum 100 karakter

Sadece JSON döndür.
''';
  }

  String _formatTeamStats(Map<String, dynamic> teamData) {
    if (!teamData['found']) {
      return '- Veri yok (Google Search kullan)';
    }

    final stats = teamData['stats'];
    final lastMatches = teamData['lastMatches'] as List?;

    String result = '';
    
    if (stats != null && stats['form'] != null) {
      result += '- Form: ${stats['form']}\n';
    }
    
    if (lastMatches != null && lastMatches.isNotEmpty) {
      final results = lastMatches.take(5).map((m) {
        return '${m['goals']?['home']}-${m['goals']?['away']}';
      }).join(', ');
      result += '- Son 5: $results';
    }

    return result.isNotEmpty ? result : '- Kısmi veri var';
  }

  /// Batch yanıtını parse et
  List<Map<String, dynamic>> _parseBatchAnalysisResponse(
    String response,
    List<Map<String, dynamic>> originalMatches,
  ) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch == null) {
        throw Exception('Geçersiz JSON yanıtı');
      }

      final jsonData = jsonDecode(jsonMatch.group(0)!);
      final analyses = (jsonData['analyses'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      return analyses;
    } catch (e) {
      print('❌ Yanıt parse hatası: $e');
      
      // Fallback: Manuel sonuçlar oluştur
      return originalMatches.asMap().entries.map((entry) {
        final index = entry.key;
        final match = entry.value;
        
        return {
          'matchIndex': index + 1,
          'homeTeam': match['homeTeam'],
          'awayTeam': match['awayTeam'],
          'userPrediction': match['userPrediction'] ?? '?',
          'aiPrediction': '?',
          'confidence': 0,
          'reasoning': 'Analiz yapılamadı - Teknik hata',
          'dataSource': 'fallback',
        };
      }).toList();
    }
  }

  /// Gemini isteğini retry mekanizması ile yap
  Future<String> _retryGeminiRequest(Future<String> Function() request, {int maxRetries = 3}) async {
    int retryCount = 0;
    Duration retryDelay = const Duration(seconds: 5);

    while (retryCount < maxRetries) {
      try {
        return await request();
      } catch (e) {
        retryCount++;
        
        if (e.toString().contains('429')) {
          // Rate limit hatası - exponential backoff
          print('⏳ Rate limit - Bekleniyor: ${retryDelay.inSeconds}s (Deneme $retryCount/$maxRetries)');
          
          setState(() {
            _statusMessage = 'Rate limit - ${retryDelay.inSeconds}s bekleniyor...';
          });
          
          await Future.delayed(retryDelay);
          retryDelay *= 2; // Exponential backoff
          
          if (retryCount >= maxRetries) {
            throw Exception('Rate limit aşıldı - Lütfen birkaç dakika sonra tekrar deneyin');
          }
        } else {
          // Başka hata - direkt fırlat
          rethrow;
        }
      }
    }

    throw Exception('Maksimum deneme sayısı aşıldı');
  }

  /// Sonuçları Realtime Database'e kaydet
  Future<void> _saveBatchResults(List<Map<String, dynamic>> results) async {
    try {
      final database = FirebaseDatabase.instance;
      
      await database.ref('bulletins/${widget.bulletinId}').update({
        'matches': results,
        'analyzedAt': ServerValue.timestamp,
        'matchCount': results.length,
      });

      print('✅ ${results.length} maç analizi Realtime Database\'e kaydedildi');
    } catch (e) {
      print('❌ Database kayıt hatası: $e');
    }
  }

  Future<void> _updateStatus(String status, String message) async {
    await _bulletinProvider.updateBulletinStatus(widget.bulletinId, status);
    setState(() {
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analiz Sonuçları'),
        centerTitle: true,
      ),
      body: _isAnalyzing ? _buildLoadingView() : _buildResultsView(),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (_matches.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${_matches.length} maç tespit edildi',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsView() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 80, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'Analiz Başarısız',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Geri Dön'),
              ),
            ],
          ),
        ),
      );
    }

    final totalCount = _analysisResults.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Özet Kartı
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.sports_soccer,
                  size: 48,
                  color: Colors.blue[700],
                ),
                const SizedBox(height: 12),
                Text(
                  '$totalCount Maç Analiz Edildi',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.blue[900],
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'AI tarafından profesyonel analiz yapıldı',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Maç Sonuçları
        ..._analysisResults.map((result) => _buildMatchCard(result)),
      ],
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> result) {
    final confidence = result['confidence'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Maç Bilgisi
            Text(
              '${result['homeTeam']} vs ${result['awayTeam']}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 16),
            
            // AI Tahmini
            Row(
              children: [
                Icon(
                  Icons.psychology,
                  color: Colors.blue[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI Tahmini:',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatPrediction(result['aiPrediction']),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
                // Güven Seviyesi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _getConfidenceColor(confidence).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getConfidenceColor(confidence),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bar_chart,
                        size: 14,
                        color: _getConfidenceColor(confidence),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '%$confidence',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _getConfidenceColor(confidence),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Analiz Nedeni
            if (result['reasoning'] != null && result['reasoning'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result['reasoning'],
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[800],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatPrediction(dynamic prediction) {
    final pred = prediction.toString();
    switch (pred) {
      case '1':
        return 'Ev Sahibi Kazanır';
      case 'X':
        return 'Beraberlik';
      case '2':
        return 'Deplasman Kazanır';
      default:
        return 'Bilinmiyor';
    }
  }

  Color _getConfidenceColor(int confidence) {
    if (confidence >= 75) return Colors.green;
    if (confidence >= 50) return Colors.orange;
    return Colors.red;
  }
}