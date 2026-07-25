// 「あなたにおすすめのコーデ」フィード用の画像をFirebase Storageにアップロードし、
// Firestoreにメタデータを書き込むシード/更新スクリプト。
//
// 実行前提: proxy/firebase-service-account.json が存在すること
// （Firebase Console → プロジェクトの設定 → サービスアカウント → 新しい秘密鍵の生成）
//
// 使い方: node tools/seed_curated_looks_firestore.js
//
// 週次のトレンド調査タスクから新しいコーデを追加する場合は、
// tools/generate_curated_looks.js で画像を生成した後、このスクリプトの
// LOOKS配列に新しいエントリを追加して再実行する。

const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

const serviceAccountPath = path.join(__dirname, '..', 'proxy', 'firebase-service-account.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('firebase-service-account.json が見つかりません。Firebase Consoleから取得して proxy/ に配置してください。');
  process.exit(1);
}

const app = initializeApp({
  credential: cert(require(serviceAccountPath)),
  storageBucket: 'stylemind-ai-d14ec.firebasestorage.app',
});

const db = getFirestore(app);
const bucket = getStorage(app).bucket();
const IMG_DIR = path.join(__dirname, '..', 'assets', 'curated_looks');

const LOOKS = [
  {
    id: 'look_01', file: 'look_01.jpg',
    title: 'カフェデートのフェミニンコーデ', gender: 'レディース', skeletonType: 'ウェーブタイプ', styles: 'フェミニン/ガーリー',
    items: [
      'トップス：GU リネンコットン半袖ブラウス（ベージュ）¥2,990',
      'ボトムス：ZARA ハイウエストフレアミニスカート（クリーム）¥3,990',
      '靴：Nike Air Force 1（ホワイト）¥9,900',
      'バッグ：かごバッグ（ベージュ×ホワイト）¥4,500',
    ],
    shopKeywords: ['GU リネンブラウス', 'ZARA フレアミニスカート', 'かごバッグ'],
  },
  {
    id: 'look_02', file: 'look_02.jpg',
    title: '上品なオフィスカジュアル', gender: 'レディース', skeletonType: 'ストレートタイプ', styles: 'クワイエットラグジュアリー',
    items: [
      'トップス：アワーレガシー ブークレニット（ミルクチョコ）¥16,500',
      'ボトムス：ユニクロ ハイウエストストレートパンツ（チャコール）¥3,990',
      '靴：Adidas Stan Smith（オフホワイト）¥8,800',
      'バッグ：フルラ メトロポリス（ネイビー）¥34,000',
    ],
    shopKeywords: ['アワーレガシー ニット', 'ユニクロ ストレートパンツ', 'フルラ ハンドバッグ'],
  },
  {
    id: 'look_03', file: 'look_03.jpg',
    title: '週末のリラックスカジュアル', gender: 'レディース', skeletonType: 'ナチュラルタイプ', styles: 'カジュアル',
    items: [
      'トップス：ZARA オーバーサイズリネンシャツ（テラコッタ）¥3,990',
      'ボトムス：ユニクロ バギーワイドアンクルパンツ（グレー）¥2,990',
      '靴：Adidas Stan Smith（オフホワイト）¥8,800',
      'バッグ：マークジェイコブス ザ・トートバッグ（クリーム）¥14,000',
    ],
    shopKeywords: ['ZARA オーバーサイズリネンシャツ', 'ユニクロ バギーパンツ', 'マークジェイコブス トートバッグ'],
  },
  {
    id: 'look_04', file: 'look_04.jpg',
    title: '通勤・通学のミニマルきれいめ', gender: 'メンズ', skeletonType: 'ストレートタイプ', styles: 'ミニマル/シンプル',
    items: [
      'トップス：Aime Leon Dore クルーネックT（オフホワイト）¥12,000',
      'ボトムス：ZARA ハイウエストテーラードトラウザー（黒）¥6,990',
      '靴：Adidas Stan Smith（ホワイト）¥10,000',
      'バッグ：Fjallraven Kanken Totepack（ブラック）¥18,000',
    ],
    shopKeywords: ['Aime Leon Dore Tシャツ', 'ZARA テーラードパンツ', 'Kanken Totepack'],
  },
  {
    id: 'look_05', file: 'look_05.jpg',
    title: '友達と遊ぶストリートコーデ', gender: 'メンズ', skeletonType: 'ウェーブタイプ', styles: 'ストリート',
    items: [
      'トップス：Stussy バックプリントロゴT（ベージュ）¥3,500',
      'ボトムス：ZARA テーパードカーゴパンツ（カーキ）¥3,990',
      '靴：Vans Old Skool（モスグリーン）¥7,700',
      'バッグ：A.P.C. サコッシュ（ベージュ）¥25,000',
    ],
    shopKeywords: ['Stussy Tシャツ', 'ZARA カーゴパンツ', 'Vans Old Skool'],
  },
  {
    id: 'look_06', file: 'look_06.jpg',
    title: '大学向けこなれたアメカジ', gender: 'メンズ', skeletonType: 'ナチュラルタイプ', styles: 'カジュアル/アメカジ',
    items: [
      'トップス：Carhartt WIP デトロイトジャケット（ブラウン）¥18,000',
      'ボトムス：ZARA ストレートレッグデニム（中色ブルー）¥4,990',
      '靴：Adidas Samba（ホワイト×ガムソール）¥10,500',
      'バッグ：Fjallraven Kanken（ターコイズ）¥8,800',
    ],
    shopKeywords: ['Carhartt WIP デトロイトジャケット', 'Adidas Samba', 'Fjallraven Kanken'],
  },
  {
    id: 'look_07', file: 'look_07.jpg',
    title: '2026年夏の韓国系オルチャン', gender: 'レディース', skeletonType: 'ウェーブタイプ', styles: '韓国系/オルチャン',
    items: [
      'トップス：クロップドカットソー（テラコッタピンク）¥1,500〜38,000',
      'ボトムス：ZARA ティアードフリルミニスカート（クリーム）¥6,990',
      '靴：Nike Air Force 1（ホワイト×ベビーピンク）¥11,000',
      'バッグ：BNOTE パデッドキルティングショルダー（ラベンダー）¥8,500',
    ],
    shopKeywords: ['ZARA ティアードミニスカート', 'パデッドキルティングバッグ', 'Nike Air Force 1'],
  },
  {
    id: 'look_08', file: 'look_08.jpg',
    title: 'スケボーセッション向けストリート', gender: 'メンズ', skeletonType: 'ストレートタイプ', styles: 'ストリート',
    items: [
      'トップス：Palace Skateboards クルーネックT（ホワイト）¥8,000',
      'ボトムス：ZARA バギーカーゴパンツ（黒）¥4,990',
      '靴：New Balance 574（コバルトブルー）¥12,000',
      'バッグ：Carhartt WIP ダック地ショルダー（黒）¥8,500',
    ],
    shopKeywords: ['Palace Skateboards Tシャツ', 'New Balance 574', 'Carhartt WIP ショルダーバッグ'],
  },
];

(async () => {
  for (const look of LOOKS) {
    const localPath = path.join(IMG_DIR, look.file);
    if (!fs.existsSync(localPath)) {
      console.error(`  スキップ: ${look.file} が見つかりません`);
      continue;
    }
    const storagePath = `curated_looks/${look.file}`;
    await bucket.upload(localPath, {
      destination: storagePath,
      metadata: { contentType: 'image/jpeg', cacheControl: 'public, max-age=604800' },
    });
    const file = bucket.file(storagePath);
    await file.makePublic();
    const imageUrl = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

    await db.collection('curatedLooks').doc(look.id).set({
      imageUrl,
      title: look.title,
      gender: look.gender,
      skeletonType: look.skeletonType,
      styles: look.styles,
      items: look.items,
      shopKeywords: look.shopKeywords,
      likeCount: 0,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log(`完了: ${look.id} -> ${imageUrl}`);
  }
  console.log('全件完了！');
  process.exit(0);
})();
