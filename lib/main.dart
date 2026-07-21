import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'closet_screen.dart';
import 'skeleton_diagnosis_screen.dart';
import 'points_service.dart';
import 'points_screen.dart';
import 'saved_screen.dart';
import 'purchase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Web版でもログイン状態を永続化
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  await PurchaseService.init();
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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && PurchaseService.isPurchaseSupported) {
        await Purchases.logIn(uid);
      }
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
  String height;
  String bodyType;
  String skeletonType;
  List<String> ngItems;

  UserProfile({
    this.gender = '',
    this.age = '',
    this.styles = const [],
    this.brands = const [],
    this.budget = '',
    this.height = '',
    this.bodyType = '',
    this.skeletonType = '',
    this.ngItems = const [],
  });

  Map<String, String> toMap() => {
    'gender': gender,
    'age': age,
    'styles': styles.join('・'),
    'brands': brands.join('・'),
    'budget': budget,
    'height': height,
    'bodyType': bodyType,
    'skeletonType': skeletonType,
    'ngItems': ngItems.join('・'),
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
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await PointsService.captureReferralCodeFromUrl(Uri.base);
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
          height: p['height'] ?? '',
          bodyType: p['bodyType'] ?? '',
          skeletonType: p['skeletonType'] ?? '',
          ngItems: List<String>.from(p['ngItems'] ?? []),
        );
        _checked = true;
      });
    } else {
      setState(() => _checked = true);
    }
  }

  bool _diagnosisDone = false;
  String _skeletonType = '';

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null || !_profile!.isComplete) {
      if (!_introDone) {
        return AppIntroScreen(onStart: () => setState(() => _introDone = true));
      }
      if (!_diagnosisDone) {
        return SkeletonDiagnosisScreen(onComplete: (type) {
          setState(() {
            _skeletonType = type;
            _diagnosisDone = true;
          });
        });
      }
      return ProfileScreen(
        initialSkeletonType: _skeletonType,
        onComplete: (profile) {
          setState(() => _profile = profile);
        },
      );
    }
    return ChatScreen(userProfile: _profile!);
  }
}

