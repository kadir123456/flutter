import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:cloud_functions/cloud_functions.dart';

class InAppPurchaseService {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  // Firebase Functions instance - default region (otomatik detect eder)
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  // Product ID'leri - Google Play Console'da tanımlanacak
  static const String credit5 = 'credits_5';
  static const String credit10 = 'credits_10';
  static const String credit25 = 'credits_25';
  static const String credit50 = 'credits_50';
  static const String premiumMonthly = 'premium_monthly';
  static const String premium3Months = 'premium_3months';
  static const String premiumYearly = 'premium_yearly';
  
  // Tüm ürün ID'leri
  static const Set<String> _productIds = {
    credit5,
    credit10,
    credit25,
    credit50,
    premiumMonthly,
    premium3Months,
    premiumYearly,
  };
  
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _purchasePending = false;
  
  // Getters
  List<ProductDetails> get products => _products;
  bool get isAvailable => _isAvailable;
  bool get purchasePending => _purchasePending;
  
  // Satın alma callback'i
  Function(PurchaseDetails)? onPurchaseSuccess;
  Function(String)? onPurchaseError;
  
  // Package name (Android) - build.gradle.kts'den alınmıştır
  static const String packageName = 'com.aisporanaliz.app';
  
  // Initialize
  Future<void> initialize() async {
    try {
      // Android için ekstra ayarlar
      // NOT: enablePendingPurchases() artık gerekli değil, otomatik aktif
      if (Platform.isAndroid) {
        final InAppPurchaseAndroidPlatformAddition androidAddition =
            _inAppPurchase
                .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        
        // Android platform eklentisi hazır
        debugPrint('Android IAP platform eklentisi yüklendi');
      }
      
      // Store bağlantısını kontrol et
      _isAvailable = await _inAppPurchase.isAvailable();
      
      if (!_isAvailable) {
        debugPrint('❌ In-App Purchase kullanılamıyor');
        return;
      }
      
      // Ürünleri yükle
      await loadProducts();
      
      // Purchase stream'i dinle
      _subscription = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription.cancel(),
        onError: (error) {
          debugPrint('❌ Purchase stream error: $error');
          onPurchaseError?.call(error.toString());
        },
      );
      
      debugPrint('✅ In-App Purchase başlatıldı');
    } catch (e) {
      debugPrint('❌ In-App Purchase başlatma hatası: $e');
    }
  }
  
  // Ürünleri yükle
  Future<void> loadProducts() async {
    try {
      final ProductDetailsResponse response = await _inAppPurchase
          .queryProductDetails(_productIds);
      
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('⚠️ Bulunamayan ürünler: ${response.notFoundIDs}');
      }
      
      if (response.error != null) {
        debugPrint('❌ Ürün yükleme hatası: ${response.error}');
        return;
      }
      
      _products = response.productDetails;
      debugPrint('✅ ${_products.length} ürün yüklendi');
      
      // Ürünleri log'la
      for (var product in _products) {
        debugPrint('  - ${product.id}: ${product.title} - ${product.price}');
      }
    } catch (e) {
      debugPrint('❌ Ürün yükleme exception: $e');
    }
  }
  
  // Satın alma başlat
  Future<bool> purchaseProduct(String productId) async {
    if (!_isAvailable) {
      onPurchaseError?.call('In-App Purchase kullanılamıyor');
      return false;
    }
    
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Ürün bulunamadı: $productId'),
    );
    
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    
    _purchasePending = true;
    
    try {
      // Premium abonelikler için
      if (productId == premiumMonthly || productId == premium3Months || productId == premiumYearly) {
        return await _inAppPurchase.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
      }
      // Kredi paketleri için
      else {
        return await _inAppPurchase.buyConsumable(
          purchaseParam: purchaseParam,
        );
      }
    } catch (e) {
      debugPrint('❌ Satın alma hatası: $e');
      _purchasePending = false;
      onPurchaseError?.call(e.toString());
      return false;
    }
  }
  
  // Purchase güncellemelerini işle
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          _purchasePending = false;
          onPurchaseError?.call(purchaseDetails.error?.message ?? 'Bilinmeyen hata');
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          // ✅ SUNUCU TARAFI DOĞRULAMA
          _verifyPurchaseWithServer(purchaseDetails);
        }
        
        // Satın almayı tamamla (doğrulama sonrası yapılacak)
        // if (purchaseDetails.pendingCompletePurchase) {
        //   _inAppPurchase.completePurchase(purchaseDetails);
        // }
      }
    }
  }
  
  // 🔐 SUNUCU DOĞRULAMA - Sahte satın almaları engeller!
  Future<void> _verifyPurchaseWithServer(PurchaseDetails purchaseDetails) async {
    try {
      debugPrint('🔐 Satın alma sunucu doğrulaması başlıyor...');
      
      String? purchaseToken;
      
      // Android için purchase token al
      if (Platform.isAndroid) {
        final androidDetails = purchaseDetails as PurchaseDetails;
        // verificationData içinde serverVerificationData var
        purchaseToken = androidDetails.verificationData.serverVerificationData;
      }
      
      if (purchaseToken == null || purchaseToken.isEmpty) {
        debugPrint('❌ Purchase token bulunamadı');
        _purchasePending = false;
        onPurchaseError?.call('Satın alma bilgisi eksik');
        return;
      }
      
      // Firebase Functions ile doğrula
      final callable = _functions.httpsCallable('verifyGooglePlayPurchase');
      final result = await callable.call({
        'productId': purchaseDetails.productID,
        'purchaseToken': purchaseToken,
        'packageName': packageName,
      });
      
      final data = result.data;
      
      if (data['success'] == true && data['verified'] == true) {
        debugPrint('✅ Satın alma sunucuda doğrulandı: ${data['orderId']}');
        
        // Başarılı - Callback çağır
        _purchasePending = false;
        onPurchaseSuccess?.call(purchaseDetails);
        
        // Satın almayı tamamla
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
          debugPrint('✅ Purchase completed');
        }
      } else {
        debugPrint('❌ Sunucu doğrulama başarısız');
        _purchasePending = false;
        onPurchaseError?.call('Satın alma doğrulanamadı');
      }
    } catch (e) {
      debugPrint('❌ Sunucu doğrulama hatası: $e');
      _purchasePending = false;
      
      // Hata mesajını kontrol et
      if (e.toString().contains('already-exists') || 
          e.toString().contains('Bu satın alma daha önce kullanıldı')) {
        onPurchaseError?.call('Bu satın alma zaten kullanılmış');
      } else {
        onPurchaseError?.call('Doğrulama hatası: ${e.toString()}');
      }
      
      // Purchase'ı complete et (hata durumunda da)
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }
  
  // Satın almaları geri yükle
  Future<void> restorePurchases() async {
    try {
      await _inAppPurchase.restorePurchases();
      debugPrint('✅ Satın almalar geri yüklendi');
    } catch (e) {
      debugPrint('❌ Geri yükleme hatası: $e');
      onPurchaseError?.call(e.toString());
    }
  }
  
  // Kredi miktarını product ID'den al (BONUS DAHİL)
  int getCreditAmountFromProduct(String productId) {
    switch (productId) {
      case credit5:
        return 6;   // 5 + 1 bonus
      case credit10:
        return 12;  // 10 + 2 bonus
      case credit25:
        return 30;  // 25 + 5 bonus
      case credit50:
        return 65;  // 50 + 15 bonus
      default:
        return 0;
    }
  }
  
  // Sadece base kredi miktarını al (bonus hariç)
  int getBaseCreditAmount(String productId) {
    switch (productId) {
      case credit5:
        return 5;
      case credit10:
        return 10;
      case credit25:
        return 25;
      case credit50:
        return 50;
      default:
        return 0;
    }
  }
  
  // Bonus kredi miktarını al
  int getBonusCreditAmount(String productId) {
    switch (productId) {
      case credit5:
        return 1;
      case credit10:
        return 2;
      case credit25:
        return 5;
      case credit50:
        return 15;
      default:
        return 0;
    }
  }
  
  // Premium süresini product ID'den al (gün)
  int getPremiumDaysFromProduct(String productId) {
    switch (productId) {
      case premiumMonthly:
        return 30;
      case premium3Months:
        return 90;
      case premiumYearly:
        return 365;
      default:
        return 0;
    }
  }
  
  // Premium ürün mü?
  bool isPremiumProduct(String productId) {
    return productId == premiumMonthly || productId == premium3Months || productId == premiumYearly;
  }
  
  // Temizle
  void dispose() {
    _subscription.cancel();
  }
}