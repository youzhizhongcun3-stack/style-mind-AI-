import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart';
import 'points_service.dart';

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

  void _shareDiagnosis() {
    final type = widget.userProfile.skeletonType;
    if (type.isEmpty) {
      Share.share('StyleMind AIで骨格タイプを診断してみたよ！\n${PointsService.shareUrl(_referralCode)}');
      return;
    }
    Share.share('骨格タイプ診断の結果、私は"$type"でした🌿\nStyleMind AIのAIコーデ診断、あなたもやってみて！\n${PointsService.shareUrl(_referralCode)}');
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
                          onPressed: _shareDiagnosis,
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
