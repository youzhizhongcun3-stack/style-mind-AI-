import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ユーザーが満足した瞬間（コーデを保存した時）に、さりげなくストアレビューを
/// お願いする仕組み。表示しすぎるとうっとうしいので、①一定回数保存した後
/// ②前回リクエストから一定期間空いている、の両方を満たした時だけ表示する。
class ReviewService {
  static const _kSaveCountKey = 'review_save_count';
  static const _kLastRequestKey = 'review_last_request_epoch_ms';
  static const int _requiredSaveCount = 3; // 3回保存したら依頼を検討
  static const int _minDaysBetweenRequests = 60; // 一度依頼したら60日は再度依頼しない

  /// コーデを保存する等、ポジティブな体験の直後に呼ぶ。
  /// 条件を満たしていれば、ストアのネイティブレビューダイアログを表示する。
  static Future<void> maybeRequestReview() async {
    final prefs = await SharedPreferences.getInstance();
    final saveCount = (prefs.getInt(_kSaveCountKey) ?? 0) + 1;
    await prefs.setInt(_kSaveCountKey, saveCount);

    if (saveCount < _requiredSaveCount) return;

    final lastRequest = prefs.getInt(_kLastRequestKey);
    if (lastRequest != null) {
      final daysSince = (DateTime.now().millisecondsSinceEpoch - lastRequest) / (1000 * 60 * 60 * 24);
      if (daysSince < _minDaysBetweenRequests) return;
    }

    final inAppReview = InAppReview.instance;
    if (!await inAppReview.isAvailable()) return;

    await inAppReview.requestReview();
    await prefs.setInt(_kLastRequestKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_kSaveCountKey, 0);
  }
}
