import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'device_id.dart';

/// 紹介コード・ポイント制度（2026-07-21実装、初期簡易版）。
///
/// 設計方針：
/// - 招待した側+30pt／招待された側+20pt は、招待された側が
///   プロフィール（診断含む）を完了した時点で自動付与する
/// - 不正対策は「同一デバイスIDからの自己招待をブロックする」簡易版のみ。
///   IPベースの検知や本人確認等は行わない（初速優先、実際に不正が
///   問題化してから強化する方針）
/// - 100pt（限定コーデパターン解放）・200pt（500円クーポン）は、
///   限定コンテンツ設計・RevenueCat本番化が未完了のため、ポイント消費の
///   受け口はあるが実際の特典付与は未実装（UI上は「近日公開」表示）
class PointsService {
  static final _users = FirebaseFirestore.instance.collection('users');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static String _generateCode(String uid) {
    final rnd = Random(uid.hashCode);
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 紛らわしい文字(0,O,1,I)を除外
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// このユーザーの紹介コードを取得。無ければ生成して保存する。
  static Future<String> ensureReferralCode() async {
    final uid = _uid;
    if (uid == null) return '';
    final docRef = _users.doc(uid);
    final snap = await docRef.get();
    final existing = snap.data()?['referralCode'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    var code = _generateCode(uid);
    // 衝突チェック（6桁33種で約15億通りあるため基本的に衝突しないが念のため）
    final clash = await _users.where('referralCode', isEqualTo: code).limit(1).get();
    if (clash.docs.isNotEmpty) code = _generateCode('$uid${DateTime.now().microsecondsSinceEpoch}');

    await docRef.set({'referralCode': code}, SetOptions(merge: true));
    return code;
  }

  static String shareUrl(String code) => 'https://stylemind-ai-d14ec.web.app/?ref=$code';

  /// アプリ起動時のURLに ?ref=CODE が含まれていれば、
  /// このユーザーの「招待してくれた人」として一度だけ記録する。
  /// （プロフィール未完成のうちに複数回呼ばれても、記録は初回のみ）
  static Future<void> captureReferralCodeFromUrl(Uri appUrl) async {
    final uid = _uid;
    if (uid == null) return;
    final refCode = appUrl.queryParameters['ref'];
    if (refCode == null || refCode.isEmpty) return;

    final docRef = _users.doc(uid);
    final snap = await docRef.get();
    if (snap.data()?['referredBy'] != null) return; // 記録済み
    if ((snap.data()?['referralCode'] as String?) == refCode) return; // 自分の紹介コードでの自己参照は無視

    await docRef.set({'referredBy': refCode}, SetOptions(merge: true));
  }

  /// プロフィール（診断含む）完了時に呼ぶ。招待されたユーザーであれば
  /// 両者に加点する（初回のみ、デバイスIDが同一の場合はブロック）。
  /// 加点自体はトランザクションで保護し、同時呼び出しによる二重付与を防ぐ。
  static Future<void> awardReferralPointsIfEligible() async {
    final uid = _uid;
    if (uid == null) return;
    final docRef = _users.doc(uid);
    final snap = await docRef.get();
    final data = snap.data() ?? {};

    final referredBy = data['referredBy'] as String?;
    if (referredBy == null || referredBy.isEmpty) return;
    if (data['referralPointsAwarded'] == true) return; // 早期リターン（確定判定はトランザクション内で行う）

    final referrerQuery = await _users.where('referralCode', isEqualTo: referredBy).limit(1).get();
    if (referrerQuery.docs.isEmpty) {
      await docRef.set({'referralPointsAwarded': true}, SetOptions(merge: true));
      return;
    }
    final referrerDocRef = referrerQuery.docs.first.reference;
    if (referrerDocRef.id == uid) {
      await docRef.set({'referralPointsAwarded': true}, SetOptions(merge: true));
      return;
    }

    final myDeviceId = getOrCreatePersistedDeviceId();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final freshSelfSnap = await tx.get(docRef);
      if (freshSelfSnap.data()?['referralPointsAwarded'] == true) return; // トランザクション内での二重付与防止チェック

      final referrerSnap = await tx.get(referrerDocRef);
      final referrerDeviceId = referrerSnap.data()?['deviceId'] as String?;

      // 簡易不正対策：招待した側・された側で端末IDが一致する場合はブロック
      final sameDevice = referrerDeviceId != null && referrerDeviceId == myDeviceId;
      if (sameDevice) {
        tx.set(docRef, {'deviceId': myDeviceId, 'referralPointsAwarded': true, 'referralBlockedReason': 'same_device'}, SetOptions(merge: true));
        return;
      }

      tx.set(referrerDocRef, {'points': FieldValue.increment(30)}, SetOptions(merge: true));
      tx.set(docRef, {'deviceId': myDeviceId, 'points': FieldValue.increment(20), 'referralPointsAwarded': true}, SetOptions(merge: true));
    });
  }

  static Future<int> getPoints() async {
    final uid = _uid;
    if (uid == null) return 0;
    final snap = await _users.doc(uid).get();
    return (snap.data()?['points'] as int?) ?? 0;
  }

  /// 50pt消費→追加診断(画像生成)1回分を付与。ポイント不足ならfalse。
  static Future<bool> redeemBonusGeneration() async {
    final uid = _uid;
    if (uid == null) return false;
    final docRef = _users.doc(uid);
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final points = (snap.data()?['points'] as int?) ?? 0;
      if (points < 50) return false;
      tx.set(docRef, {
        'points': points - 50,
        'bonusGenerations': FieldValue.increment(1),
      }, SetOptions(merge: true));
      return true;
    });
  }

  /// 500pt消費→「マイスタイリスト」称号を付与。ポイント不足ならfalse。
  static Future<bool> redeemTitle() async {
    final uid = _uid;
    if (uid == null) return false;
    final docRef = _users.doc(uid);
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final points = (snap.data()?['points'] as int?) ?? 0;
      if (points < 500) return false;
      tx.set(docRef, {
        'points': points - 500,
        'title': 'マイスタイリスト',
      }, SetOptions(merge: true));
      return true;
    });
  }

  static Future<int> getBonusGenerations() async {
    final uid = _uid;
    if (uid == null) return 0;
    final snap = await _users.doc(uid).get();
    return (snap.data()?['bonusGenerations'] as int?) ?? 0;
  }

  /// 100pt消費→限定コーデパターンを解放。ポイント不足ならfalse。
  static Future<bool> redeemLimitedPatterns() async {
    final uid = _uid;
    if (uid == null) return false;
    final docRef = _users.doc(uid);
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final points = (snap.data()?['points'] as int?) ?? 0;
      final already = snap.data()?['limitedPatternsUnlocked'] == true;
      if (already) return true;
      if (points < 100) return false;
      tx.set(docRef, {
        'points': points - 100,
        'limitedPatternsUnlocked': true,
      }, SetOptions(merge: true));
      return true;
    });
  }

  static Future<bool> isLimitedPatternsUnlocked() async {
    final uid = _uid;
    if (uid == null) return false;
    final snap = await _users.doc(uid).get();
    return snap.data()?['limitedPatternsUnlocked'] == true;
  }
}
