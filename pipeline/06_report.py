#!/usr/bin/env python
"""Step 6 — human-review reports as Markdown.

  sample    pick N entries across the frequency range (easy / hard / abstract mix) from one
            generated JSONL and render them for review
  compare   lay 2+ generated JSONL files side by side, word by word, so register differences
            between models are visible in one place

Usage:
  python 06_report.py sample --in data/generated.jsonl --n 20 --out data/review-20.md
  python 06_report.py compare data/compare-luna.jsonl data/compare-terra.jsonl data/compare-sol.jsonl \
      --out data/compare.md
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from arth_pipeline.config import DATA_DIR, read_jsonl

# Words that are abstract or polysemous enough to stress the register. Used by `sample`
# when present in the input; the rest of the sample is spread across freqRank.
STRESS_WORDS = [
    "mind",
    "sense",
    "matter",
    "state",
    "point",
    "case",
    "way",
    "fair",
    "just",
    "still",
    "even",
    "mean",
    "set",
    "right",
    "single",
    "want",
]


def rows_by_word(path: Path) -> dict[str, dict[str, Any]]:
    return {row["word"]: row for row in read_jsonl(path)}


def render_entry(row: dict[str, Any], *, header: bool = True) -> str:
    e = row["entry"]
    u = row.get("usage", {})
    lines = []
    if header:
        ipa = f"/{e['ipa']}/  ·  " if e['ipa'] else ''
        lines.append(f"## {e['word']}  ·  {ipa}{e['hindiPronunciation']}")
        lines.append(
            f"<sub>{row.get('model', '?')} · attempts {row.get('attempts', '?')} · "
            f"in {u.get('input', '?')} / out {u.get('output', '?')} tokens</sub>\n"
        )
    for s in e["senses"]:
        lines.append(f"**{s['index']}. {s['meaning']}** <sub>{s['partOfSpeech']}</sub>  ")
        lines.append(f"{s['definition']}  ")
        for ex in s["examples"]:
            lines.append(f"> {ex['en']}  \n> {ex['hi']}  ")
        lines.append("")
    if e["synonyms"]:
        lines.append("समानार्थी: " + ", ".join(f"{p['en']} – {p['hi']}" for p in e["synonyms"]) + "  ")
    if e["antonyms"]:
        lines.append("विलोम: " + ", ".join(f"{p['en']} – {p['hi']}" for p in e["antonyms"]) + "  ")
    if e["forms"]:
        lines.append("रूप: " + ", ".join(f"{f['en']} ({f['label']}) – {f['hi']}" for f in e["forms"]) + "  ")
    return "\n".join(lines) + "\n"


def cmd_sample(args: argparse.Namespace) -> None:
    rows = rows_by_word(args.inp)
    extract = json.loads((DATA_DIR / "extract.json").read_text(encoding="utf-8"))["entries"]
    rank = {e["word"]: e["freqRank"] for e in extract}
    ordered = sorted(rows, key=lambda w: rank.get(w, 10**9))
    picked: list[str] = [w for w in STRESS_WORDS if w in rows][: args.n // 2]
    rest = [w for w in ordered if w not in picked]
    need = args.n - len(picked)
    if need > 0 and rest:
        step = max(1, len(rest) // need)
        picked += rest[::step][:need]
    out = [f"# Review sample — {len(picked)} entries from {args.inp.name}\n"]
    for w in sorted(picked, key=lambda w: rank.get(w, 10**9)):
        out.append(f"<sub>freqRank {rank.get(w, '?')}</sub>\n")
        out.append(render_entry(rows[w]))
        out.append("---\n")
    args.out.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {args.out} ({len(picked)} entries)")


def cmd_compare(args: argparse.Namespace) -> None:
    files = [(p, rows_by_word(p)) for p in args.files]
    words: list[str] = []
    for _, rows in files:
        for w in rows:
            if w not in words:
                words.append(w)
    names = [p.stem.replace("compare-", "") for p, _ in files]
    out = [f"# Model comparison — {len(words)} words × {', '.join(names)}\n"]
    out.append("Same prompt, same schema, same Wiktionary senses; only the model differs.\n")
    for w in words:
        out.append(f"## {w}\n")
        out.append("<table><tr>" + "".join(f"<th>{n}</th>" for n in names) + "</tr><tr>")
        for _, rows in files:
            row = rows.get(w)
            cell = render_entry(row, header=False) if row else "_missing_"
            u = row.get("usage", {}) if row else {}
            attempts = row.get("attempts", "?") if row else "-"
            cell += f"\n<sub>out {u.get('output', '?')} tok · attempts {attempts}</sub>"
            out.append("<td valign=top width=33%>\n\n" + cell + "\n</td>")
        out.append("</tr></table>\n")
    args.out.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {args.out} ({len(words)} words)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sample")
    s.add_argument("--in", dest="inp", type=Path, default=DATA_DIR / "generated.jsonl")
    s.add_argument("--n", type=int, default=20)
    s.add_argument("--out", type=Path, default=DATA_DIR / "review.md")
    s.set_defaults(fn=cmd_sample)
    c = sub.add_parser("compare")
    c.add_argument("files", nargs="+", type=Path)
    c.add_argument("--out", type=Path, default=DATA_DIR / "compare.md")
    c.set_defaults(fn=cmd_compare)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
