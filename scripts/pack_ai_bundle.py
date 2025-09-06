#!/usr/bin/env python3
# patches 配下の .sql を再帰的に収集。3/4桁規則に合わない名前も含めてバンドル化。
import re, pathlib, argparse, datetime, sys

FILE_RE = re.compile(r"^(\d{3,4})_([a-z0-9]+)_(.+)\.sql$", re.IGNORECASE)

EXCLUDE_DIRS = {
    ".git", ".github", "ai_out", "ai_inbox", "node_modules", "vendor", "__pycache__"
}
EXCLUDE_SUFFIXES = (".bak", ".tmp", ".disabled.sql")

def parse_key(p: pathlib.Path):
    m = FILE_RE.match(p.name)
    if not m:
        return (99999999, "zzmisc", p.name.lower())
    return (int(m.group(1)), m.group(2).lower(), p.name.lower())

def read_text_safe(p: pathlib.Path) -> str:
    try:
        return p.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        # 置換モードで強制デコード（文字化けはするがバンドル自体は生成）
        return p.read_bytes().decode("utf-8", "replace")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="patches", help="SQL格納フォルダ（再帰検索）")
    ap.add_argument("--out", default=None, help="出力先（未指定なら ai_out/ 自動命名）")
    ap.add_argument("--filter", default=None, help="パス全体に対する正規表現（例: receipt|checkup）")
    ap.add_argument("--pr-paths", default="", help="バンドル先頭に '# PR_PATHS:' 行を付与")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    root.mkdir(parents=True, exist_ok=True)

    # 再帰的に .sql を収集（除外ディレクトリ/拡張子をスキップ）
    candidates = []
    for p in root.rglob("*.sql"):
        if any(part in EXCLUDE_DIRS for part in p.parts):
            continue
        if p.name.endswith(EXCLUDE_SUFFIXES):
            continue
        candidates.append(p)

    # フィルタ（パス全体）適用
    if args.filter:
        rx = re.compile(args.filter, re.IGNORECASE)
        candidates = [p for p in candidates if rx.search(p.as_posix())]

    # 安定ソート（番号→機能→ファイル名）
    candidates_sorted = sorted(candidates, key=parse_key)

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = pathlib.Path(args.out) if args.out else pathlib.Path("ai_out")/f"ai_bundle_{ts}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)

    # ログ（標準出力）
    print(f"[pack] root={root}")
    print(f"[pack] files={len(candidates_sorted)} (after filter)")
    for p in candidates_sorted[:20]:
        print(f"  - {p.relative_to(root)}")
    if len(candidates_sorted) > 20:
        print(f"  ... (+{len(candidates_sorted)-20} more)")

    with out.open("w", encoding="utf-8", newline="\n") as f:
        f.write("# AI_BUNDLE v1\n")
        if args.pr_paths.strip():
            f.write(f"# PR_PATHS: {args.pr_paths.strip()}\n")
        f.write(f"# root={root.name}\n")
        for p in candidates_sorted:
            # マーカーは repo ルートからの相対にせず、「root/相対」に固定（例: patches/dir/file.sql）
            rel_in_root = p.relative_to(root)
            rel_marker = (pathlib.Path(args.root)/rel_in_root).as_posix()
            f.write(f"<<<FILE {rel_marker}>>>\n")
            f.write(read_text_safe(p))
            if not str(p).endswith("\n"):
                f.write("\n")
            f.write(f"<<<END {rel_marker}>>>\n\n")
    print(out)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[pack] ERROR: {e}", file=sys.stderr)
        sys.exit(1)
