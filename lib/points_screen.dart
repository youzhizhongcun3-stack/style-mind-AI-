import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart';
import 'points_service.dart';

const _skeletonCardInfo = {
  'ストレートタイプ': {'emoji': '🔷', 'prompt': 'Iラインシルエットの、ハリのある素材を使ったシンプルなコーデを教えて'},
  'ウェーブタイプ': {'emoji': '🌊', 'prompt': 'Xラインシルエットの、とろみ素材を使ったフェミニンなコーデを教えて'},
  'ナチュラルタイプ': {'emoji': '🌿', 'prompt': 'ゆったりシルエットの、ラフな素材を使ったコーデを教えて'},
};

class PointsScreen extends StatefulWidget {
  final UserProfile userProfile;
  const PointsScreen({super.key, required this.userProfile});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  int _points = 0;
  String _referralCode = '';
  bool _loading = true;
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = await PointsService.ensureReferralCode();
    final points = await PointsService.getPoints();
    if (!mounted) return;
    setState(() {
      _referralCode = code;
      _points = points;
      _loading = false;
    });
  }

  void _shareReferral() {
    final url = PointsService.shareUrl(_referralCode);
    Share.share('StyleMind AIで、AIに似合うコーデを診断してもらったよ🤖✨\nあなたも試してみて！\n$url');
  }

  Future<void> _openDiagnosisShareCard() async {
    final type = widget.userProfile.skeletonType;
    if (type.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => _DiagnosisShareCardDialog(
        skeletonType: type,
        userProfile: widget.userProfile,
        shareUrl: PointsService.shareUrl(_referralCode),
      ),
    );
  }

  Future<void> _redeem(Future<bool> Function() action, String successMsg, String failMsg) async {
    setState(() => _redeeming = true);
    final ok = await action();
    final points = await PointsService.getPoints();
    if (!mounted) return;
    setState(() {
      _points = points;
      _redeeming = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? successMsg : failMsg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('招待・ポイント', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ポイント残高
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF7FD6C2), Color(0xFF5BC4AE)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text('保有ポイント', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('$_points pt', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 骨格診断結果のシェア
                if (widget.userProfile.skeletonType.isNotEmpty) ...[
                  const Text('あなたの診断結果', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('骨格タイプ：${widget.userProfile.skeletonType}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        TextButton.icon(
                          onPressed: _openDiagnosisShareCard,
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('シェア'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // 友達招待
                const Text('友達を招待する', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                const Text('招待した友達が診断を完了すると、あなたに30pt・友達に20ptが付与されます', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('あなたの紹介コード：$_referralCode', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _shareReferral,
                          icon: const Icon(Icons.share),
                          label: const Text('招待リンクをシェア'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7FD6C2), foregroundColor: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ポイント交換
                const Text('ポイントを使う', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                _redeemTile(
                  title: '追加診断1回無料',
                  cost: 50,
                  enabled: !_redeeming,
                  onTap: () => _redeem(
                    PointsService.redeemBonusGeneration,
                    '追加診断1回分を付与しました！',
                    'ポイントが不足しています（50pt必要）',
                  ),
                ),
                _redeemTile(
                  title: '限定コーデパターン解放',
                  cost: 100,
                  enabled: !_redeeming,
                  onTap: () => _redeem(
                    PointsService.redeemLimitedPatterns,
                    '限定コーデパターンを解放しました！チャット画面に新しいスタイルが追加されます',
                    'ポイントが不足しています（100pt必要）',
                  ),
                ),
                _redeemTile(title: '購入時500円クーポン', cost: 200, comingSoon: true),
                _redeemTile(
                  title: '「マイスタイリスト」称号',
                  cost: 500,
                  enabled: !_redeeming && widget.userProfile.gender.isNotEmpty,
                  onTap: () => _redeem(
                    PointsService.redeemTitle,
                    '「マイスタイリスト」称号を獲得しました！',
                    'ポイントが不足しています（500pt必要）',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _redeemTile({
    required String title,
    required int cost,
    bool comingSoon = false,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('$cost pt', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          if (comingSoon)
            const Text('近日公開', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            ElevatedButton(
              onPressed: enabled ? onTap : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7FD6C2),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('使う', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// 診断結果シェアカード：9:16画像を生成してプレビューし、
/// 確認した上で画像としてシェアする。
class _DiagnosisShareCardDialog extends StatefulWidget {
  final String skeletonType;
  final UserProfile userProfile;
  final String shareUrl;
  const _DiagnosisShareCardDialog({
    required this.skeletonType,
    required this.userProfile,
    required this.shareUrl,
  });

  @override
  State<_DiagnosisShareCardDialog> createState() => _DiagnosisShareCardDialogState();
}

class _DiagnosisShareCardDialogState extends State<_DiagnosisShareCardDialog> {
  static const String _chatUrl = 'https://stylemind-proxy-production.up.railway.app/chat';
  static const String _imageUrl = 'https://stylemind-proxy-production.up.railway.app/generate-image';

  final GlobalKey _cardKey = GlobalKey();
  Uint8List? _coordImage;
  bool _loading = true;
  bool _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateCoordImage();
  }

  Future<void> _generateCoordImage() async {
    try {
      final info = _skeletonCardInfo[widget.skeletonType];
      final prompt = info?['prompt'] ?? 'この骨格タイプに似合うコーデを教えて';
      final chatRes = await http.post(
        Uri.parse(_chatUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': [{'role': 'user', 'content': prompt}],
          'userProfile': widget.userProfile.toMap(),
        }),
      ).timeout(const Duration(seconds: 30));
      final reply = (jsonDecode(utf8.decode(chatRes.bodyBytes))['reply'] as String?) ?? '';

      final imgRes = await http.post(
        Uri.parse(_imageUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': reply, 'userProfile': widget.userProfile.toMap()}),
      ).timeout(const Duration(seconds: 90));
      final imageUrl = jsonDecode(utf8.decode(imgRes.bodyBytes))['imageUrl'] as String?;
      if (imageUrl == null) throw Exception('画像が取得できませんでした');
      final b64 = imageUrl.split(',').last;

      if (!mounted) return;
      setState(() {
        _coordImage = base64Decode(b64);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '画像の生成に失敗しました。もう一度お試しください';
        _loading = false;
      });
    }
  }

  Future<void> _captureAndShare() async {
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/diagnosis_share_card.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '骨格タイプ診断の結果、私は"${widget.skeletonType}"でした🌿\nStyleMind AIのAIコーデ診断、あなたもやってみて！\n${widget.shareUrl}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('シェアに失敗しました')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _skeletonCardInfo[widget.skeletonType];
    final emoji = info?['emoji'] ?? '✨';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('シェアカードを作成中...', style: TextStyle(color: Colors.white)),
                ],
              ),
            )
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
                ],
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: RepaintBoundary(
                key: _cardKey,
                child: SizedBox(
                  width: 337.5,
                  height: 600,
                  child: FittedBox(
                    child: SizedBox(
                      width: 1080,
                      height: 1920,
                      child: _DiagnosisCardContent(
                        skeletonType: widget.skeletonType,
                        emoji: emoji,
                        coordImage: _coordImage!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _sharing ? null : () => Navigator.pop(context),
                  child: const Text('閉じる', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _sharing ? null : _captureAndShare,
                  icon: _sharing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.share),
                  label: Text(_sharing ? '準備中...' : 'この内容でシェアする'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7FD6C2), foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagnosisCardContent extends StatelessWidget {
  final String skeletonType;
  final String emoji;
  final Uint8List coordImage;
  const _DiagnosisCardContent({required this.skeletonType, required this.emoji, required this.coordImage});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1080,
      height: 1920,
      color: Colors.white,
      child: Column(
        children: [
          // ロゴ・アプリ名
          Container(
            width: double.infinity,
            height: 150,
            color: const Color(0xFF7FD6C2),
            alignment: Alignment.center,
            child: const Text(
              'StyleMind AI',
              style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 36),
          // タイプ名（大きく）
          const Text('あなたの骨格タイプは', style: TextStyle(color: Colors.grey, fontSize: 28)),
          const SizedBox(height: 8),
          Text(emoji, style: const TextStyle(fontSize: 90)),
          Text(
            skeletonType,
            style: const TextStyle(color: Color(0xFF3C9A85), fontSize: 68, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 30),
          // AI生成画像がメイン
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.memory(coordImage, fit: BoxFit.cover, width: double.infinity),
              ),
            ),
          ),
          // フッター：ロゴ・URL
          Container(
            width: double.infinity,
            height: 110,
            color: const Color(0xFF1A1C24),
            alignment: Alignment.center,
            child: const Text(
              'StyleMind AI で診断する → stylemind-ai-d14ec.web.app',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
        ],
      ),
    );
  }
}
