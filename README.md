# vetdb (wip)

このブランチは **開発中 (WIP)** の作業ブランチです。  
**現在の正 (Canonical)** は **`/versions` 内の「番号が最も大きいファイル」** とします。

> 例: `versions/1.1.0.sql` と `versions/1.2.0.sql` があれば、**`1.2.0.sql`** が現在の正。  
> 命名は **SemVer**（`MAJOR.MINOR.PATCH.sql` 例: `1.2.0.sql`）で統一してください。  
> ※ `1.10.0` と `1.9.0` の比較誤りを防ぐため **3桁の形式**を推奨します。
dbは（MariaDB 10.5）を使用します。
lalavelでpwa-dbをつくります。
---

## ディレクトリ構成（wip ブランチのルート `/`）

/                     ← wip のルート
README.md
CHANGELOG.md

/public             ← Web公開ディレクトリ（サーバのドキュメントルート）
index.php         ← 入口（簡易ルータ）
/assets
/css/style.css
/js/main.js
/img/.gitkeep

/uploads/.gitkeep   ← ユーザーアップロード（本番は .gitignore で除外推奨）
/views              ← 画面テンプレ（PHP/HTML どちらでも可）
layout.php
home.php
404.php

/app                ← ドメインロジック
/Controllers
/Models
/Services

/config
config.php        ← DB接続など（本番は環境変数や .env で上書き推奨）

/patches            ← 書きかけ・未統合のファイル置き場
p1.sql            ← 例：番号プレフィクスで順序管理（p001_*.sql 推奨）

/versions           ← 新規インストール用「完全DDL」（版付きファイル名）
1.0.0.sql
1.1.0.sql
1.2.0.sql        ← 現在の正（最大番号）

/migrations         ← 既存DBを上げる差分（ALTER等）
1.0.0_to_1.1.0.sql
1.1.0_to_1.2.0.sql

> メモ: `uploads` を **ウェブ公開したい**場合は `/public/uploads/` に配置してください。  
> セキュリティを優先して **非公開にする**場合はルート直下のままが安全です（アプリからのみ参照）。

---

## 使い方

### 新規インストール
1. `versions/` を開き、**番号が最も大きい `.sql`** を選ぶ（= 現在の正）。  
2. そのファイルを DB に流す。  
   ```bash
   mysql -u <user> -p <database> < versions/1.2.0.sql

アップグレード
	•	手元のバージョン → 目標バージョン の順に /migrations の差分を適用。
例: 1.0.0 → 1.2.0 なら
1.0.0_to_1.1.0.sql → 1.1.0_to_1.2.0.sql を順番に実行。

⸻

開発フロー（このブランチのルール）
	1.	描きかけは /patches に置き、番号で順序を管理
	•	例: p001_qty_unit.sql, p002_fix_index.sql
	•	テキスト案や複合変更は p003_note.md のように .md で補足可
	2.	仕様が固まったら /versions の完全DDL に統合
	•	既存向けは /migrations/X.Y.Z_to_A.B.C.sql を作成
	3.	/versions に 新しい番号のファイル（例: 1.3.0.sql）を追加し、
README と CHANGELOG を更新
4.（任意）main へ取り込むときは PR（Squash merge 推奨）
	•	main を“配布用”に保ち、WIPはこのブランチで継続

命名規則
	•	/versions: MAJOR.MINOR.PATCH.sql（例 1.2.0.sql）
	•	/migrations: <from>_to_<to>.sql（例 1.1.0_to_1.2.0.sql）
	•	/patches: pNNN_<topic>.sql（例 p003_add_qty_unit.sql）

⸻

コーディング方針（DB設計）
	•	テーブル名: 複数形（individuals, checkup_items）
	•	カラム名: 単数形（name, qty_unit）
	•	互換維持の追加（NULL可/既定値あり）は MINOR、互換破壊（NOT NULL化/削除/型縮小）は MAJOR を上げる
	•	スキーマ版の刻印を入れる場合は例：

CREATE TABLE IF NOT EXISTS schema_versions(
  version VARCHAR(32) PRIMARY KEY, applied_at DATETIME(6) NOT NULL
);
INSERT INTO schema_versions(version, applied_at) VALUES ('1.2.0', NOW(6));



⸻

ChatGPT への依頼テンプレ

【参照】wip ブランチ
  - /patches/p003_add_qty_unit.sql
  - /versions/1.2.0.sql（基準）

【やること】
  - p003 を 1.2.0 に統合した「1.3.0.sql」を作成
  - 1.2.0 → 1.3.0 の差分DDLを /migrations に作成

【出力】
  - versions/1.3.0.sql
  - migrations/1.2.0_to_1.3.0.sql
  - 互換性チェックの要点


⸻

注意
	•	現在の正＝/versions の最大番号というルールを厳守してください。
	•	固定参照点が必要な場合は、コミット SHA を README/CHANGELOG に併記すると再現が容易です（タグ運用をしない前提）。
/* ============================================================
  checkups — BINARY(16) 版（MariaDB 10.5）／クライアント32桁hex・API境界のみ変換

  ■方針
    - クライアント（PWA）は UUID を **32桁hex（小文字、ダッシュ無し）** で扱う。
    - APIでは受信時に **UNHEX(…)=BINARY(16)** へ、返却時は **LOWER(HEX(…))** へ変換。
    - DBはすべて **BINARY(16)** で保存し、JOIN/索引/容量を最適化。
    - UUID未指定（クライアント発番できない）時は、**DBトリガが v7 を自動付与**。
    - GUIの可読用途は **ビュー** で提供（本体テーブルはクリーンを維持）。

  ■カラム/外部キー
    - `uuid` / `visit_uuid` / `individual_uuid` / `chart_header_uuid` は **BINARY(16)**。
    - `visits` / `individuals` / `chart_headers` 側の `uuid` も **BINARY(16) + UNIQUE** 前提。
    - （旧コメント）訪問のFK名は要望どおり **fk_visit_uuid1**。
    - （修正）FK命名規則に合わせ **fk_checkups_visit_uuid** に統一。

  ■文字コード（整合性）
    - 本テーブルは **DEFAULT CHARSET = utf8mb4, COLLATE = utf8mb4_unicode_ci** を明示。
    - アプリ内の他テーブルも **同一** に統一（混在は JOIN/比較で不具合の元）。
      例: ALTER DATABASE your_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

  ■API境界の使い方（例）
    - 受信: 32桁hex → `UNHEX(:uuid_hex)` で渡す（未指定なら NULL）
    - 返却: `SELECT LOWER(HEX(uuid)) AS uuid_hex ...`

  ■備考
    - レプリケーションは、関数で RAND() を使うため **ROWベース**推奨。
    - 親行はすでに存在していること（**親→子の順でINSERT**）。
=============================================
