import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  String _filter = 'すべて';
  static const _filterOptions = ['すべて', '画像あり', 'テキストのみ'];

  // タグはユーザーが自由に付けられる想定だが、最初の一歩を軽くするため
  // よく使われそうな候補をあらかじめ用意しておく（無ければ0から入力する必要があり面倒なため）
  static const _suggestedTags = ['お気に入り', 'オフィス', 'デート', 'カジュアル', '春夏', '秋冬'];

  String? _selectedTag;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _ref => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('saved_coordinates');

  Future<void> _delete(String id) async {
    await _ref.doc(id).delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('削除しました'), backgroundColor: Colors.grey),
      );
    }
  }

  Future<void> _addTag(String docId, String tag) async {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    await _ref.doc(docId).update({
      'tags': FieldValue.arrayUnion([trimmed]),
    });
  }

  Future<void> _removeTag(String docId, String tag) async {
    await _ref.doc(docId).update({
      'tags': FieldValue.arrayRemove([tag]),
    });
  }

  void _showAddTagDialog(BuildContext context, String docId, List<String> currentTags) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('タグを追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestedTags.where((t) => !currentTags.contains(t)).map((t) {
                return ActionChip(
                  label: Text(t, style: const TextStyle(fontSize: 13)),
                  onPressed: () {
                    _addTag(docId, t);
                    Navigator.pop(dialogContext);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '自由入力（例：友達の結婚式）',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                _addTag(docId, v);
                Navigator.pop(dialogContext);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              _addTag(docId, controller.text);
              Navigator.pop(dialogContext);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> data, String docId) {
    final text = data['text'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String?;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              if (imageUrl != null) ...[
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  if (imageUrl.startsWith('data:image')) {
                    final bytes = base64Decode(imageUrl.split(',').last);
                    return Image.memory(Uint8List.fromList(bytes), width: double.infinity, fit: BoxFit.cover);
                  }
                  return Image.network(imageUrl, width: double.infinity, fit: BoxFit.cover);
                }),
              ],
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('👗 コーデ詳細', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 12),
                    Text(text.replaceAll('**', ''), style: const TextStyle(fontSize: 14, height: 1.7)),
                    const SizedBox(height: 20),
                    // タグはStreamBuilder経由で最新状態を反映（削除ボタンを押した直後も
                    // このシートを開いたままタグ一覧が更新されるようにするため）
                    StreamBuilder<DocumentSnapshot>(
                      stream: _ref.doc(docId).snapshots(),
                      builder: (context, snap) {
                        final liveData = snap.data?.data() as Map<String, dynamic>?;
                        final tags = (liveData?['tags'] as List?)?.cast<String>() ?? const <String>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('タグ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ...tags.map((t) => Chip(
                                      label: Text(t, style: const TextStyle(fontSize: 12)),
                                      backgroundColor: const Color(0xFFE8F8F5),
                                      deleteIcon: const Icon(Icons.close, size: 14),
                                      onDeleted: () => _removeTag(docId, t),
                                    )),
                                ActionChip(
                                  avatar: const Icon(Icons.add, size: 16, color: Color(0xFF5BB8A8)),
                                  label: const Text('タグを追加', style: TextStyle(fontSize: 12, color: Color(0xFF5BB8A8))),
                                  onPressed: () => _showAddTagDialog(context, docId, tags),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () { Navigator.pop(context); _delete(docId); },
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('このコーデを削除', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('保存したコーデ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // フィルタータブ
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _filterOptions.map((f) {
                final selected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF7FD6C2) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? const Color(0xFF7FD6C2) : Colors.grey.shade300),
                      ),
                      child: Text(f, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black87, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _ref.orderBy('savedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF7FD6C2)));
                var docs = snapshot.data!.docs;

                // 実際に使われているタグだけを候補として出す（一度も使われていない
                // 提案タグまで並べると選択肢が多すぎて逆に使いにくくなるため）
                final usedTags = <String>{};
                for (final d in docs) {
                  final tags = ((d.data() as Map)['tags'] as List?)?.cast<String>() ?? const <String>[];
                  usedTags.addAll(tags);
                }
                if (_selectedTag != null && !usedTags.contains(_selectedTag)) {
                  _selectedTag = null;
                }

                // フィルタリング
                if (_filter == '画像あり') {
                  docs = docs.where((d) => (d.data() as Map)['imageUrl'] != null).toList();
                } else if (_filter == 'テキストのみ') {
                  docs = docs.where((d) => (d.data() as Map)['imageUrl'] == null).toList();
                }
                if (_selectedTag != null) {
                  docs = docs.where((d) {
                    final tags = ((d.data() as Map)['tags'] as List?)?.cast<String>() ?? const <String>[];
                    return tags.contains(_selectedTag);
                  }).toList();
                }

                final tagFilterRow = usedTags.isEmpty
                    ? null
                    : Container(
                        color: Colors.white,
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                        child: SizedBox(
                          height: 32,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: usedTags.map((t) {
                              final selected = _selectedTag == t;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedTag = selected ? null : t),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: selected ? const Color(0xFF5BB8A8) : const Color(0xFFE8F8F5),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text('#$t', style: TextStyle(fontSize: 11, color: selected ? Colors.white : const Color(0xFF5BB8A8), fontWeight: FontWeight.w500)),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );

                if (docs.isEmpty) {
                  if (tagFilterRow != null) {
                    return Column(
                      children: [
                        tagFilterRow,
                        Expanded(
                          child: Center(
                            child: Text('「$_selectedTag」のコーデはありません', style: const TextStyle(color: Colors.grey)),
                          ),
                        ),
                      ],
                    );
                  }
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bookmark_border, size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('${_filter == 'すべて' ? '保存した' : '$_filterの'}コーデはありません', style: const TextStyle(color: Colors.grey)),
                        if (_filter == 'すべて') ...[
                          const SizedBox(height: 4),
                          const Text('チャットの返答にある「保存」ボタンで追加できます', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ],
                    ),
                  );
                }

                // 画像ありはグリッド、テキストのみはリスト
                final withImage = docs.where((d) => (d.data() as Map)['imageUrl'] != null).toList();
                final textOnly = docs.where((d) => (d.data() as Map)['imageUrl'] == null).toList();
                final showMixed = _filter == 'すべて';

                final list = ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if ((showMixed || _filter == '画像あり') && withImage.isNotEmpty) ...[
                      if (showMixed) const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4),
                        child: Text('📸 画像付きコーデ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5BB8A8))),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.75,
                        ),
                        itemCount: withImage.length,
                        itemBuilder: (context, i) {
                          final doc = withImage[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final imageUrl = data['imageUrl'] as String;
                          return GestureDetector(
                            onTap: () => _showDetail(context, data, doc.id),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Builder(builder: (_) {
                                    if (imageUrl.startsWith('data:image')) {
                                      final bytes = base64Decode(imageUrl.split(',').last);
                                      return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover);
                                    }
                                    return Image.network(imageUrl, fit: BoxFit.cover);
                                  }),
                                  Positioned(
                                    bottom: 0, left: 0, right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [Colors.black.withAlpha(180), Colors.transparent],
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('タップで詳細', style: TextStyle(color: Colors.white, fontSize: 10)),
                                          GestureDetector(
                                            onTap: () => _delete(doc.id),
                                            child: const Icon(Icons.delete_outline, color: Colors.white70, size: 16),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    if ((showMixed || _filter == 'テキストのみ') && textOnly.isNotEmpty) ...[
                      if (showMixed) const Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 8, left: 4),
                        child: Text('📝 テキストコーデ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5BB8A8))),
                      ),
                      ...textOnly.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final text = data['text'] as String? ?? '';
                        final cardTags = (data['tags'] as List?)?.cast<String>() ?? const <String>[];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            onTap: () => _showDetail(context, data, doc.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(text.replaceAll('**', ''), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.6)),
                                  if (cardTags.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      children: cardTags.map((t) => Text('#$t', style: const TextStyle(fontSize: 11, color: Color(0xFF5BB8A8)))).toList(),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _delete(doc.id),
                                        icon: const Icon(Icons.delete_outline, size: 14, color: Colors.grey),
                                        label: const Text('削除', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                        style: TextButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                );

                if (tagFilterRow == null) return list;
                return Column(
                  children: [
                    tagFilterRow,
                    Expanded(child: list),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
