import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 🔐 GÜVENLİ GEMİNİ SERVİSİ
/// Cloud Functions üzerinden API çağrısı yapar
/// API key client'ta olmaz, sadece Cloud Functions'ta
class GeminiServiceSecure {
  static final GeminiServiceSecure _instance = GeminiServiceSecure._internal();
  factory GeminiServiceSecure() => _instance;
  GeminiServiceSecure._internal();

  // Firebase Functions instance - default region (otomatik detect eder)
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

      print('✅ Kullanıcı bulundu: ${user.uid}');
      print('📧 Email: ${user.email}');
      print('🔐 Email Verified: ${user.emailVerified}');

      // Token'ı yenile ve kontrol et (expire olmuş olabilir)
      try {
        final idToken = await user.getIdToken(true); // force refresh
        print('✅ Auth token yenilendi');
        print('🎫 Token length: ${idToken?.length ?? 0}');
        
        // Token'ı manuel olarak kontrol et
        if (idToken == null || idToken.isEmpty) {
          throw Exception('Token alınamadı - lütfen çıkış yapıp tekrar giriş yapın');
        }
      } catch (tokenError) {
        print('⚠️ Token yenileme hatası: $tokenError');
        throw Exception('Token yenileme başarısız: $tokenError');
      }

      // Prompt'u hazırla (Cloud Function'a gönderilecek)
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

      print('📡 Cloud Function çağrısı yapılıyor...');
      print('📝 Prompt hazır, uzunluk: ${prompt.length}');
      print('🖼️ Base64 image hazır, uzunluk: ${base64Image.length}');

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
    } on FirebaseFunctionsException catch (e) {
      print('❌ Firebase Functions Hatası:');
      print('   Code: ${e.code}');
      print('   Message: ${e.message}');
      print('   Details: ${e.details}');
      
      // Kullanıcıya daha anlaşılır hata mesajı
      if (e.code == 'unauthenticated') {
        throw Exception('Oturum süresi dolmuş olabilir. Lütfen çıkış yapıp tekrar giriş yapın.');
      }
      
      rethrow;
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

      print('✅ Kullanıcı bulundu: ${user.uid}');

      // Token'ı yenile (expire olmuş olabilir)
      try {
        await user.getIdToken(true); // force refresh
        print('✅ Auth token yenilendi');
      } catch (tokenError) {
        print('⚠️ Token yenileme hatası: $tokenError');
      }

      print('📡 Cloud Function çağrısı yapılıyor...');

      // Cloud Function'ı çağır
      final callable = _functions.httpsCallable('callGeminiAPI');
      final result = await callable.call({
        'prompt': prompt,
      });

      print('✅ Güvenli Gemini metin analizi başarılı');

      return result.data['text'] as String;
    } on FirebaseFunctionsException catch (e) {
      print('❌ Firebase Functions Hatası:');
      print('   Code: ${e.code}');
      print('   Message: ${e.message}');
      print('   Details: ${e.details}');
      
      // Kullanıcıya daha anlaşılır hata mesajı
      if (e.code == 'unauthenticated') {
        throw Exception('Oturum süresi dolmuş olabilir. Lütfen çıkış yapıp tekrar giriş yapın.');
      }
      
      rethrow;
    } catch (e) {
      print('❌ Güvenli Gemini Text Analysis Error: $e');
      rethrow;
    }
  }
}
