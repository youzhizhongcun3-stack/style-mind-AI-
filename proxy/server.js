const http = require('http');
const https = require('https');
require('dotenv').config();

const CLAUDE_API_KEY = process.env.CLAUDE_API_KEY || '';

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  if (req.method === 'POST' && req.url === '/chat') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const { messages } = JSON.parse(body);

      // 直近5件のみ送信（速度改善）
      const recentMessages = messages.slice(-5);

      const payload = JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 300,
        system: `StyleMind AI：10〜20代向けファッションスタイリスト。現在は2026年。最新トレンド情報：2025〜2026年はミニマルシック・Y2Kリバイバル・ゴープコア・バレアコアが主流。ブランドはユニクロ・GU・ZARA・H&M・アーバンリサーチ・ビームス・ナイキ・ニューバランスが人気。カラーはアースカラー・モカブラウン・オフホワイト・バーントオレンジが旬。必ず3〜4行以内で簡潔に答える。日本語・絵文字1〜2個・具体的なアイテム名とブランドを1〜2個提案。長い説明は不要。`,
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
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(3000, () => {
  console.log('StyleMind プロキシサーバー起動中: http://localhost:3000');
  console.log('Ctrl+C で停止');
});
