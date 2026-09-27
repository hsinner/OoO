"""Build a standalone tutorial from prose and the actual RTL, using stdlib only."""
from pathlib import Path
import html
import re

ROOT = Path(__file__).resolve().parents[1]
body = (ROOT / "docs/chapters.html").read_text(encoding="utf-8")
chapters = re.findall(r'<h2 id="([^"]+)">([^<]+)</h2>', body)
toc = ''.join(f'<a href="#{key}">{title}</a>' for key, title in chapters)
sources = []
for source in (ROOT / "rtl/files.f").read_text().splitlines():
    name = Path(source).stem
    sources.append(f'<details id="source-{name}"><summary>{html.escape(source)}</summary>'
                   f'<pre><code>{html.escape((ROOT / source).read_text())}</code></pre></details>')
style = '''
:root{color-scheme:light;--ink:#182c3b;--accent:#006b70;--muted:#526675;--paper:#fff}
*{box-sizing:border-box}[hidden]{display:none!important}html{scroll-behavior:smooth;scroll-padding-top:24px}
body{margin:0;background:#edf2f4;color:var(--ink);font:17px/1.7 system-ui,sans-serif}
nav{position:fixed;inset:0 auto 0 0;width:290px;overflow:auto;background:#132c3c;color:white;padding:28px 22px}
nav strong{font-size:22px;display:block;margin-bottom:20px}nav a{display:block;color:#d5e8ec;text-decoration:none;font-size:14px;padding:6px 0}
nav a:hover,nav a:focus{color:white;text-decoration:underline}main{margin-left:290px;padding:50px clamp(20px,5vw,85px);max-width:1320px;background:var(--paper);min-height:100vh}
h1{font-size:clamp(32px,4vw,56px);line-height:1.1;letter-spacing:-1px}h2{font-size:29px;border-top:2px solid #dce9ed;padding-top:34px;margin-top:64px;line-height:1.25}h3{font-size:21px;margin-top:30px}
p{max-width:85ch}a{color:var(--accent)}.eyebrow{font-size:13px;letter-spacing:2px;text-transform:uppercase;color:var(--accent);font-weight:700}
.note{border-left:5px solid var(--accent);padding:15px 22px;background:#eaf6f5;margin:24px 0}.future{border-left-color:#ae6c18;background:#fff6e7}
pre{overflow:auto;background:#122b3b;color:#e0f4f5;padding:22px;border-radius:8px;font:14px/1.6 ui-monospace,Consolas,monospace;tab-size:2}
code{font-family:ui-monospace,Consolas,monospace;font-size:.9em}p code,li code,td code{background:#eef3f5;padding:2px 4px;border-radius:3px}
table{border-collapse:collapse;width:100%;font-size:15px;margin:24px 0;display:block;overflow:auto}th,td{text-align:left;vertical-align:top;border-bottom:1px solid #d6e0e4;padding:11px 13px}th{background:#eaf1f3}
details{margin:14px 0;border:1px solid #cbdde1;border-radius:6px;padding:12px}summary{cursor:pointer;font-weight:600;color:var(--accent)}details pre{max-height:720px}
.flow{display:flex;flex-wrap:wrap;gap:10px;margin:25px 0}.flow span{background:#e4f1f1;padding:10px 14px;border-radius:5px;border:1px solid #b1d3d4}
input{width:100%;padding:10px;font:inherit;border:1px solid #88a4ad;border-radius:4px;margin-bottom:14px}.small{font-size:14px;color:var(--muted)}
@media(max-width:900px){nav{position:relative;width:auto;max-height:330px}main{margin:0;padding:30px 20px}}
@media print{nav{display:none}main{margin:0;padding:0;max-width:none}body{font-size:11pt;background:white}h2{break-before:page}pre{white-space:pre-wrap;background:#f2f4f5;color:black}details pre{max-height:none}a{color:inherit}}
'''
document = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Building an Out-of-Order RISC-V Processor</title><style>{style}</style></head>
<body><nav aria-label="Chapters"><strong>OoO / Design laboratory</strong>
<label for="filter">Find a chapter</label><input id="filter" type="search" placeholder="Rename, cache, tests…">
<div id="chapters">{toc}<a href="#rtl">RTL source appendix</a></div></nav><main>{body}
<h2 id="rtl">RTL source appendix</h2><p>These listings are embedded from the actual source by
<code>python scripts/build_docs.py</code>. Open a module to inspect its complete implementation.</p>
{''.join(sources)}</main><script>
document.getElementById('filter').addEventListener('input',event=>{{
const query=event.target.value.toLowerCase();
document.querySelectorAll('#chapters a').forEach(link=>{{link.hidden=!link.textContent.toLowerCase().includes(query)}});
}});
</script></body></html>'''
(ROOT / "docs/tutorial.html").write_text(document, encoding="utf-8", newline="\n")
print(f"Built docs/tutorial.html: {len(chapters)} chapters, {len(sources)} RTL listings")
