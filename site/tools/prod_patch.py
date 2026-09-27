"""Turn the design prototypes (.dc.html) into production variants before converting them to JSX.
Usage: python3 tools/prod_patch.py <Main.dc.html> <404.dc.html> <outdir>
"""
import sys, os

main_src, nf_src, out = sys.argv[1:4]


def rep(s, a, b, label):
    assert a in s, "missing: " + label
    return s.replace(a, b, 1)


# ---------------- Home ----------------
s = open(main_src).read()
s = rep(s, 'this.state = { lang: "pt",', 'this.state = { lang: props.lang || "pt",', "initial lang")
s = rep(s, '''    if (this._langFromUrl) this.setState({ lang: this._langFromUrl });
    else { try { if ((navigator.language || "").toLowerCase().indexOf("pt") !== 0) this.setState({ lang: "en" }); } catch (e) {} }''',
        '''    if (!this.props.lang) {
      if (this._langFromUrl) this.setState({ lang: this._langFromUrl });
      else { try { if ((navigator.language || "").toLowerCase().indexOf("pt") !== 0) this.setState({ lang: "en" }); } catch (e) {} }
    }
    this.arrive();''', "mount lang")
s = rep(s, '''    try { var u = new URL(location.href); u.searchParams.set("lang", L); history.replaceState(null, "", u.pathname + u.search + u.hash); } catch (e) {}''',
        '''    try { history.replaceState(null, "", (this.props.base || "/") + L + "/" + location.hash); } catch (e) {}
    try { var md = document.querySelector('meta[name="description"]'); if (md) md.setAttribute("content", t.metaDesc); } catch (e) {}''', "syncLang")
# arrival from the 404: the black hole spits the page out
s = rep(s, '  syncLang() {', '''  arrive() {
    var from = false;
    try { from = sessionStorage.getItem("ginga-from-404") === "1"; sessionStorage.removeItem("ginga-from-404"); } catch (e) {}
    if (!from) return;
    var self = this, rm = !!(window.Ginga && window.Ginga.reducedMotion);
    if (rm) return;
    this.setState({ arriving: true });
    setTimeout(function () { if (self.bhLoop) self.bhLoop.shade.tb = self.bhLoop.now(); }, 60);
    setTimeout(function () { self.setState({ arriving: false }); }, 1500);
  }
  syncLang() {''', "arrive")
s = rep(s, '<div class="site g-root {{astroCls}}"', '<div class="site g-root {{astroCls}} {{arriveCls}}"', "arrive class")
s = rep(s, '      astroCls: s.astroOn ? "astro-on" : "",', '      astroCls: s.astroOn ? "astro-on" : "", arriveCls: s.arriving ? "arrive" : "",', "arrive val")
s = rep(s, '    docTitle: "Ginga — seu Galaxy Tab vira tela do Mac",',
        '    docTitle: "Ginga — seu Galaxy Tab vira tela do Mac", metaDesc: "Ginga transforma um Galaxy Tab em display estendido do Mac com toque e S Pen. USB direto a 120 fps, Wi‑Fi ou sem roteador. Grátis e de código aberto.",', "meta pt")
s = rep(s, '    docTitle: "Ginga — your Galaxy Tab becomes a Mac display",',
        '    docTitle: "Ginga — your Galaxy Tab becomes a Mac display", metaDesc: "Ginga turns a Galaxy Tab into an extended Mac display with touch and S Pen. Direct USB at 120 fps, Wi‑Fi or no router. Free and open source.",', "meta en")
# full demo video (Remotion GingaHero, one per language), loaded only near the viewport
s = rep(s, '<video ref="{{refVid}}" src="/_blob/f195cb7509dc51f7df8a99a6d0180d0f" poster="/_blob/cf6d4ab242897316cb20248dfdcef847" autoplay="" muted="" loop="" playsinline="" preload="metadata" aria-label="{{t.vidAlt}}"></video>',
        '<video ref="{{refVid}}" src="{{vidSrc}}" poster="{{vidPoster}}" muted="" loop="" playsinline="" controls="" preload="none" aria-label="{{t.vidAlt}}"></video>', "video el")
