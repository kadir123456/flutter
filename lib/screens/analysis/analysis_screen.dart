import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bulletin_provider.dart';
import '../../services/gemini_service.dart';
import '../../services/gemini_service_secure.dart'; // 🔐 Güvenli Gemini
import '../../services/football_api_service.dart';
import '../../services/football_api_service_secure.dart'; // 🔐 Güvenli Football
import '../../services/match_pool_service.dart';

class AnalysisScreen extends StatefulWidget {
  final String bulletinId;
  final String? base64Image; // Optional - null ise Firebase'den yükle

  const AnalysisScreen({
    super.key,
    required this.bulletinId,
    this.base64Image,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  // 🔐 GÜVENLİ SERVİSLER - Cloud Functions üzerinden
  final GeminiServiceSecure _geminiService = GeminiServiceSecure();
  final FootballApiServiceSecure _footballApi = FootballApiServiceSecure();
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
    
    // Eğer base64Image varsa -> Yeni analiz
    // Eğer base64Image yoksa -> Firebase'den tamamlanmış analizi yükle
    if (widget.base64Image != null) {
      _startAnalysis();
    } else {
      _loadExistingAnalysis();
    }
  }

  /// Firebase'den tamamlanmış analizi yükle (geçmiş görüntüleme için)
  Future<void> _loadExistingAnalysis() async {
    try {
      setState(() {
        _statusMessage = 'Analiz yükleniyor...';
      });

      final database = FirebaseDatabase.instance;
      final snapshot = await database.ref('bulletins/${widget.bulletinId}').get();
      
      if (!snapshot.exists) {
        throw Exception('Analiz bulunamadı');
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final matchesRaw = data['matches'];
      
      if (matchesRaw == null) {
        throw Exception('Bu analizde maç bilgisi bulunamadı');
      }

      // Firebase'den gelen veriyi temiz Map listesine dönüştür
      final List<Map<String, dynamic>> parsedMatches = [];
      
      if (matchesRaw is List) {
        for (var match in matchesRaw) {
          if (match != null) {
            // Her bir match'i deep copy ile Map<String, dynamic>'e dönüştür
            final matchMap = _deepConvertToMap(match);
            parsedMatches.add(matchMap);
          }
        }
      }
      
      if (parsedMatches.isEmpty) {
        throw Exception('Maç bilgisi okunamadı');
      }

      print('✅ ${parsedMatches.length} maç yüklendi');

      setState(() {
        _isAnalyzing = false;
        _analysisResults = parsedMatches;
        _statusMessage = 'Analiz yüklendi';
      });

    } catch (e) {
      print('❌ Analiz yükleme hatası: $e');
      setState(() {
        _isAnalyzing = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// Firebase LinkedMap'i Map<String, dynamic>'e deep convert
  Map<String, dynamic> _deepConvertToMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((key, val) => MapEntry(key.toString(), _deepConvertValue(val)))
      );
    }
    return {};
  }

  /// Değerleri de dönüştür (recursive)
  dynamic _deepConvertValue(dynamic value) {
    if (value is Map) {
      return _deepConvertToMap(value);
    } else if (value is List) {
      return value.map((item) => _deepConvertValue(item)).toList();
    }
    return value;
  }

  Future<void> _startAnalysis() async {
    try {
      // 1. Görseli Gemini ile analiz et (maçları çıkar)
      await _updateStatus('analyzing', 'Görsel analiz ediliyor...');
      final geminiResponse = await _geminiService.analyzeImage(widget.base64Image!);
      
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
          // ✅ Pool'dan bulundu (Fixture ID belli!)
          poolFoundCount++;
          
          // ⭐ YENİ: Stats yoksa API'den çek (ON-DEMAND)
          var homeStats = poolMatch.homeStats;
          var awayStats = poolMatch.awayStats;
          var h2h = poolMatch.h2h ?? [];
          
          if (homeStats == null || awayStats == null) {
            print('📊 Stats yoksa API\'den çekiliyor: ${poolMatch.fixtureId}');
            
            setState(() {
              _statusMessage = 'İstatistikler alınıyor: $homeTeam vs $awayTeam';
            });
            
            // Home Stats
            await Future.delayed(const Duration(milliseconds: 800));
            homeStats = await _footballApi.getTeamStats(
              poolMatch.homeTeamId, 
              poolMatch.leagueId,
            );
            
            // Away Stats
            await Future.delayed(const Duration(milliseconds: 800));
            awayStats = await _footballApi.getTeamStats(
              poolMatch.awayTeamId, 
              poolMatch.leagueId,
            );
            
            // H2H
            await Future.delayed(const Duration(milliseconds: 800));
            h2h = await _footballApi.getH2H(
              poolMatch.homeTeamId, 
              poolMatch.awayTeamId,
            );
            
            print('✅ Stats çekildi: $homeTeam vs $awayTeam');
          } else {
            print('✅ Stats zaten mevcut (Firebase Pool): $homeTeam vs $awayTeam');
          }
          
          matchesWithData.add({
            'homeTeam': poolMatch.homeTeam,
            'awayTeam': poolMatch.awayTeam,
            'userPrediction': userPrediction,
            'homeStats': homeStats,
            'awayStats': awayStats,
            'h2h': h2h,
            'fixtureId': poolMatch.fixtureId,
            'leagueId': poolMatch.leagueId,
            'dataSource': homeStats != null ? 'firebase-pool-with-stats' : 'firebase-pool',
          });
          
          print('✅ Maç ${i + 1}: Firebase Pool - $homeTeam vs $awayTeam (Stats: ${homeStats != null ? 'VAR' : 'YOK'})');
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

  /// ✅ Geliştirilmiş prompt - Çoklu tahmin tipleri
  String _buildSimplePrompt(List<Map<String, dynamic>> matches) {
    final matchesInfo = matches.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final match = entry.value;
      
      String matchInfo = 'MAÇ $index: ${match['homeTeam']} vs ${match['awayTeam']}\n';
      matchInfo += 'Kullanıcı Tahmini: ${match['userPrediction']}\n';
      
      bool hasFullData = false;
      bool hasPartialData = false;
      
      if (match['dataSource'] == 'firebase-pool-with-stats' || match['dataSource'] == 'firebase-pool') {
        // Firebase Pool'dan gelen veriler (stats API'den çekilmiş olabilir)
        final homeStats = match['homeStats'];
        final awayStats = match['awayStats'];
        final h2h = match['h2h'] as List?;
        
        if (homeStats != null && awayStats != null) {
          hasFullData = true;
          matchInfo += '\n📊 Ev Sahibi İstatistikleri:\n';
          matchInfo += '  Form: ${homeStats['form'] ?? 'Bilinmiyor'}\n';
          matchInfo += '  Atılan Gol (Ort): ${homeStats['goals']?['for']?['average']?['total'] ?? 'Bilinmiyor'}\n';
          matchInfo += '  Yenilen Gol (Ort): ${homeStats['goals']?['against']?['average']?['total'] ?? 'Bilinmiyor'}\n';
          matchInfo += '  Toplam Gol: ${homeStats['goals']?['for']?['total']?['total'] ?? 'Bilinmiyor'}\n';
          
          matchInfo += '\n📊 Deplasman İstatistikleri:\n';
          matchInfo += '  Form: ${awayStats['form'] ?? 'Bilinmiyor'}\n';
          matchInfo += '  Atılan Gol (Ort): ${awayStats['goals']?['for']?['average']?['total'] ?? 'Bilinmiyor'}\n';
          matchInfo += '  Yenilen Gol (Ort): ${awayStats['goals']?['against']?['average']?['total'] ?? 'Bilinmiyor'}\n';
          matchInfo += '  Toplam Gol: ${awayStats['goals']?['for']?['total']?['total'] ?? 'Bilinmiyor'}\n';
        } else {
          hasPartialData = true;
          matchInfo += '\n⚠️ İstatistik verisi kısıtlı\n';
        }
        
        if (h2h != null && h2h.isNotEmpty) {
          matchInfo += '\n🔄 Son Karşılaşmalar (H2H): ${h2h.length} maç\n';
        }
      } else {
        // Football API'den gelen veriler
        final homeData = match['homeData'];
        final awayData = match['awayData'];
        
        if (homeData['found'] && awayData['found'] && homeData['stats'] != null && awayData['stats'] != null) {
          hasFullData = true;
        } else {
          hasPartialData = true;
        }
        
        matchInfo += '\n${_formatTeamStats(homeData)}\n';
        matchInfo += '${_formatTeamStats(awayData)}\n';
      }
      
      matchInfo += '\n📌 Veri Kalitesi: ${hasFullData ? 'TAM VERİ' : hasPartialData ? 'KISITLI VERİ' : 'VERİ YOK'}\n';
      
      return matchInfo;
    }).join('\n---\n');

    return '''
Sen profesyonel bir futbol analisti ve bahis uzmanısın. Verilen istatistiklere göre detaylı tahminler yap.

$matchesInfo

JSON formatında yanıt ver:
{
  "analyses": [
    {
      "matchIndex": 1,
      "homeTeam": "Takım Adı",
      "awayTeam": "Takım Adı",
      "dataQuality": "full|partial|none",
      "predictions": {
        "MS": {"prediction": "1", "confidence": 75, "reasoning": "Açıklama"},
        "IY": {"prediction": "1", "confidence": 65, "reasoning": "Açıklama"},
        "AltUst": {"prediction": "Üst 2.5", "confidence": 70, "reasoning": "Açıklama"},
        "KG": {"prediction": "Var", "confidence": 60, "reasoning": "Açıklama"},
        "Korner": {"prediction": "Üst 9.5", "confidence": 55, "reasoning": "Açıklama"}
      },
      "generalNote": "Genel değerlendirme (max 150 karakter)"
    }
  ]
}

Tahmin Açıklamaları:
- MS (Maç Sonucu): "1" (Ev Sahibi), "X" (Beraberlik), "2" (Deplasman)
- IY (İlk Yarı): "1" (Ev Sahibi), "X" (Beraberlik), "2" (Deplasman)
- AltUst: "Alt 2.5" veya "Üst 2.5" (Toplam gol)
- KG (Karşılıklı Gol): "Var" veya "Yok"
- Korner: "Alt 9.5" veya "Üst 9.5"

ÖNEMLİ KURALLAR:
1. dataQuality: "full" (tam veri), "partial" (kısıtlı veri), "none" (veri yok)
2. Eğer veri yoksa veya kısıtlıysa, confidence değerlerini düşük tut (30-50)
3. Veri yoksa reasoning'de "VERİ YETERSİZ - Tahmin güvenilir değil" yaz
4. confidence: 0-100 arası sayı
5. reasoning: Her tahmin için maksimum 80 karakter
6. generalNote: Genel değerlendirme, maksimum 150 karakter

Sadece JSON döndür, başka açıklama ekleme.
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

  /// Batch yanıtını parse et - Yeni çoklu tahmin formatı
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

      if (analyses.isEmpty) {
        throw Exception('Boş analiz yanıtı');
      }

      print('✅ ${analyses.length} maç analizi parse edildi');
      return analyses;
    } catch (e) {
      print('❌ Yanıt parse hatası: $e');
      print('📄 Response: ${response.substring(0, response.length > 500 ? 500 : response.length)}...');
      
      // Fallback: Manuel sonuçlar oluştur (yeni format)
      return originalMatches.asMap().entries.map((entry) {
        final index = entry.key;
        final match = entry.value;
        final dataSource = match['dataSource'] ?? 'unknown';
        
        // Veri kalitesini belirle
        String dataQuality = 'none';
        if (dataSource == 'firebase-pool-with-stats') {
          dataQuality = 'full';
        } else if (dataSource == 'firebase-pool' || dataSource == 'football-api') {
          dataQuality = 'partial';
        }
        
        return {
          'matchIndex': index + 1,
          'homeTeam': match['homeTeam'],
          'awayTeam': match['awayTeam'],
          'dataQuality': dataQuality,
          'predictions': {
            'MS': {
              'prediction': '?',
              'confidence': 0,
              'reasoning': 'Analiz yapılamadı - Teknik hata',
            },
            'IY': {
              'prediction': '?',
              'confidence': 0,
              'reasoning': 'Analiz yapılamadı',
            },
            'AltUst': {
              'prediction': '?',
              'confidence': 0,
              'reasoning': 'Analiz yapılamadı',
            },
            'KG': {
              'prediction': '?',
              'confidence': 0,
              'reasoning': 'Analiz yapılamadı',
            },
            'Korner': {
              'prediction': '?',
              'confidence': 0,
              'reasoning': 'Analiz yapılamadı',
            },
          },
          'generalNote': '⚠️ AI analizi yapılamadı. Lütfen tekrar deneyin veya destek ile iletişime geçin.',
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // go_router kullanıldığı için context.pop() kullan
            // Eğer pop edilemezse home'a yönlendir
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
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
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                child: const Text('Geri Dön'),
              ),
            ],
          ),
        ),
      );
    }

    final totalCount = _analysisResults.length;
    
    // Veri kalitesi analizi
    int fullDataCount = 0;
    int partialDataCount = 0;
    int noDataCount = 0;
    
    for (var result in _analysisResults) {
      final quality = result['dataQuality'] ?? 'unknown';
      if (quality == 'full') fullDataCount++;
      else if (quality == 'partial') partialDataCount++;
      else if (quality == 'none') noDataCount++;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Özet Kartı - Yeni Tasarım
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[600]!, Colors.blue[400]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Analiz Tamamlandı',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalCount Maç',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.sports_soccer,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              if (fullDataCount > 0 || partialDataCount > 0 || noDataCount > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (fullDataCount > 0)
                        _buildCompactStat('$fullDataCount', 'Tam Veri', Colors.green[300]!),
                      if (partialDataCount > 0)
                        _buildCompactStat('$partialDataCount', 'Kısıtlı', Colors.orange[300]!),
                      if (noDataCount > 0)
                        _buildCompactStat('$noDataCount', 'Veri Yok', Colors.red[300]!),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 20),

        // Maç Sonuçları
        ..._analysisResults.map((result) => _buildMatchCard(result)),
      ],
    );
  }

  Widget _buildCompactStat(String value, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$value $label',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDataQualityStat(IconData icon, String label, int count, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String code, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> result) {
    // Yeni format kontrolü
    final predictions = result['predictions'] as Map<String, dynamic>?;
    final dataQuality = result['dataQuality'] ?? 'unknown';
    final generalNote = result['generalNote'] ?? '';
    
    // Eski format desteği (geriye dönük uyumluluk)
    if (predictions == null) {
      return _buildLegacyMatchCard(result);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık Bölümü
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.sports_soccer, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${result['homeTeam']} - ${result['awayTeam']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildDataQualityBadge(dataQuality),
              ],
            ),
          ),
          
          // Tahminler - Betting Style
          _buildBettingStylePredictions(predictions),
          
          // Açıklama (varsa)
          if (generalNote.isNotEmpty && !generalNote.contains('yapılamadı')) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.blue[600],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      generalNote,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBettingStylePredictions(Map<String, dynamic> predictions) {
    final predictionTypes = [
      {'key': 'MS', 'label': 'MS'},
      {'key': 'IY', 'label': 'İY'},
      {'key': 'AltUst', 'label': 'Alt/Üst'},
      {'key': 'KG', 'label': 'KG'},
      {'key': 'Korner', 'label': 'Korner'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: predictionTypes.map((type) {
          final pred = predictions[type['key']] as Map<String, dynamic>?;
          
          if (pred == null) return const SizedBox.shrink();
          
          final prediction = pred['prediction'] ?? '?';
          final confidence = pred['confidence'] ?? 0;

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Label
                  Text(
                    type['label'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Tahmin Değeri
                  Text(
                    prediction,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  // Güven Seviyesi
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getConfidenceColor(confidence).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '%$confidence',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getConfidenceColor(confidence),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCompactPredictions(Map<String, dynamic> predictions) {
    final predictionTypes = [
      {'key': 'MS', 'label': 'MS'},
      {'key': 'IY', 'label': 'İY'},
      {'key': 'AltUst', 'label': 'Alt/Üst'},
      {'key': 'KG', 'label': 'KG'},
      {'key': 'Korner', 'label': 'Korner'},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: predictionTypes.map((type) {
        final pred = predictions[type['key']] as Map<String, dynamic>?;
        
        if (pred == null) return const SizedBox.shrink();
        
        final prediction = pred['prediction'] ?? '?';
        final confidence = pred['confidence'] ?? 0;
        final reasoning = pred['reasoning'] ?? '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _getConfidenceColor(confidence).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _getConfidenceColor(confidence).withOpacity(0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label
              Text(
                type['label'] as String,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              // Tahmin
              Text(
                prediction,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              // Güven Seviyesi
              Text(
                '%$confidence',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _getConfidenceColor(confidence),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPredictionGrid(Map<String, dynamic> predictions) {
    final predictionTypes = [
      {'key': 'MS', 'icon': Icons.sports_soccer, 'label': 'MS', 'fullLabel': 'Maç Sonucu'},
      {'key': 'IY', 'icon': Icons.timer, 'label': 'İY', 'fullLabel': 'İlk Yarı'},
      {'key': 'AltUst', 'icon': Icons.show_chart, 'label': 'Alt/Üst', 'fullLabel': 'Toplam Gol'},
      {'key': 'KG', 'icon': Icons.swap_horiz, 'label': 'KG', 'fullLabel': 'Karşılıklı Gol'},
      {'key': 'Korner', 'icon': Icons.flag, 'label': 'Korner', 'fullLabel': 'Korner Sayısı'},
    ];

    return Column(
      children: [
        // Grid Layout - 2 sütun
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: predictionTypes.length,
          itemBuilder: (context, index) {
            final type = predictionTypes[index];
            final pred = predictions[type['key']] as Map<String, dynamic>?;
            
            if (pred == null) return const SizedBox.shrink();
            
            final prediction = pred['prediction'] ?? '?';
            final confidence = pred['confidence'] ?? 0;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getConfidenceColor(confidence).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        type['icon'] as IconData,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getConfidenceColor(confidence).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '%$confidence',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: _getConfidenceColor(confidence),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        prediction,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDataQualityBadge(String quality) {
    IconData icon;
    String label;
    Color color;
    
    switch (quality) {
      case 'full':
        icon = Icons.check_circle;
        label = 'Tam Veri';
        color = Colors.green;
        break;
      case 'partial':
        icon = Icons.info;
        label = 'Kısıtlı Veri';
        color = Colors.orange;
        break;
      case 'none':
        icon = Icons.warning;
        label = 'Veri Yok';
        color = Colors.red;
        break;
      default:
        icon = Icons.help_outline;
        label = 'Bilinmiyor';
        color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getDataQualityColor(String quality) {
    switch (quality) {
      case 'full':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'none':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Eski format desteği
  Widget _buildLegacyMatchCard(Map<String, dynamic> result) {
    final confidence = result['confidence'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result['homeTeam']} vs ${result['awayTeam']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.psychology, color: Colors.blue[600], size: 20),
                const SizedBox(width: 8),
                Text('AI Tahmini:', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatPrediction(result['aiPrediction']),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue[900]),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _getConfidenceColor(confidence).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getConfidenceColor(confidence), width: 1.5),
                  ),
                  child: Text(
                    '%$confidence',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _getConfidenceColor(confidence)),
                  ),
                ),
              ],
            ),
            if (result['reasoning'] != null && result['reasoning'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Text(result['reasoning'], style: TextStyle(fontSize: 13, color: Colors.grey[800])),
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