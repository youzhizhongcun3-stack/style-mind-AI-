import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'closet_screen.dart';
import 'saved_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Web版でもログイン状態を永続化
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
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
          return const ProfileGate();
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

class UserProfile {
  String gender;
  String age;
  List<String> styles;
  List<String> brands;
  String budget;

  UserProfile({
    this.gender = '',
    this.age = '',
    this.styles = const [],
    this.brands = const [],
    this.budget = '',
  });

  Map<String, String> toMap() => {
    'gender': gender,
    'age': age,
    'styles': styles.join('・'),
    'brands': brands.join('・'),
    'budget': budget,
  };

  bool get isComplete => gender.isNotEmpty && styles.isNotEmpty;
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  UserProfile? _profile;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && doc.data()?['profile'] != null) {
      final p = doc.data()!['profile'] as Map<String, dynamic>;
      setState(() {
        _profile = UserProfile(
          gender: p['gender'] ?? '',
          age: p['age'] ?? '',
          styles: List<String>.from(p['styles'] ?? []),
          brands: List<String>.from(p['brands'] ?? []),
          budget: p['budget'] ?? '',
        );
        _checked = true;
      });
    } else {
      setState(() => _checked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null || !_profile!.isComplete) {
      return ProfileScreen(onComplete: (profile) {
        setState(() => _profile = profile);
      });
    }
    return ChatScreen(userProfile: _profile!);
  }
}

class ProfileScreen extends StatefulWidget {
  final Function(UserProfile) onComplete;
  const ProfileScreen({super.key, required this.onComplete});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _gender = '';
  String _age = '';
  final List<String> _selectedStyles = [];
  final List<String> _selectedBrands = [];
  String _budget = '';
  bool _saving = false;

  final List<String> _styleOptions = ['ミニマル/シンプル', 'ストリート', 'Y2K/レトロ', 'ゴープコア/アウトドア', 'フェミニン/ガーリー', 'クワイエットラグジュアリー', '韓国系/オルチャン', 'モード/アバンギャルド', 'カジュアル/アメカジ', 'サブカル/古着'];
  final List<String> _brandOptions = ['ユニクロ', 'GU', 'ZARA', 'H&M', 'ビームス', 'ナノユニバース', 'アーバンリサーチ', 'シュプリーム', 'ナイキ', 'ニューバランス', 'マルニ', 'アクネ', 'マルジェラ', 'その他'];
  final List<String> _budgetOptions = ['〜5,000円', '5,000〜15,000円', '15,000〜30,000円', '30,000円〜'];

