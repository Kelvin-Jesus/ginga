import React from "react";
/* Gerado de NotFound.dc.html (protótipo do editor de design) por tools/dc2jsx.py. */

export default class NotFound extends React.Component {
  constructor(props) { super(props); this.r = {}; this.refFns = {}; this.state = { done: false, anim: false }; }
  ref(name) { var self = this; if (!this.refFns[name]) this.refFns[name] = function (el) { self.r[name] = el; }; return this.refFns[name]; }
  componentDidMount() {
    if (this.r.sky) this.sky = this.pixelSky(this.r.sky);
    if (this.r.bh) { this.loop = this.ditherLoop(this.r.bh, this.blackHole()); this.loop.shade.pullT = 0.85; }
    try { if ((navigator.language || "").toLowerCase().indexOf("pt") !== 0) this.setState({ homeLang: "en" }); } catch (e) {}
    this.startSwallow(0);
  }
  /* espera a prancheta ter tamanho de verdade (no Play ela monta antes de aparecer) */
  startSwallow(tries) {
    var self = this, bh = this.r.bh, ok = bh && window.innerWidth > 200 && bh.getBoundingClientRect().height > 60;
    if (ok) { try { this.swallow(); } catch (e) { this.setState({ anim: false, done: true }); } return; }
    if (tries < 40) this._wait = setTimeout(function () { self.startSwallow(tries + 1); }, 100);
  }
  componentWillUnmount() { if (this.sky) this.sky.stop(); if (this.loop) this.loop.stop(); if (this.swRaf) cancelAnimationFrame(this.swRaf); clearTimeout(this._wait); clearTimeout(this._safety); }

  /* desenha uma "página do Ginga" num canvas fora da tela, para ser engolida */
  drawPage(W, H) {
    var c = document.createElement("canvas"); c.width = W; c.height = H;
    var g = c.getContext("2d"), hero = Math.round(H * 0.56), m = Math.max(20, Math.min(120, W * 0.09)), dark = true;
    try { dark = !window.matchMedia("(prefers-color-scheme: light)").matches; } catch (e) {}
    var BG = dark ? "#141830" : "#F2F3F8", CARD = dark ? "#171A33" : "#FFFFFF", INK = dark ? "#F2F3F8" : "#141830", LINE = dark ? "#2A2E4D" : "#DCDFEA", SOFT = dark ? "#252C66" : "#E3E7FE";
    g.fillStyle = BG; g.fillRect(0, 0, W, H);
    g.fillStyle = "#0A0C1C"; g.fillRect(0, 0, W, hero);
    for (var i = 0; i < W * hero / 2600; i++) { g.fillStyle = ["#2E47F5", "#6F82FF", "#F2F3F8", "#FFC43D"][i % 4]; g.fillRect((Math.random() * W / 4 | 0) * 4, (Math.random() * hero / 4 | 0) * 4, 2, 2); }
    g.fillStyle = "#F2F3F8"; g.font = "800 26px Unbounded, Figtree, sans-serif"; g.fillText("ginga", m, 50);
    g.fillStyle = "#6F82FF"; g.save(); g.translate(m + 30, 26); g.rotate(-0.2); g.fillRect(0, 0, 11, 8); g.restore();
    g.font = "500 15px Figtree, sans-serif"; g.fillStyle = "#C9CCE0";
    ["Recursos", "Segurança", "Comparar", "FAQ", "Baixar"].forEach(function (t, k) { if (m + 130 + k * 100 < W - 200) g.fillText(t, m + 130 + k * 100, 48); });
    var fs = Math.max(30, Math.min(64, W * 0.045));
    g.fillStyle = "#FFC43D"; g.font = "500 12px 'IBM Plex Mono', monospace"; g.fillText("✦ SEGUNDA TELA PARA MAC", m, hero * 0.34);
    g.fillStyle = "#F2F3F8"; g.font = "800 " + fs + "px Unbounded, Figtree, sans-serif";
    g.fillText("Seu Galaxy Tab", m, hero * 0.34 + fs * 1.3); g.fillText("vira tela do Mac.", m, hero * 0.34 + fs * 2.4);
    var by = hero * 0.34 + fs * 3.2;
    g.fillStyle = "#2E47F5"; this.rr(g, m, by, 190, 48, 24); g.fill();
    g.fillStyle = "#FFFFFF"; g.font = "600 15px Figtree, sans-serif"; g.fillText("Baixar para Mac", m + 34, by + 30);
    g.strokeStyle = "rgba(242,243,248,.35)"; g.lineWidth = 1.5; this.rr(g, m + 204, by, 210, 48, 24); g.stroke();
    g.fillStyle = "#F2F3F8"; g.fillText("Baixar para Android", m + 236, by + 30);
    /* cartões da seção de baixo */
    var cw = (W - m * 2 - 40) / 3, cy = hero + 70;
    g.fillStyle = INK; g.font = "600 " + Math.round(fs * 0.55) + "px Unbounded, Figtree, sans-serif"; g.fillText("Três jeitos de entrar em órbita", m, hero + 50);
    for (var k2 = 0; k2 < 3; k2++) {
      var x = m + k2 * (cw + 20);
      g.fillStyle = CARD; this.rr(g, x, cy, cw, H - cy - 30, 18); g.fill();
      g.fillStyle = SOFT; this.rr(g, x + 22, cy + 22, 42, 42, 12); g.fill();
      g.fillStyle = INK; g.font = "600 18px Figtree, sans-serif"; g.fillText(["Wi‑Fi", "Cabo USB", "Sem roteador"][k2], x + 22, cy + 94);
      g.fillStyle = LINE; for (var l = 0; l < 3; l++) { this.rr(g, x + 22, cy + 112 + l * 16, cw * (l === 2 ? 0.5 : 0.8), 7, 3); g.fill(); }
    }
    return c;
  }
  rr(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }

