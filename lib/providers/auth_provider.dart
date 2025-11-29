import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../models/credit_transaction_model.dart';
import '../services/user_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserService _userService = UserService();
  
  User? _user;
  UserModel? _userModel;
  bool _isLoading = false;
  String? _errorMessage;
  
  // Getters
  User? get user => _user;
  UserModel? get userModel => _userModel;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null;
  int get credits => _userModel?.credits ?? 0;
  bool get isPremium => _userModel?.isActivePremium ?? false;
  bool get canAnalyze => _userModel?.canAnalyze ?? false;
  
  AuthProvider() {
    // Auth durumu değişikliklerini dinle
    _auth.authStateChanges().listen((User? user) async {
      _user = user;
      
      if (user != null) {
        await _loadUserModel(user.uid);
      } else {
        _userModel = null;
      }
      
      notifyListeners();
    });
  }
  
  // User model'i yükle
  Future<void> _loadUserModel(String uid) async {
    try {
      final userModel = await _userService.getUser(uid);
      _userModel = userModel;
      notifyListeners();
    } catch (e) {
      print('❌ User model yükleme hatası: $e');
    }
  }
  
  // User model'i realtime dinle
  void listenToUserModel(String uid) {
    _userService.getUserStream(uid).listen((userModel) {
      _userModel = userModel;
      notifyListeners();
    });
  }
  
  // E-posta ile kayıt
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Kullanıcı adını güncelle
      await userCredential.user?.updateDisplayName(name);
      await userCredential.user?.reload();
      _user = _auth.currentUser;
      
      // Firestore'da kullanıcı oluştur
      if (_user != null) {
        final newUser = UserModel(
          uid: _user!.uid,
          email: _user!.email ?? email,
          displayName: name,
          photoUrl: _user!.photoURL,
          credits: 3, // İlk kayıtta 3 kredi
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        
        await _userService.createOrUpdateUser(newUser);
        
        // Hoşgeldin bonusu kaydı
        await _userService.addCredits(
          userId: _user!.uid,
          amount: 3,
          type: TransactionType.welcome,
          description: 'Hoşgeldin bonusu - İlk 3 ücretsiz analiz',
        );
        
        await _loadUserModel(_user!.uid);
        listenToUserModel(_user!.uid);
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      _errorMessage = _getErrorMessage(e.code);
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Beklenmeyen bir hata oluştu: $e';
      notifyListeners();
      return false;
    }
  }
  
  // E-posta ile giriş
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      _user = _auth.currentUser;
      
      if (_user != null) {
        // Son giriş zamanını güncelle
        await _userService.createOrUpdateUser(UserModel(
          uid: _user!.uid,
          email: _user!.email ?? email,
          displayName: _user!.displayName,
          photoUrl: _user!.photoURL,
          createdAt: DateTime.now(), // Merge olacak
          lastLoginAt: DateTime.now(),
        ));
        
        await _loadUserModel(_user!.uid);
        listenToUserModel(_user!.uid);
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      _errorMessage = _getErrorMessage(e.code);
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Beklenmeyen bir hata oluştu: $e';
      notifyListeners();
      return false;
    }
  }
  
  // Google ile giriş
  Future<bool> signInWithGoogle() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      final userCredential = await _auth.signInWithCredential(credential);
      _user = userCredential.user;
      
      if (_user != null) {
        // Yeni kullanıcı mı kontrol et
        final existingUser = await _userService.getUser(_user!.uid);
        
        if (existingUser == null) {
          // Yeni kullanıcı - hoşgeldin bonusu ver
          final newUser = UserModel(
            uid: _user!.uid,
            email: _user!.email ?? '',
            displayName: _user!.displayName,
            photoUrl: _user!.photoURL,
            credits: 3,
            createdAt: DateTime.now(),
            lastLoginAt: DateTime.now(),
          );
          
          await _userService.createOrUpdateUser(newUser);
          
          await _userService.addCredits(
            userId: _user!.uid,
            amount: 3,
            type: TransactionType.welcome,
            description: 'Hoşgeldin bonusu - İlk 3 ücretsiz analiz',
          );
        } else {
          // Mevcut kullanıcı - son giriş güncelle
          await _userService.createOrUpdateUser(UserModel(
            uid: _user!.uid,
            email: _user!.email ?? '',
            displayName: _user!.displayName,
            photoUrl: _user!.photoURL,
            createdAt: existingUser.createdAt,
            lastLoginAt: DateTime.now(),
          ));
        }
        
        await _loadUserModel(_user!.uid);
        listenToUserModel(_user!.uid);
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Google ile giriş yapılamadı: $e';
      notifyListeners();
      return false;
    }
  }
  
  // Çıkış yap
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
      _user = null;
      _userModel = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Çıkış yapılamadı: $e';
      notifyListeners();
    }
  }
  
  // Şifre sıfırlama
  Future<bool> resetPassword(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      await _auth.sendPasswordResetEmail(email: email);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      _errorMessage = _getErrorMessage(e.code);
      notifyListeners();
      return false;
    }
  }
  
  // Kredi kullan
  Future<bool> useCredit({String? analysisId}) async {
    if (_user == null) return false;
    
    final success = await _userService.useCredit(
      _user!.uid,
      analysisId: analysisId,
    );
    
    if (success) {
      await _loadUserModel(_user!.uid);
    }
    
    return success;
  }
  
  // Kredi ekle
  Future<bool> addCredits(int amount, String productId, String purchaseId) async {
    if (_user == null) return false;
    
    final success = await _userService.addCredits(
      userId: _user!.uid,
      amount: amount,
      type: TransactionType.purchase,
      description: 'Kredi satın alma',
      productId: productId,
      purchaseId: purchaseId,
    );
    
    if (success) {
      await _loadUserModel(_user!.uid);
    }
    
    return success;
  }
  
  // Premium aktive et
  Future<bool> activatePremium(int days, String productId, String purchaseId) async {
    if (_user == null) return false;
    
    final success = await _userService.setPremium(
      userId: _user!.uid,
      durationDays: days,
      productId: productId,
      purchaseId: purchaseId,
    );
    
    if (success) {
      await _loadUserModel(_user!.uid);
    }
    
    return success;
  }
  
  // Hata mesajlarını Türkçeleştir
  String _getErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'Şifre çok zayıf.';
      case 'email-already-in-use':
        return 'Bu e-posta adresi zaten kullanımda.';
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      case 'user-not-found':
        return 'Kullanıcı bulunamadı.';
      case 'wrong-password':
        return 'Yanlış şifre.';
      case 'user-disabled':
        return 'Bu hesap devre dışı bırakılmış.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar deneyin.';
      default:
        return 'Bir hata oluştu: $code';
    }
  }
  
  // Hata mesajını temizle
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // User model'i manuel yenile
  Future<void> refreshUserModel() async {
    if (_user != null) {
      await _loadUserModel(_user!.uid);
    }
  }
}