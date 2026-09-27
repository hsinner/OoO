"""Render this tutorial's Markdown subset to offline HTML; no dependencies.

Supported: headings, paragraphs, fences, flat bullet lists, pipe tables, links,
inline code and bold. Reject broken local links and stale generated output.
"""
from pathlib import Path
import argparse
import html
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/superscalar/tutorial.md"
TARGET = SOURCE.with_suffix(".html")


def inline(value):
    escaped = html.escape(value)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    return re.sub(r"\[([^]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', escaped)


def build():
    source = SOURCE.read_text(encoding="utf-8")
    lines = source.splitlines()
    for destination in re.findall(r"\[[^]]+\]\(([^)]+)\)", source):
        if not destination.startswith("https://"):
            assert (SOURCE.parent / destination).is_file(), destination
    output, toc, seen = [], [], set()
    cursor = 0
    while cursor < len(lines):
        line = lines[cursor]
        if not line.strip():
            cursor += 1
            continue
        if line.startswith("```"):
            code = []
            cursor += 1
            while cursor < len(lines) and not lines[cursor].startswith("```"):
                code.append(lines[cursor])
                cursor += 1
            assert cursor < len(lines), "Unclosed code fence"
            output.append("<pre><code>" + html.escape("\n".join(code)) + "</code></pre>")
        elif line.startswith("#"):
            level = len(line) - len(line.lstrip("#"))
            title = line[level:].strip()
            key = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
            assert key not in seen, key
            seen.add(key)
            output.append(f'<h{level} id="{key}">{inline(title)}</h{level}>')
            if level == 2:
                toc.append(f'<a href="#{key}">{inline(title)}</a>')
        elif line.startswith("|"):
            rows = []
            while cursor < len(lines) and lines[cursor].startswith("|"):
                cells = [cell.strip() for cell in lines[cursor].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", cell) for cell in cells):
                    rows.append(cells)
                cursor += 1
            assert all(len(row) == len(rows[0]) for row in rows), "Uneven table"
            header = "".join(f'<th scope="col">{inline(cell)}</th>' for cell in rows[0])
            body = "".join("<tr>" + "".join(f"<td>{inline(cell)}</td>" for cell in row) + "</tr>" for row in rows[1:])
            output.append(f'<div class="table"><table><thead><tr>{header}</tr></thead><tbody>{body}</tbody></table></div>')
            continue
        elif line.startswith("- "):
            items = []
            while cursor < len(lines) and lines[cursor].startswith("- "):
                items.append("<li>" + inline(lines[cursor][2:]) + "</li>")
                cursor += 1
            output.append("<ul>" + "".join(items) + "</ul>")
            continue
        else:
            paragraph = []
            while cursor < len(lines) and lines[cursor].strip():
                paragraph.append(lines[cursor])
                cursor += 1
            output.append("<p>" + inline(" ".join(paragraph)) + "</p>")
            continue
        cursor += 1
    assert len(toc) == 20, "Review chapter count after editing headings"
    style = '''
*{box-sizing:border-box}body{margin:0;color:#172e3c;background:#f2f5f6;font:17px/1.75 system-ui,sans-serif}
nav{position:fixed;inset:0 auto 0 0;width:285px;background:#142d3c;color:#fff;padding:25px;overflow:auto}
nav strong{font-size:23px;display:block;margin-bottom:22px}nav a{display:block;color:#d6e9ee;text-decoration:none;font-size:14px;padding:7px 0}
nav a:hover,nav a:focus{text-decoration:underline;color:white}main{margin-left:285px;max-width:1350px;padding:45px clamp(22px,5vw,80px);background:white;min-height:100vh}
h1{font-size:44px;line-height:1.2}h2{font-size:28px;line-height:1.3;margin-top:55px;padding-top:22px;border-top:2px solid #d4e5e8;scroll-margin-top:20px}
p{max-width:85ch}a{color:#006c73}pre{background:#122a39;color:#e1f4f5;border-radius:7px;padding:22px;overflow:auto;font:14px/1.6 Consolas,monospace}
code{font-family:Consolas,monospace;font-size:.93em}p code{background:#edf3f4;padding:2px 4px}.table{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:15px}th,td{text-align:left;vertical-align:top;padding:10px 12px;border-bottom:1px solid #dce6e9}th{background:#eaf3f4}
.label{color:#006c73;text-transform:uppercase;letter-spacing:2px;font-size:13px;font-weight:bold}
@media(max-width:850px){nav{position:relative;width:auto;max-height:290px}main{margin:0;padding:24px}h1{font-size:34px}}
@media print{nav{display:none}main{margin:0;padding:0}body{font-size:11pt}h2{break-before:page}pre{white-space:pre-wrap;color:black;background:#f0f3f5}}
'''
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            '<title>Four-wide RV32I design tutorial</title><style>' + style + '</style></head>'
            '<body><nav aria-label="Chapters"><strong>RV32I / Four-wide</strong>' + ''.join(toc)
            + '</nav><main><p class="label">In-order superscalar · Eight stages</p>'
            + '\n'.join(output) + '</main></body></html>\n')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    document = build()
    if args.check:
        assert TARGET.read_text(encoding="utf-8") == document, "HTML stale; run builder"
        print("PASS: superscalar HTML matches Markdown; 20 chapters and local links checked")
    else:
        TARGET.write_text(document, encoding="utf-8", newline="\n")
        print("Built docs/superscalar/tutorial.html")
