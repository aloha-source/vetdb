# vetdb
DBスキーマと簡易アプリ一式。

- **現在の正**: `versions/1.0.0.sql`（タグ: `v1.0.0`） 
※ 次版を確定したらここを `2.0.0.sql`（タグ `v2.0.0`）に更新。
バージョン変更はSemVerによる
	•	MAJOR（例: 2.0.0）… 互換破壊：列削除／型縮小／NOT NULL 追加／主キー変更 など
	•	MINOR（例: 1.1.0）… 互換維持で機能追加：列追加（NULL可/既定値あり）、新テーブル、ビュー、インデックス追加 など
	•	PATCH（例: 1.1.1）… 互換維持の修正：コメント修正、インデックス名修正、デフォルト値の誤り修正 など
- 命名ルール（迷わない型）
	•	ファイル：versions/1.1.0.sql、migrations/1.0.0_to_1.1.0.sql
	•	タグ：v1.1.0（常に頭に v）
	•	ブランチ：patch/1.1.0-<topic>（または feature/…）
---

## 1. なにが入っている？
- `/versions` … **新規インストール用の完全DDL**（版付きファイル名）
- `/migrations` … 既存DBを上げる **差分DDL（ALTER等）**
- `/ddl` … 分割DDL（開発用・
- フォルダ構成原案

/                 ← リポのルート（main）
  README.md
  CHANGELOG.m

/public         ← Web公開ディレクトリ（サーバのドキュメントルートはここを指す）
    index.php     ← 入口。簡易ルータ
  /assets
      /css/style.css
      /js/main.js
      /img/.gitkeep

/uploads/.gitkeep  ← ユーザーがアップする場所（.gitignoreで除外推奨）
/views          ← 画面テンプレ（PHPでもHTMLでもOK）
    layout.php
    home.php
    404.php

/app            ← ロジック
    /Controllers
    /Models
    /Services

/config
    config.php    ← DB接続など（本番は .env で上書き推奨）

/versions       ← 新規インストール用“完全DDL”（版付きファイル名）
    v1.sql

/migrations     ← 既存DBを上げる差分（ALTERなど）
    v1_to_v1p2.sql
/ddl            ← 分割DDLが欲しいとき（任意）
  composer.json   ← （必要なら）PSR-4オートロード用
  .gitignore
---

## 2. 使い方（DB）

### 新規インストール
- ローカルファイルから:  
  `mysql -u <user> -p <database> < versions/v1.sql`
- GitHub の固定URL（タグ）から読みたい場合:  
  `https://raw.githubusercontent.com/<ユーザー>/<リポジトリ>/<タグ>/versions/v1.sql`

### アップグレード
`migrations/` のファイルを順番に適用（例: `v1_to_v1p2.sql` → `v1p2_to_v1p3.sql` …）。

---

## 3. 開発フロー（迷わない最小ルール）
1. ブランチ作成: `patch/<topic>`（例: `patch/v1p2-add-qty-unit`）
2. 変更 → コミット（スマホのWeb編集＝即コミットでOK）
3. **Pull Request** 作成（未完成なら **Draft PR**）
4. テスト/確認 → **Squash and merge** で main に取り込み
5. **タグ付け**（Releases → *Draft a new release* → `v1p2` など）
6. README の **現在の正** を更新、`CHANGELOG.md` に要約を書く

> 長期保守が必要になった時だけ `release/v1` のような保守ブランチを作成。ふだんは **main＋タグ** で十分。

---

## 4. 命名と方針（例）
- テーブル名: **複数形**（`individuals`, `checkup_items`）  
- カラム名: **単数形**（`name`, `qty_unit`）  
- 外部キー・インデックスは依存順で定義／最後に制約をまとめてもOK  
- スキーマ版は `schema_versions` で管理（任意）

---

## 5. ChatGPT への依頼テンプレ
