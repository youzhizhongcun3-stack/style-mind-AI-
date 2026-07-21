import 'dart:math';

/// Web以外（未リリースのモバイル向けスタブ）。
/// 永続化はせず毎回新しいIDを返す。モバイル版リリース時に
/// 端末固有IDを使う実装へ差し替えること。
String getOrCreatePersistedDeviceId() {
  final rnd = Random();
  return List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
}
