import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const StyleMindApp());
}

class StyleMindApp extends StatelessWidget {
  const StyleMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StyleMind AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7FD6C2)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const ChatScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final provider = GoogleAuthProvider();
      await FirebaseAuth.instance.signInWithPopup(provider);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ログインに失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF7FD6C2),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.checkroom, size: 80, color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'StyleMind AI',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'あなた専属のAIスタイリスト',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 60),
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : ElevatedButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login),
                      label: const Text('Googleでログイン'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF7FD6C2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String? imageUrl;
  ChatMessage({required this.text, required this.isUser, this.imageUrl});
}

class ClaudeService {
  static const String _proxyUrl = 'http://localhost:3000/chat';
  static const String _imageUrl = 'http://localhost:3000/generate-image';

  static Future<String> sendMessage(List<ChatMessage> messages) async {
    final List<Map<String, String>> history = messages.map((m) => {
      'role': m.isUser ? 'user' : 'assistant',
      'content': m.text,
    }).toList();

    try {
      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'messages': history}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['reply'] as String;
      } else {
        return 'エラーが発生しました。もう一度試してください。';
      }
    } catch (e) {
      return '接続エラー: サーバーが起動しているか確認してください。';
    }
  }

  static Future<String?> generateImage(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse(_imageUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['imageUrl'] as String;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  final List<ChatMessage> _messages = [
    ChatMessage(
      text: 'こんにちは！私はStyleMind AIです👗\nどんなコーデの相談でもOKですよ！\n\n例えば：\n・デートに着ていく服を教えて\n・就活スーツに合うシャツは？\n・今日の気分はカジュアルに！',
      isUser: false,
    ),
  ];

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveToFirestore(String text, bool isUser) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('messages')
        .add({
      'text': text,
      'isUser': isUser,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();
    await _saveToFirestore(text, true);

    final reply = await ClaudeService.sendMessage(
      _messages.where((m) => m.isUser || _messages.indexOf(m) > 0).toList(),
    );

    setState(() {
      _messages.add(ChatMessage(text: '', isUser: false));
      _isLoading = false;
    });

    final int lastIndex = _messages.length - 1;
    for (int i = 0; i < reply.length; i++) {
      await Future.delayed(const Duration(milliseconds: 8));
      setState(() {
        _messages[lastIndex] = ChatMessage(
          text: reply.substring(0, i + 1),
          isUser: false,
        );
      });
    }

    await _saveToFirestore(reply, false);

    // コーデ提案または画像リクエストの場合は自動で画像生成
    final userText = text.toLowerCase();
    final isImageRequest = userText.contains('画像') || userText.contains('写真') || userText.contains('見せ') || userText.contains('イメージ');
    final isCoordRequest = reply.contains('コーデ') || reply.contains('スタイル') || reply.contains('コーディネート') || reply.contains('ニット') || reply.contains('シャツ') || reply.contains('パンツ') || reply.contains('スカート');

    if (isCoordRequest || isImageRequest) {
      setState(() {
        _messages.add(ChatMessage(text: '👗 コーデ画像を生成中です...（約15秒かかります）', isUser: false));
        _isLoading = true;
      });
      _scrollToBottom();

      final imageUrl = await ClaudeService.generateImage(reply);
      setState(() {
        _isLoading = false;
        if (imageUrl != null) {
          _messages.last = ChatMessage(text: '👗 提案コーデのイメージ', isUser: false, imageUrl: imageUrl);
        } else {
          _messages.last = ChatMessage(text: '画像の生成に失敗しました。もう一度お試しください。', isUser: false);
        }
      });
      _scrollToBottom();
    }

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: Column(
          children: [
            const Text(
              'StyleMind AI',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              FirebaseAuth.instance.currentUser?.displayName ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'ログアウト',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF7FD6C2),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('考え中...', style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                  );
                }
                final msg = _messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('コピーしました！'),
                          duration: Duration(seconds: 1),
                          backgroundColor: Color(0xFF7FD6C2),
                        ),
                      );
                    },
                    child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isUser ? const Color(0xFF7FD6C2) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.text,
                          style: TextStyle(
                            color: msg.isUser ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                        if (msg.imageUrl != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Builder(builder: (context) {
                              if (msg.imageUrl!.startsWith('data:image')) {
                                final b64 = msg.imageUrl!.split(',').last;
                                final Uint8List bytes = base64Decode(b64);
                                return Image.memory(bytes, width: double.infinity, fit: BoxFit.cover);
                              }
                              return Image.network(msg.imageUrl!, width: double.infinity, fit: BoxFit.cover);
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'コーデの相談をしてみよう...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    enabled: !_isLoading,
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: _isLoading
                      ? Colors.grey
                      : const Color(0xFF7FD6C2),
                  onPressed: _isLoading ? null : _sendMessage,
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