  /* a página racha em ladrilhos que orbitam (Kepler), são esticados (espaguetificação) e somem no horizonte */
  swallow() {
    var self = this, cv = this.r.pieces; if (!cv) return;
    if (this.swRaf) cancelAnimationFrame(this.swRaf);
    var rm = !!(window.Ginga && window.Ginga.reducedMotion);
    try { rm = rm || window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) {}
    this.setState({ done: false, anim: true });
    clearTimeout(this._safety); this._safety = setTimeout(function () { self.setState({ done: true }); }, 6000);
    var W = cv.width = window.innerWidth, H = cv.height = window.innerHeight, ctx = cv.getContext("2d");
    if (rm) { ctx.clearRect(0, 0, W, H); this.setState({ done: true }); return; }
    var page = this.drawPage(W, H);
    var bhr = this.r.bh.getBoundingClientRect(), hx = bhr.left + bhr.width / 2, hy = bhr.top + bhr.height * 0.52, R = Math.max(30, 0.28 * bhr.height / 2);
    var cols = W < 700 ? 8 : 14, rows = W < 700 ? 12 : 9, tw = W / cols, th = H / rows, T = [], maxD = 0;
    for (var y = 0; y < rows; y++) for (var x = 0; x < cols; x++) {
      var cx = x * tw + tw / 2, cy = y * th + th / 2, d = Math.hypot(cx - hx, cy - hy); maxD = Math.max(maxD, d);
      T.push({ sx: x * tw, sy: y * th, x: cx, y: cy, d: d, r: 0, th: 0, spin: (Math.random() - 0.5) * 6, delay: 0, on: false, gone: false, seed: Math.random() });
    }
    T.forEach(function (p) { p.delay = 0.55 + (p.d / maxD) * 1.7 + p.seed * 0.35; });
    if (this.loop) this.loop.shade.pullT = 1;
    var t0 = performance.now(), prev = t0, F = 0.42;
    var step = function (now) {
      var t = (now - t0) / 1000, dt = Math.min(0.05, (now - prev) / 1000); prev = now;
      ctx.clearRect(0, 0, W, H);
      var alive = 0, shake = t < 0.55 ? Math.sin(t * 60) * t * 3 : 0;
      for (var i = 0; i < T.length; i++) {
        var p = T[i]; if (p.gone) continue; alive++;
        if (!p.on && t > p.delay) { p.on = true; p.r = Math.hypot(p.x - hx, (p.y - hy) / F); p.th = Math.atan2((p.y - hy) / F, p.x - hx); p.x0 = p.x; p.y0 = p.y; p.b = 0; }
        if (!p.on) {
          /* rachando: treme cada vez mais conforme a sua vez chega */
          var near = Math.max(0, 1 - (p.delay - t) / 0.6), jx = (Math.random() - 0.5) * near * 3 + shake, jy = (Math.random() - 0.5) * near * 3;
          ctx.drawImage(page, p.sx, p.sy, tw, th, p.sx + jx, p.sy + jy, tw + 0.6, th + 0.6);
          continue;
        }
        p.th += Math.min(9, 1.6 * Math.pow(240 / Math.max(p.r, 1), 1.5)) * dt;
        p.r *= Math.exp(-(0.9 + 260 / Math.max(p.r, 30)) * dt * 0.55);
        p.b = Math.min(1, p.b + dt * 1.6);
        var e = p.b * p.b * (3 - 2 * p.b), ox = hx + p.r * Math.cos(p.th), oy = hy + p.r * Math.sin(p.th) * F;
        var X = p.x0 + (ox - p.x0) * e, Y = p.y0 + (oy - p.y0) * e;
        var st = 1 + Math.min(4, Math.pow(R * 2.2 / Math.max(p.r, R), 3) * 1.6), sc = Math.max(0.12, Math.min(1, p.r / (R * 4.5)) * (1 - e * 0.35));
        var ang = Math.atan2(hy - Y, hx - X);
        var behind = Math.sin(p.th) < 0 && Math.hypot(X - hx, Y - hy) < R;
        if (p.r < R * 1.02) { p.gone = true; continue; }
        if (behind) continue;
        ctx.save(); ctx.translate(X, Y); ctx.rotate(ang); ctx.scale(st, 1 / Math.sqrt(st)); ctx.rotate(-ang + p.spin * e);
        ctx.globalAlpha = Math.min(1, 0.35 + p.r / (R * 3));
        ctx.drawImage(page, p.sx, p.sy, tw, th, -tw * sc / 2, -th * sc / 2, tw * sc, th * sc);
        ctx.restore();
      }
      if (alive < T.length * 0.35 && !self.state.done) self.setState({ done: true });
      if (alive === 0) {
        ctx.clearRect(0, 0, W, H);
        if (self.loop) { self.loop.shade.pullT = 0.85; self.loop.shade.tb = self.loop.now(); }
        self.setState({ done: true }); self.swRaf = 0; return;
      }
      self.swRaf = requestAnimationFrame(step);
    };
    this.swRaf = requestAnimationFrame(step);
  }
  pixelSky(cv) {
      var PX = 4, ctx = cv.getContext("2d"), W = 0, H = 0, stars = [], shoot = null, raf = 0, last = 0, visible = true;
      var COL = ["#252C66", "#2E47F5", "#6F82FF", "#A4A9C8", "#F2F3F8", "#FFC43D"];
      var rm = !!(window.Ginga && window.Ginga.reducedMotion);
      var seed = function () {
        var r = cv.getBoundingClientRect(); W = Math.max(1, Math.ceil(r.width / PX)); H = Math.max(1, Math.ceil(r.height / PX));
        cv.width = W; cv.height = H; stars = [];
        var n = Math.round(W * H * 0.0048);
        for (var i = 0; i < n; i++) {
          var k = Math.random(), c = k < 0.5 ? 0 : k < 0.74 ? 1 : k < 0.88 ? 2 : k < 0.95 ? 3 : k < 0.99 ? 4 : 5;
          stars.push({ x: (Math.random() * W) | 0, y: (Math.random() * H) | 0, c: c, p: Math.random() * 6.28, s: 0.5 + Math.random() * 2, big: c >= 4 && Math.random() < 0.25 });
        }
        draw(0);
      };
      var draw = function (t) {
        ctx.clearRect(0, 0, W, H);
        for (var i = 0; i < stars.length; i++) {
          var st = stars[i], tw = Math.sin(st.p + t * st.s), c = st.c + (tw > 0.75 ? 1 : tw < -0.6 ? -1 : 0);
          if (c < 0) continue; if (c > 5) c = 5;
          ctx.fillStyle = COL[c]; ctx.fillRect(st.x, st.y, 1, 1);
          if (st.big && tw > 0.2) { ctx.fillStyle = COL[Math.max(0, c - 2)]; ctx.fillRect(st.x - 1, st.y, 1, 1); ctx.fillRect(st.x + 1, st.y, 1, 1); ctx.fillRect(st.x, st.y - 1, 1, 1); ctx.fillRect(st.x, st.y + 1, 1, 1); }
        }
        if (shoot) {
          var e = t - shoot.t0, len = 14;
          if (e > 1.1) shoot = null; else {
            var hx = shoot.x + e * shoot.vx, hy = shoot.y + e * shoot.vy;
            for (var j = 0; j < len; j++) { ctx.fillStyle = COL[j < 2 ? 5 : j < 5 ? 4 : j < 9 ? 2 : 1]; ctx.fillRect(Math.round(hx - j * shoot.vx / 60), Math.round(hy - j * shoot.vy / 60), 1, 1); }
          }
        } else if (Math.random() < 0.004) {
          shoot = { t0: t, x: Math.random() * W * 0.7, y: Math.random() * H * 0.35, vx: 90 + Math.random() * 60, vy: 30 + Math.random() * 30 };
        }
      };
      var t0 = performance.now();
      var loop = function (now) { raf = 0; if (!visible || document.hidden) return; if (now - last > 90) { last = now; draw((now - t0) / 1000); } raf = requestAnimationFrame(loop); };
      seed();
      var ro = window.ResizeObserver ? new ResizeObserver(seed) : null; if (ro) ro.observe(cv);
      if (!rm) {
        raf = requestAnimationFrame(loop);
        if (window.IntersectionObserver) new IntersectionObserver(function (en) { visible = en[0].isIntersecting; if (visible && !raf) raf = requestAnimationFrame(loop); }).observe(cv);
        document.addEventListener("visibilitychange", function () { if (!document.hidden && !raf) raf = requestAnimationFrame(loop); });
      }
      return { stop: function () { if (raf) cancelAnimationFrame(raf); raf = 0; visible = false; if (ro) ro.disconnect(); } };
    }
  
