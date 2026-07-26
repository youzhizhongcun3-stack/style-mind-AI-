import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';

/// 「あなたにおすすめのコーデ」フィード。
/// StyleMind AIが事前生成したコーデ画像(Firestore + Firebase Storageで配信、
/// 週次のトレンド調査タスクと連動して随時追加される)を並べる、閲覧・保存
/// 中心の画面。骨格タイプ・好みでの並び替え、いいね数に基づく人気バッジ、
/// Instagramへのシェア機能を持つ。
/// カードの「自分の骨格・体型で見る」を押すと、そのコーデをベースにした
/// パーソナライズ生成をチャットにリクエストする文言を返してポップバックする
/// （実際の生成・課金判定は既存のチャット送信フローにそのまま乗る）。
class CuratedLook {
  final String id;
  final String imageUrl;
  final String title;
  final String gender;
  final String skeletonType;
  final String styles;
  final List<String> items;
  final List<String> shopKeywords;
  final int likeCount;

  CuratedLook({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.gender,
    required this.skeletonType,
    required this.styles,
    required this.items,
    required this.shopKeywords,
    required this.likeCount,
  });

  factory CuratedLook.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return CuratedLook(
      id: doc.id,
      imageUrl: d['imageUrl'] as String? ?? '',
      title: d['title'] as String? ?? '',
      gender: d['gender'] as String? ?? '',
      skeletonType: d['skeletonType'] as String? ?? '',
      styles: d['styles'] as String? ?? '',
      items: List<String>.from(d['items'] as List? ?? []),
      shopKeywords: List<String>.from(d['shopKeywords'] as List? ?? []),
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CuratedLooksScreen extends StatefulWidget {
  final UserProfile userProfile;
  const CuratedLooksScreen({super.key, required this.userProfile});

  @override
  State<CuratedLooksScreen> createState() => _CuratedLooksScreenState();
}

class _CuratedLooksScreenState extends State<CuratedLooksScreen> {
  static final _looksCollection = FirebaseFirestore.instance.collection('curatedLooks');

  List<CuratedLook> _looks = [];
  Set<String> _popularIds = {};
  Set<String> _savedIds = {};
  bool _loading = true;
  String? _error;
  final Map<String, GlobalKey> _cardKeys = {};
  String? _sharingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _looksCollection.orderBy('createdAt', descending: true).get();
      final looks = snap.docs.map(CuratedLook.fromDoc).toList();

      // 「今週人気」：いいね数上位3件（1件もいいねが無ければバッジは出さない）
      final likedSorted = looks.where((l) => l.likeCount > 0).toList()
        ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
      final popularIds = likedSorted.take(3).map((l) => l.id).toSet();

      // 骨格タイプ・好みが近いものを上位に表示
      looks.sort((a, b) => _matchScore(b).compareTo(_matchScore(a)));

      final uid = FirebaseAuth.instance.currentUser?.uid;
      Set<String> saved = {};
      if (uid != null) {
        final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        saved = Set<String>.from(userSnap.data()?['savedLookIds'] as List? ?? []);
      }

      if (!mounted) return;
      setState(() {
        _looks = looks;
        _popularIds = popularIds;
        _savedIds = saved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '読み込みに失敗しました。もう一度お試しください';
        _loading = false;
      });
    }
  }

  int _matchScore(CuratedLook look) {
    int score = 0;
    if (widget.userProfile.skeletonType.isNotEmpty && look.skeletonType == widget.userProfile.skeletonType) score += 3;
    if (widget.userProfile.gender.isNotEmpty && look.gender == widget.userProfile.gender) score += 1;
    for (final s in widget.userProfile.styles) {
      if (s.isEmpty) continue;
      if (look.styles.contains(s) || s.contains(look.styles)) score += 2;
    }
    return score;
  }

  Future<void> _toggleSave(CuratedLook look) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final lookDocRef = _looksCollection.doc(look.id);
    final isSaved = _savedIds.contains(look.id);

