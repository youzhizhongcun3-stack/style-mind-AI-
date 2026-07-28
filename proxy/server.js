const http = require('http');
const https = require('https');
require('dotenv').config();

const CLAUDE_API_KEY = process.env.CLAUDE_API_KEY || '';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || '';
const OPENWEATHER_API_KEY = process.env.OPENWEATHER_API_KEY || '';

// チャット返答からアイテムをパースする共通ロジック（/chatの重複回避記録と
// /generate-imageの画像生成プロンプト作成の両方で使うため、モジュール直下に配置）
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

const OUTFIT_LABEL_MAP = [
  [['トップス', 'シャツ', 'Tシャツ', 'ニット', 'カットソー', 'ポロ'], 'top'],
  [['ボトムス', 'パンツ', 'デニム', 'ジーンズ', 'ショーツ', 'スカート', 'チノ', 'スラックス'], 'bottom'],
  [['アウター', 'ジャケット', 'コート', 'パーカー', 'ブルゾン', 'フーディ', 'ダウン', 'ブレザー'], 'outer'],
  [['靴', 'シューズ', 'スニーカー', 'ブーツ', 'サンダル', 'ローファー', '足元', 'フットウェア'], 'shoes'],
  [['バッグ', 'カバン', 'バック', 'リュック', 'トート', 'ショルダー', 'クラッチ'], 'bag'],
  [['時計', 'ウォッチ'], 'watch'],
  [['リング', 'ネックレス', 'ブレスレット', 'アクセサリー', '小物', 'チェーン', 'ピアス'], 'accessories'],
  [['ヘアスタイル', '髪型', 'ヘア'], 'hair'],
  [['カラコン', 'カラーコンタクト', 'コンタクト'], 'contacts'],
];

