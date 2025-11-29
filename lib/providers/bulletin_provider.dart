import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bulletin_model.dart';

class BulletinProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<BulletinModel> _bulletins = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // Getters
  List<BulletinModel> get bulletins => _bulletins;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  // Kullanıcının bültenlerini getir
  Future<void> fetchUserBulletins(String userId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      final querySnapshot = await _firestore
          .collection('bulletins')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();
      
      _bulletins = querySnapshot.docs
          .map((doc) => BulletinModel.fromFirestore(doc))
          .toList();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Bültenler yüklenirken hata oluştu: $e';
      notifyListeners();
    }
  }
  
  // Yeni bülten oluştur
  Future<String?> createBulletin({
    required String userId,
    String? imageUrl,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      final docRef = await _firestore.collection('bulletins').add({
        'userId': userId,
        'imageUrl': imageUrl ?? '',
        'status': 'pending', // pending, analyzing, completed, failed
        'createdAt': FieldValue.serverTimestamp(),
        'analyzedAt': null,
      });
      
      _isLoading = false;
      notifyListeners();
      
      return docRef.id;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Bülten oluşturulurken hata oluştu: $e';
      notifyListeners();
      return null;
    }
  }
  
  // Bülten durumunu güncelle
  Future<void> updateBulletinStatus(String bulletinId, String status) async {
    try {
      await _firestore.collection('bulletins').doc(bulletinId).update({
        'status': status,
        'analyzedAt': status == 'completed' ? FieldValue.serverTimestamp() : null,
      });
      
      // Listeyi güncelle
      final index = _bulletins.indexWhere((b) => b.id == bulletinId);
      if (index != -1) {
        _bulletins[index] = _bulletins[index].copyWith(
          status: status,
          analyzedAt: status == 'completed' ? DateTime.now() : null,
        );
        notifyListeners();
      }
    } catch (e) {
      print('❌ Durum güncelleme hatası: $e');
    }
  }
  
  // Bülten analizini güncelle
  Future<void> updateBulletinAnalysis(
    String bulletinId,
    Map<String, dynamic> analysis,
  ) async {
    try {
      await _firestore.collection('bulletins').doc(bulletinId).update({
        'status': 'completed',
        'analysis': analysis,
        'analyzedAt': FieldValue.serverTimestamp(),
      });
      
      // Listeyi güncelle
      final index = _bulletins.indexWhere((b) => b.id == bulletinId);
      if (index != -1) {
        _bulletins[index] = _bulletins[index].copyWith(
          status: 'completed',
          analysis: analysis,
          analyzedAt: DateTime.now(),
        );
        notifyListeners();
      }
    } catch (e) {
      print('❌ Analiz güncelleme hatası: $e');
      await updateBulletinStatus(bulletinId, 'failed');
    }
  }
  
  // Bülten detayını getir
  Future<BulletinModel?> getBulletin(String bulletinId) async {
    try {
      final doc = await _firestore.collection('bulletins').doc(bulletinId).get();
      
      if (doc.exists) {
        return BulletinModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      _errorMessage = 'Bülten detayı alınırken hata oluştu: $e';
      notifyListeners();
      return null;
    }
  }
  
  // Bülteni sil
  Future<bool> deleteBulletin(String bulletinId) async {
    try {
      await _firestore.collection('bulletins').doc(bulletinId).delete();
      
      _bulletins.removeWhere((b) => b.id == bulletinId);
      notifyListeners();
      
      return true;
    } catch (e) {
      _errorMessage = 'Bülten silinirken hata oluştu: $e';
      notifyListeners();
      return false;
    }
  }
  
  // Bülten stream'i dinle (realtime)
  Stream<BulletinModel?> getBulletinStream(String bulletinId) {
    return _firestore
        .collection('bulletins')
        .doc(bulletinId)
        .snapshots()
        .map((doc) => doc.exists ? BulletinModel.fromFirestore(doc) : null);
  }
  
  // Hata mesajını temizle
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}