    setState(() {
      if (isSaved) {
        _savedIds.remove(look.id);
        _looks = _looks.map((l) => l.id == look.id ? _withLikeDelta(l, -1) : l).toList();
      } else {
        _savedIds.add(look.id);
        _looks = _looks.map((l) => l.id == look.id ? _withLikeDelta(l, 1) : l).toList();
      }
    });

    await userDocRef.set({
      'savedLookIds': isSaved ? FieldValue.arrayRemove([look.id]) : FieldValue.arrayUnion([look.id]),
    }, SetOptions(merge: true));
    await lookDocRef.set({
      'likeCount': FieldValue.increment(isSaved ? -1 : 1),
    }, SetOptions(merge: true));
  }

  CuratedLook _withLikeDelta(CuratedLook l, int delta) => CuratedLook(
        id: l.id,
        imageUrl: l.imageUrl,
        title: l.title,
        gender: l.gender,
        skeletonType: l.skeletonType,
        styles: l.styles,
        items: l.items,
        shopKeywords: l.shopKeywords,
        likeCount: l.likeCount + delta,
      );

  List<Map<String, String>> _buildShopLinks(String keyword) {
    final encoded = Uri.encodeComponent(keyword);
    final yahooUrl = Uri.encodeComponent('https://shopping.yahoo.co.jp/search?p=$keyword');
    final rakutenUrl = Uri.encodeComponent('https://search.rakuten.co.jp/search/mall/$keyword/');
    return [
      {'icon': '🛍️', 'name': 'Yahoo!ショッピング', 'url': 'https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3774833&pid=892651346&vc_url=$yahooUrl'},
      {'icon': '🏪', 'name': 'Rakuten Fashion', 'url': 'https://hb.afl.rakuten.co.jp/hgc/556d406f.aeda9c3d.556d4070.99ba5cc0/?pc=$rakutenUrl&link_type=hybrid_url'},
      {'icon': '📦', 'name': 'Amazon', 'url': 'https://www.amazon.co.jp/s?k=$encoded&i=fashion&tag=stylemind2026-22'},
      {'icon': '♻️', 'name': 'セカンドストリート', 'url': 'https://px.a8.net/svt/ejp?a8mat=4B7SH1+4FK6WI+4J34+HWXLD'},
      {'icon': '📸', 'name': 'WEAR（コーデ参考）', 'url': 'https://wear.jp/search/?q=$encoded'},
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

  Future<void> _shareLook(CuratedLook look) async {
    setState(() => _sharingId = look.id);
    try {
      final key = _cardKeys[look.id];
      final boundary = key?.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/curated_look_${look.id}.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'StyleMind AIが提案する「${look.title}」👗✨\nAIコーデ診断、あなたもやってみて！\nhttps://stylemind-ai-d14ec.web.app',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('シェアに失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _sharingId = null);
    }
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _looks.length,
                  itemBuilder: (context, i) {
                    final look = _looks[i];
                    final isSaved = _savedIds.contains(look.id);
                    final isPopular = _popularIds.contains(look.id);
                    _cardKeys.putIfAbsent(look.id, () => GlobalKey());

                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: RepaintBoundary(
                        key: _cardKeys[look.id],
                        child: Container(
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: Image.network(
                                      look.imageUrl,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, progress) =>
                                          progress == null ? child : const Center(child: CircularProgressIndicator()),
                                      errorBuilder: (context, error, stack) => Container(
                                        color: Colors.grey.shade100,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: GestureDetector(
                                      onTap: () => _toggleSave(look),
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
                                        if (isPopular) _tag('🔥 今週人気', highlight: true),
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
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: _sharingId == look.id ? null : () => _shareLook(look),
                                          child: _sharingId == look.id
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.ios_share, size: 16),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _tag(String text, {bool highlight = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: highlight ? const Color(0xFFFF6B4A) : Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
      );
}
