import 'package:firebase_database/firebase_database.dart';
import '../models/user_model.dart';
import '../models/credit_transaction_model.dart';

class UserService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  // Kullanıcı oluştur veya güncelle
  Future<void> createOrUpdateUser(UserModel user) async {
    try {
      final ref = _database.ref('users/${user.uid}');
      await ref.update(user.toMap());
      print('✅ Kullanıcı Realtime Database\'e kaydedildi: ${user.uid}');
    } catch (e) {
      print('❌ Kullanıcı oluşturma hatası: $e');
      rethrow;
    }
  }
  
  // Kullanıcı bilgilerini getir
  Future<UserModel?> getUser(String uid) async {
    try {
      final ref = _database.ref('users/$uid');
      final snapshot = await ref.get();
      
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return UserModel.fromJson(uid, data);
      }
      return null;
    } catch (e) {
      print('❌ Kullanıcı getirme hatası: $e');
      return null;
    }
  }
  
  // Kullanıcı stream (real-time)
  Stream<UserModel?> getUserStream(String uid) {
    return _database.ref('users/$uid').onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        return UserModel.fromJson(uid, data);
      }
      return null;
    });
  }
  
  // Kredi ekle (satın alma, bonus vb.)
  Future<bool> addCredits({
    required String userId,
    required int amount,
    required TransactionType type,
    String? description,
    String? productId,
    String? purchaseId,
  }) async {
    try {
      final userRef = _database.ref('users/$userId');
      final snapshot = await userRef.get();
      
      if (!snapshot.exists || snapshot.value == null) {
        throw Exception('Kullanıcı bulunamadı');
      }
      
      final userData = Map<String, dynamic>.from(snapshot.value as Map);
      final user = UserModel.fromJson(userId, userData);
      final newCredits = user.credits + amount;
      
      // Kullanıcı kredisini güncelle
      await userRef.update({'credits': newCredits});
      
      // İşlem kaydı oluştur
      final transactionRef = _database.ref('credit_transactions').push();
      await transactionRef.set(CreditTransaction(
        id: transactionRef.key ?? '',
        userId: userId,
        type: type,
        amount: amount,
        balanceAfter: newCredits,
        createdAt: DateTime.now(),
        description: description,
        productId: productId,
        purchaseId: purchaseId,
      ).toMap());
      
      print('✅ $amount kredi eklendi. Yeni bakiye: $newCredits');
      return true;
    } catch (e) {
      print('❌ Kredi ekleme hatası: $e');
      return false;
    }
  }
  
  // Kredi kullan (analiz)
  Future<bool> useCredit(String userId, {String? analysisId}) async {
    try {
      final userRef = _database.ref('users/$userId');
      final snapshot = await userRef.get();
      
      if (!snapshot.exists || snapshot.value == null) {
        throw Exception('Kullanıcı bulunamadı');
      }
      
      final userData = Map<String, dynamic>.from(snapshot.value as Map);
      final user = UserModel.fromJson(userId, userData);
      
      // Premium kullanıcı kontrolü
      if (user.isActivePremium) {
        // Premium kullanıcı, kredi düşmesin ama işlem sayısı artsın
        await userRef.update({
          'totalAnalysisCount': user.totalAnalysisCount + 1,
        });
        
        // Premium kullanım kaydı
        final transactionRef = _database.ref('credit_transactions').push();
        await transactionRef.set(CreditTransaction(
          id: transactionRef.key ?? '',
          userId: userId,
          type: TransactionType.usage,
          amount: 0, // Premium için 0
          balanceAfter: user.credits,
          createdAt: DateTime.now(),
          description: 'Premium analiz - kredi düşmedi',
        ).toMap());
        
        print('✅ Premium kullanıcı - kredi düşmedi');
        return true;
      }
      
      // Kredi kontrolü
      if (user.credits <= 0) {
        print('❌ Yetersiz kredi');
        throw Exception('Yetersiz kredi');
      }
      
      final newCredits = user.credits - 1;
      
      // Kullanıcı kredisini düş
      await userRef.update({
        'credits': newCredits,
        'totalAnalysisCount': user.totalAnalysisCount + 1,
      });
      
      // Kullanım kaydı
      final transactionRef = _database.ref('credit_transactions').push();
      await transactionRef.set(CreditTransaction(
        id: transactionRef.key ?? '',
        userId: userId,
        type: TransactionType.usage,
        amount: -1,
        balanceAfter: newCredits,
        createdAt: DateTime.now(),
        description: analysisId != null 
            ? 'Analiz ID: $analysisId' 
            : 'Kredi kullanımı',
      ).toMap());
      
      print('✅ 1 kredi kullanıldı. Kalan: $newCredits');
      return true;
    } catch (e) {
      print('❌ Kredi kullanma hatası: $e');
      return false;
    }
  }
  
  // Premium abonelik ekle
  Future<bool> setPremium({
    required String userId,
    required int durationDays,
    String? productId,
    String? purchaseId,
  }) async {
    try {
      final expiresAt = DateTime.now().add(Duration(days: durationDays));
      final userRef = _database.ref('users/$userId');
      
      await userRef.update({
        'isPremium': true,
        'premiumExpiresAt': expiresAt.millisecondsSinceEpoch,
      });
      
      // Premium satın alma kaydı
      final transactionRef = _database.ref('credit_transactions').push();
      await transactionRef.set(CreditTransaction(
        id: transactionRef.key ?? '',
        userId: userId,
        type: TransactionType.purchase,
        amount: 0,
        balanceAfter: 0,
        createdAt: DateTime.now(),
        description: 'Premium abonelik - $durationDays gün',
        productId: productId,
        purchaseId: purchaseId,
      ).toMap());
      
      print('✅ Premium abonelik eklendi: $durationDays gün');
      return true;
    } catch (e) {
      print('❌ Premium ekleme hatası: $e');
      return false;
    }
  }
  
  // Kullanıcının işlem geçmişini getir
  Future<List<CreditTransaction>> getTransactionHistory(String userId) async {
    try {
      final ref = _database.ref('credit_transactions');
      final query = ref.orderByChild('userId').equalTo(userId);
      final snapshot = await query.get();
      
      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }
      
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final transactions = <CreditTransaction>[];
      
      data.forEach((key, value) {
        final transactionData = Map<String, dynamic>.from(value as Map);
        transactions.add(CreditTransaction.fromJson(key, transactionData));
      });
      
      // Tarihe göre sırala (yeniden eskiye)
      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return transactions.take(50).toList();
    } catch (e) {
      print('❌ İşlem geçmişi hatası: $e');
      return [];
    }
  }
}