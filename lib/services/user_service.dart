import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/credit_transaction_model.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Kullanıcı oluştur veya güncelle
  Future<void> createOrUpdateUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set(
        user.toMap(),
        SetOptions(merge: true),
      );
    } catch (e) {
      print('❌ Kullanıcı oluşturma hatası: $e');
      rethrow;
    }
  }
  
  // Kullanıcı bilgilerini getir
  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('❌ Kullanıcı getirme hatası: $e');
      return null;
    }
  }
  
  // Kullanıcı stream (real-time)
  Stream<UserModel?> getUserStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
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
      final userDoc = _firestore.collection('users').doc(userId);
      
      return await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userDoc);
        
        if (!userSnapshot.exists) {
          throw Exception('Kullanıcı bulunamadı');
        }
        
        final user = UserModel.fromFirestore(userSnapshot);
        final newCredits = user.credits + amount;
        
        // Kullanıcı kredisini güncelle
        transaction.update(userDoc, {'credits': newCredits});
        
        // İşlem kaydı oluştur
        final transactionDoc = _firestore.collection('credit_transactions').doc();
        transaction.set(transactionDoc, CreditTransaction(
          id: transactionDoc.id,
          userId: userId,
          type: type,
          amount: amount,
          balanceAfter: newCredits,
          createdAt: DateTime.now(),
          description: description,
          productId: productId,
          purchaseId: purchaseId,
        ).toMap());
        
        return true;
      });
    } catch (e) {
      print('❌ Kredi ekleme hatası: $e');
      return false;
    }
  }
  
  // Kredi kullan (analiz)
  Future<bool> useCredit(String userId, {String? analysisId}) async {
    try {
      final userDoc = _firestore.collection('users').doc(userId);
      
      return await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userDoc);
        
        if (!userSnapshot.exists) {
          throw Exception('Kullanıcı bulunamadı');
        }
        
        final user = UserModel.fromFirestore(userSnapshot);
        
        // Premium kullanıcı veya kredi kontrolü
        if (user.isActivePremium) {
          // Premium kullanıcı, kredi düşmesin ama işlem sayısı artsın
          transaction.update(userDoc, {
            'totalAnalysisCount': user.totalAnalysisCount + 1,
          });
          
          // Premium kullanım kaydı
          final transactionDoc = _firestore.collection('credit_transactions').doc();
          transaction.set(transactionDoc, CreditTransaction(
            id: transactionDoc.id,
            userId: userId,
            type: TransactionType.usage,
            amount: 0, // Premium için 0
            balanceAfter: user.credits,
            createdAt: DateTime.now(),
            description: 'Premium analiz - kredi düşmedi',
          ).toMap());
          
          return true;
        }
        
        // Kredi kontrolü
        if (user.credits <= 0) {
          throw Exception('Yetersiz kredi');
        }
        
        final newCredits = user.credits - 1;
        
        // Kullanıcı kredisini düş
        transaction.update(userDoc, {
          'credits': newCredits,
          'totalAnalysisCount': user.totalAnalysisCount + 1,
        });
        
        // Kullanım kaydı
        final transactionDoc = _firestore.collection('credit_transactions').doc();
        transaction.set(transactionDoc, CreditTransaction(
          id: transactionDoc.id,
          userId: userId,
          type: TransactionType.usage,
          amount: -1,
          balanceAfter: newCredits,
          createdAt: DateTime.now(),
          description: analysisId != null 
              ? 'Analiz ID: $analysisId' 
              : 'Kredi kullanımı',
        ).toMap());
        
        return true;
      });
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
      
      await _firestore.collection('users').doc(userId).update({
        'isPremium': true,
        'premiumExpiresAt': Timestamp.fromDate(expiresAt),
      });
      
      // Premium satın alma kaydı
      await _firestore.collection('credit_transactions').add(
        CreditTransaction(
          id: '',
          userId: userId,
          type: TransactionType.purchase,
          amount: 0,
          balanceAfter: 0,
          createdAt: DateTime.now(),
          description: 'Premium abonelik - $durationDays gün',
          productId: productId,
          purchaseId: purchaseId,
        ).toMap(),
      );
      
      return true;
    } catch (e) {
      print('❌ Premium ekleme hatası: $e');
      return false;
    }
  }
  
  // Kullanıcının işlem geçmişini getir
  Future<List<CreditTransaction>> getTransactionHistory(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('credit_transactions')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      
      return snapshot.docs
          .map((doc) => CreditTransaction.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ İşlem geçmişi hatası: $e');
      return [];
    }
  }
}