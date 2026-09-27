"""Convert a Design Component (.dc.html) into a React class component (JSX).

- <helmet> <style> goes to a CSS file.
- {{path}} holes become JS expressions; loop variables from <sc-for as="x"> stay local, everything else reads `v.` (renderVals()).
- <sc-for list as> → .map(); <sc-if value> → conditional.
- class→className, for→htmlFor, style strings → style objects, SVG/HTML attribute casing restored.
- "/_blob/<id>" literals become `A + "<file>"` (A = the site's asset base).
"""
import html, json, re, sys
from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
ATTR_CASE = {
    "viewbox": "viewBox", "preserveaspectratio": "preserveAspectRatio", "stroke-width": "strokeWidth",
    "stroke-linecap": "strokeLinecap", "stroke-linejoin": "strokeLinejoin", "stroke-dasharray": "strokeDasharray",
    "stroke-opacity": "strokeOpacity", "fill-rule": "fillRule", "clip-rule": "clipRule", "fill-opacity": "fillOpacity",
    "shape-rendering": "shapeRendering", "class": "className", "for": "htmlFor", "tabindex": "tabIndex",
    "autoplay": "autoPlay", "playsinline": "playsInline", "readonly": "readOnly", "maxlength": "maxLength",
    "crossorigin": "crossOrigin", "srcset": "srcSet", "colspan": "colSpan", "rowspan": "rowSpan",
}
EVENTS = {"onclick": "onClick", "onchange": "onChange", "onpointermove": "onPointerMove", "onpointerleave": "onPointerLeave",
          "onpointerover": "onPointerOver", "onpointerdown": "onPointerDown", "onpointerup": "onPointerUp",
          "onpointercancel": "onPointerCancel", "onpointerenter": "onPointerEnter", "oninput": "onInput",
          "onkeydown": "onKeyDown", "onfocus": "onFocus", "onblur": "onBlur", "onmouseenter": "onMouseEnter", "onmouseleave": "onMouseLeave"}
BOOL = {"autoplay", "muted", "loop", "controls", "playsinline", "checked", "disabled", "open", "hidden", "readonly", "required"}
HOLE = re.compile(r"\{\{\s*([^}]+?)\s*\}\}")


class Node:
    def __init__(self, tag, attrs):
        self.tag, self.attrs, self.children = tag, attrs, []


class P(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", [])
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs)
        self.stack[-1].children.append(n)
        if tag not in VOID:
            self.stack.append(n)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].children.append(Node(tag, attrs))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(data)


