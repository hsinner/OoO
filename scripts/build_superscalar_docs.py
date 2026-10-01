"""Build an offline course from Markdown guides and actual RTL sources.

Standard library only. Validate links, unique IDs, manifest source coverage and
reproducible output. This renderer supports the repository's Markdown subset.
"""
from pathlib import Path
from html.parser import HTMLParser
import argparse
import html
import re

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs/superscalar"
TARGET = DOCS / "tutorial.html"
CHAPTERS = [
    ("beginner", "Start here: first principles"),
    ("course", "Course: CPU architectures"),
    ("labs", "Labs: build and verify"),
    ("tutorial", "Architecture reference"),
    ("skeleton", "Implementation workbook"),
    ("modules", "Every module explained"),
]


def slug(value):
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def source_paths():
    manifest = ROOT / "rtl/superscalar/skeleton.f"
    paths = [ROOT / line.strip() for line in manifest.read_text().splitlines()
             if line.strip() and not line.startswith("#")]
    paths.append(ROOT / "examples/superscalar/pipe_reg.sv")
    assert len(paths) == len(set(paths)), "Duplicate source in manifest"
    assert all(path.is_file() for path in paths), "Missing RTL source"
    return paths


class Renderer:
    def __init__(self, sources):
        self.links = {(DOCS / f"{name}.md").resolve(): f"#{name}"
                      for name, _ in CHAPTERS}
        self.links.update({path.resolve(): f"#source-{path.stem}" for path in sources})
        self.toc = []

    def inline(self, value):
        tokens = re.split(r"(`[^`]+`|\[[^]]+\]\([^)]+\))", value)
        output = []
        for token in tokens:
            if token.startswith("`") and token.endswith("`"):
                output.append("<code>" + html.escape(token[1:-1]) + "</code>")
            elif match := re.fullmatch(r"\[([^]]+)\]\(([^)]+)\)", token):
                label, destination = match.groups()
                if not destination.startswith("https://"):
                    path = (DOCS / destination).resolve()
                    assert path.is_file(), f"Broken local link: {destination}"
                    destination = self.links.get(path, destination)
                output.append(f'<a href="{html.escape(destination, quote=True)}">'
                              + html.escape(label) + '</a>')
            else:
                output.append(re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>",
                                     html.escape(token)))
        return "".join(output)

    def markdown(self, name, label):
        lines = (DOCS / f"{name}.md").read_text(encoding="utf-8").splitlines()
        output = [f'<section id="{name}" class="part" aria-label="{label}">',
                  f'<p class="label">{label}</p>']
        entries = []
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
                assert cursor < len(lines), f"Unclosed code fence: {name}"
                output.append("<pre><code>" + html.escape("\n".join(code)) + "</code></pre>")
            elif line.startswith("#"):
                level = len(line) - len(line.lstrip("#"))
                title = line[level:].strip()
                key = name + "-" + slug(title)
                if level == 1:
                    output.append(f'<h2 class="part-title" id="{key}">{self.inline(title)}</h2>')
                else:
                    output.append(f'<h{level + 1} id="{key}">{self.inline(title)}</h{level + 1}>')
                if level == 2:
                    entries.append(f'<a href="#{key}">{self.inline(title)}</a>')
            elif line.startswith("|"):
                rows = []
                while cursor < len(lines) and lines[cursor].startswith("|"):
                    cells = [cell.strip() for cell in lines[cursor].strip().strip("|").split("|")]
                    if not all(re.fullmatch(r":?-+:?", cell) for cell in cells):
                        rows.append(cells)
                    cursor += 1
                assert rows and all(len(row) == len(rows[0]) for row in rows), f"Uneven table: {name}"
                header = "".join(f'<th scope="col">{self.inline(cell)}</th>' for cell in rows[0])
                body = "".join("<tr>" + "".join(f"<td>{self.inline(cell)}</td>" for cell in row)
                               + "</tr>" for row in rows[1:])
                output.append(f'<div class="table" tabindex="0" role="region" aria-label="Scrollable reference table"><table><thead><tr>{header}</tr></thead><tbody>{body}</tbody></table></div>')
                continue
            elif re.match(r"(?:- |\d+\. )", line):
                ordered = not line.startswith("- ")
                pattern = r"\d+\. (.*)" if ordered else r"- (.*)"
                items = []
                while cursor < len(lines) and (match := re.fullmatch(pattern, lines[cursor])):
                    item = match[1]
                    cursor += 1
                    while cursor < len(lines) and lines[cursor].startswith("   "):
                        item += " " + lines[cursor].strip()
                        cursor += 1
                    items.append("<li>" + self.inline(item) + "</li>")
                tag = "ol" if ordered else "ul"
                output.append(f"<{tag}>" + "".join(items) + f"</{tag}>")
                continue
            else:
                paragraph = []
                while cursor < len(lines) and lines[cursor].strip():
                    paragraph.append(lines[cursor])
                    cursor += 1
                output.append("<p>" + self.inline(" ".join(paragraph)) + "</p>")
                continue
            cursor += 1
        output.append("</section>")
        self.toc.append(f'<div class="nav-group"><a class="group-title" href="#{name}">{label}</a>'
                        + "".join(entries) + "</div>")
        return "\n".join(output)


