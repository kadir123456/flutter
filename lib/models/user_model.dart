import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final int credits; // Kullanıcı kredisi
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final bool isPremium; // Premium abonelik durumu
  final DateTime? premiumExpiresAt;
  final int totalAnalysisCount; // Toplam yapılan analiz sayısı
  
  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.credits = 3, // İlk kayıtta 3 kredi
    required this.createdAt,
    required this.lastLoginAt,
    this.isPremium = false,
    this.premiumExpiresAt,
    this.totalAnalysisCount = 0,
  });
  
  // Firestore'dan user oluştur
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      photoUrl: data['photoUrl'],
      credits: data['credits'] ?? 3,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPremium: data['isPremium'] ?? false,
      premiumExpiresAt: (data['premiumExpiresAt'] as Timestamp?)?.toDate(),
      totalAnalysisCount: data['totalAnalysisCount'] ?? 0,
    );
  }
  
  // Firestore'a kaydet
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'credits': credits,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'isPremium': isPremium,
      'premiumExpiresAt': premiumExpiresAt != null 
          ? Timestamp.fromDate(premiumExpiresAt!) 
          : null,
      'totalAnalysisCount': totalAnalysisCount,
    };
  }
  
  // Kredi ekle
  UserModel addCredits(int amount) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      credits: credits + amount,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      isPremium: isPremium,
      premiumExpiresAt: premiumExpiresAt,
      totalAnalysisCount: totalAnalysisCount,
    );
  }
  
  // Kredi düş
  UserModel useCredit() {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      credits: credits > 0 ? credits - 1 : 0,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      isPremium: isPremium,
      premiumExpiresAt: premiumExpiresAt,
      totalAnalysisCount: totalAnalysisCount + 1,
    );
  }
  
  // Premium yap
  UserModel setPremium(DateTime expiresAt) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      credits: credits,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      isPremium: true,
      premiumExpiresAt: expiresAt,
      totalAnalysisCount: totalAnalysisCount,
    );
  }
  
  // Premium kontrolü (süre dolmuş mu?)
  bool get isActivePremium {
    if (!isPremium || premiumExpiresAt == null) return false;
    return DateTime.now().isBefore(premiumExpiresAt!);
  }
  
  // Analiz yapabilir mi?
  bool get canAnalyze => isActivePremium || credits > 0;
}