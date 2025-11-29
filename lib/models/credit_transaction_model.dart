import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType {
  purchase, // Satın alma
  usage, // Analiz kullanımı
  bonus, // Hediye/bonus
  refund, // İade
  welcome, // Hoşgeldin bonusu
}

class CreditTransaction {
  final String id;
  final String userId;
  final TransactionType type;
  final int amount; // Pozitif = ekleme, Negatif = kullanım
  final int balanceAfter; // İşlem sonrası bakiye
  final DateTime createdAt;
  final String? description;
  final String? productId; // In-app purchase product ID
  final String? purchaseId; // Google Play purchase ID
  
  CreditTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
    this.description,
    this.productId,
    this.purchaseId,
  });
  
  factory CreditTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return CreditTransaction(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: TransactionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => TransactionType.usage,
      ),
      amount: data['amount'] ?? 0,
      balanceAfter: data['balanceAfter'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      description: data['description'],
      productId: data['productId'],
      purchaseId: data['purchaseId'],
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type.name,
      'amount': amount,
      'balanceAfter': balanceAfter,
      'createdAt': Timestamp.fromDate(createdAt),
      'description': description,
      'productId': productId,
      'purchaseId': purchaseId,
    };
  }
}