  Future<void> _save() async {
    if (_gender.isEmpty || _selectedStyles.isEmpty) return;
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'profile': {
          'gender': _gender,
          'age': _age,
          'styles': _selectedStyles,
          'brands': _selectedBrands,
          'budget': _budget,
        }
      }, SetOptions(merge: true));
    }
    final profile = UserProfile(gender: _gender, age: _age, styles: _selectedStyles, brands: _selectedBrands, budget: _budget);
    widget.onComplete(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('スタイル診断', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('あなたのファッションを教えてください✨', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _sectionTitle('性別'),
            Wrap(spacing: 8, children: ['メンズ', 'レディース', 'ユニセックス'].map((g) => ChoiceChip(
              label: Text(g), selected: _gender == g,
              onSelected: (_) => setState(() => _gender = g),
              selectedColor: const Color(0xFF7FD6C2),
            )).toList()),
            const SizedBox(height: 16),
            _sectionTitle('年齢層'),
            Wrap(spacing: 8, children: ['10代', '20代前半', '20代後半', '30代', '40代以上'].map((a) => ChoiceChip(
              label: Text(a), selected: _age == a,
              onSelected: (_) => setState(() => _age = a),
              selectedColor: const Color(0xFF7FD6C2),
            )).toList()),
            const SizedBox(height: 16),
            _sectionTitle('好きなスタイル（複数選択OK）'),
            Wrap(spacing: 8, runSpacing: 4, children: _styleOptions.map((s) => FilterChip(
              label: Text(s, style: const TextStyle(fontSize: 12)),
              selected: _selectedStyles.contains(s),
              onSelected: (v) => setState(() => v ? _selectedStyles.add(s) : _selectedStyles.remove(s)),
              selectedColor: const Color(0xFF7FD6C2),
            )).toList()),
            const SizedBox(height: 16),
            _sectionTitle('好きなブランド（複数選択OK）'),
            Wrap(spacing: 8, runSpacing: 4, children: _brandOptions.map((b) => FilterChip(
              label: Text(b, style: const TextStyle(fontSize: 12)),
              selected: _selectedBrands.contains(b),
              onSelected: (v) => setState(() => v ? _selectedBrands.add(b) : _selectedBrands.remove(b)),
              selectedColor: const Color(0xFF7FD6C2),
            )).toList()),
            const SizedBox(height: 16),
            _sectionTitle('1コーデの予算'),
            Wrap(spacing: 8, children: _budgetOptions.map((b) => ChoiceChip(
              label: Text(b), selected: _budget == b,
              onSelected: (_) => setState(() => _budget = b),
              selectedColor: const Color(0xFF7FD6C2),
            )).toList()),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_gender.isEmpty || _selectedStyles.isEmpty || _saving) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7FD6C2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('スタイル診断完了！', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7FD6C2))),
  );
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
  static const String _weatherUrl = 'http://localhost:3000/weather';

  static Future<Map<String, dynamic>?> getWeather(double lat, double lon) async {
    try {
      final response = await http.post(
        Uri.parse(_weatherUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'lat': lat, 'lon': lon}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Future<String> sendMessage(List<ChatMessage> messages, {UserProfile? userProfile, String? closetSummary}) async {
    final List<Map<String, String>> history = messages.map((m) => {
      'role': m.isUser ? 'user' : 'assistant',
      'content': m.text,
    }).toList();

    try {
      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': history,
          'userProfile': userProfile?.toMap(),
          'closetSummary': closetSummary ?? '',
        }),
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

  static Future<String?> generateImage(String prompt, {UserProfile? userProfile}) async {
    try {
      final response = await http.post(
        Uri.parse(_imageUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt, 'userProfile': userProfile?.toMap()}),
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
  final UserProfile userProfile;
  const ChatScreen({super.key, required this.userProfile});

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

  Future<void> _saveCoordinate(String text, String? imageUrl) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('saved_coordinates')
        .add({
      'text': text,
      'imageUrl': imageUrl,
      'savedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('コーデを保存しました！'),
          backgroundColor: Color(0xFF7FD6C2),
        ),
      );
    }
  }

  Future<void> _shareImage(String imageUrl) async {
    try {
      final Uint8List bytes;
      if (imageUrl.startsWith('data:image')) {
        bytes = base64Decode(imageUrl.split(',').last);
      } else {
        final response = await http.get(Uri.parse(imageUrl));
        bytes = response.bodyBytes;
      }

      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画像を長押しして保存してください'), backgroundColor: Color(0xFF7FD6C2)),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/stylemind_coord.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'StyleMind AIが提案したコーデです👗',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('共有に失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _sendWeatherCoordinate() async {
    try {
      // Web版：東京のデフォルト座標を使用（スマホ版では実際の位置情報を使用）
      double lat = 35.6895;
      double lon = 139.6917;

      if (!kIsWeb) {
        // スマホ版のみGeolocatorを使用
        // ignore: avoid_dynamic_calls
        final pos = await _getPosition();
        if (pos != null) {
          lat = pos[0];
          lon = pos[1];
        }
      }

      final weather = await ClaudeService.getWeather(lat, lon);
      if (weather == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('天気情報の取得に失敗しました')),
        );
        return;
      }
      final city = weather['city'] ?? '現在地';
      final weatherText = '今日の${city}の天気は${weather['description']}、気温${weather['temp']}℃（体感${weather['feels_like']}℃）、湿度${weather['humidity']}%です。今日の天気と気温に合わせたコーデを提案してください。';
      _controller.text = weatherText;
      _sendMessage();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('天気情報の取得に失敗しました')),
      );
    }
  }

  Future<List<double>?> _getPosition() async {
    return null; // スマホ版で実装予定
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

    final closetSummary = await getClosetSummary();
    final reply = await ClaudeService.sendMessage(
      _messages.where((m) => m.isUser || _messages.indexOf(m) > 0).toList(),
      userProfile: widget.userProfile,
      closetSummary: closetSummary,
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

    // 画像生成はユーザーが明示的に依頼した場合のみ
    final userText = text.toLowerCase();
    final isImageRequest = userText.contains('画像') || userText.contains('写真') || userText.contains('見せて') || userText.contains('イメージ') || userText.contains('生成して') || userText.contains('画像作って');

    if (isImageRequest) {
      setState(() {
        _messages.add(ChatMessage(text: '👗 コーデ画像を生成中です...（約15秒かかります）', isUser: false));
        _isLoading = true;
      });
      _scrollToBottom();

      final imageUrl = await ClaudeService.generateImage(reply, userProfile: widget.userProfile);
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
            icon: const Icon(Icons.bookmark, color: Colors.white),
            tooltip: '保存したコーデ',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const SavedScreen(),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.wb_sunny, color: Colors.white),
            tooltip: '今日の天気コーデ',
            onPressed: () => _sendWeatherCoordinate(),
          ),
          IconButton(
            icon: const Icon(Icons.checkroom, color: Colors.white),
            tooltip: 'クローゼット',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const ClosetScreen(),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: 'スタイル設定',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ProfileScreen(onComplete: (_) => Navigator.pop(context)),
              ));
            },
          ),
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
                        if (!msg.isUser && msg.imageUrl == null && msg.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _saveCoordinate(msg.text, null),
                              icon: const Icon(Icons.bookmark_border, size: 16, color: Color(0xFF7FD6C2)),
                              label: const Text('保存', style: TextStyle(color: Color(0xFF7FD6C2), fontSize: 12)),
                            ),
                          ),
                        ],
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
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _saveCoordinate(msg.text, msg.imageUrl),
                                icon: const Icon(Icons.bookmark_border, size: 18, color: Color(0xFF7FD6C2)),
                                label: const Text('保存', style: TextStyle(color: Color(0xFF7FD6C2))),
                              ),
                              TextButton.icon(
                                onPressed: () => _shareImage(msg.imageUrl!),
                                icon: const Icon(Icons.share, size: 18, color: Color(0xFF7FD6C2)),
                                label: const Text('共有', style: TextStyle(color: Color(0xFF7FD6C2))),
                              ),
                            ],
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
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        if (!_isLoading) _sendMessage();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'コーデの相談をしてみよう...\n(Shift+Enterで改行)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      enabled: !_isLoading,
                    ),
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
