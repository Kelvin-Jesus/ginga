#!/usr/bin/env python3
"""Exports the Ginga design system as one self-contained HTML page.

    python3 design/ginga-design/tools/export_html.py        # writes design/ginga-design/ginga-design-system.html

The sources are the files of the design system made in Claude (claude.ai/design), kept in this folder:
brand-book.md (the system's README), flows.md, tokens.json, components/<Name>.md (each component's
README), previews/<Name>.html (each component's live preview, unchanged), reference/tokens.css,
bundle.css and bundle.js, logos/ and design-system.json. The page inlines all of them (logos as data
URIs), so it opens offline, can be sent as a single file and is what GitHub Pages serves at
/design-system/. Fonts come from Google Fonts, as in bundle.css. No dependencies beyond Python 3.
"""
import base64
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "ginga-design-system.html"
THEMES = [("light", "Claro"), ("dark", "Escuro"), ("space", "Black espacial")]
GROUP_ORDER = ["Fluxos", "Ações", "Controles", "Status", "Estrutura", "Marca"]


# ---------------------------------------------------------------- markdown (the subset these docs use)

def inline(text):
    parts = re.split(r"(`[^`]*`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) >= 2:
            out.append("<code>" + html.escape(part[1:-1]) + "</code>")
            continue
        t = html.escape(part, quote=False)
        t = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', t)
        t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
        t = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", t)
        out.append(t)
    return "".join(out)


def cells(row):
    row = row.strip().strip("|")
    parts, cur, tick = [], "", False
    for ch in row:
        if ch == "`":
            tick = not tick
        if ch == "|" and not tick:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    parts.append(cur.strip())
    return parts


def markdown(text, skip_title=True, shift=1):
    lines = text.strip("\n").split("\n")
    if skip_title and lines and lines[0].startswith("# "):
        lines = lines[1:]
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            level = min(6, len(m.group(1)) + shift)
            title = m.group(2).strip()
            slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
            out.append(f'<h{level} id="md-{slug}">{inline(title)}</h{level}>')
            i += 1
            continue
        if line.lstrip().startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|?\s*:?-{3,}", lines[i + 1]):
            head = cells(line)
            i += 2
            body = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                body.append(cells(lines[i]))
                i += 1
            t = ['<div class="table"><table><thead><tr>' + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"]
            for r in body:
                t.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            out.append("".join(t))
            continue
        if re.match(r"^\s*[-*]\s+", line) or re.match(r"^\s*\d+\.\s+", line):
            ordered = bool(re.match(r"^\s*\d+\.\s+", line))
            items = []
            pat = r"^\s*\d+\.\s+" if ordered else r"^\s*[-*]\s+"
            while i < len(lines) and re.match(pat, lines[i]):
                item = re.sub(pat, "", lines[i])
                i += 1
                while i < len(lines) and lines[i].startswith("  ") and lines[i].strip() and not re.match(r"^\s*([-*]|\d+\.)\s+", lines[i]):
                    item += " " + lines[i].strip()
                    i += 1
                items.append(f"<li>{inline(item)}</li>")
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(items) + f"</{tag}>")
            continue
        para = [line.strip()]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#{1,6}\s|\s*[-*]\s+|\s*\d+\.\s+|\s*\|)", lines[i]):
            para.append(lines[i].strip())
            i += 1
        out.append("<p>" + inline(" ".join(para)) + "</p>")
    return "\n".join(out)


# ---------------------------------------------------------------- sources

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def data_uri(path, mime):
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()


def ds_card(preview):
    first = preview.split("\n", 1)[0]
    m = re.match(r"<!--\s*@dsCard(.*?)-->", first)
    attrs = {}
    if m:
        for k, v in re.findall(r'(\w+)=("[^"]*"|\S+)', m.group(1)):
            attrs[k] = v.strip('"')
        attrs["page"] = " page" in m.group(1) + " "
    return attrs


def main():
    index = json.loads(read("design-system.json"))
    tokens = json.loads(read("tokens.json"))
    logos = index["assetGroups"]["Logos"]
    blob_uri = {f["blob"]: data_uri(ROOT / "logos" / f["name"], f["type"]) for f in logos["files"].values()}

    def unblob(text):
        return re.sub(r"/_blob/([0-9a-f]{32})", lambda m: blob_uri.get(m.group(1), m.group(0)), text)

    # component previews, grouped as the design system groups its cards
    components = []
    for path in sorted((ROOT / "previews").glob("*.html")):
        name = path.stem
        src = path.read_text(encoding="utf-8")
        card = ds_card(src)
        body = src.split("\n", 1)[1] if src.startswith("<!--") else src
        readme = (ROOT / "components" / f"{name}.md")
        components.append({
            "name": name,
            "group": card.get("group", ""),
            "subtitle": card.get("subtitle", ""),
            "height": int(card.get("height", 200)),
            "width": int(card["width"]) if "width" in card else (960 if name == "Cover" else 0),
            "readme": markdown(readme.read_text(encoding="utf-8")) if readme.exists() else "",
            "html": unblob(body),
        })
    cover = next(c for c in components if c["name"] == "Cover")
    cards = [c for c in components if c["name"] != "Cover"]
    cards.sort(key=lambda c: (GROUP_ORDER.index(c["group"]) if c["group"] in GROUP_ORDER else 99, c["name"]))

    shared = {
        "tokensCss": read("reference/tokens.css"),
        "bundleCss": read("reference/bundle.css"),
        "bundleJs": read("reference/bundle.js"),
        "previews": {c["name"]: c["html"] for c in components},
    }

    # ---- sections
    nav, sections = [], []

    def section(sid, title, body, sub=None):
        nav.append((sid, title, sub))
        sections.append(f'<section id="{sid}"><h2>{html.escape(title)}</h2>{body}</section>')

    sections.append(f'<section id="capa" class="cover-section">{preview_frame(cover)}</section>')
    nav.append(("capa", "Capa", None))
    section("marca", "Marca", f'<div class="prose">{markdown(read("brand-book.md"), skip_title=False)}</div>')
    section("fluxos", "Fluxos de UI/UX", f'<div class="prose">{markdown(read("flows.md"))}</div>')

    # colours
    theme_ids = [t["id"] for t in tokens["color"]["themes"]]
    rows = []
    for tok in tokens["color"]["tokens"]:
        v = tok["value"]
        values = v if isinstance(v, dict) else {t: v for t in theme_ids}
        chips = "".join(
            f'<span class="chip" title="{html.escape(dict(THEMES).get(t, t))}"><i style="background:{values.get(t, values[theme_ids[0]])}"></i>'
            f'<span class="mono">{html.escape(values.get(t, values[theme_ids[0]]))}</span></span>'
            for t in theme_ids)
        rows.append(f'<article class="swatch"><div class="swatch__fill" style="background:var(--{tok["name"]})"></div>'
                    f'<div class="swatch__body"><h3 class="mono">{html.escape(tok["name"])}</h3><div class="chips">{chips}</div>'
                    f'<p>{inline(tok.get("usage", ""))}</p></div></article>')
    section("cores", "Cores", '<p class="lead">Os valores de cada tema: Claro, Escuro e Black espacial. O quadrado grande segue o tema escolhido no topo.</p>'
            f'<div class="swatches">{"".join(rows)}</div>')

    # type
    fam = tokens["type"]["families"]
    blocks = []
    for group in tokens["type"]["groups"]:
        items = []
        for st in group["styles"]:
            ls = st.get("letterSpacing", "normal")
            style = (f'font-family:{html.escape(fam[group["family"]], quote=True)};font-size:{st["fontSize"]};'
                     f'line-height:{st["lineHeight"]};font-weight:{st["fontWeight"]};letter-spacing:{ls}')
            spec = f'{st["fontSize"]}/{st["lineHeight"]} · {st["fontWeight"]}' + (f" · {ls}" if ls != "normal" else "")
            items.append(f'<div class="type-row"><div class="type-meta"><span class="mono name">{st["name"]}</span>'
                         f'<span class="mono spec">{spec}</span><p>{inline(st.get("usage", ""))}</p></div>'
                         f'<div class="type-sample" style="{style}">{html.escape(st.get("sample", st["name"]))}</div></div>')
        family_name = fam[group["family"]].split(",")[0].strip('"')
        blocks.append(f'<h3>{html.escape(group["name"])} <span class="muted">· {html.escape(family_name)}</span></h3>' + "".join(items))
    section("tipografia", "Tipografia", "".join(blocks))

    # spacing, radius
    sp = "".join(f'<div class="scale-row"><span class="mono name">{t["name"]}</span><span class="mono spec">{t["value"]}</span>'
                 f'<span class="bar" style="width:{t["value"]}"></span><p>{inline(t.get("usage", ""))}</p></div>' for t in tokens["spacing"]["tokens"])
    section("espaco", "Espaçamento", f'<div class="scale">{sp}</div>')
    rd = "".join(f'<div class="radius"><div class="radius__box" style="border-radius:{t["value"]}"></div><span class="mono name">{t["name"]}</span>'
                 f'<span class="mono spec">{t["value"]}</span><p>{inline(t.get("usage", ""))}</p></div>' for t in tokens["radius"]["tokens"])
    section("raios", "Raios", f'<div class="radii">{rd}</div>')

    # shadows
    sh = "".join(f'<div class="shadow"><div class="shadow__box" style="box-shadow:var(--{t["name"]})"></div><span class="mono name">{t["name"]}</span>'
                 f'<p>{inline(t.get("usage", ""))}</p></div>' for t in tokens["shadow"]["tokens"])
    note = tokens["shadow"].get("note", "")
    section("sombras", "Sombras e brilhos", (f'<p class="lead">{inline(note)}</p>' if note else "") + f'<div class="shadows">{sh}</div>')

    # motion
    mv = []
    for t in tokens["duration"]["tokens"]:
        mv.append(f'<div class="motion-row"><span class="mono name">{t["name"]}</span><span class="mono spec">{t["value"]}</span>'
                  f'<button class="play" data-dur="{t["value"]}" data-ease="var(--ease-ginga)" aria-label="Ver {t["name"]}"><i></i></button><p>{inline(t.get("usage", ""))}</p></div>')
    for t in tokens["easing"]["tokens"]:
        mv.append(f'<div class="motion-row"><span class="mono name">{t["name"]}</span><span class="mono spec">{html.escape(t["value"])}</span>'
                  f'<button class="play" data-dur="900ms" data-ease="{html.escape(t["value"], quote=True)}" aria-label="Ver {t["name"]}"><i></i></button><p>{inline(t.get("usage", ""))}</p></div>')
    section("movimento", "Movimento", '<p class="lead">Clique numa trilha para ver a duração ou a curva.</p><div class="motion">' + "".join(mv) + "</div>")

    # logos
    tiles = []
    for name in logos["order"]:
        f = logos["files"][name]
        dark = "-dark" in name
        tiles.append(f'<figure class="logo{" logo--dark" if dark else ""}"><img src="{blob_uri[f["blob"]]}" alt="{html.escape(name)}">'
                     f'<figcaption class="mono">{html.escape(name)}</figcaption></figure>')
    section("logos", "Logos", f'<div class="prose">{markdown(read("logos/README.md"))}</div><div class="logos">{"".join(tiles)}</div>')

    # components
    comp_html = []
    groups_seen = []
    for c in cards:
        if c["group"] not in groups_seen:
            groups_seen.append(c["group"])
            comp_html.append(f'<h3 class="group">{html.escape(c["group"])}</h3>')
        comp_html.append(f'<article class="card" id="c-{c["name"]}"><header><h4>{c["name"]}</h4>'
                         f'<p class="muted">{html.escape(c["subtitle"])}</p></header>{preview_frame(c)}'
                         f'<div class="prose">{c["readme"]}</div></article>')
    section("componentes", "Componentes", "".join(comp_html), sub=[(f"c-{c['name']}", c["name"]) for c in cards])

    last = index.get("lastChange", {})
    nav_html = []
    for sid, title, sub in nav:
        nav_html.append(f'<a href="#{sid}">{html.escape(title)}</a>')
        if sub:
            nav_html.append('<div class="sub">' + "".join(f'<a href="#{s}">{html.escape(t)}</a>' for s, t in sub) + "</div>")

    page = TEMPLATE
    page = page.replace("{{TOKENS_CSS}}", shared["tokensCss"])
    page = page.replace("{{FAVICON}}", blob_uri[logos["files"]["ginga-app-icon.png"]["blob"]])
    page = page.replace("{{WORDMARK}}", blob_uri[logos["files"]["ginga-wordmark.png"]["blob"]])
    page = page.replace("{{WORDMARK_DARK}}", blob_uri[logos["files"]["ginga-wordmark-dark.png"]["blob"]])
    page = page.replace("{{NAV}}", "\n".join(nav_html))
    page = page.replace("{{SECTIONS}}", "\n".join(sections))
    page = page.replace("{{UPDATED}}", html.escape((last.get("at") or "")[:10]))
    page = page.replace("{{DATA}}", json.dumps(shared, ensure_ascii=False).replace("</", "<\\/"))
    OUT.write_text(page, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT.parent.parent)} ({OUT.stat().st_size // 1024} KB, {len(cards)} components)")


def preview_frame(c):
    w = c["width"]
    return (f'<div class="frame" data-preview="{c["name"]}" data-w="{w}" data-h="{c["height"]}" style="height:{c["height"]}px">'
            f'<iframe title="{html.escape(c["name"])}" loading="lazy" style="height:{c["height"]}px{";width:" + str(w) + "px" if w else ""}"></iframe></div>')


TEMPLATE = r"""<!doctype html>
<html lang="pt-BR" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ginga — design system</title>
<meta name="description" content="Design system do Ginga: marca, fluxos, cores, tipografia, espaçamento, movimento, logos e componentes com prévias ao vivo.">
<link rel="icon" href="{{FAVICON}}">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&family=Unbounded:wght@600;800&display=swap">
<style>
{{TOKENS_CSS}}
:root { color-scheme: light; }
[data-theme="dark"], [data-theme="space"] { color-scheme: dark; }
* { box-sizing: border-box; }
html { scroll-behavior: smooth; scroll-padding-top: 72px; }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
body { margin: 0; background: var(--bg); color: var(--ink); font: 400 15px/22px var(--font-sans); -webkit-font-smoothing: antialiased; }
a { color: var(--cobalt); }
.mono, code { font-family: var(--font-mono); font-variant-numeric: tabular-nums; }
code { font-size: .88em; padding: 1px 5px; border-radius: 6px; background: var(--surface-2); }
.muted { color: var(--ink-muted); font-weight: 400; }
.top { position: sticky; top: 0; z-index: 10; display: flex; align-items: center; gap: 16px; height: 60px; padding: 0 24px; background: color-mix(in srgb, var(--bg) 88%, transparent); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border-bottom: 1px solid var(--line); }
.top img { height: 24px; display: block; }
.top .logo-dark { display: none; }
[data-theme="dark"] .top .logo-light, [data-theme="space"] .top .logo-light { display: none; }
[data-theme="dark"] .top .logo-dark, [data-theme="space"] .top .logo-dark { display: block; }
.top .title { font: 600 13px/18px var(--font-mono); color: var(--ink-muted); letter-spacing: .06em; text-transform: uppercase; }
.top .grow { flex: 1; }
.seg { display: inline-flex; padding: 3px; gap: 2px; border-radius: 12px; background: var(--surface-2); }
.seg button { height: 30px; padding: 0 12px; border: 0; border-radius: 9px; background: none; color: var(--ink-muted); font: 500 13px/18px var(--font-sans); cursor: pointer; white-space: nowrap; }
.seg button[aria-pressed="true"] { background: var(--surface); color: var(--ink); box-shadow: var(--shadow-card); }
.seg button:focus-visible, .play:focus-visible, .side a:focus-visible { outline: 2px solid var(--cobalt); outline-offset: 2px; }
[data-theme="space"] .seg { background: transparent; box-shadow: inset 0 0 0 1px var(--line); }
[data-theme="space"] .seg button[aria-pressed="true"] { background: var(--cobalt-soft); box-shadow: none; }
.layout { display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 40px; max-width: 1320px; margin: 0 auto; padding: 32px 24px 96px; }
.side { position: sticky; top: 92px; align-self: start; max-height: calc(100vh - 110px); overflow: auto; display: flex; flex-direction: column; gap: 2px; font-size: 14px; }
.side a { color: var(--ink-muted); text-decoration: none; padding: 5px 10px; border-radius: 8px; }
.side a:hover { color: var(--ink); background: var(--surface-2); }
.side a.on { color: var(--ink); background: var(--cobalt-soft); }
.side .sub { display: flex; flex-direction: column; gap: 1px; margin: 2px 0 6px 10px; padding-left: 8px; border-left: 1px solid var(--line); font-size: 13px; }
.side .updated { margin-top: 16px; padding: 0 10px; font: 400 12px/16px var(--font-mono); color: var(--ink-muted); }
main { min-width: 0; }
section { margin: 0 0 72px; }
section > h2 { margin: 0 0 20px; font: 600 28px/34px var(--font-display); letter-spacing: -0.01em; }
h3 { margin: 32px 0 12px; font: 600 17px/24px var(--font-sans); }
h3.group { margin: 40px 0 16px; font: 600 12px/16px var(--font-mono); letter-spacing: .08em; text-transform: uppercase; color: var(--ink-muted); }
.lead { color: var(--ink-muted); margin: -8px 0 20px; max-width: 70ch; }
.prose { max-width: 76ch; }
.prose h3 { margin-top: 28px; } .prose h4 { margin: 20px 0 8px; font: 600 15px/22px var(--font-sans); }
.prose p, .prose li { color: var(--ink); } .prose ul, .prose ol { padding-left: 22px; } .prose li { margin: 4px 0; }
.table { overflow-x: auto; margin: 12px 0 20px; }
table { border-collapse: collapse; font-size: 14px; line-height: 20px; min-width: 520px; }
th, td { text-align: left; vertical-align: top; padding: 8px 12px; border-bottom: 1px solid var(--line); }
th { font-weight: 600; color: var(--ink-muted); font-size: 13px; }
.cover-section { margin-bottom: 56px; }
.frame { position: relative; overflow: hidden; border-radius: 18px; background: var(--bg); box-shadow: inset 0 0 0 1px var(--line); }
.frame iframe { display: block; border: 0; width: 100%; transform-origin: 0 0; background: transparent; }
.card { margin: 0 0 32px; padding: 20px; border-radius: 18px; background: var(--surface); box-shadow: var(--shadow-card); }
[data-theme="space"] .card { box-shadow: inset 0 0 0 1px var(--line); }
.card header { display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; margin-bottom: 14px; }
.card h4 { margin: 0; font: 600 20px/26px var(--font-display); }
.card header p { margin: 0; font-size: 13px; }
.card .prose { margin-top: 16px; font-size: 14px; line-height: 21px; }
.swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; }
.swatch { border-radius: 18px; overflow: hidden; background: var(--surface); box-shadow: var(--shadow-card); }
[data-theme="space"] .swatch { box-shadow: inset 0 0 0 1px var(--line); }
.swatch__fill { height: 72px; box-shadow: inset 0 -1px 0 var(--line); }
.swatch__body { padding: 12px 14px 14px; }
.swatch h3 { margin: 0 0 8px; font-size: 14px; }
.swatch p { margin: 8px 0 0; font-size: 13px; line-height: 18px; color: var(--ink-muted); }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { display: inline-flex; align-items: center; gap: 5px; font-size: 11px; color: var(--ink-muted); }
.chip i { width: 12px; height: 12px; border-radius: 4px; box-shadow: inset 0 0 0 1px rgba(128,128,128,.35); }
.type-row { display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 24px; align-items: center; padding: 16px 0; border-bottom: 1px solid var(--line); }
.type-meta .name { display: block; font-weight: 500; }
.type-meta .spec { display: block; font-size: 12px; color: var(--ink-muted); }
.type-meta p { margin: 6px 0 0; font-size: 13px; line-height: 18px; color: var(--ink-muted); }
.type-sample { overflow-wrap: anywhere; }
.scale-row, .motion-row { display: grid; grid-template-columns: 120px 90px minmax(0, 220px) minmax(0, 1fr); gap: 16px; align-items: center; padding: 10px 0; border-bottom: 1px solid var(--line); }
.scale-row p, .motion-row p, .radius p, .shadow p { margin: 0; font-size: 13px; line-height: 18px; color: var(--ink-muted); }
.spec { color: var(--ink-muted); font-size: 13px; }
.bar { display: block; height: 12px; border-radius: 4px; background: var(--cobalt); }
.radii, .shadows { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 20px; }
.radius__box { width: 96px; height: 72px; margin-bottom: 10px; background: var(--cobalt-soft); box-shadow: inset 0 0 0 1.5px var(--cobalt); }
.radius .name, .shadow .name { display: block; font-weight: 500; }
.shadow__box { height: 88px; margin: 8px 8px 14px; border-radius: 18px; background: var(--surface); }
[data-theme="space"] .shadow__box { background: #000; }
.play { position: relative; width: 100%; height: 24px; border: 0; border-radius: 999px; background: var(--surface-2); cursor: pointer; }
.play i { position: absolute; top: 4px; left: 4px; width: 16px; height: 16px; border-radius: 50%; background: var(--cobalt); }
.play.go i { left: calc(100% - 20px); }
.logos { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; margin-top: 20px; }
.logo { margin: 0; padding: 24px 16px 12px; border-radius: 18px; background: #FFFFFF; box-shadow: inset 0 0 0 1px var(--line); display: flex; flex-direction: column; align-items: center; gap: 12px; }
.logo--dark { background: #0A0C1C; }
.logo img { max-width: 100%; height: 96px; object-fit: contain; }
.logo figcaption { font-size: 11px; color: #565B78; } .logo--dark figcaption { color: #A4A9C8; }
footer { margin-top: 24px; font-size: 13px; color: var(--ink-muted); }
@media (max-width: 900px) {
  .layout { grid-template-columns: minmax(0, 1fr); padding: 20px 16px 72px; gap: 0; }
  .side { display: none; }
  .top { padding: 0 16px; gap: 10px; } .top .title { display: none; }
  .seg button { padding: 0 8px; font-size: 12px; }
  .type-row { grid-template-columns: minmax(0, 1fr); gap: 8px; }
  .scale-row, .motion-row { grid-template-columns: 110px 70px minmax(0, 1fr); }
  .scale-row p, .motion-row p { grid-column: 1 / -1; }
  .card { padding: 14px; }
}
</style>
</head>
<body>
<header class="top">
  <img class="logo-light" src="{{WORDMARK}}" alt="Ginga"><img class="logo-dark" src="{{WORDMARK_DARK}}" alt="Ginga">
  <span class="title">design system</span>
  <span class="grow"></span>
  <div class="seg" role="group" aria-label="Tema">
    <button data-theme-set="light">Claro</button><button data-theme-set="dark">Escuro</button><button data-theme-set="space">Black espacial</button>
  </div>
</header>
<div class="layout">
  <nav class="side" aria-label="Seções">
{{NAV}}
    <div class="updated">atualizado em {{UPDATED}}</div>
  </nav>
  <main>
{{SECTIONS}}
    <footer>Exportado do design system do Ginga feito no Claude. Fonte: <code>design/ginga-design/</code> no repositório, gerado por <code>tools/export_html.py</code>.</footer>
  </main>
</div>
<script type="application/json" id="ds-data">{{DATA}}</script>
<script>
(function () {
  var D = JSON.parse(document.getElementById("ds-data").textContent);
  var root = document.documentElement, KEY = "ginga-ds-theme", theme = "light";
  try { theme = localStorage.getItem(KEY) || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"); } catch (e) {}

  /* each preview runs in its own document with the tokens, the fonts, bundle.css and bundle.js, as in Claude */
  function doc(name) {
    var src = D.previews[name];
    var head = "<style>" + D.tokensCss + "</style><style>" + D.bundleCss + "</style><script>" + D.bundleJs + "<\/script>";
    src = src.replace(/<html([^>]*)>/i, function (m, a) { return "<html" + a.replace(/\sdata-theme="[^"]*"/, "") + ' data-theme="' + theme + '">'; });
    return /<head[^>]*>/i.test(src) ? src.replace(/<head[^>]*>/i, function (m) { return m + head; }) : head + src;
  }
  var frames = [].slice.call(document.querySelectorAll(".frame"));
  function fit(f) {
    var w = +f.dataset.w, h = +f.dataset.h, ifr = f.firstChild;
    if (!w) { f.style.height = h + "px"; return; }
    var s = Math.min(1, f.clientWidth / w);
    ifr.style.transform = s < 1 ? "scale(" + s + ")" : "";
    f.style.height = Math.round(h * s) + "px";
  }
  function load(f) { f.firstChild.srcdoc = doc(f.dataset.preview); f.dataset.loaded = theme; }
  var io = "IntersectionObserver" in window ? new IntersectionObserver(function (es) {
    es.forEach(function (e) { if (e.isIntersecting && e.target.dataset.loaded !== theme) load(e.target); });
  }, { rootMargin: "400px 0px" }) : null;
  frames.forEach(function (f) { fit(f); if (io) io.observe(f); else load(f); });
  if ("ResizeObserver" in window) new ResizeObserver(function () { frames.forEach(fit); }).observe(document.querySelector("main"));

  function apply(t) {
    theme = t; root.dataset.theme = t;
    try { localStorage.setItem(KEY, t); } catch (e) {}
    [].forEach.call(document.querySelectorAll("[data-theme-set]"), function (b) { b.setAttribute("aria-pressed", String(b.dataset.themeSet === t)); });
    frames.forEach(function (f) {
      if (!f.dataset.loaded) return;
      var r = f.getBoundingClientRect();
      if (r.bottom > -400 && r.top < innerHeight + 400) load(f); else delete f.dataset.loaded;
    });
  }
  [].forEach.call(document.querySelectorAll("[data-theme-set]"), function (b) { b.onclick = function () { apply(b.dataset.themeSet); }; });
  apply(theme);

  [].forEach.call(document.querySelectorAll(".play"), function (b) {
    b.onclick = function () {
      var i = b.firstChild; i.style.transition = "none"; b.classList.remove("go"); void i.offsetWidth;
      i.style.transition = "left " + b.dataset.dur + " " + b.dataset.ease; b.classList.add("go");
    };
  });

  /* highlights the section in view in the side menu */
  var links = {}; [].forEach.call(document.querySelectorAll(".side a"), function (a) { links[a.getAttribute("href").slice(1)] = a; });
  if (io) {
    var spy = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { for (var k in links) links[k].classList.remove("on"); var a = links[e.target.id]; if (a) a.classList.add("on"); } });
    }, { rootMargin: "-20% 0px -70% 0px" });
    [].forEach.call(document.querySelectorAll("main section, main .card"), function (s) { spy.observe(s); });
  }
})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
