import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 🔐 GÜVENLİ GEMİNİ SERVİSİ
/// Cloud Functions üzerinden API çağrısı yapar
/// API key client'ta olmaz, sadece Cloud Functions'ta
class GeminiServiceSecure {
  static final GeminiServiceSecure _instance = GeminiServiceSecure._internal();
  factory GeminiServiceSecure() => _instance;
  GeminiServiceSecure._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Görsel analizi - Cloud Function üzerinden
  Future<String> analyzeImage(String base64Image) async {
    try {
      print('🔐 Güvenli Gemini API çağrısı başlatılıyor...');

      // Auth kontrolü
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      final prompt = '''Bu görseldeki futbol maçlarını analiz et ve her maç için takım isimlerini çıkar.

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

Sadece JSON döndür, başka açıklama yazma.''';

      // Cloud Function'ı çağır
      final callable = _functions.httpsCallable('callGeminiAPI');
      final result = await callable.call({
        'prompt': prompt,
        'imageBase64': base64Image,
      });

      print('✅ Güvenli Gemini API başarılı');

      final text = result.data['text'] as String;
      
      if (text.isEmpty) {
        throw Exception('Gemini boş yanıt döndü');
      }

      return text;
    } catch (e) {
      print('❌ Güvenli Gemini Service Error: $e');
      rethrow;
    }
  }

  /// Metin analizi - Cloud Function üzerinden
  Future<String> analyzeText(String prompt) async {
    try {
      print('🔐 Güvenli Gemini metin analizi başlatılıyor...');

      // Auth kontrolü
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Cloud Function'ı çağır
      final callable = _functions.httpsCallable('callGeminiAPI');
      final result = await callable.call({
        'prompt': prompt,
      });

      print('✅ Güvenli Gemini metin analizi başarılı');

      return result.data['text'] as String;
    } catch (e) {
      print('❌ Güvenli Gemini Text Analysis Error: $e');
      rethrow;
    }
  }
}
