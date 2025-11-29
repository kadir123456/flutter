import 'package:cloud_firestore/cloud_firestore.dart';

class Bulletin {
  final String id;
  final String userId;
  final String imageUrl;
  final String status; // pending, analyzing, completed, failed
  final DateTime createdAt;
  final DateTime updatedAt;
  final BulletinAnalysis? analysis;
  
  Bulletin({
    required this.id,
    required this.userId,
    required this.imageUrl,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.analysis,
  });
  
  // Firestore'dan nesne oluştur
  factory Bulletin.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return Bulletin(
      id: doc.id,
      userId: data['userId'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      analysis: data['analysis'] != null 
          ? BulletinAnalysis.fromMap(data['analysis'])
          : null,
    );
  }
  
  // Firestore'a kaydetmek için Map'e dönüştür
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'imageUrl': imageUrl,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'analysis': analysis?.toMap(),
    };
  }
}

class BulletinAnalysis {
  final String extractedText; // Görselden çıkarılan metin
  final List<MatchPrediction> predictions; // Her maç için tahminler
  final double overallSuccessRate; // Genel başarı oranı
  final String geminiSummary; // Gemini'nin genel yorumu
  
  BulletinAnalysis({
    required this.extractedText,
    required this.predictions,
    required this.overallSuccessRate,
    required this.geminiSummary,
  });
  
  factory BulletinAnalysis.fromMap(Map<String, dynamic> map) {
    return BulletinAnalysis(
      extractedText: map['extractedText'] ?? '',
      predictions: (map['predictions'] as List<dynamic>?)
          ?.map((p) => MatchPrediction.fromMap(p))
          .toList() ?? [],
      overallSuccessRate: (map['overallSuccessRate'] ?? 0).toDouble(),
      geminiSummary: map['geminiSummary'] ?? '',
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'extractedText': extractedText,
      'predictions': predictions.map((p) => p.toMap()).toList(),
      'overallSuccessRate': overallSuccessRate,
      'geminiSummary': geminiSummary,
    };
  }
}

class MatchPrediction {
  final String homeTeam;
  final String awayTeam;
  final String userPrediction; // Kullanıcının tahmini
  final String geminiPrediction; // Gemini'nin önerisi
  final double successProbability; // Başarı olasılığı (0-100)
  final String reasoning; // Gemini'nin açıklaması
  
  MatchPrediction({
    required this.homeTeam,
    required this.awayTeam,
    required this.userPrediction,
    required this.geminiPrediction,
    required this.successProbability,
    required this.reasoning,
  });
  
  factory MatchPrediction.fromMap(Map<String, dynamic> map) {
    return MatchPrediction(
      homeTeam: map['homeTeam'] ?? '',
      awayTeam: map['awayTeam'] ?? '',
      userPrediction: map['userPrediction'] ?? '',
      geminiPrediction: map['geminiPrediction'] ?? '',
      successProbability: (map['successProbability'] ?? 0).toDouble(),
      reasoning: map['reasoning'] ?? '',
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'homeTeam': homeTeam,
      'awayTeam': awayTeam,
      'userPrediction': userPrediction,
      'geminiPrediction': geminiPrediction,
      'successProbability': successProbability,
      'reasoning': reasoning,
    };
  }
}