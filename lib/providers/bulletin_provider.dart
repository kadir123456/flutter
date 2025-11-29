import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bulletin_model.dart';

class BulletinProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Bulletin> _bulletins = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // Getters
  List<Bulletin> get bulletins => _bulletins;
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
          .map((doc) => Bulletin.fromFirestore(doc))
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
    required String imageUrl,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      final docRef = await _firestore.collection('bulletins').add({
        'userId': userId,
        'imageUrl': imageUrl,
        'status': 'pending', // pending, analyzing, completed, failed
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
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
  
  // Bülten detayını getir
  Future<Bulletin?> getBulletin(String bulletinId) async {
    try {
      final doc = await _firestore.collection('bulletins').doc(bulletinId).get();
      
      if (doc.exists) {
        return Bulletin.fromFirestore(doc);
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
  
  // Hata mesajını temizle
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}