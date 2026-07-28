// cleanValue/parseOutfitItemsは、コーデ提案の重複回避や画像生成プロンプト作成の
// 土台になっている純粋関数。過去に文字化けバグ・色不一致バグの温床になった
// パース処理のため、退行を防ぐための最低限のテストを置く。
// 依存ライブラリなしのプレーンなNode assertで書く（このプロジェクトは軽量なプロキシ
// サーバーのみなので、テストのためだけにjest等を追加する必要はない）。
const assert = require('assert');
const { cleanValue, parseOutfitItems } = require('../server.js');

function run(name, fn) {
  try {
    fn();
    console.log(`OK   ${name}`);
  } catch (e) {
    console.error(`FAIL ${name}`);
    console.error(e);
    process.exitCode = 1;
  }
}

run('cleanValue: 太字マークダウンを除去する', () => {
  assert.strictEqual(cleanValue('**ユニクロ エアリズムT**'), 'ユニクロ エアリズムT');
});

run('cleanValue: 価格表記を除去する', () => {
  assert.strictEqual(cleanValue(' ユニクロ Tシャツ ¥1,500'), 'ユニクロ Tシャツ');
});

run('cleanValue: 節約版の注記を除去する', () => {
  assert.strictEqual(
    cleanValue('アクネ スタジオズ Tシャツ（節約版：ユニクロでも可）'),
    'アクネ スタジオズ Tシャツ'
  );
});

run('cleanValue: 「または」以降の代替提案を除去する', () => {
  assert.strictEqual(
    cleanValue('ダニエルウェリントン ¥15,000 または シンプルシルバーリング¥2,000'),
    'ダニエルウェリントン'
  );
});

run('parseOutfitItems: 基本的なラベル付き行をカテゴリ別に分類する', () => {
  const text = [
    '**トップス：** ユニクロ エアリズムT（ホワイト）¥1,500',
    '**ボトムス：** GU ワイドデニム（インディゴ）¥3,990',
    '**アウター：** アーバンリサーチ ステンカラーコート（ベージュ）¥16,500',
    '**靴：** Nike Air Force 1（ホワイト）¥8,800',
  ].join('\n');
  const items = parseOutfitItems(text);
  assert.strictEqual(items.top, 'ユニクロ エアリズムT（ホワイト）');
  assert.strictEqual(items.bottom, 'GU ワイドデニム（インディゴ）');
  assert.strictEqual(items.outer, 'アーバンリサーチ ステンカラーコート（ベージュ）');
  assert.strictEqual(items.shoes, 'Nike Air Force 1（ホワイト）');
});

run('parseOutfitItems: 色情報を欠落させずに保持する（色不一致バグの回帰防止）', () => {
  const items = parseOutfitItems('**トップス：** ユニクロ Tシャツ（黒）¥1,500');
  assert.ok(items.top.includes('黒'), `色情報が失われている: "${items.top}"`);
});

run('parseOutfitItems: コロンを含まない行は無視する', () => {
  const items = parseOutfitItems('これはただの説明文で、コロンがありません');
  assert.deepStrictEqual(items, {});
});

run('parseOutfitItems: 同じカテゴリが複数行あっても最初の行を優先する', () => {
  const text = '**トップス：** ユニクロ T\n**トップス：** GU シャツ';
  const items = parseOutfitItems(text);
  assert.strictEqual(items.top, 'ユニクロ T');
});

if (process.exitCode) {
  console.error('\n一部のテストが失敗しました');
} else {
  console.log('\n全てのテストが成功しました');
}
