# vetdb
獣医向けDBスキーマと簡易アプリ一式。

**現在の正**: `versions/v1.sql`（タグ: `v1`） 
※ 次版を確定したらここを `v1p2.sql`（タグ `v1p2`）に更新。

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
