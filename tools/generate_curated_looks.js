// 「あなたにおすすめのコーデ」フィード用の画像を一括生成するスクリプト。
//
// 実際の本番/chat・/generate-imageを呼び出し、骨格タイプ×スタイルの
// 組み合わせごとにコーデ画像を生成し、assets/curated_looks/ に保存する。
// 生成結果のメタデータは lib/curated_looks_data.dart に手動で反映する。
//
// 使い方: node tools/generate_curated_looks.js

const fs = require('fs');
const path = require('path');

const CHAT_URL = 'https://stylemind-proxy-production.up.railway.app/chat';
const IMAGE_URL = 'https://stylemind-proxy-production.up.railway.app/generate-image';
const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'curated_looks');

const looks = [
  { id: 'look_01', gender: 'レディース', skeletonType: 'ウェーブタイプ', styles: 'フェミニン/ガーリー', question: '週末のカフェデートに着ていく、フェミニンなコーデを教えて' },
  { id: 'look_02', gender: 'レディース', skeletonType: 'ストレートタイプ', styles: 'クワイエットラグジュアリー', question: 'オフィスカジュアルで浮かない、上品なコーデを教えて' },
  { id: 'look_03', gender: 'レディース', skeletonType: 'ナチュラルタイプ', styles: 'カジュアル', question: '週末に友達と出かける、リラックスしたカジュアルコーデを教えて' },
  { id: 'look_04', gender: 'メンズ', skeletonType: 'ストレートタイプ', styles: 'ミニマル/シンプル', question: '通勤・通学で使える、ミニマルできれいめなコーデを教えて' },
  { id: 'look_05', gender: 'メンズ', skeletonType: 'ウェーブタイプ', styles: 'ストリート', question: '友達と遊びに行く時のストリート系コーデを教えて' },
  { id: 'look_06', gender: 'メンズ', skeletonType: 'ナチュラルタイプ', styles: 'カジュアル/アメカジ', question: '大学に着ていく、こなれたアメカジコーデを教えて' },
  { id: 'look_07', gender: 'レディース', skeletonType: 'ウェーブタイプ', styles: '韓国系/オルチャン', question: '韓国系オルチャンっぽい、今っぽいコーデを教えて' },
  { id: 'look_08', gender: 'メンズ', skeletonType: 'ストレートタイプ', styles: 'ストリート', question: '友達とスケボーに行く時のストリート系コーデを教えて' },
  { id: 'look_09', gender: 'レディース', skeletonType: 'ナチュラルタイプ', styles: 'モード/アバンギャルド', question: '個性を出したい日のモード系コーデを教えて' },
  { id: 'look_10', gender: 'メンズ', skeletonType: 'ナチュラルタイプ', styles: 'ゴープコア/アウトドア', question: 'キャンプに着ていく、アウトドア系のコーデを教えて' },
];

async function getChatReply(question, userProfile) {
  const res = await fetch(CHAT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ messages: [{ role: 'user', content: question }], userProfile }),
  });
  const data = await res.json();
  return data.reply;
}

async function getGeneratedImage(replyText, userProfile) {
  const res = await fetch(IMAGE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt: replyText, userProfile }),
  });
  const data = await res.json();
  if (!data.imageUrl) throw new Error('画像生成失敗: ' + JSON.stringify(data));
  const b64 = data.imageUrl.split(',')[1];
  return Buffer.from(b64, 'base64');
}

(async () => {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const metadata = [];

  for (const look of looks) {
    console.log(`生成中: ${look.id} (${look.gender}/${look.skeletonType}/${look.styles}) ...`);
    const userProfile = {
      gender: look.gender,
      age: '20代前半',
      height: look.gender === 'メンズ' ? '171〜175cm' : '161〜165cm',
      bodyType: '標準',
      skeletonType: look.skeletonType,
      styles: look.styles,
    };
    try {
      const reply = await getChatReply(look.question, userProfile);
      const imageBuf = await getGeneratedImage(reply, userProfile);
      const imgPath = path.join(OUTPUT_DIR, `${look.id}.png`);
      fs.writeFileSync(imgPath, imageBuf);
      metadata.push({ ...look, reply });
      console.log(`  完了: ${imgPath}`);
    } catch (e) {
      console.error(`  失敗: ${look.id} — ${e.message}`);
    }
  }

  fs.writeFileSync(path.join(OUTPUT_DIR, 'metadata.json'), JSON.stringify(metadata, null, 2), 'utf8');
  console.log('全パターン完了！metadata.jsonを確認してください。');
})();
