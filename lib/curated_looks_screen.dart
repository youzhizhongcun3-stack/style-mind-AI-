import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'curated_looks_data.dart';
import 'main.dart';

/// 「あなたにおすすめのコーデ」フィード。
/// StyleMind AIが事前生成したコーデ画像を並べて見せる、閲覧・保存中心の画面。
/// カードの「自分の骨格・体型で見る」を押すと、そのコーデをベースにした
/// パーソナライズ生成をチャットにリクエストする文言を返してポップバックする
/// （実際の生成・課金判定は既存のチャット送信フローにそのまま乗る）。
class CuratedLooksScreen extends StatefulWidget {
  final UserProfile userProfile;
  const CuratedLooksScreen({super.key, required this.userProfile});

  @override
  State<CuratedLooksScreen> createState() => _CuratedLooksScreenState();
}

class _CuratedLooksScreenState extends State<CuratedLooksScreen> {
  Set<String> _savedIds = {};
  bool _loadingSaved = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadingSaved = false);
      return;
    }
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final saved = List<String>.from(snap.data()?['savedLookIds'] as List? ?? []);
    if (!mounted) return;
    setState(() {
      _savedIds = saved.toSet();
      _loadingSaved = false;
    });
  }

  Future<void> _toggleSave(String lookId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final isSaved = _savedIds.contains(lookId);
    setState(() {
      if (isSaved) {
        _savedIds.remove(lookId);
      } else {
        _savedIds.add(lookId);
      }
    });
    await docRef.set({
      'savedLookIds': isSaved ? FieldValue.arrayRemove([lookId]) : FieldValue.arrayUnion([lookId]),
    }, SetOptions(merge: true));
  }

  List<Map<String, String>> _buildShopLinks(String keyword) {
    final encoded = Uri.encodeComponent(keyword);
    final yahooUrl = Uri.encodeComponent('https://shopping.yahoo.co.jp/search?p=$keyword');
    final rakutenUrl = Uri.encodeComponent('https://search.rakuten.co.jp/search/mall/$keyword/');
    return [
      {'icon': '🛍️', 'name': 'Yahoo!ショッピング', 'url': 'https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3774833&pid=892651346&vc_url=$yahooUrl'},
      {'icon': '🏪', 'name': 'Rakuten Fashion', 'url': 'https://hb.afl.rakuten.co.jp/hgc/556d406f.aeda9c3d.556d4070.99ba5cc0/?pc=$rakutenUrl&link_type=hybrid_url'},
      {'icon': '📦', 'name': 'Amazon', 'url': 'https://www.amazon.co.jp/s?k=$encoded&i=fashion&tag=stylemind2026-22'},
    ];
  }

  void _showShopSheet(CuratedLook look) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(look.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...look.shopKeywords.map((kw) => ExpansionTile(
                  title: Text(kw, style: const TextStyle(fontSize: 14)),
                  children: _buildShopLinks(kw)
                      .map((s) => ListTile(
                            leading: Text(s['icon']!, style: const TextStyle(fontSize: 20)),
                            title: Text(s['name']!),
                            trailing: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF7FD6C2)),
                            onTap: () async {
                              final uri = Uri.parse(s['url']!);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                          ))
                      .toList(),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('あなたにおすすめのコーデ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: curatedLooks.length,
        itemBuilder: (context, i) {
          final look = curatedLooks[i];
          final isSaved = _savedIds.contains(look.id);
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 2 / 3,
                      child: Image.asset(look.imageAsset, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: _loadingSaved ? null : () => _toggleSave(look.id),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                          child: Icon(isSaved ? Icons.favorite : Icons.favorite_border, color: isSaved ? Colors.redAccent : Colors.grey[700], size: 22),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Wrap(
                        spacing: 6,
                        children: [
                          _tag(look.skeletonType),
                          _tag(look.styles),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(look.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      ...look.items.map((it) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(it, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
                          )),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(
                                  context,
                                  '「${look.title}」のような、${look.styles}系のコーデを、私の骨格タイプ・体型に合わせて提案して',
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7FD6C2),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text('自分の骨格・体型で見る', style: TextStyle(fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _showShopSheet(look),
                            child: const Text('購入', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
      );
}
