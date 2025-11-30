import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import '../models/user_model.dart';
import '../models/credit_transaction_model.dart';
import '../services/user_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserService _userService = UserService();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
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
  
  Future<void> _loadUserModel(String uid) async {
    try {
      final userModel = await _userService.getUser(uid);
      _userModel = userModel;
      notifyListeners();
    } catch (e) {
      print('❌ User model yükleme hatası: $e');
    }
  }
  
  void listenToUserModel(String uid) {
    _userService.getUserStream(uid).listen((userModel) {
      _userModel = userModel;
      notifyListeners();
    });
  }
  
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      // IP ve Device ID al
      final ipAddress = await _getIpAddress();
      final deviceId = await _getDeviceId();
      
      // IP BAN KONTROLÜ
      final isBanned = await _userService.checkIpBan(ipAddress, deviceId);
      if (isBanned) {
        _isLoading = false;
        _errorMessage = 'Bu cihazdan daha önce hesap oluşturulmuş.\n\nDestek ekibimizle iletişime geçin:\nbilwininc@gmail.com';
        notifyListeners();
        return false;
      }
      
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      await userCredential.user?.updateDisplayName(name);
      await userCredential.user?.reload();
      _user = _auth.currentUser;
      
      if (_user != null) {
        final newUser = UserModel(
          uid: _user!.uid,
          email: _user!.email ?? email,
          displayName: name,
          photoUrl: _user!.photoURL,
          credits: 3,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          ipAddress: ipAddress,
          deviceId: deviceId,
          isBanned: false,
        );
        
        await _userService.createOrUpdateUser(newUser);
        
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
        // Kullanıcı ban kontrolü
        final existingUser = await _userService.getUser(_user!.uid);
        if (existingUser != null && existingUser.isBanned) {
          await _auth.signOut();
          _user = null;
          _isLoading = false;
          _errorMessage = 'Hesabınız askıya alınmıştır.\n\nDestek ekibimizle iletişime geçin:\nbilwininc@gmail.com';
          notifyListeners();
          return false;
        }
        
        // Giriş başarılı - Sadece lastLoginAt güncelle (KREDİLER KORUNUR)
        await _userService.createOrUpdateUser(UserModel(
          uid: _user!.uid,
          email: _user!.email ?? email,
          displayName: _user!.displayName,
          photoUrl: _user!.photoURL,
          createdAt: existingUser?.createdAt ?? DateTime.now(),
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
        final existingUser = await _userService.getUser(_user!.uid);
        
        if (existingUser == null) {
          // YENİ KULLANICI - IP BAN KONTROLÜ
          final ipAddress = await _getIpAddress();
          final deviceId = await _getDeviceId();
          
          final isBanned = await _userService.checkIpBan(ipAddress, deviceId);
          if (isBanned) {
            await _auth.signOut();
            await _googleSignIn.signOut();
            _user = null;
            _isLoading = false;
            _errorMessage = 'Bu cihazdan daha önce hesap oluşturulmuş.\n\nDestek ekibimizle iletişime geçin:\nbilwininc@gmail.com';
            notifyListeners();
            return false;
          }
          
          final newUser = UserModel(
            uid: _user!.uid,
            email: _user!.email ?? '',
            displayName: _user!.displayName,
            photoUrl: _user!.photoURL,
            credits: 3,
            createdAt: DateTime.now(),
            lastLoginAt: DateTime.now(),
            ipAddress: ipAddress,
            deviceId: deviceId,
            isBanned: false,
          );
          
          await _userService.createOrUpdateUser(newUser);
        } else {
          // MEVCUT KULLANICI - Ban kontrolü
          if (existingUser.isBanned) {
            await _auth.signOut();
            await _googleSignIn.signOut();
            _user = null;
            _isLoading = false;
            _errorMessage = 'Hesabınız askıya alınmıştır.\n\nDestek ekibimizle iletişime geçin:\nbilwininc@gmail.com';
            notifyListeners();
            return false;
          }
          
          // Sadece lastLoginAt güncelle (KREDİLER KORUNUR)
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
  
  // Alternatif metod isimleri (LoginScreen için gerekli)
  Future<bool> signInWithEmailAndPassword(String email, String password) async {
    return await signInWithEmail(email: email, password: password);
  }
  
  Future<bool> sendPasswordResetEmail(String email) async {
    return await resetPassword(email);
  }
  
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
  
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  Future<void> refreshUserModel() async {
    if (_user != null) {
      await _loadUserModel(_user!.uid);
    }
  }
  
  // IP adresini al
  Future<String?> _getIpAddress() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org?format=json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ip'];
      }
    } catch (e) {
      print('⚠️ IP adresi alınamadı: $e');
    }
    return null;
  }
  
  // Cihaz ID'sini al
  Future<String?> _getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor; // iOS Vendor ID
      }
    } catch (e) {
      print('⚠️ Device ID alınamadı: $e');
    }
    return null;
  }
}