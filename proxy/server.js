const http = require('http');
const https = require('https');
require('dotenv').config();

const CLAUDE_API_KEY = process.env.CLAUDE_API_KEY || '';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || '';
const OPENWEATHER_API_KEY = process.env.OPENWEATHER_API_KEY || '';

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
      const ngContext = userProfile?.ngItems ? `\n【NGアイテム・絶対に提案禁止】${userProfile.ngItems}` : '';
      const now = new Date();
      const month = now.getMonth() + 1;
      const season = month >= 3 && month <= 5 ? '春（3〜5月）軽めのアウター、トレンチコート、パステルカラー向き' :
                    month >= 6 && month <= 8 ? '夏（6〜8月）半袖・薄手素材・リネン・涼しいコーデ向き' :
                    month >= 9 && month <= 11 ? '秋（9〜11月）レイヤード・秋色・ニット・チェック向き' :
                    '冬（12〜2月）ダウン・厚手コート・ウール・防寒コーデ向き';
      const profileContext = userProfile ? `\n【ユーザー情報】性別:${userProfile.gender||'未設定'} 年齢:${userProfile.age||'未設定'} 身長:${userProfile.height||'未設定'} 体型:${userProfile.bodyType||'未設定'} 好きなスタイル:${userProfile.styles||'未設定'} 好きなブランド:${userProfile.brands||'未設定'} 予算:${userProfile.budget||'未設定'}${ngContext}` : '';
      const seasonContext = `\n【現在の季節】${season} ※季節に合わせたアイテム・素材を必ず提案すること`;
      const closetContext = closetSummary ? `\n\n【ユーザーの手持ち服（クローゼット）】\n${closetSummary}\n※手持ち服を活用したコーデ提案を優先すること。新規購入アイテムを追加する場合は手持ち服と相性の良いものを提案すること` : '';

      const payload = JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 600,
        system: `あなたはStyleMind AI、感度の高いファッションスタイリスト。2026年現在の最新トレンドを熟知している。

【ブランド・アイテム詳細知識】
・Supreme：赤地に白抜きフォントのBox Logoが特徴。Tシャツ・パーカー・キャップが定番。コラボ多数
・ニューバランス574：ゴツめのダッドシューズシルエット、サイドに大きなNロゴ、スエード×メッシュ素材
・ニューバランス990：グレーのプレミアムスエード、Made in USA、クラシックランニングシルエット
・ニューバランス2002R：レトロランニング、ゴアテックスモデルあり、厚底
・Nike Air Force 1：真っ白のローカットレザースニーカー、サイドにスウォッシュ
・Nike Air Jordan 1：ハイカットバスケットシューズ、翼マーク、多彩なカラーウェイ
・Adidas Samba：細身のフットボールインスパイア、ガムソール、3本ライン
・Adidas Stan Smith：白いテニスシューズ、グリーンヒールタブ、パーフォレーション3本ライン
・Vans Old Skool：キャンバス×スエード、白のウェービーサイドストライプ
・Converse Chuck Taylor：キャンバスハイカット/ローカット、ゴムトゥキャップ、くるぶしスターパッチ
・Stone Island：アウターの左袖にコンパスローズのバッジ、染色・機能素材が特徴
・Moncler：光沢感のあるキルティングダウン、胸にMonclerロゴワッペン
・Canada Goose：ファーフード付き重厚ダウンパーカー、Arctic Programバッジ
・Carhartt WIP：デトロイトジャケット（ダックキャンバス）、チョアコートが定番
・The North Face：マウンテンジャケット（ゴアテックス）、ハーフドームロゴ
・Arc'teryx：極薄軽量シェルジャケット、鳥のロゴ、ミニマルデザイン
・Off-White：""クォーテーションマーク""プリント、ジップタイ、インダストリアルベルト
・Balenciaga Triple S：超厚底のボリューミースニーカー、レイヤードソール
・Fear of God Essentials：ロゴ小さめのミニマルフリース・スウェット、リラックスシルエット
・Maison Margiela：Tabiブーツ（つま先二又）、白ラベルに数字、解体的デザイン
・ポーター（吉田カバン）タンカー：ナイロン製、ジッパーポケット多数、艶感あるブラック
・Longchamp Le Pliage：折りたたみトートバッグ、革ハンドル、シンプルフラップ
・クロムハーツ：シルバー925の重厚ジュエリー、十字架・短剣・フルールドリスのモチーフ、ゴシック
・カシオ G-Shock DW-5600：四角いデジタル表示、厚みのある黒ラバーベルト、80年代レトロ感
・ロレックス サブマリーナー：緑または黒ベゼルの高級ダイバーズウォッチ、メタルブレスレット
・Polo Ralph Lauren：胸に小さなポロプレイヤー刺繍、定番ポロシャツ・チノパン
・Lacoste：胸に小さなワニ（クロコダイル）刺繍のポロシャツ

【2026年トレンド知識】
・スタイル系統：ミニマルシック/Y2Kリバイバル/ゴープコア/バレアコア/クワイエットラグジュアリー/ストリート/モード/韓国系オルチャン/サブカル/フェミニン/マスキュリン/ジェンダーレス
・人気ブランド（高感度）：アクネ ストゥディオズ/マルニ/トットペリー/ジルサンダー/メゾンマルジェラ/ステューシー/シュプリーム/パレス/アワーレガシー/コモンプロジェクト
・人気ブランド（プチプラ〜ミドル）：ユニクロ/GU/ZARA/H&M/アーバンリサーチ/ビームス/シップス/ナノユニバース/マウジー/スナイデル/ジャーナルスタンダード
・注目アイテム：バギーデニム/ローライズパンツ/オーバーサイズブレザー/カーゴパンツ/ニットベスト/プラットフォームシューズ/チャンキーローファー/ボアジャケット/レザートレンチ
・カラートレンド：モカムース/バーントオレンジ/コバルトブルー/チェリーレッド/ピスタチオグリーン/オフホワイト/ミルクチョコ

【返答ルール】
- ユーザーのプロフィール・好みを最優先で参考にする${profileContext}${closetContext}${seasonContext}
- NGアイテムが設定されている場合は絶対に提案しない。NGアイテムの代替を提案すること
- 体型・身長に合わせたシルエット提案をする。例：小柄→クロップドパンツ/ハイウエスト推奨、がっちり→オーバーサイズで体型カバー、細身→レイヤードで立体感を出す
- 季節に合わない素材やアイテムは提案しない（例：夏にダウンジャケットは不可）
- 毎回異なるスタイル提案をする。同じ系統を繰り返さない
- 具体的なブランド名・アイテム名を必ず含める
- 季節・シーン・体型・予算に合わせて提案する
- 3〜5行以内で簡潔に。絵文字1〜2個
- ユーザーが「画像生成して」「画像を見たい」「見せて」と言ったら「画像を生成します！少々お待ちください🎨」とだけ答える。絶対に「画像生成はできない」「対応していない」「代わりの方法」などと言ってはいけない。代替手段（PinterestやInstagram等）を提案することも禁止。システムが自動で画像を生成する仕組みになっている
- コーデ提案時にアウター・ジャケットを含める場合は必ずテキストに「アウター：〇〇（ブランド・商品名・価格目安）」と明示すること。画像に出るのにテキストに記載なしは絶対にNG
- コーデ提案には必ずバッグを含めること。バッグは省略禁止。ブランド名・商品名・価格を明記すること
- 時計・シルバーリング・ネックレス・ベルトなどのアクセサリーをコーデに加える場合は必ずテキストに記載し、画像生成にも必ず反映すること。テキストに書いたアクセサリーが画像に出ないのは絶対にNG
- 提案したアイテム（アウター・バッグ・アクセサリー全て）は必ず画像生成にも反映されること
- 【価格バランスルール】アウター・ジャケットが¥30,000以上の高額アイテムの場合、インナー（Tシャツ・シャツ等）は必ずユニクロ・GU・ZARAなど¥5,000以下のプチプラも選択肢として提案すること。例：「インナー：アクネ スタジオズ Tシャツ ¥25,000 または ユニクロ クルーネックT ¥1,500（節約版）」のように両方提示する`,
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
      const bodyType = userProfile?.bodyType || '';
      const height = userProfile?.height || '';

      let heightDesc = '';
      if (height.includes('〜160')) heightDesc = 'petite short stature around 155cm';
      else if (height.includes('161')) heightDesc = 'average height around 163cm';
      else if (height.includes('166')) heightDesc = 'average height around 168cm';
      else if (height.includes('171')) heightDesc = 'tall around 173cm';
      else if (height.includes('176')) heightDesc = 'tall around 178cm';
      else if (height.includes('181')) heightDesc = 'very tall around 183cm';

      let bodyDesc = '';
      if (bodyType.includes('細身')) bodyDesc = 'slim slender build';
      else if (bodyType.includes('がっちり')) bodyDesc = 'athletic muscular build';
      else if (bodyType.includes('ぽっちゃり')) bodyDesc = 'slightly chubby round build';
      else if (bodyType.includes('高身長')) bodyDesc = 'tall lean build';
      else if (bodyType.includes('小柄')) bodyDesc = 'petite compact build';
      else bodyDesc = 'average build';

      let modelDesc = '';
      if (gender === 'メンズ') {
        modelDesc = `Japanese male model, ${age}, ${heightDesc}, ${bodyDesc}, short hair, masculine appearance, no leg hair, no body hair visible`;
      } else if (gender === 'レディース') {
        modelDesc = `Japanese female model, ${age}, ${heightDesc}, ${bodyDesc}, feminine appearance`;
      } else {
        modelDesc = `Japanese model, ${age}, ${heightDesc}, ${bodyDesc}, gender-neutral appearance`;
      }

      // Step1: チャットテキストからアイテムをパース
      function cleanValue(val) {
        return val
          .replace(/\*\*/g, '')
          .replace(/¥[\d,〜~]+(?:万)?(?:前後|程度)?/g, '')
          .replace(/※[^\n]*/g, '')
          .replace(/（節約版[^）]*）/g, '')
          .replace(/または[^\n]*/g, '')
          .replace(/\s{2,}/g, ' ')
          .trim();
      }

      function parseOutfitItems(text) {
        const items = {};
        const lines = text.split('\n');
        const labelMap = [
          [['トップス', 'シャツ', 'Tシャツ', 'ニット', 'カットソー', 'ポロ'], 'top'],
          [['ボトムス', 'パンツ', 'デニム', 'ジーンズ', 'ショーツ', 'スカート', 'チノ', 'スラックス'], 'bottom'],
          [['アウター', 'ジャケット', 'コート', 'パーカー', 'ブルゾン', 'フーディ', 'ダウン', 'ブレザー'], 'outer'],
          [['靴', 'シューズ', 'スニーカー', 'ブーツ', 'サンダル', 'ローファー', '足元', 'フットウェア'], 'shoes'],
          [['バッグ', 'カバン', 'バック', 'リュック', 'トート', 'ショルダー', 'クラッチ'], 'bag'],
          [['時計', 'ウォッチ'], 'watch'],
          [['リング', 'ネックレス', 'ブレスレット', 'アクセサリー', '小物', 'チェーン', 'ピアス'], 'accessories'],
        ];

        for (const line of lines) {
          const colonIdx = line.search(/[：:]/);
          if (colonIdx === -1) continue;
          const label = line.substring(0, colonIdx).replace(/[*#\s「」]/g, '');
          const rawValue = line.substring(colonIdx + 1);
          const value = cleanValue(rawValue);
          if (!value || value.length < 2) continue;
          for (const [keywords, en] of labelMap) {
            if (keywords.some(kw => label.includes(kw))) {
              if (!items[en]) items[en] = value;
              break;
            }
          }
        }
        return items;
      }

      const parsedItems = parseOutfitItems(prompt);
      console.log('Parsed outfit items:', parsedItems);

      // Step2: ブランド名→視覚的特徴に変換するマップ（商標・著作権を回避）
      const brandToVisual = {
        // トップス
        'nike dri-fit': 'white athletic t-shirt with grey diagonal panel, no logo',
        'nike': 'white athletic t-shirt, no logo',
        'ナイキ tシャツ': 'white athletic t-shirt with grey panel, no brand logo',
        'supreme': 'red t-shirt with small rectangular text print on chest',
        'シュプリーム': 'red t-shirt with small rectangular logo print on chest',
        'stussy': 'white t-shirt with script logo graphic',
        'ステューシー': 'white t-shirt with script logo graphic',
        'palace': 'graphic print t-shirt streetwear style',
        'off-white': 'white t-shirt with diagonal stripe print',
        'fear of god': 'oversized beige t-shirt minimal style',
        'essentials': 'oversized beige t-shirt with small text logo',
        'polo': 'polo shirt with small embroidered logo',
        'ポロ': 'polo shirt classic style',
        'lacoste': 'polo shirt pastel color',
        'ラコステ': 'polo shirt pastel color',
        'uniqlo': 'simple clean crew neck t-shirt',
        'ユニクロ': 'simple clean crew neck t-shirt',
        // ボトムス
        'carhartt detroit': 'tan duck canvas chore coat: boxy fit, large chest patch pockets, straight hem, workwear jacket',
        'carhartt wip': 'tan canvas work jacket: relaxed fit, chest pockets, collar, workwear style',
        'carhartt': 'tan beige canvas workwear jacket: boxy fit, chest pockets, sturdy fabric',
        'カーハート wip': 'tan canvas work jacket: relaxed fit, chest pockets, workwear jacket',
        'カーハート': 'tan beige canvas workwear jacket: boxy fit, chest pockets, sturdy fabric',
        'baggy denim': 'loose baggy fit light wash denim jeans',
        'バギーデニム': 'loose baggy fit light wash denim jeans wide leg',
        'slim denim': 'slim fit dark wash denim jeans',
        'スリムデニム': 'slim fit dark wash denim jeans',
        // シューズ
        'air force 1': 'low-top white leather sneakers: completely flat thin cupsole, very smooth clean leather upper, slightly boxy square toe shape, perforations on toe cap, low profile silhouette, NOT chunky',
        'エアフォース': 'low-top white leather sneakers: flat thin sole, smooth clean leather, boxy toe, low profile, minimal design',
        'air jordan 1': 'high-top canvas and leather sneakers reaching above ankle: thick flat sole, bold colorblock leather panels, prominent heel collar, retro basketball look',
        'エアジョーダン': 'high-top sneakers above ankle: thick sole, colorful leather panels, retro basketball silhouette',
        'new balance 574': 'chunky retro dad sneakers: very thick layered foam midsole with horizontal ridges, mixed suede and mesh upper, large N letter on side, grey and white colorway, wide silhouette',
        'new balance 990': 'premium chunky grey running sneakers: extremely thick multi-layer cushioned midsole, pigskin suede upper with mesh, rounded toe, dad shoe silhouette',
        'ニューバランス': 'chunky retro running sneakers: thick layered midsole with ridges, suede and mesh upper, large N logo area on side panel, grey tones',
        'adidas samba': 'low-top black and white sneakers gum sole',
        'samba': 'low-top black and white sneakers gum sole',
        'adidas stan smith': 'white leather tennis shoes green detail',
        'vans': 'canvas low-top skate shoes with side stripe',
        'converse': 'canvas high-top sneakers white rubber sole',
        'コンバース': 'canvas high-top sneakers white rubber sole',
        'loafer': 'black leather loafer dress shoes',
        'ローファー': 'black leather loafer shoes',
        // バッグ
        'porter tanker': 'glossy black nylon shoulder bag with multiple exterior zip pockets, silver zippers, functional military style, medium size',
        'porter tote': 'black nylon tote bag with zip top closure, structured rectangular shape, silver hardware',
        'porter day': 'black nylon backpack with multiple compartments, padded back panel, silver zippers',
        'porter': 'black nylon messenger bag with front zip pocket, adjustable strap, functional design',
        'ポーター タンカー': 'glossy black nylon shoulder bag with multiple exterior zip pockets, silver zippers, medium size',
        'ポーター': 'black nylon shoulder bag with zip pockets, silver hardware',
        'longchamp le pliage': 'foldable nylon tote bag with leather flap closure and leather handles, lightweight compact',
        'longchamp': 'nylon tote bag with leather handles and snap closure',
        'ロンシャン': 'nylon tote bag with leather handles',
        'tote': 'canvas tote bag with open top, simple rectangular shape',
        'トートバッグ': 'canvas tote bag with shoulder handles',
        'トート': 'canvas tote bag with handles',
        'リュック': 'casual backpack with front pocket and padded straps',
        'バックパック': 'urban backpack with laptop compartment, minimal design',
        'クラッチ': 'slim clutch bag held under arm, minimal design',
        'ショルダーバッグ': 'small shoulder bag with adjustable strap, crossbody style',
        'サコッシュ': 'thin flat crossbody bag with single zip, lightweight nylon',
        'ボストンバッグ': 'cylindrical duffle bag with top handles and shoulder strap',
        // 時計
        'g-shock': 'square black digital watch thick rubber strap',
        'gショック': 'square black digital watch thick rubber strap',
        'g shock': 'square black digital watch thick rubber strap',
        'rolex': 'luxury metal bracelet watch round dial',
        'ロレックス': 'luxury metal bracelet watch round dial',
        // アクセサリー
        'chrome hearts': 'heavy silver ring gothic cross design',
        'クロムハーツ': 'heavy silver ring gothic design',
        'chain necklace': 'silver chain necklace',
        'チェーンネックレス': 'silver chain necklace',
        'シルバーチェーン': 'silver chain necklace',
      };

      function toVisual(text) {
        if (!text) return text;
        const lower = text.toLowerCase();
        for (const [key, visual] of Object.entries(brandToVisual)) {
          if (lower.includes(key.toLowerCase())) return visual;
        }
        // マッチしない場合はそのまま（日本語でもDALL-E 3は理解できる）
        return text;
      }

      const itemLines = [];
      if (parsedItems.outer) itemLines.push(`outerwear: ${toVisual(parsedItems.outer)}`);
      if (parsedItems.top) itemLines.push(`top: ${toVisual(parsedItems.top)}`);
      if (parsedItems.bottom) itemLines.push(`bottom: ${toVisual(parsedItems.bottom)}`);
      if (parsedItems.shoes) itemLines.push(`shoes: ${toVisual(parsedItems.shoes)}`);
      if (parsedItems.bag) itemLines.push(`bag: ${toVisual(parsedItems.bag)}`);
      if (parsedItems.watch) itemLines.push(`watch on left wrist: ${toVisual(parsedItems.watch)}`);
      if (parsedItems.accessories) itemLines.push(`accessories: ${toVisual(parsedItems.accessories)}`);

      // Step3: DALL-E 3で画像生成
      const generateImage = (outfitDesc) => {
          const genderJp = gender === 'メンズ' ? 'Japanese male fashion model' : gender === 'レディース' ? 'Japanese female fashion model' : 'Japanese fashion model';
          // DALL-E 3はブランド名を拒否する場合があるため、視覚的特徴を中心にした英語プロンプトを使用
          const finalPrompt = `Fashion catalog photography. Pure white background. ${genderJp} standing in center frame. COMPOSITION: full body from top of head to bottom of shoes — head fully visible at top, shoes fully visible at bottom, nothing cropped. Camera at medium distance showing entire figure. Outfit (show ALL items completely, nothing hidden or cropped): ${outfitDesc}. Do NOT add unlisted items. Neutral relaxed standing pose, arms slightly away from body so all items are visible.`;
          console.log('Final image prompt:', finalPrompt);

          const imagePayload = JSON.stringify({
            model: 'gpt-image-1',
            prompt: finalPrompt,
            n: 1,
            size: '1024x1536',
            quality: 'medium',
          });

          const imageOptions = {
            hostname: 'api.openai.com',
            path: '/v1/images/generations',
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${OPENAI_API_KEY}`,
              'Content-Length': Buffer.byteLength(imagePayload),
            },
          };

          const imageReq = https.request(imageOptions, (imageRes) => {
            let imageData = '';
            imageRes.on('data', chunk => { imageData += chunk; });
            imageRes.on('end', () => {
              try {
                const parsed = JSON.parse(imageData);
                if (parsed.error) {
                  console.error('OpenAI image error:', parsed.error.message);
                  // ブランド名フィルターエラーの場合、ブランド名なしで再試行
                  if (parsed.error.code === 'content_policy_violation' || parsed.error.message.includes('safety')) {
                    console.log('Retrying without brand names...');
                    const safeParts = [];
                    if (parsedItems.top) safeParts.push(`top: ${parsedItems.top.replace(/[A-Za-z]+/g, '').trim() || 't-shirt'}`);
                    if (parsedItems.bottom) safeParts.push(`bottom: ${parsedItems.bottom.replace(/[A-Za-z]+/g, '').trim() || 'pants'}`);
                    if (parsedItems.shoes) safeParts.push('shoes: sneakers');
                    if (parsedItems.bag) safeParts.push('bag: shoulder bag');
                    generateImage(safeParts.join(', '));
                    return;
                  }
                  res.writeHead(500);
                  res.end(JSON.stringify({ error: parsed.error.message }));
                  return;
                }
                const b64 = parsed.data[0].b64_json;
                const imageUrl = `data:image/png;base64,${b64}`;
                if (parsed.data[0].revised_prompt) {
                  console.log('DALL-E revised prompt:', parsed.data[0].revised_prompt);
                }
                res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
                res.end(JSON.stringify({ imageUrl }));
              } catch (e) {
                console.error('Image parse error:', e.message);
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Image generation failed' }));
              }
            });
          });

          imageReq.on('error', (e) => { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); });
          imageReq.write(imagePayload);
          imageReq.end();
      };

      const outfitDesc = itemLines.length > 0 ? itemLines.join('、') : 'スタイリッシュなカジュアルコーデ';
      generateImage(outfitDesc);
    });

  // 服の写真解析（GPT-4o Vision）
  } else if (req.method === 'POST' && req.url === '/analyze-clothing') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const { imageBase64 } = JSON.parse(body);

      const payload = JSON.stringify({
        model: 'gpt-4o',
        max_tokens: 300,
        messages: [{
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
            { type: 'text', text: 'この服の画像を分析して、以下のJSON形式のみで回答してください：{"category":"トップス/ボトムス/アウター/シューズ/バッグ/アクセサリーのいずれか","color":"色","description":"アイテム名（例：白いTシャツ）","brand":"ブランド名（不明なら空文字）"}' }
          ]
        }]
      });

      const options = {
        hostname: 'api.openai.com',
        path: '/v1/chat/completions',
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
            const text = parsed.choices[0].message.content;
            const jsonMatch = text.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
              res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
              res.end(jsonMatch[0]);
            } else {
              res.writeHead(500);
              res.end(JSON.stringify({ error: '解析失敗' }));
            }
          } catch (e) {
            res.writeHead(500);
            res.end(JSON.stringify({ error: e.message }));
          }
        });
      });
      apiReq.on('error', (e) => { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); });
      apiReq.write(payload);
      apiReq.end();
    });

  // 天気取得
  } else if (req.method === 'POST' && req.url === '/weather') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const { lat, lon } = JSON.parse(body);
      const url = `https://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${lon}&appid=${OPENWEATHER_API_KEY}&units=metric&lang=ja`;

      https.get(url, (apiRes) => {
        let data = '';
        apiRes.on('data', chunk => { data += chunk; });
        apiRes.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            const weather = {
              temp: Math.round(parsed.main.temp),
              feels_like: Math.round(parsed.main.feels_like),
              description: parsed.weather[0].description,
              city: parsed.name,
              humidity: parsed.main.humidity,
            };
            res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
            res.end(JSON.stringify(weather));
          } catch (e) {
            res.writeHead(500);
            res.end(JSON.stringify({ error: '天気取得失敗' }));
          }
        });
      }).on('error', (e) => {
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      });
    });

  } else {
    res.writeHead(404);
    res.end();
  }
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`StyleMind プロキシサーバー起動中: http://localhost:${PORT}`);
  console.log('Ctrl+C で停止');
});