s = rep(s, '''    try { var v = this.r.vid; if (v) { v.muted = true; var rmv = !!(window.Ginga && window.Ginga.reducedMotion); if (rmv) { v.removeAttribute("autoplay"); v.controls = true; } else { var pr = v.play(); if (pr && pr.catch) pr.catch(function () { v.controls = true; }); } } } catch (e) {}''',
        '''    try {
      var v = this.r.vid, rmv = !!(window.Ginga && window.Ginga.reducedMotion);
      if (v) {
        v.muted = true;
        var playV = function () { if (self._vidVis && !rmv && !self._vidUserPaused) { var pr = v.play(); if (pr && pr.catch) pr.catch(function () {}); } };
        this._playVid = playV;
        v.addEventListener("pause", function () { if (self._vidVis && !v.seeking && v.readyState >= 2 && document.visibilityState === "visible") self._vidUserPaused = true; });
        v.addEventListener("play", function () { self._vidUserPaused = false; });
        v.addEventListener("loadeddata", playV);
        if (window.IntersectionObserver) {
          this._vidIO = new IntersectionObserver(function (en) {
            self._vidVis = en[0].isIntersecting;
            if (self._vidVis) { if (v.preload !== "auto") { v.preload = "auto"; v.load(); } playV(); } else if (!v.paused) { v.pause(); self._vidUserPaused = false; }
          }, { rootMargin: "200px 0px" });
          this._vidIO.observe(v);
        } else { v.preload = "metadata"; }
      }
    } catch (e) {}''', "video mount")
s = rep(s, '  componentWillUnmount() {\n', '  componentWillUnmount() {\n    if (this._vidIO) this._vidIO.disconnect();\n', "video unmount")
s = rep(s, '      astroCls: s.astroOn ? "astro-on" : "",',
        '      vidSrc: (this.props.base || "/") + "assets/ginga-demo-" + L + ".mp4", vidPoster: (this.props.base || "/") + "assets/ginga-demo-poster.jpg",\n      astroCls: s.astroOn ? "astro-on" : "",', "video vals")
s = rep(s, 'vidH: "O cometa: Mac e tablet entrando em órbita", vidAlt: "Animação: o Mac envia o sinal como um cometa até o Galaxy Tab, que entra em warp e mostra a janela de Notas.", vidTag: "prévia · vídeo completo em breve",',
        'vidH: "O Ginga em 30 segundos", vidAlt: "Vídeo de 30 segundos: o Mac aceita tablets por Wi‑Fi, o Galaxy Tab pareia com um código de 6 dígitos, o sinal chega como um cometa, uma janela passa para o tablet e a S Pen escreve nela.", vidTag: "demo · 30 s",', "vid pt")
s = rep(s, 'vidH: "The comet: Mac and tablet entering orbit", vidAlt: "Animation: the Mac sends the signal like a comet to the Galaxy Tab, which warps in and shows the Notes window.", vidTag: "preview · full video soon",',
        'vidH: "Ginga in 30 seconds", vidAlt: "30-second video: the Mac accepts tablets over Wi‑Fi, the Galaxy Tab pairs with a 6-digit code, the signal arrives as a comet, a window moves onto the tablet and the S Pen writes on it.", vidTag: "demo · 30 s",', "vid en")
open(os.path.join(out, "Main.prod.dc.html"), "w").write(s)

# ---------------- 404 ----------------
n = open(nf_src).read()
n = rep(n, '<a class="back" href="Main.dc.html">Voltar para a órbita</a>',
        '<a class="back" href="{{homeHref}}" onClick="{{goHome}}">Voltar para a órbita</a>', "back link")
n = rep(n, '<a href="Main.dc.html" style="color: #A4A9C8;">Back to orbit</a>',
        '<a href="{{homeHrefEn}}" onClick="{{goHomeEn}}" style="color: #A4A9C8;">Back to orbit</a>', "back en")
n = rep(n, '<div class="txt {{showCls}}">', '<div class="txt {{showCls}} {{leaveCls}}">', "leave class")
n = rep(n, '.txt.show { opacity: 1; transform: none; }',
        '.txt.show { opacity: 1; transform: none; }\n.txt.leave { opacity: 0 !important; transform: scale(.94) !important; transition: opacity 300ms, transform 400ms; }', "leave css")
