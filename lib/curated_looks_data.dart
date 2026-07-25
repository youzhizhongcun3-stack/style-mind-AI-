/// 「あなたにおすすめのコーデ」フィード用の静的データ。
/// 画像はassets/curated_looks/、AIによる事前生成済み。
/// 新しいコーデを追加する場合はtools/generate_curated_looks.jsを参照。
class CuratedLook {
  final String id;
  final String imageAsset;
  final String title;
  final String gender;
  final String skeletonType;
  final String styles;
  final List<String> items; // 表示用の短いアイテム説明（ラベル: 内容）
  final List<String> shopKeywords; // 購入導線に使う検索キーワード（ブランド+アイテム名）

  const CuratedLook({
    required this.id,
    required this.imageAsset,
    required this.title,
    required this.gender,
    required this.skeletonType,
    required this.styles,
    required this.items,
    required this.shopKeywords,
  });
}

const List<CuratedLook> curatedLooks = [
  CuratedLook(
    id: 'look_01',
    imageAsset: 'assets/curated_looks/look_01.jpg',
    title: 'カフェデートのフェミニンコーデ',
    gender: 'レディース',
    skeletonType: 'ウェーブタイプ',
    styles: 'フェミニン/ガーリー',
    items: [
      'トップス：GU リネンコットン半袖ブラウス（ベージュ）¥2,990',
      'ボトムス：ZARA ハイウエストフレアミニスカート（クリーム）¥3,990',
      '靴：Nike Air Force 1（ホワイト）¥9,900',
      'バッグ：かごバッグ（ベージュ×ホワイト）¥4,500',
    ],
    shopKeywords: ['GU リネンブラウス', 'ZARA フレアミニスカート', 'かごバッグ'],
  ),
  CuratedLook(
    id: 'look_02',
    imageAsset: 'assets/curated_looks/look_02.jpg',
    title: '上品なオフィスカジュアル',
    gender: 'レディース',
    skeletonType: 'ストレートタイプ',
    styles: 'クワイエットラグジュアリー',
    items: [
      'トップス：アワーレガシー ブークレニット（ミルクチョコ）¥16,500',
      'ボトムス：ユニクロ ハイウエストストレートパンツ（チャコール）¥3,990',
      '靴：Adidas Stan Smith（オフホワイト）¥8,800',
      'バッグ：フルラ メトロポリス（ネイビー）¥34,000',
    ],
    shopKeywords: ['アワーレガシー ニット', 'ユニクロ ストレートパンツ', 'フルラ ハンドバッグ'],
  ),
  CuratedLook(
    id: 'look_03',
    imageAsset: 'assets/curated_looks/look_03.jpg',
    title: '週末のリラックスカジュアル',
    gender: 'レディース',
    skeletonType: 'ナチュラルタイプ',
    styles: 'カジュアル',
    items: [
      'トップス：ZARA オーバーサイズリネンシャツ（テラコッタ）¥3,990',
      'ボトムス：ユニクロ バギーワイドアンクルパンツ（グレー）¥2,990',
      '靴：Adidas Stan Smith（オフホワイト）¥8,800',
      'バッグ：マークジェイコブス ザ・トートバッグ（クリーム）¥14,000',
    ],
    shopKeywords: ['ZARA オーバーサイズリネンシャツ', 'ユニクロ バギーパンツ', 'マークジェイコブス トートバッグ'],
  ),
  CuratedLook(
    id: 'look_04',
    imageAsset: 'assets/curated_looks/look_04.jpg',
    title: '通勤・通学のミニマルきれいめ',
    gender: 'メンズ',
    skeletonType: 'ストレートタイプ',
    styles: 'ミニマル/シンプル',
    items: [
      'トップス：Aime Leon Dore クルーネックT（オフホワイト）¥12,000',
      'ボトムス：ZARA ハイウエストテーラードトラウザー（黒）¥6,990',
      '靴：Adidas Stan Smith（ホワイト）¥10,000',
      'バッグ：Fjallraven Kanken Totepack（ブラック）¥18,000',
    ],
    shopKeywords: ['Aime Leon Dore Tシャツ', 'ZARA テーラードパンツ', 'Kanken Totepack'],
  ),
  CuratedLook(
    id: 'look_05',
    imageAsset: 'assets/curated_looks/look_05.jpg',
    title: '友達と遊ぶストリートコーデ',
    gender: 'メンズ',
    skeletonType: 'ウェーブタイプ',
    styles: 'ストリート',
    items: [
      'トップス：Stussy バックプリントロゴT（ベージュ）¥3,500',
      'ボトムス：ZARA テーパードカーゴパンツ（カーキ）¥3,990',
      '靴：Vans Old Skool（モスグリーン）¥7,700',
      'バッグ：A.P.C. サコッシュ（ベージュ）¥25,000',
    ],
    shopKeywords: ['Stussy Tシャツ', 'ZARA カーゴパンツ', 'Vans Old Skool'],
  ),
  CuratedLook(
    id: 'look_06',
    imageAsset: 'assets/curated_looks/look_06.jpg',
    title: '大学向けこなれたアメカジ',
    gender: 'メンズ',
    skeletonType: 'ナチュラルタイプ',
    styles: 'カジュアル/アメカジ',
    items: [
      'トップス：Carhartt WIP デトロイトジャケット（ブラウン）¥18,000',
      'ボトムス：ZARA ストレートレッグデニム（中色ブルー）¥4,990',
      '靴：Adidas Samba（ホワイト×ガムソール）¥10,500',
      'バッグ：Fjallraven Kanken（ターコイズ）¥8,800',
    ],
    shopKeywords: ['Carhartt WIP デトロイトジャケット', 'Adidas Samba', 'Fjallraven Kanken'],
  ),
  CuratedLook(
    id: 'look_07',
    imageAsset: 'assets/curated_looks/look_07.jpg',
    title: '2026年夏の韓国系オルチャン',
    gender: 'レディース',
    skeletonType: 'ウェーブタイプ',
    styles: '韓国系/オルチャン',
    items: [
      'トップス：クロップドカットソー（テラコッタピンク）¥1,500〜38,000',
      'ボトムス：ZARA ティアードフリルミニスカート（クリーム）¥6,990',
      '靴：Nike Air Force 1（ホワイト×ベビーピンク）¥11,000',
      'バッグ：BNOTE パデッドキルティングショルダー（ラベンダー）¥8,500',
    ],
    shopKeywords: ['ZARA ティアードミニスカート', 'パデッドキルティングバッグ', 'Nike Air Force 1'],
  ),
  CuratedLook(
    id: 'look_08',
    imageAsset: 'assets/curated_looks/look_08.jpg',
    title: 'スケボーセッション向けストリート',
    gender: 'メンズ',
    skeletonType: 'ストレートタイプ',
    styles: 'ストリート',
    items: [
      'トップス：Palace Skateboards クルーネックT（ホワイト）¥8,000',
      'ボトムス：ZARA バギーカーゴパンツ（黒）¥4,990',
      '靴：New Balance 574（コバルトブルー）¥12,000',
      'バッグ：Carhartt WIP ダック地ショルダー（黒）¥8,500',
    ],
    shopKeywords: ['Palace Skateboards Tシャツ', 'New Balance 574', 'Carhartt WIP ショルダーバッグ'],
  ),
];