    /* dithering (Bayer 4×4) sobre a paleta da marca ---------- */
  
  ditherLoop(cv, shade) {
      var ctx = cv.getContext("2d"), W = cv.width, H = cv.height, img = ctx.createImageData(W, H), d = img.data;
      var PAL = [[10,12,28],[20,24,48],[46,71,245],[111,130,255],[242,243,248],[255,196,61]], N = PAL.length - 1;
      var B = [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5];
      var geo = shade.init(W, H), buf = new Float32Array(W * H), raf = 0, visible = true, last = 0, t0 = performance.now();
      var rm = window.Ginga && (window.Ginga && window.Ginga.reducedMotion);
      var draw = function (t) {
        for (var j = 0; j < buf.length; j++) buf[j] = shade.at(geo, j, t);
        if (shade.splat) shade.splat(buf, W, H, t);
        for (var y = 0, i = 0; y < H; y++) for (var x = 0; x < W; x++, i++) {
          var v = buf[i], th = (B[(y & 3) * 4 + (x & 3)] + 0.5) / 16;
          var lv = Math.floor(v * N + th); lv = lv < 0 ? 0 : lv > N ? N : lv;
          var c = PAL[lv], o = i * 4; d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = lv === 0 ? 0 : 255;
        }
        ctx.putImageData(img, 0, 0);
      };
      var loop = function (now) {
        raf = 0; if (!visible || document.hidden) return;
        if (now - last > 42) { last = now; draw((now - t0) / 1000); }
        raf = requestAnimationFrame(loop);
      };
      draw(0);
      if (!rm) {
        raf = requestAnimationFrame(loop);
        if (window.IntersectionObserver) new IntersectionObserver(function (e) { visible = e[0].isIntersecting; if (visible && !raf) raf = requestAnimationFrame(loop); }).observe(cv);
        document.addEventListener("visibilitychange", function () { if (!document.hidden && !raf) raf = requestAnimationFrame(loop); });
      }
      return { shade: shade, now: function () { return (performance.now() - t0) / 1000; }, stop: function () { if (raf) cancelAnimationFrame(raf); raf = 0; visible = false; } };
    }
  