n = rep(n, '  renderVals() { var self = this; return {',
        '''  /* 404 → home: o buraco negro devolve a página. Os ladrilhos saem do horizonte em espiral e se
     encaixam no lugar; então o navegador troca para a home (com View Transition onde houver suporte). */
  goTo(href) {
    var self = this, cv = this.r.pieces, rm = false;
    try { rm = window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) {}
    try { sessionStorage.setItem("ginga-from-404", "1"); } catch (e) {}
    if (rm || !cv || !this.r.bh) { location.href = href; return; }
    if (this.swRaf) cancelAnimationFrame(this.swRaf);
    this.setState({ leaving: true });
    var W = cv.width = window.innerWidth, H = cv.height = window.innerHeight, ctx = cv.getContext("2d");
    var page = this.drawPage(W, H);
    var bhr = this.r.bh.getBoundingClientRect(), hx = bhr.left + bhr.width / 2, hy = bhr.top + bhr.height * 0.52, R = Math.max(30, 0.28 * bhr.height / 2);
    var cols = W < 700 ? 8 : 14, rows = W < 700 ? 12 : 9, tw = W / cols, th = H / rows, T = [], maxD = 1;
    for (var y = 0; y < rows; y++) for (var x = 0; x < cols; x++) {
      var cx = x * tw + tw / 2, cy = y * th + th / 2, dx = cx - hx, dy = cy - hy, d = Math.hypot(dx, dy); maxD = Math.max(maxD, d);
      T.push({ sx: x * tw, sy: y * th, rt: d, tt: Math.atan2(dy, dx), turns: 0.6 + Math.random() * 0.6, spin: (Math.random() - 0.5) * 5, d: d });
    }
    T.forEach(function (p) { p.delay = 0.15 + (p.d / maxD) * 0.8 + Math.random() * 0.15; });
    if (this.loop) { this.loop.shade.pullT = 0; this.loop.shade.tb = this.loop.now(); }
    var t0 = performance.now(), DUR = 1.1;
    var ease = function (x) { return 1 - Math.pow(1 - x, 3); };
    var step = function (now) {
      var t = (now - t0) / 1000, done = 0;
      ctx.clearRect(0, 0, W, H);
      for (var i = 0; i < T.length; i++) {
        var p = T[i], q = Math.max(0, Math.min(1, (t - p.delay) / DUR));
        if (q <= 0) continue;
        if (q >= 1) { done++; ctx.drawImage(page, p.sx, p.sy, tw, th, p.sx, p.sy, tw + 0.6, th + 0.6); continue; }
        var e = ease(q), r = R + (p.rt - R) * e, a = p.tt - p.turns * 6.2832 * Math.pow(1 - q, 2), F = 0.42 + 0.58 * e;
        var X = hx + r * Math.cos(a), Y = hy + r * Math.sin(a) * F;
        var st = 1 + 2.6 * Math.pow(1 - q, 3), sc = 0.12 + 0.88 * e, ang = Math.atan2(hy - Y, hx - X);
        ctx.save(); ctx.translate(X, Y); ctx.rotate(ang); ctx.scale(st, 1 / Math.sqrt(st)); ctx.rotate(-ang + p.spin * (1 - e));
        ctx.globalAlpha = Math.min(1, 0.3 + e);
        ctx.drawImage(page, p.sx, p.sy, tw, th, -tw * sc / 2, -th * sc / 2, tw * sc, th * sc);
        ctx.restore();
      }
      if (done === T.length) { setTimeout(function () { location.href = href; }, 120); return; }
      self.swRaf = requestAnimationFrame(step);
    };
    this.swRaf = requestAnimationFrame(step);
  }
  renderVals() { var self = this; var base = this.props.base || "/"; var hl = (this.state && this.state.homeLang) || "pt"; return {
      homeHref: base + hl + "/", homeHrefEn: base + "en/", leaveCls: this.state && this.state.leaving ? "leave" : "",
      goHome: function (e) { e.preventDefault(); self.goTo(base + hl + "/"); },
      goHomeEn: function (e) { e.preventDefault(); self.goTo(base + "en/"); },''', "goTo")
n = rep(n, '    this.startSwallow(0);\n  }', '''    try { if ((navigator.language || "").toLowerCase().indexOf("pt") !== 0) this.setState({ homeLang: "en" }); } catch (e) {}
    this.startSwallow(0);
  }''', "homeLang")
open(os.path.join(out, "NotFound.prod.dc.html"), "w").write(n)
print("ok")
