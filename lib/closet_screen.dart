import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClothingItem {
  final String id;
  final String category;
  final String description;
  final String color;
  final String brand;
  final DateTime createdAt;

  ClothingItem({
    required this.id,
    required this.category,
    required this.description,
    required this.color,
    required this.brand,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'category': category,
    'description': description,
    'color': color,
    'brand': brand,
    'createdAt': FieldValue.serverTimestamp(),
  };

  factory ClothingItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ClothingItem(
      id: doc.id,
      category: d['category'] ?? '',
      description: d['description'] ?? '',
      color: d['color'] ?? '',
      brand: d['brand'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  String get summary => '$color $brand $description';
}

class ClosetScreen extends StatefulWidget {
  const ClosetScreen({super.key});

  @override
  State<ClosetScreen> createState() => _ClosetScreenState();
}

class _ClosetScreenState extends State<ClosetScreen> {
  final List<String> _categories = ['トップス', 'ボトムス', 'アウター', 'シューズ', 'アクセサリー', 'バッグ', 'その他'];
  String _selectedCategory = 'トップス';
  final _descController = TextEditingController();
  final _colorController = TextEditingController();
  final _brandController = TextEditingController();
  bool _saving = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _ref => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('closet');

  Future<void> _addItem() async {
    if (_descController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await _ref.add(ClothingItem(
      id: '',
      category: _selectedCategory,
      description: _descController.text.trim(),
      color: _colorController.text.trim(),
      brand: _brandController.text.trim(),
      createdAt: DateTime.now(),
    ).toMap());
    _descController.clear();
    _colorController.clear();
    _brandController.clear();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クローゼットに追加しました！'), backgroundColor: Color(0xFF7FD6C2)),
      );
    }
  }

  Future<void> _deleteItem(String id) async {
    await _ref.doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('マイクローゼット', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 追加フォーム
          Container(
            color: Colors.grey[50],
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('服を追加する', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7FD6C2))),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c, style: const TextStyle(fontSize: 12)),
                        selected: _selectedCategory == c,
                        onSelected: (_) => setState(() => _selectedCategory = c),
                        selectedColor: const Color(0xFF7FD6C2),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _colorController,
                        decoration: _inputDec('色（例：ネイビー）'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _brandController,
                        decoration: _inputDec('ブランド（例：ユニクロ）'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _descController,
                        decoration: _inputDec('アイテム名（例：クルーネックニット）'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _addItem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7FD6C2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.add, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // クローゼット一覧
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _ref.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final items = snapshot.data!.docs.map((d) => ClothingItem.fromDoc(d)).toList();
                if (items.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.checkroom, size: 60, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('まだ服が登録されていません', style: TextStyle(color: Colors.grey)),
                        SizedBox(height: 4),
                        Text('上のフォームから追加してください', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  );
                }
                // カテゴリ別にグループ化
                final grouped = <String, List<ClothingItem>>{};
                for (final item in items) {
                  grouped.putIfAbsent(item.category, () => []).add(item);
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: grouped.entries.map((entry) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7FD6C2), fontSize: 14)),
                      ),
                      ...entry.value.map((item) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.checkroom, color: Color(0xFF7FD6C2)),
                          title: Text(item.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${item.color}　${item.brand}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.grey),
                            onPressed: () => _deleteItem(item.id),
                          ),
                        ),
                      )),
                    ],
                  )).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    isDense: true,
  );
}

// クローゼットの服一覧をテキストで取得（Claude AIに渡す用）
Future<String> getClosetSummary() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return '';
  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('closet')
      .get();
  if (snapshot.docs.isEmpty) return '';
  final items = snapshot.docs.map((d) => ClothingItem.fromDoc(d));
  final grouped = <String, List<String>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.category, () => []).add(item.summary);
  }
  return grouped.entries.map((e) => '${e.key}：${e.value.join('、')}').join('\n');
}
