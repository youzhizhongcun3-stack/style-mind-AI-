import 'package:flutter/material.dart';
import 'closet_screen.dart';
import 'saved_screen.dart';

/// 「クローゼット」タブ：手持ち服の管理と、保存したコーデをまとめたハブ画面。
class ClosetHubScreen extends StatelessWidget {
  const ClosetHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('クローゼット', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HubCard(
            icon: Icons.checkroom,
            title: 'マイクローゼット',
            subtitle: '手持ちの服を登録して、コーデ提案に活かそう',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ClosetScreen()));
            },
          ),
          _HubCard(
            icon: Icons.bookmark,
            title: '保存したコーデ',
            subtitle: 'チャットで気に入ったコーデを見返せます',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedScreen()));
            },
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: const Color(0xFF7FD6C2).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: const Color(0xFF3C9A85)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