class DocumentCheck(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.anchors = set(), []
        self.headings = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f'Duplicate ID: {attrs["id"]}'
            self.ids.add(attrs["id"])
        if tag == "a" and attrs.get("href", "").startswith("#"):
            self.anchors.append(attrs["href"][1:])
        if tag == "h1":
            self.headings += 1


STYLE = '''
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;color:#172e3c;background:#eef3f4;font:17px/1.8 system-ui,sans-serif}
nav{position:fixed;inset:0 auto 0 0;width:290px;background:#142d3c;color:white;padding:24px;overflow:auto}
nav strong{font-size:23px;display:block}nav a{display:block;color:#d6e9ee;text-decoration:none;font-size:13px;padding:5px 0;line-height:1.5}
nav a:hover,nav a:focus{text-decoration:underline;color:white}.group-title{font-size:15px;font-weight:bold;color:#8cddd5;margin-top:24px}
label{display:block;font-size:13px;margin-top:20px}input{width:100%;padding:10px;border:1px solid #95b5be;border-radius:5px;font:inherit;font-size:14px;margin-top:6px}
#search-status{font-size:12px;color:#b9d0d9;margin:8px 0}main{margin-left:290px;max-width:1450px;padding:42px clamp(22px,5vw,80px);background:white;min-height:100vh;min-width:0}
h1{font-size:clamp(32px,4vw,52px);line-height:1.15;max-width:22ch}h2{font-size:34px;line-height:1.3}h3{font-size:26px;line-height:1.35;margin-top:50px;border-top:1px solid #cee1e5;padding-top:25px}h4{font-size:21px;margin-top:30px}
[id]{scroll-margin-top:24px}.part{margin-top:70px}.part-title{border-bottom:3px solid #168c85;padding-bottom:20px}p,li{max-width:85ch}a{color:#006c73}a:focus-visible,summary:focus-visible{outline:3px solid #c77a00;outline-offset:3px}
pre{background:#122a39;color:#e1f4f5;border-radius:8px;padding:22px;overflow:auto;font:14px/1.65 Consolas,monospace}code{font-family:Consolas,monospace;font-size:.93em}p code,li code,td code{background:#edf3f4;padding:2px 4px}
.table{overflow-x:auto;margin:22px 0}table{border-collapse:collapse;width:100%;font-size:15px}th,td{text-align:left;vertical-align:top;padding:12px;border-bottom:1px solid #dce6e9}th{background:#eaf3f4}
.label{color:#006c73;text-transform:uppercase;letter-spacing:2px;font-size:12px;font-weight:bold}.note{background:#edf7f5;border-left:4px solid #168c85;padding:20px 24px;margin:24px 0}.note p{margin:5px 0}
.pipeline{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:25px 0}.pipeline a{background:#142d3c;color:white;border-radius:7px;padding:14px;text-decoration:none;font-size:14px;line-height:1.4}.pipeline b{display:block;color:#8cddd5;font-size:22px;margin-bottom:5px}
.routes{display:flex;flex-wrap:wrap;gap:10px}.routes a{background:#eaf3f4;border:1px solid #c7dfe1;border-radius:5px;padding:9px 14px;font-size:14px}
details{border:1px solid #c7dfe1;border-radius:6px;padding:12px 18px;margin:20px 0}summary{cursor:pointer;font-weight:bold;overflow-wrap:anywhere}.status{font-size:13px;color:#506c79}.skip{position:absolute;left:-10000px}.skip:focus{position:fixed;left:10px;top:10px;background:white;padding:10px;z-index:2}[hidden]{display:none!important}
@media(max-width:850px){nav{position:relative;width:auto;max-height:320px}main{margin:0;padding:24px}.pipeline{grid-template-columns:repeat(2,1fr)}h2{font-size:28px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
@media print{nav,.routes,.skip{display:none}main{margin:0;padding:0}body{font-size:11pt}.part{break-before:page}pre{white-space:pre-wrap;overflow-wrap:anywhere;color:black;background:#f0f3f5}.table{overflow:visible}}
'''

SCRIPT = '''
const search = document.querySelector('#chapter-search');
const groups = [...document.querySelectorAll('.nav-group')];
search.addEventListener('input', () => {
  const query = search.value.trim().toLowerCase();
  let matches = 0;
  groups.forEach(group => {
    let visible = 0;
    group.querySelectorAll('a:not(.group-title)').forEach(link => {
      link.hidden = !link.textContent.toLowerCase().includes(query);
      if (!link.hidden) visible++;
    });
    group.hidden = visible === 0;
    matches += visible;
  });
  document.querySelector('#search-status').textContent = query
    ? `${matches} matching chapter titles. Clear to show all.`
    : 'Filter titles here; use Ctrl+F to search the full text.';
});
function revealSource() {
  const target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
  if (target && target.tagName === 'DETAILS') target.open = true;
}
window.addEventListener('hashchange', revealSource);
revealSource();
'''


def build():
    paths = source_paths()
    renderer = Renderer(paths)
    sections = [renderer.markdown(name, label) for name, label in CHAPTERS]
    listings, links = [], []
    for path in paths:
        text = path.read_text(encoding="utf-8")
        key = "source-" + path.stem
        status = ("Unimplemented shell: outputs intentionally undriven" if "UNIMPLEMENTED SKELETON" in text
                  else "Shared type declarations" if path.stem.endswith("_pkg")
                  else "Generic storage example" if path.stem == "pipe_reg"
                  else "Implemented hazard unit; see standalone validation report")
        relative = path.relative_to(ROOT).as_posix()
        listings.append(f'<details id="{key}"><summary>{relative}</summary><p class="status">{status}</p>'
                        + '<pre><code>' + html.escape(text.rstrip()) + '</code></pre></details>')
        links.append(f'<a href="#{key}">{path.name}</a>')
    renderer.toc.append('<div class="nav-group"><a class="group-title" href="#sources">Actual RTL source</a>'
                        + ''.join(links) + '</div>')
    sections.append('<section class="part" id="sources"><h2>Current source, not pseudocode</h2>'
                    '<p>Expand a file to inspect its exact declarations and comments. These listings are embedded '
                    'at documentation build time and work offline. The fifteen unfinished modules stay unfinished. '
                    'Successful interface checks are not CPU simulation results.</p>' + ''.join(listings) + '</section>')
    stages = [('IF', 'Fetch words'), ('D', 'Decode meaning'), ('R', 'Read registers'),
              ('DP', 'Check and dispatch'), ('EX', 'Compute results'), ('MEM', 'Process memory'),
              ('WB', 'Hold completion'), ('C', 'Commit effects')]
    diagram = '<div class="pipeline" aria-label="Eight stages in order">' + ''.join(
        f'<a href="#beginner-a7-the-eight-stages-explained-without-shortcuts"><b>{i}. {stage}</b>{label}</a>'
        for i, (stage, label) in enumerate(stages, 1)) + '</div>'
    intro = ('<header><p class="label">An offline CPU design course · RV32I · Four-wide · In-order</p>'
             '<h1>Learn the architecture. Build the processor.</h1>'
             '<p>Start from clock edges and instructions, build a four-wide in-order pipeline, '
             'then study prediction, caches, renaming, out-of-order scheduling and recovery. '
             'Thirty course lessons and seventeen labs connect the concepts to your module skeletons.</p>'
             '<div class="note"><p><strong>This is a design and implementation guide, not a completed CPU.</strong></p>'
             '<p>The forwarding and control-hazard blocks are implemented. The fifteen processor shells '
             'remain yours to build. Advanced architectures are optional study and redesign paths, '
             'not implemented features. Cycle tables are illustrations, not measured execution results.</p></div>'
             + diagram + '<div class="routes"><a href="#beginner">1 · Learn the basics</a>'
             '<a href="#course">2 · Follow the course</a><a href="#labs">3 · Work through the labs</a>'
             '<a href="#tutorial">Architecture reference</a><a href="#skeleton">Implementation contracts</a>'
             '<a href="#modules">Every module explained</a></div></header>')
    document = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
                '<meta name="viewport" content="width=device-width, initial-scale=1">'
                '<title>Build a superscalar CPU — RV32I course, architectures and labs</title><style>'
                + STYLE + '</style></head><body><a class="skip" href="#content">Skip to tutorial</a>'
                '<nav aria-label="Chapters"><strong>RV32I / Four-wide</strong>'
                '<label for="chapter-search">Find a chapter</label><input id="chapter-search" type="search" placeholder="Try forwarding or commit">'
                '<p id="search-status" role="status">Filter titles here; use Ctrl+F to search the full text.</p>'
                + ''.join(renderer.toc) + '</nav><main id="content">' + intro + '\n'.join(sections)
                + '</main><script>' + SCRIPT + '</script></body></html>\n')
    check = DocumentCheck()
    check.feed(document)
    assert check.headings == 1, "Expected one main heading"
    assert all(anchor in check.ids for anchor in check.anchors), "Broken internal anchor"
    return document


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    document = build()
    if args.check:
        assert TARGET.read_text(encoding="utf-8") == document, "HTML stale; run builder"
        print(f"PASS: HTML matches {len(CHAPTERS)} Markdown guides and all manifest RTL; links and anchors checked")
    else:
        TARGET.write_text(document, encoding="utf-8", newline="\n")
        print("Built docs/superscalar/tutorial.html")