function parseOutfitItems(text) {
  const items = {};
  const lines = text.split('\n');
  for (const line of lines) {
    const colonIdx = line.search(/[：:]/);
    if (colonIdx === -1) continue;
    const label = line.substring(0, colonIdx).replace(/[*#\s「」]/g, '');
    const rawValue = line.substring(colonIdx + 1);
    const value = cleanValue(rawValue);
    if (!value || value.length < 2) continue;
    for (const [keywords, en] of OUTFIT_LABEL_MAP) {
      if (keywords.some(kw => label.includes(kw))) {
        if (!items[en]) items[en] = value;
        break;
      }
    }
  }
  return items;
}

// 同じ質問に対してAIが毎回同じ定番アイテムに収束してしまう問題への構造的対策。
// ランダムな「方向性ヒント」だけだと、対策後も別の1アイテムに偏りが移る
// (もぐら叩き)ことが監査で判明したため、実際に直近提案したアイテムをカテゴリ別に
// プロセスメモリ上で記憶し、次のリクエストで「これは避けて」と明示的に伝える。
// サーバー再起動でリセットされる軽量な仕組み(DBは使わない)。
const RECENT_SUGGESTIONS_LIMIT = 5;
const recentSuggestions = { top: [], bottom: [], outer: [], shoes: [], bag: [], accessories: [] };

function recordRecentSuggestions(items) {
  for (const cat of Object.keys(recentSuggestions)) {
    const val = items[cat];
    if (!val) continue;
    const list = recentSuggestions[cat];
    if (list[list.length - 1] === val) continue; // 直前と全く同じ文字列の重複記録は避ける
    list.push(val);
    if (list.length > RECENT_SUGGESTIONS_LIMIT) list.shift();
  }
}

function buildAvoidRepeatContext() {
  const parts = [];
  const jpLabel = { top: 'トップス', bottom: 'ボトムス', outer: 'アウター', shoes: '靴', bag: 'バッグ', accessories: 'アクセサリー' };
  for (const [cat, list] of Object.entries(recentSuggestions)) {
    if (list.length === 0) continue;
    parts.push(`${jpLabel[cat]}: ${list.join(' / ')}`);
  }
  if (parts.length === 0) return '';
  return `\n【直近ほかのリクエストで提案したばかりのアイテム（同じ質問への回答は特に、できる限りこれらと違うアイテムを選ぶこと）】\n${parts.join('\n')}`;
}

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
    let bodyChunks = [];
    req.on('data', chunk => { bodyChunks.push(chunk); });
    req.on('end', () => {
      const body = Buffer.concat(bodyChunks).toString('utf8');
      let parsedBody;
      try {
        parsedBody = JSON.parse(body);
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: 'リクエストの形式が不正です' }));
        return;
      }
      const { messages, userProfile, closetSummary } = parsedBody;
      const recentMessages = messages.slice(-8);
      const ngContext = userProfile?.ngItems ? `\n【NGアイテム・絶対に提案禁止】${userProfile.ngItems}` : '';
      const now = new Date();
      const month = now.getMonth() + 1;
      const season = month >= 3 && month <= 5 ? '春（3〜5月）軽めのアウター、トレンチコート、パステルカラー向き' :
                    month >= 6 && month <= 8 ? '夏（6〜8月）半袖・薄手素材・リネン・涼しいコーデ向き' :
                    month >= 9 && month <= 11 ? '秋（9〜11月）レイヤード・秋色・ニット・チェック向き' :
                    '冬（12〜2月）ダウン・厚手コート・ウール・防寒コーデ向き';
      const profileContext = userProfile ? `\n【ユーザー情報】性別:${userProfile.gender||'未設定'} 年齢:${userProfile.age||'未設定'} 身長:${userProfile.height||'未設定'} 体型:${userProfile.bodyType||'未設定'} 骨格タイプ:${userProfile.skeletonType||'未設定'} 好きなスタイル:${userProfile.styles||'未設定'} 好きなブランド:${userProfile.brands||'未設定'} 予算:${userProfile.budget||'未設定'}${ngContext}` : '';
      const seasonContext = `\n【現在の季節】${season} ※季節に合わせたアイテム・素材を必ず提案すること`;
      const closetContext = closetSummary ? `\n\n【ユーザーの手持ち服（クローゼット）】\n${closetSummary}\n※手持ち服を活用したコーデ提案を優先すること。新規購入アイテムを追加する場合は手持ち服と相性の良いものを提案すること` : '';

      // 同じような質問でも毎回似たブランド・アイテムに偏ってしまう問題への対策。
      // 「毎回異なる提案をする」という抽象的な指示だけではAIは同じ定番アイテムに
      // 収束しがちなため、サーバー側で具体的な方向性をランダムに選んで強制する。
      // ヒントを1個だけ選ぶ方式だと、狙ったカテゴリ（例：靴）にヒットする確率が
      // 1/8しかなく、ヒットしなかった大半のリクエストでは結局デフォルトの定番
      // アイテム（Nike Air Force 1、Longchamp Le Pliage等）に収束してしまうことが
      // 監査で判明したため、2個を重複なく選んで反映率を倍にする。
      const varietyHints = [
        'バッグの選択肢を広げること。ポーターやロンシャンに偏らず、エコバッグ・サコッシュ・トートバッグ・ボディバッグ・かごバッグ・マークジェイコブスのトートなど、いつもと違う形状を積極的に検討する',
        'トップスに、定番ブランド（ユニクロ・ステューシー等）だけでなく、あまり出てこないブランドも1つ取り入れる（例：パレス、アワーレガシー、Aime Leon Dore等）',
        '差し色として、ベージュ・カーキ・ブラウン系の落ち着いた配色を軸にする',
        '差し色として、鮮やかな1色（オレンジ・ブルー・イエロー等）をアクセントに入れる',
        '靴の選択を、Nike Air Force 1に偏らず、Adidas Samba・Stan Smith・New Balance・ローファー・サンダル・ブーツ等、季節に応じて積極的に検討する',
        'シンプル・ミニマルな配色（黒・白・グレーの3色以内）でまとめる方向にする',
        '柄物やオーバーサイズアイテムなど、少し個性的なアイテムを1点取り入れる',
        'ネックレス・リング・イヤリングなど、アクセサリーで個性を出す提案にする',
      ];
      const shuffledHints = [...varietyHints].sort(() => Math.random() - 0.5);
      const selectedHints = shuffledHints.slice(0, 2);
      const varietyContext = `\n【今回の提案の方向性（このリクエスト限定のランダム指定、2つとも反映する）】${selectedHints.join(' / ')}`;
      const avoidRepeatContext = buildAvoidRepeatContext();

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
・Fjallraven Kanken：四角いフォルム、狐のロゴワッペン、丈夫なビニロン素材、豊富なカラー展開のリュック
・BAGGU：ナイロン製の軽量エコバッグ、シンプルな無地、豊富なカラー展開、折りたたんでポーチにもなる
・Eastpak Padded Pak'r：スクエア型のリュック、パデッド肩ひも、豊富なカラー・柄展開のカジュアルバックパック
・A.P.C. サコッシュ：薄型のミニショルダーバッグ、シンプルなロゴプレート、スマホと財布程度が入る小型サイズ
・マーク ジェイコブス ザ・トートバッグ：キャンバス地に大きめロゴプリント、しっかりした台形フォルム、太めのウェビングハンドル
・かごバッグ（バスケットバッグ）：天然素材の編み込みバスケット型、丸みのあるフォルム、夏の定番フェミニンアイテム
・フルラ：コンパクトな本革ハンドバッグ、メタルロゴプレート、上品で女性らしい佇まい
・クロムハーツ：シルバー925の重厚ジュエリー、十字架・短剣・フルールドリスのモチーフ、ゴシック
・カシオ G-Shock DW-5600：四角いデジタル表示、厚みのある黒ラバーベルト、80年代レトロ感
・カシオ エディフィス：スポーティで先進的なデザインの3針アナログ、金属ベルト、20代男性のビジネス〜オフィスカジュアル向け高コスパブランド
・シチズン アテッサ：日本製ビジネスウォッチ、シンプルな3針、シルバー×ブラック文字盤、価格帯は控えめで新社会人にも人気
・ダニエル ウェリントン：薄型ミニマルデザイン、レザーまたはメッシュベルト、男女問わずSNSで人気の定番オフィス向け時計
・タイメックス：シンプルで手頃な価格、カジュアル〜オフィスカジュアルまで幅広く使える万能時計
・ロレックス サブマリーナー：緑または黒ベゼルの高級ダイバーズウォッチ、メタルブレスレット（価格が非常に高いため、若い世代・予算重視の提案では基本的に避け、上記のような手頃なブランドを優先すること）
・Polo Ralph Lauren：胸に小さなポロプレイヤー刺繍、定番ポロシャツ・チノパン
・Lacoste：胸に小さなワニ（クロコダイル）刺繍のポロシャツ

【ヘアスタイル・カラコン・ピアスの知識（トータルスタイリング）】
・メンズヘア系統：ツーブロック（清潔感・王道）/マッシュ（柔らかい印象）/センターパート（今っぽい・韓国系）/ミニマルショート（爽やか）/パーマスタイル（動きのある印象）
・レディースヘア系統：ボブ（清楚・扱いやすい）/レイヤーロング（華やか）/シースルーバング（今っぽい）/ウルフカット（個性的）/お団子・ハーフアップ（TPO問わず使える）
・カラコン：ナチュラルブラウン系（初心者向け・自然で日常使いしやすい）/グレー・ヘーゼル系（少し個性を出したい人向け）/ブルー・グリーン系（強めの個性、パーティーやイベント向け、日常使いにはやや上級者向け）
・ピアス：シンプルスタッズ（清潔感重視・オフィスOK）/フープ（こなれ感）/フェイクピアス（穴を開けたくない人向け）
・メイク系統（レディース中心）：ナチュラルメイク/韓国風オルチャンメイク/ガーリーメイク/クールモードメイク

【大学生・学生のコーデがOLっぽくなりすぎないための黄金比】
・大学生（10代後半〜20代前半）向けの提案では「カジュアル6：きれいめ4」の黄金比を意識する（きれいめアイテムを主体にしすぎるとOL・オフィスカジュアルに寄ってしまう）
・シャツ・ブラウスなど「きれいめ」なトップスを使う場合、ボトムスや靴で必ずカジュアル要素を1つ以上足してバランスを取る。例：きれいめシャツ×ワイドデニム×スニーカー、甘めブラウス×スニーカー、シャツ×スカート×スニーカーまたはブーツ
・靴はパンプス・ヒールをデフォルトにしない。大学生の私服では白・オフホワイト系のローカットスニーカーが基本形で、きれいめにまとめたい時だけブーツやローファーを選択肢にする（パンプスは提案が明確に「オフィス」「フォーマル」等を求めている場合のみ）
・スカートを提案する場合、タイトなミニ丈だけに偏らない。ワイドデニムやミモレ丈スカートなど、体のラインを強調しすぎないシルエットも選択肢に含める
・色数は3色以内に抑える。ベーシックカラー中心で、差し色は1点までに留めると学生らしい抜け感が出る

【プチプラブランド（GU・ユニクロ・ZARA等）を高見えさせる着こなしテクニック】
・トップスの裾を片側だけ軽く出す「ハーフタック」で、シンプルな無地アイテムでも今っぽい抜け感を出す
・ベルトでウエストマークし、ゆったりニットやシャツでもメリハリのあるシルエットを作る
・マットな素材×光沢のある素材など、質感の違うアイテムを組み合わせて安っぽさを回避する
・色数を3色以内、特に同系色でまとめる「トーンオントーン」でプチプラでも上品にまとまる
・バッグ・靴・アクセサリーのうち1点だけ質感の良いもの（本革・上質な金具等）を選ぶと全体の格が上がる
・裾上げ・袖丈調整などサイズ感を体に合わせるだけでプチプラでも高見えする
・予算重視の提案（ユーザーが「プチプラで」「安く」等と言った場合や予算設定が低い場合）では、これらのテクニックを積極的に活用すること

【SNS(Instagram/TikTok)でいいね・保存されやすいコーデの傾向】
・全身が1枚で見える構図を意識し、上下でサイズ感・色のメリハリをつけた提案は反応が良い（例：オーバーサイズトップス×スリムボトム、またはその逆）
・「主役アイテムを1点決め、他は控えめにする」構成は保存されやすい（主役はアウター・バッグ・アクセサリーいずれでも良い）
・季節感が明確に伝わる色・素材の組み合わせ（真夏はリネン×淡色、秋は異素材レイヤード）は人気が出やすい
・2026年トレンドカラー（ラベンダー・ミントグリーン・モカムース等）を1点取り入れると新鮮感が出て反応が良くなりやすい
・これらは提案の質を上げるための参考知識であり、無理に全て詰め込む必要はない

【骨格タイプ別シルエットガイド】
・ストレートタイプ（筋肉にハリ・厚みがあり上重心）：Iラインシルエットが得意。ハリのある素材、Vネック、シンプルな一枚仕立てを軸にする。オーバーサイズを着ると着太りしやすいので避ける
・ウェーブタイプ（骨が華奢で曲線的、下重心）：Xラインシルエットが得意。とろみ素材、ハイウエスト、小さめ柄を軸にする。ハリのあるかっちりした素材やビッグシルエットは着られている印象になるので避ける
・ナチュラルタイプ（骨・関節がしっかりして直線的）：ゆったりシルエットが得意。ラフな素材、オーバーサイズ、ざっくりニットを軸にする。タイトでかっちりした素材は骨格が目立ちすぎるので避ける

【2026年トレンド知識】
・スタイル系統：ミニマルシック/Y2Kリバイバル/ゴープコア/バレアコア/クワイエットラグジュアリー/ストリート/モード/韓国系オルチャン/サブカル/フェミニン/マスキュリン/ジェンダーレス
・人気ブランド（高感度）：アクネ ストゥディオズ/マルニ/トットペリー/ジルサンダー/メゾンマルジェラ/ステューシー/シュプリーム/パレス/アワーレガシー/コモンプロジェクト
・人気ブランド（プチプラ〜ミドル）：ユニクロ/GU/ZARA/H&M/アーバンリサーチ/ビームス/シップス/ナノユニバース/マウジー/スナイデル/ジャーナルスタンダード/無印良品/COS/GAP
・注目アイテム：バギーデニム/ローライズパンツ/オーバーサイズブレザー/カーゴパンツ/ニットベスト/プラットフォームシューズ/チャンキーローファー/ボアジャケット/レザートレンチ
・カラートレンド：モカムース/バーントオレンジ/コバルトブルー/チェリーレッド/ピスタチオグリーン/オフホワイト/ミルクチョコ

【2026年下半期・最新トレンド追記（Pinterest/TikTok/Instagram調査に基づく、2026-07-21更新）】
・平成女児/Y3K：厚底ローファー、缶バッジ、リボン、量産型ヘアに、SF・コズミックな近未来モチーフ（Y3K）を組み合わせたスタイルがZ世代で急浮上。Y2Kより一段幼さ・少女漫画的な可愛さを強調するのが特徴
・オフデューティ・バーシティ：スポーツジャージ/野球ジャージー/パッチワークデニム/デニムジョーツなど、スポーティ×カジュアルの掛け合わせが夏の主流
・2026秋冬：ファージャケット（ショート丈・カラーファー）、力の抜けたテーラードジャケット、ウエストをマークするベルテッドデザインが台頭。「ひねり・ずれ・違和感」を効かせた着崩しがムードの核
・韓国系（オルチャン）最新：パデッド/キルティング素材のショルダーバッグが定番化（韓国コーデ投稿の9割がショルダー型）、バタフライ刺繍、ティアードフリルミニスカートが人気
・スニーカー：機能性よりコーディネート映え重視のヒュブリッドシルエット（厚底×クラシックの組み合わせ等）が主流に
・カラー最新：ラベンダー/ミントグリーン/オフホワイトが韓国系春夏コーデで人気急上昇。上記の既存カラートレンドと併用してよい

【返答ルール】
- ユーザーのプロフィール・好みを最優先で参考にする${profileContext}${closetContext}${seasonContext}${varietyContext}${avoidRepeatContext}
- 【今回の提案の方向性】は、そのリクエストだけに適用する一時的な指定。2つとも、無理に不自然にならない範囲で必ず反映すること
- 【直近ほかのリクエストで提案したばかりのアイテム】が示されている場合、そこに書かれたアイテムと同じものを繰り返し提案しないこと。同じカテゴリでも違うブランド・アイテムを選ぶこと
- NGアイテムが設定されている場合は絶対に提案しない。NGアイテムの代替を提案すること
- 体型・身長に合わせたシルエット提案をする。例：小柄→クロップドパンツ/ハイウエスト推奨、がっちり→オーバーサイズで体型カバー、細身→レイヤードで立体感を出す
- 骨格タイプが設定されている場合は、上記【骨格タイプ別シルエットガイド】を体型・身長の提案より優先し、そのタイプが得意なシルエット・素材を軸に提案すること。その上で、提案の最後に「あなたは○○タイプなので、このシルエット（例：ゆったりめ/Iライン等）が得意です」のように、なぜこの形・素材を選んだかの理由を一言添えること（提案への納得感を高めるため。長々とした説明は不要、一文で十分）
- ユーザーが学生（年齢・文脈から大学生・専門学生等と分かる場合）と判断できる時は、上記【大学生・学生のコーデがOLっぽくなりすぎないための黄金比】を必ず適用し、パンプス＋タイトミニ丈スカートのようなオフィスカジュアルに寄った提案を避けること
- 予算重視の提案や学生向けの提案では、上記【プチプラブランドを高見えさせる着こなしテクニック】を適宜活用すること。上記【SNSでいいね・保存されやすいコーデの傾向】も、不自然にならない範囲で参考にすること
- 季節に合わない素材やアイテムは提案しない（例：夏にダウンジャケットは不可）
- 毎回異なるスタイル提案をする。同じ系統を繰り返さない
- 具体的なブランド名・アイテム名を必ず含める
- 季節・シーン・体型・予算に合わせて提案する
- TPOやスタイルに合う場合は、服だけでなくヘアスタイル・カラコン・ピアスなどトータルでの提案も適宜含めること（毎回必須ではなく、自然に合う時だけでよい）。含める場合は必ずテキストに「ヘアスタイル：〇〇」「カラコン：〇〇（色）」のように明記し、画像生成にも反映されるようにすること
- 3〜5行以内で簡潔に。絵文字1〜2個
- ユーザーが「画像生成して」「画像を見たい」「見せて」と言ったら「画像を生成します！少々お待ちください🎨」とだけ答える。絶対に「画像生成はできない」「対応していない」「代わりの方法」などと言ってはいけない。代替手段（PinterestやInstagram等）を提案することも禁止。システムが自動で画像を生成する仕組みになっている
- コーデ提案時にアウター・ジャケットを含める場合は必ずテキストに「アウター：〇〇（ブランド・商品名・価格目安）」と明示すること。画像に出るのにテキストに記載なしは絶対にNG
- コーデ提案には必ずバッグを含めること。バッグは省略禁止。ブランド名・商品名・価格を明記すること
- 時計・シルバーリング・ネックレス・ベルトなどのアクセサリーをコーデに加える場合は必ずテキストに記載し、画像生成にも必ず反映すること。テキストに書いたアクセサリーが画像に出ないのは絶対にNG
- トップスをボトムスにタックイン（裾を入れる）するコーデを提案する場合、特に仕事・オフィスカジュアルなどフォーマル度が高いシーンでは、ベルトも一緒に提案すること（タックインしているのにベルトが無いと着こなしとして不完全に見えるため）
- 💡から始まるような補足コメント・スタイリングTipsを添える場合は、必ず「今回提案した具体的なアイテム」に直接関係する内容にすること。一般論・当たり障りのないアドバイス（例：「トレンドアイテムは1点だけにしましょう」等）を、その提案と無関係に付け加えることは禁止
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
        let dataChunks = [];
        apiRes.on('data', chunk => { dataChunks.push(chunk); });
        apiRes.on('end', () => {
          const data = Buffer.concat(dataChunks).toString('utf8');
          try {
            const parsed = JSON.parse(data);
            const reply = parsed.content[0].text;
            recordRecentSuggestions(parseOutfitItems(reply));
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
    let bodyChunks = [];
    req.on('data', chunk => { bodyChunks.push(chunk); });
    req.on('end', () => {
      const body = Buffer.concat(bodyChunks).toString('utf8');
      let parsedBody;
      try {
        parsedBody = JSON.parse(body);
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: 'リクエストの形式が不正です' }));
        return;
      }
      const { prompt, userProfile } = parsedBody;

      const gender = userProfile?.gender || '';
      const age = userProfile?.age || '20代';
      const bodyType = userProfile?.bodyType || '';
      const skeletonType = userProfile?.skeletonType || '';
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

      let silhouetteDesc = '';
      if (skeletonType.includes('ストレート')) silhouetteDesc = ', wearing an I-line silhouette outfit with structured crisp fabric';
      else if (skeletonType.includes('ウェーブ')) silhouetteDesc = ', wearing an X-line silhouette outfit with soft flowing fabric, high waist';
      else if (skeletonType.includes('ナチュラル')) silhouetteDesc = ', wearing a relaxed loose silhouette outfit with rough natural texture fabric';

      let modelDesc = '';
      if (gender === 'メンズ') {
        modelDesc = `Japanese male model, ${age}, ${heightDesc}, ${bodyDesc}, short hair, masculine appearance, no leg hair, no body hair visible${silhouetteDesc}`;
      } else if (gender === 'レディース') {
        modelDesc = `Japanese female model, ${age}, ${heightDesc}, ${bodyDesc}, feminine appearance${silhouetteDesc}`;
      } else {
        modelDesc = `Japanese model, ${age}, ${heightDesc}, ${bodyDesc}, gender-neutral appearance${silhouetteDesc}`;
      }

      // Step1: チャットテキストからアイテムをパース（cleanValue/parseOutfitItemsはモジュール直下で定義済み）
      const parsedItems = parseOutfitItems(prompt);
      console.log('Parsed outfit items:', parsedItems);

      // Step2: ブランド名→視覚的特徴に変換するマップ（商標・著作権を回避）
      // カテゴリごとに分離（フラットな1つのマップだと「グレー」「ユニクロ」等の短い語が
      // 別カテゴリのテキストにも誤マッチし、スカートがパンツになる等の事故が起きるため）
      const brandToVisual = {
        top: {
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
        },
        outer: {
          'carhartt detroit': 'tan duck canvas chore coat: boxy fit, large chest patch pockets, straight hem, workwear jacket',
          'carhartt wip': 'tan canvas work jacket: relaxed fit, chest pockets, collar, workwear style',
          'carhartt': 'tan beige canvas workwear jacket: boxy fit, chest pockets, sturdy fabric',
          'カーハート wip': 'tan canvas work jacket: relaxed fit, chest pockets, workwear jacket',
          'カーハート': 'tan beige canvas workwear jacket: boxy fit, chest pockets, sturdy fabric',
        },
        bottom: {
          'baggy denim': 'loose baggy fit light wash denim jeans',
          'バギーデニム': 'loose baggy fit light wash denim jeans wide leg',
          'slim denim': 'slim fit dark wash denim jeans',
          'スリムデニム': 'slim fit dark wash denim jeans',
        },
        shoes: {
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
        },
        bag: {
          'porter tanker': 'glossy black nylon shoulder bag with multiple exterior zip pockets, silver zippers, functional military style, medium size',
          'porter tote': 'black nylon tote bag with zip top closure, structured rectangular shape, silver hardware',
          'porter day': 'black nylon backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, multiple compartments, padded back panel, silver zippers',
          'porter': 'black nylon messenger bag with front zip pocket, adjustable strap, functional design',
          'ポーター タンカー': 'glossy black nylon shoulder bag with multiple exterior zip pockets, silver zippers, medium size',
          'ポーター': 'black nylon shoulder bag with zip pockets, silver hardware',
          'longchamp le pliage': 'foldable nylon tote bag with leather flap closure and leather handles, lightweight compact',
          'longchamp': 'nylon tote bag with leather handles and snap closure',
          'ロンシャン': 'nylon tote bag with leather handles',
          'tote': 'canvas tote bag with open top, simple rectangular shape',
          'トートバッグ': 'canvas tote bag with shoulder handles',
          'トート': 'canvas tote bag with handles',
          'リュック': 'casual backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, front pocket and padded straps',
          'バックパック': 'urban backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, laptop compartment, minimal design',
          'fjallraven kanken': 'square-shaped boxy backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, vinylon fabric, small fox logo patch, roll-top style flap, colorful casual design',
          'kanken': 'square-shaped boxy backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, vinylon fabric, small fox logo patch, colorful casual design',
          'カンケン': 'square-shaped boxy backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, vinylon fabric, small fox logo patch, colorful casual design',
          'baggu': 'lightweight nylon eco bag, simple solid color, foldable tote with thin straps',
          'バグゥ': 'lightweight nylon eco bag, simple solid color, foldable tote with thin straps',
          'エコバッグ': 'lightweight nylon foldable tote bag, simple solid color',
          'eastpak': 'square boxy casual backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, padded shoulder straps, colorful or patterned fabric',
          'イーストパック': 'square boxy casual backpack worn on the back, both straps over the shoulders, bag body positioned behind the torso not visible from front, padded shoulder straps, colorful or patterned fabric',
          'サコッシュ': 'thin flat mini crossbody bag, simple logo plate, small size for phone and wallet only',
          'sacoche': 'thin flat mini crossbody bag, simple logo plate, small size for phone and wallet only',
          'クラッチ': 'slim clutch bag held under arm, minimal design',
          'ショルダーバッグ': 'small shoulder bag with adjustable strap, crossbody style',
          'サコッシュ': 'thin flat crossbody bag with single zip, lightweight nylon',
          'ボストンバッグ': 'cylindrical duffle bag with top handles and shoulder strap',
          'マークジェイコブス': 'canvas tote bag with bold logo print, structured trapezoid shape, thick webbing handles',
          'ザ・トートバッグ': 'canvas tote bag with bold logo print, structured trapezoid shape, thick webbing handles',
          'かごバッグ': 'straw woven basket bag with rounded shape and top handles, natural texture',
          'バスケットバッグ': 'straw woven basket bag with rounded shape and top handles, natural texture',
          'フルラ': 'compact structured leather handbag with metal logo plate, top handle',
        },
        watch: {
          'g-shock': 'square black digital watch thick rubber strap',
          'gショック': 'square black digital watch thick rubber strap',
          'g shock': 'square black digital watch thick rubber strap',
          'edifice': 'sporty analog watch with metal bracelet, sleek modern chronograph face',
          'エディフィス': 'sporty analog watch with metal bracelet, sleek modern chronograph face',
          'attesa': 'simple business analog watch, silver metal bracelet, clean white dial',
          'アテッサ': 'simple business analog watch, silver metal bracelet, clean white dial',
          'daniel wellington': 'slim minimalist analog watch with leather strap, small round face',
          'ダニエルウェリントン': 'slim minimalist analog watch with leather strap, small round face',
          'timex': 'simple casual analog watch, canvas or leather strap',
          'タイメックス': 'simple casual analog watch, canvas or leather strap',
          'rolex': 'luxury metal bracelet watch round dial',
          'ロレックス': 'luxury metal bracelet watch round dial',
        },
        accessories: {
          'chrome hearts': 'heavy silver ring gothic cross design',
          'クロムハーツ': 'heavy silver ring gothic design',
          'ゴールドチェーンネックレス': 'gold chain necklace',
          'ゴールドチェーン': 'gold chain necklace',
          'gold chain necklace': 'gold chain necklace',
          'chain necklace': 'silver chain necklace',
          'チェーンネックレス': 'silver chain necklace',
          'シルバーチェーン': 'silver chain necklace',
        },
        contacts: {
          'ナチュラルブラウン': 'natural brown',
          'ブラウン': 'brown',
          'グレー': 'grey',
          'ヘーゼル': 'hazel',
          'ブルー': 'blue',
          'グリーン': 'green',
        },
        hair: {
          'ツーブロック': 'two-block undercut hairstyle, short and neat',
          'マッシュ': 'soft mushroom-cut hairstyle, gentle rounded silhouette',
          'センターパート': 'center-parted hairstyle',
          'パーマ': 'loosely permed textured hairstyle',
          'ボブ': 'chin-length bob haircut',
          'レイヤーロング': 'long layered hairstyle',
          'シースルーバング': 'see-through wispy bangs',
          'ウルフカット': 'wolf-cut hairstyle with layered shaggy texture',
        },
      };

      // "Stüssy"のようなブランド名の装飾的なウムラウト・アクセント記号を除去して
      // 辞書のプレーンASCII表記（'stussy'等）とマッチできるようにする。
      // これが無いと、AIが正式なブランド表記（ü等）を使った時だけ変換に失敗し、
      // 生成画像にロゴ文字をそのまま描画させてしまい文字化けの原因になる。
      function stripDiacritics(s) {
        return s.normalize('NFD').replace(/[̀-ͯ]/g, '');
      }

      // 【重要】brandToVisualの各テンプレートは元々「色固定」の説明文だったため、
      // AIが実際に指定した色（例：黒）と無関係に、テンプレートのデフォルト色
      // （例：白）で画像が生成されてしまうバグがあった（チャットでは黒なのに
      // 画像は白、というユーザー報告で発覚）。実際のテキストから色を抽出し、
      // テンプレート内の色をその色に置き換えることで一致させる。
      const JP_TO_EN_COLOR = [
        ['オフホワイト', 'off-white'], ['オフブラック', 'off-black'],
        ['チャコールグレー', 'charcoal grey'], ['チャコール', 'charcoal grey'],
        ['モスグリーン', 'moss green'], ['カーキ', 'khaki'],
        ['コバルトブルー', 'cobalt blue'], ['ネイビー', 'navy'],
        ['ベージュ', 'beige'], ['テラコッタ', 'terracotta'],
        ['ラベンダー', 'lavender'], ['ミントグリーン', 'mint green'], ['ミント', 'mint green'],
        ['キャメル', 'camel'], ['チョコ', 'dark brown'],
        ['バーガンディ', 'burgundy'], ['ワインレッド', 'wine red'],
        ['オリーブ', 'olive'], ['クリーム', 'cream'], ['タン', 'tan'],
        ['シルバー', 'silver'], ['ゴールド', 'gold'],
        ['ホワイト', 'white'], ['白', 'white'],
        ['ブラック', 'black'], ['黒', 'black'],
        ['グレー', 'grey'], ['グレイ', 'grey'],
        ['ブラウン', 'brown'], ['茶色', 'brown'],
        ['レッド', 'red'], ['赤', 'red'],
        ['ブルー', 'blue'], ['青', 'blue'],
        ['グリーン', 'green'], ['緑', 'green'],
        ['ピンク', 'pink'], ['パープル', 'purple'], ['紫', 'purple'],
        ['イエロー', 'yellow'], ['黄色', 'yellow'],
        ['オレンジ', 'orange'],
      ];
      const ENGLISH_COLOR_WORDS = [
        'off-white', 'off-black', 'charcoal grey', 'moss green', 'cobalt blue',
        'wine red', 'dark brown', 'mint green',
        'white', 'black', 'grey', 'gray', 'navy', 'beige', 'brown', 'red', 'blue',
        'green', 'pink', 'purple', 'yellow', 'orange', 'tan', 'cream', 'khaki',
        'silver', 'gold', 'burgundy', 'olive', 'camel', 'terracotta', 'lavender',
      ];

      function extractColor(text) {
        for (const [jp, en] of JP_TO_EN_COLOR) {
          if (text.includes(jp)) return en;
        }
        return null;
      }

      function applyColorOverride(visual, color) {
        if (!color) return visual;
        for (const word of ENGLISH_COLOR_WORDS) {
          const re = new RegExp('\\b' + word.replace(/[- ]/g, '[- ]?') + '\\b', 'i');
          if (re.test(visual)) return visual.replace(re, color);
        }
        return `${color} ${visual}`;
      }

      function toVisual(text, category) {
        if (!text) return text;
        const lower = stripDiacritics(text.toLowerCase());
        const map = brandToVisual[category] || {};
        const color = extractColor(text);
        for (const [key, visual] of Object.entries(map)) {
          if (lower.includes(stripDiacritics(key.toLowerCase()))) return applyColorOverride(visual, color);
        }
        // マッチしない場合はそのまま（日本語でもDALL-E 3は理解できる）
        return text;
      }

      const itemLines = [];
      if (parsedItems.hair) itemLines.push(`hairstyle: ${toVisual(parsedItems.hair, 'hair')}`);
      if (parsedItems.outer) itemLines.push(`outerwear: ${toVisual(parsedItems.outer, 'outer')}`);
      if (parsedItems.top) itemLines.push(`top: ${toVisual(parsedItems.top, 'top')}`);
      if (parsedItems.bottom) itemLines.push(`bottom: ${toVisual(parsedItems.bottom, 'bottom')}`);
      if (parsedItems.shoes) itemLines.push(`shoes: ${toVisual(parsedItems.shoes, 'shoes')}`);
      if (parsedItems.bag) itemLines.push(`bag: ${toVisual(parsedItems.bag, 'bag')}`);
      if (parsedItems.watch) itemLines.push(`watch on left wrist: ${toVisual(parsedItems.watch, 'watch')}`);
      if (parsedItems.accessories) itemLines.push(`accessories: ${toVisual(parsedItems.accessories, 'accessories')}`);
      if (parsedItems.contacts) itemLines.push(`eyes: wearing ${toVisual(parsedItems.contacts, 'contacts')} colored contact lenses`);

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
            let imageDataChunks = [];
            imageRes.on('data', chunk => { imageDataChunks.push(chunk); });
            imageRes.on('end', () => {
              const imageData = Buffer.concat(imageDataChunks).toString('utf8');
              try {
                const parsed = JSON.parse(imageData);
                if (parsed.error) {
                  console.error('OpenAI image error:', parsed.error.message);
                  // ブランド名フィルターエラーの場合、ブランド名なしで再試行
                  if (parsed.error.code === 'content_policy_violation' || parsed.error.message.includes('safety')) {
                    console.log('Retrying without brand names...');
                    const safeParts = [];
                    if (parsedItems.outer) safeParts.push(`outerwear: ${parsedItems.outer.replace(/[A-Za-z]+/g, '').trim() || 'jacket'}`);
                    if (parsedItems.top) safeParts.push(`top: ${parsedItems.top.replace(/[A-Za-z]+/g, '').trim() || 't-shirt'}`);
                    if (parsedItems.bottom) safeParts.push(`bottom: ${parsedItems.bottom.replace(/[A-Za-z]+/g, '').trim() || 'pants'}`);
                    if (parsedItems.shoes) safeParts.push('shoes: sneakers');
                    if (parsedItems.bag) safeParts.push('bag: shoulder bag');
                    if (parsedItems.watch) safeParts.push('watch on left wrist: simple analog wristwatch');
                    if (parsedItems.accessories) safeParts.push('accessories: simple silver jewelry');
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
    let bodyChunks = [];
    req.on('data', chunk => { bodyChunks.push(chunk); });
    req.on('end', () => {
      const body = Buffer.concat(bodyChunks).toString('utf8');
      let parsedBody;
      try {
        parsedBody = JSON.parse(body);
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: 'リクエストの形式が不正です' }));
        return;
      }
      const { imageBase64 } = parsedBody;

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
        let dataChunks = [];
        apiRes.on('data', chunk => { dataChunks.push(chunk); });
        apiRes.on('end', () => {
          const data = Buffer.concat(dataChunks).toString('utf8');
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

  // 全身コーデ写真の解析・提案（2026-07-20追加）
  } else if (req.method === 'POST' && req.url === '/analyze-outfit') {
    let bodyChunks = [];
    req.on('data', chunk => { bodyChunks.push(chunk); });
    req.on('end', () => {
      const body = Buffer.concat(bodyChunks).toString('utf8');
      let parsedBody;
      try {
        parsedBody = JSON.parse(body);
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: 'リクエストの形式が不正です' }));
        return;
      }
      const { imageBase64, userProfile } = parsedBody;
      if (!imageBase64) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: '画像データがありません' }));
        return;
      }

      const profileContext = userProfile ? `\n【ユーザー情報】性別:${userProfile.gender||'未設定'} 年齢:${userProfile.age||'未設定'} 好きなスタイル:${userProfile.styles||'未設定'}` : '';

      const payload = JSON.stringify({
        model: 'gpt-4o',
        max_tokens: 500,
        messages: [{
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
            { type: 'text', text: `あなたはStyleMind AI、感度の高いファッションスタイリストです。この写真に写っている人の「服装」について、率直でポジティブなフィードバックと改善提案をしてください。${profileContext}

【絶対に守るルール】
- コメント対象は服・靴・バッグ・アクセサリーなど"服装"のみに限定すること
- 顔立ち・髪型・メイク・体型・体重については一切言及しないこと（褒める場合も触れない）
- 人格や外見そのものを否定するような表現は使わないこと
- 3〜5行程度で簡潔に、絵文字1〜2個
- 改善提案をする場合は「トップス：」「ボトムス：」「靴：」のように具体的なアイテム名で提示すること` }
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
        let dataChunks = [];
        apiRes.on('data', chunk => { dataChunks.push(chunk); });
        apiRes.on('end', () => {
          const data = Buffer.concat(dataChunks).toString('utf8');
          try {
            const parsed = JSON.parse(data);
            const reply = parsed.choices[0].message.content;
            res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
            res.end(JSON.stringify({ reply }));
          } catch (e) {
            res.writeHead(500);
            res.end(JSON.stringify({ error: 'Parse error' }));
          }
        });
      });
      apiReq.on('error', (e) => { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); });
      apiReq.write(payload);
      apiReq.end();
    });

  // おすすめブランド・商品一覧（骨格タイプ・スタイル傾向でパーソナライズ）
  } else if (req.method === 'POST' && req.url === '/recommended-items') {
    let bodyChunks = [];
    req.on('data', chunk => { bodyChunks.push(chunk); });
    req.on('end', () => {
      const body = Buffer.concat(bodyChunks).toString('utf8');
      let parsedBody;
      try {
        parsedBody = JSON.parse(body);
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: 'リクエストの形式が不正です' }));
        return;
      }
      const skeletonType = parsedBody.skeletonType || '';
      const styles = (parsedBody.styles || '').split('・').filter(Boolean);

      function buildShopUrls(keyword) {
        const encoded = encodeURIComponent(keyword);
        const yahooUrl = encodeURIComponent(`https://shopping.yahoo.co.jp/search?p=${keyword}`);
        const rakutenUrl = encodeURIComponent(`https://search.rakuten.co.jp/search/mall/${keyword}/`);
        return [
          { name: 'Yahoo!ショッピング', icon: '🛍️', url: `https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3774833&pid=892651346&vc_url=${yahooUrl}` },
          { name: 'Rakuten Fashion', icon: '🏪', url: `https://hb.afl.rakuten.co.jp/hgc/556d406f.aeda9c3d.556d4070.99ba5cc0/?pc=${rakutenUrl}&link_type=hybrid_url` },
          { name: 'Amazon', icon: '📦', url: `https://www.amazon.co.jp/s?k=${encoded}&i=fashion&tag=stylemind2026-22` },
          { name: 'セカンドストリート', icon: '♻️', url: 'https://px.a8.net/svt/ejp?a8mat=4B7SH1+4FK6WI+4J34+HWXLD' },
          { name: 'WEAR（コーデ参考）', icon: '📸', url: `https://wear.jp/search/?q=${encoded}` },
        ];
      }

      // 2026-07下半期トレンド調査を反映したキュレーションリスト。
      // 週次のトレンド調査タスク（stylemind-fashion-trend-research）で内容を随時更新していく想定。
      const CATALOG = [
        { brand: 'theory', item: 'ストレートテーパードパンツ', price: '¥28,000', category: 'ボトムス', skeletonTypes: ['ストレートタイプ'], styles: ['クワイエットラグジュアリー', 'ミニマル/シンプル'] },
        { brand: 'ユニクロ', item: 'Uクルーネックカーディガン', price: '¥5,990', category: 'トップス', skeletonTypes: ['ストレートタイプ'], styles: ['ミニマル/シンプル'] },
        { brand: 'コモンプロジェクト', item: 'アキレスロートップ', price: '¥32,000', category: 'シューズ', skeletonTypes: ['ストレートタイプ'], styles: ['クワイエットラグジュアリー'] },
        { brand: 'スナイデル', item: 'フリルブラウス', price: '¥12,000', category: 'トップス', skeletonTypes: ['ウェーブタイプ'], styles: ['フェミニン/ガーリー'] },
        { brand: 'マウジー', item: 'ハイウエストフレアスカート', price: '¥9,900', category: 'ボトムス', skeletonTypes: ['ウェーブタイプ'], styles: ['フェミニン/ガーリー'] },
        { brand: 'NUGU', item: 'キルティングショルダーバッグ', price: '¥8,900', category: 'バッグ', skeletonTypes: ['ウェーブタイプ'], styles: ['韓国系/オルチャン'] },
        { brand: 'ZARA', item: 'バタフライ刺繍デニムショーツ', price: '¥5,990', category: 'ボトムス', skeletonTypes: ['ウェーブタイプ'], styles: ['韓国系/オルチャン', 'Y2K/レトロ'] },
        { brand: 'パタゴニア', item: 'レトロXフリースジャケット', price: '¥24,000', category: 'アウター', skeletonTypes: ['ナチュラルタイプ'], styles: ['ゴープコア/アウトドア'] },
        { brand: 'カーハートWIP', item: 'デトロイトジャケット', price: '¥26,000', category: 'アウター', skeletonTypes: ['ナチュラルタイプ'], styles: ['カジュアル/アメカジ', 'ストリート'] },
        { brand: 'アーバンリサーチ', item: 'オーバーサイズニット', price: '¥9,900', category: 'トップス', skeletonTypes: ['ナチュラルタイプ'], styles: ['ミニマル/シンプル'] },
        { brand: 'シュプリーム', item: 'ボックスロゴフーディ', price: '¥18,000', category: 'トップス', skeletonTypes: [], styles: ['ストリート'] },
        { brand: 'ステューシー', item: 'スクリプトロゴTシャツ', price: '¥9,900', category: 'トップス', skeletonTypes: [], styles: ['ストリート', 'サブカル/古着'] },
        { brand: 'メゾンマルジェラ', item: 'Tabiブーツ', price: '¥135,000', category: 'シューズ', skeletonTypes: [], styles: ['モード/アバンギャルド'] },
        { brand: 'アクネ ストゥディオズ', item: 'オーバーサイズブレザー', price: '¥98,000', category: 'アウター', skeletonTypes: ['ストレートタイプ'], styles: ['モード/アバンギャルド', 'クワイエットラグジュアリー'] },
        { brand: 'ジャーナルスタンダード', item: 'ヴィンテージ風デニムジャケット', price: '¥15,000', category: 'アウター', skeletonTypes: [], styles: ['サブカル/古着', 'カジュアル/アメカジ'] },
        { brand: 'ニューバランス', item: '2002R', price: '¥17,600', category: 'シューズ', skeletonTypes: [], styles: ['ストリート', 'カジュアル/アメカジ'] },
        { brand: 'GU', item: 'バギーデニム', price: '¥3,990', category: 'ボトムス', skeletonTypes: ['ナチュラルタイプ'], styles: ['ストリート', 'カジュアル/アメカジ'] },
        { brand: 'ロンシャン', item: 'ル・プリアージュ トートバッグ', price: '¥25,000', category: 'バッグ', skeletonTypes: [], styles: ['クワイエットラグジュアリー', 'ミニマル/シンプル'] },
      ];

      const scored = CATALOG.map(it => {
        let score = 0;
        if (skeletonType && it.skeletonTypes.includes(skeletonType)) score += 2;
        if (it.skeletonTypes.length === 0) score += 1; // 全タイプ向け汎用アイテムは軽く優先
        const matchedStyles = it.styles.filter(s => styles.includes(s));
        score += matchedStyles.length * 2;
        return { ...it, score };
      });
      scored.sort((a, b) => b.score - a.score);

      const items = scored.map(it => ({
        brand: it.brand,
        item: it.item,
        price: it.price,
        category: it.category,
        shops: buildShopUrls(`${it.brand} ${it.item}`),
      }));

      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ items }));
    });

  // 天気取得
  } else if (req.method === 'POST' && req.url === '/weather') {
    let bodyChunks = [];
    req.on('data', chunk => { bodyChunks.push(chunk); });
    req.on('end', () => {
      const body = Buffer.concat(bodyChunks).toString('utf8');
      let parsedBody;
      try {
        parsedBody = JSON.parse(body);
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: 'リクエストの形式が不正です' }));
        return;
      }
      const { lat, lon } = parsedBody;
      const url = `https://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${lon}&appid=${OPENWEATHER_API_KEY}&units=metric&lang=ja`;

      https.get(url, (apiRes) => {
        let dataChunks = [];
        apiRes.on('data', chunk => { dataChunks.push(chunk); });
        apiRes.on('end', () => {
          const data = Buffer.concat(dataChunks).toString('utf8');
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

process.on('uncaughtException', (e) => {
  console.error('Uncaught exception (server kept alive):', e);
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`StyleMind プロキシサーバー起動中: http://localhost:${PORT}`);
  console.log('Ctrl+C で停止');
});
