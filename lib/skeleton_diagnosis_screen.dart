import 'package:flutter/material.dart';

class _Question {
  final String text;
  final List<_Option> options;
  const _Question(this.text, this.options);
}

class _Option {
  final String label;
  final String type; // 'straight' | 'wave' | 'natural'
  const _Option(this.label, this.type);
}

const List<_Question> _questions = [
  _Question('骨や関節の目立ち方は？', [
    _Option('くっきり目立つ、華奢な感じ', 'wave'),
    _Option('あまり目立たず、なめらか', 'straight'),
    _Option('大きくしっかりしている', 'natural'),
  ]),
  _Question('肌・筋肉の質感は？', [
    _Option('柔らかく、薄い印象', 'wave'),
    _Option('ハリがあり、厚みを感じる', 'straight'),
    _Option('マットで、ややかため', 'natural'),
  ]),
  _Question('体の重心は？', [
    _Option('下重心（下半身にボリュームが出やすい）', 'wave'),
    _Option('上重心（上半身にボリュームが出やすい）', 'straight'),
    _Option('均等・フラットな印象', 'natural'),
  ]),
  _Question('直感で似合いそうな素材は？', [
    _Option('とろみのある、柔らかい素材', 'wave'),
    _Option('シンプルで、ハリのある素材', 'straight'),
    _Option('ラフで、ナチュラルな素材', 'natural'),
  ]),
  _Question('よく言われる体型の特徴は？', [
    _Option('華奢すぎる、薄いと言われる', 'wave'),
    _Option('着太りしやすいと言われる', 'straight'),
    _Option('骨感・関節の大きさが目立つと言われる', 'natural'),
  ]),
];

const Map<String, Map<String, String>> _resultInfo = {
  'straight': {
    'label': 'ストレートタイプ',
    'emoji': '🔷',
    'desc': '筋肉にハリがあり、上半身に重心があるタイプ。シンプルでベーシックなアイテムがきれいに着こなせます。',
    'tips': 'Iラインシルエット／ハリのある素材／Vネック／シンプルな一枚仕立て',
  },
  'wave': {
    'label': 'ウェーブタイプ',
    'emoji': '🌊',
    'desc': '骨が華奢で、曲線的な柔らかさが魅力のタイプ。フェミニンで柔らかい素材が得意です。',
    'tips': 'Xラインシルエット／とろみ素材／小さめ柄／ハイウエスト',
  },
  'natural': {
    'label': 'ナチュラルタイプ',
    'emoji': '🌿',
    'desc': '骨や関節がしっかりしていて、直線的でラフな質感がよく似合うタイプ。',
    'tips': 'ゆったりシルエット／ラフな素材／オーバーサイズ／ざっくり感のあるニット',
  },
};

class SkeletonDiagnosisScreen extends StatefulWidget {
  final void Function(String skeletonType) onComplete;
  const SkeletonDiagnosisScreen({super.key, required this.onComplete});

  @override
  State<SkeletonDiagnosisScreen> createState() => _SkeletonDiagnosisScreenState();
}

class _SkeletonDiagnosisScreenState extends State<SkeletonDiagnosisScreen> {
  int _step = 0;
  final Map<String, int> _scores = {'straight': 0, 'wave': 0, 'natural': 0};
  bool _showResult = false;
  String _resultType = '';

  void _answer(String type) {
    setState(() {
      _scores[type] = (_scores[type] ?? 0) + 1;
      if (_step < _questions.length - 1) {
        _step++;
      } else {
        final sorted = _scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        _resultType = sorted.first.key;
        _showResult = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showResult) return _buildResult();

    final q = _questions[_step];
    final progress = (_step + 1) / _questions.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF7FD6C2),
        title: const Text('骨格タイプ診断', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                Text('${_step + 1} / ${_questions.length}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('約30秒でわかる、あなたの骨格タイプ', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 32),
            Text('Q${_step + 1}', style: const TextStyle(color: Color(0xFF7FD6C2), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Text(q.text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            Expanded(
              child: ListView(
                children: q.options.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _answer(o.type),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(o.label, style: const TextStyle(fontSize: 15, color: Colors.black87), textAlign: TextAlign.left),
                    ),
                  ),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final info = _resultInfo[_resultType]!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(info['emoji']!, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text('あなたの骨格タイプは', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 8),
              Text(
                info['label']!,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Color(0xFF3C9A85)),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info['desc']!, style: const TextStyle(fontSize: 14, height: 1.6)),
                    const SizedBox(height: 12),
                    Text('得意なスタイル：${info['tips']!}', style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.6)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => widget.onComplete(info['label']!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7FD6C2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('この骨格タイプでコーデ診断へ →', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
