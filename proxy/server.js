const http = require('http');
const https = require('https');

// APIキーは環境変数で管理（起動時に設定）
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

      const payload = JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: 1024,
        system: `あなたはStyleMind AIというファッションスタイリストAIです。
10〜20代の日本の若者向けに、おしゃれで親しみやすいコーデ提案をしてください。
返答は日本語で、絵文字を適度に使い、読みやすく簡潔にまとめてください。
具体的なアイテム名・ブランド・色・コーデの組み合わせを提案してください。`,
        messages: messages,
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
