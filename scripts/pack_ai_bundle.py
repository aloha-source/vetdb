#!/usr/bin/env python3
# 3桁/4桁ファイル名に対応。選択した .sql を "AIバンドル" 1本に連結します。
import re, pathlib, argparse, datetime

FILE_RE = re.compile(r"^(\d{3,4})_([a-z0-9]+)_(.+)\.sql$", re.IGNORECASE)

def parse_file(p: pathlib.Path):
    m = FILE_RE.match(p.name)
    if not m:
        return (99999999, "zzmisc", p.name)
    return (int(m.group(1)), m.group(2), p.name)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="patches", help="SQL格納フォルダ")
    ap.add_argument("--out", default=None, help="出力先（未指定なら ai_out/ 自動命名）")
    ap.add_argument("--filter", default=None, help="ファイル名フィルタの正規表現（例: receipt|checkup）")
    args = ap.parse_args()

    root = pathlib.Path(args.root)
    root.mkdir(parents=True, exist_ok=True)
    files = sorted(root.glob("*.sql"))
    parsed = [(p, *parse_file(p)) for p in files]
    # 安定ソート（番号→機能→ファイル名）
    parsed_sorted = sorted(parsed, key=lambda x: (x[1], x[2], x[0].name.lower()))

    if args.filter:
        rx = re.compile(args.filter, re.IGNORECASE)
        parsed_sorted = [t for t in parsed_sorted if rx.search(t[0].name)]

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = pathlib.Path(args.out) if args.out else pathlib.Path("ai_out")/f"ai_bundle_{ts}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)

    with out.open("w", encoding="utf-8", newline="\n") as f:
        f.write("# AI_BUNDLE v1\n")
        f.write(f"# root={root.as_posix()}\n")
        for (p, *_rest) in parsed_sorted:
            rel = p if p.is_absolute() else pathlib.Path(args.root)/p.name
            f.write(f"<<<FILE {rel.as_posix()}>>>\n")
            f.write(p.read_text(encoding="utf-8"))
            if not str(p).endswith("\n"):
                f.write("\n")
            f.write(f"<<<END {rel.as_posix()}>>>\n\n")
    print(out)

if __name__ == "__main__":
    main()
