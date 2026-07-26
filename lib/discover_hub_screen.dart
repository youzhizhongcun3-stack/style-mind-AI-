import 'package:flutter/material.dart';
import 'curated_looks_screen.dart';
import 'main.dart';
import 'points_screen.dart';
import 'recommended_items_screen.dart';

/// 「発見」タブ：おすすめコーデ・おすすめ商品・招待ポイントなど、
/// 「探す・見つける」系の機能をひとまとめにしたハブ画面。
/// 個別のアプリバーアイコンが増え続けて分かりにくくなっていた問題への対応。
class DiscoverHubScreen extends StatelessWidget {
  final UserProfile userProfile;
  final void Function(String prompt) onSendPrompt;
  final VoidCallback onReturnedFromPoints;

  const DiscoverHubScreen({
    super.key,
    required this.userProfile,
    required this.onSendPrompt,
    required this.onReturnedFromPoints,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('発見', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HubCard(
            icon: Icons.auto_awesome,
            title: 'あなたにおすすめのコーデ',
            subtitle: 'AIが提案するコーデ画像を見て、自分の骨格・体型で生成しよう',
            onTap: () async {
              final prompt = await Navigator.push<String>(context, MaterialPageRoute(
                builder: (_) => CuratedLooksScreen(userProfile: userProfile),
              ));
              if (prompt != null) onSendPrompt(prompt);
            },
          ),
          _HubCard(
            icon: Icons.style_outlined,
            title: 'あなたへのおすすめ商品',
            subtitle: '骨格タイプ・好みに合わせたブランド・商品一覧',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => RecommendedItemsScreen(userProfile: userProfile),
              ));
            },
          ),
          _HubCard(
            icon: Icons.card_giftcard,
            title: '招待・ポイント',
            subtitle: '友達を招待してポイントを貯めよう',
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => PointsScreen(userProfile: userProfile),
              ));
              onReturnedFromPoints();
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
