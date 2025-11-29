// Firebase Realtime Database için güncellendi - Firestore kaldırıldı
// Görsel kaydedilmiyor, sadece analiz için kullanılıyor

class BulletinModel {
  final String id;
  final String userId;
  final String status; // pending, analyzing, completed, failed
  final DateTime createdAt;
  final DateTime? analyzedAt;
  final Map<String, dynamic>? analysis;
  
  BulletinModel({
    required this.id,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.analyzedAt,
    this.analysis,
  });
  
  // Realtime Database'den oluştur
  factory BulletinModel.fromJson(String id, Map<String, dynamic> data) {
    return BulletinModel(
      id: id,
      userId: data['userId'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: data['createdAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int)
          : DateTime.now(),
      analyzedAt: data['analyzedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(data['analyzedAt'] as int)
          : null,
      analysis: data['analysis'] != null 
          ? Map<String, dynamic>.from(data['analysis'])
          : null,
    );
  }
  
  // Realtime Database'e kaydet
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'analyzedAt': analyzedAt?.millisecondsSinceEpoch,
      'analysis': analysis,
    };
  }
  
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
  
  // toMap metodu eklendi (bulletin_provider için gerekli)
  Map<String, dynamic> toMap() => toJson();
  
  // fromMap metodu eklendi
  factory BulletinAnalysis.fromMap(Map<String, dynamic> map) => 
      BulletinAnalysis.fromJson(map);
}

class MatchPrediction {
  final String homeTeam;
  final String awayTeam;
  final String userPrediction;
  final String aiPrediction;
  final double confidence;
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
  final String level;
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
  final double successProbability;
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