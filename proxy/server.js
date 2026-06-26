const http = require('http');
const https = require('https');
require('dotenv').config();

const CLAUDE_API_KEY = process.env.CLAUDE_API_KEY || '';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || '';

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // チャット
  if (req.method === 'POST' && req.url === '/chat') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const { messages, userProfile, closetSummary } = JSON.parse(body);
      const recentMessages = messages.slice(-8);
      const profileContext = userProfile ? `\n【ユーザー情報】性別:${userProfile.gender||'未設定'} 年齢:${userProfile.age||'未設定'} 好きなスタイル:${userProfile.styles||'未設定'} 好きなブランド:${userProfile.brands||'未設定'} 予算:${userProfile.budget||'未設定'}` : '';
      const closetContext = closetSummary ? `\n\n【ユーザーの手持ち服（クローゼット）】\n${closetSummary}\n※手持ち服を活用したコーデ提案を優先すること。新規購入アイテムを追加する場合は手持ち服と相性の良いものを提案すること` : '';

      const payload = JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 400,
        system: `あなたはStyleMind AI、感度の高いファッションスタイリスト。2026年現在の最新トレンドを熟知している。

【2026年トレンド知識】
・スタイル系統：ミニマルシック/Y2Kリバイバル/ゴープコア/バレアコア/クワイエットラグジュアリー/ストリート/モード/韓国系オルチャン/サブカル/フェミニン/マスキュリン/ジェンダーレス
・人気ブランド（高感度）：アクネ ストゥディオズ/マルニ/トットペリー/ジルサンダー/メゾンマルジェラ/ステューシー/シュプリーム/パレス/アワーレガシー/コモンプロジェクト
・人気ブランド（プチプラ〜ミドル）：ユニクロ/GU/ZARA/H&M/アーバンリサーチ/ビームス/シップス/ナノユニバース/マウジー/スナイデル/ジャーナルスタンダード
・注目アイテム：バギーデニム/ローライズパンツ/オーバーサイズブレザー/カーゴパンツ/ニットベスト/プラットフォームシューズ/チャンキーローファー/ボアジャケット/レザートレンチ
・カラートレンド：モカムース/バーントオレンジ/コバルトブルー/チェリーレッド/ピスタチオグリーン/オフホワイト/ミルクチョコ

【返答ルール】
- ユーザーのプロフィール・好みを最優先で参考にする${profileContext}${closetContext}
- 毎回異なるスタイル提案をする。同じ系統を繰り返さない
- 具体的なブランド名・アイテム名を必ず含める
- 季節・シーン・体型・予算に合わせて提案する
- 3〜5行以内で簡潔に。絵文字1〜2個
- ユーザーが「画像生成して」「画像を見たい」「見せて」と言ったら「画像を生成します！少々お待ちください🎨」とだけ答える。絶対に「画像生成はできない」「対応していない」「代わりの方法」などと言ってはいけない。代替手段（PinterestやInstagram等）を提案することも禁止。システムが自動で画像を生成する仕組みになっている
- コーデ提案時にジャケットを追加する場合は「＋アクセントとしてジャケット：〇〇（ブランド・商品名・価格目安）」と明示して説明すること。勝手に追加して説明なしはNG
- シルバーリング・時計・ネックレス・バッグ・ベルトなどのアクセサリーや小物をコーデに加える場合は必ずブランド名と商品名を具体的に提案すること（例：「クロムハーツ シルバーリング」「カシオ Gショック DW-5600」「ポーター タンカー ウエストバッグ」など）`,
        messages: recentMessages,
      });

      const options = {
        hostname: 'api.anthropic.com',
        path: '/v1/messages',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': CLAUDE_API_KEY,
          'anthropic-version': '2023-06-01',
          'Content-Length': Buffer.byteLength(payload),
        },
      };

      const apiReq = https.request(options, (apiRes) => {
        let data = '';
        apiRes.on('data', chunk => { data += chunk; });
        apiRes.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            const reply = parsed.content[0].text;
            res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
            res.end(JSON.stringify({ reply }));
          } catch (e) {
            res.writeHead(500);
            res.end(JSON.stringify({ error: 'Parse error' }));
          }
        });
      });

      apiReq.on('error', (e) => {
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      });

      apiReq.write(payload);
      apiReq.end();
    });

  // 画像生成
  } else if (req.method === 'POST' && req.url === '/generate-image') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const { prompt, userProfile } = JSON.parse(body);

      const gender = userProfile?.gender || '';
      const age = userProfile?.age || '20代';
      let modelDesc = '';
      if (gender === 'メンズ') {
        modelDesc = `Japanese male model, ${age}, short hair, masculine appearance, no leg hair, no body hair visible`;
      } else if (gender === 'レディース') {
        modelDesc = `Japanese female model, ${age}, feminine appearance`;
      } else {
        modelDesc = `Japanese model, ${age}, gender-neutral appearance`;
      }

      const payload = JSON.stringify({
        model: 'gpt-image-1',
        prompt: `Professional fashion photography. ${prompt}. Full body shot from head to toe, shoes and footwear must be clearly visible at the bottom of the frame. Include all accessories mentioned such as rings, watches, necklaces, bags exactly as described in the outfit. ${modelDesc}, natural pose, standing on white studio background, realistic photo, high quality fashion magazine style, entire outfit including shoes and accessories fully shown, anatomically correct proportions, do not crop feet or shoes`,
        n: 1,
        size: '1024x1536',
        quality: 'medium',
      });

      const options = {
        hostname: 'api.openai.com',
        path: '/v1/images/generations',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENAI_API_KEY}`,
          'Content-Length': Buffer.byteLength(payload),
        },
      };

      const apiReq = https.request(options, (apiRes) => {
        let data = '';
        apiRes.on('data', chunk => { data += chunk; });
        apiRes.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            console.log('OpenAI response:', JSON.stringify(parsed));
            if (parsed.error) {
              console.error('OpenAI error:', parsed.error.message);
              res.writeHead(500);
              res.end(JSON.stringify({ error: parsed.error.message }));
              return;
            }
            const b64 = parsed.data[0].b64_json;
            const imageUrl = `data:image/png;base64,${b64}`;
            res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
            res.end(JSON.stringify({ imageUrl }));
          } catch (e) {
            console.error('Parse error:', e.message, 'Raw data:', data);
            res.writeHead(500);
            res.end(JSON.stringify({ error: 'Image generation failed' }));
          }
        });
      });

      apiReq.on('error', (e) => {
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      });

      apiReq.write(payload);
      apiReq.end();
    });

  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(3000, () => {
  console.log('StyleMind プロキシサーバー起動中: http://localhost:3000');
  console.log('Ctrl+C で停止');
});
