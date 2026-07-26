import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart';

/// 「マイページ」タブ：スタイル設定、ログアウト、アカウント削除など。
/// アカウント削除のような取り消せない操作は、誤操作を防ぐためあえて
/// アプリバーの目立つ場所ではなく、このタブの奥に置いている。
class MyPageScreen extends StatelessWidget {
  final UserProfile userProfile;
  final Future<void> Function(BuildContext context) onConfirmDeleteAccount;

  const MyPageScreen({
    super.key,
    required this.userProfile,
    required this.onConfirmDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('マイページ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.tune, color: Color(0xFF3C9A85)),
            title: const Text('スタイル設定'),
            subtitle: const Text('骨格タイプ・好みのスタイル・予算などの変更'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ProfileScreen(onComplete: (_) => Navigator.pop(context)),
              ));
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.grey),
            title: const Text('ログアウト'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('アカウントを削除', style: TextStyle(color: Colors.red)),
            subtitle: const Text('すべてのデータが完全に削除されます'),
            onTap: () => onConfirmDeleteAccount(context),
          ),
        ],
      ),
    );
  }
}
