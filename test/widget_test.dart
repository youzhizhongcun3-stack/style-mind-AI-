// Unit tests for pure logic in lib/main.dart.
//
// Note: a full widget test of StyleMindApp/AuthGate would require mocking
// Firebase (main() calls Firebase.initializeApp() before runApp, and
// AuthGate reads FirebaseAuth.instance directly), which isn't set up in
// this project yet. Until that's added, we test the pure, Firebase-free
// logic instead so `flutter test` actually compiles and passes.

import 'package:flutter_test/flutter_test.dart';
import 'package:stylemind_ai/main.dart';

void main() {
  group('UserProfile', () {
    test('isComplete is false when gender and styles are empty', () {
      final profile = UserProfile();
      expect(profile.isComplete, isFalse);
    });

    test('isComplete is true once gender and at least one style are set', () {
      final profile = UserProfile(gender: 'メンズ', styles: ['ストリート']);
      expect(profile.isComplete, isTrue);
    });

    test('toMap joins list fields with the ・ separator', () {
      final profile = UserProfile(
        gender: 'メンズ',
        age: '20代',
        styles: ['ストリート', 'モード'],
        brands: ['ユニクロ'],
        budget: '1万円以内',
        height: '166〜170cm',
        bodyType: '細身',
        ngItems: ['露出多め'],
      );

      final map = profile.toMap();

      expect(map['gender'], 'メンズ');
      expect(map['styles'], 'ストリート・モード');
      expect(map['brands'], 'ユニクロ');
      expect(map['ngItems'], '露出多め');
    });
  });
}
