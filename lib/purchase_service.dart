import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCatでの課金管理。
/// TODO: RevenueCatダッシュボードで作成したAPIキーに差し替えること。
/// iOS/Androidそれぞれのプロジェクト設定 > API keys から取得できる。
class PurchaseService {
  // TODO: RevenueCatダッシュボードでApple/Google商品を連携後、
  // それぞれ appl_ / goog_ で始まる本番用キーに差し替えること。
  // 現在はRevenueCat発行のテスト用キー（動作確認用、実課金不可）。
  static const String _iosApiKey = 'test_kBAfNmzwIrQpZEiOvMlvZXBkpBd';
  static const String _androidApiKey = 'test_kBAfNmzwIrQpZEiOvMlvZXBkpBd';

  /// RevenueCatダッシュボードで作成したEntitlement識別子。
  static const String entitlementId = 'StyleMind AI Pro';

  /// 無料プランで生成できる生涯合計回数。
  static const int freeGenerationLimit = 5;

  /// Web版はストア課金の仕組みが無いため、無料枠のみで運用する。
  static bool get isPurchaseSupported => !kIsWeb;

  static Future<void> init() async {
    if (!isPurchaseSupported) return;
    try {
      final apiKey = defaultTargetPlatform == TargetPlatform.iOS
          ? _iosApiKey
          : _androidApiKey;
      await Purchases.configure(PurchasesConfiguration(apiKey));
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await Purchases.logIn(uid);
      }
    } catch (e) {
      debugPrint('PurchaseService.init failed: $e');
    }
  }

  /// 現在のユーザーが有料プラン（Entitlement有効）かどうか。
  /// 判定に失敗した場合は無料枠扱い（fail-closed）にする。
  static Future<bool> isPremium() async {
    if (!isPurchaseSupported) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('PurchaseService.isPremium failed: $e');
      return false;
    }
  }

  /// 現在のオファリングの月額パッケージを購入する。
  /// 成功したらtrueを返す。ユーザーによるキャンセルや失敗はfalseを返す。
  static Future<bool> purchasePremium() async {
    if (!isPurchaseSupported) return false;
    try {
      final offerings = await Purchases.getOfferings();
      final available = offerings.current?.availablePackages ?? const [];
      final package = offerings.current?.monthly ?? (available.isNotEmpty ? available.first : null);
      if (package == null) {
        debugPrint('PurchaseService.purchasePremium: no package available');
        return false;
      }
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return result.customerInfo.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('PurchaseService.purchasePremium failed: $e');
      return false;
    }
  }

  static Future<bool> restorePurchases() async {
    if (!isPurchaseSupported) return false;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('PurchaseService.restorePurchases failed: $e');
      return false;
    }
  }

  /// 無料枠の残り回数があるか、または有料プランかを確認する（判定のみ、カウントは増やさない）。
  static Future<bool> canGenerateImage() async {
    final premium = await isPremium();
    if (premium) return true;
    return (await remainingFreeGenerations()) > 0;
  }

  /// 画像生成に実際に成功した後に呼び出し、無料枠の使用回数を1つ消費する。
  /// 有料プランの場合は何もしない（無制限のためカウント不要）。
  static Future<void> recordGenerationUsed() async {
    final premium = await isPremium();
    if (premium) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await docRef.get();
    final used = (snap.data()?['freeGenerationsUsed'] as int?) ?? 0;
    await docRef.set({'freeGenerationsUsed': used + 1}, SetOptions(merge: true));
  }

  static Future<int> remainingFreeGenerations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final used = (doc.data()?['freeGenerationsUsed'] as int?) ?? 0;
    final bonus = (doc.data()?['bonusGenerations'] as int?) ?? 0;
    final remaining = (freeGenerationLimit + bonus) - used;
    return remaining < 0 ? 0 : remaining;
  }
}