  blackHole() {
      /* Buraco negro em dithering: gás espiralando para dentro (disco inclinado com efeito Doppler),
         anel de fótons, arco lenteado por cima, estrelas de fundo deformadas pela lente
         e ~700 partículas em órbita kepleriana que colapsam com o mouse e explodem no clique. */
      var R = 0.28, K = 0.2, rIn = 0.42, rOut = 1.6;
      var hash = function (a, b) { var x = Math.sin(a * 127.1 + b * 311.7) * 43758.5453; return x - Math.floor(x); };
      var shade = {
        pull: 0, pullT: 0, tb: -99, cx: 0, cy: 0, W: 0, H: 0,
        init: function (W, H) {
          var n = W * H, g = { x: new Float32Array(n), y: new Float32Array(n), rd: new Float32Array(n), lrd: new Float32Array(n), ang: new Float32Array(n), rs: new Float32Array(n), st: new Float32Array(n) };
          shade.W = W; shade.H = H; shade.cx = W * 0.5; shade.cy = H * 0.52;
          for (var yy = 0, i = 0; yy < H; yy++) for (var xx = 0; xx < W; xx++, i++) {
            var x = (xx - shade.cx) / (H / 2), y = (yy - shade.cy) / (H / 2), v = y / K, rs = Math.sqrt(x * x + y * y);
            g.x[i] = x; g.y[i] = y; g.rd[i] = Math.sqrt(x * x + v * v); g.lrd[i] = Math.log(g.rd[i] + 0.001); g.ang[i] = Math.atan2(v, x); g.rs[i] = rs;
            /* lente: a estrela vista aqui vem de um ponto empurrado para fora (Einstein) */
            var k = rs > R ? 1 + 0.09 / (rs * rs) : 0, sx = x * k, sy = y * k;
            var h = hash(Math.floor(sx * 60), Math.floor(sy * 60));
            g.st[i] = rs > R * 1.1 && rs < 1.05 && h > 0.985 ? 0.28 + (h - 0.985) * 40 : 0;
          }
          var P = [], NP = Math.min(700, Math.round(W * H * 0.03));
          for (var p = 0; p < NP; p++) {
            var r0 = rIn * 0.9 + Math.pow(Math.random(), 0.8) * (rOut * 1.25 - rIn);
            P.push({ r: r0, a: Math.random() * 6.2832, w: 0.9 / Math.pow(r0, 1.5), b: 0.35 + Math.random() * 0.55, z: (Math.random() - 0.5) * 0.05 });
          }
          g.P = P;
          return g;
        },
        at: function (g, i, t) {
          var x = g.x[i], y = g.y[i], rd = g.rd[i], a = g.ang[i], rs = g.rs[i];
          var dop = 0.5 - 0.5 * Math.cos(a);
          var D = 0;
          if (rd > rIn && rd < rOut) {
            var f = 1 - (rd - rIn) / (rOut - rIn);
            /* espirais que puxam o gás para dentro */
            var sw = 0.5 + 0.5 * Math.sin(a * 3 + g.lrd[i] * 7 + t * 2.2);
            var sw2 = 0.5 + 0.5 * Math.sin(a * 7 - g.lrd[i] * 11 + t * 3.1);
            D = Math.pow(f, 1.05) * (0.35 + 0.75 * dop) * (0.45 + 0.4 * sw + 0.2 * sw2) * Math.min(1, (rd - rIn) / 0.06);
          }
          var L = 0, dr = Math.abs(rs - 0.47);
          if (dr < 0.17 && y < 0.05) {
            var la = Math.atan2(y, x);
            L = Math.pow(1 - dr / 0.17, 1.4) * (0.55 + 0.45 * (0.5 - 0.5 * Math.cos(la))) * (0.7 + 0.3 * Math.sin(la * 5 + t * 2.4 + rs * 20));
          }
          var Pr = Math.max(0, 1 - Math.abs(rs - R * 1.04) / 0.02);
          if (rs < R) return (y > 0 && D > 0) ? D : 0;
          var halo = 0.18 * Math.exp(-(rs - R) / 0.14) * (1 + 0.6 * shade.pull);
          var back = Math.min(1, Math.max(0, (rs - 0.5) / 0.3)); back = back * back * (3 - 2 * back);
          var v = Math.max(y > 0 ? D : Math.max(D * back, L), Pr * (0.85 + 0.15 * Math.sin(t * 3)), halo);
          v += g.st[i] * (0.65 + 0.35 * Math.sin(t * 1.7 + i));
          return v > 1 ? 1 : v;
        },
        splat: function (buf, W, H, t) {
          var g = shade.g; if (!g) return;
          shade.pull += (shade.pullT - shade.pull) * 0.08;
          var e = t - shade.tb, burst = e > 0 && e < 2.2 ? Math.sin(Math.PI * Math.min(1, e / 2.2)) * Math.exp(-e * 0.6) : 0;
          var S = H / 2, dt = 0.042;
          for (var p = 0; p < g.P.length; p++) {
            var q = g.P[p];
            q.a += q.w * dt * (1 + 1.4 * shade.pull);
            var r = q.r * (1 - 0.38 * shade.pull) * (1 + 1.6 * burst * (0.6 + q.b));
            for (var k = 0; k < 3; k++) {
              var aa = q.a - k * 0.05 * (1 + shade.pull), x = r * Math.cos(aa), y = r * Math.sin(aa) * K + q.z;
              var rs = Math.sqrt(x * x + y * y);
              if (rs < R && Math.sin(aa) < 0) continue;
              var px = Math.round(shade.cx + x * S), py = Math.round(shade.cy + y * S);
              if (px < 0 || py < 0 || px >= W || py >= H) continue;
              var o = py * W + px, add = q.b * (k === 0 ? 0.75 : 0.32 / k) * (0.6 + 0.6 * (0.5 - 0.5 * Math.cos(aa)));
              buf[o] = Math.min(1, buf[o] + add);
            }
          }
        }
      };
      var init = shade.init;
      shade.init = function (W, H) { var g = init(W, H); shade.g = g; return g; };
      return shade;
    }
  
