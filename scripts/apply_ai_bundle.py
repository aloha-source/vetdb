#!/usr/bin/env python3
# AIバンドル（テキスト1本）を、元の複数 .sql に展開します。
import re, sys, pathlib

START_RE = re.compile(r'^<<<FILE\s+(.+?)>>>$')
END_RE   = re.compile(r'^<<<END\s+(.+?)>>>$')

def main():
    if len(sys.argv) < 2:
        print("usage: apply_ai_bundle.py <bundle.txt>")
        sys.exit(1)
    bundle = pathlib.Path(sys.argv[1])
    cur_path = None
    buf = []
    wrote = []

    with bundle.open(encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            m1 = START_RE.match(line)
            m2 = END_RE.match(line)
            if m1:
                cur_path = pathlib.Path(m1.group(1))
                buf = []
            elif m2:
                endpath = pathlib.Path(m2.group(1))
                if cur_path is None or endpath.as_posix() != cur_path.as_posix():
                    raise RuntimeError(f"Marker mismatch: {endpath} vs {cur_path}")
                content = "".join(buf)
                cur_path.parent.mkdir(parents=True, exist_ok=True)
                cur_path.write_text(content, encoding="utf-8")
                wrote.append(cur_path.as_posix())
                cur_path = None
                buf = []
            else:
                if cur_path is not None:
                    buf.append(raw)

    print("updated files:")
    for p in wrote:
        print(" -", p)

if __name__ == "__main__":
    main()
