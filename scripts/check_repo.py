"""Check source manifest, strict sequential style and local tutorial links."""
from pathlib import Path
from html.parser import HTMLParser
import re

ROOT = Path(__file__).resolve().parents[1]
files = (ROOT / "rtl/files.f").read_text().splitlines()
assert set(files) == {p.relative_to(ROOT).as_posix() for p in (ROOT / "rtl").glob("*.sv")}
blocks = 0
for filename in files:
    source = (ROOT / filename).read_text()
    source = re.sub(r"//[^\n]*|/\*.*?\*/", "", source, flags=re.S)
    assert not re.search(r"\b(initial|always_latch)\b", source), filename
    for block in re.findall(r"always_ff\s*@\(posedge clk_i\)\s*begin(.*?)\bend\b", source, re.S):
        blocks += 1
        assert re.fullmatch(r"\s*(?:\w+_q\s*<=\s*\w+_d\s*;\s*)+", block), filename
    assert len(re.findall(r"\balways_ff\b", source)) == len(re.findall(r"always_ff\s*@\(posedge clk_i\)\s*begin", source)), filename

class TutorialParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.anchors = []
        self.headings = 0
        self.words = 0
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs["id"])
        if tag == "a" and attrs.get("href", "").startswith("#"):
            self.anchors.append(attrs["href"][1:])
        if tag == "h2":
            self.headings += 1
    def handle_data(self, data):
        self.words += len(data.split())

parser = TutorialParser()
parser.feed((ROOT / "docs/tutorial.html").read_text(encoding="utf-8"))
assert not (set(parser.anchors) - parser.ids), "Broken internal links"
assert blocks == 3, "Review sequential block inventory when adding stateful modules"
assert parser.headings == 29, "Review chapter inventory when changing the tutorial"
print(f"PASS: {len(files)} RTL files, {blocks} assignment-only always_ff blocks, "
      f"{parser.headings} tutorial sections, {len(parser.anchors)} internal links")
