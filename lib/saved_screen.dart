import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _ref => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('saved_coordinates');

  Future<void> _delete(String id, BuildContext context) async {
    await _ref.doc(id).delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('削除しました'), backgroundColor: Colors.grey),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('保存したコーデ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ref.orderBy('savedAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_border, size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('保存したコーデはありません', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 4),
                  Text('チャットの返答にある「保存」ボタンで追加できます', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final text = data['text'] as String? ?? '';
              final imageUrl = data['imageUrl'] as String?;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null) ...[
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Builder(builder: (_) {
                          if (imageUrl.startsWith('data:image')) {
                            final b64 = imageUrl.split(',').last;
                            final Uint8List bytes = base64Decode(b64);
                            return Image.memory(bytes, width: double.infinity, height: 300, fit: BoxFit.cover);
                          }
                          return Image.network(imageUrl, width: double.infinity, height: 300, fit: BoxFit.cover);
                        }),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(text, style: const TextStyle(fontSize: 14)),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _delete(doc.id, context),
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                        label: const Text('削除', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
