import 'dart:html' as html;
import 'dart:math';

const _storageKey = 'stylemind_device_id';

/// ブラウザのlocalStorageに永続化した簡易デバイスID。
/// 招待の自己不正（同一ブラウザでの多重アカウント作成）を
/// 検知するための簡易チェック用途（完全な不正対策ではない）。
String getOrCreatePersistedDeviceId() {
  final existing = html.window.localStorage[_storageKey];
  if (existing != null && existing.isNotEmpty) return existing;
  final rnd = Random();
  final id = List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  html.window.localStorage[_storageKey] = id;
  return id;
}
