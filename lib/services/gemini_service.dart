import 'dart:convert';
import 'package:dio/dio.dart';
import 'remote_config_service.dart';

class GeminiAnalysisService {
  final Dio _dio = Dio();
  final RemoteConfigService _remoteConfig = RemoteConfigService();
  
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const String _model = 'gemini-2.5-pro'; // Gemini 2.5 Pro yerine güncel model
  
  // API key'i Remote Config'den al
  String get _apiKey => _remoteConfig.geminiApiKey;
  
  // Görsel analiz - maç bilgilerini çıkar
  Future<Map<String, dynamic>?> analyzeMatchImage(String base64Image) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/models/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'contents': [
            {
              'parts': [
                {
                  'text': '''Bu spor bülteni görselinden aşağıdaki bilgileri JSON formatında çıkar:

1. Tüm maçların ev sahibi ve deplasman takım isimlerini
2. Varsa lig/turnuva bilgisini
3. Varsa maç tarihini
4. Kullanıcının yaptığı tahminleri (1, X, 2, Alt, Üst, KG Var vb.)

ÖNEMLI:
- Türkçe karakter ve kısaltmaları normalize et (ör: "G.S" → "Galatasaray")
- Benzer isimleri standartlaştır (ör: "FB", "Fenerbahçe", "Fenerbahce" → "Fenerbahçe")
- Her maç için ayrı bir obje oluştur

JSON formatı:
{
  "matches": [
    {
      "homeTeam": "Galatasaray",
      "awayTeam": "Fenerbahçe",
      "league": "Süper Lig",
      "date": "2025-01-15",
      "userPrediction": "1"
    }
  ],
  "totalMatches": 5
}'''
                },
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'topK': 1,
            'topP': 1,
            'maxOutputTokens': 2048,
            'responseMimeType': 'application/json',
          }
        },
      );
      
      final text = response.data['candidates'][0]['content']['parts'][0]['text'];
      
      // JSON string'i parse et
      if (text != null) {
        // Markdown code block'larını temizle
        String cleanedText = text.toString()
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        
        // JSON parse et
        try {
          final jsonResponse = json.decode(cleanedText) as Map<String, dynamic>;
          print('✅ Gemini görsel analizi başarılı: ${jsonResponse['totalMatches']} maç bulundu');
          return jsonResponse;
        } catch (e) {
          print('❌ JSON parse hatası: $e');
          print('Raw response: $cleanedText');
          return null;
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Gemini görsel analiz hatası: $e');
      return null;
    }
  }
  
  // Maç tahmin analizi
  Future<Map<String, dynamic>?> analyzeMatch({
    required String homeTeam,
    required String awayTeam,
    required String userPrediction,
    required Map<String, dynamic> matchStats,
  }) async {
    try {
      final prompt = '''Aşağıdaki futbol maçı için detaylı tahmin analizi yap:

**MAÇ BİLGİLERİ:**
Ev Sahibi: $homeTeam
Deplasman: $awayTeam
Kullanıcı Tahmini: $userPrediction

**İSTATİSTİKLER:**
${_formatStats(matchStats)}

**GÖREV:**
1. Kullanıcının tahmininin başarı olasılığını hesapla (0-100%)
2. Tahmine gerekçe sun (istatistiklere dayalı)
3. Alternatif tahmin önerileri ver
4. Risk analizi yap

**ÇIKTI FORMATI (JSON):**
{
  "prediction": {
    "type": "$userPrediction",
    "confidence": 75,
    "isRecommended": true
  },
  "reasoning": "Ev sahibi takım son 5 maçta...",
  "statistics": {
    "homeForm": "WWDWL",
    "awayForm": "LWLDD",
    "h2h": "Son 3 maçta 2 ev sahibi galibiyeti",
    "goalAverage": {
      "home": 1.8,
      "away": 1.2
    }
  },
  "alternatives": [
    {
      "type": "1",
      "confidence": 75,
      "reason": "Ev sahibi güçlü"
    },
    {
      "type": "Alt 2.5",
      "confidence": 60,
      "reason": "Deplasman savunması sağlam"
    }
  ],
  "riskAnalysis": {
    "level": "medium",
    "factors": ["Deplasman takımın savunması güçlü", "Ev sahibinin son iki maçı berabere"]
  },
  "finalRecommendation": "Tahmininiz makul, ancak 'Alt 2.5' de değerlendirilebilir."
}

ÖNEMLI: Sadece JSON formatında yanıt ver, başka açıklama ekleme.''';

      final response = await _dio.post(
        '$_baseUrl/models/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.3,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 2048,
            'responseMimeType': 'application/json',
          }
        },
      );
      
      final text = response.data['candidates'][0]['content']['parts'][0]['text'];
      
      if (text != null) {
        String cleanedText = text.toString()
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        
        // JSON parse et
        try {
          final analysisResult = json.decode(cleanedText) as Map<String, dynamic>;
          print('✅ Gemini maç analizi başarılı');
          return analysisResult;
        } catch (e) {
          print('❌ JSON parse hatası: $e');
          print('Raw response: $cleanedText');
          return null;
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Gemini maç analiz hatası: $e');
      return null;
    }
  }
  
  // İstatistikleri formatla
  String _formatStats(Map<String, dynamic> stats) {
    final buffer = StringBuffer();
    
    if (stats.containsKey('last5Matches')) {
      buffer.writeln('Son 5 Maç:');
      buffer.writeln('  Ev Sahibi: ${stats['last5Matches']['home']}');
      buffer.writeln('  Deplasman: ${stats['last5Matches']['away']}');
    }
    
    if (stats.containsKey('goalStats')) {
      buffer.writeln('\nGol İstatistikleri:');
      buffer.writeln('  Ev Sahibi Ortalaması: ${stats['goalStats']['homeAvg']}');
      buffer.writeln('  Deplasman Ortalaması: ${stats['goalStats']['awayAvg']}');
    }
    
    if (stats.containsKey('h2h')) {
      buffer.writeln('\nKafa Kafaya (H2H):');
      buffer.writeln('  ${stats['h2h']}');
    }
    
    if (stats.containsKey('injuries')) {
      buffer.writeln('\nSakatlıklar:');
      buffer.writeln('  ${stats['injuries']}');
    }
    
    if (stats.containsKey('standings')) {
      buffer.writeln('\nPuan Durumu:');
      buffer.writeln('  Ev Sahibi: ${stats['standings']['home']}. sırada');
      buffer.writeln('  Deplasman: ${stats['standings']['away']}. sırada');
    }
    
    return buffer.toString();
  }
  
  // Genel bülten analizi
  Future<String?> analyzeBulletinOverall(List<Map<String, dynamic>> predictions) async {
    try {
      final prompt = '''Kullanıcının hazırladığı ${predictions.length} maçlık spor bültenini analiz et.

**MAÇLAR VE TAHMİNLER:**
${predictions.map((p) => '- ${p['homeTeam']} vs ${p['awayTeam']}: ${p['userPrediction']} (Güven: ${p['confidence']}%)').join('\n')}

**GÖREV:**
1. Genel başarı olasılığını hesapla
2. En riskli tahminleri belirt
3. Genel strateji önerisi sun
4. Bülteni geliştirmek için tavsiyelerde bulun

Samimi ve dostça bir dille, Türkçe olarak yanıt ver (JSON değil).''';

      final response = await _dio.post(
        '$_baseUrl/models/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.7,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 1024,
          }
        },
      );
      
      return response.data['candidates'][0]['content']['parts'][0]['text'];
    } catch (e) {
      print('❌ Gemini genel analiz hatası: $e');
      return null;
    }
  }
}