  galaxy(o) {
      o = o || {}; var CX = o.cx == null ? 0.5 : o.cx, CY = o.cy == null ? 0.5 : o.cy, SC = o.s || 1, SPIN = o.spin == null ? 0.35 : o.spin;
      return {
        init: function (W, H) {
          var n = W * H, g = { r: new Float32Array(n), th: new Float32Array(n) }, U = Math.min(W, H) / 2 * SC;
          for (var yy = 0, i = 0; yy < H; yy++) for (var xx = 0; xx < W; xx++, i++) {
            var x = (xx - W * CX) / U, y = (yy - H * CY) / U;
            var c = Math.cos(-0.5), s = Math.sin(-0.5), u = x * c - y * s, w = (x * s + y * c) / 0.62;
            g.r[i] = Math.sqrt(u * u + w * w); g.th[i] = Math.atan2(w, u);
          }
          return g;
        },
        at: function (g, i, t) {
          var r = g.r[i]; if (r > 1.05) return 0;
          var arms = Math.pow(0.5 + 0.5 * Math.cos(2 * g.th[i] - 5.2 * Math.log(r + 0.06) - t * SPIN), 3);
          var edge = Math.min(1, (1.05 - r) / 0.35);
          var v = (Math.exp(-r * 2.4) * (0.25 + 1.1 * arms)) * edge + 1.15 * Math.exp(-r * r * 60);
          return v > 1 ? 1 : v;
        }
      };
    }
  /* 404 → home: o buraco negro devolve a página. Os ladrilhos saem do horizonte em espiral e se
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
      goHomeEn: function (e) { e.preventDefault(); self.goTo(base + "en/"); }, refSky: this.ref("sky"), refBh: this.ref("bh"), refPieces: this.ref("pieces"), showCls: !this.state || !this.state.anim || this.state.done ? "show" : "", replay: function () { self.startSwallow(0); } }; }

  render() {
    const v = this.renderVals();
    const A = this.props.base + "assets/";
    return (<>{" "}<main className={"p404"}>{" "}<canvas className={"sky"} ref={v.refSky} aria-hidden={"true"}></canvas>{" "}<canvas className={"bh"} ref={v.refBh} width={"285"} height={"182"} aria-hidden={"true"}></canvas>{" "}<canvas className={"pieces"} ref={v.refPieces} aria-hidden={"true"}></canvas>{" "}<img className={`astro404 ${v.showCls}`} src={A + "ginga-astronaut.svg"} alt={""} />{" "}<div className={`txt ${v.showCls} ${v.leaveCls}`}>{" "}<div className={"code"}>{"404"}</div>{" "}<h1 className={"msg"}>{"Essa p\u00e1gina caiu num buraco negro."}</h1>{" "}<p className={"msg2"}>{"Nem a luz voltou de l\u00e1."}</p>{" "}<p className={"msg2"} lang={"en"} style={{"fontStyle": "italic"}}>{"This page fell into a black hole. Not even light made it back."}</p>{" "}<a className={"back"} href={v.homeHref} onClick={v.goHome}>{"Voltar para a \u00f3rbita"}</a><button className={"replay"} onClick={v.replay}>{"Ver de novo"}</button>{" "}<div className={"small"}><a href={v.homeHrefEn} onClick={v.goHomeEn} style={{"color": "#A4A9C8"}}>{"Back to orbit"}</a>{" \u00b7 ginga \u00b7 404"}</div>{" "}</div>{" "}</main>{" "}</>);
  }
}