class Conv:
    def __init__(self, blobmap):
        self.blobmap = blobmap

    def path(self, p, scope):
        p = p.strip()
        if p in ("true", "false", "null") or re.match(r"^-?\d", p):
            return p
        head = p.split(".")[0]
        if head in scope:
            return p
        return "v." + p

    def blob(self, s):
        m = re.fullmatch(r"/_blob/([0-9a-f]{32})", s.strip())
        if m:
            return 'A + ' + json.dumps(self.blobmap[m.group(1)])
        return None

    def interp(self, s, scope):
        """literal with holes → JS expression (template literal) or JSON string"""
        if not HOLE.search(s):
            b = self.blob(s)
            return b if b else json.dumps(s)
        out, last = "`", 0
        for m in HOLE.finditer(s):
            out += s[last:m.start()].replace("\\", "\\\\").replace("`", "\\`").replace("${", "\\${")
            out += "${" + self.path(m.group(1), scope) + "}"
            last = m.end()
        out += s[last:].replace("\\", "\\\\").replace("`", "\\`").replace("${", "\\${") + "`"
        return out

    def style(self, s, scope):
        items = []
        for decl in s.split(";"):
            if ":" not in decl:
                continue
            k, val = decl.split(":", 1)
            k, val = k.strip(), val.strip()
            if not k:
                continue
            key = k if k.startswith("--") else re.sub(r"-([a-z])", lambda m: m.group(1).upper(), k)
            w = HOLE.fullmatch(val)
            expr = self.path(w.group(1), scope) if w else self.interp(val, scope)
            items.append(json.dumps(key) + ": " + expr)
        return "{{" + ", ".join(items) + "}}"

    def attrs(self, n, scope):
        out = []
        for name, val in n.attrs:
            if name.startswith("hint-"):
                continue
            val = "" if val is None else val
            if name == "style":
                out.append("style=" + self.style(val, scope))
                continue
            key = EVENTS.get(name) or ATTR_CASE.get(name) or name
            whole = HOLE.fullmatch(val.strip()) if val else None
            if whole:
                out.append(key + "={" + self.path(whole.group(1), scope) + "}")
            elif name in BOOL and val == "":
                out.append(key + "={true}")
            else:
                out.append(key + "={" + self.interp(val, scope) + "}")
        if n.tag == "video":
            out.append("suppressHydrationWarning={true}")
        return (" " + " ".join(out)) if out else ""

    def text(self, t, scope, pre):
        if not pre:
            t = re.sub(r"\s+", " ", t)
            if t == "":
                return ""
            if t == " ":
                return '{" "}'
        parts, last = [], 0
        for m in HOLE.finditer(t):
            if m.start() > last:
                parts.append("{" + json.dumps(t[last:m.start()]) + "}")
            parts.append("{" + self.path(m.group(1), scope) + "}")
            last = m.end()
        if last < len(t):
            parts.append("{" + json.dumps(t[last:]) + "}")
        return "".join(parts)

    def node(self, n, scope, pre=False):
        if isinstance(n, str):
            return self.text(n, scope, pre)
        tag = n.tag
        a = dict(n.attrs)
        if tag == "sc-for":
            lst = self.path(HOLE.fullmatch(a["list"].strip()).group(1), scope)
            var = a.get("as", "item")
            inner = self.children(n, scope | {var, "$index"}, pre)
            return "{(" + lst + " || []).map((" + var + ", $index) => (<React.Fragment key={$index}>" + inner + "</React.Fragment>))}"
        if tag == "sc-if":
            cond = self.path(HOLE.fullmatch(a["value"].strip()).group(1), scope)
            return "{" + cond + " ? (<>" + self.children(n, scope, pre) + "</>) : null}"
        if tag == "helmet":
            return ""
        cls = a.get("class", "") or ""
        pre2 = pre or ("code" in cls.split() and tag == "div")
        at = self.attrs(n, scope)
        if tag in VOID:
            return "<" + tag + at + " />"
        return "<" + tag + at + ">" + self.children(n, scope, pre2) + "</" + tag + ">"

    def children(self, n, scope, pre=False):
        return "".join(self.node(c, scope, pre) for c in n.children)


def convert(src, name, blobmap):
    helmet_css = "\n".join(re.findall(r"<helmet>.*?<style>(.*?)</style>.*?</helmet>", src, re.S))
    body = re.search(r"<x-dc>(.*?)</x-dc>", src, re.S).group(1)
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    body = re.sub(r"<helmet>.*?</helmet>", "", body, flags=re.S)
    p = P(); p.feed(body)
    jsx = Conv(blobmap).children(p.root, set())
    a = src.index("data-dc-script"); a = src.index(">", a) + 1; b = src.index("</script>", a)
    logic = src[a:b]
    for bid, fname in blobmap.items():
        logic = logic.replace('"/_blob/' + bid + '"', '(this.props.base + "assets/' + fname + '")')
    logic = logic.replace("class Component extends DCLogic {", "export default class " + name + " extends React.Component {", 1)
    # add render() before the final closing brace of the class
    k = logic.rstrip().rfind("}")
    render = ("\n  render() {\n    const v = this.renderVals();\n    const A = this.props.base + \"assets/\";\n"
              "    return (<>" + jsx + "</>);\n  }\n")
    logic = logic[:k] + render + logic[k:]
    out = "import React from \"react\";\n/* Gerado de " + name + ".dc.html (protótipo do editor de design) por tools/dc2jsx.py. */\n" + logic
    return out, helmet_css


if __name__ == "__main__":
    src, name, out_jsx, out_css, blobjson = sys.argv[1:6]
    blobmap = json.load(open(blobjson))
    jsx, css = convert(open(src).read(), name, blobmap)
    open(out_jsx, "w").write(jsx)
    open(out_css, "w").write(css)
    print("ok", name, len(jsx), len(css))
