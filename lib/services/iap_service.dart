import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

class InAppPurchaseService {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  // Product ID'leri - Google Play Console'da tanımlanacak
  static const String credit10 = 'credits_10';
  static const String credit25 = 'credits_25';
  static const String credit50 = 'credits_50';
  static const String credit100 = 'credits_100';
  static const String premiumMonthly = 'premium_monthly';
  static const String premiumYearly = 'premium_yearly';
  
  // Tüm ürün ID'leri
  static const Set<String> _productIds = {
    credit10,
    credit25,
    credit50,
    credit100,
    premiumMonthly,
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
  
  // Initialize
  Future<void> initialize() async {
    try {
      // Android için ekstra ayarlar
      if (Platform.isAndroid) {
        final InAppPurchaseAndroidPlatformAddition androidAddition =
            _inAppPurchase
                .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        
        // Pending purchases kontrolü
        await androidAddition.enablePendingPurchases();
      }
      
      // Store bağlantısını kontrol et
      _isAvailable = await _inAppPurchase.isAvailable();
      
      if (!_isAvailable) {
        print('❌ In-App Purchase kullanılamıyor');
        return;
      }
      
      // Ürünleri yükle
      await loadProducts();
      
      // Purchase stream'i dinle
      _subscription = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription.cancel(),
        onError: (error) {
          print('❌ Purchase stream error: $error');
          onPurchaseError?.call(error.toString());
        },
      );
      
      print('✅ In-App Purchase başlatıldı');
    } catch (e) {
      print('❌ In-App Purchase başlatma hatası: $e');
    }
  }
  
  // Ürünleri yükle
  Future<void> loadProducts() async {
    try {
      final ProductDetailsResponse response = await _inAppPurchase
          .queryProductDetails(_productIds);
      
      if (response.notFoundIDs.isNotEmpty) {
        print('⚠️ Bulunamayan ürünler: ${response.notFoundIDs}');
      }
      
      if (response.error != null) {
        print('❌ Ürün yükleme hatası: ${response.error}');
        return;
      }
      
      _products = response.productDetails;
      print('✅ ${_products.length} ürün yüklendi');
      
      // Ürünleri log'la
      for (var product in _products) {
        print('  - ${product.id}: ${product.title} - ${product.price}');
      }
    } catch (e) {
      print('❌ Ürün yükleme exception: $e');
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
      if (productId == premiumMonthly || productId == premiumYearly) {
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
      print('❌ Satın alma hatası: $e');
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
          // Satın alma başarılı
          _purchasePending = false;
          onPurchaseSuccess?.call(purchaseDetails);
        }
        
        // Satın almayı tamamla
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }
  
  // Satın almaları geri yükle
  Future<void> restorePurchases() async {
    try {
      await _inAppPurchase.restorePurchases();
      print('✅ Satın almalar geri yüklendi');
    } catch (e) {
      print('❌ Geri yükleme hatası: $e');
      onPurchaseError?.call(e.toString());
    }
  }
  
  // Kredi miktarını product ID'den al
  int getCreditAmountFromProduct(String productId) {
    switch (productId) {
      case credit10:
        return 10;
      case credit25:
        return 25;
      case credit50:
        return 50;
      case credit100:
        return 100;
      default:
        return 0;
    }
  }
  
  // Premium süresini product ID'den al (gün)
  int getPremiumDaysFromProduct(String productId) {
    switch (productId) {
      case premiumMonthly:
        return 30;
      case premiumYearly:
        return 365;
      default:
        return 0;
    }
  }
  
  // Premium ürün mü?
  bool isPremiumProduct(String productId) {
    return productId == premiumMonthly || productId == premiumYearly;
  }
  
  // Temizle
  void dispose() {
    _subscription.cancel();
  }
}