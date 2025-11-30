import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bulletin_provider.dart';
import '../../services/gemini_service.dart';
import '../../services/football_api_service.dart';

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

  /// ⭐ YENİ: Tüm maçları tek Gemini isteğinde analiz et
  Future<void> _analyzeAllMatchesInBatch(List<Map<String, dynamic>> matches) async {
    try {
      setState(() {
        _statusMessage = '${matches.length} maç için istatistikler toplanıyor...';
      });

      // 1. Tüm maçlar için Football API'den istatistikleri topla
      List<Map<String, dynamic>> matchesWithStats = [];
      
      for (int i = 0; i < matches.length; i++) {
        final match = matches[i];
        final homeTeam = match['homeTeam'] ?? '';
        final awayTeam = match['awayTeam'] ?? '';

        setState(() {
          _statusMessage = 'Maç ${i + 1}/${matches.length}: $homeTeam vs $awayTeam';
        });

        // Football API'den takım bilgisi çek (Rate limit için bekleme)
        if (i > 0) await Future.delayed(const Duration(milliseconds: 800));
        
        final homeStats = await _getTeamStatsWithFallback(homeTeam);
        
        // İkinci takım için de biraz bekle
        await Future.delayed(const Duration(milliseconds: 600));
        final awayStats = await _getTeamStatsWithFallback(awayTeam);

        matchesWithStats.add({
          'homeTeam': homeTeam,
          'awayTeam': awayTeam,
          'homeStats': homeStats,
          'awayStats': awayStats,
        });
      }

      // 2. TEK BİR GEMINI İSTEĞİNDE TÜM MAÇLARI ANALİZ ET
      setState(() {
        _statusMessage = 'AI analizi yapılıyor (tüm maçlar)...';
      });

      await Future.delayed(const Duration(seconds: 2)); // Rate limit için bekleme

      final batchPrompt = _createBatchAnalysisPrompt(matchesWithStats);
      final batchResponse = await _retryGeminiRequest(() => 
        _geminiService.analyzeText(batchPrompt)
      );

      // 3. Yanıtı parse et
      final results = _parseBatchAnalysisResponse(batchResponse, matchesWithStats);
      
      setState(() {
        _analysisResults = results;
      });

      // 4. Firestore'a kaydet
      await _saveBatchResults(results);

    } catch (e) {
      print('❌ Batch analiz hatası: $e');
      rethrow;
    }
  }

  /// Football API'den istatistik çek (hata durumunda fallback)
  Future<Map<String, dynamic>> _getTeamStatsWithFallback(String teamName) async {
    try {
      var teamData = await _footballApi.searchTeam(teamName);
      
      // İlk denemede bulunamadıysa, Gemini ile normalize et
      if (teamData == null) {
        print('🔄 Gemini ile normalize ediliyor: $teamName');
        final normalizedName = await _normalizeTeamNameWithGemini(teamName);
        
        if (normalizedName != null && normalizedName != teamName) {
          print('  ➡️ Normalize edildi: $teamName -> $normalizedName');
          teamData = await _footballApi.searchTeam(normalizedName);
        }
      }
      
      if (teamData != null) {
        final teamId = teamData['team']?['id'];
        if (teamId != null) {
          final stats = await _footballApi.getTeamStats(teamId, 2024);
          if (stats != null) {
            return {
              'found': true,
              'name': teamData['team']?['name'] ?? teamName,
              'stats': stats,
            };
          }
        }
      }

      // API'de bulunamadı
      print('! Takım API\'de bulunamadı: $teamName');
      return {
        'found': false,
        'name': teamName,
        'stats': null,
      };
    } catch (e) {
      print('❌ Takım istatistiği hatası ($teamName): $e');
      return {
        'found': false,
        'name': teamName,
        'stats': null,
      };
    }
  }

  /// Gemini ile takım ismini normalize et
  Future<String?> _normalizeTeamNameWithGemini(String teamName) async {
    try {
      final prompt = '''Takım ismi: "$teamName"

Bu takımın Football-API.com'da bulunabilecek resmi İngilizce ismini ver.

Örnekler:
- "Espanyol II" → "Espanyol B"
- "Valencia M." → "Valencia Mestalla"
- "UD Poblense" → "Poblense"
- "CE Andratx" → "Andratx"

Sadece takım ismini yaz, başka bir şey yazma.''';

      final response = await _geminiService.analyzeText(prompt);
      final normalized = response.trim().replaceAll('"', '');
      
      return normalized.isNotEmpty ? normalized : null;
    } catch (e) {
      print('❌ Gemini normalize hatası: $e');
      return null;
    }
  }

  /// Tüm maçlar için tek prompt oluştur
  String _createBatchAnalysisPrompt(List<Map<String, dynamic>> matches) {
    final matchesInfo = matches.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final match = entry.value;
      
      return '''
MAÇ $index:
- Ev Sahibi: ${match['homeTeam']} ${_formatStats(match['homeStats'])}
- Deplasman: ${match['awayTeam']} ${_formatStats(match['awayStats'])}
''';
    }).join('\n');

    return '''
Sen profesyonel bir futbol analistisin. Aşağıdaki ${matches.length} maçı analiz et ve her biri için tahmin ver.

$matchesInfo

Her maç için şu JSON formatında yanıt ver:
{
  "analyses": [
    {
      "matchIndex": 1,
      "homeTeam": "Takım Adı",
      "awayTeam": "Takım Adı",
      "aiPrediction": "X",
      "confidence": 75,
      "reasoning": "Net ve kısa analiz nedeni (max 100 karakter)"
    }
  ]
}

KURALLAR:
- aiPrediction: "1" (Ev Sahibi Kazanır), "X" (Beraberlik), veya "2" (Deplasman Kazanır)
- confidence: 0-100 arası güven seviyesi
- reasoning: Kısa ve net neden açıklaması (maksimum 100 karakter)
- Sadece JSON döndür, başka açıklama ekleme
''';
  }

  String _formatStats(Map<String, dynamic> statsData) {
    if (statsData['found'] != true) {
      return '(İstatistik yok)';
    }
    
    final stats = statsData['stats'];
    if (stats == null) return '(İstatistik yok)';

    return '''(Form: ${stats['form'] ?? '?'}, Gol Ort: ${stats['goals']?['for']?['average']?['total'] ?? '?'})''';
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
          'aiPrediction': '?',
          'confidence': 0,
          'reasoning': 'Analiz yapılamadı - Teknik hata',
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