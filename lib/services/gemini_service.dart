import 'package:http/http.dart' as http;
import 'dart:convert';
import './remote_config_service.dart';

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  final String _baseUrl = 'https://generativelanguage.googleapis.com/v1/models';
  final RemoteConfigService _remoteConfig = RemoteConfigService();
  
  String get _apiKey => _remoteConfig.geminiApiKey;

  /// Gemini Flash ile görsel analizi
  Future<String> analyzeImage(String base64Image) async {
    try {
      // ✅ Güncel model: gemini-2.5-flash (Haziran 2025)
      final url = Uri.parse('$_baseUrl/gemini-2.5-flash:generateContent?key=$_apiKey');

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'text': '''Bu görseldeki futbol maçlarını analiz et ve her maç için takım isimlerini çıkar.

ÖNEMLİ: Takım isimlerini resmi İngilizce isimlerine çevir. Football-API.com ile uyumlu olmalı.

Örnekler:
- "Espanyol II" → "Espanyol B"
- "Valencia M." → "Valencia Mestalla"  
- "Almería B" → "Almeria B"
- "Girona B" → "Girona B"
- Türkçe karakterleri (ı,ğ,ü,ş,ö,ç) İngilizce'ye çevir (i,g,u,s,o,c)

JSON formatı:
{
  "matches": [
    {
      "homeTeam": "Resmi İngilizce Takım Adı",
      "awayTeam": "Resmi İngilizce Takım Adı"
    }
  ]
}

Sadece JSON döndür, başka açıklama yazma.'''
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
          'temperature': 0.4,
          'topK': 32,
          'topP': 1,
          'maxOutputTokens': 8192, // Gemini 2.5 Flash max: 65,536
        }
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        
        if (text.isEmpty) {
          throw Exception('Gemini boş yanıt döndü');
        }
        
        return text;
      } else {
        throw Exception('Gemini API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Gemini Service Error: $e');
      rethrow;
    }
  }

  /// Metin analizi (opsiyonel)
  Future<String> analyzeText(String prompt) async {
    try {
      final url = Uri.parse('$_baseUrl/gemini-2.5-flash:generateContent?key=$_apiKey');

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 8192, // Gemini 2.5 Flash için artırıldı
        }
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
      } else {
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Gemini Text Analysis Error: $e');
      rethrow;
    }
  }

  /// ⭐ YENİ METOD: Google Search ile analiz (OPSIYONEL) - DEVRE DIŞI
  Future<String> analyzeWithGoogleSearch(String prompt) async {
    try {
      print('⚠️ Google Search devre dışı - Normal analiz yapılıyor...');
      
      // Google Search devre dışı - normal analiz yap
      return await analyzeText(prompt);

      // Artık buraya ulaşmayacak - üstteki return zaten döndürüyor
    } catch (e) {
      print('❌ Gemini Error: $e');
      rethrow;
    }
  }

  /// ⭐ YENİ: Opsiyonel Google Search ile analiz - DEVRE DIŞI
  Future<String> analyzeWithOptionalSearch(String prompt, {bool useSearch = false}) async {
    // Google Search devre dışı - her zaman normal analiz yap
    print('⚠️ Google Search parametresi göz ardı ediliyor - Normal analiz yapılıyor');
    return await analyzeText(prompt);
  }
}