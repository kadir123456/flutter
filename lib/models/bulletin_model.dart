import 'package:cloud_firestore/cloud_firestore.dart';

class BulletinModel {
  final String id;
  final String userId;
  final String? imageUrl; // OPSIYONEL - Storage kullanmıyoruz
  final String status; // pending, analyzing, completed, failed
  final DateTime createdAt;
  final DateTime? analyzedAt;
  
  // Analiz sonuçları
  final Map<String, dynamic>? analysis;
  
  BulletinModel({
    required this.id,
    required this.userId,
    this.imageUrl,
    required this.status,
    required this.createdAt,
    this.analyzedAt,
    this.analysis,
  });
  
  // Firestore'dan nesne oluştur
  factory BulletinModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return BulletinModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      imageUrl: data['imageUrl'], // null olabilir
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      analyzedAt: (data['analyzedAt'] as Timestamp?)?.toDate(),
      analysis: data['analysis'] as Map<String, dynamic>?,
    );
  }
  
  // Firestore'a kaydet
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'imageUrl': imageUrl ?? '', // Boş string olabilir
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'analyzedAt': analyzedAt != null ? Timestamp.fromDate(analyzedAt!) : null,
      'analysis': analysis,
    };
  }
  
  // Kopyalama (güncelleme için)
  BulletinModel copyWith({
    String? id,
    String? userId,
    String? imageUrl,
    String? status,
    DateTime? createdAt,
    DateTime? analyzedAt,
    Map<String, dynamic>? analysis,
  }) {
    return BulletinModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      analyzedAt: analyzedAt ?? this.analyzedAt,
      analysis: analysis ?? this.analysis,
    );
  }
}

// Analiz detay modelleri
class BulletinAnalysis {
  final List<MatchPrediction> predictions;
  final OverallAssessment overall;
  
  BulletinAnalysis({
    required this.predictions,
    required this.overall,
  });
  
  factory BulletinAnalysis.fromJson(Map<String, dynamic> json) {
    return BulletinAnalysis(
      predictions: (json['predictions'] as List?)
          ?.map((p) => MatchPrediction.fromJson(p))
          .toList() ?? [],
      overall: OverallAssessment.fromJson(json['overall'] ?? {}),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'predictions': predictions.map((p) => p.toJson()).toList(),
      'overall': overall.toJson(),
    };
  }
}

class MatchPrediction {
  final String homeTeam;
  final String awayTeam;
  final String userPrediction; // 1, X, 2, Alt, Üst, KG Var
  final String aiPrediction;
  final double confidence; // 0-100
  final String reasoning;
  final List<String> alternativePredictions;
  final RiskAnalysis risk;
  
  MatchPrediction({
    required this.homeTeam,
    required this.awayTeam,
    required this.userPrediction,
    required this.aiPrediction,
    required this.confidence,
    required this.reasoning,
    required this.alternativePredictions,
    required this.risk,
  });
  
  factory MatchPrediction.fromJson(Map<String, dynamic> json) {
    return MatchPrediction(
      homeTeam: json['homeTeam'] ?? '',
      awayTeam: json['awayTeam'] ?? '',
      userPrediction: json['userPrediction'] ?? '',
      aiPrediction: json['aiPrediction'] ?? '',
      confidence: (json['confidence'] ?? 0).toDouble(),
      reasoning: json['reasoning'] ?? '',
      alternativePredictions: List<String>.from(json['alternativePredictions'] ?? []),
      risk: RiskAnalysis.fromJson(json['risk'] ?? {}),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'homeTeam': homeTeam,
      'awayTeam': awayTeam,
      'userPrediction': userPrediction,
      'aiPrediction': aiPrediction,
      'confidence': confidence,
      'reasoning': reasoning,
      'alternativePredictions': alternativePredictions,
      'risk': risk.toJson(),
    };
  }
}

class RiskAnalysis {
  final String level; // low, medium, high
  final List<String> factors;
  
  RiskAnalysis({
    required this.level,
    required this.factors,
  });
  
  factory RiskAnalysis.fromJson(Map<String, dynamic> json) {
    return RiskAnalysis(
      level: json['level'] ?? 'medium',
      factors: List<String>.from(json['factors'] ?? []),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'level': level,
      'factors': factors,
    };
  }
}

class OverallAssessment {
  final double successProbability; // 0-100
  final List<String> riskiestPicks;
  final String strategy;
  
  OverallAssessment({
    required this.successProbability,
    required this.riskiestPicks,
    required this.strategy,
  });
  
  factory OverallAssessment.fromJson(Map<String, dynamic> json) {
    return OverallAssessment(
      successProbability: (json['successProbability'] ?? 0).toDouble(),
      riskiestPicks: List<String>.from(json['riskiestPicks'] ?? []),
      strategy: json['strategy'] ?? '',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'successProbability': successProbability,
      'riskiestPicks': riskiestPicks,
      'strategy': strategy,
    };
  }
}