class AppIntroScreen extends StatelessWidget {
  final VoidCallback onStart;
  const AppIntroScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('👗', 'あなた専属のAIスタイリスト', 'チャットで相談するだけで、TPOに合わせたコーデをAIが提案します'),
      ('🧥', 'クローゼットを活用', '持っている服を登録すると、その服を使ったコーデも提案できます'),
      ('🖼️', 'コーデを画像でイメージ', '提案されたコーデは画像でも確認でき、そのまま保存もできます'),
      ('🛍️', 'そのまま購入もOK', '気に入ったアイテムは「購入」ボタンから通販サイトで探せます'),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text('StyleMind AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF5BB8A8))),
              const SizedBox(height: 4),
              const Text('へようこそ！', style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 32),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 24),
                  itemBuilder: (_, i) {
                    final (emoji, title, desc) = items[i];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(desc, style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.5)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'この後、簡単な質問（30秒ほど）にお答えいただくと、あなた好みのコーデを提案できるようになります',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7FD6C2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('はじめる →', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final Function(UserProfile) onComplete;
  final String initialSkeletonType;
  const ProfileScreen({super.key, required this.onComplete, this.initialSkeletonType = ''});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _gender = '';
  String _age = '';
  final List<String> _selectedStyles = [];
  final List<String> _selectedBrands = [];
  String _budget = '';
  String _height = '';
  String _bodyType = '';
  String _skeletonType = '';
  final List<String> _selectedNgItems = [];
  bool _saving = false;

  final List<String> _styleOptions = ['ミニマル/シンプル', 'ストリート', 'Y2K/レトロ', 'ゴープコア/アウトドア', 'フェミニン/ガーリー', 'クワイエットラグジュアリー', '韓国系/オルチャン', 'モード/アバンギャルド', 'カジュアル/アメカジ', 'サブカル/古着'];
  final List<String> _brandOptions = ['ユニクロ', 'GU', 'ZARA', 'H&M', 'ビームス', 'ナノユニバース', 'アーバンリサーチ', 'シュプリーム', 'ナイキ', 'ニューバランス', 'マルニ', 'アクネ', 'マルジェラ', 'その他'];
  final List<String> _budgetOptions = ['〜5,000円', '5,000〜15,000円', '15,000〜30,000円', '30,000円〜'];
  final List<String> _heightOptions = ['〜160cm', '161〜165cm', '166〜170cm', '171〜175cm', '176〜180cm', '181cm〜'];
  final List<String> _bodyTypeOptions = ['細身/スリム', '標準', 'がっちり/筋肉質', 'ぽっちゃり', '高身長', '小柄'];
  final List<String> _ngItemOptions = ['ショートパンツ', 'タンクトップ', 'スキニーパンツ', 'ハイヒール', 'ピンク系', '柄物', 'ロゴ多め', '露出多め'];

  @override
  void initState() {
    super.initState();
    _skeletonType = widget.initialSkeletonType;
  }

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
          'height': _height,
          'bodyType': _bodyType,
          'skeletonType': _skeletonType,
          'ngItems': _selectedNgItems,
        }
      }, SetOptions(merge: true));
    }
    await PointsService.ensureReferralCode();
    await PointsService.awardReferralPointsIfEligible();
    final profile = UserProfile(gender: _gender, age: _age, styles: _selectedStyles, brands: _selectedBrands, budget: _budget, height: _height, bodyType: _bodyType, skeletonType: _skeletonType, ngItems: _selectedNgItems);
    widget.onComplete(profile);
  }

  int _step = 0;

  static const _steps = [
    '性別を教えてください',
    '年齢層を教えてください',
    '好きなスタイルは？',
    '好きなブランドは？',
    '1コーデの予算は？',
    '身長を教えてください',
    '体型を教えてください',
    'NGアイテムはありますか？',
  ];

  bool get _canProceed {
    switch (_step) {
      case 0: return _gender.isNotEmpty;
      case 1: return _age.isNotEmpty;
      case 2: return _selectedStyles.isNotEmpty;
      case 4: return _budget.isNotEmpty;
      default: return true;
    }
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _chipGroup(['メンズ', 'レディース', 'ユニセックス'], _gender, (v) => setState(() => _gender = v));
      case 1:
        return _chipGroup(['10代', '20代前半', '20代後半', '30代', '40代以上'], _age, (v) => setState(() => _age = v));
      case 2:
        return _multiChipGroup(_styleOptions, _selectedStyles);
      case 3:
        return _multiChipGroup(_brandOptions, _selectedBrands);
      case 4:
        return _chipGroup(_budgetOptions, _budget, (v) => setState(() => _budget = v));
      case 5:
        return _chipGroup(_heightOptions, _height, (v) => setState(() => _height = v));
      case 6:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_skeletonType.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7FD6C2).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('骨格タイプ診断の結果：$_skeletonType', style: const TextStyle(color: Color(0xFF3C9A85), fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            _chipGroup(_bodyTypeOptions, _bodyType, (v) => setState(() => _bodyType = v)),
          ],
        );
      case 7:
        return _multiChipGroup(_ngItemOptions, _selectedNgItems, color: Colors.red[100]!);
      default:
        return const SizedBox();
    }
  }

  Widget _chipGroup(List<String> options, String selected, void Function(String) onSelect) {
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: options.map((o) => GestureDetector(
        onTap: () => onSelect(o),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: selected == o ? const Color(0xFF7FD6C2) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected == o ? const Color(0xFF7FD6C2) : Colors.grey.shade300),
          ),
          child: Text(o, style: TextStyle(color: selected == o ? Colors.white : Colors.black87, fontWeight: selected == o ? FontWeight.bold : FontWeight.normal)),
        ),
      )).toList(),
    );
  }

  Widget _multiChipGroup(List<String> options, List<String> selected, {Color color = const Color(0xFF7FD6C2)}) {
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: options.map((o) {
        final isSelected = selected.contains(o);
        return GestureDetector(
          onTap: () => setState(() => isSelected ? selected.remove(o) : selected.add(o)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: isSelected ? color : Colors.grey.shade300),
            ),
            child: Text(o, style: TextStyle(color: isSelected ? (color == Colors.red[100] ? Colors.red[800]! : Colors.white) : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSteps = _steps.length;
    final progress = (_step + 1) / totalSteps;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('スタイル診断', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: _step > 0 ? IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => setState(() => _step--),
        ) : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // プログレスバー
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF7FD6C2)),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${_step + 1} / $totalSteps', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 32),
            Text('Q${_step + 1}', style: const TextStyle(color: Color(0xFF7FD6C2), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Text(_steps[_step], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (_step == 2 || _step == 3 || _step == 7)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('複数選択OK', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            const SizedBox(height: 32),
            Expanded(child: SingleChildScrollView(child: _buildStepContent())),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (!_canProceed || _saving) ? null : () {
                  if (_step < totalSteps - 1) {
                    setState(() => _step++);
                  } else {
                    _save();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7FD6C2),
                  disabledBackgroundColor: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _step < totalSteps - 1 ? '次へ →' : '診断完了！',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            // Q4以降はスキップ可能
            if (_step >= 3 && _step < totalSteps - 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      if (_step < totalSteps - 1) setState(() => _step++);
                    },
                    child: const Text('スキップ →', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageGeneratingCard extends StatefulWidget {
  const _ImageGeneratingCard();

  @override
  State<_ImageGeneratingCard> createState() => _ImageGeneratingCardState();
}

class _ImageGeneratingCardState extends State<_ImageGeneratingCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _tipIndex = 0;
  static const _tips = [
    '✨ コーデ画像を生成中です...',
    '👗 AIがあなたのスタイルを描いています...',
    '🎨 ブランドのビジュアルを正確に再現中...',
    '👟 シューズからアクセサリーまで細部を描写中...',
    '🌟 もうすぐ完成します...',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addListener(() {
        final newIndex = (_controller.value * _tips.length).floor().clamp(0, _tips.length - 1);
        if (newIndex != _tipIndex) setState(() => _tipIndex = newIndex);
      })
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7FD6C2), Color(0xFF5BC4AE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tips[_tipIndex],
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => LinearProgressIndicator(
                value: _controller.value,
                backgroundColor: Colors.white30,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💡 スタイリングの豆知識', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                SizedBox(height: 4),
                Text(
                  'コーデの基本は「3色ルール」。メインカラー・サブカラー・アクセントカラーの3色でまとめると洗練されたスタイルが完成します',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaywallCard extends StatefulWidget {
  const _PaywallCard();

  @override
  State<_PaywallCard> createState() => _PaywallCardState();
}

class _PaywallCardState extends State<_PaywallCard> {
  bool _purchasing = false;

  Future<void> _onUpgradePressed() async {
    if (!PurchaseService.isPurchaseSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現在Web版では購読いただけません。スマホアプリ版からご購読ください。')),
        );
      }
      return;
    }
    setState(() => _purchasing = true);
    final success = await PurchaseService.purchasePremium();
    if (mounted) {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'ご購読ありがとうございます！引き続きお楽しみください' : '購入が完了しませんでした')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7FD6C2), Color(0xFF5BC4AE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '✨ 無料の画像生成回数を使い切りました',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            '有料プラン（月額1,000円）で、画像生成が無制限になります。',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _purchasing ? null : _onUpgradePressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF3C9A85),
              ),
              child: _purchasing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('有料プランにアップグレード'),
            ),
          ),
        ],
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
  static const String _proxyUrl = 'https://stylemind-proxy-production.up.railway.app/chat';
  static const String _imageUrl = 'https://stylemind-proxy-production.up.railway.app/generate-image';
  static const String _weatherUrl = 'https://stylemind-proxy-production.up.railway.app/weather';
  static const String _outfitAnalysisUrl = 'https://stylemind-proxy-production.up.railway.app/analyze-outfit';

  static Future<Map<String, dynamic>?> getWeather(double lat, double lon) async {
    try {
      final response = await http.post(
        Uri.parse(_weatherUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'lat': lat, 'lon': lon}),
      ).timeout(const Duration(seconds: 15));
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
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['reply'] as String;
      } else {
        return 'エラーが発生しました。もう一度試してください。';
      }
    } catch (e) {
      return '通信がうまくいきませんでした。もう一度お試しください。';
    }
  }

  static Future<String?> getFashionTip() async {
    try {
      final tips = [
        '白シャツ1枚でコーデの印象が大きく変わります。オーバーサイズとジャストサイズを使い分けてみましょう',
        'デニムの色で季節感を演出できます。夏は薄いライトブルー、秋冬は濃いインディゴが旬です',
        'スニーカーの白は最強の万能アイテム。どんなコーデにも合わせやすくクリーンな印象を作れます',
        'バッグの色はシューズと合わせると統一感が生まれます。この小技でグッとおしゃれに見えます',
        'レイヤードは首元・袖口・裾の3箇所で差し色を見せると洗練されたスタイルになります',
        'ワントーンコーデは同系色でまとめることで自然なグラデーションが生まれおしゃれ上級者に見えます',
        '腕時計は左手首、リングは右手に付けるとバランスよく見えます',
        'オーバーサイズトップスはボトムをタックインするとシルエットが締まりスタイルよく見えます',
        'ベルトはパンツとシューズの色に合わせると全体がまとまり、洗練された印象になります',
        'ニットとデニムの組み合わせは季節を問わず使えるベーシックコーデの王道です',
        'キャップ一つでカジュアル感が増し、ストリートスタイルのアクセントになります',
        '小柄な方は上下同系色のワントーンにすると縦のラインが強調されスタイルよく見えます',
        'がっちり体型の方はオーバーサイズのトップスで肩幅をカバーするとバランスが整います',
        '色は3色以内にまとめるとコーデが破綻しません。メイン・サブ・アクセントの3色が基本です',
        'ソックスを見せるだけでコーデにアクセントが生まれます。柄・色ソックスは上級テクです',
        'シャツの第1ボタンを開けるだけでこなれた印象に。ネクタイなしのシャツはここが重要です',
        '素材感の違いを楽しむのが2026年のトレンド。ニット×レザー、コットン×ナイロンなどの組み合わせを試してみて',
        'トレンドアイテムを1点入れるだけでコーデが今っぽくなります。全部トレンドにする必要はありません',
        'ロールアップ（袖・裾の折り返し）でカジュアル感と抜け感が同時に出せます',
        '購入前にコーデ全体のバランスをスマホで写真撮って確認する習慣をつけると失敗が減ります',
      ];
      tips.shuffle();
      return tips.first;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> generateImage(String prompt, {UserProfile? userProfile}) async {
    try {
      final response = await http.post(
        Uri.parse(_imageUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt, 'userProfile': userProfile?.toMap()}),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['imageUrl'] as String;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 全身コーデ写真を送って、服装だけについてのフィードバックをもらう（顔・髪型・体型には触れない）。
  static Future<String?> analyzeOutfit(Uint8List imageBytes, {UserProfile? userProfile}) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final response = await http.post(
        Uri.parse(_outfitAnalysisUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'imageBase64': base64Image, 'userProfile': userProfile?.toMap()}),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['reply'] as String;
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
  String? _lastOutfitReply;
  String? _selectedScene;
  int? _remainingFree;
  bool _premium = false;

  static const String _welcomeMessage = 'こんにちは！私はStyleMind AIです👗\nどんなコーデの相談でもOKですよ！\n\n例えば：\n・デートに着ていく服を教えて\n・就活スーツに合うシャツは？\n・今日の気分はカジュアルに！\n\n⚠️ 画像生成について\nAIが生成するコーデ画像は「雰囲気のイメージ」です。著作権・商標の関係上、ブランドロゴやマークは表示されません。実際の商品は「購入」ボタンからご確認ください。';

  final List<ChatMessage> _messages = [
    ChatMessage(text: _welcomeMessage, isUser: false),
  ];

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _refreshFreeStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDisclaimerIfNeeded());
  }

  Future<void> _refreshFreeStatus() async {
    final premium = await PurchaseService.isPremium();
    final remaining = await PurchaseService.remainingFreeGenerations();
    if (!mounted) return;
    setState(() {
      _premium = premium;
      _remainingFree = remaining;
    });
  }

  Future<void> _showDisclaimerIfNeeded() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.data()?['disclaimerShown'] == true) return;
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Text('⚠️ ', style: TextStyle(fontSize: 20)),
          Text('ご利用前にお読みください', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('【画像生成について】', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5BB8A8))),
              SizedBox(height: 6),
              Text('AIが生成するコーデ画像は「雰囲気のイメージ」です。著作権・商標の関係上、以下の制限があります：', style: TextStyle(fontSize: 13)),
              SizedBox(height: 8),
              Text('• ブランドロゴ・マークは表示されません\n• 実際の商品デザインと異なる場合があります\n• 生成画像の商用利用はできません', style: TextStyle(fontSize: 13, height: 1.6)),
              SizedBox(height: 12),
              Text('【購入について】', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5BB8A8))),
              SizedBox(height: 6),
              Text('実際の商品は「購入」ボタンから各ショッピングサイトでご確認ください。\n購入リンクにはアフィリエイトが含まれる場合があります。', style: TextStyle(fontSize: 13, height: 1.6)),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                FirebaseFirestore.instance.collection('users').doc(uid).update({'disclaimerShown': true});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7FD6C2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('理解しました'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadChatHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .limitToLast(50)
          .get();
      if (snapshot.docs.isEmpty) return;
      final loaded = snapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          text: data['text'] as String? ?? '',
          isUser: data['isUser'] as bool? ?? false,
          imageUrl: data['imageUrl'] as String?,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.add(ChatMessage(text: _welcomeMessage, isUser: false));
          _messages.addAll(loaded);
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('アカウントを削除'),
        content: const Text('アカウントとすべてのデータ（チャット履歴・クローゼット・保存したコーデ・診断結果・ポイント）を完全に削除します。この操作は取り消せません。本当に削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除する', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteAccount(context);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      for (final sub in ['messages', 'saved_coordinates', 'closet']) {
        final docs = await userRef.collection(sub).get();
        for (final d in docs.docs) {
          await d.reference.delete();
        }
      }
      await userRef.delete();

      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          await user.reauthenticateWithProvider(GoogleAuthProvider());
          await user.delete();
        } else {
          rethrow;
        }
      }

      if (context.mounted) Navigator.pop(context); // ローディングダイアログを閉じる
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // ローディングダイアログを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e')),
        );
      }
    }
  }

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

  Future<void> _saveToFirestore(String text, bool isUser, {String? imageUrl}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = {
      'text': text,
      'isUser': isUser,
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (imageUrl != null) data['imageUrl'] = imageUrl;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('messages')
        .add(data);
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

  // コーデテキストからアイテムリストを抽出
  List<Map<String, String>> _parseOutfitItemsForShop(String messageText) {
    final labelMap = [
      [['トップス', 'シャツ', 'Tシャツ', 'ニット', 'カットソー', 'ポロ', 'インナー'], 'トップス', '👕'],
      [['ボトムス', 'パンツ', 'デニム', 'ジーンズ', 'スカート', 'チノ', 'スラックス', 'ショーツ'], 'ボトムス', '👖'],
      [['アウター', 'ジャケット', 'コート', 'パーカー', 'ブルゾン', 'フーディ', 'ダウン'], 'アウター', '🧥'],
      [['シューズ', '靴', 'スニーカー', 'ブーツ', 'サンダル', 'ローファー', '足元'], 'シューズ', '👟'],
      [['バッグ', 'カバン', 'リュック', 'トート', 'ショルダー', 'クラッチ', 'サコッシュ'], 'バッグ', '👜'],
      [['時計', 'ウォッチ'], '時計', '⌚'],
      [['アクセサリー', 'リング', 'ネックレス', 'ブレスレット', 'ピアス'], 'アクセサリー', '💍'],
    ];

    final luxuryBrands = RegExp(
      r'マルジェラ|アクネ|バレンシアガ|ストーンアイランド|モンクレール|オフホワイト|クロムハーツ|ロレックス|ロンシャン|メゾン|Maison|Acne|Balenciaga|Supreme|シュプリーム|ビームス|ケンゾー|ゴールドウィン',
      caseSensitive: false,
    );
    final massRetailBrands = RegExp(
      r'ユニクロ|UNIQLO|GU|ジーユー|しまむら|ワークマン',
      caseSensitive: false,
    );

    final lines = messageText.split('\n');
    final List<Map<String, String>> items = [];
    final Set<String> addedLabels = {};

    for (final line in lines) {
      final colonIdx = line.indexOf('：') != -1 ? line.indexOf('：') : line.indexOf(':');
      if (colonIdx == -1) continue;
      final labelRaw = line.substring(0, colonIdx).replaceAll(RegExp(r'[\*\#\s「」]'), '');
      final valueRaw = line.substring(colonIdx + 1)
          .replaceAll(RegExp(r'\*\*'), '')
          .replaceAll(RegExp(r'¥[\d,〜~]+(?:万)?(?:前後|程度)?'), '')
          .trim();
      if (valueRaw.isEmpty || valueRaw.length < 2) continue;

      // 通販サイト検索用キーワード：「または〜」の代替案や補足注記は検索エンジンが解釈できないため除去
      final searchValue = valueRaw
          .replaceAll(RegExp(r'または.*$'), '')
          .replaceAll(RegExp(r'※[^\n]*'), '')
          .replaceAll(RegExp(r'（節約版[^）]*）'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      for (final entry in labelMap) {
        final keywords = entry[0] as List<String>;
        final label = entry[1] as String;
        final icon = entry[2] as String;
        if (keywords.any((kw) => labelRaw.contains(kw)) && !addedLabels.contains(label)) {
          final isLuxury = luxuryBrands.hasMatch(valueRaw);
          final isMassRetail = massRetailBrands.hasMatch(valueRaw);
          final keyword = searchValue.length > 40 ? searchValue.substring(0, 40) : searchValue;
          final encoded = Uri.encodeComponent(keyword);

          // ストアリストをブランドに応じて決定
          final List<Map<String, String>> shops = [];
          if (!isMassRetail) {
            // ZOZOTOWNはアフィリエイトプログラムが2012年に終了し現存しないため、Yahoo!ショッピングに置き換え（バリューコマース MyLink経由）
            final yahooShoppingUrl = Uri.encodeComponent('https://shopping.yahoo.co.jp/search?p=${Uri.decodeComponent(encoded)}');
            shops.add({'name': 'Yahoo!ショッピング', 'icon': '🛍️', 'url': 'https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3774833&pid=892651346&vc_url=$yahooShoppingUrl'});
          }
          if (isMassRetail && massRetailBrands.hasMatch(valueRaw)) {
            shops.add({'name': 'ユニクロ公式', 'icon': '👕', 'url': 'https://www.uniqlo.com/jp/ja/search?q=${Uri.encodeComponent(searchValue.replaceAll(RegExp(r'ユニクロ|UNIQLO'), '').trim())}'});
          } else if (!isLuxury) {
            // プチプラ・一般ブランドのみユニクロに送る
          }
          // ジャンルID指定なし（旧100533は「キッズ・ベビー・マタニティ」ジャンルで誤指定だった）
          // 楽天アフィリエイト直リンク（オーナー個人アカウント発行のID。旧A8.net経由リンクは別アカウント宛だったため置き換え）
          final rakutenSearchUrl = Uri.encodeComponent('https://search.rakuten.co.jp/search/mall/${Uri.decodeComponent(encoded)}/');
          shops.add({'name': 'Rakuten Fashion', 'icon': '🏪', 'url': 'https://hb.afl.rakuten.co.jp/hgc/556d406f.aeda9c3d.556d4070.99ba5cc0/?pc=$rakutenSearchUrl&link_type=hybrid_url'});
          shops.add({'name': 'Amazon', 'icon': '📦', 'url': 'https://www.amazon.co.jp/s?k=$encoded&i=fashion&tag=stylemind2026-22'});
          // セカンドストリート（A8.net、即時提携承認済み）：検索URL非対応のためトップページへの固定リンク
          shops.add({'name': 'セカンドストリート', 'icon': '♻️', 'url': 'https://px.a8.net/svt/ejp?a8mat=4B7SH1+4FK6WI+4J34+HWXLD'});

          items.add({
            'label': label,
            'icon': icon,
            'value': valueRaw,
            'shops': shops.map((s) => '${s['icon']}|${s['name']}|${s['url']}').join(';;'),
          });
          addedLabels.add(label);
          break;
        }
      }
    }
    return items;
  }

  void _showOutfitDetails(BuildContext context, String outfitText) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('👗 コーデ詳細', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Text(
                outfitText.replaceAll(RegExp(r'\*\*'), ''),
                style: const TextStyle(fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showShopLinks(context, outfitText);
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('このコーデを購入する'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7FD6C2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShopLinks(BuildContext context, String messageText) {
    final outfitItems = _parseOutfitItemsForShop(messageText);

    // WEARリンク用キーワード
    final wearKeyword = Uri.encodeComponent(outfitItems.isNotEmpty ? outfitItems.first['value']! : 'コーデ');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('🛒 アイテム別購入リンク', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 4),
              const Text('各アイテムをタップしてショップで検索', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 16),
              if (outfitItems.isEmpty)
                const Text('アイテム情報が見つかりませんでした', style: TextStyle(color: Colors.grey))
              else
                ...outfitItems.map((item) {
                  final shops = item['shops']!.split(';;').map((s) {
                    final parts = s.split('|');
                    return {'icon': parts[0], 'name': parts[1], 'url': parts[2]};
                  }).toList();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7FD6C2).withOpacity(0.1),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              Text(item['icon']!, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['label']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5BB8A8))),
                                    Text(item['value']!, style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...shops.map((shop) => ListTile(
                          dense: true,
                          leading: Text(shop['icon']!, style: const TextStyle(fontSize: 20)),
                          title: Text(shop['name']!, style: const TextStyle(fontSize: 14)),
                          trailing: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF7FD6C2)),
                          onTap: () async {
                            final uri = Uri.parse(shop['url']!);
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {
                              await launchUrl(uri, mode: LaunchMode.platformDefault);
                            }
                          },
                        )),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 8),
              ListTile(
                leading: const Text('📸', style: TextStyle(fontSize: 20)),
                title: const Text('WEAR（コーデ参考）', style: TextStyle(fontSize: 14)),
                trailing: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF7FD6C2)),
                onTap: () async {
                  final uri = Uri.parse('https://wear.jp/search/?q=$wearKeyword');
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  static const _scenes = [
    {'label': '📅 普段着', 'prompt': '普段のカジュアルなコーデ'},
    {'label': '💼 仕事', 'prompt': 'オフィス・仕事向けのきれいめコーデ'},
    {'label': '💕 デート', 'prompt': 'デート向けのおしゃれなコーデ'},
    {'label': '🎉 お出かけ', 'prompt': 'お出かけ・買い物向けのコーデ'},
    {'label': '⚽ スポーツ', 'prompt': 'スポーツ・アクティブなコーデ'},
    {'label': '🌙 夜・パーティ', 'prompt': '夜のお出かけ・パーティ向けのコーデ'},
  ];

  Future<void> _sendMessage() async {
    final rawText = _controller.text.trim();
    final text = (_selectedScene != null && rawText.isEmpty)
        ? _selectedScene!
        : rawText;
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
      _selectedScene = null;
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

    // AIの返答がコーデ提案の場合、最新として記憶
    final bool isOutfitReply = reply.contains('トップス') || reply.contains('ボトムス') ||
        reply.contains('シューズ') || reply.contains('足元') || reply.contains('スニーカー') ||
        reply.contains('アウター') || reply.contains('ジャケット');
    if (isOutfitReply) {
      _lastOutfitReply = reply;
      // コーデ提案時にスタイリングTipsを自動追加
      final tip = await ClaudeService.getFashionTip();
      if (tip != null && tip.isNotEmpty && mounted) {
        setState(() {
          _messages.add(ChatMessage(text: '💡 $tip', isUser: false));
        });
        await _saveToFirestore('💡 $tip', false);
      }
    }

    // 画像生成はユーザーが明示的に依頼した場合のみ
    final userText = text.toLowerCase();
    final isImageRequest = userText.contains('画像') || userText.contains('写真') || userText.contains('見せて') || userText.contains('イメージ') || userText.contains('生成') || userText.contains('画面') || userText.contains('見たい') || userText.contains('コーデ見') || userText.contains('作って');

    if (isImageRequest) {
      final canGenerate = await PurchaseService.canGenerateImage();
      if (!canGenerate) {
        setState(() {
          _messages.add(ChatMessage(text: '__paywall__', isUser: false));
        });
        _scrollToBottom();
        return;
      }

      setState(() {
        _messages.add(ChatMessage(text: '__generating_image__', isUser: false));
        _isLoading = true;
      });
      _scrollToBottom();

      // 最新のコーデ提案を使用（なければ直前メッセージを検索）
      String outfitText = _lastOutfitReply ?? reply;
      if (_lastOutfitReply == null) {
        for (int i = _messages.length - 1; i >= 0; i--) {
          final msg = _messages[i];
          if (!msg.isUser && (msg.text.contains('トップス') || msg.text.contains('ボトムス') || msg.text.contains('シューズ') || msg.text.contains('足元') || msg.text.contains('スニーカー'))) {
            outfitText = msg.text;
            break;
          }
        }
      }

      // 画像生成と並列でTipsを取得
      final results = await Future.wait([
        ClaudeService.generateImage(outfitText, userProfile: widget.userProfile),
        ClaudeService.getFashionTip(),
      ]);
      final imageUrl = results[0] as String?;
      final tip = results[1] as String?;

      if (imageUrl != null) {
        await PurchaseService.recordGenerationUsed();
        await _refreshFreeStatus();
      }

      setState(() {
        _isLoading = false;
        if (imageUrl != null) {
          _messages.last = ChatMessage(text: '👗 提案コーデのイメージ', isUser: false, imageUrl: imageUrl);
          _saveToFirestore('👗 提案コーデのイメージ', false, imageUrl: imageUrl);
          if (tip != null && tip.isNotEmpty) {
            _messages.add(ChatMessage(text: '💡 スタイリングTips\n$tip', isUser: false));
            _saveToFirestore('💡 スタイリングTips\n$tip', false);
          }
        } else {
          _messages.last = ChatMessage(text: '画像の生成に失敗しました。もう一度お試しください。', isUser: false);
        }
      });
      _scrollToBottom();
    }

    _scrollToBottom();
  }

  /// 全身コーデ写真を撮影/選択してStyleMind AIに送り、服装だけのフィードバックをもらう。
  /// 画像生成と同じ無料枠を消費する（2026-07-20方針）。
  Future<void> _analyzeOutfitPhoto() async {
    if (_isLoading) return;

    final canUse = await PurchaseService.canGenerateImage();
    if (!canUse) {
      setState(() {
        _messages.add(ChatMessage(text: '__paywall__', isUser: false));
      });
      _scrollToBottom();
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1024);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    setState(() {
      _messages.add(ChatMessage(text: '今日のコーデ、これです！', isUser: true, imageUrl: dataUri));
      _messages.add(ChatMessage(text: '', isUser: false));
      _isLoading = true;
    });
    _scrollToBottom();
    await _saveToFirestore('今日のコーデ、これです！', true, imageUrl: dataUri);

    final reply = await ClaudeService.analyzeOutfit(bytes, userProfile: widget.userProfile);

    if (reply == null) {
      setState(() {
        _isLoading = false;
        _messages.last = ChatMessage(text: '写真の解析に失敗しました。もう一度お試しください。', isUser: false);
      });
      _scrollToBottom();
      return;
    }

    await PurchaseService.recordGenerationUsed();
    await _refreshFreeStatus();

    final int lastIndex = _messages.length - 1;
    for (int i = 0; i < reply.length; i++) {
      await Future.delayed(const Duration(milliseconds: 8));
      if (!mounted) return;
      setState(() {
        _messages[lastIndex] = ChatMessage(text: reply.substring(0, i + 1), isUser: false);
      });
    }
    setState(() => _isLoading = false);
    await _saveToFirestore(reply, false);
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
            if (!_premium && _remainingFree != null)
              Text(
                '🎨 無料画像生成 あと$_remainingFree回',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'チャットをリセット',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('チャットをリセット'),
                  content: const Text('チャット履歴をすべて削除しますか？\n保存したコーデは残ります。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('削除する', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !mounted) return;
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('messages').get();
                for (final doc in snap.docs) { await doc.reference.delete(); }
              }
              setState(() {
                _messages.clear();
                _messages.add(ChatMessage(text: _welcomeMessage, isUser: false));
                _lastOutfitReply = null;
                _selectedScene = null;
              });
            },
          ),
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
            icon: const Icon(Icons.card_giftcard, color: Colors.white),
            tooltip: '招待・ポイント',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PointsScreen(userProfile: widget.userProfile),
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
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            tooltip: 'アカウントを削除',
            onPressed: () => _confirmDeleteAccount(context),
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

                // 無料枠上限に達した場合のペイウォールカード
                if (msg.text == '__paywall__' && !msg.isUser) {
                  return const _PaywallCard();
                }

                // 画像生成中ローディングカード
                if (msg.text == '__generating_image__' && !msg.isUser) {
                  return const _ImageGeneratingCard();
                }

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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _saveCoordinate(msg.text, null),
                                icon: const Icon(Icons.bookmark_border, size: 16, color: Color(0xFF7FD6C2)),
                                label: const Text('保存', style: TextStyle(color: Color(0xFF7FD6C2), fontSize: 12)),
                              ),
                              TextButton.icon(
                                onPressed: () => _showShopLinks(context, msg.text),
                                icon: const Icon(Icons.shopping_bag_outlined, size: 16, color: Color(0xFF7FD6C2)),
                                label: const Text('購入', style: TextStyle(color: Color(0xFF7FD6C2), fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                        if (msg.imageUrl != null) ...[
                          const SizedBox(height: 8),
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  final outfitText = _lastOutfitReply ?? msg.text;
                                  _showOutfitDetails(context, outfitText);
                                },
                                child: ClipRRect(
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
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app, color: Colors.white, size: 14),
                                      SizedBox(width: 4),
                                      Text('タップで詳細', style: TextStyle(color: Colors.white, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _controller.text = '節約版のコーデも提案してください。それぞれの違いや高い版の良さも教えてください。';
                                    _sendMessage();
                                  },
                                  icon: const Icon(Icons.compare_arrows, size: 16, color: Color(0xFF7FD6C2)),
                                  label: const Text('節約版と比較', style: TextStyle(color: Color(0xFF7FD6C2), fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFF7FD6C2)),
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                  ),
                                ),
                              ),
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
          // クイックリプライボタン（コーデ提案後に表示）
          if (_lastOutfitReply != null)
            Container(
              height: 36,
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  {'label': '🔄 別の提案', 'text': '違うスタイルでもう一度提案してください'},
                  {'label': '👕 もっとカジュアルに', 'text': 'もっとカジュアルなコーデに変えてください'},
                  {'label': '✨ もっときれいめに', 'text': 'もっときれいめ・上品なコーデに変えてください'},
                  {'label': '💰 節約版', 'text': '同じスタイルでもっとリーズナブルな予算のコーデを提案してください'},
                  {'label': '🖼️ 画像生成', 'text': 'このコーデの画像を生成してください'},
                ].map((q) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () {
                      _controller.text = q['text']!;
                      _sendMessage();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F8F5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF7FD6C2)),
                      ),
                      child: Text(q['label']!, style: const TextStyle(fontSize: 12, color: Color(0xFF5BB8A8), fontWeight: FontWeight.w500)),
                    ),
                  ),
                )).toList(),
              ),
            ),
          // シーン選択チップ
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _scenes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final scene = _scenes[i];
                final selected = _selectedScene == scene['prompt'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedScene = selected ? null : scene['prompt'];
                      if (!selected) _controller.clear();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF7FD6C2) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? const Color(0xFF7FD6C2) : Colors.grey.shade300),
                    ),
                    child: Text(
                      scene['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : Colors.black87,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF7FD6C2)),
                  tooltip: '今日のコーデを撮って診断してもらう',
                  onPressed: _isLoading ? null : _analyzeOutfitPhoto,
                ),
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
                        hintText: _selectedScene != null
                            ? '$_selectedScene\n(送信ボタンでこのシーンのコーデを提案)'
                            : 'コーデの相談をしてみよう...\n(Shift+Enterで改行)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      enabled: true,
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
