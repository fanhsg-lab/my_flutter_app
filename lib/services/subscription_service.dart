import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../local_db.dart';

// ========================
// DATA MODEL
// ========================

enum AccessLevel { trial, subscribed, locked }

class SubscriptionState {
  final AccessLevel access;
  final int trialDaysLeft;
  final String? productId;
  final DateTime? expiresAt;

  const SubscriptionState({
    required this.access,
    this.trialDaysLeft = 0,
    this.productId,
    this.expiresAt,
  });

  bool get canLearn => access != AccessLevel.locked;

  static const SubscriptionState loading = SubscriptionState(
    access: AccessLevel.trial,
    trialDaysLeft: 60,
  );
}

// ========================
// PRODUCT IDS
// ========================

const String kMonthlyProductId = 'palabra_monthly';
const String kYearlyProductId = 'palabra_yearly';
const Set<String> kProductIds = {kMonthlyProductId, kYearlyProductId};

// ========================
// SUBSCRIPTION SERVICE
// ========================

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  final ValueNotifier<SubscriptionState> state = ValueNotifier(SubscriptionState.loading);

  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  bool _initialized = false;

  List<ProductDetails> get products => _products;

  /// Call once after auth is confirmed (e.g. in MainScreen._initialLoad)
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Load cached state first (instant, offline-safe)
    await _loadCachedState();

    // 2. Refresh from Supabase if online
    try {
      await refreshStatus();
    } catch (e) {
      debugPrint("⚠️ Could not refresh subscription status: $e");
    }

    // 3. Initialize in-app purchase
    if (await InAppPurchase.instance.isAvailable()) {
      _listenToPurchaseUpdates();
      await _loadProducts();
    } else {
      debugPrint("⚠️ In-app purchases not available");
    }
  }

  /// Refresh subscription status from Supabase RPC
  Future<void> refreshStatus() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .rpc('get_subscription_status', params: {'p_user_id': userId});

      if (response is List && response.isNotEmpty) {
        final data = response[0] as Map<String, dynamic>;
        _applyServerStatus(data);
      } else if (response is Map) {
        _applyServerStatus(response as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching subscription status: $e");
    }
  }

  void _applyServerStatus(Map<String, dynamic> data) {
    final isTrial = data['is_trial'] as bool? ?? false;
    final trialDaysLeft = data['trial_days_left'] as int? ?? 0;
    final hasActiveSub = data['has_active_sub'] as bool? ?? false;
    final subExpiresAt = data['sub_expires_at'] != null
        ? DateTime.tryParse(data['sub_expires_at'].toString())
        : null;

    AccessLevel access;
    if (hasActiveSub) {
      access = AccessLevel.subscribed;
    } else if (isTrial) {
      access = AccessLevel.trial;
    } else {
      access = AccessLevel.locked;
    }

    state.value = SubscriptionState(
      access: access,
      trialDaysLeft: trialDaysLeft,
      expiresAt: subExpiresAt,
    );

    // Cache locally
    LocalDB.instance.setSubscriptionCache(
      accessLevel: access.name,
      trialDaysLeft: trialDaysLeft,
      expiresAt: subExpiresAt?.toIso8601String(),
    );
  }

  Future<void> _loadCachedState() async {
    final cache = await LocalDB.instance.getSubscriptionCache();
    if (cache.isEmpty) return;

    final levelStr = cache['sub_access_level'];
    final daysStr = cache['sub_trial_days_left'];
    final expiresStr = cache['sub_expires_at'];

    AccessLevel access = AccessLevel.trial;
    if (levelStr == 'subscribed') access = AccessLevel.subscribed;
    else if (levelStr == 'locked') access = AccessLevel.locked;

    state.value = SubscriptionState(
      access: access,
      trialDaysLeft: int.tryParse(daysStr ?? '') ?? 0,
      expiresAt: (expiresStr != null && expiresStr.isNotEmpty)
          ? DateTime.tryParse(expiresStr)
          : null,
    );
  }

  Future<void> _loadProducts() async {
    final response = await InAppPurchase.instance.queryProductDetails(kProductIds);
    if (response.error != null) {
      debugPrint("⚠️ Error loading products: ${response.error}");
      return;
    }
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint("⚠️ Products not found: ${response.notFoundIDs}");
    }
    _products = response.productDetails.toList();
    debugPrint("✅ Loaded ${_products.length} products");
  }

  void _listenToPurchaseUpdates() {
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      (purchases) {
        for (final purchase in purchases) {
          _handlePurchase(purchase);
        }
      },
      onError: (error) {
        debugPrint("❌ Purchase stream error: $error");
      },
    );
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      // Verify with server
      await _verifyPurchase(purchase);
    }

    if (purchase.status == PurchaseStatus.error) {
      debugPrint("❌ Purchase error: ${purchase.error}");
    }

    // Always complete pending purchases
    if (purchase.pendingCompletePurchase) {
      await InAppPurchase.instance.completePurchase(purchase);
    }
  }

  Future<void> _verifyPurchase(PurchaseDetails purchase) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'verify-purchase',
        body: {
          'product_id': purchase.productID,
          'purchase_token': purchase.verificationData.serverVerificationData,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        },
      );

      // Refresh status after verification
      await refreshStatus();
      debugPrint("✅ Purchase verified: ${purchase.productID}");
    } catch (e) {
      debugPrint("❌ Error verifying purchase: $e");
    }
  }

  /// Start a purchase flow
  Future<void> purchase(String productId) async {
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product $productId not found'),
    );

    final purchaseParam = PurchaseParam(productDetails: product);
    // Subscriptions are non-consumable
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    await InAppPurchase.instance.restorePurchases();
  }

  /// Clean up (call on logout)
  void dispose() {
    _purchaseSubscription?.cancel();
    _initialized = false;
  }
}
