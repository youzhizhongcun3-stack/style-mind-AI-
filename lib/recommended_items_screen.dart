import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';

class RecommendedItemsScreen extends StatefulWidget {
  final UserProfile userProfile;
  const RecommendedItemsScreen({super.key, required this.userProfile});

  @override
  State<RecommendedItemsScreen> createState() => _RecommendedItemsScreenState();
}

class _RecommendedItemsScreenState extends State<RecommendedItemsScreen> {
  static const String _url = 'https://stylemind-proxy-production.up.railway.app/recommended-items';

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'skeletonType': widget.userProfile.skeletonType,
          'styles': widget.userProfile.styles.join('・'),
        }),
      ).timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(data['items'] as List);
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

  void _showShops(Map<String, dynamic> item) {
    final shops = List<Map<String, dynamic>>.from(item['shops'] as List);
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
            Text('${item['brand']} ${item['item']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ...shops.map((s) => ListTile(
                  leading: Text(s['icon'] as String, style: const TextStyle(fontSize: 20)),
                  title: Text(s['name'] as String),
                  trailing: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF7FD6C2)),
                  onTap: () async {
                    final uri = Uri.parse(s['url'] as String);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
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
        title: const Text('あなたへのおすすめ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: const Color(0xFF7FD6C2).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                            alignment: Alignment.center,
                            child: const Icon(Icons.checkroom, color: Color(0xFF3C9A85)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item['category']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                Text('${item['brand']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3C9A85))),
                                Text('${item['item']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                Text('${item['price']}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _showShops(item),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7FD6C2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: const Text('購入', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
